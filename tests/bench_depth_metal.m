/* Repere de rejet precoce : N couches plein ecran dessinees de l'avant vers
 * l'arriere, test de profondeur LESS, nuanceur fragment couteux. Si le GPU
 * ecarte les fragments caches, le temps ne depend pas de N. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <time.h>

static const char *src =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 pos [[position]]; float2 uv; };\n"
"vertex VOut vmain(uint vid [[vertex_id]], constant float &z [[buffer(0)]]) {\n"
"    float2 p = float2((vid << 1) & 2, vid & 2);\n"
"    VOut o; o.pos = float4(p * 2.0 - 1.0, z, 1.0); o.uv = p; return o;\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]],\n"
"                      texture2d<float> tex [[texture(0)]],\n"
"                      sampler smp [[sampler(0)]],\n"
"                      constant uint &n [[buffer(1)]]) {\n"
"    float4 acc = float4(0.0);\n"
"    float2 uv = in.uv;\n"
"    for (uint i = 0u; i < n; ++i) { acc += tex.sample(smp, uv);\n"
"        uv += float2(0.00137, 0.00219); }\n"
"    return acc * (1.0 / float(n));\n"
"}\n";

static double maintenant(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t ech = argc > 1 ? (uint32_t)atoi(argv[1]) : 128u;
      uint32_t couches = argc > 2 ? (uint32_t)atoi(argv[2]) : 8u;
      int reps = argc > 3 ? atoi(argv[3]) : 6;
      const uint32_t W = 1920, H = 1080;

      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSError *err = nil;
      id<MTLLibrary> lib = [dev newLibraryWithSource:@(src) options:nil error:&err];
      if (!lib) { printf("compilation : %s\n", [[err description] UTF8String]); return 1; }

      MTLTextureDescriptor *td = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
         width:2048 height:2048 mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead; td.storageMode = MTLStorageModePrivate;
      id<MTLTexture> tex = [dev newTextureWithDescriptor:td];

      MTLTextureDescriptor *rd = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
         width:W height:H mipmapped:NO];
      rd.usage = MTLTextureUsageRenderTarget; rd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> rt = [dev newTextureWithDescriptor:rd];

      MTLTextureDescriptor *dd = [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
         width:W height:H mipmapped:NO];
      dd.usage = MTLTextureUsageRenderTarget; dd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> dep = [dev newTextureWithDescriptor:dd];

      MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
      pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
      pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
      pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
      id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      MTLDepthStencilDescriptor *dsd = [[MTLDepthStencilDescriptor alloc] init];
      dsd.depthCompareFunction = MTLCompareFunctionLess;
      dsd.depthWriteEnabled = YES;
      id<MTLDepthStencilState> dss = [dev newDepthStencilStateWithDescriptor:dsd];

      MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeRepeat;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];
      id<MTLBuffer> nb = [dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
      ((uint32_t *)[nb contents])[0] = ech;
      id<MTLBuffer> zb = [dev newBufferWithLength:4*256 options:MTLResourceStorageModeShared];
      for (uint32_t i = 0; i < 256; ++i)
         ((float *)[zb contents])[i] = 0.1f + 0.8f * (float)i / 256.0f;

      id<MTLCommandQueue> q = [dev newCommandQueue];
      double meilleur = 1e9;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         id<MTLCommandBuffer> cb = [q commandBuffer];
         MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
         rp.colorAttachments[0].texture = rt;
         rp.colorAttachments[0].loadAction = MTLLoadActionClear;
         rp.colorAttachments[0].storeAction = MTLStoreActionStore;
         rp.depthAttachment.texture = dep;
         rp.depthAttachment.loadAction = MTLLoadActionClear;
         rp.depthAttachment.clearDepth = 1.0;
         rp.depthAttachment.storeAction = MTLStoreActionDontCare;
         id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
         [e setRenderPipelineState:pso];
         [e setDepthStencilState:dss];
         [e setFragmentTexture:tex atIndex:0];
         [e setFragmentSamplerState:smp atIndex:0];
         [e setFragmentBuffer:nb offset:0 atIndex:1];
         for (uint32_t c = 0; c < couches; ++c) {
            [e setVertexBuffer:zb offset:4*c atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
         }
         [e endEncoding];
         [cb commit];
         [cb waitUntilCompleted];
         double dt = maintenant() - t0;
         if (dt < meilleur) meilleur = dt;
      }
      printf("metal-natif  ech/pixel=%u couches=%u  meilleur=%.2f ms  (%.3f ms/couche)\n",
             ech, couches, meilleur*1e3, meilleur*1e3/couches);
   }
   return 0;
}
