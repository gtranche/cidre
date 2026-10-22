/* Temoin de l'ordre memoire x86 (TSO) sous FEX, pour les lectures rendues nues par dependance d'adresse
 * (CIDRE_TSO_DEP=1, Cidre 0225). Un fil ecrit, dans cet ordre, donnee = i, puis les valeurs publiees (slot[k] = i,
 * drapeau = i, pdrapeau = &slot[k], pp = &pslot[k]) ; les lecteurs lisent une valeur publiee, une lecture qui en
 * depend, puis donnee : sous TSO, donnee >= valeur publiee toujours. La premiere lecture est celle que 0225 rend nue.
 *
 *   D1  pointeur puis champ : p = pdrapeau ; f = *p ; d = donnee
 *   D2  chaine de trois : q = pp ; p = *q ; f = *p ; d = donnee (deux lectures nues)
 *   D3  index calcule : f = drapeau ; x = tab[f & masque] (and, puis index du SIB) ; d = donnee
 *   D4  temoin negatif : f = drapeau ; d = donnee, sans dependance (doit rester ordonne : 0 attendu)
 *   B   banc mono-fil : chaine D2 en boucle, ms (la chaine nue doit aller plus vite)
 *
 * Toutes les inversions doivent valoir 0 sous TSO exact ; sans TSO (FEX_TSOENABLED=0), D1-D4 en comptent
 * (sensibilite du temoin).
 * x86_64-w64-mingw32-clang -O2 h64tso_dep.c -o h64tso_dep.exe ; code de sortie 0 si D1-D4 passent. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

#define MASQUE ((1u << 16) - 1)
static volatile uint64_t donnee, drapeau;
static volatile uint64_t *volatile pdrapeau;
static volatile uint64_t *volatile *volatile pp;
static volatile uint64_t slot[MASQUE + 1];
static volatile uint64_t *volatile pslot[MASQUE + 1];
static uint64_t tab[MASQUE + 1];
static volatile LONG fin;

static DWORD WINAPI ecrivain( void *p )
{
    uint64_t i = 1;
    while (!fin)
    {
        uint32_t k = i & MASQUE;
        donnee = i;
        slot[k] = i;
        pslot[k] = &slot[k];
        drapeau = i;
        pdrapeau = &slot[k];
        pp = &pslot[k];
        i++;
    }
    return 0;
}

static uint64_t __attribute__((noinline)) d1( uint64_t tours )
{
    uint64_t inversions = 0;
    for (uint64_t n = 0; n < tours; n++)
    {
        uint64_t p, f, d;
        __asm__ volatile( "movq %3, %0\n\tmovq (%0), %1\n\tmovq %4, %2"
                          : "=&r"(p), "=&r"(f), "=&r"(d) : "m"(pdrapeau), "m"(donnee) : "memory" );
        inversions += d < f;
    }
    return inversions;
}

static uint64_t __attribute__((noinline)) d2( uint64_t tours )
{
    uint64_t inversions = 0;
    for (uint64_t n = 0; n < tours; n++)
    {
        uint64_t q, f, d;
        __asm__ volatile( "movq %3, %0\n\tmovq (%0), %0\n\tmovq (%0), %1\n\tmovq %4, %2"
                          : "=&r"(q), "=&r"(f), "=&r"(d) : "m"(pp), "m"(donnee) : "memory" );
        inversions += d < f;
    }
    return inversions;
}

static uint64_t __attribute__((noinline)) d3( uint64_t tours )
{
    uint64_t inversions = 0;
    for (uint64_t n = 0; n < tours; n++)
    {
        uint64_t f, x, d;
        __asm__ volatile( "movq %3, %0\n\tmovl %k0, %k1\n\tandl %6, %k1\n\tmovq (%5,%1,8), %1\n\tmovq %4, %2"
                          : "=&r"(f), "=&r"(x), "=&r"(d) : "m"(drapeau), "m"(donnee), "r"(tab), "i"(MASQUE)
                          : "memory", "cc" );
        inversions += d < f;
    }
    return inversions;
}

static uint64_t __attribute__((noinline)) d4( uint64_t tours )
{
    uint64_t inversions = 0;
    for (uint64_t n = 0; n < tours; n++)
    {
        uint64_t f, d;
        __asm__ volatile( "movq %2, %0\n\tmovq %3, %1" : "=&r"(f), "=&r"(d) : "m"(drapeau), "m"(donnee) : "memory" );
        inversions += d < f;
    }
    return inversions;
}

static double banc( uint64_t tours )
{
    LARGE_INTEGER f, a, b;
    uint64_t s = 0;
    QueryPerformanceFrequency( &f );
    QueryPerformanceCounter( &a );
    for (uint64_t n = 0; n < tours; n++)
    {
        uint64_t q;
        __asm__ volatile( "movq %1, %0\n\tmovq (%0), %0\n\tmovq (%0), %0" : "=&r"(q) : "m"(pp) : "memory" );
        s += q;
    }
    QueryPerformanceCounter( &b );
    if (s == 1) printf( "!" );
    return (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
}

int main( int argc, char **argv )
{
    const uint64_t tours = argc > 1 ? _strtoui64( argv[1], NULL, 10 ) : 50000000;
    int echecs = 0;
    for (uint32_t k = 0; k <= MASQUE; k++) { pslot[k] = &slot[k]; tab[k] = k; }
    pdrapeau = &slot[0];
    pp = &pslot[0];

    printf( "B   chaine nue, mono-fil : %.1f ms pour 100000000 tours\n", banc( 100000000 ) );

    HANDLE h = CreateThread( NULL, 0, ecrivain, NULL, 0, NULL );
    Sleep( 50 );
    uint64_t i1 = d1( tours ), i2 = d2( tours ), i3 = d3( tours ), i4 = d4( tours );
    fin = 1;
    WaitForSingleObject( h, INFINITE );
    printf( "%s D1 pointeur puis champ : %llu inversion(s) sur %llu\n", i1 ? "ECHEC" : "OK   ", (unsigned long long)i1, (unsigned long long)tours );
    printf( "%s D2 chaine de trois : %llu inversion(s) sur %llu\n", i2 ? "ECHEC" : "OK   ", (unsigned long long)i2, (unsigned long long)tours );
    printf( "%s D3 index calcule : %llu inversion(s) sur %llu\n", i3 ? "ECHEC" : "OK   ", (unsigned long long)i3, (unsigned long long)tours );
    printf( "%s D4 sans dependance : %llu inversion(s) sur %llu\n", i4 ? "ECHEC" : "OK   ", (unsigned long long)i4, (unsigned long long)tours );
    echecs = (i1 != 0) + (i2 != 0) + (i3 != 0) + (i4 != 0);
    printf( "%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs );
    return echecs;
}
