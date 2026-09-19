/* Vues de texel buffer a offset non aligne sur 16 (KosmicKrisp). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "cs.h"

#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){ \
   printf("ECHEC %s -> %d (ligne %d)\n",#x,_r,__LINE__); exit(1);} } while(0)

#define N        32u        /* uints dans le buffer source */
#define READS     8u        /* texels lus par chaque vue */
#define BASE    100u        /* data[i] = BASE + i */

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags props){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++)
      if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&props)==props) return i;
   printf("pas de type memoire\n"); exit(1);
}
static void mk_buffer(VkDeviceSize size, VkBufferUsageFlags usage,
                      VkBuffer *buf, VkDeviceMemory *mem){
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size=size,.usage=usage,.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
   CK(vkCreateBuffer(dev,&bci,NULL,buf));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,*buf,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize=mr.size,.memoryTypeIndex=mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,mem));
   CK(vkBindBufferMemory(dev,*buf,*mem,0));
}

int main(int argc, char **argv){
   /* Offsets en TEXELS (4 octets chacun) : 1 et 3 ne sont pas alignes sur 16. */
   uint32_t uni_texel = argc>1 ? (uint32_t)atoi(argv[1]) : 1u;
   uint32_t sto_texel = argc>2 ? (uint32_t)atoi(argv[2]) : 3u;

   VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));

   VkPhysicalDeviceVulkan13Properties v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES};
   VkPhysicalDeviceProperties2 p2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,.pNext=&v13};
   vkGetPhysicalDeviceProperties2(pdev,&p2);
   printf("uniformSingleTexel=%d (align %llu)  storageSingleTexel=%d (align %llu)\n\n",
      v13.uniformTexelBufferOffsetSingleTexelAlignment,
      (unsigned long long)v13.uniformTexelBufferOffsetAlignmentBytes,
      v13.storageTexelBufferOffsetSingleTexelAlignment,
      (unsigned long long)v13.storageTexelBufferOffsetAlignmentBytes);

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT){qfam=i;break;}
   float prio=1.0f;
   VkDeviceQueueCreateInfo qci={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&qci};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev));
   vkGetDeviceQueue(dev,qfam,0,&queue);

   VkBuffer src,dst; VkDeviceMemory srcm,dstm;
   mk_buffer(N*4, VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT|
                  VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT, &src,&srcm);
   mk_buffer(16*4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &dst,&dstm);

   uint32_t *p; CK(vkMapMemory(dev,srcm,0,VK_WHOLE_SIZE,0,(void**)&p));
   for(uint32_t i=0;i<N;i++) p[i]=BASE+i;
   vkUnmapMemory(dev,srcm);
   CK(vkMapMemory(dev,dstm,0,VK_WHOLE_SIZE,0,(void**)&p));
   memset(p,0xFF,16*4); vkUnmapMemory(dev,dstm);

   VkBufferViewCreateInfo uvi={.sType=VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
      .buffer=src,.format=VK_FORMAT_R32_UINT,.offset=uni_texel*4u,.range=READS*4u};
   VkBufferViewCreateInfo svi={.sType=VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
      .buffer=src,.format=VK_FORMAT_R32_UINT,.offset=sto_texel*4u,.range=READS*4u};
   VkBufferView uview,sview;
   CK(vkCreateBufferView(dev,&uvi,NULL,&uview));
   CK(vkCreateBufferView(dev,&svi,NULL,&sview));

   VkDescriptorSetLayoutBinding b[3]={
     {0,VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT},
     {1,VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT},
     {2,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount=3,.pBindings=b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dl,NULL,&dsl));
   VkDescriptorPoolSize ps[3]={{VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,1},
      {VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,1},{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1}};
   VkDescriptorPoolCreateInfo dp={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets=1,.poolSizeCount=3,.pPoolSizes=ps};
   VkDescriptorPool dpool; CK(vkCreateDescriptorPool(dev,&dp,NULL,&dpool));
   VkDescriptorSetAllocateInfo dsa={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool=dpool,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsa,&ds));

   VkDescriptorBufferInfo dbi={.buffer=dst,.offset=0,.range=VK_WHOLE_SIZE};
   VkWriteDescriptorSet w[3]={
     {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
      .pTexelBufferView=&uview},
     {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=1,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
      .pTexelBufferView=&sview},
     {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=2,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
      .pBufferInfo=&dbi}};
   vkUpdateDescriptorSets(dev,3,w,0,NULL);

   VkShaderModuleCreateInfo smi={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=c_spv_len,.pCode=(const uint32_t*)c_spv};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&smi,NULL,&sm));
   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&plci,NULL,&pl));
   VkComputePipelineCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
              .stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=pl};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cpi,NULL,&pipe));

   VkCommandPoolCreateInfo pci={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .queueFamilyIndex=qfam}; CK(vkCreateCommandPool(dev,&pci,NULL,&pool));
   VkCommandBufferAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&ai,&cb));
   VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb,&bi));
   vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe);
   vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pl,0,1,&ds,0,NULL);
   vkCmdDispatch(cb,1,1,1);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
   CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
   CK(vkQueueWaitIdle(queue));

   uint32_t *out; CK(vkMapMemory(dev,dstm,0,VK_WHOLE_SIZE,0,(void**)&out));
   int fail=0;
   printf("vue uniform a l'offset %u texels (%u octets%s)\n", uni_texel, uni_texel*4,
          (uni_texel*4)%16 ? ", NON aligne sur 16" : ", aligne sur 16");
   for(uint32_t i=0;i<READS;i++){
      uint32_t exp=BASE+uni_texel+i; int ok=out[i]==exp;
      if(!ok) fail++;
      printf("  texel %u : %u (attendu %u) %s\n",i,out[i],exp,ok?"OK":"ECHEC");
   }
   printf("vue storage a l'offset %u texels (%u octets%s)\n", sto_texel, sto_texel*4,
          (sto_texel*4)%16 ? ", NON aligne sur 16" : ", aligne sur 16");
   for(uint32_t i=0;i<READS;i++){
      uint32_t exp=BASE+sto_texel+i; int ok=out[8+i]==exp;
      if(!ok) fail++;
      printf("  texel %u : %u (attendu %u) %s\n",i,out[8+i],exp,ok?"OK":"ECHEC");
   }
   vkUnmapMemory(dev,dstm);
   printf("\n%s (%d echec(s))\n",fail?"ECHECS":"TOUT PASSE",fail);
   return fail?1:0;
}
