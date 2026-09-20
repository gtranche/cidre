/* Sonde : taille memoire rapportee par le pilote pour une image 2D, en faisant
 * varier le nombre de couches et de niveaux. Un surcout constant se distingue
 * ainsi d'un surcout proportionnel. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>

static VkDevice dev;
static VkPhysicalDevice phys;

static uint64_t taille(VkFormat fmt, uint32_t w, uint32_t h, uint32_t levels,
                       uint32_t layers, uint64_t *align)
{
   VkImageCreateInfo ci = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D,
      .format = fmt,
      .extent = { w, h, 1 },
      .mipLevels = levels,
      .arrayLayers = layers,
      .samples = VK_SAMPLE_COUNT_1_BIT,
      .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT
             | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
   };
   VkImage img;
   VkMemoryRequirements req;

   if (vkCreateImage(dev, &ci, NULL, &img) != VK_SUCCESS) return 0;
   vkGetImageMemoryRequirements(dev, img, &req);
   vkDestroyImage(dev, img, NULL);
   if (align) *align = req.alignment;
   return req.size;
}

int main(void)
{
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                             .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                .pApplicationInfo = &app };
   VkInstance inst;
   uint32_t n = 1;
   float prio = 1.0f;
   VkDeviceQueueCreateInfo q = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                 .queueCount = 1, .pQueuePriorities = &prio };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                              .queueCreateInfoCount = 1, .pQueueCreateInfos = &q };
   VkPhysicalDeviceProperties props;

   if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) { puts("pas d'instance"); return 1; }
   vkEnumeratePhysicalDevices(inst, &n, &phys);
   vkGetPhysicalDeviceProperties(phys, &props);
   printf("pilote : %s\n", props.deviceName);
   if (vkCreateDevice(phys, &dci, NULL, &dev) != VK_SUCCESS) { puts("pas de peripherique"); return 1; }

   printf("\nBC1 512x256, 1 niveau, couches variables (dense attendu : 65536 par couche)\n");
   for (uint32_t l = 1; l <= 6; ++l) {
      uint64_t a = 0, s = taille(VK_FORMAT_BC1_RGB_UNORM_BLOCK, 512, 256, 1, l, &a);
      printf("  couches %u : taille %8llu  dense %8u  ecart %6lld  align %llu\n",
             l, (unsigned long long)s, 65536u * l,
             (long long)s - 65536ll * l, (unsigned long long)a);
   }

   printf("\nRGBA8 128x128, 1 couche, niveaux variables (niveau 0 : 65536)\n");
   for (uint32_t m = 1; m <= 5; ++m) {
      uint64_t a = 0, s = taille(VK_FORMAT_R8G8B8A8_UNORM, 128, 128, m, 1, &a);
      printf("  niveaux %u : taille %8llu  align %llu\n", m, (unsigned long long)s,
             (unsigned long long)a);
   }

   printf("\nune seule couche, un seul niveau, tailles variables\n");
   struct { uint32_t w, h; const char *nom; } cas[] = {
      { 4, 4, "RGBA8 4x4" }, { 16, 16, "RGBA8 16x16" }, { 64, 64, "RGBA8 64x64" },
      { 128, 128, "RGBA8 128x128" }, { 256, 256, "RGBA8 256x256" },
   };
   for (unsigned i = 0; i < sizeof(cas)/sizeof(*cas); ++i) {
      uint64_t a = 0, s = taille(VK_FORMAT_R8G8B8A8_UNORM, cas[i].w, cas[i].h, 1, 1, &a);
      uint32_t dense = cas[i].w * cas[i].h * 4;
      printf("  %-16s taille %8llu  dense %8u  ecart %6lld  align %llu\n",
             cas[i].nom, (unsigned long long)s, dense,
             (long long)s - (long long)dense, (unsigned long long)a);
   }
   return 0;
}
