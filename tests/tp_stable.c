#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
static void *brule(void *a){ for(;;) __asm__ volatile(""); return 0; }
static inline uint64_t tp(void){ uint64_t v; __asm__ volatile("mrs %0, TPIDRRO_EL0":"=r"(v)); return v; }
int main(void){
    for (int i=0;i<10;i++){ pthread_t t; pthread_create(&t,NULL,brule,NULL); pthread_detach(t); }
    uint64_t ref = tp();
    printf("TPIDRRO_EL0 = %#llx   (self=%p, bits bas = %llu)\n",
           (unsigned long long)ref, (void*)pthread_self(), (unsigned long long)(ref & 7));
    for (long i=0;i<300000000L;i++){
        uint64_t c = tp();
        if ((c & ~7ULL) != (ref & ~7ULL)) { printf("PERDU apres %ld tours : %#llx\n", i, (unsigned long long)c); return 1; }
    }
    printf("stable sur 300 millions de tours, sous charge, sans appel systeme\n");
    return 0;
}
