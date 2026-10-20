/* Témoin de surlibération des événements auto (0210) : un événement auto ne doit jamais libérer plus de fils que
 * de SetEvent reçus, et deux SetEvent sans personne en attente ne laissent qu'UNE libération en réserve.
 * Compiler : toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang -O1 -o temoin_surliberation.exe tests/temoin_surliberation.c
 * Lancer   : CIDRE_SYNC_LOCAL=1 wine temoin_surliberation.exe [secondes]
 * Cas :
 *  verrou    8 fils prennent un événement auto comme verrou (Wait, section critique, SetEvent) ; la moitié par
 *            WaitForMultipleObjects { ev, jamais }. Deux fils dans la section = ECHEC.
 *  tue       un fil est tué (TerminateThread) pendant qu'il attend l'événement (seul, puis { ev, jamais }) ; puis 2 SetEvent sans dormeur :
 *            une seule attente à 0 ms doit réussir (un dormeur fantôme compté en ferait passer deux).
 *  servi     un fil attend { ev, autre } et est servi par « autre » ; pendant qu'il sort, 2 SetEvent sur ev :
 *            une seule libération doit rester (répété 2000 fois). Excédent (deux restent) = ECHEC ; manque (aucune
 *            ne reste) = limite connue de 0103, l'attente multiple n'étant pas atomique : informatif seulement. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static HANDLE ev, jamais;
static volatile LONG dans, viol, tours, fin;

static DWORD WINAPI preneur( void *arg )
{
    HANDLE h[2] = { ev, jamais };
    int multi = (int)(INT_PTR)arg & 1;
    while (!fin)
    {
        DWORD r = multi ? WaitForMultipleObjects( 2, h, FALSE, 200 ) : WaitForSingleObject( ev, 200 );
        if (r != WAIT_OBJECT_0) continue;
        if (InterlockedIncrement( &dans ) != 1) InterlockedIncrement( &viol );
        YieldProcessor();
        InterlockedDecrement( &dans );
        InterlockedIncrement( &tours );
        SetEvent( ev );
    }
    return 0;
}

static int cas_verrou( int secondes )
{
    HANDLE f[8];
    int i;
    ev = CreateEventA( NULL, FALSE, TRUE, NULL );
    jamais = CreateEventA( NULL, TRUE, FALSE, NULL );
    dans = viol = tours = fin = 0;
    for (i = 0; i < 8; i++) f[i] = CreateThread( NULL, 0, preneur, (void *)(INT_PTR)i, 0, NULL );
    Sleep( secondes * 1000 );
    fin = 1;
    WaitForMultipleObjects( 8, f, TRUE, 5000 );
    printf( "%-6s verrou : %ld tours, %ld fois deux fils dans la section\n", viol ? "ECHEC" : "ok", tours, viol );
    for (i = 0; i < 8; i++) CloseHandle( f[i] );
    CloseHandle( ev ); CloseHandle( jamais );
    return !viol;
}

static DWORD WINAPI dormeur( void *arg )
{
    HANDLE h[2] = { ev, jamais };
    if (arg) WaitForMultipleObjects( 2, h, FALSE, INFINITE );
    else WaitForSingleObject( ev, INFINITE );
    return 0;
}

static int cas_tue( int multi )
{
    int i, echecs = 0;
    jamais = CreateEventA( NULL, TRUE, FALSE, NULL );
    for (i = 0; i < 50; i++)
    {
        HANDLE f;
        int passes = 0;
        ev = CreateEventA( NULL, FALSE, FALSE, NULL );
        f = CreateThread( NULL, 0, dormeur, (void *)(INT_PTR)multi, 0, NULL );
        Sleep( 20 );
        TerminateThread( f, 9 );
        WaitForSingleObject( f, 2000 );
        CloseHandle( f );
        SetEvent( ev ); SetEvent( ev );
        while (passes < 5 && WaitForSingleObject( ev, 0 ) == WAIT_OBJECT_0) passes++;
        if (passes != 1) echecs++;
        CloseHandle( ev );
    }
    printf( "%-6s tue%s : %d/50 manches avec un nombre de passages different de 1\n", echecs ? "ECHEC" : "ok",
            multi ? " (attente multiple)" : "", echecs );
    CloseHandle( jamais );
    return !echecs;
}

static HANDLE autre, servi_pret;
static DWORD WINAPI servi( void *arg )
{
    HANDLE h[2] = { ev, autre };
    SetEvent( servi_pret );
    return WaitForMultipleObjects( 2, h, FALSE, 2000 );
}

static int cas_servi( void )
{
    int i, exces = 0, manques = 0;
    for (i = 0; i < 2000; i++)
    {
        HANDLE f;
        int passes = 0;
        DWORD r;
        ev = CreateEventA( NULL, FALSE, FALSE, NULL );
        autre = CreateEventA( NULL, FALSE, FALSE, NULL );
        servi_pret = CreateEventA( NULL, TRUE, FALSE, NULL );
        f = CreateThread( NULL, 0, servi, NULL, 0, NULL );
        WaitForSingleObject( servi_pret, 2000 );
        Sleep( i % 3 );
        SetEvent( autre );                 /* le fil est servi par « autre »... */
        SetEvent( ev ); SetEvent( ev );    /* ...et ev reçoit deux SetEvent pendant qu'il sort */
        WaitForSingleObject( f, 3000 );
        GetExitCodeThread( f, &r );
        while (passes < 5 && WaitForSingleObject( ev, 0 ) == WAIT_OBJECT_0) passes++;
        /* attendu : exactement UNE libération reste. Le fil a pris « autre » (r == 1) : les deux SetEvent sans dormeur
         * n'en laissent qu'une ; ou il a pris ev (r == 0) : le second SetEvent en laisse une. */
        if (passes > 1) exces++;
        if (passes == 0) manques++;
        CloseHandle( f ); CloseHandle( ev ); CloseHandle( autre ); CloseHandle( servi_pret );
    }
    /* informatif : l'attente multiple de 0103 n'est pas atomique (le fil reveille par « autre » peut prendre ev s'il
     * le trouve signale en repassant), d'ou des « manques » deja sans 0210 ; seuls les excedents comptent au verdict */
    printf( "%-6s servi : %d excedents, %d manques (informatif : attente multiple non atomique) sur 2000\n",
            exces ? "ECHEC" : "ok", exces, manques );
    return !exces;
}

int main( int argc, char **argv )
{
    int s = argc > 1 ? atoi( argv[1] ) : 10, ok = 1;
    ok &= cas_verrou( s );
    ok &= cas_tue( 0 );
    ok &= cas_tue( 1 );
    ok &= cas_servi();
    printf( "bilan -> %s\n", ok ? "ok" : "ECHEC" );
    return ok ? 0 : 1;
}
