/* Banc des barrieres de cloture de KosmicKrisp : une donnee ECRITE au fragment
 * d'une passe, LUE au sommet de la passe suivante.
 *
 * Pour k = 1..K, dans un seul tampon de commandes :
 *   passe A_k : rend la texture T (grande, fragment lourd) avec la valeur k ;
 *   barriere  : COLOR_ATTACHMENT_OUTPUT -> <dst choisi>, T -> SHADER_READ_ONLY ;
 *   passe B_k : un point dont le SOMMET lit T au centre et ecrit la valeur lue dans
 *               le pixel k de la cible C (K x 1) ;
 *   barriere  : <dst choisi> -> COLOR_ATTACHMENT_OUTPUT, T -> COLOR_ATTACHMENT.
 * Relu a la fin : C[k] doit valoir k. Un C[k] different = le sommet de B_k a lu T
 * avant la fin du fragment de A_k : la barriere a ete relachee a tort.
 *
 * usage : bench_barriere_vertex <dst: v|vf|all> [K=200] [iter_frag=64] [taille_T=2048] [repetitions=5]
 * Le mode des barrieres se choisit par CIDRE_NARROW_BARRIERS (absent, 1, global).
 * Imprime : fautes (C[k] != k) par repetition et temps GPU median. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
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
   VkFormat fmt=VK_FORMAT_R32_SFLOAT;
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
   const char*dst=argc>1?argv[1]:"vf";
   uint32_t K=argc>2?(uint32_t)atoi(argv[2]):200u;
   uint32_t iter=argc>3?(uint32_t)atoi(argv[3]):64u;
   uint32_t TS=argc>4?(uint32_t)atoi(argv[4]):2048u;
   int reps=argc>5?atoi(argv[5]):5;
   const char*dir=getenv("BANC_SPV")?getenv("BANC_SPV"):".";
   VkPipelineStageFlags2 dstm;
   if(!strcmp(dst,"v")) dstm=VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT;
   else if(!strcmp(dst,"vf")) dstm=VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT|VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
   else dstm=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;

   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in));
   uint32_t n=1; vkEnumeratePhysicalDevices(in,&n,&pd);
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&pr};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      .dynamicRendering=VK_TRUE,.synchronization2=VK_TRUE};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&v13};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&f2,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&qc};
   CK(vkCreateDevice(pd,&dc,NULL,&dev));
   VkQueue queue; vkGetDeviceQueue(dev,0,0,&queue);

   VkImage ti,ci; VkDeviceMemory tm,cm; VkImageView tv,cv;
   img(VK_FORMAT_R32_SFLOAT,TS,TS,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_SAMPLED_BIT,&ti,&tm,&tv);
   img(VK_FORMAT_R32_SFLOAT,K,1,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT,&ci,&cm,&cv);
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=K*4,.usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   VkBuffer rb; CK(vkCreateBuffer(dev,&bci,NULL,&rb));
   VkMemoryRequirements rq; vkGetBufferMemoryRequirements(dev,rb,&rq);
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=rq.size,
      .memoryTypeIndex=mtype(rq.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory rm; CK(vkAllocateMemory(dev,&ai,NULL,&rm)); CK(vkBindBufferMemory(dev,rb,rm,0));
   float*lu; CK(vkMapMemory(dev,rm,0,K*4,0,(void**)&lu));

   VkSamplerCreateInfo sc={.sType=VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,.magFilter=VK_FILTER_NEAREST,
      .minFilter=VK_FILTER_NEAREST,.addressModeU=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeV=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,.addressModeW=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE};
   VkSampler smp; CK(vkCreateSampler(dev,&sc,NULL,&smp));
   VkDescriptorSetLayoutBinding b={0,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_VERTEX_BIT};
   VkDescriptorSetLayoutCreateInfo dl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dl,NULL,&dsl));
   VkPushConstantRange pc={VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,12};
   VkPipelineLayoutCreateInfo pl={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,
      .pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pc};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev,&pl,NULL,&lay));
   char p1[512],p2[512],p3[512],p4[512];
   snprintf(p1,sizeof p1,"%s/bv_plein.vert.spv",dir); snprintf(p2,sizeof p2,"%s/bv_lourd.frag.spv",dir);
   snprintf(p3,sizeof p3,"%s/bv_lit.vert.spv",dir);   snprintf(p4,sizeof p4,"%s/bv_ecrit.frag.spv",dir);
   VkPipeline pa=pipeline(lay,p1,p2,VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,TS,TS);
   VkPipeline pb=pipeline(lay,p3,p4,VK_PRIMITIVE_TOPOLOGY_POINT_LIST,K,1);

   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1};
   VkDescriptorPoolCreateInfo dp={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool pool2; CK(vkCreateDescriptorPool(dev,&dp,NULL,&pool2));
   VkDescriptorSetAllocateInfo da={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=pool2,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&da,&ds));
   VkDescriptorImageInfo di={smp,tv,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkWriteDescriptorSet wd={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&di};
   vkUpdateDescriptorSets(dev,1,&wd,0,NULL);

   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=0};
   VkCommandPool cp; CK(vkCreateCommandPool(dev,&cpi,NULL,&cp));
   VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cp,
      .level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev,&ca,&cmd));
   VkQueryPoolCreateInfo qpi={.sType=VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,.queryType=VK_QUERY_TYPE_TIMESTAMP,.queryCount=2};
   VkQueryPool qpool; CK(vkCreateQueryPool(dev,&qpi,NULL,&qpool));
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd,&props);
   double periode=props.limits.timestampPeriod;

   VkRect2D rT={{0,0},{TS,TS}}, rC={{0,0},{K,1}};
   double *ms=calloc(reps,sizeof(double)); int fautes_tot=0;
   for(int rep=0;rep<reps;++rep){
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cmd,&bi));
      vkCmdResetQueryPool(cmd,qpool,0,2);
      vkCmdWriteTimestamp2(cmd,VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,qpool,0);
      VkImageMemoryBarrier2 b0[2]={
         {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
          .dstStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.dstAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
          .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=ti,
          .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}},
         {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
          .dstStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.dstAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
          .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=ci,
          .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}}};
      VkDependencyInfo d0={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=2,.pImageMemoryBarriers=b0};
      vkCmdPipelineBarrier2(cmd,&d0);
      /* C a -1 partout (un pixel jamais ecrit se voit). */
      VkRenderingAttachmentInfo a0={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=cv,
         .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,
         .storeOp=VK_ATTACHMENT_STORE_OP_STORE,.clearValue={.color={{-1.f,0,0,0}}}};
      VkRenderingInfo r0={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=rC,.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&a0};
      vkCmdBeginRendering(cmd,&r0); vkCmdEndRendering(cmd);
      for(uint32_t k=1;k<=K;++k){
         uint32_t push[3]={k,iter,K};
         VkRenderingAttachmentInfo aa={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=tv,
            .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.loadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .storeOp=VK_ATTACHMENT_STORE_OP_STORE};
         VkRenderingInfo ra={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=rT,.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&aa};
         vkCmdBeginRendering(cmd,&ra);
         vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pa);
         vkCmdPushConstants(cmd,lay,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,12,push);
         vkCmdDraw(cmd,3,1,0,0);
         vkCmdEndRendering(cmd);
         VkImageMemoryBarrier2 b1={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.srcAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .dstStageMask=dstm,.dstAccessMask=VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
            .oldLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.image=ti,
            .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
         VkDependencyInfo d1={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&b1};
         vkCmdPipelineBarrier2(cmd,&d1);
         VkRenderingAttachmentInfo ab={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=cv,
            .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.loadOp=VK_ATTACHMENT_LOAD_OP_LOAD,
            .storeOp=VK_ATTACHMENT_STORE_OP_STORE};
         VkRenderingInfo rb2={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=rC,.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&ab};
         vkCmdBeginRendering(cmd,&rb2);
         vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pb);
         vkCmdBindDescriptorSets(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,lay,0,1,&ds,0,NULL);
         vkCmdPushConstants(cmd,lay,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,12,push);
         vkCmdDraw(cmd,1,1,0,0);
         vkCmdEndRendering(cmd);
         VkImageMemoryBarrier2 b2={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask=dstm,.srcAccessMask=0,
            .dstStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.dstAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=ti,
            .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
         VkDependencyInfo d2={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&b2};
         vkCmdPipelineBarrier2(cmd,&d2);
      }
      VkImageMemoryBarrier2 b3={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
         .srcStageMask=VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,.srcAccessMask=VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
         .dstStageMask=VK_PIPELINE_STAGE_2_COPY_BIT,.dstAccessMask=VK_ACCESS_2_TRANSFER_READ_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,.image=ci,
         .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      VkDependencyInfo d3={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&b3};
      vkCmdPipelineBarrier2(cmd,&d3);
      VkBufferImageCopy bc={.bufferOffset=0,.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageExtent={K,1,1}};
      vkCmdCopyImageToBuffer(cmd,ci,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,rb,1,&bc);
      vkCmdWriteTimestamp2(cmd,VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,qpool,1);
      CK(vkEndCommandBuffer(cmd));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cmd};
      CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue));
      uint64_t ts[2]={0,0};
      vkGetQueryPoolResults(dev,qpool,0,2,sizeof(ts),ts,sizeof(uint64_t),VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WAIT_BIT);
      ms[rep]=(double)(ts[1]-ts[0])*periode*1e-6;
      int fautes=0, premier=-1;
      for(uint32_t k=1;k<=K;++k) if(lu[k-1]!=(float)k){ fautes++; if(premier<0) premier=(int)k; }
      fautes_tot+=fautes;
      printf("  rep %d : fautes=%d/%u%s%s  gpu=%.2f ms\n",rep,fautes,K,premier>0?" premier k=":"",
             premier>0?"":"",ms[rep]);
      if(premier>0) printf("          C[%d]=%g (attendu %d)\n",premier,lu[premier-1],premier);
   }
   qsort(ms,reps,sizeof(double),cmpd);
   const char*mode=getenv("CIDRE_NARROW_BARRIERS");
   printf("RESULTAT dst=%s mode=%s K=%u iter=%u T=%u : fautes=%d/%d  gpu med=%.2f ms (min %.2f max %.2f)\n",
          dst,mode?mode:"ALL",K,iter,TS,fautes_tot,K*reps,ms[reps/2],ms[0],ms[reps-1]);
   return fautes_tot?3:0;
}
