// L'architecture GPU de ce Mac au sens des compilateurs de Metal (applegpu_g13s
// pour un M1 Pro ou Max, applegpu_g16g pour un M4...) : le nom des archives de
// pipelines precompilees que Cidre telecharge (tests/precompil_kk.sh). Metal ne
// le donne pas ; on compile un noyau minuscule dans une MTLBinaryArchive et on
// lit, dans l'en-tete Mach-O de l'archive, le sous-type de la tranche GPU, que
// la table ci-dessous traduit. La table vient de metal-tt (chaine Metal 17.6) :
// une archive par architecture, sous-type releve (cputype 0x1000013).
//   puce-gpu            le nom, ou « inconnu » (code 1)
//   puce-gpu --brut     cputype et sous-type en hexadecimal
// Construit par tests/empaqueter_runtime.sh (build/puce-gpu).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

static const struct { uint32_t sous_type; const char *nom; } table[] = {
    {0x142, "applegpu_g13g"}, {0x212, "applegpu_g13s"}, {0x252, "applegpu_g13d"},
    {0x192, "applegpu_g14g"}, {0x1b2, "applegpu_g14s"}, {0x1f2, "applegpu_g14d"},
    {0x113, "applegpu_g15g"}, {0x1a3, "applegpu_g15s"}, {0x0b3, "applegpu_g15d"},
    {0x193, "applegpu_g16g"}, {0x1d3, "applegpu_g16s"},
    {0x153, "applegpu_g17g"}, {0x163, "applegpu_g17s"}, {0x143, "applegpu_g17p"},
};
#define CPU_APPLEGPU 0x1000013u

// Le sous-type de la tranche GPU Apple d'une archive (grosse ou simple), 0 sinon.
static uint32_t sous_type(NSData *d) {
    const uint8_t *p = d.bytes;
    if (d.length < 32) return 0;
    uint32_t magie = OSReadBigInt32(p, 0);
    if (magie == FAT_MAGIC || magie == 0xcbfebabe) {   // grosse archive (cbfebabe : variante 64 bits de Metal)
        uint32_t n = OSReadBigInt32(p, 4);
        for (uint32_t i = 0; i < n && 8 + 20 * (i + 1) <= d.length; i++) {
            if (OSReadBigInt32(p, 8 + 20 * i) == CPU_APPLEGPU) return OSReadBigInt32(p, 12 + 20 * i);
        }
        return 0;
    }
    if (OSReadLittleInt32(p, 0) == MH_MAGIC_64 && OSReadLittleInt32(p, 4) == CPU_APPLEGPU)
        return OSReadLittleInt32(p, 8);
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL brut = argc > 1 && !strcmp(argv[1], "--brut");
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) { puts("inconnu"); return 1; }
        NSError *e = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:@"kernel void k(device uint *b [[buffer(0)]]) { b[0] = 1; }"
                                               options:nil error:&e];
        MTLComputePipelineDescriptor *cd = [MTLComputePipelineDescriptor new];
        cd.computeFunction = [lib newFunctionWithName:@"k"];
        id<MTLBinaryArchive> a = [dev newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
        NSString *f = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"cidre-puce-gpu.%d.metallib", getpid()]];
        uint32_t st = 0;
        if (cd.computeFunction && a && [a addComputePipelineFunctionsWithDescriptor:cd error:&e] &&
            [a serializeToURL:[NSURL fileURLWithPath:f] error:&e])
            st = sous_type([NSData dataWithContentsOfFile:f]);
        [[NSFileManager defaultManager] removeItemAtPath:f error:nil];
        if (brut) { printf("0x%x 0x%x\n", CPU_APPLEGPU, st); return st ? 0 : 1; }
        for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++)
            if (table[i].sous_type == st) { puts(table[i].nom); return 0; }
        puts("inconnu");
        return 1;
    }
}
