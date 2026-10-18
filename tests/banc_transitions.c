/* Banc des transitions x86-64 -> arm64ec (essai 0180, abandonne). Compile en x86-64 et
 * lance sous Wine arm64ec : chaque appel a une fonction de kernelbase/ntdll,
 * qui sont en arm64ec natif, sort du JIT de FEX (ExitFunctionEC) puis y
 * revient (check_target_ec). On chronometre N appels de deux fonctions
 * triviales et on donne le cout par aller-retour.
 *
 *   banc_transitions.exe [appels, 10000000 par defaut] [passes, 5]
 *
 * Mesure du 2026-10-18 (M1 Max, 10^7 appels x 3 x 4 passes entrelacees) :
 * GetLastError 7,6 ns, QueryPerformanceCounter 40,7-41,0 ns par aller-retour,
 * avec ou sans l'essai 0180 (ExitFunctionEC n'ecrit FPCR que si AH ou NEP est
 * pose) : aucun ecart, essai abandonne.
 */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

static double ms( LARGE_INTEGER a, LARGE_INTEGER b, LARGE_INTEGER f )
{
    return (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
}

int main( int argc, char **argv )
{
    long n = argc > 1 ? atol( argv[1] ) : 10000000;
    int passes = argc > 2 ? atoi( argv[2] ) : 5;
    LARGE_INTEGER f, a, b, q;
    DWORD (WINAPI *p_GetLastError)(void);
    BOOL (WINAPI *p_QPC)(LARGE_INTEGER *);
    volatile DWORD puits = 0;
    long i;
    int p;

    /* Par pointeur, pour que le compilateur ne puisse rien replier. */
    p_GetLastError = (void *)GetProcAddress( GetModuleHandleA( "kernelbase.dll" ), "GetLastError" );
    p_QPC = (void *)GetProcAddress( GetModuleHandleA( "kernelbase.dll" ), "QueryPerformanceCounter" );
    if (!p_GetLastError || !p_QPC) { printf( "kernelbase introuvable\n" ); return 1; }
    QueryPerformanceFrequency( &f );

    for (p = 0; p < passes; p++)
    {
        QueryPerformanceCounter( &a );
        for (i = 0; i < n; i++) puits += p_GetLastError();
        QueryPerformanceCounter( &b );
        printf( "passe %d GetLastError : %ld appels en %.1f ms = %.1f ns\n", p, n, ms( a, b, f ), ms( a, b, f ) * 1e6 / n );
        QueryPerformanceCounter( &a );
        for (i = 0; i < n; i++) { p_QPC( &q ); puits += q.LowPart; }
        QueryPerformanceCounter( &b );
        printf( "passe %d QPC          : %ld appels en %.1f ms = %.1f ns\n", p, n, ms( a, b, f ), ms( a, b, f ) * 1e6 / n );
    }
    return puits == 12345 ? 2 : 0;
}
