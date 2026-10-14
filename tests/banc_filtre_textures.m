// Banc : un noyau MSL de 32 lectures (gen_filtre_textures.py) sur une grille L x H, temps GPU median.
// usage : banc_filtre_textures <noyau.metal> [L=1920] [H=1080] [reps=15] [has_border=1]
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
int main(int argc, char **argv) {
   @autoreleasepool {
      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSUInteger W = argc > 2 ? atoi(argv[2]) : 1920, H = argc > 3 ? atoi(argv[3]) : 1080;
      int reps = argc > 4 ? atoi(argv[4]) : 15;
      uint32_t has_border = argc > 5 ? atoi(argv[5]) : 1;
      NSError *e = nil;
      NSString *src = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:&e];
      MTLCompileOptions *o = [MTLCompileOptions new];
      o.mathMode = MTLMathModeFast;
      id<MTLLibrary> lib = [dev newLibraryWithSource:src options:o error:&e];
      if (!lib) { printf("compilation : %s\n", e.localizedDescription.UTF8String); return 1; }
      id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&e];
      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:W height:H mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      td.storageMode = MTLStorageModePrivate;
      id<MTLTexture> tin = [dev newTextureWithDescriptor:td], tout = [dev newTextureWithDescriptor:td];
      MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeClampToBorderColor;
      sd.borderColor = MTLSamplerBorderColorTransparentBlack;
      id<MTLSamplerState> s0 = [dev newSamplerStateWithDescriptor:sd];
      sd.borderColor = MTLSamplerBorderColorOpaqueWhite;
      id<MTLSamplerState> s1 = [dev newSamplerStateWithDescriptor:sd];
      struct { float w[32][4]; float off[32][4]; float clampv[4]; float border[4]; uint32_t swz, has_border; uint32_t pad[2]; } p;
      for (int i = 0; i < 32; i++) {
         for (int k = 0; k < 4; k++) p.w[i][k] = 1.0f / 32;
         p.off[i][0] = (i % 8 - 4) / (float)W * 3; p.off[i][1] = (i / 8 - 2) / (float)H * 3; p.off[i][2] = p.off[i][3] = 0;
      }
      p.clampv[0] = p.clampv[1] = 0.001f; p.clampv[2] = p.clampv[3] = 0.999f;
      p.border[0] = p.border[1] = p.border[2] = p.border[3] = 0;
      p.swz = 0 | (1 << 3) | (2 << 6) | (3 << 9);
      p.has_border = has_border;
      id<MTLBuffer> pb = [dev newBufferWithBytes:&p length:sizeof(p) options:MTLResourceStorageModeShared];
      id<MTLCommandQueue> q = [dev newCommandQueue];
      double *t = calloc(reps, sizeof(double));
      for (int r = 0; r < reps + 2; r++) {
         id<MTLCommandBuffer> cb = [q commandBuffer];
         id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
         [ce setComputePipelineState:ps];
         [ce setTexture:tin atIndex:0]; [ce setTexture:tout atIndex:1];
         [ce setSamplerState:s0 atIndex:0]; [ce setSamplerState:s1 atIndex:1];
         [ce setBuffer:pb offset:0 atIndex:0];
         [ce dispatchThreads:MTLSizeMake(W, H, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
         [ce endEncoding];
         [cb commit]; [cb waitUntilCompleted];
         if (r >= 2) t[r - 2] = (cb.GPUEndTime - cb.GPUStartTime) * 1e3;
      }
      qsort(t, reps, sizeof(double), cmpd);
      printf("%s %lux%lu bord_actif=%u : GPU med=%.3f ms (min %.3f max %.3f) max_fils=%lu\n", argv[1], (unsigned long)W, (unsigned long)H,
             has_border, t[reps / 2], t[0], t[reps - 1], (unsigned long)ps.maxTotalThreadsPerThreadgroup);
   }
   return 0;
}
