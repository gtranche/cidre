/* Banc cible des chemins FEX qui changent avec FlagM/FlagM2/FRINTTS :
 * octets (setf8), comparaisons flottantes scalaires (ucomiss -> axflag),
 * cvttps2dq vectoriel (frint32z). banc_cible.exe <octets|fcmp|cvt> */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <windows.h>
#include <emmintrin.h>

static double ms( LARGE_INTEGER a, LARGE_INTEGER b )
{
    LARGE_INTEGER f; QueryPerformanceFrequency( &f );
    return (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
}

static uint8_t o[4096];
static float fa[4096], fb[4096];

static uint64_t __attribute__((noinline)) octets( void )
{
    uint64_t s = 0; int i;
    for (i = 1; i < 4096; i++)
    {
        uint8_t r; int16_t q;
        if (__builtin_add_overflow( o[i], o[i - 1], &r )) s += 3;
        s += r;
        if (__builtin_sub_overflow( (int16_t)(o[i] * 129), (int16_t)(o[i - 1] * 257), &q )) s ^= 5;
        s += (uint16_t)q;
    }
    return s;
}

static uint64_t __attribute__((noinline)) fcmp( void )
{
    uint64_t s = 0; int i;
    for (i = 0; i < 4096; i++)
    {
        if (fa[i] < fb[i]) s += 1;
        else if (fa[i] == fb[i]) s += 7;
        if (fa[i] >= 0.5f) s += 2;
    }
    return s;
}

static uint64_t __attribute__((noinline)) cvt( void )
{
    __m128i acc = _mm_setzero_si128(); int i;
    for (i = 0; i < 4096; i += 4)
        acc = _mm_add_epi32( acc, _mm_cvttps_epi32( _mm_mul_ps( _mm_loadu_ps( fa + i ), _mm_set1_ps( 1000.0f ) ) ) );
    acc = _mm_add_epi32( acc, _mm_srli_si128( acc, 8 ) );
    acc = _mm_add_epi32( acc, _mm_srli_si128( acc, 4 ) );
    return (uint32_t)_mm_cvtsi128_si32( acc );
}

int main( int argc, char **argv )
{
    const char *mode = argc > 1 ? argv[1] : "octets";
    uint64_t s = 0; unsigned t, x = 1; int i;
    LARGE_INTEGER a, b;
    for (i = 0; i < 4096; i++)
    {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        o[i] = (uint8_t)x; fa[i] = (x & 0xffff) / 65536.0f; fb[i] = ((x >> 16) & 0xff) / 256.0f;
    }
    QueryPerformanceCounter( &a );
    for (t = 0; t < 20000; t++)
    {
        if (!strcmp( mode, "octets" )) s += octets();
        else if (!strcmp( mode, "fcmp" )) s += fcmp();
        else s += cvt();
        fa[t & 4095] += 1e-7f;
    }
    QueryPerformanceCounter( &b );
    printf( "somme %llx %s : %.1f ms\n", (unsigned long long)s, mode, ms( a, b ) );
    return 0;
}
