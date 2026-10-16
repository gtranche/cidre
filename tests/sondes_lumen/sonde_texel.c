/* Sonde KosmicKrisp : atomiques sur tampons texel et images R32 sous charge, comme les
 * nuanceurs UE (listes de tuiles de Lumen) : compteur rendu servant d'indice, vues texel a
 * decalage non aligne, compteurs par tuile 2D, min/max signes.
 *   sonde_texel <texel.spv> [fils] [decalage en texels] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("ECHEC %s -> %d (l.%d)\n", #x, r_, __LINE__); exit(1); } } while (0)

static VkDevice dev;
static VkPhysicalDeviceMemoryProperties mp;

static uint32_t hash_c(uint32_t x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16; return x; }

static uint32_t mtype(uint32_t bits, VkMemoryPropertyFlags f)
{
   for (uint32_t t = 0; t < mp.memoryTypeCount; t++) if ((bits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & f) == f) return t;
   exit(1);
}

static VkBuffer buffer(VkDeviceSize sz, VkBufferUsageFlags u, void **map)
{
   VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = sz, .usage = u};
   VkBuffer b; CK(vkCreateBuffer(dev, &bc, NULL, &b));
   VkMemoryRequirements r; vkGetBufferMemoryRequirements(dev, b, &r);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = r.size, .memoryTypeIndex = mtype(r.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory m; CK(vkAllocateMemory(dev, &ai, NULL, &m)); CK(vkBindBufferMemory(dev, b, m, 0));
   CK(vkMapMemory(dev, m, 0, VK_WHOLE_SIZE, 0, map)); memset(*map, 0, sz);
   return b;
}

static VkBufferView view(VkBuffer b, VkFormat f, VkDeviceSize off, VkDeviceSize range)
{
   VkBufferViewCreateInfo vc = {.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO, .buffer = b, .format = f, .offset = off, .range = range};
   VkBufferView v; CK(vkCreateBufferView(dev, &vc, NULL, &v));
   return v;
}

int main(int argc, char **argv)
{
   if (argc < 2) return 2;
   setvbuf(stdout, NULL, _IONBF, 0);
   const uint32_t N = argc > 2 ? atoi(argv[2]) : 65536, OFF = argc > 3 ? atoi(argv[3]) : 3;
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

   /* Tampons texel : compteur (avec un voisin de garde avant et apres), liste, signes. */
   void *mc, *ml, *ms, *mo;
   const VkBufferUsageFlags TU = VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
   VkBuffer bcpt = buffer(256, TU, &mc), bl = buffer((VkDeviceSize)(N + 64 + OFF) * 4, TU, &ml), bs = buffer(256, TU, &ms);
   VkBuffer bo = buffer((VkDeviceSize)N * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &mo);
   uint32_t *cpt = mc, *lst = ml; int32_t *sg = ms; uint32_t *ro = mo;
   for (int i = 0; i < 64; i++) cpt[i] = 0xa5a5a5a5u;
   cpt[OFF] = 0;
   for (uint32_t i = 0; i < N + 64 + OFF; i++) lst[i] = 0xa5a5a5a5u;
   sg[OFF] = 0x7fffffff; sg[OFF + 1] = (int32_t)0x80000000;
   VkBufferView vcpt = view(bcpt, VK_FORMAT_R32_UINT, OFF * 4, 4 * 4);
   VkBufferView vl = view(bl, VK_FORMAT_R32_UINT, OFF * 4, (VkDeviceSize)N * 4);
   VkBufferView vs = view(bs, VK_FORMAT_R32_SINT, OFF * 4, 2 * 4);

   /* Image 2D R32ui 64x64 de compteurs. */
   VkImageCreateInfo ic = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R32_UINT,
      .extent = {64, 64, 1}, .mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
   VkImage img; CK(vkCreateImage(dev, &ic, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = mtype(mr.memoryTypeBits, 0)};
   VkDeviceMemory im; CK(vkAllocateMemory(dev, &ai, NULL, &im)); CK(vkBindImageMemory(dev, img, im, 0));
   VkImageViewCreateInfo ivc = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R32_UINT,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   VkImageView iv; CK(vkCreateImageView(dev, &ivc, NULL, &iv));
   void *mt; VkBuffer bt = buffer(64 * 64 * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT, &mt);

   VkDescriptorSetLayoutBinding bd[5] = {
      {0, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {1, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {2, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {3, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT},
      {4, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 5, .pBindings = bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dl, NULL, &dsl));
   VkPipelineLayoutCreateInfo pl = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev, &pl, NULL, &lay));
   VkShaderModuleCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &si, NULL, &sm));
   VkComputePipelineCreateInfo cp = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main"}, .layout = lay};
   VkPipeline p; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cp, NULL, &p));
   VkDescriptorPoolSize ps[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 3}, {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
   VkDescriptorPoolCreateInfo dp = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 3, .pPoolSizes = ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev, &dp, NULL, &pool));
   VkDescriptorSetAllocateInfo da = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &da, &ds));
   VkDescriptorImageInfo dii = {VK_NULL_HANDLE, iv, VK_IMAGE_LAYOUT_GENERAL};
   VkDescriptorBufferInfo dbi = {bo, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wd[5] = {
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .pTexelBufferView = &vcpt},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .pTexelBufferView = &vl},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 2, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &dii},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 3, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .pTexelBufferView = &vs},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 4, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi}};
   vkUpdateDescriptorSets(dev, 5, wd, 0, NULL);

   VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo ca = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ca, &cb));
   VkCommandBufferBeginInfo cbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb, &cbi));
   VkImageMemoryBarrier b1 = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_GENERAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
   VkClearColorValue z = {0}; VkImageSubresourceRange rr = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
   vkCmdClearColorImage(cb, img, VK_IMAGE_LAYOUT_GENERAL, &z, 1, &rr);
   VkMemoryBarrier mb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_HOST_READ_BIT};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, lay, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, N / 64, 1, 1);
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
   VkBufferImageCopy rg = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}, .imageExtent = {64, 64, 1}};
   vkCmdCopyImageToBuffer(cb, img, VK_IMAGE_LAYOUT_GENERAL, bt, 1, &rg);
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo sub = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(q, 1, &sub, VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));

   /* 1. liste */
   uint32_t attendus = 0; for (uint32_t g = 0; g < N; g++) attendus += (hash_c(g) & 3u) != 0u;
   int f1 = 0; uint8_t *vu = calloc(N + 1, 1);
   if (cpt[OFF] != attendus) { printf("  compteur : %u, attendu %u\n", cpt[OFF], attendus); f1++; }
   for (int i = 0; i < 64; i++) if (i != OFF && cpt[i] != 0xa5a5a5a5u) { if (f1++ < 3) printf("  compteur : voisin %d ecrase (%#x)\n", i, cpt[i]); }
   for (uint32_t i = 0; i < attendus; i++) {
      uint32_t v = lst[OFF + i];
      if (v == 0 || v > N || (hash_c(v - 1) & 3u) == 0u || vu[v]++) { if (f1++ < 6) printf("  liste[%u] = %#x\n", i, v); }
   }
   for (uint32_t i = 0; i < OFF; i++) if (lst[i] != 0xa5a5a5a5u) { if (f1++ < 8) printf("  liste : garde avant ecrasee [%u]\n", i); }
   for (uint32_t i = OFF + attendus; i < N + 64 + OFF; i++) if (lst[i] != 0xa5a5a5a5u) { if (f1++ < 10) printf("  liste : ecrite au-dela [%u]\n", i); break; }
   printf("liste par compteur texel (decalage %u texels, %u ajouts) : %d faux\n", OFF, attendus, f1);
   /* 2. tuiles */
   uint32_t ref[4096] = {0}; for (uint32_t g = 0; g < N; g++) { uint32_t h = hash_c(g); ref[(h & 63u) + 64 * ((h >> 6) & 63u)]++; }
   uint32_t *tu = mt; int f2 = 0; uint8_t *rv = calloc((size_t)4096 * 65536 / 8 + 1, 1);
   for (int i = 0; i < 4096; i++) if (tu[i] != ref[i]) { if (f2++ < 3) printf("  tuile %d : %u attendu %u\n", i, tu[i], ref[i]); }
   for (uint32_t g = 0; g < N; g++) {
      uint32_t h = hash_c(g), t = (h & 63u) + 64 * ((h >> 6) & 63u), r = ro[g];
      if ((r >> 16) != t || (r & 0xffffu) >= ref[t]) { if (f2++ < 6) printf("  rendu tuile fil %u : %#x\n", g, r); continue; }
      size_t bit = (size_t)t * 65536 + (r & 0xffffu);
      if (rv[bit / 8] & (1u << (bit % 8))) { if (f2++ < 6) printf("  rendu tuile en double fil %u\n", g); }
      rv[bit / 8] |= 1u << (bit % 8);
   }
   printf("compteurs par tuile 2D (valeur lue) : %d faux\n", f2);
   /* 3. signes */
   int32_t mn = 0x7fffffff, mx = (int32_t)0x80000000;
   for (uint32_t g = 0; g < N; g++) { int32_t s = (int32_t)hash_c(g) >> 8; if (s < mn) mn = s; if (s > mx) mx = s; }
   int f3 = (sg[OFF] != mn) + (sg[OFF + 1] != mx);
   if (f3) printf("  min %d attendu %d ; max %d attendu %d\n", sg[OFF], mn, sg[OFF + 1], mx);
   printf("min/max signes sur tampon texel : %d faux\n", f3);
   printf("RESULTAT : %d faux\n", f1 + f2 + f3);
   return 0;
}
