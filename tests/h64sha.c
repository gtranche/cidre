/* Temoin : SHA-NI (SHA-1 et SHA-256 d'un bloc) sous FEX, contre les condensats connus de « abc ».
 * x86_64-w64-mingw32-clang -O1 -msha -msse4.1 h64sha.c -o h64sha.exe */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <immintrin.h>
#include <intrin.h>

static void bloc_abc(uint8_t *b)
{
    memset(b, 0, 64);
    b[0] = 'a'; b[1] = 'b'; b[2] = 'c'; b[3] = 0x80; b[63] = 24;
}

static int sha256(void)
{
    static const uint32_t K[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
        0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
        0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
        0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    uint32_t h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    uint8_t b[64]; bloc_abc(b);
    const __m128i MASK = _mm_set_epi64x(0x0c0d0e0f08090a0bULL, 0x0405060700010203ULL);
    __m128i t = _mm_loadu_si128((__m128i *)&h[0]), s1 = _mm_loadu_si128((__m128i *)&h[4]);
    t = _mm_shuffle_epi32(t, 0xB1); s1 = _mm_shuffle_epi32(s1, 0x1B);
    __m128i s0 = _mm_alignr_epi8(t, s1, 8); s1 = _mm_blend_epi16(s1, t, 0xF0);
    __m128i a0 = s0, a1 = s1, m[4], msg;
    for (int i = 0; i < 4; i++) m[i] = _mm_shuffle_epi8(_mm_loadu_si128((__m128i *)(b + 16 * i)), MASK);
    for (int r = 0; r < 16; r++)
    {
        __m128i w = m[r & 3];
        if (r >= 4)
        {
            /* m[r&3] = msg2(msg1(m[r&3], m[(r+1)&3]) + alignr(m[(r+3)&3], m[(r+2)&3], 4), m[(r+3)&3]) */
            __m128i x = _mm_sha256msg1_epu32(m[r & 3], m[(r + 1) & 3]);
            x = _mm_add_epi32(x, _mm_alignr_epi8(m[(r + 3) & 3], m[(r + 2) & 3], 4));
            m[r & 3] = _mm_sha256msg2_epu32(x, m[(r + 3) & 3]);
            w = m[r & 3];
        }
        msg = _mm_add_epi32(w, _mm_loadu_si128((const __m128i *)&K[4 * r]));
        s1 = _mm_sha256rnds2_epu32(s1, s0, msg);
        msg = _mm_shuffle_epi32(msg, 0x0E);
        s0 = _mm_sha256rnds2_epu32(s0, s1, msg);
    }
    s0 = _mm_add_epi32(s0, a0); s1 = _mm_add_epi32(s1, a1);
    t = _mm_shuffle_epi32(s0, 0x1B); s1 = _mm_shuffle_epi32(s1, 0xB1);
    s0 = _mm_blend_epi16(t, s1, 0xF0); s1 = _mm_alignr_epi8(s1, t, 8);
    _mm_storeu_si128((__m128i *)&h[0], s0); _mm_storeu_si128((__m128i *)&h[4], s1);
    static const uint32_t att[8] = {0xba7816bf,0x8f01cfea,0x414140de,0x5dae2223,0xb00361a3,0x96177a9c,0xb410ff61,0xf20015ad};
    printf("sha256 : %08x%08x%08x%08x%08x%08x%08x%08x %s\n", h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], memcmp(h, att, 32) ? "ECHEC" : "OK");
    return memcmp(h, att, 32) != 0;
}

static int sha1(void)
{
    uint32_t h[5] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0};
    uint8_t b[64]; bloc_abc(b);
    const __m128i MASK = _mm_set_epi64x(0x0001020304050607ULL, 0x08090a0b0c0d0e0fULL);
    __m128i abcd = _mm_shuffle_epi32(_mm_loadu_si128((__m128i *)h), 0x1B), e_s = _mm_set_epi32(h[4], 0, 0, 0);
    __m128i abcd_s = abcd, m[4], ecur, saved = abcd;
    for (int i = 0; i < 4; i++) m[i] = _mm_shuffle_epi8(_mm_loadu_si128((__m128i *)(b + 16 * i)), MASK);
    for (int r = 0; r < 20; r++)
    {
        __m128i w;
        if (r < 4) w = m[r];
        else
        {
            __m128i x = _mm_sha1msg1_epu32(m[r & 3], m[(r + 1) & 3]);
            x = _mm_xor_si128(x, m[(r + 2) & 3]);
            m[r & 3] = _mm_sha1msg2_epu32(x, m[(r + 3) & 3]);
            w = m[r & 3];
        }
        ecur = r ? _mm_sha1nexte_epu32(saved, w) : _mm_add_epi32(e_s, w);
        saved = abcd;
        switch (r / 5)
        {
        case 0: abcd = _mm_sha1rnds4_epu32(abcd, ecur, 0); break;
        case 1: abcd = _mm_sha1rnds4_epu32(abcd, ecur, 1); break;
        case 2: abcd = _mm_sha1rnds4_epu32(abcd, ecur, 2); break;
        default: abcd = _mm_sha1rnds4_epu32(abcd, ecur, 3); break;
        }
    }
    __m128i e0 = _mm_sha1nexte_epu32(saved, e_s);
    abcd = _mm_add_epi32(abcd, abcd_s);
    abcd = _mm_shuffle_epi32(abcd, 0x1B);
    _mm_storeu_si128((__m128i *)h, abcd);
    h[4] = (uint32_t)_mm_extract_epi32(e0, 3);
    static const uint32_t att[5] = {0xa9993e36,0x4706816a,0xba3e2571,0x7850c26c,0x9cd0d89d};
    printf("sha1 : %08x%08x%08x%08x%08x %s\n", h[0], h[1], h[2], h[3], h[4], memcmp(h, att, 20) ? "ECHEC" : "OK");
    return memcmp(h, att, 20) != 0;
}

int main(void)
{
    int cpu[4];
    __cpuidex(cpu, 7, 0);
    printf("cpuid 7 ebx %08x (sha %d)\n", cpu[1], (cpu[1] >> 29) & 1);
    __cpuid(cpu, 1);
    printf("cpuid 1 ecx %08x (aes %d pclmul %d sse42 %d avx %d)\n", cpu[2], (cpu[2] >> 25) & 1, (cpu[2] >> 1) & 1, (cpu[2] >> 20) & 1, (cpu[2] >> 28) & 1);
    if (!((cpu[1] >> 29) & 1)) { __cpuidex(cpu, 7, 0); }
    int e = sha256();
    e |= sha1();
    return e;
}
