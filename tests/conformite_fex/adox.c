#include <windows.h>
#include <stdio.h>
#include <stdint.h>
int main(void){
    /* ADOX isolé : propage la retenue via OF (indépendante de CF) */
    uint64_t s0=9,s1=9;
    __asm__ volatile(
      "xorq %%rax,%%rax\n\t"          /* CF=0, OF=0 */
      "movq $-1,%%r8\n\t" "movq $1,%%r9\n\t"
      "adoxq %%r9,%%r8\n\t"           /* r8=0, OF=1 */
      "movq $0,%%r10\n\t" "movq $0,%%r11\n\t"
      "adoxq %%r11,%%r10\n\t"         /* r10 = 0+0+OF = 1 si ADOX marche */
      "movq %%r8,%0\n\t" "movq %%r10,%1\n\t"
      : "=r"(s0),"=r"(s1) : : "rax","r8","r9","r10","r11","cc");
    int adox_ok=(s0==0 && s1==1);
    printf("ADOX : somme=%llu retenue_propagee=%llu  %s\n",(unsigned long long)s0,(unsigned long long)s1, adox_ok?"OK":"FAUX");

    /* Deux chaînes entrelacées ADCX(CF) + ADOX(OF) simultanées (motif OpenSSL mulx) */
    uint64_t c0=9,c1=9,o0=9,o1=9;
    __asm__ volatile(
      "xorq %%rax,%%rax\n\t"
      "movq $-1,%%r8\n\t"  "movq $-1,%%r12\n\t"
      "movq $1,%%r9\n\t"
      "adcxq %%r9,%%r8\n\t"           /* CF chain: r8=0, CF=1 */
      "adoxq %%r9,%%r12\n\t"          /* OF chain: r12=0, OF=1 */
      "movq $5,%%r10\n\t" "movq $7,%%r13\n\t"
      "movq $0,%%r11\n\t"
      "adcxq %%r11,%%r10\n\t"         /* r10 = 5 + CF(1) = 6 */
      "adoxq %%r11,%%r13\n\t"         /* r13 = 7 + OF(1) = 8 */
      "movq %%r8,%0\n\t""movq %%r10,%1\n\t""movq %%r12,%2\n\t""movq %%r13,%3\n\t"
      : "=r"(c0),"=r"(c1),"=r"(o0),"=r"(o1) : : "rax","r8","r9","r10","r11","r12","r13","cc");
    int dual_ok=(c0==0 && c1==6 && o0==0 && o1==8);
    printf("ADCX+ADOX entrelacés : CF[%llu,%llu] OF[%llu,%llu]  attendu CF[0,6] OF[0,8]  %s\n",
        (unsigned long long)c0,(unsigned long long)c1,(unsigned long long)o0,(unsigned long long)o1, dual_ok?"OK":"FAUX");
    printf((adox_ok&&dual_ok)?"=> ADOX et double chaîne OK : bignum complet correct, RSA/EC marche\n":"=> ADOX/double-chaîne CASSE sous FEX = RSA/ECDSA echoue = CAUSE DbD !!!\n");
    return 0;
}
