/* Sonde KosmicKrisp : operations de vague (sous-groupes) des nuanceurs Lumen de Demonologist,
 * en flot divergent, comparees a un calcul CPU (sous-groupe = 32 invocations consecutives).
 * A lancer avec les contournements de macOS 26 (defaut) puis MESA_KK_DISABLE_WORKAROUNDS=3.
 *   sonde_vague <vague.spv> <quad.spv> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

static VkDevice dev;
static VkPhysicalDeviceMemoryProperties mp;

static uint32_t *lire_spv(const char *p, size_t *n)
{
   FILE *f = fopen(p, "rb"); if (!f) { printf("ECHEC %s\n", p); exit(1); }
   fseek(f, 0, SEEK_END); *n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *c = malloc(*n); if (fread(c, 1, *n, f) != *n) exit(1); fclose(f);
   return c;
}

static void lancer(VkQueue q, const char *spv, uint32_t groups, VkBuffer buf)
{
   size_t n; uint32_t *code = lire_spv(spv, &n);
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkDescriptorSetLayoutBinding bd = {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline p; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &p));
   VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorBufferInfo bi = {buf, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wd = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bi};
   vkUpdateDescriptorSets(dev, 1, &wd, 0, NULL);
   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, groups, 1, 1);
   VkMemoryBarrier mb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));
}

static const char *noms[24] = {"BroadcastFirst", "Shuffle", "UMin", "Elect", "All", "Any", "Ballot", "BallotBitCount",
   "BallotExclusiveBitCount", "BallotInclusiveBitCount", "Or", "And", "BallotFindLSB", "UMax", "FAdd", "ExclusiveAdd",
   "FMin", "FMax", "InclusiveAdd", "SubgroupInvocationID", "AllEqual", "BallotFindMSB", "Add(1)", "Broadcast(7)"};

int main(int argc, char **argv)
{
   if (argc < 3) return 2;
   setvbuf(stdout, NULL, _IONBF, 0);
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   VkPhysicalDevice pd; uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
   vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   const uint32_t G = 256, T = G * 64, NR = 24;
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = (VkDeviceSize)T * NR * 4, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   VkBuffer buf; CK(vkCreateBuffer(dev, &bc, NULL, &buf));
   VkMemoryRequirements r; vkGetBufferMemoryRequirements(dev, buf, &r);
   uint32_t t = 0; for (; t < mp.memoryTypeCount; t++) if ((r.memoryTypeBits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = r.size, .memoryTypeIndex = t};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, buf, m, 0));
   uint32_t *res; CK(vkMapMemory(dev, m, 0, VK_WHOLE_SIZE, 0, (void **)&res));

   lancer(q, argv[1], G, buf);
   int faux[24] = {0}, total = 0, montre = 0;
   for (uint32_t sg = 0; sg < T / 32; sg++) {
      uint32_t v[32], act[32]; float fv[32];
      for (int l = 0; l < 32; l++) {
         uint32_t gid = sg * 32 + l;
         v[l] = (uint32_t)(gid * 2654435761u) >> 7;
         fv[l] = (float)(v[l] & 1023u) * 0.25f - 100.0f;
         act[l] = (v[l] % 3u) != 0u;
      }
      int first = -1; uint32_t mn = ~0u, mx = 0, orv = 0, andv = ~0u, bal = 0, add1 = 0, alle = 1, all = 1, any = 0;
      float fsum = 0, fmn = INFINITY, fmx = -INFINITY; uint32_t e0 = 0;
      for (int l = 0; l < 32; l++) if (act[l]) {
         if (first < 0) { first = l; e0 = v[l] >> 30; }
         if (v[l] < mn) mn = v[l]; if (v[l] > mx) mx = v[l];
         orv |= v[l] & 0xffu; andv &= v[l] | 0xffffff00u;
         if (v[l] & 1u) bal |= 1u << l;
         add1++; fsum += fv[l]; if (fv[l] < fmn) fmn = fv[l]; if (fv[l] > fmx) fmx = fv[l];
         if ((v[l] & 1u) != 0u) all = 0; if ((v[l] & 7u) == 5u) any = 1;
         if ((v[l] >> 30) != e0) alle = 0;
      }
      uint32_t pre = 0;
      for (int l = 0; l < 32; l++) {
         uint32_t *o = &res[(sg * 32 + l) * NR];
         uint32_t e[24];
         if (!act[l]) { for (int k = 0; k < 24; k++) e[k] = 0xdeadbeefu; }
         else {
            int src = (l + 5) & 31;
            e[0] = v[first]; e[1] = act[src] ? v[src] : o[1]; /* lane source inactive : indefini */
            e[2] = mn; e[3] = l == first; e[4] = all; e[5] = any; e[6] = bal;
            e[7] = __builtin_popcount(bal); e[8] = __builtin_popcount(bal & ((1u << l) - 1u));
            e[9] = __builtin_popcount(bal & (l == 31 ? ~0u : ((2u << l) - 1u)));
            e[10] = orv; e[11] = andv; e[12] = bal ? __builtin_ctz(bal) : 0xffffffffu; e[13] = mx;
            memcpy(&e[14], &fsum, 4); e[15] = pre; memcpy(&e[16], &fmn, 4); memcpy(&e[17], &fmx, 4);
            e[18] = pre + (v[l] & 0xffu); e[19] = l; e[20] = alle;
            e[21] = bal ? 31 - __builtin_clz(bal) : 0xffffffffu; e[22] = add1;
            e[23] = act[7] ? v[7] : o[23];
            if (!bal) { e[12] = o[12]; e[21] = o[21]; } /* indefini sans bit */
            pre += v[l] & 0xffu;
         }
         for (int k = 0; k < 24; k++) if (o[k] != e[k]) {
            faux[k]++; total++;
            if (montre++ < 8) printf("  lane %u.%d %s : obtenu %#x attendu %#x\n", sg, l, noms[k], o[k], e[k]);
         }
      }
   }
   for (int k = 0; k < 24; k++) if (faux[k]) printf("  %-24s %d faux\n", noms[k], faux[k]);
   printf("vague (divergent, %u lanes) : %d faux\n", T, total);

   memset(res, 0, (size_t)T * NR * 4);
   lancer(q, argv[2], G, buf);
   int fq = 0;
   for (uint32_t gid = 0; gid < T; gid++) {
      uint32_t l = gid & 31u, base = gid - l;
      uint32_t e[4] = {(base + (l ^ 1u)) * 7u + 3u, (base + (l ^ 2u)) * 7u + 3u, (base + (l ^ 3u)) * 7u + 3u, (base + ((l & ~3u) | 2u)) * 7u + 3u};
      for (int k = 0; k < 4; k++) if (res[gid * 4 + k] != e[k]) { if (fq++ < 4) printf("  quad %u.%d : obtenu %u attendu %u\n", gid, k, res[gid * 4 + k], e[k]); }
   }
   printf("quad : %d faux\n", fq);
   printf("RESULTAT : %d faux\n", total + fq);
   return 0;
}
