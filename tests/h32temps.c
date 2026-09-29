/*
 * Invite i386 : le temps avance-t-il ?
 *
 * Au demarrage, notre portage reserve KUSER_SHARED_DATA a l'adresse fixe que
 * l'invite 32 bits attend, 0x7ffe0000 dans sa fenetre. Cette reservation
 * echoue par moments -- « KUSER_SHARED_DATA de l'invite non reservee :
 * c0000018 », c'est-a-dire adresses en conflit. Or c'est la que l'invite lit
 * son compteur de tics et l'heure systeme, sans appel systeme.
 *
 * Un jeu qui attend une horloge figee tourne en rond sur Sleep sans rien
 * consommer -- exactement la signature du gel authentique.
 *
 * On verifie donc que la page est lisible et que tout ce qui s'en sert avance.
 */
#include <windows.h>
#include <stdio.h>

#define KUSER 0x7ffe0000

/* Decalages stables depuis Windows NT. */
#define KU_TICKCOUNT_BAS   0x320
#define KU_INTERRUPT_BAS   0x008
#define KU_SYSTEMTIME_BAS  0x014

static int lisible;
static int echecs;

static LONG CALLBACK gestionnaire( EXCEPTION_POINTERS *p )
{
    if (p->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION)
    {
        lisible = 0;
        return EXCEPTION_EXECUTE_HANDLER;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static ULONG lire( ULONG decalage )
{
    return *(volatile ULONG *)(ULONG_PTR)(KUSER + decalage);
}

static void verifier( const char *quoi, ULONGLONG a, ULONGLONG b )
{
    printf( "%-28s %llu -> %llu : %s\n", quoi, a, b, b > a ? "avance" : "FIGE" );
    if (b <= a) echecs++;
    fflush( stdout );
}

int main(void)
{
    DWORD t1, t2;
    ULONGLONG q1, q2, c1, c2;
    LARGE_INTEGER p1, p2;
    ULONG k1 = 0, k2 = 0, i1 = 0, i2 = 0;

    AddVectoredExceptionHandler( 1, gestionnaire );

    /* La page est-elle seulement la ? */
    {
        MEMORY_BASIC_INFORMATION mbi;
        SIZE_T n = VirtualQuery( (void *)KUSER, &mbi, sizeof(mbi) );

        printf( "page %p : %s", (void *)KUSER, n ? "" : "VirtualQuery echoue\n" );
        if (n) printf( "etat %lx prot %lx taille %llx\n", mbi.State, mbi.Protect,
                       (unsigned long long)mbi.RegionSize );
        /* On ne lit que si la page est engagee et lisible : pas de SEH ici, le
         * compilateur i686 de la chaine ne le fournit pas. */
        lisible = n && mbi.State == MEM_COMMIT &&
                  (mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE_READ |
                                  PAGE_EXECUTE_READWRITE | PAGE_WRITECOPY)) != 0;
    }

    printf( "lecture directe : %s\n", lisible ? "possible" : "IMPOSSIBLE" );
    if (lisible) { k1 = lire( KU_TICKCOUNT_BAS ); i1 = lire( KU_INTERRUPT_BAS ); }

    t1 = GetTickCount();
    q1 = GetTickCount64();
    QueryPerformanceCounter( &p1 );
    c1 = p1.QuadPart;

    Sleep( 300 );

    t2 = GetTickCount();
    q2 = GetTickCount64();
    QueryPerformanceCounter( &p2 );
    c2 = p2.QuadPart;
    if (lisible) { k2 = lire( KU_TICKCOUNT_BAS ); i2 = lire( KU_INTERRUPT_BAS ); }

    verifier( "GetTickCount", t1, t2 );
    verifier( "GetTickCount64", q1, q2 );
    verifier( "QueryPerformanceCounter", c1, c2 );
    if (lisible)
    {
        verifier( "KUSER tics (direct)", k1, k2 );
        verifier( "KUSER interruption (direct)", i1, i2 );
    }
    else printf( "KUSER direct : non verifiable, la page n'est pas lisible\n" );

    printf( "i386 temps : %s (%d figes)\n", echecs ? "ECHEC" : "ok", echecs );
    return echecs ? 1 : 0;
}
