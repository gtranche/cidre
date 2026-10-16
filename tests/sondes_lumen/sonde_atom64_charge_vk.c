/* Sonde KosmicKrisp : atomiques 64 bits sous charge (CIDRE_ATOMIQUES_64 ; M1 : emulees ;
 * CIDRE_ATOMIQUES_64_EMULEES : emulation forcee sur M2+).
 *  1. Visbuffer facon Nanite : image R32G32_UINT a format mutable vue en R64_UINT (comme
 *     vkd3d-proton), 1920x1080, 8,3 M imageAtomicMax 64 bits ; compare au CPU, relu par
 *     imageLoad 64 bits, par la texture R32G32 (chemin SRV) et par copie. Cout compare a
 *     imageAtomicMax 32 bits natif (meme motif), temps GPU par horodatages.
 *  2. Tampon, 16 fils par adresse : add avec valeur rendue, CAS en boucle, max avec valeur
 *     rendue, echange en chaine.
 * Tailles bornees : chaque soumission reste loin du chien de garde du GPU (le M1 a
 * redemarre sur un banc de contention extreme).
 *   sonde_atom64_charge_vk <dossier des .spv> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

static VkDevice dev;
static VkPhysicalDevice pd;
static VkQueue q;
static VkPhysicalDeviceMemoryProperties mp;
static VkCommandPool cpool;
static VkQueryPool qp;
static double ts_ns;
static const char *dir;

struct pc { uint32_t w, h, iters, mode; };

static uint32_t hash_c(uint32_t x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16; return x; }

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags want)
{
   for (uint32_t t = 0; t < mp.memoryTypeCount; t++)
      if ((bits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & want) == want) return t;
   printf("ECHEC type memoire\n"); exit(1);
}

static VkBuffer make_buffer(VkDeviceSize size, void **map)
{
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
      .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements r; vkGetBufferMemoryRequirements(dev, b, &r);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = r.size,
      .memoryTypeIndex = mem_type(r.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0));
   CK(vkMapMemory(dev, m, 0, size, 0, map));
   memset(*map, 0, size);
   return b;
}

static VkPipeline make_pipe(const char *name, VkPipelineLayout lay)
{
   char path[1024]; snprintf(path, sizeof(path), "%s/%s.spv", dir, name);
   FILE *f = fopen(path, "rb"); if (!f) { printf("ECHEC %s\n", path); exit(1); }
   fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != (size_t)n) exit(1); fclose(f);
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline p; VkResult r = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &p);
   if (r) { printf("RESULTAT : pipeline %s refuse (%d)\n", name, r); exit(3); }
   return p;
}

static VkCommandBuffer begin(void)
{
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   return cb;
}

static void submit(VkCommandBuffer cb)
{
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));
   vkFreeCommandBuffers(dev, cpool, 1, &cb);
}

static void barrier(VkCommandBuffer cb)
{
   VkMemoryBarrier mb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
}

/* Temps GPU d'un dispatch (horodatages autour). */
static double timed_dispatch(VkPipeline p, VkPipelineLayout lay, VkDescriptorSet ds, const void *pcv, uint32_t pcs, uint32_t groups)
{
   VkCommandBuffer cb = begin();
   vkCmdResetQueryPool(cb, qp, 0, 2);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdPushConstants(cb, lay, VK_SHADER_STAGE_COMPUTE_BIT, 0, pcs, pcv);
   vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, qp, 0);
   vkCmdDispatch(cb, groups, 1, 1);
   vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, qp, 1);
   barrier(cb);
   struct timespec a, z; clock_gettime(CLOCK_MONOTONIC, &a);
   submit(cb);
   clock_gettime(CLOCK_MONOTONIC, &z);
   /* Horodatages KK nuls ici : temps mur de la soumission (comprend ~0,2 ms de surcout fixe). */
   return (z.tv_sec - a.tv_sec) * 1e3 + (z.tv_nsec - a.tv_nsec) / 1e6;
}

static VkImage make_image(VkFormat fmt, const VkFormat *views, uint32_t nviews, uint32_t w, uint32_t h)
{
   VkImageFormatListCreateInfo fl = {.sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO, .viewFormatCount = nviews, .pViewFormats = views};
   VkImageCreateInfo ic = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = nviews ? &fl : NULL,
      .flags = nviews ? VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT : 0,
      .imageType = VK_IMAGE_TYPE_2D, .format = fmt, .extent = {w, h, 1}, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   VkImage img; CK(vkCreateImage(dev, &ic, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size,
      .memoryTypeIndex = mem_type(mr.memoryTypeBits, 0)};
   VkDeviceMemory im; CK(vkAllocateMemory(dev, &ai, NULL, &im)); CK(vkBindImageMemory(dev, img, im, 0));
   VkCommandBuffer cb = begin();
   VkImageMemoryBarrier b1 = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_GENERAL,
      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
   submit(cb);
   return img;
}

static VkImageView make_view(VkImage img, VkFormat fmt)
{
   VkImageViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = fmt,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   VkImageView v; CK(vkCreateImageView(dev, &vc, NULL, &v));
   return v;
}

static void clear_image(VkImage img)
{
   VkCommandBuffer cb = begin();
   VkClearColorValue z = {0};
   VkImageSubresourceRange r = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
   vkCmdClearColorImage(cb, img, VK_IMAGE_LAYOUT_GENERAL, &z, 1, &r);
   barrier(cb);
   submit(cb);
}

static int cmp_d(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }

int main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   dir = argc > 1 ? argv[1] : ".";
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd, &props);
   ts_ns = props.limits.timestampPeriod;
   VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT ia = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_IMAGE_ATOMIC_INT64_FEATURES_EXT};
   VkPhysicalDeviceVulkan12Features v12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &ia};
   VkPhysicalDeviceFeatures2 f2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v12};
   vkGetPhysicalDeviceFeatures2(pd, &f2);
   printf("%s : shaderBufferInt64Atomics=%u shaderImageInt64Atomics=%u\n", props.deviceName,
          v12.shaderBufferInt64Atomics, ia.shaderImageInt64Atomics);
   if (!v12.shaderBufferInt64Atomics || !ia.shaderImageInt64Atomics) { printf("RESULTAT : non annonce\n"); return 3; }

   VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT ea = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_IMAGE_ATOMIC_INT64_FEATURES_EXT, .shaderImageInt64Atomics = VK_TRUE};
   VkPhysicalDeviceVulkan12Features e12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &ea, .shaderBufferInt64Atomics = VK_TRUE, .hostQueryReset = VK_TRUE};
   VkPhysicalDeviceFeatures2 e2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &e12, .features = {.shaderInt64 = VK_TRUE}};
   const char *ext[] = {"VK_EXT_shader_image_atomic_int64"};
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &e2, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc, .enabledExtensionCount = 1, .ppEnabledExtensionNames = ext};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); vkGetDeviceQueue(dev, 0, 0, &q);
   vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkQueryPoolCreateInfo qpi = {.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO, .queryType = VK_QUERY_TYPE_TIMESTAMP, .queryCount = 2};
   CK(vkCreateQueryPool(dev, &qpi, NULL, &qp));
   int faux_total = 0;

   /* ---- 1. visbuffer ---- */
   const uint32_t W = 1920, H = 1080, NPIX = W * H, ITERS = 4, THREADS = NPIX;
   VkFormat vues[2] = {VK_FORMAT_R32G32_UINT, VK_FORMAT_R64_UINT};
   VkImage vis = make_image(VK_FORMAT_R32G32_UINT, vues, 2, W, H);
   VkImageView vis64 = make_view(vis, VK_FORMAT_R64_UINT);
   VkImageView visrg = make_view(vis, VK_FORMAT_R32G32_UINT);
   VkImage vis32 = make_image(VK_FORMAT_R32_UINT, NULL, 0, W, H);
   VkImageView vis32v = make_view(vis32, VK_FORMAT_R32_UINT);
   void *m_img, *m_tex, *m_copy;
   VkBuffer b_img = make_buffer((VkDeviceSize)NPIX * 8, &m_img);
   VkBuffer b_tex = make_buffer((VkDeviceSize)NPIX * 8, &m_tex);
   VkBuffer b_copy = make_buffer((VkDeviceSize)NPIX * 8, &m_copy);

   VkSamplerCreateInfo sci = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .magFilter = VK_FILTER_NEAREST, .minFilter = VK_FILTER_NEAREST,
      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE};
   VkSampler smp; CK(vkCreateSampler(dev, &sci, NULL, &smp));

   VkDescriptorSetLayoutBinding bd[4] = {
      {0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 4, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPushConstantRange pcr = {VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(struct pc)};
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkPipeline p_vis64 = make_pipe("vis64", lay), p_vis32 = make_pipe("vis32", lay), p_lire = make_pipe("lire64", lay);

   VkDescriptorPoolSize ps[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 4}, {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 16}};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 4, .poolSizeCount = 3, .pPoolSizes = ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetLayout two[2] = {dsl, dsl};
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 2, .pSetLayouts = two};
   VkDescriptorSet ds[2]; CK(vkAllocateDescriptorSets(dev, &da, ds));
   for (int s = 0; s < 2; s++) {
      VkDescriptorImageInfo st = {VK_NULL_HANDLE, s ? vis32v : vis64, VK_IMAGE_LAYOUT_GENERAL};
      VkDescriptorImageInfo sa = {smp, visrg, VK_IMAGE_LAYOUT_GENERAL};
      VkDescriptorBufferInfo o1 = {b_img, 0, VK_WHOLE_SIZE}, o2 = {b_tex, 0, VK_WHOLE_SIZE};
      VkWriteDescriptorSet wd[4] = {
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &st},
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &sa},
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 2, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &o1},
         {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds[s], .dstBinding = 3, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &o2}};
      vkUpdateDescriptorSets(dev, 4, wd, 0, NULL);
   }
   struct pc pcv = {W, H, ITERS, 0};

   /* Justesse. */
   clear_image(vis);
   double t64 = timed_dispatch(p_vis64, lay, ds[0], &pcv, sizeof(pcv), THREADS / 64);
   VkCommandBuffer cb = begin();
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p_lire);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds[0], 0, NULL);
   vkCmdPushConstants(cb, lay, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(pcv), &pcv);
   vkCmdDispatch(cb, (NPIX + 63) / 64, 1, 1);
   barrier(cb);
   VkBufferImageCopy rg = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}, .imageExtent = {W, H, 1}};
   vkCmdCopyImageToBuffer(cb, vis, VK_IMAGE_LAYOUT_GENERAL, b_copy, 1, &rg);
   barrier(cb);
   submit(cb);

   uint64_t *ref = calloc(NPIX, 8);
   for (uint32_t tid = 0; tid < THREADS; tid++)
      for (uint32_t i = 0; i < ITERS; i++) {
         uint32_t hh = hash_c(tid * 7919u + i * 104729u);
         uint32_t pix = (tid / 4u + i * 37u) % NPIX;
         uint64_t v = ((uint64_t)hash_c(hh) << 32) | (uint64_t)(tid * ITERS + i);
         if (v > ref[pix]) ref[pix] = v;
      }
   uint64_t *gi = m_img, *gt = m_tex, *gc = m_copy;
   uint32_t f_img = 0, f_tex = 0, f_copy = 0, touches = 0;
   for (uint32_t p = 0; p < NPIX; p++) {
      f_img += gi[p] != ref[p]; f_tex += gt[p] != ref[p]; f_copy += gc[p] != ref[p]; touches += ref[p] != 0;
   }
   printf("visbuffer %ux%u, %u imageAtomicMax 64 bits sur %u pixels (%.2f ms) :\n", W, H, THREADS * ITERS, touches, t64);
   printf("  relu par imageLoad 64 bits : %u faux\n", f_img);
   printf("  relu par la texture R32G32 : %u faux\n", f_tex);
   printf("  relu par copie image->tampon : %u faux\n", f_copy);
   faux_total += f_img + f_tex + f_copy;

   /* Cout : 7 manches entrelacees, mediane du temps GPU. */
   double a64[7], a32[7];
   for (int r = 0; r < 7; r++) {
      clear_image(vis);
      a64[r] = timed_dispatch(p_vis64, lay, ds[0], &pcv, sizeof(pcv), THREADS / 64);
      clear_image(vis32);
      a32[r] = timed_dispatch(p_vis32, lay, ds[1], &pcv, sizeof(pcv), THREADS / 64);
   }
   qsort(a64, 7, sizeof(double), cmp_d); qsort(a32, 7, sizeof(double), cmp_d);
   printf("  cout (mediane, temps mur) : 64 bits %.2f ms, 32 bits natif %.2f ms, rapport %.1fx\n", a64[3], a32[3], a64[3] / a32[3]);

   /* ---- 2. tampon ---- */
   {
      const uint32_t N = 16384, K = 1024, PAR = N / K;
      void *m_b, *m_a, *m_x, *m_m;
      VkBuffer bb = make_buffer(4 * K * 8, &m_b);
      VkBuffer ba = make_buffer(N * 8, &m_a), bx = make_buffer(N * 8, &m_x), bm = make_buffer(N * 8, &m_m);
      VkDescriptorSetLayoutBinding bd2[4];
      for (int i = 0; i < 4; i++) bd2[i] = (VkDescriptorSetLayoutBinding){i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT};
      VkDescriptorSetLayoutCreateInfo dl2 = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 4, .pBindings = bd2};
      VkDescriptorSetLayout dsl2; CK(vkCreateDescriptorSetLayout(dev, &dl2, NULL, &dsl2));
      VkPushConstantRange pcr2 = {VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
      VkPipelineLayoutCreateInfo pl2 = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl2, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr2};
      VkPipelineLayout lay2; CK(vkCreatePipelineLayout(dev, &pl2, NULL, &lay2));
      VkPipeline p_buf = make_pipe("buf64", lay2);
      VkDescriptorSetAllocateInfo da2 = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl2};
      VkDescriptorSet ds2; CK(vkAllocateDescriptorSets(dev, &da2, &ds2));
      VkBuffer bufs[4] = {bb, ba, bx, bm};
      VkDescriptorBufferInfo bi[4]; VkWriteDescriptorSet wd[4];
      for (int i = 0; i < 4; i++) {
         bi[i] = (VkDescriptorBufferInfo){bufs[i], 0, VK_WHOLE_SIZE};
         wd[i] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds2, .dstBinding = i, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bi[i]};
      }
      vkUpdateDescriptorSets(dev, 4, wd, 0, NULL);
      uint64_t *B = m_b, *somme = B, *compteur = B + K, *maxi = B + 2 * K, *chaine = B + 3 * K;
      for (uint32_t i = 0; i < K; i++) somme[i] = 0xFFFFFFF0ull;
      const char *noms[4] = {"add rendu", "CAS en boucle", "max rendu", "echange"};
      printf("tampon : %u fils, %u adresses, %u fils par adresse :\n", N, K, PAR);
      for (uint32_t mode = 0; mode < 4; mode++)
         printf("  %-16s %6.2f ms\n", noms[mode], timed_dispatch(p_buf, lay2, ds2, &mode, 4, N / 64));
      int f = 0, dbl = 0;
      for (uint32_t i = 0; i < K; i++) f += somme[i] != 0xFFFFFFF0ull + (uint64_t)PAR * 0x100000001ull;
      uint8_t *vu = calloc(N, 1); uint64_t *ra = m_a;
      for (uint32_t tid = 0; tid < N; tid++) {
         uint64_t d = ra[tid] - 0xFFFFFFF0ull, k = d / 0x100000001ull;
         if (d % 0x100000001ull || k >= PAR) { dbl++; continue; }
         if (vu[k * K + (tid % K)]++) dbl++;
      }
      printf("  add 64 avec retenue : %d sommes fausses, %d valeurs rendues fausses ou en double\n", f, dbl);
      int fc = 0;
      for (uint32_t i = 0; i < K; i++) fc += compteur[i] != (uint64_t)PAR * 0xFFFFFFFFull;
      printf("  CAS 64 en boucle : %d compteurs faux\n", fc);
      int fm = 0; uint64_t *rm = m_m;
      for (uint32_t i = 0; i < K; i++) {
         uint64_t best = 0;
         for (uint32_t tid = i; tid < N; tid += K) { uint64_t v = ((uint64_t)tid << 32) | (uint32_t)~tid; if (v > best) best = v; }
         fm += maxi[i] != best;
      }
      for (uint32_t tid = 0; tid < N; tid++) {
         uint64_t r = rm[tid];
         if (r == 0) continue;
         uint32_t t = (uint32_t)(r >> 32);
         fm += (t % K) != (tid % K) || (uint32_t)r != (uint32_t)~t || r > maxi[tid % K] || t == tid;
      }
      printf("  max 64 avec valeur rendue : %d faux\n", fm);
      /* echange : par adresse, les valeurs rendues + la finale = {0} U {tid+1 des fils de l'adresse}. */
      int fx = 0; uint64_t *rx = m_x; uint8_t *vx = calloc(N + 1, 1);
      for (uint32_t tid = 0; tid < N; tid++) {
         uint64_t r = rx[tid];
         if (r != 0 && (r > N || ((r - 1) % K) != (tid % K) || vx[r]++)) fx++;
      }
      for (uint32_t i = 0; i < K; i++) { uint64_t r = chaine[i]; if (r == 0 || r > N || vx[r]++) fx++; }
      int zeros = 0; for (uint32_t tid = 0; tid < N; tid++) zeros += rx[tid] == 0;
      fx += zeros != (int)K;
      for (uint32_t v = 1; v <= N; v++) fx += vx[v] != 1;
      printf("  echange 64 en chaine : %d faux\n", fx);
      faux_total += f + dbl + fc + fm + fx;
   }

   printf("RESULTAT : %d faux\n", faux_total);
   return faux_total ? 3 : 0;
}
