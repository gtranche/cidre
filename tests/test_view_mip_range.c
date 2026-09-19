/* Vues tableau a plage de niveaux : reproduit la geometrie du test d3d12
 * test_tex2d_array_reinterpretation (256x128, 8 niveaux, 16 couches, R8_UNORM).
 *
 * Chaque sous-ressource (couche, niveau) recoit la valeur couche*8 + niveau + 1.
 * On cree deux vues et on echantillonne plusieurs LOD relatifs a leur niveau de
 * base : la valeur lue doit correspondre a la sous-ressource visee par la vue.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "viewmip_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 256
#define H 128
#define MIPS 8
#define LAYERS 16
static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }
static VkDeviceSize level_bytes(int L){ return (VkDeviceSize)(W>>L)*(H>>L); }
static VkDeviceSize layer_bytes(void){ VkDeviceSize s=0; for(int L=0;L<MIPS;L++) s+=level_bytes(L); return s; }
static VkDeviceSize sub_off(int layer,int L){ VkDeviceSize s=(VkDeviceSize)layer*layer_bytes();
   for(int k=0;k<L;k++) s+=level_bytes(k); return s; }

int main(void){
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

   VkImage img; VkDeviceMemory imem;
   VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
      .format=VK_FORMAT_R8_UNORM,.extent={W,H,1},.mipLevels=MIPS,.arrayLayers=LAYERS,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   CK(vkCreateImage(dev,&ii,NULL,&img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,img,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&imem)); CK(vkBindImageMemory(dev,img,imem,0));

   VkDeviceSize total=(VkDeviceSize)LAYERS*layer_bytes();
   VkBuffer up; VkDeviceMemory upm;
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size=total,.usage=VK_BUFFER_USAGE_TRANSFER_SRC_BIT};
   CK(vkCreateBuffer(dev,&bci,NULL,&up));
   vkGetBufferMemoryRequirements(dev,up,&mr);
   VkMemoryAllocateInfo mai2={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai2,NULL,&upm)); CK(vkBindBufferMemory(dev,up,upm,0));
   unsigned char *m; CK(vkMapMemory(dev,upm,0,VK_WHOLE_SIZE,0,(void**)&m));
   for(int l=0;l<LAYERS;l++) for(int L=0;L<MIPS;L++)
      memset(m+sub_off(l,L), l*8+L+1, (size_t)level_bytes(L));
   vkUnmapMemory(dev,upm);

   VkBuffer out; VkDeviceMemory outm;
   VkBufferCreateInfo obci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=4*4*18,
      .usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   CK(vkCreateBuffer(dev,&obci,NULL,&out));
   vkGetBufferMemoryRequirements(dev,out,&mr);
   VkMemoryAllocateInfo mai3={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai3,NULL,&outm)); CK(vkBindBufferMemory(dev,out,outm,0));

   /* v0 : couche 0, tous les niveaux.  v1 : couche 3, niveau de base 2. */
   VkImageView v0,v1;
   VkImageViewCreateInfo vci={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=img,
      .viewType=VK_IMAGE_VIEW_TYPE_2D_ARRAY,.format=VK_FORMAT_R8_UNORM,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,MIPS,0,1}};
   CK(vkCreateImageView(dev,&vci,NULL,&v0));
   /* v1 : vue de type 2D (non tableau) sur une seule couche, lue par un
    * shader qui la declare sampler2DArray -- ce que fait le test d3d12. */
   vci.viewType=VK_IMAGE_VIEW_TYPE_2D;
   vci.subresourceRange=(VkImageSubresourceRange){VK_IMAGE_ASPECT_COLOR_BIT,0,MIPS,3,1};
   CK(vkCreateImageView(dev,&vci,NULL,&v1));

   VkSamplerCreateInfo sci={.sType=VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      .magFilter=VK_FILTER_NEAREST,.minFilter=VK_FILTER_NEAREST,
      .mipmapMode=VK_SAMPLER_MIPMAP_MODE_NEAREST,
      .addressModeU=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeV=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeW=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,.maxLod=VK_LOD_CLAMP_NONE};
   VkSampler samp; CK(vkCreateSampler(dev,&sci,NULL,&samp));

   VkDescriptorSetLayoutBinding b[3]={
      {0,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL},
      {1,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL},
      {2,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL}};
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
   VkDescriptorImageInfo d0={.sampler=samp,.imageView=v0,.imageLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkDescriptorImageInfo d1={.sampler=samp,.imageView=v1,.imageLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkDescriptorBufferInfo dbi={.buffer=out,.offset=0,.range=VK_WHOLE_SIZE};
   VkWriteDescriptorSet w[3]={
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&d0},
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=1,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,.pImageInfo=&d1},
      {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=2,.descriptorCount=1,
       .descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&dbi}};
   vkUpdateDescriptorSets(dev,3,w,0,NULL);

   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl};
   VkPipelineLayout layout; CK(vkCreatePipelineLayout(dev,&plci,NULL,&layout));
   VkShaderModuleCreateInfo smci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=cs_spv_len,.pCode=(const uint32_t*)cs_spv};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&smci,NULL,&sm));
   VkComputePipelineCreateInfo cpci2={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
              .stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=layout};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cpci2,NULL,&pipe));

   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&cbai,&cb));
   VkCommandBufferBeginInfo cbbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb,&cbbi));
   VkImageMemoryBarrier tb={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .dstAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT,.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,.image=img,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,MIPS,0,LAYERS}};
   vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,0,NULL,0,NULL,1,&tb);
   VkBufferImageCopy *cps=calloc(LAYERS*MIPS,sizeof(*cps));
   for(int l=0;l<LAYERS;l++) for(int L=0;L<MIPS;L++)
      cps[l*MIPS+L]=(VkBufferImageCopy){.bufferOffset=sub_off(l,L),
         .imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,(uint32_t)L,(uint32_t)l,1},
         .imageExtent={(uint32_t)(W>>L),(uint32_t)(H>>L),1}};
   vkCmdCopyBufferToImage(cb,up,img,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,LAYERS*MIPS,cps);
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
   struct { const char *nom; int attendu; } cas[18]={
      {"v0 fetch LOD execution 0",1},{"v0 fetch LOD execution 1",2},
      {"v0 fetch LOD execution 2",3},{"v0 fetch LOD execution 3",4},
      {"v0 fetch LOD execution 4",5},{"v0 fetch LOD execution 5",6},
      {"v0 fetch LOD execution 6",7},{"v0 fetch LOD execution 7",8},
      {"v0 sample LOD litteral 0",1},{"v0 sample LOD litteral 1",2},
      {"v0 sample LOD litteral 2",3},{"v0 sample LOD litteral 3",4},
      {"v1 (vue 2D) sample LOD 0",3*8+0+1},{"v1 (vue 2D) sample LOD 1",3*8+1+1},
      {"v1 (vue 2D) fetch  LOD 0",3*8+0+1},{"v1 (vue 2D) fetch  LOD 1",3*8+1+1},
      {"v0 mip nearest LOD 0.5   ",2},{"v0 mip nearest LOD 1.5   ",3}};
   int fail=0;
   printf("image %dx%d, %d niveaux, %d couches, valeur = couche*8 + niveau + 1\n\n",W,H,MIPS,LAYERS);
   for(int i=0;i<18;i++){
      int got=(int)(res[i*4]*255.f+0.5f);
      int ok=(got==cas[i].attendu);
      if(!ok) fail++;
      printf("  %-24s : %3d  (attendu %3d)  %s\n",cas[i].nom,got,cas[i].attendu,ok?"OK":"ECHEC");
   }
   vkUnmapMemory(dev,outm);
   printf("\n%s (%d echec(s))\n",fail?"ECHECS":"TOUT PASSE",fail);
   return fail?1:0;
}
