#include <windows.h>
#include <stdio.h>
__attribute__((noinline)) static int f(void){ return 1; }
static int (*volatile pf)(void) = f;   /* appel indirect volatile : pas de repli */
int main(void){
    unsigned char* c=(unsigned char*)(void*)f;
    DWORD old; VirtualProtect(c,32,PAGE_EXECUTE_READWRITE,&old);
    int before=pf();
    int patched=0;
    for(int i=0;i<24;i++){ if(c[i]==0xb8 && c[i+1]==0x01 && c[i+2]==0 && c[i+3]==0 && c[i+4]==0){ c[i+1]=0x02; patched=1; break; } }
    int after=pf();
    FlushInstructionCache(GetCurrentProcess(), c, 32);
    int after_flush=pf();
    printf("patch=%d avant=%d apres=%d apres_flush=%d\n", patched, before, after, after_flush);
    if(!patched) printf("motif introuvable\n");
    else if(after==2) printf("SMC vu sans flush : OK\n");
    else if(after_flush==2) printf("SMC vu seulement apres FlushInstructionCache\n");
    else printf("SMC JAMAIS vu = code perime execute\n");
    return 0;
}
