/* Le CRT d'Unity sauvegarde par « fstcw » le mot de controle de l'appelant a
 * l'entree de atan2, et c'est celui-la qui dit sous-depassement demasque. Donc
 * le mot etait deja faux *avant* l'appel.
 *
 * Un mot de controle doit survivre a tout : un appel systeme, un rappel, et
 * surtout une exception rattrapee -- chaque exception fait un aller-retour
 * complet du contexte a travers wow64 et l'emulateur. */
#include <windows.h>
#include <stdio.h>

static int mauvais, poubelle;

static unsigned short lire_cw( void ) { unsigned short c; __asm__ volatile("fnstcw %0":"=m"(c)); return c; }
static void ecrire_cw( unsigned short c ) { __asm__ volatile("fldcw %0"::"m"(c)); }

static LONG CALLBACK rattraper( EXCEPTION_POINTERS *ep )
{
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    ep->ContextRecord->Eax = (DWORD)(ULONG_PTR)&poubelle;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static void verifier( const char *quoi, unsigned short attendu )
{
    unsigned short c = lire_cw();
    if (c != attendu) { printf( "apres %-28s CW = %04x (attendu %04x)\n", quoi, c, attendu ); mauvais++; }
}

int main(void)
{
    unsigned short cw = 0x027f;
    char nom[64];
    HANDLE ev;

    AddVectoredExceptionHandler( 1, rattraper );

    ecrire_cw( cw );                 verifier( "fldcw", cw );

    /* Un appel systeme ordinaire. */
    GetModuleFileNameA( NULL, nom, sizeof(nom) );
    verifier( "GetModuleFileName", cw );

    ev = CreateEventW( NULL, TRUE, FALSE, NULL );
    WaitForSingleObject( ev, 0 );
    verifier( "WaitForSingleObject", cw );
    CloseHandle( ev );

    /* Une exception rattrapee, qui reprend : le contexte fait l'aller-retour. */
    __asm__ volatile( "xorl %%eax, %%eax\n\t movl $7, (%%eax)" ::: "eax", "memory" );
    verifier( "exception rattrapee", cw );

    /* Une deuxieme, avec un autre mot de controle. */
    cw = 0x133f; ecrire_cw( cw );    verifier( "fldcw 133f", cw );
    __asm__ volatile( "xorl %%eax, %%eax\n\t movl $7, (%%eax)" ::: "eax", "memory" );
    verifier( "exception rattrapee (133f)", cw );

    /* Et une trace de debogage, qui passe aussi par une exception. */
    OutputDebugStringA( "sonde\n" );
    verifier( "OutputDebugString", cw );

    ecrire_cw( 0x037f );
    printf( "i386 CW a travers les exceptions : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
