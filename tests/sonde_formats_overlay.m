/* Sonde hors jeu : formats de surface annonces par la WSI Metal de
 * KosmicKrisp, avec et sans le mode overlay Steam
 * (MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER=1, pose par etape2).
 *
 * L'overlay de Steam a des pipelines BGRA8, BGR10A2 et RGBA16Float, aucun en
 * RGB10A2 : un drawable RGB10A2 (A2B10G10R10, defaut des back buffers
 * UE4/UE5) est relu en BGRA8 et l'image entiere vire au bleu/violet. En mode
 * overlay, la WSI ne doit plus annoncer A2B10G10R10 en sRGB (HDR10 garde,
 * A2R10G10B10 = BGR10A2 garde), et vkd3d-proton/DXVK retombent sur BGRA8.
 * Depuis 0193, A2B10G10R10 n'est plus annonce en sRGB hors overlay non plus
 * (RGB10A2 n'est jamais envoye en direct a l'ecran), sauf MESA_WSI_METAL_RGB10A2=1.
 *
 * Construction :
 *   clang -arch arm64 -fobjc-arc -I src/Vulkan-Headers/include tests/sonde_formats_overlay.m \
 *      -framework Foundation -framework QuartzCore -framework Metal -o sonde_formats_overlay
 * Usage : [MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER=1] sonde_formats_overlay <libvulkan_kosmickrisp.dylib>
 * Sortie : liste des couples, puis VERDICT ; code 0 si conforme au mode.
 */
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>

typedef PFN_vkVoidFunction (*PFN_icdGIPA)(VkInstance, const char *);

static const char *nom_format(VkFormat f)
{
   switch (f) {
   case VK_FORMAT_B8G8R8A8_SRGB: return "B8G8R8A8_SRGB";
   case VK_FORMAT_B8G8R8A8_UNORM: return "B8G8R8A8_UNORM";
   case VK_FORMAT_R16G16B16A16_SFLOAT: return "R16G16B16A16_SFLOAT";
   case VK_FORMAT_A2R10G10B10_UNORM_PACK32: return "A2R10G10B10_UNORM";
   case VK_FORMAT_A2B10G10R10_UNORM_PACK32: return "A2B10G10R10_UNORM";
   default: return "?";
   }
}

static int dix_bits(VkFormat f)
{
   return f == VK_FORMAT_A2R10G10B10_UNORM_PACK32 ||
          f == VK_FORMAT_A2B10G10R10_UNORM_PACK32;
}

int main(int argc, char **argv)
{
   @autoreleasepool {
      if (argc < 2) {
         fprintf(stderr, "usage : %s <libvulkan_kosmickrisp.dylib>\n", argv[0]);
         return 2;
      }
      void *icd = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      if (!icd) { fprintf(stderr, "dlopen : %s\n", dlerror()); return 2; }
      PFN_icdGIPA gipa = (PFN_icdGIPA)dlsym(icd, "vk_icdGetInstanceProcAddr");
      if (!gipa) { fprintf(stderr, "vk_icdGetInstanceProcAddr absent\n"); return 2; }

#define GIPA(inst, nom) ((PFN_##nom)gipa(inst, #nom))
      const char *exts[] = { "VK_KHR_surface", "VK_EXT_metal_surface",
                             "VK_EXT_swapchain_colorspace",
                             "VK_KHR_get_surface_capabilities2" };
      VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                                .apiVersion = VK_API_VERSION_1_3 };
      VkInstanceCreateInfo ici = {
         .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
         .pApplicationInfo = &app,
         .enabledExtensionCount = 4, .ppEnabledExtensionNames = exts,
      };
      VkInstance inst;
      VkResult r = GIPA(NULL, vkCreateInstance)(&ici, NULL, &inst);
      if (r != VK_SUCCESS) { fprintf(stderr, "vkCreateInstance %d\n", r); return 2; }

      uint32_t n = 1;
      VkPhysicalDevice pd;
      GIPA(inst, vkEnumeratePhysicalDevices)(inst, &n, &pd);
      if (n == 0) { fprintf(stderr, "aucun peripherique\n"); return 2; }

      CAMetalLayer *layer = [CAMetalLayer layer];
      layer.device = MTLCreateSystemDefaultDevice();
      VkMetalSurfaceCreateInfoEXT sci = {
         .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
         .pLayer = layer,
      };
      VkSurfaceKHR surf;
      r = GIPA(inst, vkCreateMetalSurfaceEXT)(inst, &sci, NULL, &surf);
      if (r != VK_SUCCESS) { fprintf(stderr, "vkCreateMetalSurfaceEXT %d\n", r); return 2; }

      const char *env = getenv("MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER");
      int overlay = env && (!strcmp(env, "1") || !strcasecmp(env, "true"));
      printf("mode overlay : %s\n", overlay ? "oui" : "non");

      int erreurs = 0;
      /* Les deux entrees : vkGetPhysicalDeviceSurfaceFormatsKHR (DXVK) et
       * vkGetPhysicalDeviceSurfaceFormats2KHR (vkd3d-proton). */
      for (int voie = 0; voie < 2; voie++) {
         uint32_t c = 0;
         VkSurfaceFormatKHR fmts[256];
         if (voie == 0) {
            PFN_vkGetPhysicalDeviceSurfaceFormatsKHR f =
               GIPA(inst, vkGetPhysicalDeviceSurfaceFormatsKHR);
            f(pd, surf, &c, NULL);
            if (c > 256) c = 256;
            f(pd, surf, &c, fmts);
         } else {
            PFN_vkGetPhysicalDeviceSurfaceFormats2KHR f =
               GIPA(inst, vkGetPhysicalDeviceSurfaceFormats2KHR);
            VkPhysicalDeviceSurfaceInfo2KHR info = {
               .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR,
               .surface = surf };
            f(pd, &info, &c, NULL);
            if (c > 256) c = 256;
            VkSurfaceFormat2KHR f2[256];
            for (uint32_t i = 0; i < c; i++)
               f2[i] = (VkSurfaceFormat2KHR){ .sType = VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR };
            f(pd, &info, &c, f2);
            for (uint32_t i = 0; i < c; i++) fmts[i] = f2[i].surfaceFormat;
         }

         int rgb10_srgb = 0, bgr10_srgb = 0, dix_hdr10 = 0, bgra8_srgb = 0;
         for (uint32_t i = 0; i < c; i++) {
            if (fmts[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
               if (fmts[i].format == VK_FORMAT_A2B10G10R10_UNORM_PACK32) rgb10_srgb++;
               if (fmts[i].format == VK_FORMAT_A2R10G10B10_UNORM_PACK32) bgr10_srgb++;
               if (fmts[i].format == VK_FORMAT_B8G8R8A8_UNORM) bgra8_srgb++;
               printf("  [%s] %s / SRGB_NONLINEAR\n", voie ? "Formats2" : "Formats ",
                      nom_format(fmts[i].format));
            }
            if (fmts[i].colorSpace == VK_COLOR_SPACE_HDR10_ST2084_EXT && dix_bits(fmts[i].format))
               dix_hdr10++;
         }
         printf("  [%s] %u couples ; sRGB : A2B10G10R10 %d, A2R10G10B10 %d ; 10 bits en HDR10 : %d\n",
                voie ? "Formats2" : "Formats ", c, rgb10_srgb, bgr10_srgb, dix_hdr10);

         if (!bgra8_srgb) { printf("  ECHEC : BGRA8 sRGB absent\n"); erreurs++; }
         /* 0193 : RGB10A2 n'est jamais envoye en direct a l'ecran, masque en SDR
          * aussi hors overlay, sauf MESA_WSI_METAL_RGB10A2=1. */
         const char *rgb10 = getenv("MESA_WSI_METAL_RGB10A2");
         int rgb10_voulu = !overlay && rgb10 && (!strcmp(rgb10, "1") || !strcasecmp(rgb10, "true"));
         if (!rgb10_voulu && rgb10_srgb) { printf("  ECHEC : A2B10G10R10 (RGB10A2) annonce en sRGB\n"); erreurs++; }
         if (rgb10_voulu && !rgb10_srgb) { printf("  ECHEC : A2B10G10R10 sRGB attendu avec MESA_WSI_METAL_RGB10A2=1\n"); erreurs++; }
         if (!bgr10_srgb) { printf("  ECHEC : A2R10G10B10 (BGR10A2) sRGB perdu\n"); erreurs++; }
         if (dix_hdr10 != 2) { printf("  ECHEC : HDR10 10 bits perdu\n"); erreurs++; }
      }

      GIPA(inst, vkDestroySurfaceKHR)(inst, surf, NULL);
      GIPA(inst, vkDestroyInstance)(inst, NULL);
      printf("VERDICT : %s\n", erreurs ? "ECHEC" : "OK");
      return erreurs ? 1 : 0;
   }
}
