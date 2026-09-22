/* Cout du motif de traduction : N echantillonnages de la meme texture, soit par
 * texture liee (patron natif), soit a travers un descripteur bindless recharge a
 * chaque fois (patron produit par KosmicKrisp). Meme texture des deux cotes pour
 * que le cache se comporte identiquement. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

static double maintenant(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
   return t.tv_sec + t.tv_nsec*1e-9; }

static char *source(uint32_t n, int bindless)
{
   size_t cap = 4096 + (size_t)n * 512;
   char *s = malloc(cap); s[0] = 0;
   strcat(s,
      "#include <metal_stdlib>\n"
      "using namespace metal;\n"
      "struct ST { sampler handles[4096]; };\n"
      "struct VOut { float4 pos [[position]]; float2 uv; };\n"
      "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
      "  float2 p = float2((vid << 1) & 2, vid & 2);\n"
      "  VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = p; return o;\n"
      "}\n"
      "fragment float4 fmain(VOut in [[stage_in]],\n"
      "                      texture2d<float> tex [[texture(0)]],\n"
      "                      sampler smp [[sampler(0)]],\n"
      "                      constant ulong *root [[buffer(0)]],\n"
      "                      constant ST &st [[buffer(2)]]) {\n"
      "  float4 acc = float4(0.0);\n"
      "  float2 uv = in.uv;\n");
   char b[512];
   for (uint32_t i = 0; i < n; ++i) {
      if (bindless)
         snprintf(b, sizeof b,
            "  { ulong d = root[%u];\n"
            "    half lb = *(coherent device half *)(d + 12);\n"
            "    texture2d<float> t = *(constant texture2d<float> *)d;\n"
            "    ushort si = *(coherent device ushort *)(d + 8);\n"
            "    sampler s = st.handles[si];\n"
            "    acc += t.sample(s, uv, bias(float(lb))); }\n"
            "  uv += float2(0.00137, 0.00219);\n", i);
      else
         snprintf(b, sizeof b,
            "  acc += tex.sample(smp, uv);\n"
            "  uv += float2(0.00137, 0.00219);\n");
      strcat(s, b);
   }
   strcat(s, "  return acc * (1.0 / float(");
   snprintf(b, sizeof b, "%u", n); strcat(s, b);
   strcat(s, "));\n}\n");
   return s;
}

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t n = argc > 1 ? (uint32_t)atoi(argv[1]) : 114u;
      int bindless = argc > 2 ? atoi(argv[2]) : 0;
      int reps = argc > 3 ? atoi(argv[3]) : 6;
      const uint32_t W = 1920, H = 1080;
      NSError *err = nil;

      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      char *src = source(n, bindless);
      MTLCompileOptions *opts = [MTLCompileOptions new];
      opts.mathMode = MTLMathModeFast;
      id<MTLLibrary> lib = [dev newLibraryWithSource:@(src) options:opts error:&err];
      free(src);
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

      MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
      sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
      sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeRepeat;
      sd.supportArgumentBuffers = YES;
      id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];

      /* Un descripteur par echantillonnage : identifiant de texture a +0,
       * index d'echantillonneur a +8, biais fp16 a +12. */
      id<MTLBuffer> descs = [dev newBufferWithLength:64*n options:MTLResourceStorageModeShared];
      memset([descs contents], 0, 64*n);
      for (uint32_t i = 0; i < n; ++i) {
         char *p = (char *)[descs contents] + 64*i;
         *((MTLResourceID *)p) = tex.gpuResourceID;
         *((uint16_t *)(p + 8)) = (uint16_t)(i % 4096);
         *((uint16_t *)(p + 12)) = 0;
      }
      id<MTLBuffer> root = [dev newBufferWithLength:8*n options:MTLResourceStorageModeShared];
      for (uint32_t i = 0; i < n; ++i)
         ((uint64_t *)[root contents])[i] = [descs gpuAddress] + 64*i;
      id<MTLBuffer> stab = [dev newBufferWithLength:4096*8 options:MTLResourceStorageModeShared];
      { MTLResourceID *h = (MTLResourceID *)[stab contents];
        for (int i = 0; i < 4096; ++i) h[i] = smp.gpuResourceID; }

      MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
      pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
      pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
      pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
      id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
      if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

      id<MTLCommandQueue> q = [dev newCommandQueue];
      double meilleur = 1e9;
      for (int rep = 0; rep < reps; ++rep) {
         double t0 = maintenant();
         id<MTLCommandBuffer> cb = [q commandBuffer];
         MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
         rp.colorAttachments[0].texture = rt;
         rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
         rp.colorAttachments[0].storeAction = MTLStoreActionStore;
         id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
         [e setRenderPipelineState:pso];
         [e setFragmentTexture:tex atIndex:0];
         [e setFragmentSamplerState:smp atIndex:0];
         [e setFragmentBuffer:root offset:0 atIndex:0];
         [e setFragmentBuffer:stab offset:0 atIndex:2];
         [e useResource:tex usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
         [e useResource:descs usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
         [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
         [e endEncoding];
         [cb commit];
         [cb waitUntilCompleted];
         double dt = maintenant() - t0;
         if (dt < meilleur) meilleur = dt;
      }
      printf("motif=%-9s echantillonnages=%u  meilleur=%.3f ms\n",
             bindless ? "bindless" : "lie", n, meilleur*1e3);
   }
   return 0;
}
