/*
 * Sonde : le pilote decode-t-il BC4 juste ?
 *
 * Le §278 a montre que Surviving Mars ne cree aucun atlas de police classique :
 * son menu charge 1865 textures, presque toutes compressees, dont 372 en BC4 --
 * le format a un canal qu'on emploie pour une police. Le pilote annonce BC4 ;
 * l'annoncer n'est pas le decoder juste.
 *
 * On pose donc un bloc BC4 dont on connait le contenu, on echantillonne ses
 * seize texels, et on compare au decodage que la specification impose. Les deux
 * modes sont eprouves :
 *
 *   rouge0 > rouge1 : huit valeurs interpolees
 *   rouge0 <= rouge1 : six valeurs, plus 0 et 1 aux indices 6 et 7
 *
 * Le second mode est le plus souvent fautif : ses deux valeurs extremes sont un
 * cas particulier qu'un decodeur presse oublie.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <vulkan/vulkan.h>
#include "grille16_spv.h"

#define CHK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
   printf("ECHEC %s -> %d\n", #x, r_); return 1; } } while (0)

static VkDevice dev; static VkPhysicalDevice phys; static VkInstance inst;
static uint32_t qfam; static VkQueue file;

static uint32_t type_memoire(uint32_t bits, VkMemoryPropertyFlags veut)
{
   VkPhysicalDeviceMemoryProperties mp;
   vkGetPhysicalDeviceMemoryProperties(phys, &mp);
   for (uint32_t i = 0; i < mp.memoryTypeCount; ++i)
      if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & veut) == veut) return i;
   return 0;
}

/* Le decodage impose par la specification, en entier, pour servir de reference. */
static void decoder_bc4(const uint8_t bloc[8], double attendu[16])
{
   double r[8];
   uint32_t r0 = bloc[0], r1 = bloc[1];

   r[0] = r0; r[1] = r1;
   if (r0 > r1) {
      for (int i = 1; i <= 6; ++i) r[1 + i] = ((7 - i) * (double)r0 + i * (double)r1) / 7.0;
   } else {
      for (int i = 1; i <= 4; ++i) r[1 + i] = ((5 - i) * (double)r0 + i * (double)r1) / 5.0;
      r[6] = 0.0; r[7] = 255.0;
   }

   uint64_t indices = 0;
   for (int i = 0; i < 6; ++i) indices |= (uint64_t)bloc[2 + i] << (8 * i);
   for (int t = 0; t < 16; ++t)
      attendu[t] = r[(indices >> (3 * t)) & 7u] / 255.0;
}

static int eprouver(const uint8_t bloc[8], const char *quoi,
                    VkImage img, VkDeviceMemory mimg, VkBuffer bsrc, VkDeviceMemory msrc,
                    VkBuffer bdst, VkDeviceMemory mdst, VkCommandBuffer cb,
                    VkPipeline pipe, VkPipelineLayout pl, VkDescriptorSet ds)
{
   void *p;
   CHK(vkMapMemory(dev, msrc, 0, VK_WHOLE_SIZE, 0, &p));
   memcpy(p, bloc, 8); vkUnmapMemory(dev, msrc);

   VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
   CHK(vkBeginCommandBuffer(cb, &bi));
   VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      .image = img, .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
      .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT };
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
   VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { 4, 4, 1 } };
   vkCmdCopyBufferToImage(cb, bsrc, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &c);
   b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
   b.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
   b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, 1, 1, 1);
   CHK(vkEndCommandBuffer(cb));
   VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
   CHK(vkQueueSubmit(file, 1, &si, VK_NULL_HANDLE));
   CHK(vkQueueWaitIdle(file));
   CHK(vkResetCommandBuffer(cb, 0));

   double attendu[16];
   decoder_bc4(bloc, attendu);

   CHK(vkMapMemory(dev, mdst, 0, VK_WHOLE_SIZE, 0, &p));
   const float *f = p;
   int ecarts = 0;
   printf("%s  (rouge0 = %#04x, rouge1 = %#04x)\n", quoi, bloc[0], bloc[1]);
   for (int t = 0; t < 16; ++t) {
      double obtenu = f[t * 4];
      double d = fabs(obtenu - attendu[t]);
      if (d > 2.0 / 255.0) {
         if (ecarts < 8)
            printf("   texel %2d : obtenu %.4f, attendu %.4f   ECART %.4f\n", t, obtenu, attendu[t], d);
         ecarts++;
      }
   }
   vkUnmapMemory(dev, mdst);
   printf("   %s (%d ecarts sur 16)\n\n", ecarts ? "FAUX" : "juste", ecarts);
   return ecarts;
}

int main(void)
{
   float prio = 1.0f;
   VkApplicationInfo ai = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ai };
   uint32_t n = 1;
   CHK(vkCreateInstance(&ici, NULL, &inst));
   vkEnumeratePhysicalDevices(inst, &n, &phys);
   uint32_t nq = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, NULL);
   VkQueueFamilyProperties *qp = malloc(nq * sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, qp);
   for (uint32_t i = 0; i < nq; ++i)
      if (qp[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }
   VkDeviceQueueCreateInfo q = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qfam, .queueCount = 1, .pQueuePriorities = &prio };
   VkPhysicalDeviceFeatures feats = { .textureCompressionBC = VK_TRUE };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1, .pQueueCreateInfos = &q, .pEnabledFeatures = &feats };
   CHK(vkCreateDevice(phys, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qfam, 0, &file);

   VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(phys, &pp);
   printf("pilote : %s\n\n", pp.deviceName);

   VkImage img; VkDeviceMemory mimg;
   VkImageCreateInfo ici2 = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_BC4_UNORM_BLOCK,
      .extent = { 4, 4, 1 }, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
   CHK(vkCreateImage(dev, &ici2, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size, .memoryTypeIndex = type_memoire(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
   CHK(vkAllocateMemory(dev, &mai, NULL, &mimg));
   CHK(vkBindImageMemory(dev, img, mimg, 0));

   VkBuffer bsrc, bdst; VkDeviceMemory msrc, mdst;
   VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = 256, .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT };
   CHK(vkCreateBuffer(dev, &bci, NULL, &bsrc));
   vkGetBufferMemoryRequirements(dev, bsrc, &mr);
   mai.allocationSize = mr.size;
   mai.memoryTypeIndex = type_memoire(mr.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
   CHK(vkAllocateMemory(dev, &mai, NULL, &msrc));
   CHK(vkBindBufferMemory(dev, bsrc, msrc, 0));

   bci.size = 16 * 4 * sizeof(float); bci.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
   CHK(vkCreateBuffer(dev, &bci, NULL, &bdst));
   vkGetBufferMemoryRequirements(dev, bdst, &mr);
   mai.allocationSize = mr.size;
   mai.memoryTypeIndex = type_memoire(mr.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
   CHK(vkAllocateMemory(dev, &mai, NULL, &mdst));
   CHK(vkBindBufferMemory(dev, bdst, mdst, 0));

   VkImageView vue;
   VkImageViewCreateInfo vci = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_BC4_UNORM_BLOCK,
      .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
   CHK(vkCreateImageView(dev, &vci, NULL, &vue));
   VkSampler ech;
   VkSamplerCreateInfo sci = { .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      .magFilter = VK_FILTER_NEAREST, .minFilter = VK_FILTER_NEAREST,
      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE };
   CHK(vkCreateSampler(dev, &sci, NULL, &ech));

   VkDescriptorSetLayoutBinding lb[2] = {
      { 0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL },
      { 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL } };
   VkDescriptorSetLayout dsl;
   VkDescriptorSetLayoutCreateInfo dlci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 2, .pBindings = lb };
   CHK(vkCreateDescriptorSetLayout(dev, &dlci, NULL, &dsl));
   VkPipelineLayout pl;
   VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1, .pSetLayouts = &dsl };
   CHK(vkCreatePipelineLayout(dev, &plci, NULL, &pl));
   VkShaderModule sm;
   VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sizeof(spv16), .pCode = spv16 };
   CHK(vkCreateShaderModule(dev, &smci, NULL, &sm));
   VkPipeline pipe;
   VkComputePipelineCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                 .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main" }, .layout = pl };
   CHK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipe));

   VkDescriptorPoolSize ps[2] = { { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1 },
                                  { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1 } };
   VkDescriptorPool dp;
   VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = 1, .poolSizeCount = 2, .pPoolSizes = ps };
   CHK(vkCreateDescriptorPool(dev, &dpci, NULL, &dp));
   VkDescriptorSet ds;
   VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = dp, .descriptorSetCount = 1, .pSetLayouts = &dsl };
   CHK(vkAllocateDescriptorSets(dev, &dsai, &ds));
   VkDescriptorImageInfo dii = { ech, vue, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
   VkDescriptorBufferInfo dbi = { bdst, 0, VK_WHOLE_SIZE };
   VkWriteDescriptorSet w[2] = {
      { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0,
        .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &dii },
      { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1,
        .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi } };
   vkUpdateDescriptorSets(dev, 2, w, 0, NULL);

   VkCommandPool cp; VkCommandBuffer cb;
   VkCommandPoolCreateInfo cpci2 = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = qfam };
   CHK(vkCreateCommandPool(dev, &cpci2, NULL, &cp));
   VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = cp, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   CHK(vkAllocateCommandBuffers(dev, &cbai, &cb));

   /* Les seize indices 0..15, soit chaque valeur du bloc deux fois :
    * 0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7 */
   uint8_t indices[6];
   {
      uint64_t bits = 0;
      for (int t = 0; t < 16; ++t) bits |= (uint64_t)(t & 7) << (3 * t);
      for (int i = 0; i < 6; ++i) indices[i] = (bits >> (8 * i)) & 0xff;
   }

   uint8_t mode_haut[8] = { 0xff, 0x00 }; memcpy(mode_haut + 2, indices, 6);
   uint8_t mode_bas[8]  = { 0x40, 0xc0 }; memcpy(mode_bas + 2, indices, 6);

   int fautes = 0;
   fautes += eprouver(mode_haut, "mode a huit valeurs  (rouge0 > rouge1)",
                      img, mimg, bsrc, msrc, bdst, mdst, cb, pipe, pl, ds);
   fautes += eprouver(mode_bas,  "mode a six valeurs + 0 et 1 (rouge0 <= rouge1)",
                      img, mimg, bsrc, msrc, bdst, mdst, cb, pipe, pl, ds);

   printf("decodage BC4 : %s (%d ecarts)\n", fautes ? "FAUX" : "juste", fautes);
   return fautes ? 1 : 0;
}
