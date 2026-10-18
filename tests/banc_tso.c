/* Banc du TSO de FEX par module (patch 0179). Compile en x86-64 et lance sous
 * Wine arm64ec : une boucle a fort trafic memoire (lectures et ecritures d'un
 * tableau), chronometree par QPC. Le binaire est compile par llvm-mingw, sans
 * metadonnee volatile MSVC : FEX y applique son reglage global sauf exemption.
 *
 *   banc_tso.exe [tours, 30000 par defaut]
 *
 * Mesure du 2026-10-18 (M1 Max, 30000 tours, 3 passes entrelacees) :
 *   TSO                                               787 ms
 *   FEX_TSOENABLED=0                                  299 ms
 *   FEX_EXTENDEDVOLATILEMETADATA=banc_tso.exe, sans 0179  786 ms (sans effet)
 *   idem avec 0179                                    299 ms
 *   idem, plage hors de la boucle (banc_tso.exe;100000-100010)  786 ms
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <windows.h>

#define N 4096
static volatile uint32_t tab[N];

int main( int argc, char **argv )
{
    unsigned tours = argc > 1 ? (unsigned)atoi( argv[1] ) : 30000;
    LARGE_INTEGER f, a, b;
    uint64_t somme = 0;
    unsigned t, i;

    QueryPerformanceFrequency( &f );
    for (i = 0; i < N; i++) tab[i] = i * 2654435761u;
    QueryPerformanceCounter( &a );
    for (t = 0; t < tours; t++)
        for (i = 1; i < N; i++)
        {
            uint32_t v = tab[i] + tab[i - 1];
            tab[i] = v ^ t;
            somme += v;
        }
    QueryPerformanceCounter( &b );
    printf( "boucle : %u x %u en %.1f ms (somme %llx)\n", tours, N,
            (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart, (unsigned long long)somme );
    return 0;
}
