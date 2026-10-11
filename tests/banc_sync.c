/* Micro-banc des primitives de synchronisation Win32 (cout unitaire d'un aller-retour wineserver
 * contre la synchro en process de 0103). Compiler :
 *   x86_64 : toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang -O2 -o banc_sync_x64.exe tests/banc_sync.c
 *   arm64  : toolchain/llvm-mingw/bin/aarch64-w64-mingw32-clang -O2 -o banc_sync_a64.exe tests/banc_sync.c
 * Lancer : wine banc_sync_x64.exe [iterations]  -- imprime des microsecondes par operation. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static LARGE_INTEGER freq;
static double us_per_op( LARGE_INTEGER t0, LARGE_INTEGER t1, int n )
{
    return (double)(t1.QuadPart - t0.QuadPart) * 1e6 / freq.QuadPart / n;
}
#define BANC(nom, n, corps) do { LARGE_INTEGER t0, t1; int i_; QueryPerformanceCounter(&t0); \
    for (i_ = 0; i_ < (n); i_++) { corps; } QueryPerformanceCounter(&t1); \
    printf("%-58s %8.2f us\n", nom, us_per_op(t0, t1, (n))); fflush(stdout); } while (0)

struct pingpong { HANDLE a, b; int n; };
static DWORD WINAPI pong( void *arg )
{
    struct pingpong *p = arg;
    int i;
    for (i = 0; i < p->n; i++) { WaitForSingleObject( p->a, INFINITE ); SetEvent( p->b ); }
    return 0;
}
static DWORD WINAPI consommateur( void *arg )
{
    struct pingpong *p = arg;   /* a = semaphore, b = evenement « fini » */
    int i;
    for (i = 0; i < p->n; i++) WaitForSingleObject( p->a, INFINITE );
    SetEvent( p->b );
    return 0;
}

int main( int argc, char **argv )
{
    int n = argc > 1 ? atoi( argv[1] ) : 200000, i;
    HANDLE ev_manual = CreateEventA( NULL, TRUE, TRUE, NULL );
    HANDLE ev_auto   = CreateEventA( NULL, FALSE, FALSE, NULL );
    HANDLE sem       = CreateSemaphoreA( NULL, 0, 1000000, NULL );
    HANDLE mtx       = CreateMutexA( NULL, FALSE, NULL );
    HANDLE pair[2]   = { CreateEventA( NULL, FALSE, FALSE, NULL ), CreateEventA( NULL, FALSE, FALSE, NULL ) };
    HANDLE th;
    struct pingpong pp;
    LONG prev;

    QueryPerformanceFrequency( &freq );
    printf( "banc_sync : %d iterations, %s\n", n,
#ifdef __aarch64__
            "arm64 natif"
#else
            "x86_64 (emule)"
#endif
          );

    BANC( "QueryPerformanceCounter (reference, pas de serveur)", n, { LARGE_INTEGER q; QueryPerformanceCounter( &q ); } );
    BANC( "SetEvent manuel deja signale (aucun waiter)", n, SetEvent( ev_manual ) );
    BANC( "SetEvent auto (aucun waiter) + ResetEvent", n, { SetEvent( ev_auto ); ResetEvent( ev_auto ); } );
    BANC( "WaitForSingleObject manuel signale (retour immediat)", n, WaitForSingleObject( ev_manual, INFINITE ) );
    BANC( "SetEvent auto + WaitForSingleObject (consomme)", n, { SetEvent( ev_auto ); WaitForSingleObject( ev_auto, INFINITE ); } );
    BANC( "WaitForSingleObject auto non signale, timeout 0", n, WaitForSingleObject( ev_auto, 0 ) );
    BANC( "ReleaseSemaphore(1) + WaitForSingleObject", n, { ReleaseSemaphore( sem, 1, &prev ); WaitForSingleObject( sem, INFINITE ); } );
    BANC( "WaitForSingleObject(mutex) + ReleaseMutex", n, { WaitForSingleObject( mtx, INFINITE ); ReleaseMutex( mtx ); } );
    BANC( "WaitForMultipleObjects(2 evts, l'un signale)", n, { SetEvent( pair[1] ); WaitForMultipleObjects( 2, pair, FALSE, INFINITE ); } );
    BANC( "WaitForSingleObjectEx alertable, signale", n, WaitForSingleObjectEx( ev_manual, INFINITE, TRUE ) );

    pp.a = pair[0]; pp.b = pair[1]; pp.n = n / 4;
    th = CreateThread( NULL, 0, pong, &pp, 0, NULL );
    BANC( "ping-pong 2 fils (SetEvent + Wait, x2 par tour)", n / 4, { SetEvent( pair[0] ); WaitForSingleObject( pair[1], INFINITE ); } );
    WaitForSingleObject( th, INFINITE ); CloseHandle( th );

    pp.a = sem; pp.b = pair[1]; pp.n = n;
    ResetEvent( pair[1] );
    th = CreateThread( NULL, 0, consommateur, &pp, 0, NULL );
    BANC( "ReleaseSemaphore vers un consommateur (producteur)", n, ReleaseSemaphore( sem, 1, NULL ) );
    WaitForSingleObject( pair[1], INFINITE );
    WaitForSingleObject( th, INFINITE ); CloseHandle( th );

    /* temoins de semantique */
    {
        DWORD r; LONG c;
        SetEvent( ev_auto ); r = WaitForSingleObject( ev_auto, 0 ); printf( "auto consomme : %s\n", r == WAIT_OBJECT_0 ? "ok" : "ECHEC" );
        r = WaitForSingleObject( ev_auto, 0 ); printf( "auto puis vide : %s\n", r == WAIT_TIMEOUT ? "ok" : "ECHEC" );
        ReleaseSemaphore( sem, 3, &c ); printf( "semaphore prev=%ld : %s\n", c, c == 0 ? "ok" : "ECHEC" );
        r = WaitForMultipleObjects( 1, &sem, TRUE, 0 ); printf( "semaphore wait-all(1) : %s\n", r == WAIT_OBJECT_0 ? "ok" : "ECHEC" );
        ReleaseSemaphore( sem, 1, &c ); printf( "semaphore prev=%ld : %s\n", c, c == 2 ? "ok" : "ECHEC" );
        r = WaitForSingleObject( mtx, 0 ); r = WaitForSingleObject( mtx, 0 ); printf( "mutex recursif : %s\n", r == WAIT_OBJECT_0 ? "ok" : "ECHEC" );
        ReleaseMutex( mtx ); ReleaseMutex( mtx ); printf( "mutex release de trop : %s\n", ReleaseMutex( mtx ) ? "ECHEC" : "ok" );
        for (i = 0; i < 100; i++) { HANDLE e = CreateEventA( NULL, TRUE, FALSE, NULL ); SetEvent( e ); CloseHandle( e ); }
        printf( "100 creations/fermetures : ok\n" );
    }
    return 0;
}
