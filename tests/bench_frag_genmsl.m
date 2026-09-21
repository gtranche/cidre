/* Execute le MSL genere par KosmicKrisp dans le harnais Metal, avec les memes
 * tampons : table racine, table d'echantillonneurs, descripteur bindless.
 * Sert a savoir si l'ecart vient du code genere ou de la mise en place du pilote. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "gen_src.h"

static double maintenant(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t ech = argc > 1 ? (uint32_t)atoi(argv[1]) : 512u;
      uint32_t passes = argc > 2 ? (uint32_t)atoi(argv[2]) : 20u;
      int reps = argc > 3 ? atoi(argv[3]) : 4;
      const uint32_t W = 1920, H = 1080;

      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSError *err = nil;
      MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
      opts.mathMode = MTLMathModeFast;
#if FPFAST
      opts.mathFloatingPointFunctions = MTLMathFloatingPointFunctionsFast;
#endif
      id<MTLLibrary> vlib = [dev newLibraryWithSource:@(vs_src) options:opts error:&err];
      if (!vlib) { printf("VS : %s\n", [[err description] UTF8String]); return 1; }
      id<MTLLibrary> flib = [dev newLibraryWithSource:@(fs_src) options:opts error:&err];
      if (!flib) { printf("FS : %s\n", [[err description] UTF8String]); return 1; }

      MTLTextureDescriptor *td = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
         width:2048 height:2048 mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead;
      td.storageMode = MTLStorageModePrivate;
      id<MTLTexture> tex = [dev newTextureWithDescriptor:td];

      MTLTextureDescriptor *rd = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
         width:W height:H mipmapped:NO];
      rd.usage = MTLTextureUsageRenderTarget;
      rd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> rt = [dev newTextureWithDescriptor:rd];

      MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeRepeat;
      sd.supportArgumentBuffers = YES;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];

      MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
      pd.vertexFunction = [vlib newFunctionWithName:@"main_entrypoint"];
      pd.fragmentFunction = [flib newFunctionWithName:@"main_entrypoint"];
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
      id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      /* Descripteur bindless : id de texture a +0, index d'echantillonneur a +8,
       * biais de lod fp16 a +12. */
      id<MTLBuffer> descb = [dev newBufferWithLength:64 options:MTLResourceStorageModeShared];
      memset([descb contents], 0, 64);
      *((MTLResourceID *)[descb contents]) = tex.gpuResourceID;
      *((uint16_t *)((char *)[descb contents] + 8)) = 0;
      *((uint16_t *)((char *)[descb contents] + 12)) = 0; /* half 0.0 */

      /* Table racine : compteur a +760, adresse du descripteur a +1016,
       * float a +536 lu par le sommet. */
      id<MTLBuffer> root = [dev newBufferWithLength:2048 options:MTLResourceStorageModeShared];
      memset([root contents], 0, 2048);
      *((uint32_t *)((char *)[root contents] + 760)) = ech;
      *((uint64_t *)((char *)[root contents] + 1016)) = [descb gpuAddress];
      *((float *)((char *)[root contents] + 536)) = 0.0f;

      id<MTLBuffer> stab = [dev newBufferWithLength:4096*8 options:MTLResourceStorageModeShared];
      { MTLResourceID *h = (MTLResourceID *)[stab contents];
        for (int i = 0; i < 4096; ++i) h[i] = smp.gpuResourceID; }

      id<MTLCommandQueue> q = [dev newCommandQueue];
#if RESIDENCE
      MTLResidencySetDescriptor *rsd = [[MTLResidencySetDescriptor alloc] init];
      rsd.initialCapacity = 8;
      id<MTLResidencySet> rset = [dev newResidencySetWithDescriptor:rsd error:&err];
      if (!rset) { printf("residency : %s\n", [[err description] UTF8String]); return 1; }
      [rset addAllocation:tex]; [rset addAllocation:descb];
      [rset addAllocation:root]; [rset addAllocation:stab]; [rset addAllocation:rt];
      [rset commit];
      [q addResidencySet:rset];
#endif
      double meilleur = 1e9;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         id<MTLCommandBuffer> cb = [q commandBuffer];
         for (uint32_t p = 0; p < passes; ++p) {
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:pso];
            [e setVertexBuffer:root offset:0 atIndex:0];
            [e setVertexBuffer:stab offset:0 atIndex:1];
            [e setFragmentBuffer:root offset:0 atIndex:0];
            [e setFragmentBuffer:stab offset:0 atIndex:1];
#if !RESIDENCE
            [e useResource:tex usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
            [e useResource:descb usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
#endif
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [e endEncoding];
         }
         [cb commit];
         [cb waitUntilCompleted];
         double dt = maintenant() - t0;
         if (dt < meilleur) meilleur = dt;
      }
      printf("msl-genere res=%d ech/pixel=%u passes=%u  meilleur=%.1f ms  (%.3f ms/passe)\n",
             RESIDENCE, ech, passes, meilleur*1e3, meilleur*1e3/passes);
   }
   return 0;
}
