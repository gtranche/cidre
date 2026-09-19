/* robustImageAccess2 : lire une couche hors de la plage d'une vue doit rendre zero.
 *
 * Image tableau de 4 couches, contenu distinct par couche. On cree une vue qui
 * n'expose que la couche 0, puis on lit la couche 1 -- hors de la vue. Avec
 * robustImageAccess2, la lecture doit rendre zero, pas borner sur la couche 0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "arrayrob_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define LAYERS 4
#define SZ 4
#define MIPS 2
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
   VkPhysicalDeviceRobustness2FeaturesEXT r2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&r2};
   vkGetPhysicalDeviceFeatures2(pdev,&f2);
   printf("robustImageAccess2 = %d\n\n", r2.robustImageAccess2);
   if(!r2.robustImageAccess2){ printf("feature absente, test sans objet\n"); return 77; }

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceRobustness2FeaturesEXT want_r2={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,.robustImageAccess2=VK_TRUE};
   const char *exts[]={VK_EXT_ROBUSTNESS_2_EXTENSION_NAME};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&want_r2,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,
      .enabledExtensionCount=1,.ppEnabledExtensionNames=exts};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

   VkImage img; VkDeviceMemory imem;
   VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
      .format=VK_FORMAT_R8G8B8A8_UNORM,.extent={SZ,SZ,1},.mipLevels=MIPS,.arrayLayers=LAYERS,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   CK(vkCreateImage(dev,&ii,NULL,&img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,img,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&imem)); CK(vkBindImageMemory(dev,img,imem,0));

   /* Chaque couche recoit une valeur distincte : couche i -> i+1 */
   VkBuffer up; VkDeviceMemory upm;
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size=(SZ*SZ + (SZ/2)*(SZ/2))*4*LAYERS,.usage=VK_BUFFER_USAGE_TRANSFER_SRC_BIT};
   CK(vkCreateBuffer(dev,&bci,NULL,&up));
   vkGetBufferMemoryRequirements(dev,up,&mr);
   VkMemoryAllocateInfo mai2={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai2,NULL,&upm)); CK(vkBindBufferMemory(dev,up,upm,0));
   unsigned char *m; CK(vkMapMemory(dev,upm,0,VK_WHOLE_SIZE,0,(void**)&m));
   /* Niveau 0 : (couche+1)*64.  Niveau 1 (un texel) : 200, valeur distincte. */
   for(int l=0;l<LAYERS;l++) memset(m + l*SZ*SZ*4, (l+1)*64, SZ*SZ*4);
   memset(m + LAYERS*SZ*SZ*4, 200, (SZ/2)*(SZ/2)*4*LAYERS);
   vkUnmapMemory(dev,upm);

   VkBuffer out; VkDeviceMemory outm;
   VkBufferCreateInfo obci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=4*4*6,
      .usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   CK(vkCreateBuffer(dev,&obci,NULL,&out));
   vkGetBufferMemoryRequirements(dev,out,&mr);
   VkMemoryAllocateInfo mai3={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai3,NULL,&outm)); CK(vkBindBufferMemory(dev,out,outm,0));

   /* Vue restreinte a la couche 0 */
   VkImageView view;
   VkImageViewCreateInfo vci={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=img,
      .viewType=VK_IMAGE_VIEW_TYPE_2D_ARRAY,.format=VK_FORMAT_R8G8B8A8_UNORM,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,MIPS,0,1}};
   CK(vkCreateImageView(dev,&vci,NULL,&view));
   /* Vue dont le niveau de base est 1 : lire le LOD 0 doit rendre le niveau 1 */
   VkImageView view_mip1;
   VkImageViewCreateInfo vci1=vci; vci1.subresourceRange=(VkImageSubresourceRange){VK_IMAGE_ASPECT_COLOR_BIT,1,1,0,1};
   CK(vkCreateImageView(dev,&vci1,NULL,&view_mip1));
   VkSamplerCreateInfo sci={.sType=VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      .magFilter=VK_FILTER_NEAREST,.minFilter=VK_FILTER_NEAREST,
      .addressModeU=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeV=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeW=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .mipmapMode=VK_SAMPLER_MIPMAP_MODE_NEAREST,.maxLod=VK_LOD_CLAMP_NONE};
   VkSampler samp; CK(vkCreateSampler(dev,&sci,NULL,&samp));

   VkDescriptorSetLayoutBinding b[3]={
      {0,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL},
      {1,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL},
      {2,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL}};
   VkDescriptorSetLayoutCreateInfo dslci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount=3,.pBindings=b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dslci,NULL,&dsl));
   VkDescriptorPoolSize ps[2]={{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,2},{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1}};
   VkDescriptorPoolCreateInfo dpci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets=1,.poolSizeCount=2,.pPoolSizes=ps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpci,NULL,&dp));
   VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool=dp,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsai,&ds));
   VkDescriptorImageInfo dii={.sampler=samp,.imageView=view,.imageLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkDescriptorBufferInfo dbi={.buffer=out,.offset=0,.range=VK_WHOLE_SIZE};
   VkDescriptorImageInfo dii1={.sampler=samp,.imageView=view_mip1,.imageLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkWriteDescriptorSet w[3]={
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&dii},
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=1,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&dbi},
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=2,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&dii1}};
   vkUpdateDescriptorSets(dev,3,w,0,NULL);

   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl};
   VkPipelineLayout layout; CK(vkCreatePipelineLayout(dev,&plci,NULL,&layout));
   VkShaderModuleCreateInfo smci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=cs_spv_len,.pCode=(const uint32_t*)cs_spv};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&smci,NULL,&sm));
   VkComputePipelineCreateInfo cp={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
              .stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=layout};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cp,NULL,&pipe));

   VkCommandBufferAllocateInfo cbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&cbi,&cb));
   VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb,&bi));
   VkImageMemoryBarrier tb={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .dstAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT,.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,.image=img,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,MIPS,0,LAYERS}};
   vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,0,NULL,0,NULL,1,&tb);
   VkBufferImageCopy cp2[LAYERS*2];
   for(int l=0;l<LAYERS;l++) cp2[l]=(VkBufferImageCopy){.bufferOffset=(VkDeviceSize)l*SZ*SZ*4,
      .imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,(uint32_t)l,1},.imageExtent={SZ,SZ,1}};
   for(int l=0;l<LAYERS;l++) cp2[LAYERS+l]=(VkBufferImageCopy){
      .bufferOffset=(VkDeviceSize)LAYERS*SZ*SZ*4 + (VkDeviceSize)l*(SZ/2)*(SZ/2)*4,
      .imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,1,(uint32_t)l,1},.imageExtent={SZ/2,SZ/2,1}};
   vkCmdCopyBufferToImage(cb,up,img,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,LAYERS*2,cp2);
   tb.srcAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT; tb.dstAccessMask=VK_ACCESS_SHADER_READ_BIT;
   tb.oldLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; tb.newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
   vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,0,0,NULL,0,NULL,1,&tb);
   vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe);
   vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,layout,0,1,&ds,0,NULL);
   vkCmdDispatch(cb,1,1,1);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
   CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(queue));

   float *res; CK(vkMapMemory(dev,outm,0,VK_WHOLE_SIZE,0,(void**)&res));
   int fail=0;
   printf("vue restreinte a la couche 0, image de %d couches\n", LAYERS);
   printf("  couche 0 (dans la vue)  : %.3f  (attendu 0.251)  %s\n", res[0],
          (res[0] > 0.2f && res[0] < 0.3f) ? "OK" : "ECHEC");
   if(!(res[0] > 0.2f && res[0] < 0.3f)) fail++;
   printf("  couche 1 (hors de vue)  : %.3f  (attendu 0.000)  %s\n", res[4],
          res[4] == 0.0f ? "OK" : "ECHEC");
   if(res[4] != 0.0f) fail++;
   printf("  niveau 1 (dans la vue)   : %.3f  (attendu 0.784)  %s\n", res[8],
          (res[8] > 0.75f && res[8] < 0.82f) ? "OK" : "ECHEC");
   if(!(res[8] > 0.75f && res[8] < 0.82f)) fail++;
   printf("  texelFetch niveau 1      : %.3f  (attendu 0.784)  %s\n", res[12],
          (res[12] > 0.75f && res[12] < 0.82f) ? "OK" : "ECHEC");
   if(!(res[12] > 0.75f && res[12] < 0.82f)) fail++;
   printf("  vue base=niveau 1, sample : %.3f  (attendu 0.784)  %s\n", res[16],
          (res[16] > 0.75f && res[16] < 0.82f) ? "OK" : "ECHEC");
   if(!(res[16] > 0.75f && res[16] < 0.82f)) fail++;
   printf("  vue base=niveau 1, fetch  : %.3f  (attendu 0.784)  %s\n", res[20],
          (res[20] > 0.75f && res[20] < 0.82f) ? "OK" : "ECHEC");
   if(!(res[20] > 0.75f && res[20] < 0.82f)) fail++;
   vkUnmapMemory(dev,outm);
   printf("\n%s (%d echec(s))\n",fail?"ECHECS":"TOUT PASSE",fail);
   return fail?1:0;
}
