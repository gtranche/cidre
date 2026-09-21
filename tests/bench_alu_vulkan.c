/* Meme chaine de multiplications-additions dependantes que
 * tests/bench_alu_metal.m, mais empruntee via GLSL -> SPIR-V -> KosmicKrisp. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#define CK(x) do { VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__); exit(1);} } while(0)

static double maintenant(void)
{
   struct timespec ts; clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
   return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
   uint32_t iterations = argc > 1 ? (uint32_t)atoi(argv[1]) : 100000u;
   uint32_t fils = argc > 2 ? (uint32_t)atoi(argv[2]) : 65536u;
   const char *spv = argc > 3 ? argv[3] : "build/bench_alu.spv";

   VkApplicationInfo app = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici = {.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo=&app};
   VkInstance inst; CK(vkCreateInstance(&ici, NULL, &inst));
   VkPhysicalDevice pd; uint32_t n=1; vkEnumeratePhysicalDevices(inst,&n,&pd);
   uint32_t nq=0; vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,NULL);
   VkQueueFamilyProperties *qp=malloc(nq*sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,qp);
   uint32_t qf=0; for(uint32_t i=0;i<nq;++i) if(qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT){qf=i;break;}
   float prio=1.0f;
   VkDeviceQueueCreateInfo q={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=qf,.queueCount=1,.pQueuePriorities=&prio};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.queueCreateInfoCount=1,.pQueueCreateInfos=&q};
   VkDevice dev; CK(vkCreateDevice(pd,&dci,NULL,&dev));
   VkQueue queue; vkGetDeviceQueue(dev,qf,0,&queue);

   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
   uint32_t mt=UINT32_MAX;
   for(uint32_t i=0;i<mp.memoryTypeCount;++i)
      if((mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
         (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) { mt=i; break; }

   VkDeviceSize taille = 16 + (VkDeviceSize)fils*4;
   VkBufferCreateInfo bi={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=taille,
      .usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
   VkBuffer buf; CK(vkCreateBuffer(dev,&bi,NULL,&buf));
   VkMemoryRequirements req; vkGetBufferMemoryRequirements(dev,buf,&req);
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=req.size,.memoryTypeIndex=mt};
   VkDeviceMemory mem; CK(vkAllocateMemory(dev,&ai,NULL,&mem));
   CK(vkBindBufferMemory(dev,buf,mem,0));
   void *map; CK(vkMapMemory(dev,mem,0,VK_WHOLE_SIZE,0,&map));
   memset(map,0,taille); ((uint32_t*)map)[0]=iterations;

   FILE *fp=fopen(spv,"rb"); if(!fp){printf("pas de %s\n",spv);return 1;}
   fseek(fp,0,SEEK_END); long sz=ftell(fp); fseek(fp,0,SEEK_SET);
   uint32_t *code=malloc(sz); if(fread(code,1,sz,fp)!=(size_t)sz){printf("lecture\n");return 1;} fclose(fp);
   VkShaderModuleCreateInfo smi={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=sz,.pCode=code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&smi,NULL,&sm));

   VkDescriptorSetLayoutBinding b0={0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo dli={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&b0};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dli,NULL,&dsl));
   VkPipelineLayoutCreateInfo pli={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&dsl};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&pli,NULL,&pl));
   VkComputePipelineCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=pl};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cpi,NULL,&pipe));

   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1};
   VkDescriptorPoolCreateInfo dpi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpi,NULL,&dp));
   VkDescriptorSetAllocateInfo dsa={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=dp,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsa,&ds));
   VkDescriptorBufferInfo dbi={buf,0,VK_WHOLE_SIZE};
   VkWriteDescriptorSet w={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,
      .descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&dbi};
   vkUpdateDescriptorSets(dev,1,&w,0,NULL);

   VkCommandPoolCreateInfo cpci={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qf};
   VkCommandPool pool; CK(vkCreateCommandPool(dev,&cpci,NULL,&pool));
   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&cbai,&cb));

   double meilleur=1e9;
   for (int rep=0; rep<5; ++rep) {
      double t0=maintenant();
      VkCommandBufferBeginInfo bgi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cb,&bgi));
      vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe);
      vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pl,0,1,&ds,0,NULL);
      vkCmdDispatch(cb,fils/64u,1,1);
      CK(vkEndCommandBuffer(cb));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
      CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
      CK(vkQueueWaitIdle(queue));
      double dt=maintenant()-t0;
      if (dt<meilleur) meilleur=dt;
   }
   printf("notre-pile   iterations=%u fils=%u  meilleur=%.1f ms  sortie[0]=%g\n",
          iterations, fils, meilleur*1e3, ((float*)((char*)map+16))[0]);
   return 0;
}
