#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

#define MAGIC 0x00000001deadbeefULL

static void *brule(void *a){ for(;;) __asm__ volatile(""); return 0; }

int main(void)
{
    /* de la charge pour forcer la preemption */
    for (int i = 0; i < 12; i++) { pthread_t t; pthread_create(&t, NULL, brule, NULL); pthread_detach(t); }

    uint64_t v = MAGIC;
    __asm__ volatile("mov x18, %0" :: "r"(v));
    for (long i = 0; i < 2000000000L; i++) {
        uint64_t c;
        __asm__ volatile("mov %0, x18" : "=r"(c));
        if (c != MAGIC) { printf("x18 PERDU apres %ld tours : %llx\n", i, (unsigned long long)c); return 1; }
    }
    printf("x18 conserve sur 2 milliards de tours, sans aucun appel systeme\n");
    return 0;
}
