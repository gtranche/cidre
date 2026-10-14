/* Sonde KosmicKrisp : atomiques 64 bits sur image (VK_EXT_shader_image_atomic_int64,
 * CIDRE_ATOMIQUES_64, M2 et suivants), comme vkd3d-proton les sert a Nanite : une image
 * R32G32_UINT a format mutable, vue en R64_UINT. imageAtomicMax/Min 64 bits sans valeur
 * rendue, imageStore et imageLoad 64 bits.
 *   sonde_img64_vk <img64.spv> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

int main(int argc, char **argv) {
   if (argc < 2) return 2;
   FILE *f = fopen(argv[1], "rb"); if (!f) return 2;
   fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(n); if (fread(code, 1, n, f) != (size_t)n) return 2; fclose(f);
   VkApplicationInfo ap = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ap};
   VkInstance in; CK(vkCreateInstance(&ii, NULL, &in));
   VkPhysicalDevice pd; uint32_t c = 1; vkEnumeratePhysicalDevices(in, &c, &pd);
   VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT ia = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_IMAGE_ATOMIC_INT64_FEATURES_EXT};
   VkPhysicalDeviceFeatures2 f2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &ia};
   vkGetPhysicalDeviceFeatures2(pd, &f2);
   VkFormatProperties3 fp3 = {.sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_3};
   VkFormatProperties2 fp = {.sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &fp3};
   vkGetPhysicalDeviceFormatProperties2(pd, VK_FORMAT_R64_UINT, &fp);
   printf("annonce : shaderImageInt64Atomics=%u ; R64_UINT optimal : stockage %d, atomique %d\n", ia.shaderImageInt64Atomics,
          !!(fp3.optimalTilingFeatures & VK_FORMAT_FEATURE_2_STORAGE_IMAGE_BIT), !!(fp3.optimalTilingFeatures & VK_FORMAT_FEATURE_2_STORAGE_IMAGE_ATOMIC_BIT));
   if (!ia.shaderImageInt64Atomics) { printf("RESULTAT : non annonce\n"); return 3; }

   VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT ea = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_IMAGE_ATOMIC_INT64_FEATURES_EXT, .shaderImageInt64Atomics = VK_TRUE};
   VkPhysicalDeviceFeatures2 e2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &ea, .features = {.shaderInt64 = VK_TRUE}};
   const char *ext[] = {"VK_EXT_shader_image_atomic_int64"};
   float pr = 1.f; VkDeviceQueueCreateInfo qc = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &pr};
   VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &e2, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qc, .enabledExtensionCount = 1, .ppEnabledExtensionNames = ext};
   VkDevice dev; CK(vkCreateDevice(pd, &dc, NULL, &dev)); VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);

   VkFormat vues[2] = {VK_FORMAT_R32G32_UINT, VK_FORMAT_R64_UINT};
   VkImageFormatListCreateInfo fl = {.sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO, .viewFormatCount = 2, .pViewFormats = vues};
   VkImageCreateInfo ic = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = &fl, .flags = VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT,
      .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R32G32_UINT, .extent = {8, 1, 1}, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   VkImage img; CK(vkCreateImage(dev, &ic, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   uint32_t t = 0; for (; t < mp.memoryTypeCount; t++) if (mr.memoryTypeBits & (1u << t)) break;
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = t};
   VkDeviceMemory im; CK(vkAllocateMemory(dev, &ai, NULL, &im)); CK(vkBindImageMemory(dev, img, im, 0));
   VkImageViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R64_UINT,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   VkImageView view; CK(vkCreateImageView(dev, &vc, NULL, &view));

   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = 64, .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   VkBuffer buf; CK(vkCreateBuffer(dev, &bc, NULL, &buf));
   VkMemoryRequirements br; vkGetBufferMemoryRequirements(dev, buf, &br);
   for (t = 0; t < mp.memoryTypeCount; t++) if ((br.memoryTypeBits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo bai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = br.size, .memoryTypeIndex = t};
   VkDeviceMemory bm; CK(vkAllocateMemory(dev, &bai, NULL, &bm)); CK(vkBindBufferMemory(dev, buf, bm, 0));
   uint64_t *p; CK(vkMapMemory(dev, bm, 0, 64, 0, (void **)&p));
   memset(p, 0, 64); p[1] = ~0ull; p[3] = 0x77;

   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkDescriptorSetLayoutBinding bd = {0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline pipe; VkResult r = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &pipe);
   if (r) { printf("RESULTAT : pipeline refuse (%d)\n", r); return 3; }
   VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorImageInfo dii = {VK_NULL_HANDLE, view, VK_IMAGE_LAYOUT_GENERAL};
   VkWriteDescriptorSet wd = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &dii};
   vkUpdateDescriptorSets(dev, 1, &wd, 0, NULL);

   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   VkImageMemoryBarrier b1 = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_GENERAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
   VkBufferImageCopy rg = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}, .imageExtent = {8, 1, 1}};
   vkCmdCopyBufferToImage(cb, buf, img, VK_IMAGE_LAYOUT_GENERAL, 1, &rg);
   VkMemoryBarrier mb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, 1, 1, 1);
   VkMemoryBarrier mb2 = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 1, &mb2, 0, NULL, 0, NULL);
   vkCmdCopyImageToBuffer(cb, img, VK_IMAGE_LAYOUT_GENERAL, buf, 1, &rg);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));

   uint64_t att[5] = {64 + (1ull << 40), 1 + (1ull << 40), 0x123456789abcull, 0x77, 0x78};
   const char *nom[5] = {"imageAtomicMax 64 bits", "imageAtomicMin 64 bits", "imageStore 64 bits", "texel intact", "imageLoad + imageStore 64 bits"};
   int faux = 0;
   for (int k = 0; k < 5; k++) {
      int ok = p[k] == att[k]; faux += !ok;
      printf("  %-30s %s (%#llx, attendu %#llx)\n", nom[k], ok ? "juste" : "FAUX", (unsigned long long)p[k], (unsigned long long)att[k]);
   }
   printf("RESULTAT : %d faux sur 5\n", faux);
   return faux ? 3 : 0;
}
