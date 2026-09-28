/* Le CRT de Microsoft relit son mot de controle dans un tampon d'environnement
 * x87. Deux dispositions existent : 14 octets (prefixe 0x66) et 28 octets. Se
 * tromper de l'une pour l'autre fait lire le mot de controle au mauvais
 * endroit -- et le CRT croit alors des exceptions demasquees. */
#include <windows.h>
#include <stdio.h>

static int mauvais;

int main(void)
{
    unsigned char e32[28], e16[14];
    unsigned short cw, cw2;
    unsigned short essais[] = { 0x037f, 0x027f, 0x133f, 0x0362 };
    unsigned i;

    for (i = 0; i < sizeof(essais)/sizeof(essais[0]); i++)
    {
        cw = essais[i];
        __asm__ volatile( "fldcw %0" :: "m"(cw) );

        memset( e32, 0xcd, sizeof(e32) );
        __asm__ volatile( "fnstenv %0" : "=m"(e32) :: "memory" );
        memset( e16, 0xcd, sizeof(e16) );
        __asm__ volatile( ".byte 0x66\n\t fnstenv %0" : "=m"(e16) :: "memory" );

        printf( "CW %04x : env32[0..1]=%02x%02x env32[4..5]=%02x%02x env32[8..9]=%02x%02x | "
                "env16[0..1]=%02x%02x env16[2..3]=%02x%02x env16[4..5]=%02x%02x\n",
                cw, e32[1], e32[0], e32[5], e32[4], e32[9], e32[8],
                e16[1], e16[0], e16[3], e16[2], e16[5], e16[4] );

        if ((e32[0] | (e32[1] << 8)) != cw) { printf( "   -> env 28 octets : CW faux\n" ); mauvais++; }
        if ((e16[0] | (e16[1] << 8)) != cw) { printf( "   -> env 14 octets : CW faux\n" ); mauvais++; }

        /* fldenv doit rendre le mot de controle */
        __asm__ volatile( "fldcw %0" :: "m"(essais[0]) );
        __asm__ volatile( "fldenv %0" :: "m"(e32) : "memory" );
        __asm__ volatile( "fnstcw %0" : "=m"(cw2) );
        if (cw2 != cw) { printf( "   -> fldenv 28 : CW relu %04x\n", cw2 ); mauvais++; }

        __asm__ volatile( "fldcw %0" :: "m"(essais[0]) );
        __asm__ volatile( ".byte 0x66\n\t fldenv %0" :: "m"(e16) : "memory" );
        __asm__ volatile( "fnstcw %0" : "=m"(cw2) );
        if (cw2 != cw) { printf( "   -> fldenv 14 : CW relu %04x\n", cw2 ); mauvais++; }
    }
    cw = 0x037f; __asm__ volatile( "fldcw %0" :: "m"(cw) );
    printf( "i386 environnement x87 : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
