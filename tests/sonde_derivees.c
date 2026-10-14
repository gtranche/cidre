/* Sonde KosmicKrisp : derivees dans les nuanceurs de calcul (VK_KHR_compute_shader_derivatives,
 * CIDRE_DERIVEES_CALCUL). Deux nuanceurs : groupes de derivees en quads (8x8) et lineaires (64).
 * Chacun calcule dFdxFine/dFdyFine/dFdxCoarse/dFdyCoarse d'une fonction non lineaire de la position,
 * compares au calcul exact ; le nuanceur en quads lit aussi une texture a LOD implicite (niveau 2
 * attendu, 3 avec un biais de 1 : chaque niveau de mip vaut 10 x son numero).
 *   sonde_derivees <quads.spv> <lineaire.spv>   (sh tests/build_sondes_sm66.sh) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)
static VkDevice dev; static VkPhysicalDevice pd; static VkQueue q; static VkCommandPool cpool;

static uint32_t memtype(uint32_t bits, VkMemoryPropertyFlags want) {
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   for (uint32_t t = 0; t < mp.memoryTypeCount; t++)
      if ((bits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & want) == want) return t;
   return 0;
}
static VkBuffer mkbuf(VkDeviceSize sz, VkBufferUsageFlags u, void **map) {
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = sz, .usage = u};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, b, &mr);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size,
      .memoryTypeIndex = memtype(mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0)); CK(vkMapMemory(dev, m, 0, sz, 0, map));
   return b;
}
static uint32_t *lire(const char *f, size_t *n) {
   FILE *fp = fopen(f, "rb"); if (!fp) { printf("pas de %s\n", f); exit(2); }
   fseek(fp, 0, SEEK_END); *n = ftell(fp); fseek(fp, 0, SEEK_SET);
   uint32_t *c = malloc(*n); if (fread(c, 1, *n, fp) != *n) exit(2); fclose(fp); return c;
}
static VkCommandBuffer debut(void) {
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo bi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &bi));
   return cb;
}
static void fin(VkCommandBuffer cb) {
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo s = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &s, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));
}

static float fq(int x, int y) { return x * x * 3.0f + y * y * 7.0f + x * y; }
static float fl(int i) { return (float)(i * i) * 0.5f + (float)i; }

int main(int argc, char **argv) {
   if (argc < 3) return 2;
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   VkPhysicalDeviceComputeShaderDerivativesFeaturesKHR dq = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_COMPUTE_SHADER_DERIVATIVES_FEATURES_KHR};
   VkPhysicalDeviceFeatures2 f2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &dq};
   vkGetPhysicalDeviceFeatures2(pd, &f2);
   printf("annonce : computeDerivativeGroupQuads=%u computeDerivativeGroupLinear=%u\n", dq.computeDerivativeGroupQuads, dq.computeDerivativeGroupLinear);
   if (!dq.computeDerivativeGroupQuads || !dq.computeDerivativeGroupLinear) { printf("RESULTAT : extension non annoncee\n"); return 3; }
   const char *ext[] = {"VK_NV_compute_shader_derivatives"};
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &dq, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc, .enabledExtensionCount = 1, .ppEnabledExtensionNames = ext};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); vkGetDeviceQueue(dev, 0, 0, &q);
   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));

   /* texture 256x256, 9 niveaux, niveau L = 10*L partout */
   const uint32_t N = 256, L = 9;
   VkImageCreateInfo ic = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
      .extent = {N, N, 1}, .mipLevels = L, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   VkImage img; CK(vkCreateImage(dev, &ic, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = memtype(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   VkDeviceMemory im; CK(vkAllocateMemory(dev, &ai, NULL, &im)); CK(vkBindImageMemory(dev, img, im, 0));
   float *up; VkBuffer ub = mkbuf((VkDeviceSize)N * N * 16 * 2, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, (void **)&up);
   VkBufferImageCopy rg[9]; VkDeviceSize off = 0;
   for (uint32_t l = 0; l < L; l++) {
      uint32_t s = N >> l; for (uint32_t k = 0; k < s * s * 4; k++) up[off / 4 + k] = 10.0f * l;
      rg[l] = (VkBufferImageCopy){.bufferOffset = off, .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, l, 0, 1}, .imageExtent = {s, s, 1}};
      off += (VkDeviceSize)s * s * 16;
   }
   VkCommandBuffer cb = debut();
   VkImageMemoryBarrier b1 = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, L, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
   vkCmdCopyBufferToImage(cb, ub, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, L, rg);
   VkImageMemoryBarrier b2 = b1; b2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b2.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
   b2.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b2.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &b2);
   fin(cb);
   VkImageViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = ic.format,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, L, 0, 1}};
   VkImageView view; CK(vkCreateImageView(dev, &vc, NULL, &view));
   VkSamplerCreateInfo sci = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .magFilter = VK_FILTER_NEAREST, .minFilter = VK_FILTER_NEAREST,
      .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST, .maxLod = 16.0f};
   VkSampler smp; CK(vkCreateSampler(dev, &sci, NULL, &smp));

   float *out; VkBuffer ob = mkbuf(192 * 16, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, (void **)&out);
   VkDescriptorSetLayoutBinding bd[2] = {{0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT}, {1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkDescriptorPoolSize ps[2] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 2, .pPoolSizes = ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorImageInfo dii = {smp, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
   VkDescriptorBufferInfo dbi = {ob, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wd[2] = {{.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &dii},
                                 {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi}};
   vkUpdateDescriptorSets(dev, 2, wd, 0, NULL);

   int faux_total = 0;
   for (int mode = 0; mode < 2; mode++) {
      size_t n; uint32_t *code = lire(argv[1 + mode], &n);
      VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
      VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
      VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
         .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
      VkPipeline pipe; VkResult r = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &pipe);
      if (r) { printf("%s : pipeline refuse (%d)\n", mode ? "lineaire" : "quads", r); faux_total++; continue; }
      memset(out, 0xff, 192 * 16);
      cb = debut();
      vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
      vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
      vkCmdDispatch(cb, 1, 1, 1);
      fin(cb);
      int faux = 0, cas = 0;
      for (int i = 0; i < 64; i++) {
         float e[4];
         if (mode == 0) {
            int x = i % 8, y = i / 8, x0 = x & ~1, y0 = y & ~1;
            e[0] = fq(x0 + 1, y) - fq(x0, y); e[1] = fq(x, y0 + 1) - fq(x, y0);
            e[2] = fq(x0 + 1, y0) - fq(x0, y0); e[3] = fq(x0, y0 + 1) - fq(x0, y0);
         } else {
            int qd = i & ~3;
            e[0] = fl(i | 1) - fl(i & ~1); e[1] = fl(i | 2) - fl(i & ~2);
            e[2] = fl(qd + 1) - fl(qd); e[3] = fl(qd + 2) - fl(qd);
         }
         for (int k = 0; k < 4; k++, cas++)
            if (fabsf(out[i * 4 + k] - e[k]) > 1e-3f) {
               if (faux < 6) printf("  FAUX %s fil %d %s : %g (attendu %g)\n", mode ? "lineaire" : "quads", i,
                                   (const char *[]){"ddx fine", "ddy fine", "ddx grossiere", "ddy grossiere"}[k], out[i * 4 + k], e[k]);
               faux++;
            }
         if (mode == 0) {
            cas += 2;
            if (out[(64 + i) * 4] != 20.0f) { if (faux < 6) printf("  FAUX quads fil %d LOD implicite : %g (attendu 20)\n", i, out[(64 + i) * 4]); faux++; }
            if (out[(128 + i) * 4] != 30.0f) { if (faux < 6) printf("  FAUX quads fil %d LOD + biais 1 : %g (attendu 30)\n", i, out[(128 + i) * 4]); faux++; }
         }
      }
      printf("%s : %d faux sur %d\n", mode ? "lineaire" : "quads", faux, cas);
      faux_total += faux;
   }
   printf("RESULTAT : %d faux\n", faux_total);
   return faux_total ? 3 : 0;
}
