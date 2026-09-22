/* Meme banc de rejet precoce que tests/bench_depth_metal.m, via KosmicKrisp. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
#define CK(x) do{VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__);exit(1);} }while(0)
#define W 1920u
#define H 1080u
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec*1e-9;}
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
int main(int argc,char**argv){
   uint32_t ech=argc>1?(uint32_t)atoi(argv[1]):128u;
   uint32_t couches=argc>2?(uint32_t)atoi(argv[2]):8u;
   int reps=argc>3?atoi(argv[3]):6;
   const char*vs=argc>4?argv[4]:"build/bench_depth_vs.spv";
   const char*fs=argc>5?argv[5]:"build/bench_depth_fs.spv";
   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in));
   uint32_t n=1; vkEnumeratePhysicalDevices(in,&n,&pd);
   uint32_t nq=0; vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,NULL);
   VkQueueFamilyProperties*qp=malloc(nq*sizeof(*qp)); vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,qp);
   uint32_t qf=0; for(uint32_t i=0;i<nq;++i) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qf=i;break;}
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qf,.queueCount=1,.pQueuePriorities=&pr};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.dynamicRendering=VK_TRUE};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&v13};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&f2,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&qc};
   CK(vkCreateDevice(pd,&dc,NULL,&dev));
   VkQueue queue; vkGetDeviceQueue(dev,qf,0,&queue);

   VkImage src_i,rt_i,dep_i; VkDeviceMemory src_m,rt_m,dep_m; VkImageView src_v,rt_v,dep_v;
   img(VK_FORMAT_R8G8B8A8_UNORM,2048,2048,VK_IMAGE_USAGE_SAMPLED_BIT,&src_i,&src_m,&src_v);
   img(VK_FORMAT_R16G16B16A16_SFLOAT,W,H,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,&rt_i,&rt_m,&rt_v);
   {
      VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
         .format=VK_FORMAT_D32_SFLOAT,.extent={W,H,1},.mipLevels=1,.arrayLayers=1,
         .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
         .usage=VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,.sharingMode=VK_SHARING_MODE_EXCLUSIVE,
         .initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
      CK(vkCreateImage(dev,&ci,NULL,&dep_i));
      VkMemoryRequirements rq; vkGetImageMemoryRequirements(dev,dep_i,&rq);
      VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=rq.size,
         .memoryTypeIndex=mtype(rq.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
      CK(vkAllocateMemory(dev,&ai,NULL,&dep_m)); CK(vkBindImageMemory(dev,dep_i,dep_m,0));
      VkImageViewCreateInfo vc={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=dep_i,
         .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=VK_FORMAT_D32_SFLOAT,
         .subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1}};
      CK(vkCreateImageView(dev,&vc,NULL,&dep_v));
   }
   VkSamplerCreateInfo sc={.sType=VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,.magFilter=VK_FILTER_LINEAR,
      .minFilter=VK_FILTER_LINEAR,.addressModeU=VK_SAMPLER_ADDRESS_MODE_REPEAT,
      .addressModeV=VK_SAMPLER_ADDRESS_MODE_REPEAT,.addressModeW=VK_SAMPLER_ADDRESS_MODE_REPEAT};
   VkSampler smp; CK(vkCreateSampler(dev,&sc,NULL,&smp));
   VkDescriptorSetLayoutBinding b={0,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_FRAGMENT_BIT};
   VkDescriptorSetLayoutCreateInfo dl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dl,NULL,&dsl));
   VkPushConstantRange pc={VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,8};
   VkPipelineLayoutCreateInfo pl={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,
      .pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pc};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev,&pl,NULL,&lay));
   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1};
   VkDescriptorPoolCreateInfo dpi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpi,NULL,&dp));
   VkDescriptorSetAllocateInfo dsa={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=dp,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsa,&ds));
   VkDescriptorImageInfo di={smp,src_v,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkWriteDescriptorSet wd={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&di};
   vkUpdateDescriptorSets(dev,1,&wd,0,NULL);

   VkFormat cfmt=VK_FORMAT_R16G16B16A16_SFLOAT;
   VkPipelineRenderingCreateInfo rci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount=1,.pColorAttachmentFormats=&cfmt,.depthAttachmentFormat=VK_FORMAT_D32_SFLOAT};
   VkPipelineShaderStageCreateInfo st[2]={
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=mod(vs),.pName="main"},
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=mod(fs),.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
   VkViewport vp={0,0,(float)W,(float)H,0,1}; VkRect2D sr={{0,0},{W,H}};
   VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,.viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sr};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE,.lineWidth=1.f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineDepthStencilStateCreateInfo dss={.sType=VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
      .depthTestEnable=VK_TRUE,.depthWriteEnable=VK_TRUE,.depthCompareOp=VK_COMPARE_OP_LESS};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,.attachmentCount=1,.pAttachments=&cba};
   VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&rci,
      .stageCount=2,.pStages=st,.pVertexInputState=&vi,.pInputAssemblyState=&ia,.pViewportState=&vps,
      .pRasterizationState=&rs,.pMultisampleState=&ms,.pDepthStencilState=&dss,.pColorBlendState=&cb,.layout=lay};
   VkPipeline pipe; CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipe));

   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qf};
   VkCommandPool cp; CK(vkCreateCommandPool(dev,&cpi,NULL,&cp));
   VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cp,
      .level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev,&ca,&cmd));

   double best=1e9;
   for(int rep=0;rep<reps;++rep){
      double t0=now();
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cmd,&bi));
      VkImageMemoryBarrier2 bar[3]={
        {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
         .dstStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.dstAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=rt_i,
         .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}},
        {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
         .dstStageMask=VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,.dstAccessMask=VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,.image=dep_i,
         .subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1}},
        {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
         .dstStageMask=VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,.dstAccessMask=VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.image=src_i,
         .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}}};
      VkDependencyInfo dep={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=3,.pImageMemoryBarriers=bar};
      vkCmdPipelineBarrier2(cmd,&dep);
      VkRenderingAttachmentInfo at={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=rt_v,.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE};
      VkRenderingAttachmentInfo dat={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=dep_v,.imageLayout=VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE,
         .clearValue={.depthStencil={1.0f,0}}};
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=sr,.layerCount=1,
         .colorAttachmentCount=1,.pColorAttachments=&at,.pDepthAttachment=&dat};
      vkCmdBeginRendering(cmd,&ri);
      vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
      vkCmdBindDescriptorSets(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,lay,0,1,&ds,0,NULL);
      for(uint32_t c=0;c<couches;++c){
         struct { float z; uint32_t n; } pcv = { 0.1f + 0.8f*(float)c/256.0f, ech };
         vkCmdPushConstants(cmd,lay,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,8,&pcv);
         vkCmdDraw(cmd,3,1,0,0);
      }
      vkCmdEndRendering(cmd);
      CK(vkEndCommandBuffer(cmd));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cmd};
      CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue));
      double dt=now()-t0;
      if(dt>0.0 && dt<best) best=dt;
   }
   printf("notre-pile   ech/pixel=%u couches=%u  meilleur=%.2f ms  (%.3f ms/couche)\n",
          ech,couches,best*1e3,best*1e3/couches);
   return 0;
}
