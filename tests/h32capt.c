/* RtlCaptureContext ne sauvegarde PAS l'etat x87 : elle rend
 * ContextFlags = CONTEXT_i386|CONTROL|INTEGER|SEGMENTS et laisse FloatSave et
 * ExtendedRegisters tels quels. C'est le contrat de Windows, et c'est pour
 * cela que NtContinue doit respecter ContextFlags -- sinon il restaure de la
 * pile non initialisee dans le processeur de l'invite. */
#include <windows.h>
#include <stdio.h>
static unsigned short lire( void ) { unsigned short c; __asm__ volatile("fnstcw %0":"=m"(c)); return c; }
static void ecrire( unsigned short c ) { __asm__ volatile("fldcw %0"::"m"(c)); }

int main(void)
{
    CONTEXT ctx;
    int mauvais = 0;
    unsigned short cws[] = { 0x037f, 0x133f, 0x027f };
    unsigned i;

    for (i = 0; i < 3; i++)
    {
        ecrire( cws[i] );
        memset( &ctx, 0xcd, sizeof(ctx) );
        ctx.ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT | CONTEXT_EXTENDED_REGISTERS;
        RtlCaptureContext( &ctx );
        printf( "CW %04x : capture flags=%08lx FloatSave.CW=%08lx Extended[0]=%04x\n",
                cws[i], ctx.ContextFlags, ctx.FloatSave.ControlWord,
                *(unsigned short *)ctx.ExtendedRegisters );
        /* Ce qu'on verifie : les drapeaux annonces, et le fait que la zone
         * x87 n'a pas ete touchee (elle porte encore notre 0xcd). */
        if (ctx.ContextFlags != (CONTEXT_i386 | CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_SEGMENTS)) mauvais++;
        if (ctx.FloatSave.ControlWord != 0xcdcdcdcd) mauvais++;
        fflush( stdout );
    }
    ecrire( 0x037f );
    printf( "i386 RtlCaptureContext : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
