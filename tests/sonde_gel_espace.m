/* Sonde du gel au changement d'espace macOS (2026-10-16).
 *
 * Constat : Sherlock Holmes Chapter One (DXMT) et PEAK (vkd3d -> KosmicKrisp)
 * figent quand on quitte l'espace plein ecran du jeu (cmd-tab, ctrl-fleche).
 * Les stackshots du watchdog de WindowServer montrent deux soumissions Metal
 * bloquees dans le noyau (IOGPUFamily -> AGXG13X), et rien d'autre :
 *   - WindowServer, fil principal : WSCaptureMenuResolveDesktopChanges ->
 *     CaptureSurfaceMetal::Populate -> MetalContext::Flush ->
 *     -[_MTLCommandQueue submitCommandBuffer:] (capture de l'espace qu'on quitte) ;
 *   - le jeu, file com.Metal.CommandQueueDispatch :
 *     -[_MTLCommandQueue _submitAvailableCommandBuffers] ;
 *   dxmt-finish-thr attend waitUntilCompleted d'un tampon jamais soumis.
 * WindowServer ne repond plus, watchdog a 40 s, panique a 120 s.
 *
 * Cette sonde rejoue la presentation de DXMT hors de Wine (fenetre promue en
 * espace plein ecran, CAMetalLayer, displaySyncEnabled = NO,
 * presentDrawable:afterMinimumDuration:, rendu hors ecran puis copie dans le
 * drawable depuis un fil a part) et quitte puis retrouve son espace elle-meme,
 * en activant le Finder puis en se reactivant : aucune touche, aucune
 * permission d'accessibilite.
 *
 * Garde : si aucun tampon ne se termine pendant --garde secondes, la sonde
 * ecrit son journal et sort (_exit) -- la fin du processus doit liberer la
 * soumission de WindowServer bien avant son watchdog. NE PAS LANCER sans
 * l'utilisateur devant la machine : un gel peut la reprendre.
 *
 *   cc -fobjc-arc -O1 -o sonde-gel-espace sonde_gel_espace.m \
 *      -framework Cocoa -framework Metal -framework QuartzCore
 *   ./sonde-gel-espace --bascules 6            # comme DXMT
 *   ./sonde-gel-espace --sync 1                # vsync de CoreAnimation
 *   ./sonde-gel-espace --cache-pause 1         # correctif : rien presenter hors de l'espace actif
 *   ./sonde-gel-espace --fenetre 1             # temoin : fenetre ordinaire, pas d'espace
 *
 * Options (valeurs par defaut entre crochets) :
 *   --sync 0|1        displaySyncEnabled [0, comme dxmt_presenter.cpp]
 *   --apres S         presentDrawable:afterMinimumDuration: S (0 = presentDrawable) [0.008]
 *   --event 0|1       chaque image attend (encodeWaitForEvent) un event signale
 *                     par une seconde file, comme l'initialiseur de ressources de DXMT [1]
 *   --charge N        iterations du nuanceur de fragment (temps GPU par image) [200]
 *   --bascules N      allers-retours d'espace [4]
 *   --tenue S         secondes dans l'espace du jeu avant de le quitter [4]
 *   --ailleurs S      secondes hors de l'espace [3]
 *   --garde S         sortie si aucun tampon termine depuis S secondes [4]
 *   --fenetre 0|1     1 = pas de plein ecran (temoin) [0]
 *   --cache-pause 0|1 correctif : ne plus demander de drawable ni presenter tant
 *                     que la fenetre n'est pas visible ou que l'appli n'est pas active [0]
 *   --cb N            tampons par image (les N-1 premiers : passe de charge seule,
 *                     plus un envoi par blit sur la seconde file) [1]
 *   --options 0|1     options de presentation de 0122 (HideMenuBar, HideDock) [0]
 *   --journal F       fichier du journal [sonde-gel-espace.journal]
 */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <pthread.h>
#include <unistd.h>

static int    o_cb = 1, o_options = 0;
static int    o_sync = 0, o_event = 1, o_charge = 200, o_bascules = 4, o_fenetre = 0, o_cache_pause = 0;
static double o_apres = 0.008, o_tenue = 4, o_ailleurs = 3, o_garde = 4;
static const char *o_journal = "sonde-gel-espace.journal";

/* ---- journal silencieux en anneau (une sonde bavarde masque les courses) */
enum { J_IMAGE = 1, J_FINI, J_DRAWABLE_NUL, J_OCCLUSION, J_ACTIF, J_ESPACE, J_PHASE, J_SAUTE, J_DRAWABLE_LENT };
static const char *j_noms[] = { "?", "image", "fini", "drawable-nul", "occlusion", "actif", "espace", "phase", "saute", "drawable-lent" };
typedef struct { double t; int type; long a; double b; } entree;
#define J_TAILLE 65536
static entree j_anneau[J_TAILLE];
static _Atomic long j_index;
static double t0;
static mach_timebase_info_data_t tb;

static double maintenant(void) {
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9 - t0;
}
static void noter(int type, long a, double b) {
  long i = atomic_fetch_add(&j_index, 1);
  j_anneau[i % J_TAILLE] = (entree){ maintenant(), type, a, b };
}
static void vider_journal(const char *pourquoi) {
  FILE *f = fopen(o_journal, "w");
  if (!f) f = stderr;
  long n = atomic_load(&j_index), debut = n > J_TAILLE ? n - J_TAILLE : 0;
  fprintf(f, "# sonde-gel-espace : %s ; cb=%d options=%d sync=%d apres=%.4f event=%d charge=%d fenetre=%d cache_pause=%d\n",
          pourquoi, o_cb, o_options, o_sync, o_apres, o_event, o_charge, o_fenetre, o_cache_pause);
  for (long i = debut; i < n; i++) {
    entree *e = &j_anneau[i % J_TAILLE];
    /* les images sont nombreuses : on n'ecrit que les 400 dernieres et les evenements */
    if ((e->type == J_IMAGE || e->type == J_FINI) && n - i > 400) continue;
    fprintf(f, "%10.4f %-14s %8ld %10.4f\n", e->t, j_noms[e->type], e->a, e->b);
  }
  if (f != stderr) fclose(f);
}

/* ---- etat partage */
static _Atomic double dernier_fini;       /* instant du dernier tampon termine */
static _Atomic long   tampons_finis, tampons_commis;
static _Atomic int    fenetre_visible = 1, appli_active = 1;
static _Atomic int    largeur = 0, hauteur = 0;
static _Atomic int    arret;

static void *garde(void *arg) {
  (void)arg;
  for (;;) {
    usleep(200000);
    double t = maintenant(), d = atomic_load(&dernier_fini);
    long commis = atomic_load(&tampons_commis), finis = atomic_load(&tampons_finis);
    if (d > 0 && commis > finis && t - d > o_garde) {
      char msg[256];
      snprintf(msg, sizeof msg, "GEL : aucun tampon termine depuis %.1f s (commis %ld, finis %ld)", t - d, commis, finis);
      noter(J_PHASE, -1, t - d);
      vider_journal(msg);
      fprintf(stderr, "%s -- journal dans %s, sortie\n", msg, o_journal);
      system("ioreg -r -c IOAccelerator -d 1 | grep -o '\"Device Utilization %\"=[0-9]*' >&2");
      _exit(3);
    }
  }
  return NULL;
}

/* ---- rendu, depuis un fil a part comme dxmt-encode-thr */
static NSString *source_msl =
  @"#include <metal_stdlib>\nusing namespace metal;\n"
   "struct V { float4 p [[position]]; float2 uv; };\n"
   "vertex V vs(uint i [[vertex_id]]) { float2 q = float2((i << 1) & 2, i & 2);"
   "  V v; v.p = float4(q * 2.0 - 1.0, 0, 1); v.uv = float2(q.x, 1.0 - q.y); return v; }\n"
   "fragment float4 fs_charge(V v [[stage_in]], constant uint &n [[buffer(0)]], constant float &t [[buffer(1)]]) {"
   "  float c = v.uv.x + t;"
   "  for (uint i = 0; i < n; i++) c = fract(sin(c * 12.9898 + v.uv.y) * 43758.5453);"
   "  return float4(c, v.uv.y, fract(t), 1); }\n"
   "fragment float4 fs_copie(V v [[stage_in]], texture2d<float> s [[texture(0)]]) {"
   "  constexpr sampler e(filter::linear); return s.sample(e, v.uv); }\n";

static void *rendu(void *arg) {
  CAMetalLayer *couche = (__bridge CAMetalLayer *)arg;
  id<MTLDevice> dev = couche.device;
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:source_msl options:nil error:&err];
  if (!lib) { fprintf(stderr, "MSL : %s\n", err.description.UTF8String); exit(2); }
  MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
  d.vertexFunction = [lib newFunctionWithName:@"vs"];
  d.fragmentFunction = [lib newFunctionWithName:@"fs_charge"];
  d.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> pso_charge = [dev newRenderPipelineStateWithDescriptor:d error:&err];
  d.fragmentFunction = [lib newFunctionWithName:@"fs_copie"];
  d.colorAttachments[0].pixelFormat = couche.pixelFormat;
  id<MTLRenderPipelineState> pso_copie = [dev newRenderPipelineStateWithDescriptor:d error:&err];

  id<MTLCommandQueue> file = [dev newCommandQueueWithMaxCommandBufferCount:32]; /* kCommandChunkCount */
  id<MTLCommandQueue> file_init = [dev newCommandQueueWithMaxCommandBufferCount:16];
  id<MTLSharedEvent> ev = [dev newSharedEvent];
  uint64_t ev_val = 0;
  dispatch_semaphore_t en_vol = dispatch_semaphore_create(3); /* latence d'images */
  id<MTLTexture> arriere = nil;
  id<MTLBuffer> tampon_envoi = [dev newBufferWithLength:16 << 20 options:MTLResourceStorageModePrivate];
  long image = 0;

  while (!atomic_load(&arret)) {
    @autoreleasepool {
      int w = atomic_load(&largeur), h = atomic_load(&hauteur);
      if (w <= 0 || h <= 0) { usleep(10000); continue; }
      if (!arriere || arriere.width != (NSUInteger)w || arriere.height != (NSUInteger)h) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:w height:h mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModePrivate;
        arriere = [dev newTextureWithDescriptor:td];
      }
      dispatch_semaphore_wait(en_vol, DISPATCH_TIME_FOREVER);

      for (int k = 1; k < o_cb; k++) { /* DXMT : plusieurs tampons par image, avec envois */
        id<MTLCommandBuffer> cu = [file_init commandBuffer];
        id<MTLBlitCommandEncoder> bl = [cu blitCommandEncoder];
        [bl fillBuffer:tampon_envoi range:NSMakeRange(0, tampon_envoi.length) value:(uint8_t)k];
        [bl endEncoding];
        [cu encodeSignalEvent:ev value:++ev_val];
        [cu commit];
        id<MTLCommandBuffer> cx = [file commandBuffer];
        [cx encodeWaitForEvent:ev value:ev_val];
        MTLRenderPassDescriptor *rx = [MTLRenderPassDescriptor renderPassDescriptor];
        rx.colorAttachments[0].texture = arriere;
        rx.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        rx.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> ex = [cx renderCommandEncoderWithDescriptor:rx];
        uint32_t nx = o_charge; float tx = (float)k;
        [ex setRenderPipelineState:pso_charge];
        [ex setFragmentBytes:&nx length:4 atIndex:0];
        [ex setFragmentBytes:&tx length:4 atIndex:1];
        [ex drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [ex endEncoding];
        [cx commit];
      }
      if (o_event) { /* l'initialiseur de DXMT : une autre file signale, la principale attend */
        id<MTLCommandBuffer> cb0 = [file_init commandBuffer];
        [cb0 encodeSignalEvent:ev value:++ev_val];
        [cb0 commit];
      }
      id<MTLCommandBuffer> cb = [file commandBuffer];
      if (o_event) [cb encodeWaitForEvent:ev value:ev_val];

      MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture = arriere;
      rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
      rp.colorAttachments[0].storeAction = MTLStoreActionStore;
      id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
      uint32_t n = o_charge; float t = (float)maintenant();
      [enc setRenderPipelineState:pso_charge];
      [enc setFragmentBytes:&n length:4 atIndex:0];
      [enc setFragmentBytes:&t length:4 atIndex:1];
      [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [enc endEncoding];

      bool presenter = true;
      if (o_cache_pause && (!atomic_load(&fenetre_visible) || !atomic_load(&appli_active))) {
        presenter = false;
        noter(J_SAUTE, image, 0);
      }
      if (presenter) {
        double a = maintenant();
        id<CAMetalDrawable> dr = [couche nextDrawable];
        double b = maintenant();
        if (b - a > 0.1) noter(J_DRAWABLE_LENT, image, b - a);
        if (!dr) {
          noter(J_DRAWABLE_NUL, image, b - a);
        } else {
          MTLRenderPassDescriptor *rp2 = [MTLRenderPassDescriptor renderPassDescriptor];
          rp2.colorAttachments[0].texture = dr.texture;
          rp2.colorAttachments[0].loadAction = MTLLoadActionDontCare;
          rp2.colorAttachments[0].storeAction = MTLStoreActionStore;
          id<MTLRenderCommandEncoder> e2 = [cb renderCommandEncoderWithDescriptor:rp2];
          [e2 setRenderPipelineState:pso_copie];
          [e2 setFragmentTexture:arriere atIndex:0];
          [e2 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
          [e2 endEncoding];
          if (o_apres > 0) [cb presentDrawable:dr afterMinimumDuration:o_apres];
          else [cb presentDrawable:dr];
        }
      } else {
        usleep(16000);
      }
      long ici = image;
      double tc = maintenant();
      [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
        double tf = maintenant();
        atomic_store(&dernier_fini, tf);
        atomic_fetch_add(&tampons_finis, 1);
        noter(J_FINI, ici, tf - tc);
        if (c.status == MTLCommandBufferStatusError) noter(J_PHASE, -2, (double)c.error.code);
        dispatch_semaphore_signal(en_vol);
      }];
      atomic_fetch_add(&tampons_commis, 1);
      if (atomic_load(&dernier_fini) == 0) atomic_store(&dernier_fini, tc);
      [cb commit];
      noter(J_IMAGE, image, presenter);
      image++;
    }
  }
  return NULL;
}

/* ---- appli */
@interface Sonde : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *fenetre;
@property CAMetalLayer *couche;
@property int bascule;
@end

@implementation Sonde
- (void)majTaille {
  CGFloat s = self.fenetre.backingScaleFactor;
  NSSize z = self.fenetre.contentView.bounds.size;
  self.couche.drawableSize = CGSizeMake(z.width * s, z.height * s);
  atomic_store(&largeur, (int)(z.width * s));
  atomic_store(&hauteur, (int)(z.height * s));
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  NSRect r = NSScreen.mainScreen.frame;
  NSWindowStyleMask m = o_fenetre ? (NSWindowStyleMaskTitled | NSWindowStyleMaskResizable) : NSWindowStyleMaskBorderless;
  if (o_fenetre) r = NSMakeRect(100, 100, 1280, 720);
  self.fenetre = [[NSWindow alloc] initWithContentRect:r styleMask:m backing:NSBackingStoreBuffered defer:NO];
  self.fenetre.delegate = self;
  self.fenetre.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
  self.couche = [CAMetalLayer layer];
  self.couche.device = MTLCreateSystemDefaultDevice();
  self.couche.pixelFormat = MTLPixelFormatBGRA8Unorm;
  self.couche.framebufferOnly = YES;
  self.couche.displaySyncEnabled = o_sync;          /* DXMT : false */
  self.couche.maximumDrawableCount = 3;
  self.fenetre.contentView.wantsLayer = YES;
  self.fenetre.contentView.layer = self.couche;
  [self.fenetre makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [self majTaille];

  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  [nc addObserverForName:NSWindowDidChangeOcclusionStateNotification object:self.fenetre queue:nil
              usingBlock:^(NSNotification *x) {
    int v = (self.fenetre.occlusionState & NSWindowOcclusionStateVisible) != 0;
    atomic_store(&fenetre_visible, v); noter(J_OCCLUSION, v, 0); }];
  [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil
              usingBlock:^(NSNotification *x) { atomic_store(&appli_active, 1); noter(J_ACTIF, 1, 0); }];
  [nc addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:nil
              usingBlock:^(NSNotification *x) { atomic_store(&appli_active, 0); noter(J_ACTIF, 0, 0); }];
  [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
              object:nil queue:nil usingBlock:^(NSNotification *x) {
    noter(J_ESPACE, self.fenetre.isOnActiveSpace, 0); }];

  pthread_t f;
  pthread_create(&f, NULL, garde, NULL);
  pthread_create(&f, NULL, rendu, (__bridge void *)self.couche);

  if (!o_fenetre) {
    noter(J_PHASE, 0, 0); /* entree dans l'espace */
    [self.fenetre toggleFullScreen:nil];
  }
  [self performSelector:@selector(quitter) withObject:nil afterDelay:1.5 + o_tenue];
}
- (NSApplicationPresentationOptions)window:(NSWindow *)w willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)o {
  /* comme 0122 (cocoa_window.m) : Hide* remplace AutoHide*, AppKit refuse les deux
     ensemble (NSInvalidArgumentException, manche rafale du 2026-10-16) */
  if (o_options)
    return NSApplicationPresentationFullScreen | NSApplicationPresentationHideMenuBar |
           NSApplicationPresentationHideDock;
  return o;
}
- (void)windowDidResize:(NSNotification *)n { [self majTaille]; }
- (void)quitter { /* quitter l'espace : le Finder vit sur le bureau */
  if (self.bascule >= o_bascules) { [self finir]; return; }
  noter(J_PHASE, 10 + self.bascule, 0);
  fprintf(stderr, "bascule %d : on quitte l'espace (finis %ld)\n", self.bascule + 1, atomic_load(&tampons_finis));
  [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject
      activateWithOptions:NSApplicationActivateAllWindows];
  [self performSelector:@selector(revenir) withObject:nil afterDelay:o_ailleurs];
}
- (void)revenir {
  noter(J_PHASE, 20 + self.bascule, 0);
  fprintf(stderr, "bascule %d : retour (finis %ld)\n", self.bascule + 1, atomic_load(&tampons_finis));
  [NSApp activateIgnoringOtherApps:YES];
  [self.fenetre makeKeyAndOrderFront:nil];
  self.bascule++;
  [self performSelector:@selector(quitter) withObject:nil afterDelay:o_tenue];
}
- (void)finir {
  atomic_store(&arret, 1);
  usleep(200000);
  char msg[160];
  snprintf(msg, sizeof msg, "fin normale : %d bascules, commis %ld, finis %ld",
           o_bascules, atomic_load(&tampons_commis), atomic_load(&tampons_finis));
  vider_journal(msg);
  fprintf(stderr, "%s -- journal dans %s\n", msg, o_journal);
  exit(0);
}
@end

int main(int argc, char **argv) {
  mach_timebase_info(&tb);
  t0 = (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
  for (int i = 1; i + 1 < argc; i += 2) {
    const char *k = argv[i], *v = argv[i + 1];
    if (!strcmp(k, "--sync")) o_sync = atoi(v);
    else if (!strcmp(k, "--apres")) o_apres = atof(v);
    else if (!strcmp(k, "--event")) o_event = atoi(v);
    else if (!strcmp(k, "--charge")) o_charge = atoi(v);
    else if (!strcmp(k, "--bascules")) o_bascules = atoi(v);
    else if (!strcmp(k, "--tenue")) o_tenue = atof(v);
    else if (!strcmp(k, "--ailleurs")) o_ailleurs = atof(v);
    else if (!strcmp(k, "--garde")) o_garde = atof(v);
    else if (!strcmp(k, "--fenetre")) o_fenetre = atoi(v);
    else if (!strcmp(k, "--cache-pause")) o_cache_pause = atoi(v);
    else if (!strcmp(k, "--cb")) o_cb = atoi(v);
    else if (!strcmp(k, "--options")) o_options = atoi(v);
    else if (!strcmp(k, "--journal")) o_journal = v;
    else { fprintf(stderr, "option inconnue : %s\n", k); return 2; }
  }
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    Sonde *s = [Sonde new];
    NSApp.delegate = s;
    [NSApp run];
  }
  return 0;
}
