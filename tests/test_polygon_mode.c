/* VK_POLYGON_MODE_LINE : un triangle doit sortir en fil de fer, pas plein. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <vulkan/vulkan.h>
#include "polygon_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 64
#define H 64
static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static VkImage color; static VkDeviceMemory color_mem; static VkImageView view;
static VkBuffer rb; static VkDeviceMemory rb_mem;
static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }
static VkShaderModule mk(const unsigned char *c, unsigned l){
   VkShaderModuleCreateInfo ci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=l,.pCode=(const uint32_t*)c};
   VkShaderModule m; CK(vkCreateShaderModule(dev,&ci,NULL,&m)); return m; }

int main(void){
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   VkPhysicalDeviceFeatures f; vkGetPhysicalDeviceFeatures(pdev,&f);
   printf("fillModeNonSolid = %d\n\n", f.fillModeNonSolid);
   if(!f.fillModeNonSolid){ printf("feature absente, test sans objet\n"); return 77; }

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceFeatures want={.fillModeNonSolid=VK_TRUE};
   VkPhysicalDeviceDynamicRenderingFeatures dr={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,.dynamicRendering=VK_TRUE};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&dr,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,.pEnabledFeatures=&want};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

   VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
      .format=VK_FORMAT_R8G8B8A8_UNORM,.extent={W,H,1},.mipLevels=1,.arrayLayers=1,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT};
   CK(vkCreateImage(dev,&ii,NULL,&color));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,color,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&color_mem)); CK(vkBindImageMemory(dev,color,color_mem,0));
   VkImageViewCreateInfo vi={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=color,
      .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   CK(vkCreateImageView(dev,&vi,NULL,&view));
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=W*H*4,
      .usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   CK(vkCreateBuffer(dev,&bci,NULL,&rb));
   vkGetBufferMemoryRequirements(dev,rb,&mr);
   VkMemoryAllocateInfo mai2={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai2,NULL,&rb_mem)); CK(vkBindBufferMemory(dev,rb,rb_mem,0));

   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   VkPipelineLayout layout; CK(vkCreatePipelineLayout(dev,&plci,NULL,&layout));
   VkShaderModule vs=mk(vs_spv,vs_spv_len), fs=mk(fs_spv,fs_spv_len);
   VkPipelineShaderStageCreateInfo st[2]={
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vin={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
   VkViewport vp={0,0,W,H,0,1}; VkRect2D sc={{0,0},{W,H}};
   VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount=1,.pAttachments=&cba};
   VkFormat cf=VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo prci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount=1,.pColorAttachmentFormats=&cf};

   VkPipeline pipes[2];
   const VkPolygonMode modes[2]={VK_POLYGON_MODE_FILL,VK_POLYGON_MODE_LINE};
   for(int m=0;m<2;m++){
      VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .polygonMode=modes[m],.cullMode=VK_CULL_MODE_NONE,
         .frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE,.lineWidth=1.f};
      VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&prci,
         .stageCount=2,.pStages=st,.pVertexInputState=&vin,.pInputAssemblyState=&ia,
         .pViewportState=&vps,.pRasterizationState=&rs,.pMultisampleState=&ms,
         .pColorBlendState=&cb,.layout=layout};
      CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipes[m]));
   }

   int fail=0, lit[2]={0,0};
   const char *names[2]={"POLYGON_MODE_FILL","POLYGON_MODE_LINE"};
   for(int m=0;m<2;m++){
      VkCommandBufferAllocateInfo cbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
         .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
      VkCommandBuffer cbuf; CK(vkAllocateCommandBuffers(dev,&cbi,&cbuf));
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cbuf,&bi));
      VkImageMemoryBarrier b={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,
         .newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.image=color,
         .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      vkCmdPipelineBarrier(cbuf,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,0,NULL,0,NULL,1,&b);
      VkRenderingAttachmentInfo att={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=view,.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE,
         .clearValue={.color={.float32={0,0,0,1}}}};
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea={{0,0},{W,H}},
         .layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&att};
      vkCmdBeginRendering(cbuf,&ri);
      vkCmdBindPipeline(cbuf,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[m]);
      vkCmdDraw(cbuf,3,1,0,0);
      vkCmdEndRendering(cbuf);
      VkImageMemoryBarrier b2={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .srcAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,.dstAccessMask=VK_ACCESS_TRANSFER_READ_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
         .image=color,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      vkCmdPipelineBarrier(cbuf,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
         VK_PIPELINE_STAGE_TRANSFER_BIT,0,0,NULL,0,NULL,1,&b2);
      VkBufferImageCopy cp={.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageExtent={W,H,1}};
      vkCmdCopyImageToBuffer(cbuf,color,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,rb,1,&cp);
      CK(vkEndCommandBuffer(cbuf));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cbuf};
      CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue));
      vkFreeCommandBuffers(dev,pool,1,&cbuf);

      uint32_t *px; CK(vkMapMemory(dev,rb_mem,0,VK_WHOLE_SIZE,0,(void**)&px));
      /* Un fil de fer allume les aretes seulement : beaucoup moins de pixels
       * qu'un triangle plein, mais pas zero. */
      lit[m] = 0;
      for(int i=0;i<W*H;i++) if(px[i]!=0xff000000u) lit[m]++;
      vkUnmapMemory(dev,rb_mem);
      printf("  %-18s pixels allumes : %d\n", names[m], lit[m]);
   }
   if(lit[0] <= 0){ printf("  ECHEC: le triangle plein n'a rien dessine\n"); fail++; }
   if(lit[1] <= 0){ printf("  ECHEC: le fil de fer n'a rien dessine\n"); fail++; }
   if(lit[1] >= lit[0]/2){ printf("  ECHEC: le fil de fer couvre autant que le plein\n"); fail++; }
   if(!fail) printf("  le fil de fer couvre %d%% du plein : mode pris en compte\n",
                    lit[0] ? 100*lit[1]/lit[0] : 0);

   printf("\n%s (%d echec(s))\n",fail?"ECHECS":"TOUT PASSE",fail);
   return fail?1:0;
}
