// Sonde sans risque (aucun travail GPU) : cree seulement des MTLFXTemporalScaler avec
// les formats qu'Expedition 33 donne a DLSS (couleur RG11B10Float, profondeur
// Depth32Float_Stencil8, vecteurs RG16Float, sortie RGBA16Float, exposition auto),
// et avec les variantes de profondeur, sous la couche de validation Metal. Rien n'est
// encode : on lit ce que MetalFX accepte et les usages qu'il exige.
//   clang -fobjc-arc -framework Metal -framework MetalFX -framework Foundation sonde_formats_metalfx.m -o sonde_formats_metalfx
//   MTL_DEBUG_LAYER=1 ./sonde_formats_metalfx
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

static void essai(id<MTLDevice> dev, const char *nom, MTLPixelFormat couleur, MTLPixelFormat profondeur, BOOL autoexpo,
                  NSUInteger in_w, NSUInteger in_h) {
  MTLFXTemporalScalerDescriptor *d = [MTLFXTemporalScalerDescriptor new];
  d.colorTextureFormat = couleur;
  d.outputTextureFormat = MTLPixelFormatRGBA16Float;
  d.depthTextureFormat = profondeur;
  d.motionTextureFormat = MTLPixelFormatRG16Float;
  d.inputWidth = in_w;
  d.inputHeight = in_h;
  d.outputWidth = 1384;
  d.outputHeight = 868;
  d.autoExposureEnabled = autoexpo;
  d.inputContentPropertiesEnabled = YES;
  d.inputContentMinScale = 1.0f;
  d.inputContentMaxScale = 3.0f;
  id<MTLFXTemporalScaler> s = nil;
  @try {
    s = [d newTemporalScalerWithDevice:dev];
  } @catch (NSException *e) {
    printf("%-34s EXCEPTION %s : %s\n", nom, e.name.UTF8String, e.reason.UTF8String);
    return;
  }
  if (!s) {
    printf("%-34s REFUSE (nil)\n", nom);
    return;
  }
  printf("%-34s accepte ; usages exiges : couleur %lu profondeur %lu vecteurs %lu sortie %lu\n", nom,
         (unsigned long)s.colorTextureUsage, (unsigned long)s.depthTextureUsage, (unsigned long)s.motionTextureUsage,
         (unsigned long)s.outputTextureUsage);
}

int main(void) {
  @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    printf("%s ; temporel %s ; echelle contenu min %.2f max %.2f\n", dev.name.UTF8String,
           [MTLFXTemporalScalerDescriptor supportsDevice:dev] ? "oui" : "non",
           [MTLFXTemporalScalerDescriptor supportedInputContentMinScaleForDevice:dev],
           [MTLFXTemporalScalerDescriptor supportedInputContentMaxScaleForDevice:dev]);
    essai(dev, "Exp33 : RG11B10 + D32S8 + auto", MTLPixelFormatRG11B10Float, MTLPixelFormatDepth32Float_Stencil8, YES, 692, 436);
    essai(dev, "Exp33 1244x780 (contenu 1241)", MTLPixelFormatRG11B10Float, MTLPixelFormatDepth32Float_Stencil8, YES, 1244, 780);
    essai(dev, "RG11B10 + Depth32Float + auto", MTLPixelFormatRG11B10Float, MTLPixelFormatDepth32Float, YES, 692, 436);
    essai(dev, "RG11B10 + R32Float + auto", MTLPixelFormatRG11B10Float, MTLPixelFormatR32Float, YES, 692, 436);
    essai(dev, "RG11B10 + D32S8, sans auto", MTLPixelFormatRG11B10Float, MTLPixelFormatDepth32Float_Stencil8, NO, 692, 436);
    essai(dev, "sondes : RGBA16F + Depth32Float", MTLPixelFormatRGBA16Float, MTLPixelFormatDepth32Float, NO, 864, 542);
  }
  return 0;
}
