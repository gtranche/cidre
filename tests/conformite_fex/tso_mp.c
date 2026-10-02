#include <windows.h>
#include <stdio.h>
/* Litmus MP rapide : writer fait X=s puis Y=s (monotones). Sur TSO, un lecteur qui
   lit Y puis X doit voir X>=Y. Si FEX reordonne, il verra X<Y (comme singleton nul). */
__declspec(align(64)) volatile long X;
__declspec(align(64)) volatile long Y;
__declspec(align(64)) volatile long violations;
__declspec(align(64)) volatile long stop;
static DWORD WINAPI reader(void* p){
    long v=0;
    while(!stop){ long y=Y; long x=X; if(x<y) v++; }
    violations=v; return 0;
}
int main(void){
    HANDLE h=CreateThread(0,0,reader,0,0,0);
    const long N=80000000;
    for(long s=1;s<=N;s++){ X=s; Y=s; }
    stop=1; WaitForSingleObject(h,3000);
    printf("iterations writer=%ld  violations (X<Y vu par lecteur)=%ld\n", N, violations);
    printf(violations>0 ? "=> ORDRE MEMOIRE VIOLE sous FEX arm64ec (half-barrier) = cause probable !\n"
                        : "=> ordre memoire respecte : TSO OK, pas la cause\n");
    return 0;
}
