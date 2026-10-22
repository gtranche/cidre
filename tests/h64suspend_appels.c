/* Temoin de suspension d'un fil qui ne fait que des appels et des retours (FEX : sonnette de suspension retiree des
 * blocs de retour d'appel, CIDRE_SONNETTE_RETOUR). Un fil calcule fib recursivement sans fin ; le fil principal le
 * suspend, lit son contexte (RIP) et le reprend, 3000 fois.
 *
 *   S1  3000 suspensions abouties, chacune en moins de 1 s ; latence (SuspendThread + GetThreadContext) moyenne
 *       et maximale
 *   S2  les RIP lus tombent dans fib ou sa boucle (pas dans le vide) : nombre hors de [fib, fin du code]
 *   S3  le calcul reste juste : fib(24) = 46368 a chaque tour du fil
 *
 * x86_64-w64-mingw32-clang -O2 h64suspend_appels.c -o h64suspend_appels.exe
 * Lancement : wine h64suspend_appels.exe ; code de sortie 0 si tout passe. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

static volatile LONG fin, tours, faux;

static uint32_t __attribute__((noinline)) fib( uint32_t n )
{
    return n < 2 ? n : fib( n - 1 ) + fib( n - 2 );
}

static DWORD WINAPI calcul( void *p )
{
    while (!fin)
    {
        if (fib( 24 ) != 46368) InterlockedIncrement( &faux );
        InterlockedIncrement( &tours );
    }
    return 0;
}

int main( void )
{
    int echecs = 0;
    LARGE_INTEGER f, a, b;
    QueryPerformanceFrequency( &f );
    HANDLE h = CreateThread( NULL, 0, calcul, NULL, 0, NULL );
    Sleep( 100 );
    double somme = 0, pire = 0;
    int abouties = 0, lentes = 0, hors = 0;
    for (int i = 0; i < 3000; i++)
    {
        CONTEXT c = { .ContextFlags = CONTEXT_CONTROL };
        QueryPerformanceCounter( &a );
        if (SuspendThread( h ) == (DWORD)-1) break;
        BOOL ok = GetThreadContext( h, &c );
        QueryPerformanceCounter( &b );
        ResumeThread( h );
        if (!ok) break;
        double ms = (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
        somme += ms; if (ms > pire) pire = ms; if (ms > 1000) lentes++;
        abouties++;
        /* fib et calcul sont contigus dans .text (noinline, meme unite) ; un RIP hors du module serait suspect */
        if (c.Rip < (DWORD64)GetModuleHandleA( NULL ) || c.Rip > (DWORD64)GetModuleHandleA( NULL ) + 0x100000) hors++;
        Sleep( 0 );
    }
    fin = 1;
    WaitForSingleObject( h, INFINITE );
    printf( "%s S1 suspensions : %d/3000 abouties, %d > 1 s ; latence moyenne %.3f ms, max %.3f ms\n",
            abouties == 3000 && !lentes ? "OK   " : "ECHEC", abouties, lentes, abouties ? somme / abouties : 0, pire );
    echecs += abouties != 3000 || lentes;
    printf( "%s S2 RIP hors du module : %d\n", hors ? "INFO " : "OK   ", hors );
    printf( "%s S3 fib juste : %ld tours, %ld faux\n", faux ? "ECHEC" : "OK   ", tours, faux );
    echecs += faux != 0;
    printf( "%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs );
    return echecs;
}
