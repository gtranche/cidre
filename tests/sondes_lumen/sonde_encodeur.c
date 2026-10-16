/* Sonde KosmicKrisp : beaucoup de dispatchs dans un meme encodeur de calcul, chacun avec ses
 * constantes poussees et son jeu de descripteurs (alternes), directs ou indirects (arguments
 * ecrits par le dispatch precedent, barriere entre deux). Chaque dispatch ecrit son numero
 * dans le tampon de son jeu : un dispatch qui voit la racine d'un autre ecrit au mauvais
 * endroit ou la mauvaise valeur.
 *   sonde_encodeur <ecrit.spv> [dispatchs] [barriere 0|1] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

static VkDevice dev;
static VkPhysicalDeviceMemoryProperties mp;

static VkBuffer buffer(VkDeviceSize sz, VkBufferUsageFlags u, void **map)
{
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = sz, .usage = u};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements r; vkGetBufferMemoryRequirements(dev, b, &r);
   uint32_t t = 0; for (; t < mp.memoryTypeCount; t++) if ((r.memoryTypeBits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = r.size, .memoryTypeIndex = t};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0));
   CK(vkMapMemory(dev, m, 0, VK_WHOLE_SIZE, 0, map)); memset(*map, 0, sz);
   return b;
}

int main(int argc, char **argv)
{
   if (argc < 2) return 2;
   setvbuf(stdout, NULL, _IONBF, 0);
   const uint32_t K = argc > 2 ? atoi(argv[2]) : 512, BAR = argc > 3 ? atoi(argv[3]) : 1;
   FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); size_t n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != n) return 2; fclose(f);
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   VkPhysicalDevice pd; uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
   vkGetPhysicalDeviceMemoryProperties(pd, &mp);

   void *ma, *mb, *mg;
   VkBuffer ba = buffer((VkDeviceSize)K * 64 * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &ma);
   VkBuffer bb = buffer((VkDeviceSize)K * 64 * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &mb);
   VkBuffer bg = buffer((VkDeviceSize)(K + 1) * 16, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, &mg);

   VkDescriptorSetLayoutBinding bd[2] = {{0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}, {1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPushConstantRange pcr = {VK_SHADER_STAGE_COMPUTE_BIT, 0, 8};
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline p; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &p));
   VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 4};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 2, .poolSizeCount = 1, .pPoolSizes = &ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetLayout two[2] = {dsl, dsl};
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 2, .pSetLayouts = two};
   VkDescriptorSet ds[2]; CK(vkAllocateDescriptorSets(dev, &da, ds));
   for (int s = 0; s < 2; s++) {
      VkDescriptorBufferInfo b0 = {s ? bb : ba, 0, VK_WHOLE_SIZE}, b1 = {bg, 0, VK_WHOLE_SIZE};
      VkWriteDescriptorSet wd[2] = {
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &b0},
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &b1}};
      vkUpdateDescriptorSets(dev, 2, wd, 0, NULL);
   }

   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p);
   VkMemoryBarrier mbar = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_INDIRECT_COMMAND_READ_BIT | VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT};
   for (uint32_t k = 0; k < K; k++) {
      uint32_t pc[2] = {k, K};
      vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds[k & 1], 0, NULL);
      vkCmdPushConstants(cb, lay, VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, pc);
      if (k == 0 || k % 3 == 0) vkCmdDispatch(cb, 1, 1, 1);
      else vkCmdDispatchIndirect(cb, bg, (VkDeviceSize)k * 16);
      if (BAR)
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT, 0, 1, &mbar, 0, NULL, 0, NULL);
   }
   VkMemoryBarrier hb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &hb, 0, NULL, 0, NULL);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));

   uint32_t *ra = ma, *rb = mb; int faux = 0, montre = 0, ind_faux = 0;
   for (uint32_t k = 0; k < K; k++) {
      uint32_t *bon = (k & 1) ? rb : ra, *autre = (k & 1) ? ra : rb;
      int fk = 0;
      for (uint32_t i = 0; i < 64; i++) {
         if (bon[k * 64 + i] != k + 1) fk++;
         if (autre[k * 64 + i] != 0) fk++;
      }
      if (fk) { faux += fk; if (k % 3 && k) ind_faux++; if (montre++ < 6) printf("  dispatch %u (%s) : %d faux, case %#x / autre %#x\n", k, (k == 0 || k % 3 == 0) ? "direct" : "indirect", fk, bon[k * 64], autre[k * 64]); }
   }
   printf("%u dispatchs dans un encodeur (barriere %s) : %d valeurs fausses (%d dispatchs indirects touches)\n", K, BAR ? "oui" : "non", faux, ind_faux);
   printf("RESULTAT : %d faux\n", faux);
   return 0;
}
