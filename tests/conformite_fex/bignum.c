#include <windows.h>
#include <stdio.h>
#include <stdint.h>
static void cpuid(uint32_t leaf,uint32_t sub,uint32_t*r){ __asm__ volatile("cpuid":"=a"(r[0]),"=b"(r[1]),"=c"(r[2]),"=d"(r[3]):"a"(leaf),"c"(sub)); }
int main(void){
    uint32_t r[4]; cpuid(7,0,r);
    printf("CPUID leaf7: BMI2=%d  ADX=%d\n",(int)((r[1]>>8)&1),(int)((r[1]>>19)&1));
    uint64_t a=~0ULL,b=~0ULL,hi,lo;
    __asm__("mulq %3":"=a"(lo),"=d"(hi):"a"(a),"d"(b):"cc");
    int mul_ok=(hi==0xFFFFFFFFFFFFFFFEULL&&lo==1ULL);
    printf("MUL  = %016llx:%016llx  %s\n",(unsigned long long)hi,(unsigned long long)lo,mul_ok?"OK":"FAUX");
    uint64_t mhi=0,mlo=0;
    __asm__("mulx %3,%0,%1":"=r"(mlo),"=r"(mhi):"d"(a),"r"(b));
    int mulx_ok=(mhi==0xFFFFFFFFFFFFFFFEULL&&mlo==1ULL);
    printf("MULX = %016llx:%016llx  %s\n",(unsigned long long)mhi,(unsigned long long)mlo,mulx_ok?"OK":"FAUX");
    /* 4 limbes x 1 limbe : reference (MUL via __int128) vs MULX+ADCX */
    uint64_t A[4]={0x1111111111111111ULL,0x2222222222222222ULL,0x3333333333333333ULL,0x4444444444444444ULL};
    uint64_t m=0xFEDCBA9876543210ULL, ref[5]={0}, car=0;
    for(int i=0;i<4;i++){ unsigned __int128 p=(unsigned __int128)A[i]*m+car; ref[i]=(uint64_t)p; car=(uint64_t)(p>>64);} ref[4]=car;
    uint64_t out[5]={0};
    __asm__ volatile(
      "movq %2,%%rdx\n\t" "xorq %%r10,%%r10\n\t"
      "mulx 0(%1),%%r8,%%r9\n\t"   "movq %%r8,0(%0)\n\t"
      "mulx 8(%1),%%r8,%%r11\n\t"  "adcxq %%r9,%%r8\n\t"  "movq %%r8,8(%0)\n\t"
      "mulx 16(%1),%%r8,%%r9\n\t"  "adcxq %%r11,%%r8\n\t" "movq %%r8,16(%0)\n\t"
      "mulx 24(%1),%%r8,%%r11\n\t" "adcxq %%r9,%%r8\n\t"  "movq %%r8,24(%0)\n\t"
      "movq $0,%%r8\n\t"           "adcxq %%r11,%%r8\n\t" "movq %%r8,32(%0)\n\t"
      : : "r"(out),"r"(A),"r"(m) : "rdx","r8","r9","r10","r11","cc","memory");
    int bn_ok=1; for(int i=0;i<5;i++) if(out[i]!=ref[i]) bn_ok=0;
    printf("bignum MULX+ADCX vs reference : %s\n", bn_ok?"IDENTIQUE":"DIFFERENT");
    if(!bn_ok) for(int i=0;i<5;i++) printf("  limbe %d MULX=%016llx ref=%016llx%s\n",i,(unsigned long long)out[i],(unsigned long long)ref[i],out[i]!=ref[i]?" <--":"");
    printf((mul_ok&&mulx_ok&&bn_ok)?"=> bignum OK (RSA/EC devrait marcher)\n":"=> BIGNUM CASSE = RSA/ECDSA echoue = cause plausible DbD !\n");
    return 0;
}
