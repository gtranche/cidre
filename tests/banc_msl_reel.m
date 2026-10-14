// Execute tel quel un MSL de calcul ecrit par KosmicKrisp (CIDRE_DISPATCH_TRACE, ou MESA_KK_DEBUG=msl),
// avec un buf0 reconstruit a la main. Ecrit pour le filtre de Little Nightmares (cs de 32 lectures,
// grille 1728x976) : le temps obtenu (4,60 ms) est celui mesure en jeu (~4,3 ms) ; il a montre que le
// select de 0136, garde par le contournement 10, triplait le filtre (0138 : 1,55 ms).
// buf0 reconstruit a la main : constantes du jeu par pointeur (+888), indices de texture /
// echantillonneur / sortie (+896, +900, +904), tables de descripteurs (+1144 echantillonneurs,
// +1152 images, 64 octets par entree), table d'echantillonneurs Metal en buffer(1).
// Les constantes imitent un filtre : uv = (x + 0,5) / L, decalages de 1,5 texel, poids 1/32.
// usage : banc_msl_reel <cs.metal> [L=1728] [H=976] [reps=15] [champ_decalage=1.5]
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
static void put32(uint8_t *b, size_t o, uint32_t v) { memcpy(b + o, &v, 4); }
static void put64(uint8_t *b, size_t o, uint64_t v) { memcpy(b + o, &v, 8); }
static void putf4(uint8_t *b, size_t o, float x, float y, float z, float w) { float v[4] = {x, y, z, w}; memcpy(b + o, v, 16); }
int main(int argc, char **argv) {
   @autoreleasepool {
      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSUInteger W = argc > 2 ? atoi(argv[2]) : 1728, H = argc > 3 ? atoi(argv[3]) : 976;
      int reps = argc > 4 ? atoi(argv[4]) : 15;
      float champ = argc > 5 ? atof(argv[5]) : 1.5f;
      NSError *e = nil;
      NSString *src = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:&e];
      MTLCompileOptions *o = [MTLCompileOptions new];
      o.mathMode = MTLMathModeFast;
      id<MTLLibrary> lib = [dev newLibraryWithSource:src options:o error:&e];
      if (!lib) { printf("compilation : %s\n", e.localizedDescription.UTF8String); return 1; }
      id<MTLFunction> fn = [lib newFunctionWithName:lib.functionNames.firstObject];
      id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:&e];
      if (!ps) { printf("pipeline : %s\n", e.localizedDescription.UTF8String); return 1; }

      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:W height:H mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      td.storageMode = MTLStorageModePrivate;
      id<MTLTexture> tin = [dev newTextureWithDescriptor:td], tout = [dev newTextureWithDescriptor:td];
      MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
      sd.supportArgumentBuffers = YES;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];

      id<MTLBuffer> cbv = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
      uint8_t *c = cbv.contents; memset(c, 0, 4096);
      putf4(c, 1312, 0, 0, 1.0f / W, 1.0f / H);
      putf4(c, 1344, 0, 0, 0, 0);
      putf4(c, 528, 0.0f, 0.0f, 1.0f, 1.0f);
      for (size_t off = 432; off < 1312; off += 16) {
         if (off == 528) continue;
         int i = (int)(off / 16);
         float dx = ((i % 8) - 4) * champ / W, dy = ((i / 8 % 4) - 2) * champ / H;
         putf4(c, off, dx, dy, -dx, -dy);
      }
      for (size_t off = 560; off < 1312; off += 32) putf4(c, off, 1.0f / 32, 1.0f / 32, 1.0f / 32, 1.0f / 32);

      id<MTLBuffer> stab = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
      memset(stab.contents, 0, 4096);
      id<MTLBuffer> itab = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
      uint8_t *it = itab.contents; memset(it, 0, 4096);
      MTLResourceID rin = tin.gpuResourceID, rout = tout.gpuResourceID;
      memcpy(it + 1 * 64 + 64, &rin, 8);
      memcpy(it + 2 * 64 + 64, &rout, 8);

      id<MTLBuffer> root = [dev newBufferWithLength:2048 options:MTLResourceStorageModeShared];
      uint8_t *r = root.contents; memset(r, 0, 2048);
      uint64_t a = cbv.gpuAddress; put32(r, 888, (uint32_t)a); put32(r, 892, (uint32_t)(a >> 32));
      put32(r, 896, 1); put32(r, 900, 0); put32(r, 904, 2);
      put64(r, 1144, stab.gpuAddress); put64(r, 1152, itab.gpuAddress);

      id<MTLBuffer> samplers = [dev newBufferWithLength:4096 * 8 options:MTLResourceStorageModeShared];
      MTLResourceID rs = smp.gpuResourceID; memcpy(samplers.contents, &rs, 8);

      id<MTLCommandQueue> q = [dev newCommandQueue];
      double *t = calloc(reps, sizeof(double));
      for (int k = 0; k < reps + 2; k++) {
         id<MTLCommandBuffer> cb = [q commandBuffer];
         id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
         [ce setComputePipelineState:ps];
         [ce setBuffer:root offset:0 atIndex:0];
         [ce setBuffer:samplers offset:0 atIndex:1];
         [ce useResource:cbv usage:MTLResourceUsageRead];
         [ce useResource:stab usage:MTLResourceUsageRead];
         [ce useResource:itab usage:MTLResourceUsageRead];
         [ce useResource:tin usage:MTLResourceUsageRead];
         [ce useResource:tout usage:MTLResourceUsageWrite];
         [ce dispatchThreadgroups:MTLSizeMake((W + 7) / 8, (H + 7) / 8, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
         [ce endEncoding];
         [cb commit]; [cb waitUntilCompleted];
         if (cb.error) { printf("erreur GPU : %s\n", cb.error.localizedDescription.UTF8String); return 1; }
         if (k >= 2) t[k - 2] = (cb.GPUEndTime - cb.GPUStartTime) * 1e3;
      }
      qsort(t, reps, sizeof(double), cmpd);
      printf("%s %lux%lu : GPU med=%.3f ms (min %.3f max %.3f) max_fils=%lu\n", argv[1], (unsigned long)W, (unsigned long)H,
             t[reps / 2], t[0], t[reps - 1], (unsigned long)ps.maxTotalThreadsPerThreadgroup);
   }
   return 0;
}
