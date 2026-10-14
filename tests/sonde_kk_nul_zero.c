/* Sonde KosmicKrisp (correctifs 0135 et 0136) : un nuanceur de calcul lit une vraie texture
 * et un descripteur nul (robustness2.nullDescriptor) par textureLod, texelFetch et
 * textureGather, et calcule min/max sur des zeros signes, des NaN et des infinis sous
 * SignedZeroInfNanPreserve. Attendu : texture 0,25 par composante, nul -> 0, min/max exacts.
 *   sonde_kk_nul_zero <sonde.spv> */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)
static VkDevice dev; static VkPhysicalDevice pd;
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
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = memtype(mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0)); CK(vkMapMemory(dev, m, 0, sz, 0, map));
   return b;
}
int main(int argc, char **argv) {
   if (argc < 2) return 2;
   FILE *f = fopen(argv[1], "rb"); if (!f) return 2;
   fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != (size_t)n) return 2; fclose(f);
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   VkPhysicalDeviceRobustness2FeaturesEXT rob = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT, .nullDescriptor = VK_TRUE};
   VkPhysicalDeviceVulkan12Features v12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &rob,
      .runtimeDescriptorArray = VK_TRUE, .descriptorBindingPartiallyBound = VK_TRUE, .shaderSampledImageArrayNonUniformIndexing = VK_TRUE};
   const char *ext[] = {"VK_EXT_robustness2"};
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &v12, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc, .enabledExtensionCount = 1, .ppEnabledExtensionNames = ext};
   CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);

   VkImageCreateInfo ic = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
      .extent = {4, 4, 1}, .mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED};
   VkImage img; CK(vkCreateImage(dev, &ic, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = memtype(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   VkDeviceMemory im; CK(vkAllocateMemory(dev, &ai, NULL, &im)); CK(vkBindImageMemory(dev, img, im, 0));
   VkImageViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = ic.format,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   VkImageView view; CK(vkCreateImageView(dev, &vc, NULL, &view));
   VkSamplerCreateInfo sci = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .magFilter = VK_FILTER_LINEAR, .minFilter = VK_FILTER_LINEAR};
   VkSampler smp; CK(vkCreateSampler(dev, &sci, NULL, &smp));

   float *up; VkBuffer ub = mkbuf(256, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, (void **)&up);
   for (int i = 0; i < 64; i++) up[i] = 0.25f;
   float nz = -0.0f, inf = INFINITY, nan_ = NAN, nnan; uint32_t nb = 0xffc00000; memcpy(&nnan, &nb, 4);
   float pairs[] = {nz, 0.0f, 0.0f, nz, nan_, 1.0f, 1.0f, nan_, nnan, -1.0f, -1.0f, nnan, inf, inf, 2.0f, 3.0f, -2.0f, -2.0f, nz, nz};
   const int NP = sizeof(pairs) / 8;
   float attendu_min[] = {nz, nz, 1.0f, 1.0f, -1.0f, -1.0f, inf, 2.0f, -2.0f, nz};
   float attendu_max[] = {0.0f, 0.0f, 1.0f, 1.0f, -1.0f, -1.0f, inf, 3.0f, -2.0f, nz};
   float *inp; VkBuffer ib = mkbuf(sizeof(pairs), VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, (void **)&inp); memcpy(inp, pairs, sizeof(pairs));
   float *out; VkBuffer ob = mkbuf(64 * 16 * 3 + NP * 8, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, (void **)&out);
   memset(out, 0xab, 64 * 16 * 3 + NP * 8);

   VkDescriptorSetLayoutBinding bd[4] = {{0, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 2, VK_SHADER_STAGE_COMPUTE_BIT},
      {1, VK_DESCRIPTOR_TYPE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT}, {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 4, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &pipe));
   VkDescriptorPoolSize ps[3] = {{VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 2}, {VK_DESCRIPTOR_TYPE_SAMPLER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 2}};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 3, .pPoolSizes = ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorImageInfo ii2[2] = {{VK_NULL_HANDLE, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}, {VK_NULL_HANDLE, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}};
   VkDescriptorImageInfo si2 = {smp, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED};
   VkDescriptorBufferInfo bo = {ob, 0, VK_WHOLE_SIZE}, bi = {ib, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wd[4] = {
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0, .descriptorCount = 2, .descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .pImageInfo = ii2},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER, .pImageInfo = &si2},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 2, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bo},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 3, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bi}};
   vkUpdateDescriptorSets(dev, 4, wd, 0, NULL);

   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   VkImageMemoryBarrier b1 = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
   VkBufferImageCopy rg = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}, .imageExtent = {4, 4, 1}};
   vkCmdCopyBufferToImage(cb, ub, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &rg);
   VkImageMemoryBarrier b2 = b1; b2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b2.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
   b2.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b2.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &b2);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, 1, 1, 1);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));

   int faux = 0;
   const char *op[3] = {"textureLod", "texelFetch", "textureGather"};
   for (int k = 0; k < 3; k++)
      for (int i = 0; i < 64; i++) {
         float *v = out + (k * 64 + i) * 4; float e = (i & 1) ? 0.0f : 0.25f;
         if (v[0] != e || v[1] != e || v[2] != e || v[3] != e) {
            if (faux < 8) printf("FAUX %s fil %d (%s) : %g %g %g %g\n", op[k], i, (i & 1) ? "nul" : "vrai", v[0], v[1], v[2], v[3]);
            faux++;
         }
      }
   uint32_t *mm = (uint32_t *)(out + 64 * 4 * 3);
   for (int i = 0; i < NP; i++) {
      uint32_t emn, emx; memcpy(&emn, &attendu_min[i], 4); memcpy(&emx, &attendu_max[i], 4);
      if (mm[2 * i] != emn || mm[2 * i + 1] != emx) {
         uint32_t a, b; memcpy(&a, &pairs[2 * i], 4); memcpy(&b, &pairs[2 * i + 1], 4);
         printf("FAUX min/max (%08x,%08x) : min=%08x (attendu %08x) max=%08x (attendu %08x)\n", a, b, mm[2 * i], emn, mm[2 * i + 1], emx);
         faux++;
      }
   }
   const char *a = getenv("CIDRE_TEXTURES_NULLES_SANS_BRANCHE"), *z = getenv("CIDRE_MINMAX_ZERO_ENTIER");
   printf("RESULTAT nul_sans_branche=%s zero_entier=%s : %d faux sur %d\n", a ? "oui" : "non", z ? "oui" : "non", faux, 3 * 64 + NP);
   return faux ? 3 : 0;
}
