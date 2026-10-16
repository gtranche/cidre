// Rejoue une recolte de KosmicKrisp (MESA_KK_RECOLTE) par l'ancienne API de
// Metal et ecrit une MTLBinaryArchive pour la puce de cette machine :
//   build/rejouer-mtl3 <dossier air> <pipelines.jsonl> <archive.metallib> [fils]
// Chaque ligne : {"t":"c","cs":[cle,nom],"tg":N} ou {"t":"r","vs":[cle,nom],
// "fs":[cle,nom]|null,"topo","rs","a2c","a2o","rast","amp","col":[[i,format,
// melange,src rgb,dst rgb,op rgb,src a,dst a,op a,masque],...]}, valeurs
// numeriques de Metal (les memes en MTL3 et MTL4). Les bibliotheques sont les
// AIR de air/<cle>.metallib : la meme metallib que KosmicKrisp chargera, d'ou la
// meme empreinte de fonction. L'archive (relue telle quelle par les recherches
// MTL4 de KosmicKrisp) sert ensuite a metal-source, dont le script nourrit
// metal-tt pour les autres architectures.
// Pipelines crees en parallele (le binaire va dans le cache de Metal), puis
// ajoutes a l'archive sous verrou (rien a recompiler).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <pthread.h>
#include <stdatomic.h>

static id<MTLDevice> dev;
static NSString *dossier_air;
static NSMutableDictionary<NSString *, id<MTLLibrary>> *libs;
static pthread_mutex_t verrou_libs = PTHREAD_MUTEX_INITIALIZER, verrou_archive = PTHREAD_MUTEX_INITIALIZER;
static NSArray<NSDictionary *> *lignes;
static id<MTLBinaryArchive> archive;
static atomic_int suivant, ok_n, ko_n, sans_air;

static id<MTLFunction> fonction(NSArray *ref) {
    if (![ref isKindOfClass:[NSArray class]] || ref.count != 2) return nil;
    NSString *cle = ref[0];
    pthread_mutex_lock(&verrou_libs);
    id<MTLLibrary> l = libs[cle];
    if (!l) {
        NSString *p = [dossier_air stringByAppendingPathComponent:[cle stringByAppendingString:@".metallib"]];
        l = [dev newLibraryWithURL:[NSURL fileURLWithPath:p] error:nil];
        if (l) libs[cle] = l;
    }
    pthread_mutex_unlock(&verrou_libs);
    return l ? [l newFunctionWithName:ref[1]] : nil;
}

static BOOL un(NSDictionary *j, NSString **err) {
    NSError *e = nil;
    if ([j[@"t"] isEqualToString:@"c"]) {
        MTLComputePipelineDescriptor *d = [MTLComputePipelineDescriptor new];
        d.computeFunction = fonction(j[@"cs"]);
        if (!d.computeFunction) { atomic_fetch_add(&sans_air, 1); *err = @"AIR absent"; return NO; }
        d.maxTotalThreadsPerThreadgroup = [j[@"tg"] unsignedIntegerValue];
        if (![dev newComputePipelineStateWithDescriptor:d options:MTLPipelineOptionNone reflection:nil error:&e]) {
            *err = e.localizedDescription; return NO;
        }
        pthread_mutex_lock(&verrou_archive);
        BOOL a = [archive addComputePipelineFunctionsWithDescriptor:d error:&e];
        pthread_mutex_unlock(&verrou_archive);
        if (!a) *err = e.localizedDescription;
        return a;
    }
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = fonction(j[@"vs"]);
    if (!d.vertexFunction) { atomic_fetch_add(&sans_air, 1); *err = @"AIR absent"; return NO; }
    if (j[@"fs"] != [NSNull null]) {
        d.fragmentFunction = fonction(j[@"fs"]);
        if (!d.fragmentFunction) { atomic_fetch_add(&sans_air, 1); *err = @"AIR absent"; return NO; }
    }
    d.inputPrimitiveTopology = [j[@"topo"] unsignedIntegerValue];
    d.rasterSampleCount = [j[@"rs"] unsignedIntegerValue];
    d.alphaToCoverageEnabled = [j[@"a2c"] boolValue];
    d.alphaToOneEnabled = [j[@"a2o"] boolValue];
    d.rasterizationEnabled = [j[@"rast"] boolValue];
    d.maxVertexAmplificationCount = [j[@"amp"] unsignedIntegerValue];
    for (NSArray *c in j[@"col"]) {
        MTLRenderPipelineColorAttachmentDescriptor *a = d.colorAttachments[[c[0] unsignedIntegerValue]];
        a.pixelFormat = [c[1] unsignedIntegerValue];
        a.blendingEnabled = [c[2] boolValue];
        a.sourceRGBBlendFactor = [c[3] unsignedIntegerValue];
        a.destinationRGBBlendFactor = [c[4] unsignedIntegerValue];
        a.rgbBlendOperation = [c[5] unsignedIntegerValue];
        a.sourceAlphaBlendFactor = [c[6] unsignedIntegerValue];
        a.destinationAlphaBlendFactor = [c[7] unsignedIntegerValue];
        a.alphaBlendOperation = [c[8] unsignedIntegerValue];
        a.writeMask = [c[9] unsignedIntegerValue];
    }
    if (![dev newRenderPipelineStateWithDescriptor:d options:MTLPipelineOptionNone reflection:nil error:&e]) {
        *err = e.localizedDescription; return NO;
    }
    pthread_mutex_lock(&verrou_archive);
    BOOL a = [archive addRenderPipelineFunctionsWithDescriptor:d error:&e];
    pthread_mutex_unlock(&verrou_archive);
    if (!a) *err = e.localizedDescription;
    return a;
}

static void *fil(void *arg) {
    for (;;) {
        int i = atomic_fetch_add(&suivant, 1);
        if (i >= (int)lignes.count) return NULL;
        @autoreleasepool {
            NSString *err = nil;
            if (un(lignes[i], &err)) atomic_fetch_add(&ok_n, 1);
            else {
                atomic_fetch_add(&ko_n, 1);
                if (![err isEqualToString:@"AIR absent"]) fprintf(stderr, "ligne %d : %s\n", i + 1, err.UTF8String);
            }
        }
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 4) { fprintf(stderr, "usage : rejouer_mtl3 <air> <pipelines.jsonl> <archive> [fils]\n"); return 2; }
        dev = MTLCreateSystemDefaultDevice();
        dossier_air = @(argv[1]);
        libs = [NSMutableDictionary new];
        NSString *texte = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:nil];
        NSMutableArray *ls = [NSMutableArray new];
        NSMutableSet *vues = [NSMutableSet new];
        for (NSString *l in [texte componentsSeparatedByString:@"\n"]) {
            if (!l.length || [vues containsObject:l]) continue;
            [vues addObject:l];
            id j = [NSJSONSerialization JSONObjectWithData:[l dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([j isKindOfClass:[NSDictionary class]]) [ls addObject:j];
        }
        lignes = ls;
        NSError *e = nil;
        archive = [dev newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
        int nf = argc > 4 ? atoi(argv[4]) : 20;
        pthread_t th[64];
        NSDate *t0 = [NSDate date];
        for (int k = 0; k < nf && k < 64; k++) pthread_create(&th[k], NULL, fil, NULL);
        for (int k = 0; k < nf && k < 64; k++) pthread_join(th[k], NULL);
        double mur = -[t0 timeIntervalSinceNow];
        if (![archive serializeToURL:[NSURL fileURLWithPath:@(argv[3])] error:&e]) {
            fprintf(stderr, "archive non ecrite : %s\n", e.localizedDescription.UTF8String); return 1;
        }
        printf("%lu pipelines distincts : %d dans l'archive, %d en echec (dont %d sans AIR) ; %.1f s au mur, %d fils\n",
               (unsigned long)lignes.count, ok_n, ko_n, sans_air, mur, nf);
    }
    return 0;
}
