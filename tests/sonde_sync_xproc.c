/* Sonde : attente/reveil par adresse entre deux processus sur une page partagee (macOS).
 * Resultat sur macOS 26.5 (M1 Max) : OS_SYNC_*_NONE ne traverse pas les processus (timeout),
 * OS_SYNC_*_SHARED traverse (1000 allers-retours, 1,9 us chacun). Base de 0103-wine11-synchro-en-process-macos.
 * Compiler : cc -O2 -arch arm64 -o sonde_sync_xproc tests/sonde_sync_xproc.c ; lancer : ./sonde_sync_xproc none ; ./sonde_sync_xproc shared */
#include <os/os_sync_wait_on_address.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <stdatomic.h>
#include <mach/mach_time.h>
static double ns(void){ static mach_timebase_info_data_t tb; if(!tb.denom) mach_timebase_info(&tb); return (double)mach_absolute_time()*tb.numer/tb.denom; }
int main(int argc,char**argv){
    int shared = argc>1 && !strcmp(argv[1],"shared");
    uint32_t flags_wait = shared? OS_SYNC_WAIT_ON_ADDRESS_SHARED : OS_SYNC_WAIT_ON_ADDRESS_NONE;
    uint32_t flags_wake = shared? OS_SYNC_WAKE_BY_ADDRESS_SHARED : OS_SYNC_WAKE_BY_ADDRESS_NONE;
    char path[]="/tmp/sonde-sync-XXXXXX";
    int fd=mkstemp(path); unlink(path); ftruncate(fd,16384);
    _Atomic uint32_t *p = mmap(NULL,16384,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    p[0]=0; p[1]=0;
    pid_t child=fork();
    if(!child){
        /* enfant : mappe a part (autre adresse virtuelle), attend que p[0] passe a 1, puis repond sur p[1] */
        _Atomic uint32_t *q = mmap(NULL,16384,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        for(int i=0;i<1000;i++){
            while(atomic_load(q)!=i+1){ int r=os_sync_wait_on_address((void*)q,i,4,flags_wait); if(r<0 && errno!=EINTR && errno!=EAGAIN){perror("child wait"); _exit(2);} }
            atomic_store(q+1,i+1); os_sync_wake_by_address_any((void*)(q+1),4,flags_wake);
        }
        _exit(0);
    }
    usleep(20000);
    double t0=ns(); int ok=1;
    for(int i=0;i<1000;i++){
        atomic_store(p,i+1); os_sync_wake_by_address_any((void*)p,4,flags_wake);
        double t=ns(); while(atomic_load(p+1)!=i+1){ int r=os_sync_wait_on_address_with_timeout((void*)(p+1),i,4,flags_wait,OS_CLOCK_MACH_ABSOLUTE_TIME,200000000ull); if(r<0&&errno==ETIMEDOUT){ok=0;break;} }
        if(!ok){ printf("%s: TIMEOUT a l'iteration %d (reveil non recu)\n", shared?"SHARED":"NONE", i); kill(child,9); break; }
    }
    double t1=ns(); int st; waitpid(child,&st,0);
    if(ok) printf("%s: 1000 allers-retours inter-processus OK, %.2f us par aller-retour (attente+reveil x2)\n", shared?"SHARED":"NONE", (t1-t0)/1000/1000);
    return 0;
}
