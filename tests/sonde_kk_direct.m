/* Sonde affichage direct a travers KosmicKrisp : fenetre native en espace plein
 * ecran, CAMetalLayer donnee a vkCreateMetalSurfaceEXT, swapchain Vulkan
 * compositeAlpha OPAQUE (comme vkd3d-proton), images effacees par
 * vkCmdClearColorImage (alpha 0,25 : la WSI doit le ramener a 1), presentees
 * en boucle. Releve toutes les 0,25 s le code de detachement de la couche
 * (32 bits bas de -[CAMetalLayer displayCompositingInternalStatus], 0 = direct)
 * et l'etat de la couche (opaque, format) fixe par la WSI.
 *
 * Construction : clang -arch arm64 -fobjc-arc -O1 -I src/Vulkan-Headers/include tests/sonde_kk_direct.m \
 *    -framework Cocoa -framework Metal -framework QuartzCore -o sonde_kk_direct ; emballer en .app
 *    (Info.plist minimal, codesign -s -) : une appli lancee d'un terminal reste inactive.
 * usage (par LaunchServices, sinon l'appli reste inactive) :
 *   open -n -W --stdout out.txt --env MESA_WSI_METAL_OPAQUE=... SondeKK.app \
 *        --args <libvulkan_kosmickrisp.dylib> <format: bgra8|rgb10a2|bgr10a2> [secondes]
 * Le curseur est cache (un curseur visible force la composition, 0x70017).
 */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <pthread.h>
#define VK_USE_PLATFORM_METAL_EXT
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

@interface CAMetalLayer (Prive)
- (uint64_t) displayCompositingInternalStatus;
@end

static const char *icd, *nom_format = "bgra8";
static double duree = 6.0;
static PFN_vkGetInstanceProcAddr gipa;
static VkInstance inst;
static VkPhysicalDevice pd;
static VkDevice dev;
static VkQueue file;
static VkSurfaceKHR surf;
static VkSwapchainKHR sc;
static VkImage images[8];
static uint32_t n_images;
static VkCommandPool pool;
static VkCommandBuffer cbs[8];
static VkSemaphore sem_acq[8], sem_fin[8];
static VkFence fences[8];
static volatile int fini, n_presentees, n_erreurs;
static VkResult derniere_erreur;
#define P(x) PFN_##x x
static P(vkGetDeviceProcAddr);
static P(vkAcquireNextImageKHR); static P(vkQueuePresentKHR); static P(vkQueueSubmit);
static P(vkBeginCommandBuffer); static P(vkEndCommandBuffer); static P(vkCmdPipelineBarrier);
static P(vkCmdClearColorImage); static P(vkWaitForFences); static P(vkResetFences);
static P(vkDeviceWaitIdle);
#define GI(n) n = (PFN_##n)gipa(inst, #n)
#define GD(n) n = (PFN_##n)vkGetDeviceProcAddr(dev, #n)

static int codes_n;
static uint32_t codes_val[32], codes_cpt[32];
static void noter_code(uint32_t c)
{
   for (int i = 0; i < codes_n; i++) if (codes_val[i] == c) { codes_cpt[i]++; return; }
   if (codes_n < 32) { codes_val[codes_n] = c; codes_cpt[codes_n++] = 1; }
}

static VkFormat format_voulu(void)
{
   if (!strcmp(nom_format, "rgb10a2")) return VK_FORMAT_A2B10G10R10_UNORM_PACK32;
   if (!strcmp(nom_format, "bgr10a2")) return VK_FORMAT_A2R10G10B10_UNORM_PACK32;
   return VK_FORMAT_B8G8R8A8_UNORM;
}

static int init_vulkan(CAMetalLayer *layer, uint32_t w, uint32_t h)
{
   void *lib = dlopen(icd, RTLD_NOW | RTLD_LOCAL);
   if (!lib) { printf("dlopen %s : %s\n", icd, dlerror()); return 1; }
   gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vk_icdGetInstanceProcAddr");
   if (!gipa) gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
   const char *iext[] = { "VK_KHR_surface", "VK_EXT_metal_surface", "VK_KHR_get_surface_capabilities2",
                          "VK_EXT_swapchain_colorspace", "VK_KHR_portability_enumeration" };
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
                                .enabledExtensionCount = 4, .ppEnabledExtensionNames = iext };
   PFN_vkCreateInstance ci = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
   VkResult r = ci(&ici, NULL, &inst);
   if (r) { printf("vkCreateInstance %d\n", r); return 1; }
   uint32_t n = 1;
   ((PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices"))(inst, &n, &pd);
   VkMetalSurfaceCreateInfoEXT sci = { .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, .pLayer = layer };
   r = ((PFN_vkCreateMetalSurfaceEXT)gipa(inst, "vkCreateMetalSurfaceEXT"))(inst, &sci, NULL, &surf);
   if (r) { printf("vkCreateMetalSurfaceEXT %d\n", r); return 1; }

   /* Le format est-il annonce ? (0193 masque A2B10G10R10 en SDR) */
   VkSurfaceFormatKHR fmts[256]; uint32_t nf = 256;
   ((PFN_vkGetPhysicalDeviceSurfaceFormatsKHR)gipa(inst, "vkGetPhysicalDeviceSurfaceFormatsKHR"))(pd, surf, &nf, fmts);
   int annonce = 0;
   for (uint32_t i = 0; i < nf; i++)
      if (fmts[i].format == format_voulu() && fmts[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) annonce = 1;
   printf("format %s annonce en sRGB : %s (%u couples)\n", nom_format, annonce ? "oui" : "non", nf);

   float prio = 1;
   VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio };
   const char *dext[] = { "VK_KHR_swapchain" };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci,
                              .enabledExtensionCount = 1, .ppEnabledExtensionNames = dext };
   r = ((PFN_vkCreateDevice)gipa(inst, "vkCreateDevice"))(pd, &dci, NULL, &dev);
   if (r) { printf("vkCreateDevice %d\n", r); return 1; }
   GI(vkGetDeviceProcAddr);
   ((PFN_vkGetDeviceQueue)vkGetDeviceProcAddr(dev, "vkGetDeviceQueue"))(dev, 0, 0, &file);
   GD(vkAcquireNextImageKHR); GD(vkQueuePresentKHR); GD(vkQueueSubmit); GD(vkBeginCommandBuffer);
   GD(vkEndCommandBuffer); GD(vkCmdPipelineBarrier); GD(vkCmdClearColorImage); GD(vkWaitForFences);
   GD(vkResetFences); GD(vkDeviceWaitIdle);

   VkSwapchainCreateInfoKHR sci2 = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, .surface = surf, .minImageCount = 3,
      .imageFormat = format_voulu(), .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
      .imageExtent = { w, h }, .imageArrayLayers = 1,
      .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
      .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
      .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = VK_TRUE };
   r = ((PFN_vkCreateSwapchainKHR)vkGetDeviceProcAddr(dev, "vkCreateSwapchainKHR"))(dev, &sci2, NULL, &sc);
   if (r) { printf("vkCreateSwapchainKHR %d\n", r); return 1; }
   n_images = 8;
   ((PFN_vkGetSwapchainImagesKHR)vkGetDeviceProcAddr(dev, "vkGetSwapchainImagesKHR"))(dev, sc, &n_images, images);

   VkCommandPoolCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                   .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
   ((PFN_vkCreateCommandPool)vkGetDeviceProcAddr(dev, "vkCreateCommandPool"))(dev, &pci, NULL, &pool);
   VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool,
                                       .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 8 };
   ((PFN_vkAllocateCommandBuffers)vkGetDeviceProcAddr(dev, "vkAllocateCommandBuffers"))(dev, &cai, cbs);
   for (int i = 0; i < 8; i++) {
      VkSemaphoreCreateInfo s = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
      VkFenceCreateInfo f = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
      ((PFN_vkCreateSemaphore)vkGetDeviceProcAddr(dev, "vkCreateSemaphore"))(dev, &s, NULL, &sem_acq[i]);
      ((PFN_vkCreateSemaphore)vkGetDeviceProcAddr(dev, "vkCreateSemaphore"))(dev, &s, NULL, &sem_fin[i]);
      ((PFN_vkCreateFence)vkGetDeviceProcAddr(dev, "vkCreateFence"))(dev, &f, NULL, &fences[i]);
   }
   return 0;
}

static void *boucle(void *arg)
{
   unsigned k = 0;
   while (!fini) {
      unsigned s = k % 3;
      vkWaitForFences(dev, 1, &fences[s], VK_TRUE, UINT64_MAX);
      uint32_t idx;
      VkResult r = vkAcquireNextImageKHR(dev, sc, 2000000000ull, sem_acq[s], VK_NULL_HANDLE, &idx);
      if (r < 0) { derniere_erreur = r; n_erreurs++; usleep(10000); continue; }
      vkResetFences(dev, 1, &fences[s]);
      VkCommandBuffer cb = cbs[s];
      VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
      vkBeginCommandBuffer(cb, &bi);
      VkImageSubresourceRange rg = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
      VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                                 .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                 .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                 .image = images[idx], .subresourceRange = rg };
      vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
      float t = (k % 120) / 120.0f;
      VkClearColorValue c = { .float32 = { t, 0.3f, 1.0f - t, 0.25f } };
      vkCmdClearColorImage(cb, images[idx], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &c, 1, &rg);
      b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask = 0;
      b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
      vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &b);
      vkEndCommandBuffer(cb);
      VkPipelineStageFlags st = VK_PIPELINE_STAGE_TRANSFER_BIT;
      VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .waitSemaphoreCount = 1, .pWaitSemaphores = &sem_acq[s],
                          .pWaitDstStageMask = &st, .commandBufferCount = 1, .pCommandBuffers = &cb,
                          .signalSemaphoreCount = 1, .pSignalSemaphores = &sem_fin[s] };
      vkQueueSubmit(file, 1, &si, fences[s]);
      VkPresentInfoKHR pi = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = 1, .pWaitSemaphores = &sem_fin[s],
                              .swapchainCount = 1, .pSwapchains = &sc, .pImageIndices = &idx };
      r = vkQueuePresentKHR(file, &pi);
      if (r < 0) { derniere_erreur = r; n_erreurs++; }
      else n_presentees++;
      k++;
   }
   vkDeviceWaitIdle(dev);
   return NULL;
}

@interface VueMetal : NSView
@end
@implementation VueMetal
- (instancetype) initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { self.wantsLayer = YES; self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever; } return self; }
- (CALayer*) makeBackingLayer { return [CAMetalLayer layer]; }
- (BOOL) isOpaque { return YES; }
@end

@interface Fenetre : NSWindow
@end
@implementation Fenetre
- (BOOL) canBecomeKeyWindow { return YES; }
- (BOOL) canBecomeMainWindow { return YES; }
@end

@interface Sonde : NSObject <NSApplicationDelegate, NSWindowDelegate>
{
@public
   Fenetre *win;
   CAMetalLayer *layer;
   BOOL plein, demarre;
   pthread_t fil;
}
@end

@implementation Sonde
- (void) windowDidEnterFullScreen:(NSNotification*)n
{
   plein = YES;
   [NSCursor hide];
   CGFloat s = 1.0;
   layer.contentsScale = s;
   uint32_t w = layer.bounds.size.width * s, h = layer.bounds.size.height * s;
   if (init_vulkan(layer, w, h)) { fflush(stdout); [NSApp terminate:nil]; return; }
   printf("couche apres swapchain : opaque=%d format=%lu drawable=%.0fx%.0f\n", layer.opaque,
          (unsigned long)layer.pixelFormat, layer.drawableSize.width, layer.drawableSize.height);
   fflush(stdout);
   pthread_create(&fil, NULL, boucle, NULL);
   demarre = YES;
   /* 2 s de mise en route, puis releve */
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      int p0 = n_presentees;
      CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
      NSTimer *tm = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) {
         noter_code((uint32_t)[layer displayCompositingInternalStatus]);
      }];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duree * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
         [tm invalidate];
         double dt = CFAbsoluteTimeGetCurrent() - t0;
         NSMutableString *h = [NSMutableString string];
         for (int i = 0; i < codes_n; i++) [h appendFormat:@"0x%x:%u ", codes_val[i], codes_cpt[i]];
         printf("RESULTAT format=%s opaque=%d fmt_couche=%lu detach={%s} images/s=%.1f erreurs=%d (%d)\n",
                nom_format, layer.opaque, (unsigned long)layer.pixelFormat, [h UTF8String],
                (n_presentees - p0) / dt, n_erreurs, derniere_erreur);
         fflush(stdout);
         fini = 1;
         pthread_join(fil, NULL);
         [win toggleFullScreen:nil];
         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
      });
   });
}

- (void) applicationDidFinishLaunching:(NSNotification*)n
{
   NSScreen *ecran = [NSScreen mainScreen];
   NSRect r = NSMakeRect(200, 200, 1280, 800);
   win = [[Fenetre alloc] initWithContentRect:r styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                      backing:NSBackingStoreBuffered defer:NO screen:ecran];
   win.delegate = self;
   win.releasedWhenClosed = NO;
   win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
   VueMetal *mv = [[VueMetal alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
   win.contentView = mv;
   layer = (CAMetalLayer*)mv.layer;
   layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
   [NSApp activate];
   [NSApp activateIgnoringOtherApps:YES];
   [win makeKeyAndOrderFront:nil];
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [NSApp activate];
      [win toggleFullScreen:nil];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
         if (!plein) { printf("pas en plein ecran apres 4 s : actif=%d\n", [NSApp isActive]); fflush(stdout); }
      });
   });
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duree + 15) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      printf("DELAI DEPASSE\n"); fflush(stdout); exit(2);
   });
}
@end

int main(int argc, char **argv)
{
   @autoreleasepool {
      if (argc < 2) { fprintf(stderr, "usage : sonde_kk_direct <icd> [bgra8|rgb10a2|bgr10a2] [secondes]\n"); return 2; }
      icd = argv[1];
      if (argc > 2) nom_format = argv[2];
      if (argc > 3) duree = atof(argv[3]);
      printf("MESA_WSI_METAL_OPAQUE=%s MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER=%s MESA_WSI_METAL_RGB10A2=%s\n",
             getenv("MESA_WSI_METAL_OPAQUE") ?: "-", getenv("MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER") ?: "-",
             getenv("MESA_WSI_METAL_RGB10A2") ?: "-");
      NSApplication *app = [NSApplication sharedApplication];
      [app setActivationPolicy:NSApplicationActivationPolicyRegular];
      Sonde *s = [Sonde new];
      app.delegate = s;
      [app run];
   }
   return 0;
}
