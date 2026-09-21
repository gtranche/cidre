/* Repere : chaine de multiplications-additions dependantes, purement ALU.
 * Meme calcul que tests/bench_alu_vulkan.c, ecrit directement en MSL. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <time.h>

static const char *source =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"kernel void bench(device uint *params [[buffer(0)]],\n"
"                  device float *out [[buffer(1)]],\n"
"                  uint tid [[thread_position_in_grid]])\n"
"{\n"
"    uint n = params[0];\n"
"    float acc = float(tid) * 1e-6f;\n"
"    float a = 1.0000001f, c = 1e-7f;\n"
"    for (uint i = 0u; i < n; ++i)\n"
"        acc = fma(acc, a, c);\n"
"    out[tid] = acc;\n"
"}\n";

static double maintenant(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        uint32_t iterations = argc > 1 ? (uint32_t)atoi(argv[1]) : 100000u;
        uint32_t fils = argc > 2 ? (uint32_t)atoi(argv[2]) : 65536u;

        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:@(source) options:nil error:&err];
        if (!lib) { printf("compilation : %s\n", [[err description] UTF8String]); return 1; }
        id<MTLFunction> fn = [lib newFunctionWithName:@"bench"];
        id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:fn error:&err];
        if (!pso) { printf("pipeline : %s\n", [[err description] UTF8String]); return 1; }

        id<MTLBuffer> params = [dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
        ((uint32_t *)[params contents])[0] = iterations;
        id<MTLBuffer> out = [dev newBufferWithLength:fils * 4 options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> q = [dev newCommandQueue];

        double meilleur = 1e9;
        for (int rep = 0; rep < 5; ++rep) {
            double t0 = maintenant();
            id<MTLCommandBuffer> cb = [q commandBuffer];
            id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
            [enc setComputePipelineState:pso];
            [enc setBuffer:params offset:0 atIndex:0];
            [enc setBuffer:out offset:0 atIndex:1];
            [enc dispatchThreads:MTLSizeMake(fils, 1, 1)
                threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
            [enc endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
            double dt = maintenant() - t0;
            if (dt < meilleur) meilleur = dt;
        }
        printf("metal-natif  iterations=%u fils=%u  meilleur=%.1f ms  sortie[0]=%g\n",
               iterations, fils, meilleur * 1e3, ((float *)[out contents])[0]);
    }
    return 0;
}
