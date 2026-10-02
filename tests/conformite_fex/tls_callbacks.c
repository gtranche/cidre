#include <windows.h>
#include <stdio.h>
volatile __thread int dummy = 0x1234;   /* volatile + utilisé -> survit */
volatile int cb_proc=0, cb_tattach=0, cb_tdetach=0;
void NTAPI tls_cb(void* h, DWORD reason, void* r){
    if(reason==DLL_PROCESS_ATTACH) cb_proc++;
    else if(reason==DLL_THREAD_ATTACH) cb_tattach++;
    else if(reason==DLL_THREAD_DETACH) cb_tdetach++;
}
__attribute__((section(".CRT$XLB"), used)) PIMAGE_TLS_CALLBACK p_cb = tls_cb;
static DWORD WINAPI worker(void* p){ return dummy; }
int main(void){
    printf("dummy(main)=0x%x\n", dummy);
    HANDLE h=CreateThread(0,0,worker,0,0,0); WaitForSingleObject(h,3000);
    HANDLE h2=CreateThread(0,0,worker,0,0,0); WaitForSingleObject(h2,3000);
    printf("TLS cb: process=%d thread_attach=%d thread_detach=%d\n", cb_proc, cb_tattach, cb_tdetach);
    printf(cb_tattach>=2 ? "thread_attach OK\n" : "thread_attach MANQUE -> callbacks TLS non lances sur threads = BUG DbD\n");
    return 0;
}
