/* Sonde direct-to-display : reproduit la hierarchie de couches de winemac
 * (cocoa_window.m) dans une appli native, entre dans un espace plein ecran,
 * presente des images et mesure le temps GPU de WindowServer (IORegistry,
 * AGXDeviceUserClient/AppUsage/accumulatedGPUTime). En direct-to-display,
 * WindowServer ne compose plus rien : son temps GPU tombe pres de zero.
 *
 * Construire : clang -arch arm64 -fobjc-arc -O1 -o sonde_direct sonde_affichage_direct.m \
 *   -framework Cocoa -framework Metal -framework QuartzCore -framework IOKit -framework IOSurface
 * puis l'emballer dans une .app et la lancer par `open` (LaunchServices l'active ; lancee
 * d'un terminal elle reste inactive et ne passe jamais en plein ecran), session
 * deverrouillee, ecran allume (~/Dev/cidre-direct/sonde/lancer.sh, serie.sh).
 * Le temoin fiable est detach={...} (code de detachement, 0 = direct) ; ws_gpu (temps GPU de
 * WindowServer) reste a 0 quand c'est le controleur d'affichage qui compose.
 *
 * usage : sonde_direct <variante> [secondes]
 * Les drapeaux de la variante (lettres, dans n'importe quel ordre) :
 *   W  hierarchie Wine : contentView avec contenu (image grise) > vue client > vue Metal
 *      (sinon : la CAMetalLayer est la couche de la contentView, comme un port natif)
 *   T  fenetre non opaque, fond clearColor (winemac)
 *   L  niveau de fenetre NSStatusWindowLevel+1 (winemac, fenetre plein ecran active)
 *   R  contentsScale 2 (drawable a la taille native) ; sinon 1 (mode non retina de winemac)
 *   N  layer.opaque = NO (sinon YES)
 *   M  presentation HideMenuBar|HideDock (0122)
 *   H  contentView de NSToolbarFullScreenWindow masquee (0122)
 *   C  curseur cache
 *   S  displaySyncEnabled = YES (sinon NO, comme DXMT)
 *   A  pixel format BGR10A2 ; B  RGB10A2 ; F RGBA16Float (sinon BGRA8)
 *   K  couche noire (CAShapeLayer) par-dessus, comme setMask: de winemac
 *   G  CAMetalLayer en sous-couche de la contentView au lieu d'une vue (CALayerHost-like : sous-couche nue)
 *   I  magnificationFilter lineaire (defaut de Core Animation) au lieu de nearest (winemac)
 *   U  HUD Metal et son journal (MTL_HUD_ENABLED, MTL_HUD_LOG_ENABLED)
 *   E  vues parentes sans fond ni contenu ; Q  fond noir
 *   Y  une seule vue parente (contentView > vue Metal, sans vue client)
 *   V  avec X : fenetre sous l'encoche seulement (ecran moins la barre des menus)
 *   Z  dans l'espace plein ecran : cadre agrandi a tout l'ecran (encoche comprise) + niveau 26
 *   O  temoin fenetre : 1280x800, ni plein ecran ni couverture de l'ecran
 *   X  pas d'espace plein ecran (fenetre couvrant l'ecran, sans toggleFullScreen)
 *   D  drawable a une taille arbitraire 1280x800 (agrandi par l'affichage)
 *   J  niveau kCGDockWindowLevel+1 (21) avant et apres l'entree dans l'espace : fenetre
 *      topmost de winemac quand `fullscreen` retombe a 0 dans l'espace (LN, mode emule)
 *   P  chemin hors ecran de winemac : CAMetalLayer exportee par un CAContext,
 *      montree par un CALayerHost sous-couche de la contentView (CAContextSwapChain)
 */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/IOKitLib.h>

typedef uint32_t CAContextID;
@interface CAContext : NSObject
+ (id) contextWithCGSConnection:(uint32_t)cid options:(NSDictionary*)dict;
@property(readonly) CAContextID contextId;
@property(retain) CALayer *layer;
@end
@interface CALayerHost : CALayer
@property CAContextID contextId;
@end
extern uint32_t CGSMainConnectionID(void);

@interface CAMetalLayer (Prive)
- (uint64_t) displayCompositingInternalStatus;
@end
@protocol DrawablePrive
- (BOOL) didComposite;
@end
static volatile int n_presentees, n_composees;
#import <IOSurface/IOSurface.h>
extern uint32_t IOSurfaceGetDetachModeCode(IOSurfaceRef) __attribute__((weak_import));
static volatile int codes[16];
static volatile uint32_t code_dernier, code_ou; /* histogramme des codes de detachement (dernier groupe : >=15) */
#include <objc/runtime.h>
static NSString *hud_dernier_libelle;
static IMP imp_label_metric, imp_metric_name, imp_label;
static void note_libelle(id v)
{
    if (![v isKindOfClass:[NSString class]]) return;
    NSString *t = v;
    if ([t rangeOfString:@"Direct"].location != NSNotFound || [t rangeOfString:@"Composited"].location != NSNotFound)
    {
        if (![t isEqualToString:hud_dernier_libelle]) { printf("HUDLABEL %s\n", [t UTF8String]); fflush(stdout); }
        hud_dernier_libelle = [t copy];
    }
}
static void f_label_metric(id self, SEL _cmd, id m, id l) { note_libelle(l); ((void(*)(id,SEL,id,id))imp_label_metric)(self, _cmd, m, l); }
static void f_metric_name(id self, SEL _cmd, id m, id n) { note_libelle(n); ((void(*)(id,SEL,id,id))imp_metric_name)(self, _cmd, m, n); }
static void f_label(id self, SEL _cmd, id m, id v) { note_libelle(v); ((void(*)(id,SEL,id,id))imp_label)(self, _cmd, m, v); }
static void espionner_hud(void)
{
    Class C = objc_getClass("_CADeveloperHUDProperties");
    if (!C) { printf("HUD : classe absente\n"); return; }
    Method m;
    if ((m = class_getInstanceMethod(C, @selector(updateLabelMetric:label:)))) imp_label_metric = method_setImplementation(m, (IMP)f_label_metric);
    if ((m = class_getInstanceMethod(C, @selector(updateMetricName:name:)))) imp_metric_name = method_setImplementation(m, (IMP)f_metric_name);
    if ((m = class_getInstanceMethod(C, @selector(updateLabel:value:)))) imp_label = method_setImplementation(m, (IMP)f_label);
}

static const char *flags = "";
static CAContext *contexte_distant;
static double duree = 6.0;
static BOOL has(char c) { return strchr(flags, c) != NULL; }

static uint64_t ws_gpu_ns(void)
{
    uint64_t total = 0;
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXDeviceUserClient"), &it) != KERN_SUCCESS)
        return 0;
    io_object_t o;
    while ((o = IOIteratorNext(it)))
    {
        CFStringRef creator = IORegistryEntryCreateCFProperty(o, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0);
        if (creator && CFStringFind(creator, CFSTR("WindowServer"), 0).location != kCFNotFound)
        {
            CFArrayRef usage = IORegistryEntryCreateCFProperty(o, CFSTR("AppUsage"), kCFAllocatorDefault, 0);
            if (usage && CFGetTypeID(usage) == CFArrayGetTypeID())
            {
                for (CFIndex i = 0; i < CFArrayGetCount(usage); i++)
                {
                    CFDictionaryRef d = CFArrayGetValueAtIndex(usage, i);
                    CFNumberRef n = CFDictionaryGetValue(d, CFSTR("accumulatedGPUTime"));
                    uint64_t v = 0;
                    if (n && CFNumberGetValue(n, kCFNumberSInt64Type, &v)) total += v;
                }
            }
            if (usage) CFRelease(usage);
        }
        if (creator) CFRelease(creator);
        IOObjectRelease(o);
    }
    IOObjectRelease(it);
    return total;
}

@interface VueMetal : NSView
@end
@implementation VueMetal
- (instancetype) initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { self.wantsLayer = YES; self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever; } return self; }
- (CALayer*) makeBackingLayer { return [CAMetalLayer layer]; }
- (BOOL) isOpaque { return YES; }
@end

@interface VueContenu : NSView
@end
@implementation VueContenu
- (instancetype) initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { self.wantsLayer = YES; } return self; }
- (BOOL) wantsUpdateLayer { return YES; }
- (void) updateLayer
{
    /* winemac pose l'image de la surface GDI comme contenu de la couche */
    if (has('J') || has('j'))
    {
        /* image de la surface GDI : noire (J) ou blanche (j) */
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, 64, 64, 8, 0, cs, kCGImageAlphaNoneSkipFirst);
        CGContextSetGrayFillColor(ctx, has('J') ? 0.0 : 1.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(0, 0, 64, 64));
        CGImageRef img = CGBitmapContextCreateImage(ctx);
        self.layer.contents = (__bridge id)img;
        CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
        self.layer.backgroundColor = NULL;
    }
    else if (has('E')) self.layer.backgroundColor = NULL;
    else if (has('Q')) self.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    else self.layer.backgroundColor = CGColorGetConstantColor(kCGColorWhite);
}
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
    id<MTLDevice> dev;
    id<MTLCommandQueue> q;
    NSTimer *timer;
    unsigned frames;
    BOOL plein;
}
@end

@implementation Sonde

- (void) presenter
{
    id<CAMetalDrawable> d = [layer nextDrawable];
    if (!d) return;
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = d.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    double t = (frames++ % 120) / 120.0;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(t, 0.3, 1.0 - t, 1.0);
    id<MTLCommandBuffer> cb = [q commandBuffer];
    [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
    [d addPresentedHandler:^(id<MTLDrawable> dr) {
        IOSurfaceRef sf = ((id<CAMetalDrawable>)dr).texture.iosurface;
        if (sf && IOSurfaceGetDetachModeCode && dr.presentedTime > 0) { uint32_t c = IOSurfaceGetDetachModeCode(sf); code_dernier = c; __sync_fetch_and_or(&code_ou, c); __sync_fetch_and_add(&codes[c < 15 ? c : 15], 1); }
        if (dr.presentedTime > 0) { __sync_fetch_and_add(&n_presentees, 1); if ([(id<DrawablePrive>)dr didComposite]) __sync_fetch_and_add(&n_composees, 1); }
    }];
    [cb presentDrawable:d];
    [cb commit];
}

- (NSApplicationPresentationOptions) window:(NSWindow*)w willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)p
{
    if (has('M')) return NSApplicationPresentationFullScreen | NSApplicationPresentationHideMenuBar | NSApplicationPresentationHideDock;
    return p;
}

- (void) masquerBarre
{
    for (NSWindow *c in [win childWindows])
        if ([[c className] isEqualToString:@"NSToolbarFullScreenWindow"]) { [[c contentView] setHidden:YES]; [c setIgnoresMouseEvents:YES]; }
}

- (void) majTaille
{
    CGFloat s = has('R') ? 2.0 : 1.0;
    if (has('P'))
    {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        layer.bounds = CGRectMake(0, 0, win.contentView.bounds.size.width, win.contentView.bounds.size.height);
        [CATransaction commit];
    }
    layer.contentsScale = s;
    if (has('D')) layer.drawableSize = CGSizeMake(1280, 800);
    else layer.drawableSize = CGSizeMake(layer.bounds.size.width * s, layer.bounds.size.height * s);
}

- (void) windowDidEnterFullScreen:(NSNotification*)n
{
    plein = YES;
    if (has('H')) [self masquerBarre];
    if (has('J')) [win setLevel:kCGDockWindowLevel + 1];
    if (has('Z'))
    {
        [win setLevel:NSStatusWindowLevel + 1];
        [win setFrame:win.screen.frame display:YES];
    }
    [self majTaille];
    [self performSelector:@selector(mesurer) withObject:nil afterDelay:2.0];
}

- (void) windowDidResize:(NSNotification*)n { [self majTaille]; }

- (void) mesurer
{
    if (has('H')) [self masquerBarre];
    uint64_t a = ws_gpu_ns();
    n_presentees = n_composees = 0;
    for (int i = 0; i < 16; i++) codes[i] = 0;
    code_ou = 0;
    unsigned fa = frames;
    CFAbsoluteTime ta = CFAbsoluteTimeGetCurrent();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duree * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        uint64_t b = ws_gpu_ns();
        double dt = CFAbsoluteTimeGetCurrent() - ta;
        NSRect fr = [win frame];
        NSString *enfants = @"";
        for (NSWindow *c in [win childWindows]) enfants = [enfants stringByAppendingFormat:@"%@(%@,%.0fx%.0f@%.0f,%.0f) ", [c className], [c isVisible] ? @"vis" : @"cach", c.frame.size.width, c.frame.size.height, c.frame.origin.x, c.frame.origin.y];
        NSMutableString *h = [NSMutableString string];
        for (int i = 0; i < 16; i++) if (codes[i]) [h appendFormat:@"%d:%d ", i, codes[i]];
        [h appendFormat:@"dernier=0x%x ou=0x%x", code_dernier, code_ou];
        printf("detach={%s} hud=%s variante=%-8s composees=%4d/%-4d statut=0x%llx ws_gpu=%7.2f ms/s  fps=%5.1f  ms_ws_par_image=%5.3f  fenetre=%.0fx%.0f drawable=%.0fx%.0f echelle=%.0f niveau=%ld opaque_fen=%d enfants=%s\n",
               [h UTF8String], hud_dernier_libelle ? [hud_dernier_libelle UTF8String] : "?", *flags ? flags : "-", n_composees, n_presentees, (unsigned long long)[layer displayCompositingInternalStatus], (b - a) / 1e6 / dt, (frames - fa) / dt, (b - a) / 1e6 / (frames - fa ? frames - fa : 1),
               fr.size.width, fr.size.height, layer.drawableSize.width, layer.drawableSize.height, layer.contentsScale,
               (long)[win level], [win isOpaque], [enfants UTF8String]);
        fflush(stdout);
        if (plein && !has('X') && !has('O')) [win toggleFullScreen:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
    });
}

- (void) applicationDidFinishLaunching:(NSNotification*)n
{
    dev = MTLCreateSystemDefaultDevice();
    if (has('U')) espionner_hud();
    q = [dev newCommandQueue];
    NSScreen *ecran = [NSScreen mainScreen];
    NSRect r = has('X') ? ecran.frame : NSMakeRect(200, 200, 1280, 800);
    if (has('X') && has('V')) r.size.height -= (ecran.frame.size.height - ecran.visibleFrame.size.height - (ecran.visibleFrame.origin.y - ecran.frame.origin.y));
    if (has('O')) flags = flags; /* fenetre simple */
    win = [[Fenetre alloc] initWithContentRect:r styleMask:(has('X') ? NSWindowStyleMaskBorderless : (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)) backing:NSBackingStoreBuffered defer:NO screen:ecran];
    win.delegate = self;
    win.releasedWhenClosed = NO;
    win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    if (has('T')) { [win setBackgroundColor:[NSColor clearColor]]; [win setOpaque:NO]; }

    NSView *contenu;
    if (has('P'))
    {
        contenu = [[VueContenu alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
        win.contentView = contenu;
        layer = [[CAMetalLayer alloc] init];
        layer.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
        layer.anchorPoint = CGPointMake(0, 0);
        contexte_distant = [CAContext contextWithCGSConnection:CGSMainConnectionID() options:@{}];
        contexte_distant.layer = layer;
        CALayerHost *host = [CALayerHost layer];
        host.contextId = contexte_distant.contextId;
        host.magnificationFilter = has('I') ? kCAFilterLinear : kCAFilterNearest;
        host.frame = contenu.layer.bounds;
        host.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        [contenu.layer addSublayer:host];
    }
    else if (has('W') || has('G'))
    {
        contenu = [[VueContenu alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
        win.contentView = contenu;
        if (has('G'))
        {
            layer = [CAMetalLayer layer];
            layer.frame = contenu.layer.bounds;
            layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
            [contenu.layer addSublayer:layer];
        }
        else
        {
            NSView *client = has('Y') ? contenu : [[VueContenu alloc] initWithFrame:contenu.bounds];
            client.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            if (client != contenu) [contenu addSubview:client];
            VueMetal *mv = [[VueMetal alloc] initWithFrame:client.bounds];
            mv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [client setAutoresizesSubviews:YES];
            [client addSubview:mv positioned:NSWindowBelow relativeTo:nil];
            layer = (CAMetalLayer*)mv.layer;
        }
    }
    else
    {
        VueMetal *mv = [[VueMetal alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
        win.contentView = mv;
        layer = (CAMetalLayer*)mv.layer;
    }
    layer.device = dev;
    layer.framebufferOnly = YES;
    layer.magnificationFilter = has('I') ? kCAFilterLinear : kCAFilterNearest;
    layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    layer.opaque = has('N') ? NO : YES;
    layer.displaySyncEnabled = has('S') ? YES : NO;
    layer.pixelFormat = has('A') ? MTLPixelFormatBGR10A2Unorm : has('B') ? MTLPixelFormatRGB10A2Unorm : has('F') ? MTLPixelFormatRGBA16Float : MTLPixelFormatBGRA8Unorm;
    [self majTaille];

    if (has('K'))
    {
        CAShapeLayer *sh = [CAShapeLayer layer];
        sh.frame = win.contentView.layer.bounds;
        sh.fillColor = CGColorGetConstantColor(kCGColorBlack);
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddRect(p, NULL, CGRectMake(0, 0, 40, 4000));
        sh.path = p;
        CGPathRelease(p);
        [win.contentView.layer addSublayer:sh];
    }

    if (has('L')) [win setLevel:NSStatusWindowLevel + 1];
    if (has('J')) [win setLevel:kCGDockWindowLevel + 1];
    [NSApp activate];
    [NSApp activateIgnoringOtherApps:YES];
    [win makeKeyAndOrderFront:nil];
    if (has('C')) [NSCursor hide];

    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 120.0 repeats:YES block:^(NSTimer *t) { [self presenter]; }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

    if (has('X') || has('O'))
    {
        plein = NO;
        [self performSelector:@selector(mesurer) withObject:nil afterDelay:2.0];
    }
    else
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSApp activate];
            [win toggleFullScreen:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!plein) { printf("variante=%s pas en plein ecran apres 4 s : actif=%d cle=%d style=%lx\n", flags, [NSApp isActive], [win isKeyWindow], (unsigned long)[win styleMask]); fflush(stdout); }
            });
        });

    /* garde-fou */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duree + 15) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        printf("variante=%s DELAI DEPASSE\n", flags); fflush(stdout); exit(2);
    });
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1) flags = argv[1];
        if (argc > 2) duree = atof(argv[2]);
        if (strchr(flags, 'U') && !getenv("OS_ACTIVITY_DT_MODE"))
        {
            /* os_log en clair sur stderr (mode Xcode) : lu a l'init de libsystem_trace, d'ou le re-exec */
            setenv("OS_ACTIVITY_DT_MODE", "1", 1);
            setenv("MTL_HUD_ENABLED", "1", 1);
            setenv("MTL_HUD_LOG_ENABLED", "1", 1);
            execv(argv[0], argv);
        }
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        Sonde *s = [Sonde new];
        app.delegate = s;
        [app run];
    }
    return 0;
}
