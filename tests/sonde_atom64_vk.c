/* Sonde KosmicKrisp : atomiques 64 bits sur tampon (VK_KHR_shader_atomic_int64,
 * CIDRE_ATOMIQUES_64, M2 et suivants). 64 fils : max/min sans valeur rendue (natifs Metal),
 * add avec retenue entre les deux mots, or/and/xor (decoupes en deux atomiques 32 bits).
 * Verifie les valeurs finales, et dit combien des 64 valeurs rendues par atomicAdd sont des
 * sommes partielles coherentes (le decoupage rend chaque mot a part).
 *   sonde_atom64_vk <atom64.spv> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

static int cmpu(const void *a, const void *b) { uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b; return x < y ? -1 : x > y; }

int main(int argc, char **argv) {
   if (argc < 2) return 2;
   FILE *f = fopen(argv[1], "rb"); if (!f) return 2;
   fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != (size_t)n) return 2; fclose(f);
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   VkPhysicalDevice pd; uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   VkPhysicalDeviceVulkan12Features v12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
   VkPhysicalDeviceFeatures2 f2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v12};
   vkGetPhysicalDeviceFeatures2(pd, &f2);
   printf("annonce : shaderBufferInt64Atomics=%u shaderSharedInt64Atomics=%u shaderInt64=%u\n",
          v12.shaderBufferInt64Atomics, v12.shaderSharedInt64Atomics, f2.features.shaderInt64);
   if (!v12.shaderBufferInt64Atomics) { printf("RESULTAT : non annonce\n"); return 3; }
   VkPhysicalDeviceVulkan12Features e12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .shaderBufferInt64Atomics = VK_TRUE};
   VkPhysicalDeviceFeatures2 e2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &e12, .features = {.shaderInt64 = VK_TRUE}};
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &e2, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc};
   VkDevice dev; CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);

   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = 70 * 8, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, b, &mr);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   uint32_t t = 0; for (; t < mp.memoryTypeCount; t++) if ((mr.memoryTypeBits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = t};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0));
   uint64_t *p; CK(vkMapMemory(dev, m, 0, 70 * 8, 0, (void **)&p));
   memset(p, 0, 70 * 8); p[1] = ~0ull; p[4] = ~0ull;

   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkDescriptorSetLayoutBinding bd = {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline pipe; VkResult r = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &pipe);
   if (r) { printf("RESULTAT : pipeline refuse (%d)\n", r); return 3; }
   VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorBufferInfo bi = {b, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wd = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bi};
   vkUpdateDescriptorSets(dev, 1, &wd, 0, NULL);
   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, 1, 1, 1);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));

   uint64_t mx = 0, mn = ~0ull, sum = 0, o = 0, a = ~0ull, x = 0;
   for (uint64_t i = 0; i < 64; i++) {
      uint64_t v = i + 1 + (1ull << 40);
      mx = v > mx ? v : mx; mn = v < mn ? v : mn; sum += v + 0xFFFFFFF0ull; o |= v; a &= ~(1ull << i); x ^= v;
   }
   const char *nom[6] = {"max (natif, sans valeur rendue)", "min (natif, sans valeur rendue)", "add (deux mots + retenue)", "or (deux mots)", "and (deux mots)", "xor (deux mots)"};
   uint64_t att[6] = {mx, mn, sum, o, a, x};
   int faux = 0;
   for (int k = 0; k < 6; k++) {
      int ok = p[k] == att[k]; faux += !ok;
      printf("  %-34s %s (%#llx, attendu %#llx)\n", nom[k], ok ? "juste" : "FAUX", (unsigned long long)p[k], (unsigned long long)att[k]);
   }
   uint64_t ret[64]; memcpy(ret, p + 6, sizeof(ret)); qsort(ret, 64, 8, cmpu);
   int coherents = 0; uint64_t prefixe = 0;
   for (int i = 0; i < 64; i++) { if (ret[i] == prefixe) coherents++; if (i < 63) prefixe = ret[i + 1]; }
   int croissant = 1; for (int i = 1; i < 64; i++) if (ret[i] <= ret[i - 1]) croissant = 0;
   printf("  valeurs rendues par atomicAdd : %s, la plus petite %#llx (attendu 0)\n", croissant ? "toutes distinctes" : "DOUBLONS", (unsigned long long)ret[0]);
   printf("RESULTAT : %d faux sur 6\n", faux);
   (void)coherents;
   return faux ? 3 : 0;
}
