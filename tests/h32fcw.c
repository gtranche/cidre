/* UnityPlayer leve STATUS_FLOAT_UNDERFLOW par le filtre IEEE du CRT, qui ne
 * leve que si l'exception est *demasquee*. On verifie donc que le mot de
 * controle x87 et le MXCSR font l'aller-retour, et qu'un depassement par le
 * bas masque ne fait que poser son drapeau. */
#include <windows.h>
#include <stdio.h>
#include <float.h>

static unsigned short lire_cw( void ) { unsigned short c; __asm__ volatile("fnstcw %0":"=m"(c)); return c; }
static void ecrire_cw( unsigned short c ) { __asm__ volatile("fldcw %0"::"m"(c)); }
static unsigned short lire_sw( void ) { unsigned short s; __asm__ volatile("fnstsw %0":"=m"(s)); return s; }
static unsigned lire_mxcsr( void ) { unsigned m; __asm__ volatile("stmxcsr %0":"=m"(m)); return m; }
static void ecrire_mxcsr( unsigned m ) { __asm__ volatile("ldmxcsr %0"::"m"(m)); }

int main(void)
{
    unsigned short cw0 = lire_cw(), cw;
    unsigned m0 = lire_mxcsr(), m;
    volatile double a = 1e-300, b = 1e-300, r;
    int mauvais = 0;
    unsigned i;
    static const unsigned short essais[] = { 0x037f, 0x027f, 0x137f, 0x036f, 0x0362 };

    printf( "CW au depart = %04x, MXCSR au depart = %08x\n", cw0, m0 );
    if ((cw0 & 0x3f) != 0x3f) { printf( "  -> des exceptions sont DEMASQUEES au depart\n" ); mauvais++; }

    for (i = 0; i < sizeof(essais)/sizeof(essais[0]); i++)
    {
        ecrire_cw( essais[i] );
        cw = lire_cw();
        if (cw != essais[i]) { printf( "fldcw %04x -> fnstcw %04x\n", essais[i], cw ); mauvais++; }
    }
    ecrire_cw( cw0 );

    for (i = 0; i < 4; i++)
    {
        unsigned v = 0x1f80 ^ (i ? (0x80 << (i - 1)) : 0);
        ecrire_mxcsr( v );
        m = lire_mxcsr();
        if (m != v) { printf( "ldmxcsr %08x -> stmxcsr %08x\n", v, m ); mauvais++; }
    }
    ecrire_mxcsr( m0 );

    /* Depassement par le bas, masque : doit rendre un denormal ou zero et
     * poser le drapeau UE (0x10), sans exception. */
    __asm__ volatile("fnclex");
    r = a * b;
    printf( "1e-300*1e-300 = %g, SW = %04x (UE=%d PE=%d), MXCSR = %08x\n",
            r, lire_sw(), (lire_sw() >> 4) & 1, (lire_sw() >> 5) & 1, lire_mxcsr() );

    printf( "i386 mot de controle : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
