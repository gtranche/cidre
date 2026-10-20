/* Temoin : instructions crypto x86 (AES-NI, PCLMULQDQ, CRC32) sous FEX,
 * comparees a des implementations logicielles sur des entrees pseudo-aleatoires.
 * x86_64-w64-mingw32-clang -O1 -maes -mpclmul -msse4.2 h64crypto.c -o h64crypto.exe */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <wmmintrin.h>
#include <nmmintrin.h>

static uint64_t etat = 0x9e3779b97f4a7c15ULL;
static uint64_t alea(void) { etat ^= etat << 13; etat ^= etat >> 7; etat ^= etat << 17; return etat; }

static uint8_t sbox[256], inv_sbox[256];
static uint8_t xt(uint8_t a) { return (uint8_t)((a << 1) ^ ((a & 0x80) ? 0x1b : 0)); }
static uint8_t mul(uint8_t a, uint8_t b) { uint8_t r = 0; while (b) { if (b & 1) r ^= a; a = xt(a); b >>= 1; } return r; }
static void init_sbox(void)
{
    for (int i = 0; i < 256; i++)
    {
        uint8_t inv = 0;
        if (i) for (int j = 1; j < 256; j++) if (mul((uint8_t)i, (uint8_t)j) == 1) { inv = (uint8_t)j; break; }
        uint8_t s = inv, x = inv;
        for (int k = 0; k < 4; k++) { x = (uint8_t)((x << 1) | (x >> 7)); s ^= x; }
        s ^= 0x63;
        sbox[i] = s; inv_sbox[s] = (uint8_t)i;
    }
}
/* etat en ordre colonne (octet 4*c + r), comme le registre xmm */
static void sub_bytes(uint8_t *s, const uint8_t *t) { for (int i = 0; i < 16; i++) s[i] = t[s[i]]; }
static void shift_rows(uint8_t *s, int inv)
{
    uint8_t t[16];
    for (int c = 0; c < 4; c++) for (int r = 0; r < 4; r++)
        if (!inv) t[4 * c + r] = s[4 * ((c + r) % 4) + r];
        else t[4 * ((c + r) % 4) + r] = s[4 * c + r];
    memcpy(s, t, 16);
}
static void mix_columns(uint8_t *s, int inv)
{
    for (int c = 0; c < 4; c++)
    {
        uint8_t *a = s + 4 * c, b[4];
        for (int r = 0; r < 4; r++)
            b[r] = inv ? (uint8_t)(mul(a[r], 14) ^ mul(a[(r + 1) % 4], 11) ^ mul(a[(r + 2) % 4], 13) ^ mul(a[(r + 3) % 4], 9))
                       : (uint8_t)(mul(a[r], 2) ^ mul(a[(r + 1) % 4], 3) ^ a[(r + 2) % 4] ^ a[(r + 3) % 4]);
        memcpy(a, b, 4);
    }
}
static void xor16(uint8_t *s, const uint8_t *k) { for (int i = 0; i < 16; i++) s[i] ^= k[i]; }

static int echecs;
static void compare(const char *nom, const void *a, const void *b, int n, int tour)
{
    if (memcmp(a, b, n))
    {
        if (echecs < 20)
        {
            const uint8_t *x = a, *y = b;
            printf("ECHEC %s tour %d : fex ", nom, tour);
            for (int i = n - 1; i >= 0; i--) printf("%02x", x[i]);
            printf(" attendu ");
            for (int i = n - 1; i >= 0; i--) printf("%02x", y[i]);
            printf("\n");
        }
        echecs++;
    }
}

static uint64_t clmul_lo(uint64_t a, uint64_t b, uint64_t *hi)
{
    uint64_t lo = 0, h = 0;
    for (int i = 0; i < 64; i++)
        if ((b >> i) & 1) { lo ^= a << i; if (i) h ^= a >> (64 - i); }
    *hi = h; return lo;
}
static uint32_t crc32c_sw(uint32_t crc, const uint8_t *p, int n)
{
    for (int i = 0; i < n; i++) { crc ^= p[i]; for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0x82f63b78 & -(crc & 1)); }
    return crc;
}

#define KEYGEN(imm) do { __m128i r = _mm_aeskeygenassist_si128(x, imm); \
    uint32_t w[4], e[4]; memcpy(w, s, 16); \
    uint32_t x1 = w[1], x3 = w[3]; uint8_t *p; \
    p = (uint8_t *)&x1; for (int i = 0; i < 4; i++) p[i] = sbox[p[i]]; \
    p = (uint8_t *)&x3; for (int i = 0; i < 4; i++) p[i] = sbox[p[i]]; \
    e[0] = x1; e[1] = ((x1 >> 8) | (x1 << 24)) ^ (imm); e[2] = x3; e[3] = ((x3 >> 8) | (x3 << 24)) ^ (imm); \
    compare("aeskeygenassist " #imm, &r, e, 16, t); } while (0)

#define CLMUL(imm) do { __m128i r = _mm_clmulepi64_si128(x, y, imm); uint64_t a64[2], b64[2], e[2]; \
    memcpy(a64, s, 16); memcpy(b64, k, 16); \
    e[0] = clmul_lo(a64[(imm) & 1], b64[((imm) >> 4) & 1], &e[1]); compare("pclmulqdq " #imm, &r, e, 16, t); } while (0)

static __m128i expand(__m128i k, __m128i g)
{
    g = _mm_shuffle_epi32(g, 0xff);
    k = _mm_xor_si128(k, _mm_slli_si128(k, 4));
    k = _mm_xor_si128(k, _mm_slli_si128(k, 4));
    k = _mm_xor_si128(k, _mm_slli_si128(k, 4));
    return _mm_xor_si128(k, g);
}

static void fips197(void)
{
    static const uint8_t pt[16] = {0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
    static const uint8_t key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
    static const uint8_t ct[16] = {0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a};
    __m128i k[11];
    k[0] = _mm_loadu_si128((const __m128i *)key);
#define X(i, rc) k[i] = expand(k[i - 1], _mm_aeskeygenassist_si128(k[i - 1], rc))
    X(1, 0x01); X(2, 0x02); X(3, 0x04); X(4, 0x08); X(5, 0x10); X(6, 0x20); X(7, 0x40); X(8, 0x80); X(9, 0x1b); X(10, 0x36);
    __m128i b = _mm_xor_si128(_mm_loadu_si128((const __m128i *)pt), k[0]);
    for (int i = 1; i < 10; i++) b = _mm_aesenc_si128(b, k[i]);
    b = _mm_aesenclast_si128(b, k[10]);
    compare("fips197 chiffre", &b, ct, 16, -1);
    for (int i = 9; i > 0; i--) k[i] = _mm_aesimc_si128(k[i]);
    b = _mm_xor_si128(b, k[10]);
    for (int i = 9; i > 0; i--) b = _mm_aesdec_si128(b, k[i]);
    b = _mm_aesdeclast_si128(b, k[0]);
    compare("fips197 dechiffre", &b, pt, 16, -1);
}

int main(void)
{
    init_sbox();
    fips197();
    for (int t = 0; t < 2000; t++)
    {
        uint8_t s[16], k[16], e[16];
        for (int i = 0; i < 16; i += 8) { uint64_t v = alea(); memcpy(s + i, &v, 8); v = alea(); memcpy(k + i, &v, 8); }
        __m128i x = _mm_loadu_si128((const __m128i *)s), y = _mm_loadu_si128((const __m128i *)k), r;

        r = _mm_aesenc_si128(x, y);
        memcpy(e, s, 16); sub_bytes(e, sbox); shift_rows(e, 0); mix_columns(e, 0); xor16(e, k); compare("aesenc", &r, e, 16, t);
        r = _mm_aesenclast_si128(x, y);
        memcpy(e, s, 16); sub_bytes(e, sbox); shift_rows(e, 0); xor16(e, k); compare("aesenclast", &r, e, 16, t);
        r = _mm_aesdec_si128(x, y);
        memcpy(e, s, 16); shift_rows(e, 1); sub_bytes(e, inv_sbox); mix_columns(e, 1); xor16(e, k); compare("aesdec", &r, e, 16, t);
        r = _mm_aesdeclast_si128(x, y);
        memcpy(e, s, 16); shift_rows(e, 1); sub_bytes(e, inv_sbox); xor16(e, k); compare("aesdeclast", &r, e, 16, t);
        r = _mm_aesimc_si128(x);
        memcpy(e, s, 16); mix_columns(e, 1); compare("aesimc", &r, e, 16, t);
        KEYGEN(0x00); KEYGEN(0x01); KEYGEN(0x1b); KEYGEN(0x36); KEYGEN(0x80); KEYGEN(0xff);
        CLMUL(0x00); CLMUL(0x01); CLMUL(0x10); CLMUL(0x11);

        uint32_t c0 = (uint32_t)alea();
        uint64_t q; memcpy(&q, k, 8);
        uint32_t c, ce;
        c = _mm_crc32_u8(c0, k[0]); ce = crc32c_sw(c0, k, 1); compare("crc32 b", &c, &ce, 4, t);
        c = _mm_crc32_u16(c0, (uint16_t)q); ce = crc32c_sw(c0, k, 2); compare("crc32 w", &c, &ce, 4, t);
        c = _mm_crc32_u32(c0, (uint32_t)q); ce = crc32c_sw(c0, k, 4); compare("crc32 d", &c, &ce, 4, t);
        uint64_t c64 = _mm_crc32_u64(c0, q), ce64 = crc32c_sw(c0, k, 8); compare("crc32 q", &c64, &ce64, 8, t);
    }
    printf("h64crypto : %d echecs\n", echecs);
    return echecs != 0;
}
