/*
 * Sonde : le melange de composantes d'une vue d'image est-il respecte ?
 *
 * Surviving Mars affiche son texte troue de rectangles noirs. DXVK journalise
 * « VK_FORMAT_A8_UNORM_KHR -> VK_FORMAT_R8_UNORM » : le format A8 n'etant pas
 * annonce, il se rabat sur R8 en demandant le melange {ZERO, ZERO, ZERO, R},
 * pour que la couverture reste dans l'alpha. Sur le papier c'est correct des
 * deux cotes. Reste a verifier que ca l'est a l'execution.
 *
 * On pose une image R8 de quatre texels -- 0x00, 0x40, 0x80, 0xff -- on la
 * regarde a travers une vue portant ce melange, on l'echantillonne, et on
 * imprime ce qui sort. Attendu : (0, 0, 0, v). Tout autre resultat nomme le
 * fautif.
 *
 * A titre de temoin, la meme image est aussi lue par une vue sans melange.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>
#include "melange_spv.h"

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
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1, .pQueueCreateInfos = &q };
   CHK(vkCreateDevice(phys, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qfam, 0, &file);

   VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(phys, &pp);
   printf("pilote : %s\n\n", pp.deviceName);

   /* Le format A8 est-il seulement annonce ? C'est la question que DXVK pose. */
   {
      VkFormatProperties fp;
      vkGetPhysicalDeviceFormatProperties(phys, VK_FORMAT_A8_UNORM_KHR, &fp);
      printf("A8_UNORM_KHR  echantillonnable : %s\n",
             (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) ? "oui" : "NON");
      vkGetPhysicalDeviceFormatProperties(phys, VK_FORMAT_R8_UNORM, &fp);
      printf("R8_UNORM      echantillonnable : %s\n\n",
             (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) ? "oui" : "NON");
   }

   /* Les formats compresses : un atlas de police a un canal se stocke en BC4.
    * Si le pilote ne l'annonce pas, tout texte qui en vient est perdu. */
   {
      static const struct { VkFormat f; const char *nom; } bc[] = {
         { VK_FORMAT_BC1_RGB_UNORM_BLOCK,  "BC1_RGB " },
         { VK_FORMAT_BC1_RGBA_UNORM_BLOCK, "BC1_RGBA" },
         { VK_FORMAT_BC3_UNORM_BLOCK,      "BC3     " },
         { VK_FORMAT_BC4_UNORM_BLOCK,      "BC4     " },
         { VK_FORMAT_BC5_UNORM_BLOCK,      "BC5     " },
         { VK_FORMAT_BC7_UNORM_BLOCK,      "BC7     " } };
      for (unsigned i = 0; i < sizeof(bc) / sizeof(bc[0]); ++i) {
         VkFormatProperties fp;
         vkGetPhysicalDeviceFormatProperties(phys, bc[i].f, &fp);
         printf("%s echantillonnable : %s\n", bc[i].nom,
                (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) ? "oui" : "NON");
      }
      printf("\n");
   }

   /* L'image de quatre texels. */
   const uint8_t texels[4] = { 0x00, 0x40, 0x80, 0xff };
   VkImage img; VkDeviceMemory mimg;
   VkImageCreateInfo ici2 = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R8_UNORM,
      .extent = { 4, 1, 1 }, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
   CHK(vkCreateImage(dev, &ici2, NULL, &img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size, .memoryTypeIndex = type_memoire(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
   CHK(vkAllocateMemory(dev, &mai, NULL, &mimg));
   CHK(vkBindImageMemory(dev, img, mimg, 0));

   /* Un tampon pour y verser les texels, et un autre pour recuperer la sortie. */
   VkBuffer bsrc, bdst; VkDeviceMemory msrc, mdst; void *p;
   VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = 256, .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT };
   CHK(vkCreateBuffer(dev, &bci, NULL, &bsrc));
   vkGetBufferMemoryRequirements(dev, bsrc, &mr);
   mai.allocationSize = mr.size;
   mai.memoryTypeIndex = type_memoire(mr.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
   CHK(vkAllocateMemory(dev, &mai, NULL, &msrc));
   CHK(vkBindBufferMemory(dev, bsrc, msrc, 0));
   CHK(vkMapMemory(dev, msrc, 0, VK_WHOLE_SIZE, 0, &p));
   memcpy(p, texels, sizeof(texels)); vkUnmapMemory(dev, msrc);

   bci.size = 2 * 4 * sizeof(float) * 4;
   bci.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
   CHK(vkCreateBuffer(dev, &bci, NULL, &bdst));
   vkGetBufferMemoryRequirements(dev, bdst, &mr);
   mai.allocationSize = mr.size;
   mai.memoryTypeIndex = type_memoire(mr.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
   CHK(vkAllocateMemory(dev, &mai, NULL, &mdst));
   CHK(vkBindBufferMemory(dev, bdst, mdst, 0));

   /* Deux vues : avec le melange de DXVK, et sans, pour temoin. */
   VkImageView vues[2];
   VkComponentMapping melanges[2] = {
      { VK_COMPONENT_SWIZZLE_ZERO, VK_COMPONENT_SWIZZLE_ZERO,
        VK_COMPONENT_SWIZZLE_ZERO, VK_COMPONENT_SWIZZLE_R },
      { VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
        VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY } };
   for (int i = 0; i < 2; ++i) {
      VkImageViewCreateInfo vci = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
         .image = img, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R8_UNORM,
         .components = melanges[i],
         .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
      CHK(vkCreateImageView(dev, &vci, NULL, &vues[i]));
   }

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
      .codeSize = sizeof(spv), .pCode = spv };
   CHK(vkCreateShaderModule(dev, &smci, NULL, &sm));
   VkPipeline pipe;
   VkComputePipelineCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                 .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main" },
      .layout = pl };
   CHK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipe));

   VkDescriptorPoolSize ps[2] = { { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 2 },
                                  { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 2 } };
   VkDescriptorPool dp;
   VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = 2, .poolSizeCount = 2, .pPoolSizes = ps };
   CHK(vkCreateDescriptorPool(dev, &dpci, NULL, &dp));

   VkCommandPool cp; VkCommandBuffer cb;
   VkCommandPoolCreateInfo cpci2 = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = qfam };
   CHK(vkCreateCommandPool(dev, &cpci2, NULL, &cp));
   VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = cp, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   CHK(vkAllocateCommandBuffers(dev, &cbai, &cb));

   static const char *noms[2] = { "melange de DXVK {0,0,0,R}", "sans melange (temoin)" };
   for (int i = 0; i < 2; ++i) {
      VkDescriptorSet ds;
      VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
         .descriptorPool = dp, .descriptorSetCount = 1, .pSetLayouts = &dsl };
      CHK(vkAllocateDescriptorSets(dev, &dsai, &ds));
      VkDescriptorImageInfo dii = { ech, vues[i], VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
      VkDescriptorBufferInfo dbi = { bdst, i * 4 * 4 * sizeof(float), 4 * 4 * sizeof(float) };
      VkWriteDescriptorSet w[2] = {
         { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0,
           .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &dii },
         { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1,
           .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi } };
      vkUpdateDescriptorSets(dev, 2, w, 0, NULL);

      VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
      CHK(vkBeginCommandBuffer(cb, &bi));
      if (i == 0) {
         VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .image = img, .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
            .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT };
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
         VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { 4, 1, 1 } };
         vkCmdCopyBufferToImage(cb, bsrc, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &c);
         b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
         b.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
         b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
      }
      vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
      vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
      vkCmdDispatch(cb, 1, 1, 1);
      CHK(vkEndCommandBuffer(cb));
      VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
      CHK(vkQueueSubmit(file, 1, &si, VK_NULL_HANDLE));
      CHK(vkQueueWaitIdle(file));
      CHK(vkResetCommandBuffer(cb, 0));
   }

   CHK(vkMapMemory(dev, mdst, 0, VK_WHOLE_SIZE, 0, &p));
   const float *f = p;
   int fautes = 0;
   for (int i = 0; i < 2; ++i) {
      printf("%s :\n", noms[i]);
      for (int t = 0; t < 4; ++t) {
         const float *v = f + (i * 4 + t) * 4;
         float attendu_a = texels[t] / 255.0f;
         printf("   texel %#04x -> (%.3f, %.3f, %.3f, %.3f)", texels[t], v[0], v[1], v[2], v[3]);
         if (i == 0) {
            int ok = v[0] < 0.01f && v[1] < 0.01f && v[2] < 0.01f &&
                     v[3] > attendu_a - 0.01f && v[3] < attendu_a + 0.01f;
            printf("   attendu (0, 0, 0, %.3f) : %s", attendu_a, ok ? "ok" : "ECART");
            if (!ok) fautes++;
         }
         printf("\n");
      }
      printf("\n");
   }
   printf("melange de composantes : %s (%d ecarts)\n", fautes ? "NON RESPECTE" : "respecte", fautes);
   return fautes ? 1 : 0;
}
