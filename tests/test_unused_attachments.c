/* VK_EXT_dynamic_rendering_unused_attachments : balayage exhaustif.
 *
 * Pour chaque combinaison (masque declare par le pipeline, masque fourni par la
 * passe) sur 4 attachements, on dessine un fragment qui ecrit j+1 a
 * l'emplacement j, et on verifie que l'attachement j vaut j+1 si et seulement
 * si j est dans les deux masques, 0 sinon.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "unusedatt_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define NRT 4
#define NMASK 16
static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }

int main(void){
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   VkPhysicalDeviceDynamicRenderingUnusedAttachmentsFeaturesEXT ua={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_FEATURES_EXT};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&ua};
   vkGetPhysicalDeviceFeatures2(pdev,&f2);
   if(!ua.dynamicRenderingUnusedAttachments){ printf("feature absente\n"); return 77; }

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceDynamicRenderingUnusedAttachmentsFeaturesEXT want_ua={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_FEATURES_EXT,
      .dynamicRenderingUnusedAttachments=VK_TRUE};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      .pNext=&want_ua,.dynamicRendering=VK_TRUE};
   const char *exts[]={VK_EXT_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_EXTENSION_NAME};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&v13,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,
      .enabledExtensionCount=1,.ppEnabledExtensionNames=exts};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

   VkImage img[NRT]; VkDeviceMemory imem[NRT]; VkImageView view[NRT];
   for(int i=0;i<NRT;i++){
      VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
         .format=VK_FORMAT_R32_SFLOAT,.extent={1,1,1},.mipLevels=1,.arrayLayers=1,
         .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
         .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT};
      CK(vkCreateImage(dev,&ii,NULL,&img[i]));
      VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,img[i],&mr);
      VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
         .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
      CK(vkAllocateMemory(dev,&mai,NULL,&imem[i])); CK(vkBindImageMemory(dev,img[i],imem[i],0));
      VkImageViewCreateInfo vci={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=img[i],
         .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=VK_FORMAT_R32_SFLOAT,
         .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      CK(vkCreateImageView(dev,&vci,NULL,&view[i]));
   }

   VkBuffer out; VkDeviceMemory outm;
   VkDeviceSize outsz=(VkDeviceSize)4*NRT*NMASK*NMASK;
   VkBufferCreateInfo obci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=outsz,
      .usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   CK(vkCreateBuffer(dev,&obci,NULL,&out));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,out,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&outm)); CK(vkBindBufferMemory(dev,out,outm,0));

   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   VkPipelineLayout layout; CK(vkCreatePipelineLayout(dev,&plci,NULL,&layout));
   VkShaderModuleCreateInfo vsm={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=vs_spv_len,.pCode=(const uint32_t*)vs_spv};
   VkShaderModuleCreateInfo fsm={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=fs_spv_len,.pCode=(const uint32_t*)fs_spv};
   VkShaderModule vs,fs; CK(vkCreateShaderModule(dev,&vsm,NULL,&vs)); CK(vkCreateShaderModule(dev,&fsm,NULL,&fs));

   const int blend = getenv("NOBLEND") ? 0 : 1;
   VkPipeline pipes[NMASK];
   for(int m=0;m<NMASK;m++){
      VkFormat pf[NRT];
      for(int j=0;j<NRT;j++) pf[j]=(m>>j)&1 ? VK_FORMAT_R32_SFLOAT : VK_FORMAT_UNDEFINED;
      VkPipelineRenderingCreateInfo prci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
         .colorAttachmentCount=NRT,.pColorAttachmentFormats=pf};
      VkPipelineShaderStageCreateInfo st[2]={
         {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
         {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
      VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
      VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
      VkViewport vp={0,0,1,1,0,1}; VkRect2D sc={{0,0},{1,1}};
      VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
      VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.lineWidth=1.f};
      VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
      VkPipelineColorBlendAttachmentState cba[NRT];
      for(int j=0;j<NRT;j++) cba[j]=(VkPipelineColorBlendAttachmentState){.colorWriteMask=0xf,
         .blendEnable=(blend && ((m>>j)&1))?VK_TRUE:VK_FALSE,
         .srcColorBlendFactor=VK_BLEND_FACTOR_ONE,.dstColorBlendFactor=VK_BLEND_FACTOR_ONE,
         .colorBlendOp=VK_BLEND_OP_ADD,
         .srcAlphaBlendFactor=VK_BLEND_FACTOR_ONE,.dstAlphaBlendFactor=VK_BLEND_FACTOR_ONE,
         .alphaBlendOp=VK_BLEND_OP_ADD};
      VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
         .attachmentCount=NRT,.pAttachments=cba};
      VkGraphicsPipelineCreateInfo gpci={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&prci,
         .stageCount=2,.pStages=st,.pVertexInputState=&vi,.pInputAssemblyState=&ia,
         .pViewportState=&vps,.pRasterizationState=&rs,.pMultisampleState=&ms,
         .pColorBlendState=&cb,.layout=layout};
      CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gpci,NULL,&pipes[m]));
   }

   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev,&cbai,&cmd));
   VkCommandBufferBeginInfo cbbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cmd,&cbbi));

   VkImageSubresourceRange srr={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
   VkImageMemoryBarrier b[NRT];
   for(int i=0;i<NRT;i++) b[i]=(VkImageMemoryBarrier){.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .image=img[i],.subresourceRange=srr};
   #define BARRIER(src,dst,ol,nl,ss,ds) do{ for(int _i=0;_i<NRT;_i++){ b[_i].srcAccessMask=(src); \
      b[_i].dstAccessMask=(dst); b[_i].oldLayout=(ol); b[_i].newLayout=(nl);} \
      vkCmdPipelineBarrier(cmd,(ss),(ds),0,0,NULL,0,NULL,NRT,b);}while(0)

   BARRIER(0,VK_ACCESS_TRANSFER_WRITE_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
           VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);

   for(int pass_mask=0;pass_mask<NMASK;pass_mask++)
   for(int pso_mask=0;pso_mask<NMASK;pso_mask++){
      VkClearColorValue zero={.float32={0.f,0.f,0.f,0.f}};
      for(int i=0;i<NRT;i++) vkCmdClearColorImage(cmd,img[i],VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,&zero,1,&srr);
      BARRIER(VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
              VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
              VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);

      VkRenderingAttachmentInfo ra[NRT];
      for(int j=0;j<NRT;j++) ra[j]=(VkRenderingAttachmentInfo){.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=((pass_mask>>j)&1)?view[j]:VK_NULL_HANDLE,
         .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_LOAD,.storeOp=VK_ATTACHMENT_STORE_OP_STORE};
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea={{0,0},{1,1}},
         .layerCount=1,.colorAttachmentCount=NRT,.pColorAttachments=ra};
      vkCmdBeginRendering(cmd,&ri);
      vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[pso_mask]);
      vkCmdDraw(cmd,3,1,0,0);
      vkCmdDraw(cmd,3,1,0,0);
      vkCmdEndRendering(cmd);

      BARRIER(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT,
              VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
      for(int i=0;i<NRT;i++){
         VkBufferImageCopy cp={.bufferOffset=(VkDeviceSize)(((pass_mask*NMASK)+pso_mask)*NRT+i)*4,
            .imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageExtent={1,1,1}};
         vkCmdCopyImageToBuffer(cmd,img[i],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,out,1,&cp);
      }
      BARRIER(VK_ACCESS_TRANSFER_READ_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,
              VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
              VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
   }
   CK(vkEndCommandBuffer(cmd));
   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cmd};
   CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue));

   float *res; CK(vkMapMemory(dev,outm,0,VK_WHOLE_SIZE,0,(void**)&res));
   int fail=0, shown=0;
   for(int pass_mask=0;pass_mask<NMASK;pass_mask++)
   for(int pso_mask=0;pso_mask<NMASK;pso_mask++){
      for(int j=0;j<NRT;j++){
         float got=res[((pass_mask*NMASK)+pso_mask)*NRT+j];
         float want=(((pass_mask&pso_mask)>>j)&1)?(float)((blend?2:1)*(j+1)):0.f;
         if(got!=want){
            fail++;
            if(shown++<12)
               printf("  passe=%X pipeline=%X attachement %d : %.1f (attendu %.1f)\n",
                      pass_mask,pso_mask,j,got,want);
         }
      }
   }
   vkUnmapMemory(dev,outm);
   printf("\n%d combinaisons, %s (%d echec(s) sur %d verifications)\n",
          NMASK*NMASK, fail?"ECHECS":"TOUT PASSE", fail, NMASK*NMASK*NRT);
   return fail?1:0;
}
