/* Banc des extensions ARM de l'hote vues par FEX (levier 0183). Compile en
 * x86-64, lance sous Wine arm64ec + FEX, A/B par FEX_HOSTFEATURES.
 *
 *   banc_ext.exe <mode> [tours]
 *
 * modes :
 *   drapeaux  additions a retenue en chaine (adc/sbb), comparaisons, setcc/cmov
 *   tri       tri rapide maison + hachage (code entier « ordinaire »)
 *   atom1     lock xadd et lock cmpxchg, un seul fil
 *   atom4     4 fils sur le meme compteur (lock xadd) puis verrou cmpxchg
 *   flottant  cvttss2si/cvttsd2si, roundsd, mulsd/addsd scalaires
 *   tso       structure lue a deplacements (ldapur avec LRCPC2), ecritures
 * Le temps est pris par QPC dans le programme (sans le demarrage).
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <smmintrin.h>

static double ms( LARGE_INTEGER a, LARGE_INTEGER b )
{
    LARGE_INTEGER f;
    QueryPerformanceFrequency( &f );
    return (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
}

/* ---- drapeaux ---- */
#define MOTS 64
static uint64_t __attribute__((noinline)) addition_longue( uint64_t *a, const uint64_t *b )
{
    unsigned long long c = 0;
    int i;
    for (i = 0; i < MOTS; i++)
    {
        unsigned long long r;
        r = __builtin_addcll( a[i], b[i], c, &c );
        a[i] = r;
    }
    return c;
}

static uint64_t __attribute__((noinline)) soustraction_longue( uint64_t *a, const uint64_t *b )
{
    unsigned long long c = 0;
    int i;
    for (i = 0; i < MOTS; i++)
    {
        unsigned long long r;
        r = __builtin_subcll( a[i], b[i], c, &c );
        a[i] = r;
    }
    return c;
}

static uint64_t __attribute__((noinline)) comparaisons( const int32_t *v, int n )
{
    uint64_t s = 0;
    int i;
    for (i = 1; i < n; i++)
    {
        int32_t x = v[i], y = v[i - 1];
        s += (x < y) + 2 * (x == y) + 4 * ((uint32_t)x > (uint32_t)y);
        s += x > y ? x : y;
    }
    return s;
}

static void drapeaux( unsigned tours )
{
    static uint64_t a[MOTS], b[MOTS];
    static int32_t v[4096];
    uint64_t s = 0;
    unsigned t;
    int i;
    for (i = 0; i < MOTS; i++) { a[i] = i * 0x9e3779b97f4a7c15ull; b[i] = ~a[i] + i; }
    for (i = 0; i < 4096; i++) v[i] = (int32_t)(i * 2654435761u);
    for (t = 0; t < tours; t++)
    {
        s += addition_longue( a, b );
        s += soustraction_longue( b, a );
        if (!(t & 7)) s += comparaisons( v, 4096 );
    }
    printf( "somme %llx ", (unsigned long long)(s + a[3] + b[5]) );
}

/* ---- tri ---- */
static void __attribute__((noinline)) tri( uint32_t *t, int g, int d )
{
    while (g < d)
    {
        uint32_t p = t[(g + d) / 2];
        int i = g, j = d;
        while (i <= j)
        {
            while (t[i] < p) i++;
            while (t[j] > p) j--;
            if (i <= j) { uint32_t x = t[i]; t[i] = t[j]; t[j] = x; i++; j--; }
        }
        if (j - g < d - i) { tri( t, g, j ); g = i; }
        else { tri( t, i, d ); d = j; }
    }
}

static uint32_t hacher( const uint8_t *p, size_t n )
{
    uint32_t h = 2166136261u;
    while (n--) { h ^= *p++; h *= 16777619u; }
    return h;
}

static void trier( unsigned tours )
{
    static uint32_t t[65536];
    uint32_t h = 0, x = 1;
    unsigned k;
    int i;
    for (k = 0; k < tours; k++)
    {
        for (i = 0; i < 65536; i++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; t[i] = x; }
        tri( t, 0, 65535 );
        h ^= hacher( (const uint8_t *)t, sizeof(t) );
    }
    printf( "somme %x ", h );
}

/* ---- atomiques ---- */
static volatile LONG64 compteur;
static volatile LONG verrou;
static LONG64 protege;
static unsigned tours_fil;

static void prendre( void ) { while (InterlockedCompareExchange( &verrou, 1, 0 )) YieldProcessor(); }
static void rendre( void ) { InterlockedExchange( &verrou, 0 ); }

static DWORD WINAPI fil_xadd( void *arg )
{
    unsigned i;
    for (i = 0; i < tours_fil; i++) InterlockedExchangeAdd64( &compteur, 1 );
    return 0;
}

static DWORD WINAPI fil_verrou( void *arg )
{
    unsigned i;
    for (i = 0; i < tours_fil; i++) { prendre(); protege++; rendre(); }
    return 0;
}

static double lancer_fils( LPTHREAD_START_ROUTINE f, int n )
{
    HANDLE h[8];
    LARGE_INTEGER a, b;
    int i;
    QueryPerformanceCounter( &a );
    for (i = 0; i < n; i++) h[i] = CreateThread( NULL, 0, f, NULL, 0, NULL );
    WaitForMultipleObjects( n, h, TRUE, INFINITE );
    QueryPerformanceCounter( &b );
    for (i = 0; i < n; i++) CloseHandle( h[i] );
    return ms( a, b );
}

static void atomiques( unsigned tours, int fils )
{
    double x, v;
    tours_fil = tours;
    compteur = 0; protege = 0;
    x = lancer_fils( fil_xadd, fils );
    v = lancer_fils( fil_verrou, fils );
    printf( "xadd %.1f ms, verrou %.1f ms (%lld %lld) ", x, v, (long long)compteur, (long long)protege );
}

/* ---- flottant ---- */
static void flottant( unsigned tours )
{
    double s = 0, x = 0.5;
    int64_t e = 0;
    unsigned t;
    for (t = 0; t < tours; t++)
    {
        float f = (float)(x * 1000.0);
        e += _mm_cvttss_si32( _mm_set_ss( f ) );
        e += _mm_cvttsd_si64( _mm_set_sd( x * 1e6 ) );
        s += _mm_cvtsd_f64( _mm_round_sd( _mm_setzero_pd(), _mm_set_sd( x * 3.7 ), _MM_FROUND_TO_NEAREST_INT | _MM_FROUND_NO_EXC ) );
        x = x * 1.0000001 + 1e-9;
        if (x > 1000.0) x = 0.5;
    }
    printf( "somme %g %lld ", s, (long long)e );
}

/* ---- tso ---- */
struct objet { uint32_t a, b, c, d; uint64_t e, f; };
static volatile struct objet objets[2048];

static void tso( unsigned tours )
{
    uint64_t s = 0;
    unsigned t;
    int i;
    for (i = 0; i < 2048; i++) { objets[i].a = i; objets[i].b = i * 3; objets[i].c = i ^ 5; objets[i].d = 7; objets[i].e = i; objets[i].f = 1; }
    for (t = 0; t < tours; t++)
        for (i = 0; i < 2048; i++)
        {
            uint64_t v = objets[i].a + objets[i].b + objets[i].c + objets[i].d + objets[i].e;
            objets[i].f = v ^ t;
            s += v;
        }
    printf( "somme %llx ", (unsigned long long)s );
}

int main( int argc, char **argv )
{
    const char *mode = argc > 1 ? argv[1] : "drapeaux";
    unsigned tours = argc > 2 ? (unsigned)atoi( argv[2] ) : 0;
    LARGE_INTEGER a, b;

    QueryPerformanceCounter( &a );
    if (!strcmp( mode, "drapeaux" )) drapeaux( tours ? tours : 400000 );
    else if (!strcmp( mode, "tri" )) trier( tours ? tours : 40 );
    else if (!strcmp( mode, "atom1" )) atomiques( tours ? tours : 20000000, 1 );
    else if (!strcmp( mode, "atom4" )) atomiques( tours ? tours : 2000000, 4 );
    else if (!strcmp( mode, "flottant" )) flottant( tours ? tours : 30000000 );
    else if (!strcmp( mode, "tso" )) tso( tours ? tours : 20000 );
    else { printf( "mode inconnu\n" ); return 1; }
    QueryPerformanceCounter( &b );
    printf( "%s : %.1f ms\n", mode, ms( a, b ) );
    return 0;
}
