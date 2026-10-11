/* Repere etage sommets : cout de la lecture des attributs par 1 M de sommets
 * (SoA : position float3, normale half4, tangente half4, uv float2) selon le
 * chemin de lecture, plus `nu` lectures uniformes de float4 (donnees de
 * primitive type GPUScene, meme index pour tous les sommets).
 *   tex     : texture_buffer avec test de bornes par lecture (= Buffer<T> SRV d'airconv)
 *   dev     : device pointeur brut, sans test (= tampons IA d'airconv, sans le test de nullite)
 *   devchk  : device pointeur, test de bornes par lecture (select vers zero)
 *   devonce : device pointeur, un seul test par sommet (branche) puis lectures brutes
 *   stagein : attributs natifs [[stage_in]] + MTLVertexDescriptor
 * Toutes les sorties dependent de toutes les lectures. Les modes sont mesures en
 * tourniquet, temps GPU du tampon de commandes (GPUStartTime/GPUEndTime), mediane.
 * Usage : bench_vertex_fetch_metal [nu=0] [dessins/cb=10] [tours=7] [nv=0] [sommets=1000002] */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>

static const char *src =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 pos [[position]]; float4 c; };\n"
"struct Params { uint count; uint nu; uint nv; };\n"
"static inline VOut finish(float3 p, float4 n, float4 t, float2 uv, float4 acc) {\n"
"    VOut o; o.pos = float4(p * 1e-3 + n.xyz * 1e-4 + t.xyz * 1e-4 + float3(uv * 1e-4, 0.0), 1.0);\n"
"    o.c = acc + n + t; return o;\n"
"}\n"
/* tex : une texture_buffer par flux, test de bornes par lecture comme airconv
 * (select vers -1 : lecture hors bornes -> 0 par le materiel). Position en
 * R32Float lue 3 fois (comme le PositionBuffer d'UE5), normales/tangentes en
 * RGBA16Float, uv en RG32Float, uniformes en RGBA32Float. */
"vertex VOut v_tex(uint vid [[vertex_id]], constant Params &P [[buffer(4)]],\n"
"    texture_buffer<float> tp [[texture(0)]], texture_buffer<float> tn [[texture(1)]],\n"
"    texture_buffer<float> tt [[texture(2)]], texture_buffer<float> tu [[texture(3)]],\n"
"    texture_buffer<float> tg [[texture(4)]], texture_buffer<float> tv [[texture(5)]]) {\n"
"    uint cp = P.count * 3u, c = P.count;\n"
"    uint i0 = vid * 3u;\n"
"    float px = tp.read(i0 < cp ? i0 : 0xFFFFFFFFu).x;\n"
"    float py = tp.read(i0 + 1u < cp ? i0 + 1u : 0xFFFFFFFFu).x;\n"
"    float pz = tp.read(i0 + 2u < cp ? i0 + 2u : 0xFFFFFFFFu).x;\n"
"    float4 n = tn.read(vid < c ? vid : 0xFFFFFFFFu);\n"
"    float4 t = tt.read(vid < c ? vid : 0xFFFFFFFFu);\n"
"    float2 uv = tu.read(vid < c ? vid : 0xFFFFFFFFu).xy;\n"
"    float4 acc = 0.0; uint cg = P.nu;\n"
"    for (uint k = 0; k < P.nu; ++k) acc += tg.read(k < cg ? k : 0xFFFFFFFFu);\n"
"    uint cv = tv.get_width();\n"
"    for (uint k = 0; k < P.nv; ++k) { uint i = vid + k; acc += tv.read(i < cv ? i : 0xFFFFFFFFu); }\n"
"    return finish(float3(px, py, pz), n, t, uv, acc);\n"
"}\n"
/* dev : pointeurs device bruts, aucun test. */
"vertex VOut v_dev(uint vid [[vertex_id]], constant Params &P [[buffer(4)]],\n"
"    device const packed_float3 *bp [[buffer(0)]], device const half4 *bn [[buffer(1)]],\n"
"    device const half4 *bt [[buffer(2)]], device const float2 *bu [[buffer(3)]],\n"
"    device const float4 *bg [[buffer(5)]], device const float4 *bv [[buffer(6)]]) {\n"
"    float3 p = float3(bp[vid]); float4 n = float4(bn[vid]); float4 t = float4(bt[vid]); float2 uv = bu[vid];\n"
"    float4 acc = 0.0;\n"
"    for (uint k = 0; k < P.nu; ++k) acc += bg[k];\n"
"    for (uint k = 0; k < P.nv; ++k) acc += bv[vid + k];\n"
"    return finish(p, n, t, uv, acc);\n"
"}\n"
/* devchk : pointeurs device, test de bornes par lecture (valeur 0 hors bornes). */
"vertex VOut v_devchk(uint vid [[vertex_id]], constant Params &P [[buffer(4)]],\n"
"    device const packed_float3 *bp [[buffer(0)]], device const half4 *bn [[buffer(1)]],\n"
"    device const half4 *bt [[buffer(2)]], device const float2 *bu [[buffer(3)]],\n"
"    device const float4 *bg [[buffer(5)]], device const float4 *bv [[buffer(6)]]) {\n"
"    uint c = P.count;\n"
"    float3 p = vid < c ? float3(bp[vid]) : float3(0.0);\n"
"    float4 n = vid < c ? float4(bn[vid]) : float4(0.0);\n"
"    float4 t = vid < c ? float4(bt[vid]) : float4(0.0);\n"
"    float2 uv = vid < c ? bu[vid] : float2(0.0);\n"
"    float4 acc = 0.0; uint cg = P.nu;\n"
"    for (uint k = 0; k < P.nu; ++k) acc += (k < cg) ? bg[k] : float4(0.0);\n"
"    uint cv = P.count + 256u;\n"
"    for (uint k = 0; k < P.nv; ++k) { uint i = vid + k; acc += (i < cv) ? bv[i] : float4(0.0); }\n"
"    return finish(p, n, t, uv, acc);\n"
"}\n"
/* devonce : un seul test par sommet, puis lectures brutes. */
"vertex VOut v_devonce(uint vid [[vertex_id]], constant Params &P [[buffer(4)]],\n"
"    device const packed_float3 *bp [[buffer(0)]], device const half4 *bn [[buffer(1)]],\n"
"    device const half4 *bt [[buffer(2)]], device const float2 *bu [[buffer(3)]],\n"
"    device const float4 *bg [[buffer(5)]], device const float4 *bv [[buffer(6)]]) {\n"
"    if (vid >= P.count) { VOut o; o.pos = float4(0.0, 0.0, 0.0, 1.0); o.c = 0.0; return o; }\n"
"    float3 p = float3(bp[vid]); float4 n = float4(bn[vid]); float4 t = float4(bt[vid]); float2 uv = bu[vid];\n"
"    float4 acc = 0.0;\n"
"    for (uint k = 0; k < P.nu; ++k) acc += bg[k];\n"
"    for (uint k = 0; k < P.nv; ++k) acc += bv[vid + k];\n"
"    return finish(p, n, t, uv, acc);\n"
"}\n"
/* stagein : attributs natifs. */
"struct VIn { float3 p [[attribute(0)]]; half4 n [[attribute(1)]]; half4 t [[attribute(2)]]; float2 uv [[attribute(3)]]; };\n"
"vertex VOut v_stagein(VIn in [[stage_in]], uint vid [[vertex_id]], constant Params &P [[buffer(4)]],\n"
"    device const float4 *bg [[buffer(5)]], device const float4 *bv [[buffer(6)]]) {\n"
"    float4 acc = 0.0;\n"
"    for (uint k = 0; k < P.nu; ++k) acc += bg[k];\n"
"    for (uint k = 0; k < P.nv; ++k) acc += bv[vid + k];\n"
"    return finish(in.p, float4(in.n), float4(in.t), in.uv, acc);\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]]) { return in.c; }\n"
/* verification de la semantique hors bornes des texture_buffer */
"kernel void k_oob(texture_buffer<float> tb [[texture(0)]], device float4 *out [[buffer(0)]], uint tid [[thread_position_in_grid]]) {\n"
"    if (tid == 0) { out[0] = tb.read(0u); out[1] = tb.read(tb.get_width() - 1u); out[2] = tb.read(tb.get_width()); out[3] = tb.read(0xFFFFFFFFu); }\n"
"}\n";

static int cmp_d(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }

int main(int argc, char **argv)
{
   @autoreleasepool {
      uint32_t nu = argc > 1 ? (uint32_t)atoi(argv[1]) : 0u;
      uint32_t dessins = argc > 2 ? (uint32_t)atoi(argv[2]) : 10u;
      int tours = argc > 3 ? atoi(argv[3]) : 7;
      uint32_t nv = argc > 4 ? (uint32_t)atoi(argv[4]) : 0u;
      uint32_t N = argc > 5 ? (uint32_t)atoi(argv[5]) : 1000002u;
      N -= N % 3u;
      id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
      NSError *err = nil;
      id<MTLLibrary> lib = [dev newLibraryWithSource:@(src) options:nil error:&err];
      if (!lib) { printf("compilation : %s\n", [[err description] UTF8String]); return 1; }

      /* donnees : positions dans [0,1], normales/tangentes half4 dans [-1,1], uv dans [0,1] */
      id<MTLBuffer> bp = [dev newBufferWithLength:(NSUInteger)N * 12 options:MTLResourceStorageModeShared];
      id<MTLBuffer> bn = [dev newBufferWithLength:(NSUInteger)N * 8 options:MTLResourceStorageModeShared];
      id<MTLBuffer> bt = [dev newBufferWithLength:(NSUInteger)N * 8 options:MTLResourceStorageModeShared];
      id<MTLBuffer> bu = [dev newBufferWithLength:(NSUInteger)N * 8 options:MTLResourceStorageModeShared];
      id<MTLBuffer> bg = [dev newBufferWithLength:256 * 16 options:MTLResourceStorageModeShared];
      id<MTLBuffer> bv = [dev newBufferWithLength:((NSUInteger)N + 256) * 16 options:MTLResourceStorageModeShared];
      float *fp = [bp contents]; uint16_t *hn = [bn contents]; uint16_t *ht = [bt contents]; float *fu = [bu contents];
      float *fg = [bg contents]; float *fv = [bv contents];
      srand(1234);
      for (uint32_t i = 0; i < N * 3; ++i) fp[i] = (float)rand() / RAND_MAX;
      for (uint32_t i = 0; i < N * 4; ++i) { hn[i] = 0x3C00 ^ (uint16_t)(rand() & 0x83FF); ht[i] = 0x3C00 ^ (uint16_t)(rand() & 0x83FF); }
      for (uint32_t i = 0; i < N * 2; ++i) fu[i] = (float)rand() / RAND_MAX;
      for (uint32_t i = 0; i < 256 * 4; ++i) fg[i] = (float)rand() / RAND_MAX;
      for (uint32_t i = 0; i < (N + 256) * 4; ++i) fv[i] = (float)rand() / RAND_MAX;

      /* vues texture_buffer sur les memes tampons */
      id<MTLTexture> (^tb)(id<MTLBuffer>, MTLPixelFormat, NSUInteger, NSUInteger) = ^(id<MTLBuffer> b, MTLPixelFormat f, NSUInteger w, NSUInteger stride) {
         MTLTextureDescriptor *d = [MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:f width:w
            resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];
         return [b newTextureWithDescriptor:d offset:0 bytesPerRow:w * stride];
      };
      id<MTLTexture> tp = tb(bp, MTLPixelFormatR32Float, N * 3, 4);
      id<MTLTexture> tn = tb(bn, MTLPixelFormatRGBA16Float, N, 8);
      id<MTLTexture> tt = tb(bt, MTLPixelFormatRGBA16Float, N, 8);
      id<MTLTexture> tu = tb(bu, MTLPixelFormatRG32Float, N, 8);
      id<MTLTexture> tg = tb(bg, MTLPixelFormatRGBA32Float, 256, 16);
      id<MTLTexture> tv = tb(bv, MTLPixelFormatRGBA32Float, N + 256, 16);
      if (!tp || !tn || !tt || !tu || !tg || !tv) { printf("vue texture_buffer refusee\n"); return 1; }

      struct { uint32_t count, nu, nv; } params = { N, nu, nv };
      id<MTLBuffer> pb = [dev newBufferWithLength:sizeof params options:MTLResourceStorageModeShared];
      memcpy([pb contents], &params, sizeof params);

      /* semantique hors bornes */
      {
         id<MTLComputePipelineState> kp = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_oob"] error:&err];
         id<MTLBuffer> ob = [dev newBufferWithLength:64 options:MTLResourceStorageModeShared];
         memset([ob contents], 0x7f, 64);
         id<MTLCommandQueue> q0 = [dev newCommandQueue];
         id<MTLCommandBuffer> cb = [q0 commandBuffer];
         id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
         [e setComputePipelineState:kp]; [e setTexture:tg atIndex:0]; [e setBuffer:ob offset:0 atIndex:0];
         [e dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
         [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
         float *o = [ob contents];
         printf("texture_buffer hors bornes : read(0)=%.3f read(w-1)=%.3f read(w)=%.3f,%.3f,%.3f,%.3f read(-1)=%.3f,%.3f,%.3f,%.3f\n",
                o[0], o[4], o[8], o[9], o[10], o[11], o[12], o[13], o[14], o[15]);
      }

      MTLTextureDescriptor *rd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
      rd.usage = MTLTextureUsageRenderTarget; rd.storageMode = MTLStorageModePrivate;
      id<MTLTexture> rt = [dev newTextureWithDescriptor:rd];

      const char *modes[] = { "tex", "dev", "devchk", "devonce", "stagein" };
      const char *fns[] = { "v_tex", "v_dev", "v_devchk", "v_devonce", "v_stagein" };
      const int NM = 5;
      id<MTLRenderPipelineState> pso[5];
      for (int m = 0; m < NM; ++m) {
         MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
         pd.vertexFunction = [lib newFunctionWithName:[NSString stringWithUTF8String:fns[m]]];
         pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
         pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
         if (m == 4) {
            MTLVertexDescriptor *vd = [[MTLVertexDescriptor alloc] init];
            vd.attributes[0].format = MTLVertexFormatFloat3; vd.attributes[0].bufferIndex = 0; vd.attributes[0].offset = 0;
            vd.attributes[1].format = MTLVertexFormatHalf4;  vd.attributes[1].bufferIndex = 1; vd.attributes[1].offset = 0;
            vd.attributes[2].format = MTLVertexFormatHalf4;  vd.attributes[2].bufferIndex = 2; vd.attributes[2].offset = 0;
            vd.attributes[3].format = MTLVertexFormatFloat2; vd.attributes[3].bufferIndex = 3; vd.attributes[3].offset = 0;
            vd.layouts[0].stride = 12; vd.layouts[1].stride = 8; vd.layouts[2].stride = 8; vd.layouts[3].stride = 8;
            pd.vertexDescriptor = vd;
         }
         pso[m] = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
         if (!pso[m]) { printf("pipeline %s : %s\n", modes[m], [[err description] UTF8String]); return 1; }
      }

      id<MTLCommandQueue> q = [dev newCommandQueue];
      double *mes = calloc((size_t)NM * tours, sizeof(double));
      for (int tour = 0; tour < tours; ++tour) {
         for (int m = 0; m < NM; ++m) {
            id<MTLCommandBuffer> cb = [q commandBuffer];
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            rp.colorAttachments[0].storeAction = MTLStoreActionDontCare;
            id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:pso[m]];
            [e setVertexBuffer:bp offset:0 atIndex:0];
            [e setVertexBuffer:bn offset:0 atIndex:1];
            [e setVertexBuffer:bt offset:0 atIndex:2];
            [e setVertexBuffer:bu offset:0 atIndex:3];
            [e setVertexBuffer:pb offset:0 atIndex:4];
            [e setVertexBuffer:bg offset:0 atIndex:5];
            [e setVertexBuffer:bv offset:0 atIndex:6];
            [e setVertexTexture:tp atIndex:0]; [e setVertexTexture:tn atIndex:1];
            [e setVertexTexture:tt atIndex:2]; [e setVertexTexture:tu atIndex:3];
            [e setVertexTexture:tg atIndex:4]; [e setVertexTexture:tv atIndex:5];
            for (uint32_t d = 0; d < dessins; ++d)
               [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:N];
            [e endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
            if (cb.status != MTLCommandBufferStatusCompleted) { printf("tampon de commandes en erreur (%s)\n", modes[m]); return 1; }
            mes[m * tours + tour] = (cb.GPUEndTime - cb.GPUStartTime) * 1e3 / dessins;
         }
      }
      printf("sommets=%u dessins/cb=%u tours=%d lectures uniformes=%u lectures par sommet=%u ; ms GPU par dessin (mediane [min..max])\n", N, dessins, tours, nu, nv);
      double ref = 0;
      for (int m = 0; m < NM; ++m) {
         qsort(mes + m * tours, tours, sizeof(double), cmp_d);
         double med = mes[m * tours + tours / 2];
         if (m == 0) ref = med;
         printf("  %-8s %7.3f ms  [%.3f..%.3f]  x%.2f vs tex  (%.1f ns/sommet)\n", modes[m], med,
                mes[m * tours], mes[m * tours + tours - 1], med / ref, med * 1e6 / N);
      }
      free(mes);
   }
   return 0;
}
