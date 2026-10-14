// Sonde Metal : ce qu'il manque au Shader Model 6.6 (Unreal 5 en D3D12) sur ce Mac.
// Chaque capacite est essayee pour de vrai : compilation MSL puis execution et
// verification. Metal seul, sans Wine ni KosmicKrisp, ~2 s.
//   clang -arch arm64 -fobjc-arc -framework Metal -framework Foundation sonde_sm66.m -o sonde_sm66 && ./sonde_sm66
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

static id<MTLDevice> dev;
static id<MTLCommandQueue> q;

// Compile `src` (noyau « k ») ; NULL et la raison si le compilateur refuse.
static id<MTLComputePipelineState> compiler(NSString *src, NSString **raison) {
   NSError *e = nil;
   MTLCompileOptions *o = [MTLCompileOptions new];
   o.mathMode = MTLMathModeSafe;
   id<MTLLibrary> l = [dev newLibraryWithSource:src options:o error:&e];
   if (!l) {
      NSString *m = e.localizedDescription;
      NSRange r = [m rangeOfString:@"error: "];
      *raison = r.location != NSNotFound ? [[m substringFromIndex:r.location + 7] componentsSeparatedByString:@"\n"][0] : m;
      return nil;
   }
   id<MTLComputePipelineState> p = [dev newComputePipelineStateWithFunction:[l newFunctionWithName:@"k"] error:&e];
   if (!p) *raison = e.localizedDescription;
   return p;
}

static void lancer(id<MTLComputePipelineState> p, NSArray *tampons, NSArray *textures, NSUInteger fils) {
   id<MTLCommandBuffer> cb = [q commandBuffer];
   id<MTLComputeCommandEncoder> c = [cb computeCommandEncoder];
   [c setComputePipelineState:p];
   for (NSUInteger i = 0; i < tampons.count; i++) [c setBuffer:tampons[i] offset:0 atIndex:i];
   for (NSUInteger i = 0; i < textures.count; i++) [c setTexture:textures[i] atIndex:i];
   [c dispatchThreads:MTLSizeMake(fils, 1, 1) threadsPerThreadgroup:MTLSizeMake(MIN(fils, 64), 1, 1)];
   [c endEncoding];
   [cb commit];
   [cb waitUntilCompleted];
}

static void ligne(const char *nom, const char *verdict, NSString *detail) {
   printf("  %-44s %-6s %s\n", nom, verdict, detail ? detail.UTF8String : "");
}

// Atomique 64 bits sur tampon : 64 fils appliquent `op` ; `attendu` est la valeur finale.
static void atomique_tampon(const char *nom, NSString *corps, uint64_t depart, uint64_t attendu) {
   NSString *src = [NSString stringWithFormat:
      @"#include <metal_stdlib>\nusing namespace metal;\n"
       "kernel void k(device atomic_ulong *a [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
       "  ulong v = ulong(i) + 1ul + (1ul << 40);\n  %@;\n}\n", corps];
   NSString *raison = nil;
   id<MTLComputePipelineState> p = compiler(src, &raison);
   if (!p) { ligne(nom, "NON", raison); return; }
   id<MTLBuffer> b = [dev newBufferWithLength:8 options:MTLResourceStorageModeShared];
   memcpy(b.contents, &depart, 8);
   lancer(p, @[b], @[], 64);
   uint64_t r; memcpy(&r, b.contents, 8);
   ligne(nom, r == attendu ? "oui" : "FAUX",
         r == attendu ? nil : [NSString stringWithFormat:@"(obtenu %#llx, attendu %#llx)", r, attendu]);
}

// Atomique 64 bits sur texture (RG32Uint, usage atomique).
static void atomique_texture(const char *nom, NSString *appel, uint64_t depart, uint64_t attendu) {
   NSString *src = [NSString stringWithFormat:
      @"#include <metal_stdlib>\nusing namespace metal;\n"
       "kernel void k(texture2d<ulong, access::read_write> t [[texture(0)]], uint i [[thread_position_in_grid]]) {\n"
       "  ulong v = ulong(i) + 1ul + (1ul << 40);\n  t.%@;\n}\n", appel];
   NSString *raison = nil;
   id<MTLComputePipelineState> p = compiler(src, &raison);
   if (!p) { ligne(nom, "NON", raison); return; }
   MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG32Uint width:1 height:1 mipmapped:NO];
   td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageShaderAtomic;
   td.storageMode = MTLStorageModeShared;
   id<MTLTexture> t = [dev newTextureWithDescriptor:td];
   if (!t) { ligne(nom, "NON", @"(texture RG32Uint atomique refusee)"); return; }
   [t replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&depart bytesPerRow:8];
   lancer(p, @[], @[t], 64);
   uint64_t r; [t getBytes:&r bytesPerRow:8 fromRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0];
   ligne(nom, r == attendu ? "oui" : "FAUX",
         r == attendu ? nil : [NSString stringWithFormat:@"(obtenu %#llx, attendu %#llx)", r, attendu]);
}

// Denormaux : x * 1 sur un denormal, en mode « safe » (pas de repliement a la compilation).
static void denormaux(void) {
   NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
      "kernel void k(device const float *f [[buffer(0)]], device const half *h [[buffer(1)]],\n"
      "              device float *of [[buffer(2)]], device half *oh [[buffer(3)]], uint i [[thread_position_in_grid]]) {\n"
      "  of[i] = f[i] * f[2]; oh[i] = h[i] * h[2];\n}\n";
   NSString *raison = nil;
   id<MTLComputePipelineState> p = compiler(src, &raison);
   if (!p) { ligne("denormaux", "?", raison); return; }
   float f[3] = {1e-40f, -1e-40f, 1.0f};
   __fp16 h[3] = {(__fp16)3e-6f, (__fp16)-3e-6f, (__fp16)1.0f};
   id<MTLBuffer> bf = [dev newBufferWithBytes:f length:sizeof(f) options:0], bh = [dev newBufferWithBytes:h length:sizeof(h) options:0];
   id<MTLBuffer> of = [dev newBufferWithLength:16 options:0], oh = [dev newBufferWithLength:8 options:0];
   lancer(p, @[bf, bh, of, oh], @[], 2);
   float rf = ((float *)of.contents)[0]; __fp16 rh = ((__fp16 *)oh.contents)[0];
   ligne("denormaux fp32 preserves (SM 6.2+)", rf != 0.0f ? "oui" : "NON",
         [NSString stringWithFormat:@"(1e-40 * 1 = %g : %@)", rf, rf != 0.0f ? @"preserve" : @"remis a zero, sans reglage"]);
   ligne("denormaux fp16 preserves", (float)rh != 0.0f ? "oui" : "NON", [NSString stringWithFormat:@"(3e-6 * 1 = %g)", (float)rh]);
}

static void compiler_seulement(const char *nom, NSString *corps, NSString *note) {
   NSString *src = [NSString stringWithFormat:
      @"#include <metal_stdlib>\nusing namespace metal;\n"
       "kernel void k(device float *o [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n  %@;\n}\n", corps];
   NSString *raison = nil;
   id<MTLComputePipelineState> p = compiler(src, &raison);
   ligne(nom, p ? "oui" : "NON", p ? note : raison);
}

int main(void) {
   @autoreleasepool {
      dev = MTLCreateSystemDefaultDevice();
      q = [dev newCommandQueue];
      NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
      printf("%s, macOS %ld.%ld.%ld\n", dev.name.UTF8String, (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion);
      printf("  familles : Apple7 %d, Apple8 %d, Apple9 %d, Apple10 %d, Metal3 %d, Metal4 %d\n",
             [dev supportsFamily:MTLGPUFamilyApple7], [dev supportsFamily:MTLGPUFamilyApple8],
             [dev supportsFamily:MTLGPUFamilyApple9], [dev supportsFamily:(MTLGPUFamily)1010],
             [dev supportsFamily:MTLGPUFamilyMetal3], [dev supportsFamily:(MTLGPUFamily)5002]);

      printf("Atomiques 64 bits sur tampon (SM 6.6 exige add, min/max, and/or/xor, echange, comparaison-echange) :\n");
      uint64_t somme = 0, mx = 0, mn = ~0ull, ou = 0, et = ~0ull, ox = 0;
      for (uint64_t i = 0; i < 64; i++) {
         uint64_t x = i + 1 + (1ull << 40);
         somme += x; mx = x > mx ? x : mx; mn = x < mn ? x : mn; ou |= x; et &= x; ox ^= x;
      }
      atomique_tampon("add 64 bits", @"atomic_fetch_add_explicit(a, v, memory_order_relaxed)", 0, somme);
      atomique_tampon("max 64 bits", @"atomic_max_explicit(a, v, memory_order_relaxed)", 0, mx);
      atomique_tampon("min 64 bits", @"atomic_min_explicit(a, v, memory_order_relaxed)", ~0ull, mn);
      atomique_tampon("or 64 bits", @"atomic_fetch_or_explicit(a, v, memory_order_relaxed)", 0, ou);
      atomique_tampon("and 64 bits", @"atomic_fetch_and_explicit(a, v, memory_order_relaxed)", ~0ull, et);
      atomique_tampon("xor 64 bits", @"atomic_fetch_xor_explicit(a, v, memory_order_relaxed)", 0, ox);
      atomique_tampon("echange 64 bits", @"atomic_exchange_explicit(a, v, memory_order_relaxed)", 0, 0);
      atomique_tampon("comparaison-echange 64 bits",
         @"ulong e = 0; atomic_compare_exchange_weak_explicit(a, &e, v, memory_order_relaxed, memory_order_relaxed)", 0, 0);

      printf("Atomiques 64 bits sur texture (Nanite d'Unreal 5 : min/max sur image 64 bits) :\n");
      atomique_texture("texture max 64 bits", @"atomic_max(uint2(0), v)", 0, mx);
      atomique_texture("texture min 64 bits", @"atomic_min(uint2(0), v)", ~0ull, mn);
      atomique_texture("texture add 64 bits", @"atomic_fetch_add(uint2(0), v)", 0, somme);

      printf("Denormaux (SM 6.2+ : controle des denormaux fp32 independant) :\n");
      denormaux();

      printf("Derivees en calcul (SM 6.6 ; Vulkan computeDerivativeGroupLinear) :\n");
      compiler_seulement("dfdx dans un noyau de calcul", @"o[i] = dfdx(float(i))", nil);
      compiler_seulement("operations de quad dans un noyau (emulation)", @"o[i] = quad_shuffle_xor(float(i), 1u)",
                         @"(les derivees peuvent etre synthetisees par quad_shuffle)");
   }
   return 0;
}
