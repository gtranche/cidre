/*
 * Sonde : le pilote decode-t-il BC7 mode 6 juste ?
 *
 * Le §279 a trouve l'atlas de police de Surviving Mars : de petits rectangles
 * poses a des offsets epars dans une texture 2048x2048, et tous, sans
 * exception, en BC7 **mode 6**. Les illustrations du jeu, elles, emploient les
 * modes 0, 1, 3, 5 et 7. Un decodeur qui se tromperait sur le seul mode 6
 * casserait donc le texte et rien d'autre -- ce qu'on observe.
 *
 * Mode 6 est le plus simple des huit : un seul sous-ensemble, pas de partition,
 * quatre composantes de 7 bits par extremite, un bit de parite chacune, et des
 * indices de 4 bits. On peut donc fabriquer un bloc a la main et savoir
 * exactement ce qu'il doit rendre.
 *
 *   bits  0..6   : le mode, 6 zeros puis un 1
 *   bits  7..62  : R0 R1 G0 G1 B0 B1 A0 A1, 7 bits chacun
 *   bits 63..64  : P0 P1
 *   bits 65..127 : l'indice 0 sur 3 bits (ancre), puis quinze sur 4 bits
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

/* Ecriture de bits, du moins significatif vers le plus significatif. */
struct sac { uint8_t o[16]; unsigned n; };
static void poser(struct sac *s, uint32_t valeur, unsigned bits)
{
   for (unsigned i = 0; i < bits; ++i, ++s->n)
      if ((valeur >> i) & 1u) s->o[s->n >> 3] |= 1u << (s->n & 7u);
}

static const int poids4[16] = { 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 };

/* Le bloc, et ce qu'il doit rendre : les deux sortent de la meme description,
 * mais le second par le calcul de la specification, pas par le pilote. */
static void fabriquer(struct sac *s, double attendu[16][4],
                      const uint32_t e0[4], const uint32_t e1[4],
                      uint32_t p0, uint32_t p1, const uint32_t idx[16])
{
   memset(s, 0, sizeof(*s));
   poser(s, 0x40u, 7);                                  /* le mode */
   for (int c = 0; c < 4; ++c) { poser(s, e0[c], 7); poser(s, e1[c], 7); }
   poser(s, p0, 1); poser(s, p1, 1);
   poser(s, idx[0], 3);
   for (int t = 1; t < 16; ++t) poser(s, idx[t], 4);

   for (int t = 0; t < 16; ++t) {
      int w = poids4[idx[t]];
      for (int c = 0; c < 4; ++c) {
         int a = (int)((e0[c] << 1) | p0);
         int b = (int)((e1[c] << 1) | p1);
         attendu[t][c] = (double)((a * (64 - w) + b * w + 32) >> 6) / 255.0;
      }
   }
}

static int eprouver(const char *quoi, const struct sac *s, const double attendu[16][4],
                    VkImage img, VkBuffer bsrc, VkDeviceMemory msrc, VkDeviceMemory mdst,
                    VkCommandBuffer cb, VkPipeline pipe, VkPipelineLayout pl, VkDescriptorSet ds)
{
   void *p;
   CHK(vkMapMemory(dev, msrc, 0, VK_WHOLE_SIZE, 0, &p));
   memcpy(p, s->o, 16); vkUnmapMemory(dev, msrc);

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

   CHK(vkMapMemory(dev, mdst, 0, VK_WHOLE_SIZE, 0, &p));
   const float *f = p;
   static const char *canaux = "RGBA";
   int ecarts = 0;
   printf("%s\n", quoi);
   for (int t = 0; t < 16; ++t) {
      for (int c = 0; c < 4; ++c) {
         double d = fabs((double)f[t * 4 + c] - attendu[t][c]);
         if (d > 2.0 / 255.0) {
            if (ecarts < 6)
               printf("   texel %2d canal %c : obtenu %.4f, attendu %.4f   ECART %.4f\n",
                      t, canaux[c], f[t * 4 + c], attendu[t][c], d);
            ecarts++;
         }
      }
   }
   vkUnmapMemory(dev, mdst);
   printf("   %s (%d ecarts sur 64 composantes)\n\n", ecarts ? "FAUX" : "juste", ecarts);
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
      .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_BC7_UNORM_BLOCK,
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
      .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_BC7_UNORM_BLOCK,
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

   struct sac s; double attendu[16][4];
   uint32_t idx[16]; for (int t = 0; t < 16; ++t) idx[t] = t;   /* les seize poids */
   int fautes = 0;

   {  /* Noir opaque vers blanc opaque : la rampe d'un glyphe. */
      uint32_t e0[4] = { 0, 0, 0, 127 }, e1[4] = { 127, 127, 127, 127 };
      fabriquer(&s, attendu, e0, e1, 0, 1, idx);
      fautes += eprouver("noir -> blanc, alpha plein", &s, attendu, img, bsrc, msrc, mdst, cb, pipe, pl, ds);
   }
   {  /* Transparent vers opaque : la couverture d'un glyphe. */
      uint32_t e0[4] = { 127, 127, 127, 0 }, e1[4] = { 127, 127, 127, 127 };
      fabriquer(&s, attendu, e0, e1, 0, 1, idx);
      fautes += eprouver("alpha 0 -> 1, couleur pleine", &s, attendu, img, bsrc, msrc, mdst, cb, pipe, pl, ds);
   }
   {  /* Bits de parite differents : le detail que l'on oublie. */
      uint32_t e0[4] = { 0x2a, 0x55, 0x7f, 0x11 }, e1[4] = { 0x6d, 0x03, 0x40, 0x7e };
      fabriquer(&s, attendu, e0, e1, 1, 0, idx);
      fautes += eprouver("extremites quelconques, parites 1 et 0", &s, attendu, img, bsrc, msrc, mdst, cb, pipe, pl, ds);
   }

   printf("decodage BC7 mode 6 : %s (%d ecarts)\n", fautes ? "FAUX" : "juste", fautes);
   return fautes ? 1 : 0;
}
