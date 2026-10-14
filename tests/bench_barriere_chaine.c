/* Banc de recouvrement : chaine de N passes ping-pong (sommet lourd, fragment lourd
 * qui lit la cible de la passe precedente). Barriere de lecture COLOR_OUTPUT ->
 * <dst> (f = FRAGMENT_SHADER, comme RENDER_TARGET -> PIXEL_SHADER_RESOURCE de
 * vkd3d-proton ; vf = VERTEX|FRAGMENT). Mesure le temps GPU median selon
 * CIDRE_NARROW_BARRIERS.
 * usage : bench_barriere_chaine <f|vf> [N=40] [V=30000] [itv=32] [itf=32] [reps=7] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec*1e-9;}
#define CK(x) do{VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__);exit(1);} }while(0)
static VkDevice dev; static VkPhysicalDevice pd;
static uint32_t mtype(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties m; vkGetPhysicalDeviceMemoryProperties(pd,&m);
   for(uint32_t i=0;i<m.memoryTypeCount;++i) if((bits&(1u<<i))&&(m.memoryTypes[i].propertyFlags&p)==p) return i;
   return UINT32_MAX; }
static VkShaderModule mod(const char *p){
   FILE*f=fopen(p,"rb"); if(!f){printf("pas de %s\n",p);exit(1);}
   fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET);
   uint32_t*c=malloc(n); if(fread(c,1,n,f)!=(size_t)n){printf("lecture\n");exit(1);} fclose(f);
   VkShaderModuleCreateInfo i={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=n,.pCode=c};
   VkShaderModule s; CK(vkCreateShaderModule(dev,&i,NULL,&s)); return s; }
static void img(VkFormat fm,uint32_t w,uint32_t h,VkImageUsageFlags u,VkImage*im,VkDeviceMemory*me,VkImageView*vi){
   VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,.format=fm,
      .extent={w,h,1},.mipLevels=1,.arrayLayers=1,.samples=VK_SAMPLE_COUNT_1_BIT,
      .tiling=VK_IMAGE_TILING_OPTIMAL,.usage=u,.sharingMode=VK_SHARING_MODE_EXCLUSIVE,
      .initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
   CK(vkCreateImage(dev,&ci,NULL,im));
   VkMemoryRequirements rq; vkGetImageMemoryRequirements(dev,*im,&rq);
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=rq.size,
      .memoryTypeIndex=mtype(rq.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&ai,NULL,me)); CK(vkBindImageMemory(dev,*im,*me,0));
   VkImageViewCreateInfo vc={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=*im,
      .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=fm,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   CK(vkCreateImageView(dev,&vc,NULL,vi)); }
static VkPipeline pipeline(VkPipelineLayout lay,const char*vs,const char*fs,VkPrimitiveTopology topo,uint32_t w,uint32_t h){
   VkFormat fmt=VK_FORMAT_R16G16B16A16_SFLOAT;
   VkPipelineRenderingCreateInfo rci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount=1,.pColorAttachmentFormats=&fmt};
   VkPipelineShaderStageCreateInfo st[2]={
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=mod(vs),.pName="main"},
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=mod(fs),.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,.topology=topo};
   VkViewport vp={0,0,(float)w,(float)h,0,1}; VkRect2D sr={{0,0},{w,h}};
   VkPipelineViewportStateCreateInfo vs2={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,.viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sr};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,.polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.lineWidth=1.f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,.attachmentCount=1,.pAttachments=&cba};
   VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&rci,
      .stageCount=2,.pStages=st,.pVertexInputState=&vi,.pInputAssemblyState=&ia,.pViewportState=&vs2,
      .pRasterizationState=&rs,.pMultisampleState=&ms,.pColorBlendState=&cb,.layout=lay};
   VkPipeline p; CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&p)); return p; }
static int cmpd(const void*a,const void*b){double x=*(const double*)a,y=*(const double*)b;return x<y?-1:x>y;}
int main(int argc,char**argv){
   const char*dst=argc>1?argv[1]:"f";
   uint32_t N=argc>2?atoi(argv[2]):40, V=argc>3?atoi(argv[3]):30000, itv=argc>4?atoi(argv[4]):32, itf=argc>5?atoi(argv[5]):32;
   int reps=argc>6?atoi(argv[6]):7;
   const char*dir=getenv("BANC_SPV")?getenv("BANC_SPV"):".";
   VkPipelineStageFlags2 dstm=!strcmp(dst,"vf")?(VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT|VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT):VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
   const uint32_t W=1920,H=1080;
   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in));
   uint32_t n=1; vkEnumeratePhysicalDevices(in,&n,&pd);
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&pr};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.dynamicRendering=VK_TRUE,.synchronization2=VK_TRUE};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&v13};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&f2,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};
   CK(vkCreateDevice(pd,&dc,NULL,&dev));
   VkQueue queue; vkGetDeviceQueue(dev,0,0,&queue);
   VkImage ri[2]; VkDeviceMemory rm[2]; VkImageView rv[2];
   for(int i=0;i<2;i++) img(VK_FORMAT_R16G16B16A16_SFLOAT,W,H,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_SAMPLED_BIT,&ri[i],&rm[i],&rv[i]);
   VkSamplerCreateInfo sc={.sType=VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,.magFilter=VK_FILTER_NEAREST,.minFilter=VK_FILTER_NEAREST};
   VkSampler smp; CK(vkCreateSampler(dev,&sc,NULL,&smp));
   VkDescriptorSetLayoutBinding b={0,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_FRAGMENT_BIT};
   VkDescriptorSetLayoutCreateInfo dl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dl,NULL,&dsl));
   VkPushConstantRange pc={VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,12};
   VkPipelineLayoutCreateInfo pl={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pc};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev,&pl,NULL,&lay));
   char p1[512],p2[512]; snprintf(p1,sizeof p1,"%s/ch_lourd.vert.spv",dir); snprintf(p2,sizeof p2,"%s/ch_lourd.frag.spv",dir);
   VkPipeline pp=pipeline(lay,p1,p2,VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,W,H);
   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,2};
   VkDescriptorPoolCreateInfo dp={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=2,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool pool2; CK(vkCreateDescriptorPool(dev,&dp,NULL,&pool2));
   VkDescriptorSetLayout dsls[2]={dsl,dsl};
   VkDescriptorSetAllocateInfo da={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=pool2,.descriptorSetCount=2,.pSetLayouts=dsls};
   VkDescriptorSet ds[2]; CK(vkAllocateDescriptorSets(dev,&da,ds));
   for(int i=0;i<2;i++){ VkDescriptorImageInfo di={smp,rv[i],VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
      VkWriteDescriptorSet wd={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds[i],.dstBinding=0,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&di};
      vkUpdateDescriptorSets(dev,1,&wd,0,NULL); }
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=0};
   VkCommandPool cp; CK(vkCreateCommandPool(dev,&cpi,NULL,&cp));
   VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cp,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev,&ca,&cmd));
   VkQueryPoolCreateInfo qpi={.sType=VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,.queryType=VK_QUERY_TYPE_TIMESTAMP,.queryCount=2};
   VkQueryPool qpool; CK(vkCreateQueryPool(dev,&qpi,NULL,&qpool));
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd,&props);
   double *ms=calloc(reps,sizeof(double));
   VkRect2D rr={{0,0},{W,H}};
   for(int rep=0;rep<reps;++rep){
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cmd,&bi));
      vkCmdResetQueryPool(cmd,qpool,0,2);
      VkImageMemoryBarrier2 b0[2];
      for(int i=0;i<2;i++) b0[i]=(VkImageMemoryBarrier2){.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
         .dstStageMask=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,.dstAccessMask=VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,
         .newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.image=ri[i],.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      VkDependencyInfo d0={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=2,.pImageMemoryBarriers=b0};
      vkCmdPipelineBarrier2(cmd,&d0);
      vkCmdWriteTimestamp2(cmd,VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,qpool,0);
      for(uint32_t k=0;k<N;++k){
         uint32_t w=k%2, r=1-w;
         VkImageMemoryBarrier2 bw={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
            .dstStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.dstAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=ri[w],.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
         VkDependencyInfo dw={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&bw};
         vkCmdPipelineBarrier2(cmd,&dw);
         VkRenderingAttachmentInfo at={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=rv[w],.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE,.storeOp=VK_ATTACHMENT_STORE_OP_STORE};
         VkRenderingInfo ri2={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=rr,.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&at};
         vkCmdBeginRendering(cmd,&ri2);
         vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pp);
         vkCmdBindDescriptorSets(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,lay,0,1,&ds[r],0,NULL);
         uint32_t push[3]={k,itv,itf};
         vkCmdPushConstants(cmd,lay,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,12,push);
         vkCmdDraw(cmd,V,1,0,0);
         vkCmdEndRendering(cmd);
         VkImageMemoryBarrier2 brd={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,.dstStageMask=dstm,.dstAccessMask=VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
            .oldLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.image=ri[w],.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
         VkDependencyInfo drd={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&brd};
         vkCmdPipelineBarrier2(cmd,&drd);
      }
      vkCmdWriteTimestamp2(cmd,VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,qpool,1);
      CK(vkEndCommandBuffer(cmd));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cmd};
      double t0=now(); CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue)); double tw=(now()-t0)*1e3;
      uint64_t ts[2]={0,0};
      vkGetQueryPoolResults(dev,qpool,0,2,sizeof(ts),ts,sizeof(uint64_t),VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WAIT_BIT);
      ms[rep]=tw; (void)ts;
   }
   qsort(ms,reps,sizeof(double),cmpd);
   const char*mode=getenv("CIDRE_NARROW_BARRIERS");
   printf("CHAINE dst=%s mode=%s N=%u V=%u itv=%u itf=%u : mur med=%.2f ms (min %.2f max %.2f)\n",dst,mode?mode:"ALL",N,V,itv,itf,ms[reps/2],ms[0],ms[reps-1]);
   return 0;
}
