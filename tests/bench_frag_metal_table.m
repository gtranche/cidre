/* Repere fragment : passe plein ecran 1920x1080, N echantillonnages de texture
 * par pixel, M cibles de couleur. Ecrit directement en MSL. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <time.h>

static const char *src =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 pos [[position]]; float2 uv; };\n"
"vertex VOut vmain(uint vid [[vertex_id]]) {\n"
"    float2 p = float2((vid << 1) & 2, vid & 2);\n"
"    VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = p; return o;\n"
"}\n"
"struct SamplerTable { sampler handles[4096]; };\n"
"struct FOut { float4 c0 [[color(0)]];"
#if MRT >= 2
" float4 c1 [[color(1)]];"
#endif
"};\n"
"fragment FOut fmain(VOut in [[stage_in]],\n"
"                    texture2d<float> tex [[texture(0)]],\n"
"                    sampler smp [[sampler(0)]],\n"
"                    constant uint &n [[buffer(0)]],\n"
"                    constant float &lb [[buffer(1)]],\n"
"                    device const uchar *desc [[buffer(2)]],\n"
"                    constant ulong &texid [[buffer(3)]],\n"
"                    constant SamplerTable &stab [[buffer(4)]],\n"
"                    device const ushort *sidx [[buffer(5)]]) {\n"
"    float4 acc = float4(0.0);\n"
"    float2 uv = in.uv;\n"
"    for (uint i = 0u; i < n; ++i) {\n"
#if TABLE
"        sampler ds = stab.handles[sidx[0]];\n"
"        acc += tex.sample(ds, uv);\n"
#else
"        acc += tex.sample(smp, uv);\n"
#endif
"        uv += float2(0.00137, 0.00219);\n"
"    }\n"
"    FOut o; o.c0 = acc * (1.0 / float(n));\n"
#if MRT >= 2
"    o.c1 = o.c0 * 0.5;\n"
#endif
"    return o;\n"
"}\n";

static double maintenant(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t ech = argc > 1 ? (uint32_t)atoi(argv[1]) : 32u;
      uint32_t passes = argc > 2 ? (uint32_t)atoi(argv[2]) : 20u;
      const uint32_t W = 1920, H = 1080;
      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSError *err = nil;
      id<MTLLibrary> lib = [dev newLibraryWithSource:@(src) options:nil error:&err];
      if (!lib) { printf("compilation : %s\n", [[err description] UTF8String]); return 1; }

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
      id<MTLTexture> rt0 = [dev newTextureWithDescriptor:rd];
      id<MTLTexture> rt1 = [dev newTextureWithDescriptor:rd];

      MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
      pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
      pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
#if MRT >= 2
      pd.colorAttachments[1].pixelFormat = MTLPixelFormatRGBA16Float;
#endif
      id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeRepeat;
      sd.supportArgumentBuffers = YES;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];
      id<MTLBuffer> nb = [dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
      ((uint32_t *)[nb contents])[0] = ech;
      id<MTLBuffer> lbb = [dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
      ((float *)[lbb contents])[0] = 0.0f;
      id<MTLBuffer> db = [dev newBufferWithLength:64 options:MTLResourceStorageModeShared];
      memset([db contents], 0, 64);
      id<MTLBuffer> tb = [dev newBufferWithLength:8 options:MTLResourceStorageModeShared];
      *((MTLResourceID *)[tb contents]) = tex.gpuResourceID;
      id<MTLBuffer> stb = [dev newBufferWithLength:4096*8 options:MTLResourceStorageModeShared];
      id<MTLBuffer> sib = [dev newBufferWithLength:8 options:MTLResourceStorageModeShared];
      memset([sib contents], 0, 8);
      { MTLResourceID *h = (MTLResourceID *)[stb contents];
        for (int i = 0; i < 4096; ++i) h[i] = smp.gpuResourceID; }
      id<MTLCommandQueue> q = [dev newCommandQueue];

      double meilleur = 1e9;
      int reps = argc > 3 ? atoi(argv[3]) : 4;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         id<MTLCommandBuffer> cb = [q commandBuffer];
         for (uint32_t p = 0; p < passes; ++p) {
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt0;
            rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
#if MRT >= 2
            rp.colorAttachments[1].texture = rt1;
            rp.colorAttachments[1].loadAction = MTLLoadActionDontCare;
            rp.colorAttachments[1].storeAction = MTLStoreActionStore;
#endif
            id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:pso];
            [e setFragmentTexture:tex atIndex:0];
            [e setFragmentSamplerState:smp atIndex:0];
            [e setFragmentBuffer:nb offset:0 atIndex:0];
            [e setFragmentBuffer:lbb offset:0 atIndex:1];
            [e setFragmentBuffer:db offset:0 atIndex:2];
            [e setFragmentBuffer:tb offset:0 atIndex:3];
            [e setFragmentBuffer:stb offset:0 atIndex:4];
            [e setFragmentBuffer:sib offset:0 atIndex:5];
            [e useResource:tex usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [e endEncoding];
         }
         [cb commit];
         [cb waitUntilCompleted];
         double dt = maintenant() - t0;
         if (dt < meilleur) meilleur = dt;
      }
      printf("metal-table=%d ech/pixel=%u passes=%u cibles=%d  meilleur=%.1f ms  (%.2f ms/passe)\n",
             TABLE, ech, passes, MRT, meilleur*1e3, meilleur*1e3/passes);
   }
   return 0;
}
