/*
 * Invite i386 : les operations verrouillees non alignees sont-elles atomiques ?
 *
 * Sur x86 un « lock » tient meme a cheval sur deux lignes de cache ; sur ARM64
 * il n'existe rien d'equivalent, et FEX rattrape ces acces par une faute --
 * mille cent soixante-six par execution de DREDGE. Si le rattrapage perd
 * l'atomicite, un verrou peut se defaire, et le symptome est un dormeur que
 * personne ne reveille.
 *
 * On compte : huit fils, cent mille increments chacun. Le total doit tomber
 * juste, aligne comme non aligne.
 */
#include <windows.h>
#include <stdio.h>

#define FILS   8
#define TOURS  100000

static char zone[64];
static LONG *cible32;
static LONGLONG *cible64;
static volatile LONG erreurs_cas;

static DWORD WINAPI incrementer( void *p )
{
    LONG i;
    for (i = 0; i < TOURS; i++) InterlockedIncrement( cible32 );
    return 0;
}

static DWORD WINAPI echanger( void *p )
{
    LONG i;
    for (i = 0; i < TOURS; i++)
    {
        LONG ancien, neuf;
        do { ancien = *cible32; neuf = ancien + 1; }
        while (InterlockedCompareExchange( cible32, neuf, ancien ) != ancien);
    }
    return 0;
}

static DWORD WINAPI incrementer64( void *p )
{
    LONG i;
    for (i = 0; i < TOURS; i++)
    {
        LONGLONG ancien, neuf;
        do { ancien = *cible64; neuf = ancien + 1; }
        while (InterlockedCompareExchange64( cible64, neuf, ancien ) != ancien);
    }
    return 0;
}

static LONG lancer( LPTHREAD_START_ROUTINE f )
{
    HANDLE h[FILS];
    int i;
    for (i = 0; i < FILS; i++) h[i] = CreateThread( NULL, 0, f, NULL, 0, NULL );
    for (i = 0; i < FILS; i++) { WaitForSingleObject( h[i], INFINITE ); CloseHandle( h[i] ); }
    return 0;
}

static int epreuve32( const char *quoi, int decalage, LPTHREAD_START_ROUTINE f )
{
    LONG attendu = FILS * TOURS, vu;

    cible32 = (LONG *)(zone + decalage);
    *cible32 = 0;
    lancer( f );
    vu = *cible32;
    printf( "%-34s decalage %d : %ld / %ld%s\n", quoi, decalage, vu, attendu,
            vu == attendu ? "  ok" : "  ECART" );
    fflush( stdout );
    return vu != attendu;
}

static int epreuve64( const char *quoi, int decalage )
{
    LONGLONG attendu = (LONGLONG)FILS * TOURS, vu;

    cible64 = (LONGLONG *)(zone + decalage);
    *cible64 = 0;
    lancer( incrementer64 );
    vu = *cible64;
    printf( "%-34s decalage %d : %lld / %lld%s\n", quoi, decalage, vu, attendu,
            vu == attendu ? "  ok" : "  ECART" );
    fflush( stdout );
    return vu != attendu;
}

int main(void)
{
    int mauvais = 0;

    /* Aligne d'abord : si celui-la echoue, ce n'est pas l'alignement. */
    mauvais += epreuve32( "increment aligne", 0, incrementer );
    mauvais += epreuve32( "increment non aligne", 1, incrementer );
    mauvais += epreuve32( "increment a cheval sur 4", 2, incrementer );
    mauvais += epreuve32( "cmpxchg aligne", 0, echanger );
    mauvais += epreuve32( "cmpxchg non aligne", 1, echanger );
    mauvais += epreuve32( "cmpxchg a cheval sur 4", 3, echanger );
    mauvais += epreuve64( "cmpxchg8b aligne", 0 );
    mauvais += epreuve64( "cmpxchg8b non aligne", 1 );
    mauvais += epreuve64( "cmpxchg8b a cheval sur 8", 6 );

    printf( "i386 atomiques : %s (%d ecarts)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return mauvais ? 1 : 0;
}
