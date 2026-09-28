/* fnsave/frstor (108 octets) et fxsave/fxrstor (512) : les deux instantanes de
 * l'etat x87 que le CRT de Microsoft utilise. Si l'un d'eux rend un mot de
 * controle faux, le CRT croit des exceptions demasquees et leve. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int mauvais;

int main(void)
{
    __attribute__((aligned(16))) unsigned char fx[512], fx2[512];
    unsigned char sv[108];
    unsigned short cw, cw2;
    unsigned short essais[] = { 0x037f, 0x027f, 0x133f, 0x0362 };
    unsigned i;

    for (i = 0; i < sizeof(essais)/sizeof(essais[0]); i++)
    {
        cw = essais[i];
        __asm__ volatile( "fldcw %0" :: "m"(cw) );
        __asm__ volatile( "fld1" );

        memset( sv, 0xcd, sizeof(sv) );
        __asm__ volatile( "fnsave %0" : "=m"(sv) :: "memory" );   /* remet l'etat a zero */
        if ((sv[0] | (sv[1] << 8)) != cw)
        { printf( "fnsave CW=%04x -> %02x%02x\n", cw, sv[1], sv[0] ); mauvais++; }
        __asm__ volatile( "frstor %0" :: "m"(sv) : "memory" );
        __asm__ volatile( "fnstcw %0" : "=m"(cw2) );
        if (cw2 != cw) { printf( "frstor CW=%04x -> %04x\n", cw, cw2 ); mauvais++; }

        memset( fx, 0xcd, sizeof(fx) );
        __asm__ volatile( "fxsave %0" : "=m"(fx) :: "memory" );
        if ((fx[0] | (fx[1] << 8)) != cw)
        { printf( "fxsave CW=%04x -> %02x%02x\n", cw, fx[1], fx[0] ); mauvais++; }
        printf( "CW %04x : fnsave[0..1]=%02x%02x SW=%02x%02x TW=%02x%02x | fxsave CW=%02x%02x SW=%02x%02x TW=%02x MXCSR=%02x%02x%02x%02x\n",
                cw, sv[1], sv[0], sv[5], sv[4], sv[9], sv[8],
                fx[1], fx[0], fx[3], fx[2], fx[4], fx[27], fx[26], fx[25], fx[24] );

        cw2 = 0x037f; __asm__ volatile( "fldcw %0" :: "m"(cw2) );
        __asm__ volatile( "fxrstor %0" :: "m"(fx) : "memory" );
        __asm__ volatile( "fnstcw %0" : "=m"(cw2) );
        if (cw2 != cw) { printf( "fxrstor CW=%04x -> %04x\n", cw, cw2 ); mauvais++; }

        memset( fx2, 0xcd, sizeof(fx2) );
        __asm__ volatile( "fxsave %0" : "=m"(fx2) :: "memory" );
        if (memcmp( fx, fx2, 32 )) { printf( "fxsave/fxrstor/fxsave : les 32 premiers octets different\n" ); mauvais++; }
        __asm__ volatile( "fnclex\n\t ffree %%st(0)" ::: "memory" );
    }
    cw = 0x037f; __asm__ volatile( "fldcw %0" :: "m"(cw) );
    printf( "i386 fnsave/fxsave : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
