// Sonde native de MetalFX temporel (sans Wine ni DXMT) : ce qu'Expedition 33 lui fait
// faire par DLSS sur le M1, sans le jeu. Textures aux formats du jeu (couleur
// RG11B10Float 1244x780, profondeur R32Float inversee, vecteurs RG16Float, sortie
// RGBA16Float 1384x868), reglages de DXMT (contenu variable 1x-3x, exposition auto,
// initialisation synchrone), entrees reecrites a chaque image par un calcul (scene
// qui glisse, jitter de Halton, vecteurs exacts). Modes :
//   fixe    contenu 1241x779 a chaque image ;
//   dyn     contenu qui change a chaque image entre 692x434 et 1241x779 (definition
//           dynamique d'Unreal) ;
//   deux    dyn + un second scaler (entree 692x436) alterne toutes les 2 s, comme les
//           deux qu'a crees le jeu.
// Garde : le journal GPU de winemetal (bloc « cidre-journal-gpu », meme code que le jeu)
// et un arret net : plus aucun tampon termine depuis 1,5 s -> on cesse de soumettre et
// le processus sort aussitot (code 3), pour rendre le GPU au plus vite.
//   sh construire_sonde_metalfx_temporel.sh
//   ./sonde_metalfx_temporel <fixe|dyn|deux> [secondes, 60] [journal]
// Codes : 0 = fini sans arret du GPU, 3 = arret du GPU detecte, 1 = echec.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "journal_gpu_extrait.inc"

static const char *KERNELS =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct P { float t; float2 jitter; float2 contenu; float2 vitesse; };\n"
    "kernel void entrees(texture2d<float, access::write> couleur [[texture(0)]],\n"
    "                    texture2d<float, access::write> profondeur [[texture(1)]],\n"
    "                    texture2d<float, access::write> vecteurs [[texture(2)]],\n"
    "                    constant P &p [[buffer(0)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= couleur.get_width() || g.y >= couleur.get_height()) return;\n"
    "  float2 x = (float2(g) + 0.5 - p.jitter) - p.vitesse * p.t;\n"
    "  int2 c = int2(floor(x / 12.0));\n"
    "  float v = ((c.x + c.y) & 1) ? 4.0 : 0.15;\n"
    "  if (fmod(fabs(x.x + 2.0 * x.y), 37.0) < 1.0) v = 12.0;\n"
    "  couleur.write(float4(v, v * 0.8, v * 0.6, 1), g);\n"
    "  profondeur.write(float4(0.01 + 0.5 * fract(x.x / 300.0)), g);\n"
    "  vecteurs.write(float4(-p.vitesse, 0, 0), g);\n"
    "}\n";

int
main(int argc, char **argv) {
  @autoreleasepool {
    const char *mode = argc > 1 ? argv[1] : "dyn";
    bool dyn = strcmp(mode, "fixe") != 0, deux = strcmp(mode, "deux") == 0;
    if (strcmp(mode, "fixe") && strcmp(mode, "dyn") && strcmp(mode, "deux")) {
      printf("usage : sonde_metalfx_temporel <fixe|dyn|deux> [secondes] [journal]\n");
      return 1;
    }
    double secondes = argc > 2 ? atof(argv[2]) : 60;
    char journal[1024];
    snprintf(journal, sizeof(journal), "%s", argc > 3 ? argv[3] : "/tmp/sonde-metalfx-temporel.txt");
    setenv("CIDRE_DXMT_JOURNAL_GPU", journal, 1);
    if (!cidre_jgpu_actif()) { printf("ECHEC : journal %s\n", journal); return 1; }

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> q = [dev newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:KERNELS] options:nil error:&err];
    id<MTLComputePipelineState> pso = lib ? [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"entrees"] error:&err] : nil;
    if (!pso) { printf("ECHEC : pipeline : %s\n", err.localizedDescription.UTF8String); return 1; }
    if (![MTLFXTemporalScalerDescriptor supportsDevice:dev]) { printf("ECHEC : pas de MetalFX temporel\n"); return 1; }

    const NSUInteger OW = 1384, OH = 868;
    const NSUInteger IW[2] = {1244, 692}, IH[2] = {780, 436};
    id<MTLTexture> couleur[2], profondeur[2], vecteurs[2];
    id<MTLFXTemporalScaler> scaler[2];
    id<MTLTexture> sortie = nil;
    int n_scalers = deux ? 2 : 1;
    for (int k = 0; k < n_scalers; k++) {
      MTLFXTemporalScalerDescriptor *d = [MTLFXTemporalScalerDescriptor new];
      d.colorTextureFormat = MTLPixelFormatRG11B10Float;
      d.depthTextureFormat = MTLPixelFormatR32Float;
      d.motionTextureFormat = MTLPixelFormatRG16Float;
      d.outputTextureFormat = MTLPixelFormatRGBA16Float;
      d.inputWidth = IW[k]; d.inputHeight = IH[k];
      d.outputWidth = OW; d.outputHeight = OH;
      d.autoExposureEnabled = YES;
      d.inputContentPropertiesEnabled = YES;
      d.inputContentMinScale = 1.0f;
      d.inputContentMaxScale = 3.0f;
      d.requiresSynchronousInitialization = YES;
      scaler[k] = [d newTemporalScalerWithDevice:dev];
      if (!scaler[k]) { printf("ECHEC : scaler %d\n", k); return 1; }
      MTLTextureDescriptor *t = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG11B10Float
                                                                                    width:IW[k] height:IH[k] mipmapped:NO];
      t.storageMode = MTLStorageModePrivate;
      t.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      couleur[k] = [dev newTextureWithDescriptor:t];
      t.pixelFormat = MTLPixelFormatR32Float;
      profondeur[k] = [dev newTextureWithDescriptor:t];
      t.pixelFormat = MTLPixelFormatRG16Float;
      vecteurs[k] = [dev newTextureWithDescriptor:t];
      if (!sortie) {
        MTLTextureDescriptor *o = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                    width:OW height:OH mipmapped:NO];
        o.storageMode = MTLStorageModePrivate;
        o.usage = scaler[k].outputTextureUsage | MTLTextureUsageShaderRead;
        sortie = [dev newTextureWithDescriptor:o];
      }
    }
    printf("sonde_metalfx_temporel : %s, mode %s, %.0f s, journal %s\n", dev.name.UTF8String, mode, secondes, journal);
    fflush(stdout);

    dispatch_semaphore_t vol = dispatch_semaphore_create(3);
    double t0 = CACurrentMediaTime(), dernier_tour = t0;
    uint64_t images = 0;
    int actif = 0;
    bool reset = true;
    while (CACurrentMediaTime() - t0 < secondes) {
      // arret net : plus rien ne se termine depuis 1,5 s alors que des tampons sont en vol
      uint64_t crees = atomic_load(&cidre_jgpu_crees), finis = atomic_load(&cidre_jgpu_finis);
      uint64_t silence = cidre_jgpu_ms() - atomic_load(&cidre_jgpu_derniere_fin_ms);
      if (crees > finis && silence >= 1500) {
        cidre_jgpu_ecrire("sonde : ARRET, aucun tampon termine depuis %.1f s (%llu en vol) a l'image %llu", silence / 1000.0,
                          crees - finis, images);
        printf("ARRET : GPU sans reponse depuis %.1f s a l'image %llu\n", silence / 1000.0, images);
        fflush(stdout);
        _exit(3);
      }
      if (dispatch_semaphore_wait(vol, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)))
        continue;
      if (deux && CACurrentMediaTime() - dernier_tour >= 2.0) {
        actif ^= 1;
        dernier_tour = CACurrentMediaTime();
        reset = true;
      }
      NSUInteger iw = IW[actif], ih = IH[actif];
      NSUInteger cw = iw - 3, ch = ih - 1;
      if (dyn) { // definition dynamique : de ~56 % a 100 % du contenu, une valeur par image
        float f = 0.56f + 0.44f * (0.5f + 0.5f * sinf((float)images * 0.37f));
        cw = MAX((NSUInteger)(f * (iw - 3)), (NSUInteger)ceil(OW / 3.0));
        ch = MAX((NSUInteger)(f * (ih - 1)), (NSUInteger)ceil(OH / 3.0));
      }
      float jx = 0, jy = 0, fb = 0.5f, rb = 0;
      for (uint64_t i = images % 8 + 1; i > 0; i /= 2) { fb /= 2; rb += fb * (i % 2); }
      jx = rb - 0.5f;
      fb = 1; rb = 0;
      for (uint64_t i = images % 8 + 1; i > 0; i /= 3) { fb /= 3; rb += fb * (i % 3); }
      jy = rb - 0.5f;
      struct { float t; float jitter[2]; float contenu[2]; float vitesse[2]; } p = {
          (float)images, {jx, jy}, {(float)cw, (float)ch}, {2.0f * cw / OW, 0.7f * ch / OH}};

      id<MTLCommandBuffer> cb = cidre_jgpu_tampon(q);
      id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
      e.label = @"C entrees";
      [e setComputePipelineState:pso];
      [e setTexture:couleur[actif] atIndex:0];
      [e setTexture:profondeur[actif] atIndex:1];
      [e setTexture:vecteurs[actif] atIndex:2];
      [e setBytes:&p length:sizeof(p) atIndex:0];
      [e dispatchThreads:MTLSizeMake(iw, ih, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
      [e endEncoding];
      id<MTLFXTemporalScaler> s = scaler[actif];
      s.colorTexture = couleur[actif];
      s.depthTexture = profondeur[actif];
      s.motionTexture = vecteurs[actif];
      s.outputTexture = sortie;
      s.inputContentWidth = cw;
      s.inputContentHeight = ch;
      s.jitterOffsetX = -jx;
      s.jitterOffsetY = -jy;
      s.motionVectorScaleX = 1;
      s.motionVectorScaleY = 1;
      s.depthReversed = YES;
      s.reset = reset;
      reset = false;
      [s encodeToCommandBuffer:cb];
      [cb addCompletedHandler:^(id<MTLCommandBuffer> b) {
        (void)b;
        dispatch_semaphore_signal(vol);
      }];
      cidre_jgpu_soumis();
      [cb commit];
      images++;
    }
    // laisser finir ce qui est en vol (au plus 3 tampons), sous la meme garde
    double fin = CACurrentMediaTime();
    while (atomic_load(&cidre_jgpu_crees) > atomic_load(&cidre_jgpu_finis) && CACurrentMediaTime() - fin < 1.5)
      usleep(10000);
    double dt = CACurrentMediaTime() - t0;
    printf("resultat : mode %s, %llu images en %.1f s (%.1f/s), %llu erreurs, %llu lents, aucun arret du GPU\n", mode,
           images, dt, images / dt, atomic_load(&cidre_jgpu_erreurs), atomic_load(&cidre_jgpu_lents));
    return 0;
  }
}
