/* Meme MSL genere que tests/bench_frag_genmsl.m, mais encode avec Metal 4 :
 * MTL4CommandBuffer, MTL4RenderCommandEncoder, table d'arguments et ensemble de
 * residence, comme le fait KosmicKrisp. Isole le cout de l'encodeur. */
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
      NSError *err = nil;

      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      MTL4CompilerDescriptor *cdesc = [MTL4CompilerDescriptor new];
      id<MTL4Compiler> comp = [dev newCompilerWithDescriptor:cdesc error:&err];
      if (!comp) { printf("compilateur : %s\n", [[err description] UTF8String]); return 1; }

      MTLCompileOptions *opts = [MTLCompileOptions new];
      opts.mathMode = MTLMathModeFast;
      opts.mathFloatingPointFunctions = MTLMathFloatingPointFunctionsFast;

      MTL4LibraryDescriptor *vld = [MTL4LibraryDescriptor new];
      vld.source = @(vs_src); vld.options = opts;
      id<MTLLibrary> vlib = [comp newLibraryWithDescriptor:vld error:&err];
      MTL4LibraryDescriptor *fld = [MTL4LibraryDescriptor new];
      fld.source = @(fs_src); fld.options = opts;
      id<MTLLibrary> flib = [comp newLibraryWithDescriptor:fld error:&err];
      if (!vlib || !flib) { printf("bibliotheque : %s\n", [[err description] UTF8String]); return 1; }

      MTL4LibraryFunctionDescriptor *vfd = [MTL4LibraryFunctionDescriptor new];
      vfd.name = @"main_entrypoint"; vfd.library = vlib;
      MTL4LibraryFunctionDescriptor *ffd = [MTL4LibraryFunctionDescriptor new];
      ffd.name = @"main_entrypoint"; ffd.library = flib;

      MTL4RenderPipelineDescriptor *pd = [MTL4RenderPipelineDescriptor new];
      pd.vertexFunctionDescriptor = vfd;
      pd.fragmentFunctionDescriptor = ffd;
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
      id<MTLRenderPipelineState> pso =
         [comp newRenderPipelineStateWithDescriptor:pd compilerTaskOptions:nil error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      MTLTextureDescriptor *td = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:(BCFMT ? MTLPixelFormatBC1_RGBA : MTLPixelFormatRGBA8Unorm)
         width:2048 height:2048 mipmapped:NO];
#if TEXWRITE
      td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
#else
      td.usage = MTLTextureUsageShaderRead;
#endif
#if NOCOMPRESS
      td.allowGPUOptimizedContents = NO;
#endif
      td.storageMode = MTLStorageModePrivate;
      id<MTLTexture> tex = [dev newTextureWithDescriptor:td];

      MTLTextureDescriptor *rd = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
         width:W height:H mipmapped:NO];
      rd.usage = MTLTextureUsageRenderTarget; rd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> rt = [dev newTextureWithDescriptor:rd];

      MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeRepeat;
      sd.supportArgumentBuffers = YES;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];

      id<MTLBuffer> descb = [dev newBufferWithLength:64 options:MTLResourceStorageModeShared];
      memset([descb contents], 0, 64);
      *((MTLResourceID *)[descb contents]) = tex.gpuResourceID;

      id<MTLBuffer> root = [dev newBufferWithLength:2048 options:MTLResourceStorageModeShared];
      memset([root contents], 0, 2048);
      *((uint32_t *)((char *)[root contents] + 760)) = ech;
      *((uint64_t *)((char *)[root contents] + 1016)) = [descb gpuAddress];

      id<MTLBuffer> stab = [dev newBufferWithLength:4096*8 options:MTLResourceStorageModeShared];
      { MTLResourceID *h = (MTLResourceID *)[stab contents];
        for (int i = 0; i < 4096; ++i) h[i] = smp.gpuResourceID; }

      MTL4ArgumentTableDescriptor *atd = [MTL4ArgumentTableDescriptor new];
      atd.maxBufferBindCount = 8;
      id<MTL4ArgumentTable> at = [dev newArgumentTableWithDescriptor:atd error:&err];
      if (!at) { printf("table : %s\n", [[err description] UTF8String]); return 1; }
      [at setAddress:[root gpuAddress] atIndex:0];
      [at setAddress:[stab gpuAddress] atIndex:1];

      id<MTL4CommandQueue> q = [dev newMTL4CommandQueue];
      id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
      id<MTL4CommandBuffer> cb = [dev newCommandBuffer];
      id<MTLSharedEvent> ev = [dev newSharedEvent];

      MTLResidencySetDescriptor *rsd = [MTLResidencySetDescriptor new];
      rsd.initialCapacity = 8;
      id<MTLResidencySet> rset = [dev newResidencySetWithDescriptor:rsd error:&err];
      if (!rset) { printf("residence : %s\n", [[err description] UTF8String]); return 1; }
      [rset addAllocation:tex]; [rset addAllocation:rt]; [rset addAllocation:descb];
      [rset addAllocation:root]; [rset addAllocation:stab];
      [rset commit];
      [q addResidencySet:rset];

      uint64_t valeur = 0;
      double meilleur = 1e9;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         [alloc reset];
         [cb beginCommandBufferWithAllocator:alloc];
         for (uint32_t p = 0; p < passes; ++p) {
            MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            rp.renderTargetWidth = W; rp.renderTargetHeight = H;
            id<MTL4RenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
            [e setArgumentTable:at atStages:(MTLRenderStageVertex | MTLRenderStageFragment)];
            [e setRenderPipelineState:pso];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [e barrierAfterStages:MTLStageAll beforeQueueStages:MTLStageAll
                visibilityOptions:MTL4VisibilityOptionResourceAlias];
            [e endEncoding];
         }
         [cb endCommandBuffer];
         id<MTL4CommandBuffer> bufs[1] = { cb };
         MTL4CommitOptions *copt = [MTL4CommitOptions new];
         [q commit:bufs count:1 options:copt];
         [q signalEvent:ev value:++valeur];
         [ev waitUntilSignaledValue:valeur timeoutMS:20000];
         double dt = maintenant() - t0;
         if (dt < meilleur) meilleur = dt;
      }
      printf("mtl4 texwrite=%d nocomp=%d  ech/pixel=%u passes=%u  meilleur=%.1f ms  (%.3f ms/passe)\n",
             TEXWRITE, NOCOMPRESS, ech, passes, meilleur*1e3, meilleur*1e3/passes);
   }
   return 0;
}
