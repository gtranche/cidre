/* Liste de tuiles a la UE5 : le thread 0 de chaque groupe reserve 64 places par imageAtomicAdd
 * sur un tampon texel et range la base en memoire partagee ; chaque thread ecrit a base + i.
 * 4 groupes : attendu, 256 entrees ecrites (valeurs 1..4), compteur = 256.
 *   build/sonde_liste_tuiles build/liste_tuiles.spv   (correctif 0145) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d\n", #x, r_); exit(1); } } while (0)
static VkDevice dev; static VkPhysicalDevice pd;
static VkBuffer mkbuf(VkDeviceSize sz, void **map) {
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = sz, .usage = VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, b, &mr);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp); uint32_t t = 0;
   for (; t < mp.memoryTypeCount; t++) if ((mr.memoryTypeBits >> t & 1) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = t};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0)); CK(vkMapMemory(dev, m, 0, sz, 0, map));
   return b;
}
static VkBufferView mkview(VkBuffer b, VkDeviceSize sz) {
   VkBufferViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO, .buffer = b, .format = VK_FORMAT_R32_UINT, .range = sz};
   VkBufferView v; CK(vkCreateBufferView(dev, &vc, NULL, &v)); return v;
}
int main(int argc, char **argv) {
   if (argc < 2) return 2;
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
   uint32_t *cpt, *lst;
   VkBuffer bc = mkbuf(256, (void **)&cpt), bl = mkbuf(1024 * 4, (void **)&lst);
   memset(cpt, 0, 256); memset(lst, 0xff, 1024 * 4);
   VkBufferView vcpt = mkview(bc, 256), vlst = mkview(bl, 1024 * 4);
   FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); size_t n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != n) return 2; fclose(f);
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkDescriptorSetLayoutBinding bd[2] = {{0, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}, {1, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &pipe));
   VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 2};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkWriteDescriptorSet wd[2] = {{.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .pTexelBufferView = &vcpt},
                                 {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .pTexelBufferView = &vlst}};
   vkUpdateDescriptorSets(dev, 2, wd, 0, NULL);
   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo bi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &bi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, 4, 1, 1);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo s = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &s, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));
   int ecrites = 0, par[5] = {0};
   for (int i = 0; i < 256; i++) if (lst[i] != 0xffffffffu) { ecrites++; if (lst[i] <= 4) par[lst[i]]++; }
   printf("compteur = %u (attendu 256) ; entrees 0..255 ecrites : %d (attendu 256) ; groupes 1..4 : %d %d %d %d\n",
          cpt[0], ecrites, par[1], par[2], par[3], par[4]);
   printf("RESULTAT : %s\n", cpt[0] == 256 && ecrites == 256 ? "juste" : "FAUX");
   return 0;
}
