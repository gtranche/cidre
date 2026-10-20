/* Sonde hors jeu : agrandissement MetalFX a la presentation dans la WSI Metal
 * de KosmicKrisp (correctif 0202, MESA_WSI_METAL_METALFX=1).
 *
 * Une couche CAMetalLayer hors fenetre (rien a l'ecran, aucune capture) a la
 * taille d'un espace en points ; une swapchain plus petite, comme celle d'un jeu
 * qui rend sous la taille de l'espace en mode emule. Chaque image recoit un
 * damier (cases de 32 pixels, rouge et bleu, une ligne blanche d'un pixel par
 * case) copie depuis un tampon, puis est presentee. Avec MetalFX, la WSI relit
 * le drawable agrandi a la 30e image (MESA_WSI_METAL_METALFX_RELIRE) : la sonde
 * verifie sa taille (pixels physiques de la couche) et la couleur au centre de
 * chaque case.
 *
 * Construction :
 *   clang -arch arm64 -fobjc-arc -I src/Vulkan-Headers/include tests/sonde_metalfx_kk.m \
 *      -framework Foundation -framework QuartzCore -framework Metal -o sonde_metalfx_kk
 * Usage :
 *   [MESA_WSI_METAL_METALFX=1] [SONDE_SRGB=1] sonde_metalfx_kk <libvulkan_kosmickrisp.dylib> <entree LxH> <couche LxH en points> [images]
 * SONDE_SRGB=1 : swapchain B8G8R8A8_SRGB (le format des jeux DXVK/vkd3d-proton)
 * au lieu de B8G8R8A8_UNORM.
 * Sortie : temps par image, puis VERDICT ; code 0 si conforme.
 */
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>

typedef PFN_vkVoidFunction (*PFN_icdGIPA)(VkInstance, const char *);
static PFN_icdGIPA gipa;
static VkInstance inst;
#define F(nom) static PFN_##nom nom;
F(vkEnumeratePhysicalDevices) F(vkCreateDevice) F(vkGetDeviceQueue)
F(vkCreateMetalSurfaceEXT) F(vkCreateSwapchainKHR) F(vkGetSwapchainImagesKHR)
F(vkAcquireNextImageKHR) F(vkQueuePresentKHR) F(vkCreateCommandPool)
F(vkAllocateCommandBuffers) F(vkBeginCommandBuffer) F(vkEndCommandBuffer)
F(vkCmdPipelineBarrier) F(vkCmdCopyBufferToImage) F(vkQueueSubmit)
F(vkCreateSemaphore) F(vkCreateFence) F(vkWaitForFences) F(vkResetFences)
F(vkCreateBuffer) F(vkGetBufferMemoryRequirements) F(vkAllocateMemory)
F(vkBindBufferMemory) F(vkMapMemory) F(vkGetPhysicalDeviceMemoryProperties)
F(vkDeviceWaitIdle) F(vkGetPhysicalDeviceSurfaceCapabilitiesKHR)
F(vkDestroySwapchainKHR) F(vkResetCommandBuffer)
#define L(nom) nom = (PFN_##nom)gipa(inst, #nom)

#define CASE 32

static double maintenant(void)
{
   struct timespec t;
   clock_gettime(CLOCK_MONOTONIC, &t);
   return t.tv_sec + t.tv_nsec / 1e9;
}

/* Couleur attendue d'une case (BGRA) : rouge pour (cx + cy) pair, bleu sinon. */
static int case_rouge(unsigned cx, unsigned cy) { return ((cx + cy) & 1) == 0; }

static int verifier(const char *ppm, unsigned in_w, unsigned in_h,
                    unsigned out_w, unsigned out_h)
{
   FILE *f = fopen(ppm, "rb");
   if (!f) { printf("  ECHEC : %s absent (la WSI n'a rien relu)\n", ppm); return 1; }
   unsigned w, h, m;
   if (fscanf(f, "P6 %u %u %u", &w, &h, &m) != 3) { fclose(f); printf("  ECHEC : PPM illisible\n"); return 1; }
   fgetc(f);
   uint8_t *px = malloc((size_t)w * h * 3);
   size_t lu = fread(px, 3, (size_t)w * h, f);
   fclose(f);
   int err = 0;
   printf("  drawable relu : %ux%u (attendu %ux%u)\n", w, h, out_w, out_h);
   if (w != out_w || h != out_h || lu != (size_t)w * h) { printf("  ECHEC : taille\n"); free(px); return 1; }
   unsigned justes = 0, total = 0;
   for (unsigned cy = 0; cy + 1 < in_h / CASE; cy++)
      for (unsigned cx = 0; cx + 1 < in_w / CASE; cx++) {
         /* centre de la case en entree, ramene a la sortie */
         double ix = cx * CASE + CASE / 2.0, iy = cy * CASE + CASE / 2.0;
         unsigned ox = (unsigned)(ix * out_w / in_w), oy = (unsigned)(iy * out_h / in_h);
         const uint8_t *p = px + ((size_t)oy * w + ox) * 3;
         int rouge = p[0] > 150 && p[2] < 100, bleu = p[2] > 150 && p[0] < 100;
         total++;
         if (case_rouge(cx, cy) ? rouge : bleu) justes++;
      }
   printf("  cases justes : %u / %u\n", justes, total);
   if (justes != total) err++;
   /* la ligne blanche du haut de la case (0,0) doit survivre a l'agrandissement */
   unsigned blancs = 0;
   for (unsigned x = 0; x < out_w * CASE / in_w; x++)
      for (unsigned y = 0; y < (out_h + in_h - 1) / in_h + 1; y++) {
         const uint8_t *p = px + ((size_t)y * w + x) * 3;
         if (p[0] > 200 && p[1] > 200 && p[2] > 200) { blancs++; break; }
      }
   printf("  ligne blanche d'un pixel : %u colonnes sur %u\n", blancs, out_w * CASE / in_w);
   if (blancs < out_w * CASE / in_w / 2) { printf("  ECHEC : ligne fine perdue\n"); err++; }
   free(px);
   return err;
}

int main(int argc, char **argv)
{
   @autoreleasepool {
      unsigned in_w, in_h, pt_w, pt_h, images = argc > 4 ? atoi(argv[4]) : 600;
      if (argc < 4 || sscanf(argv[2], "%ux%u", &in_w, &in_h) != 2 ||
          sscanf(argv[3], "%ux%u", &pt_w, &pt_h) != 2) {
         fprintf(stderr, "usage : %s <icd> <entree LxH> <couche LxH points> [images]\n", argv[0]);
         return 2;
      }
      void *icd = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      if (!icd) { fprintf(stderr, "dlopen : %s\n", dlerror()); return 2; }
      gipa = (PFN_icdGIPA)dlsym(icd, "vk_icdGetInstanceProcAddr");

      const char *iexts[] = { "VK_KHR_surface", "VK_EXT_metal_surface" };
      VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
      VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
                                   .enabledExtensionCount = 2, .ppEnabledExtensionNames = iexts };
      if (((PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance"))(&ici, NULL, &inst)) return 2;
      L(vkEnumeratePhysicalDevices); L(vkCreateDevice); L(vkGetDeviceQueue); L(vkCreateMetalSurfaceEXT);
      L(vkCreateSwapchainKHR); L(vkGetSwapchainImagesKHR); L(vkAcquireNextImageKHR); L(vkQueuePresentKHR);
      L(vkCreateCommandPool); L(vkAllocateCommandBuffers); L(vkBeginCommandBuffer); L(vkEndCommandBuffer);
      L(vkCmdPipelineBarrier); L(vkCmdCopyBufferToImage); L(vkQueueSubmit); L(vkCreateSemaphore);
      L(vkCreateFence); L(vkWaitForFences); L(vkResetFences); L(vkCreateBuffer);
      L(vkGetBufferMemoryRequirements); L(vkAllocateMemory); L(vkBindBufferMemory); L(vkMapMemory);
      L(vkGetPhysicalDeviceMemoryProperties); L(vkDeviceWaitIdle);
      L(vkGetPhysicalDeviceSurfaceCapabilitiesKHR); L(vkDestroySwapchainKHR); L(vkResetCommandBuffer);

      uint32_t n = 1;
      VkPhysicalDevice pd;
      vkEnumeratePhysicalDevices(inst, &n, &pd);
      float prio = 1;
      VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio };
      const char *dexts[] = { "VK_KHR_swapchain" };
      VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1,
                                 .pQueueCreateInfos = &qci, .enabledExtensionCount = 1, .ppEnabledExtensionNames = dexts };
      VkDevice dev;
      if (vkCreateDevice(pd, &dci, NULL, &dev)) return 2;
      VkQueue q;
      vkGetDeviceQueue(dev, 0, 0, &q);

      CAMetalLayer *layer = [CAMetalLayer layer];
      layer.device = MTLCreateSystemDefaultDevice();
      layer.bounds = CGRectMake(0, 0, pt_w, pt_h);
      layer.contentsScale = 1;
      VkMetalSurfaceCreateInfoEXT sci = { .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, .pLayer = layer };
      VkSurfaceKHR surf;
      if (vkCreateMetalSurfaceEXT(inst, &sci, NULL, &surf)) return 2;

      VkSwapchainCreateInfoKHR sc = {
         .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, .surface = surf, .minImageCount = 3,
         .imageFormat = getenv("SONDE_SRGB") ? VK_FORMAT_B8G8R8A8_SRGB : VK_FORMAT_B8G8R8A8_UNORM, .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
         .imageExtent = { in_w, in_h }, .imageArrayLayers = 1,
         .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
         .preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR, .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
         .presentMode = VK_PRESENT_MODE_IMMEDIATE_KHR, .clipped = VK_TRUE };
      VkSwapchainKHR chain;
      VkResult r = vkCreateSwapchainKHR(dev, &sc, NULL, &chain);
      if (r) { fprintf(stderr, "vkCreateSwapchainKHR %d\n", r); return 2; }
      uint32_t ni = 8;
      VkImage imgs[8];
      vkGetSwapchainImagesKHR(dev, chain, &ni, imgs);
      CGSize ds = layer.drawableSize;
      printf("swapchain %ux%u, couche %ux%u points, drawable %.0fx%.0f, %u images\n",
             in_w, in_h, pt_w, pt_h, ds.width, ds.height, ni);

      /* damier dans un tampon visible de l'hote */
      VkDeviceSize taille = (VkDeviceSize)in_w * in_h * 4;
      VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = taille,
                                 .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT };
      VkBuffer buf;
      vkCreateBuffer(dev, &bci, NULL, &buf);
      VkMemoryRequirements mr;
      vkGetBufferMemoryRequirements(dev, buf, &mr);
      VkPhysicalDeviceMemoryProperties mp;
      vkGetPhysicalDeviceMemoryProperties(pd, &mp);
      uint32_t type = 0;
      for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
         if ((mr.memoryTypeBits & (1u << i)) &&
             (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) { type = i; break; }
      VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = type };
      VkDeviceMemory mem;
      vkAllocateMemory(dev, &mai, NULL, &mem);
      vkBindBufferMemory(dev, buf, mem, 0);
      uint8_t *p;
      vkMapMemory(dev, mem, 0, taille, 0, (void **)&p);
      for (unsigned y = 0; y < in_h; y++)
         for (unsigned x = 0; x < in_w; x++) {
            uint8_t *q4 = p + ((size_t)y * in_w + x) * 4;
            int blanc = (y % CASE) == 0;
            int rouge = case_rouge(x / CASE, y / CASE);
            q4[0] = blanc ? 255 : (rouge ? 30 : 230);  /* B */
            q4[1] = blanc ? 255 : 30;                  /* G */
            q4[2] = blanc ? 255 : (rouge ? 230 : 30);  /* R */
            q4[3] = 255;
         }

      VkCommandPoolCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
      VkCommandPool pool;
      vkCreateCommandPool(dev, &cpi, NULL, &pool);
      enum { VOL = 3 };
      VkCommandBuffer cbs[VOL];
      VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool,
                                          .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = VOL };
      vkAllocateCommandBuffers(dev, &cai, cbs);
      VkSemaphore acq[VOL], fin[VOL];
      VkFence fences[VOL];
      VkSemaphoreCreateInfo semi = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
      VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
      for (int i = 0; i < VOL; i++) {
         vkCreateSemaphore(dev, &semi, NULL, &acq[i]);
         vkCreateSemaphore(dev, &semi, NULL, &fin[i]);
         vkCreateFence(dev, &fci, NULL, &fences[i]);
      }

      double t0 = 0;
      unsigned sousopt = 0;
      for (unsigned f = 0; f < images; f++) {
         if (f == 30) t0 = maintenant();
         int v = f % VOL;
         vkWaitForFences(dev, 1, &fences[v], VK_TRUE, UINT64_MAX);
         vkResetFences(dev, 1, &fences[v]);
         uint32_t idx;
         r = vkAcquireNextImageKHR(dev, chain, 2000000000ull, acq[v], VK_NULL_HANDLE, &idx);
         if (r < 0 || r == VK_NOT_READY || r == VK_TIMEOUT) { fprintf(stderr, "acquisition %d a l'image %u\n", r, f); return 1; }
         VkCommandBuffer cb = cbs[v];
         vkResetCommandBuffer(cb, 0);
         VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
         vkBeginCommandBuffer(cb, &bi);
         VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = imgs[idx], .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
         VkBufferImageCopy reg = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
                                   .imageExtent = { in_w, in_h, 1 } };
         vkCmdCopyBufferToImage(cb, buf, imgs[idx], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &reg);
         b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask = 0;
         b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &b);
         vkEndCommandBuffer(cb);
         VkPipelineStageFlags ws = VK_PIPELINE_STAGE_TRANSFER_BIT;
         VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .waitSemaphoreCount = 1, .pWaitSemaphores = &acq[v],
                             .pWaitDstStageMask = &ws, .commandBufferCount = 1, .pCommandBuffers = &cb,
                             .signalSemaphoreCount = 1, .pSignalSemaphores = &fin[v] };
         vkQueueSubmit(q, 1, &si, fences[v]);
         VkPresentInfoKHR pi = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = 1, .pWaitSemaphores = &fin[v],
                                 .swapchainCount = 1, .pSwapchains = &chain, .pImageIndices = &idx };
         r = vkQueuePresentKHR(q, &pi);
         if (r == VK_SUBOPTIMAL_KHR) sousopt++;
         else if (r) { fprintf(stderr, "presentation %d a l'image %u\n", r, f); return 1; }
      }
      vkDeviceWaitIdle(dev);
      double dt = maintenant() - t0;
      printf("%u images en %.2f s : %.3f ms par image (%u sous-optimales, attendu quand la couche n'a pas la taille de la swapchain)\n",
             images - 30, dt, dt * 1e3 / (images - 30), sousopt);
      vkDestroySwapchainKHR(dev, chain, NULL);
      usleep(200000);

      int err = 0;
      const char *mfx = getenv("MESA_WSI_METAL_METALFX");
      const char *relire = getenv("MESA_WSI_METAL_METALFX_RELIRE");
      if (mfx && *mfx == '1') {
         if (ds.width <= in_w) { printf("  ECHEC : drawable pas agrandi\n"); err++; }
         else if (relire) err += verifier(relire, in_w, in_h, (unsigned)ds.width, (unsigned)ds.height);
      } else if (ds.width != in_w || ds.height != in_h) {
         printf("  ECHEC : sans MetalFX, le drawable doit garder la taille de la swapchain\n"); err++;
      }
      printf("VERDICT : %s\n", err ? "ECHEC" : "OK");
      return err ? 1 : 0;
   }
}
