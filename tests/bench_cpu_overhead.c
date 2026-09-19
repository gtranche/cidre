/* Mesure le cout CPU du pilote : enregistrement de commandes et soumission.
 * C'est la partie que Rosetta traduit ; le travail GPU est natif des deux cotes.
 * Le meme source est compile en arm64 et en x86_64 pour chiffrer l'ecart.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
#include "bench_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define DISPATCHES 20000
#define ROUNDS 10

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

int main(void){
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pdev,&props);
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

   VkBuffer buf; VkDeviceMemory bm;
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=4096,
      .usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   CK(vkCreateBuffer(dev,&bci,NULL,&buf));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,buf,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&bm)); CK(vkBindBufferMemory(dev,buf,bm,0));

   VkDescriptorSetLayoutBinding b={0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT,NULL};
   VkDescriptorSetLayoutCreateInfo dslci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount=1,.pBindings=&b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dslci,NULL,&dsl));
   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1};
   VkDescriptorPoolCreateInfo dpci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpci,NULL,&dp));
   VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool=dp,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsai,&ds));
   VkDescriptorBufferInfo dbi={.buffer=buf,.offset=0,.range=VK_WHOLE_SIZE};
   VkWriteDescriptorSet w={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&dbi};
   vkUpdateDescriptorSets(dev,1,&w,0,NULL);

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

   printf("%s  --  %d dispatches par tour, %d tours\n\n", props.deviceName, DISPATCHES, ROUNDS);

   double rec_best = 1e9, tot_best = 1e9;
   for (int r = 0; r < ROUNDS; r++) {
      CK(vkResetCommandPool(dev,pool,0));
      double t0 = now();
      CK(vkBeginCommandBuffer(cb,&cbbi));
      vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe);
      vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,layout,0,1,&ds,0,NULL);
      for (int i = 0; i < DISPATCHES; i++)
         vkCmdDispatch(cb,1,1,1);
      CK(vkEndCommandBuffer(cb));
      double t1 = now();
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
      CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
      CK(vkQueueWaitIdle(queue));
      double t2 = now();
      if (t1-t0 < rec_best) rec_best = t1-t0;
      if (t2-t0 < tot_best) tot_best = t2-t0;
   }

   printf("enregistrement : %8.2f ms   (%.2f M commandes/s)\n",
          rec_best*1e3, DISPATCHES/rec_best/1e6);
   printf("total (+ GPU)  : %8.2f ms\n", tot_best*1e3);
   return 0;
}
