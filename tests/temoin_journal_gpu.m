// Temoin natif du journal GPU de winemetal (CIDRE_DXMT_JOURNAL_GPU) : le code du
// journal est extrait tel quel de src/winemetal/unix/winemetal_unix.c (entre les
// marques « cidre-journal-gpu: ») et pousse sur ses trois chemins, sans Wine :
//   1. tampons normaux       -> lignes « releve » ;
//   2. tampon en erreur      -> ligne « ERREUR » + etat des encodeurs (tampon qui
//                               lit un MTLBuffer purgeable vide : InvalidResource,
//                               refuse par le pilote, sans faute GPU ni attente) ;
//   3. tampon bloque         -> lignes « GEL ? » (attente d'un MTLSharedEvent que
//                               le CPU ne signale qu'apres 3,5 s : rien ne tourne
//                               sur le GPU pendant ce temps) ;
//   4. tampon long (option « lent ») -> ligne « lent » (calcul de ~260-520 ms).
//
//   sh construire_temoin_journal_gpu.sh && ./temoin_journal_gpu <journal> [lent]
// Codes : 0 = chaque chemin a ecrit sa ligne, 2 = une ligne manque, 1 = echec.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "journal_gpu_extrait.inc"

static void
commit(id<MTLCommandBuffer> cb) {
  cidre_jgpu_soumis();
  [cb commit];
}

static const char *KERNEL =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "kernel void k(device uint *b [[buffer(0)]], constant uint &n [[buffer(1)]], uint i [[thread_position_in_grid]]) {\n"
    "  uint h = i;\n"
    "  for (uint k = 0; k < n; k++) h = h * 1664525u + 1013904223u;\n"
    "  b[i] = h;\n"
    "}\n";

static int
compter(const char *chemin, const char *motif) {
  FILE *f = fopen(chemin, "r");
  if (!f) return -1;
  char ligne[4096];
  int n = 0;
  while (fgets(ligne, sizeof(ligne), f))
    if (strstr(ligne, motif)) n++;
  fclose(f);
  return n;
}

int
main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      printf("usage : temoin_journal_gpu <journal> [lent]\n");
      return 1;
    }
    const char *chemin = argv[1];
    bool lent = argc > 2 && !strcmp(argv[2], "lent");
    unlink(chemin);
    setenv("CIDRE_DXMT_JOURNAL_GPU", chemin, 1);
    if (!cidre_jgpu_actif()) {
      printf("ECHEC : journal non ouvert\n");
      return 1;
    }
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> q = [dev newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:KERNEL] options:nil error:&err];
    id<MTLComputePipelineState> pso = lib ? [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&err] : nil;
    if (!pso) {
      printf("ECHEC : pipeline : %s\n", err.localizedDescription.UTF8String);
      return 1;
    }
    printf("temoin_journal_gpu : %s, journal %s\n", dev.name.UTF8String, chemin);
    const NSUInteger N = 1 << 16;
    id<MTLBuffer> b = [dev newBufferWithLength:N * 4 options:MTLResourceStorageModeShared];

    // 1. tampons normaux, avec une etiquette d'encodeur
    for (int i = 0; i < 20; i++) {
      id<MTLCommandBuffer> cb = cidre_jgpu_tampon(q);
      id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
      e.label = @"C disp=1 (temoin normal)";
      uint32_t n = 16;
      [e setComputePipelineState:pso];
      [e setBuffer:b offset:0 atIndex:0];
      [e setBytes:&n length:4 atIndex:1];
      [e dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
      [e endEncoding];
      commit(cb);
      [cb waitUntilCompleted];
    }
    printf("1. normaux : 20 tampons finis\n");

    // 2. tampon en erreur : buffer purgeable vide
    {
      id<MTLBuffer> vide = [dev newBufferWithLength:N * 4 options:MTLResourceStorageModeShared];
      [vide setPurgeableState:MTLPurgeableStateEmpty];
      id<MTLCommandBuffer> cb = cidre_jgpu_tampon(q);
      id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
      e.label = @"C disp=1 (temoin purgeable vide)";
      uint32_t n = 16;
      [e setComputePipelineState:pso];
      [e setBuffer:vide offset:0 atIndex:0];
      [e setBytes:&n length:4 atIndex:1];
      [e dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
      [e endEncoding];
      commit(cb);
      [cb waitUntilCompleted];
      printf("2. erreur : statut %ld, %s\n", (long)cb.status,
             cb.error ? cb.error.localizedDescription.UTF8String : "aucune erreur");
    }

    // 3. tampon bloque sur un evenement que le CPU signale apres 3,5 s
    {
      id<MTLSharedEvent> ev = [dev newSharedEvent];
      id<MTLCommandBuffer> cb = cidre_jgpu_tampon(q);
      [cb encodeWaitForEvent:ev value:1];
      commit(cb);
      [NSThread sleepForTimeInterval:3.5];
      ev.signaledValue = 1;
      [cb waitUntilCompleted];
      printf("3. bloque : libere apres 3,5 s, statut %ld\n", (long)cb.status);
    }

    // 4. tampon long (option) : on double la boucle jusqu'a depasser 260 ms
    if (lent) {
      for (uint32_t n = 1 << 12; n <= (1u << 24); n <<= 1) {
        id<MTLCommandBuffer> cb = cidre_jgpu_tampon(q);
        id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
        e.label = @"C disp=1 (temoin long)";
        [e setComputePipelineState:pso];
        [e setBuffer:b offset:0 atIndex:0];
        [e setBytes:&n length:4 atIndex:1];
        [e dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [e endEncoding];
        commit(cb);
        [cb waitUntilCompleted];
        double ms = (cb.GPUEndTime - cb.GPUStartTime) * 1000.0;
        if (ms > 260.0) {
          printf("4. long : %u tours, %.1f ms\n", n, ms);
          break;
        }
      }
    }

    [NSThread sleepForTimeInterval:2.5]; // un releve de plus
    int ouvert = compter(chemin, "journal ouvert"), erreur = compter(chemin, "ERREUR"),
        encodeur = compter(chemin, "  encodeur "), gel = compter(chemin, "GEL ?"), releve = compter(chemin, "releve :"),
        l = compter(chemin, "lent :");
    printf("resultat : ouvert %d, ERREUR %d, encodeurs %d, GEL %d, releves %d, lent %d\n", ouvert, erreur, encodeur, gel,
           releve, l);
    bool ok = ouvert == 1 && erreur >= 1 && gel >= 2 && releve >= 2 && (!lent || l >= 1);
    printf("%s\n", ok ? "TEMOIN OK : chaque chemin du journal a ecrit sa ligne" : "TEMOIN INCOMPLET : une ligne manque");
    return ok ? 0 : 2;
  }
}
