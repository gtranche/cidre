/* Repere tirages : D tirages de T triangles chacun, dans une seule passe.
 * Cible 256x256 et triangles minuscules : le cout fragment est negligeable,
 * ce qui isole le cout par tirage et le debit par triangle. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <time.h>

static const char *src =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"vertex float4 vmain(uint vid [[vertex_id]]) {\n"
"    uint tri = vid / 3u, corner = vid % 3u;\n"
"    float a = float(tri & 63u) * 0.001;\n"
"    float2 base = float2(-0.9 + a, -0.9 + a);\n"
"    float2 off = corner == 0u ? float2(0.0, 0.0)\n"
"               : (corner == 1u ? float2(0.004, 0.0) : float2(0.0, 0.004));\n"
"    return float4(base + off, 0.0, 1.0);\n"
"}\n"
"fragment float4 fmain() { return float4(1.0); }\n";

static double maintenant(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t tirages = argc > 1 ? (uint32_t)atoi(argv[1]) : 10000u;
      uint32_t tris    = argc > 2 ? (uint32_t)atoi(argv[2]) : 1u;
      int reps         = argc > 3 ? atoi(argv[3]) : 4;
      const uint32_t W = 256, H = 256;

      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSError *err = nil;
      id<MTLLibrary> lib = [dev newLibraryWithSource:@(src) options:nil error:&err];
      if (!lib) { printf("compilation : %s\n", [[err description] UTF8String]); return 1; }

      MTLTextureDescriptor *rd = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
         width:W height:H mipmapped:NO];
      rd.usage = MTLTextureUsageRenderTarget;
      rd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> rt = [dev newTextureWithDescriptor:rd];

      MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
      pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
      pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
      id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      id<MTLCommandQueue> q = [dev newCommandQueue];
      double meilleur = 1e9, meilleur_enc = 0.0;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         id<MTLCommandBuffer> cb = [q commandBuffer];
         MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
         rp.colorAttachments[0].texture = rt;
         rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
         rp.colorAttachments[0].storeAction = MTLStoreActionStore;
         id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
         [e setRenderPipelineState:pso];
         for (uint32_t d = 0; d < tirages; ++d)
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3*tris];
         [e endEncoding];
         double tenc = maintenant() - t0;
         [cb commit];
         [cb waitUntilCompleted];
         double dt = maintenant() - t0;
         if (dt < meilleur) { meilleur = dt; meilleur_enc = tenc; }
      }
      double total_tris = (double)tirages * (double)tris;
      printf("metal-natif  tirages=%u tris/tirage=%u  meilleur=%.2f ms  "
             "(%.3f us/tirage, %.2f ns/triangle)  encodage=%.2f ms (%.3f us/tirage) "
             "reste=%.2f ms\n",
             tirages, tris, meilleur*1e3, meilleur*1e6/tirages,
             meilleur*1e9/total_tris, meilleur_enc*1e3, meilleur_enc*1e6/tirages,
             (meilleur-meilleur_enc)*1e3);
   }
   return 0;
}
