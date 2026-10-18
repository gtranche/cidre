/* Temoin de justesse des drapeaux x86 (FEX avec/sans FlagM/FlagM2/FRINTTS) :
 * comiss/ucomiss/comisd/ucomisd sur valeurs speciales, operations 8/16/32 bits
 * (add/adc/sub/sbb/neg/inc/dec/shl/sar/rol), cvttps2dq/cvttss2si/cvtss2si.
 * Imprime une empreinte FNV par famille. Meme source compilee pour Windows x64
 * (sous FEX) et macOS x86_64 (sous Rosetta, reference). */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <emmintrin.h>

#define FL 0x8d5 /* CF PF AF ZF SF OF */

static uint64_t h;
static void mel( uint64_t v ) { int i; for (i = 0; i < 8; i++) { h ^= (v >> (8 * i)) & 0xff; h *= 0x100000001b3ull; } }

#define CMP(insn, T, reg) static uint64_t f_##insn( T a, T b ) { uint64_t f; \
    __asm__ volatile( #insn " %2, %1\n\tpushfq\n\tpopq %0" : "=r"(f) : "x"(a), "x"(b) : "cc" ); return f & FL; }
CMP(comiss, float, x) CMP(ucomiss, float, x) CMP(comisd, double, x) CMP(ucomisd, double, x)

#define OP2(nom, insn, T, suf) static uint64_t nom( T a, T b, int cin, T *r ) { uint64_t f; T x = a; \
    __asm__ volatile( "bt $0, %q3\n\t" insn suf " %2, %0\n\tpushfq\n\tpopq %1" : "+r"(x), "=r"(f) : "r"(b), "r"((uint64_t)cin) : "cc" ); *r = x; return f & FL; }
OP2(add8, "add", uint8_t, "b") OP2(adc8, "adc", uint8_t, "b") OP2(sub8, "sub", uint8_t, "b") OP2(sbb8, "sbb", uint8_t, "b")
OP2(add16, "add", uint16_t, "w") OP2(adc16, "adc", uint16_t, "w") OP2(sub16, "sub", uint16_t, "w") OP2(sbb16, "sbb", uint16_t, "w")
OP2(add32, "add", uint32_t, "l") OP2(adc32, "adc", uint32_t, "l") OP2(sub32, "sub", uint32_t, "l") OP2(sbb32, "sbb", uint32_t, "l")
OP2(cmp8, "cmp", uint8_t, "b") OP2(cmp16, "cmp", uint16_t, "w") OP2(and8, "and", uint8_t, "b") OP2(xor16, "xor", uint16_t, "w")

#define OP1(nom, insn, T) static uint64_t nom( T a, int cin, T *r ) { uint64_t f; T x = a; \
    __asm__ volatile( "bt $0, %q2\n\t" insn " %0\n\tpushfq\n\tpopq %1" : "+r"(x), "=r"(f) : "r"((uint64_t)cin) : "cc" ); *r = x; return f; }
OP1(neg8, "negb", uint8_t) OP1(inc8, "incb", uint8_t) OP1(dec16, "decw", uint16_t) OP1(neg16, "negw", uint16_t)

#define SH(nom, insn, T) static uint64_t nom( T a, uint8_t c, T *r ) { uint64_t f; T x = a; \
    __asm__ volatile( "clc\n\t" insn " %%cl, %0\n\tpushfq\n\tpopq %1" : "+r"(x), "=r"(f) : "c"(c) : "cc" ); *r = x; return f; }
SH(shl8, "shlb", uint8_t) SH(sar16, "sarw", uint16_t) SH(rol8, "rolb", uint8_t) SH(shr16, "shrw", uint16_t)

int main( void )
{
    static const float vf[] = { 0.0f, -0.0f, 1.0f, -1.0f, 0.5f, 1e-40f, -1e-40f, 3.4e38f, INFINITY, -INFINITY, NAN, -NAN,
                                2147483520.0f, 2147483648.0f, -2147483648.0f, -2147483904.0f, 1.5f, 2.5f, -2.5f, 1e10f };
    static const double vd[] = { 0.0, -0.0, 1.0, -1.0, 0.5, 4e-320, -4e-320, 1.7e308, INFINITY, -INFINITY, NAN, -NAN,
                                 2147483647.0, 2147483648.0, -2147483649.0, 9.3e18, 1.5, 2.5, -2.5, 1e300 };
    const int nf = sizeof(vf) / sizeof(vf[0]), nd = sizeof(vd) / sizeof(vd[0]);
    static const uint32_t vi[] = { 0, 1, 2, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000, 0xffff, 0x10000, 0x7fffffff,
                                   0x80000000u, 0xffffffffu, 0x12345678, 0x55aa55aa, 0xdeadbeef, 3, 0x81, 0xfe };
    const int ni = sizeof(vi) / sizeof(vi[0]);
    int i, j, c;

    h = 0xcbf29ce484222325ull;
    for (i = 0; i < nf; i++) for (j = 0; j < nf; j++) { mel( f_comiss( vf[i], vf[j] ) ); mel( f_ucomiss( vf[i], vf[j] ) ); }
    for (i = 0; i < nd; i++) for (j = 0; j < nd; j++) { mel( f_comisd( vd[i], vd[j] ) ); mel( f_ucomisd( vd[i], vd[j] ) ); }
    printf( "comparaisons flottantes %016llx\n", (unsigned long long)h );

    h = 0xcbf29ce484222325ull;
    for (i = 0; i < ni; i++) for (j = 0; j < ni; j++) for (c = 0; c < 2; c++)
    {
        uint8_t r8; uint16_t r16; uint32_t r32;
        mel( add8( vi[i], vi[j], c, &r8 ) ); mel( r8 ); mel( adc8( vi[i], vi[j], c, &r8 ) ); mel( r8 );
        mel( sub8( vi[i], vi[j], c, &r8 ) ); mel( r8 ); mel( sbb8( vi[i], vi[j], c, &r8 ) ); mel( r8 );
        mel( cmp8( vi[i], vi[j], c, &r8 ) ); mel( and8( vi[i], vi[j], c, &r8 ) ); mel( r8 );
        mel( add16( vi[i], vi[j], c, &r16 ) ); mel( r16 ); mel( adc16( vi[i], vi[j], c, &r16 ) ); mel( r16 );
        mel( sub16( vi[i], vi[j], c, &r16 ) ); mel( r16 ); mel( sbb16( vi[i], vi[j], c, &r16 ) ); mel( r16 );
        mel( cmp16( vi[i], vi[j], c, &r16 ) ); mel( xor16( vi[i], vi[j], c, &r16 ) ); mel( r16 );
        mel( add32( vi[i], vi[j], c, &r32 ) ); mel( r32 ); mel( adc32( vi[i], vi[j], c, &r32 ) ); mel( r32 );
        mel( sub32( vi[i], vi[j], c, &r32 ) ); mel( r32 ); mel( sbb32( vi[i], vi[j], c, &r32 ) ); mel( r32 );
    }
    printf( "arithmetique 8/16/32  %016llx\n", (unsigned long long)h );

    h = 0xcbf29ce484222325ull;
    for (i = 0; i < ni; i++) for (c = 0; c < 2; c++)
    {
        uint8_t r8; uint16_t r16;
        /* inc/dec ne touchent pas CF ; neg le pose : on garde tout FL sauf AF (indefini pour rien ici) */
        mel( neg8( vi[i], c, &r8 ) & FL ); mel( r8 ); mel( inc8( vi[i], c, &r8 ) & FL ); mel( r8 );
        mel( dec16( vi[i], c, &r16 ) & FL ); mel( r16 ); mel( neg16( vi[i], c, &r16 ) & FL ); mel( r16 );
    }
    printf( "neg/inc/dec           %016llx\n", (unsigned long long)h );

    h = 0xcbf29ce484222325ull;
    for (i = 0; i < ni; i++) for (c = 1; c < 8; c++)
    {
        uint8_t r8; uint16_t r16;
        /* comptes 1..7 : CF/ZF/SF/PF definis (OF seulement pour 1, AF indefini) */
        uint64_t m = c == 1 ? 0x8c5 : 0xc5;
        mel( shl8( vi[i], c, &r8 ) & m ); mel( r8 ); mel( sar16( vi[i], c, &r16 ) & m ); mel( r16 );
        mel( rol8( vi[i], c, &r8 ) & (c == 1 ? 0x801 : 0x1) ); mel( r8 ); mel( shr16( vi[i], c, &r16 ) & m ); mel( r16 );
    }
    printf( "decalages             %016llx\n", (unsigned long long)h );

    h = 0xcbf29ce484222325ull;
    for (i = 0; i < nf; i += 4)
    {
        __m128i v = _mm_cvttps_epi32( _mm_loadu_ps( vf + i ) );
        int32_t o[4]; memcpy( o, &v, 16 ); for (j = 0; j < 4; j++) mel( (uint32_t)o[j] );
    }
    for (i = 0; i < nf; i++) { mel( (uint32_t)_mm_cvttss_si32( _mm_set_ss( vf[i] ) ) ); mel( (uint32_t)_mm_cvtss_si32( _mm_set_ss( vf[i] ) ) ); }
    for (i = 0; i < nd; i++) { mel( (uint64_t)_mm_cvttsd_si64( _mm_set_sd( vd[i] ) ) ); mel( (uint32_t)_mm_cvttsd_si32( _mm_set_sd( vd[i] ) ) ); }
    printf( "conversions           %016llx\n", (unsigned long long)h );
    return 0;
}
