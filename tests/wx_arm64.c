/* Que macOS arm64 accepte-t-il pour un JIT ?
 *
 * FEX alloue sa memoire de code en lecture-ecriture-execution. macOS arm64
 * l'interdit en principe, sauf par MAP_JIT assorti de
 * pthread_jit_write_protect_np. On mesure les trois voies : RWX direct,
 * RW puis mprotect en RX, et MAP_JIT.
 */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <pthread.h>
#include <errno.h>

static const unsigned int retourne_42[] = { 0xd2800540, 0xd65f03c0 }; /* mov x0,#42 ; ret */

static int essayer(const char *nom, void *p, int executer)
{
    if (p == MAP_FAILED) { printf("  %-28s ECHEC (%s)\n", nom, strerror(errno)); return 0; }
    if (!executer) { printf("  %-28s alloue a %p\n", nom, p); return 1; }
    memcpy(p, retourne_42, sizeof(retourne_42));
    __builtin___clear_cache((char *)p, (char *)p + sizeof(retourne_42));
    printf("  %-28s -> %d\n", nom, ((int (*)(void))p)());
    return 1;
}

int main(void)
{
    size_t t = 16384;
    void *p;

    printf("RWX direct\n");
    p = mmap(NULL, t, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANON, -1, 0);
    essayer("mmap RWX", p, p != MAP_FAILED);

    printf("RW puis mprotect RX\n");
    p = mmap(NULL, t, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if (essayer("mmap RW", p, 0)) {
        memcpy(p, retourne_42, sizeof(retourne_42));
        if (mprotect(p, t, PROT_READ|PROT_EXEC)) printf("  mprotect RX ECHEC (%s)\n", strerror(errno));
        else { __builtin___clear_cache(p, (char *)p + t); printf("  mprotect RX -> %d\n", ((int (*)(void))p)()); }
    }

    printf("MAP_JIT\n");
    p = mmap(NULL, t, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
    if (essayer("mmap MAP_JIT", p, 0)) {
        pthread_jit_write_protect_np(0);
        memcpy(p, retourne_42, sizeof(retourne_42));
        pthread_jit_write_protect_np(1);
        __builtin___clear_cache(p, (char *)p + t);
        printf("  MAP_JIT execution       -> %d\n", ((int (*)(void))p)());
    }
    return 0;
}
