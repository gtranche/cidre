/* Banc : cout d'un acces a une page de 4 Kio permise d'une page d'hote de 16 Kio
 * mixte (une voisine NOACCESS), en ns par acces, et cout du meme site sur une
 * page d'hote normale. Avant le correctif FEX/Wine des sous-pages : chaque acces
 * fait faute et Wine le rejoue (~2,4 us) ; apres : la premiere faute fait
 * reecrire l'instruction JIT vers un talon, les suivantes passent par l'alias.
 *
 *   L1  lecture d'un octet indexe (le cas de D2R : D2R.exe lit son image)
 *   L8  lecture de 8 octets
 *   E4  ecriture de 4 octets
 *   N1  meme site que L1, page d'hote normale (cout du talon hors page mixte)
 *   R1  reference : lecture d'un octet, page normale, site jamais reecrit
 *   F4  L1 a 4 fils
 *   A1  meme site, alternance page mixte / page normale par blocs de 4096
 * x86_64-w64-mingw32-clang -O1 h64sous_page_banc.c -o h64sous_page_banc.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static uint8_t *base;
static LARGE_INTEGER freq;
static volatile uint64_t puits;

__attribute__((noinline)) static uint64_t boucle_l1(const uint8_t *p, int n)
{
    uint64_t s = 0;
    for (int i = 0; i < n; i++)
    {
        unsigned r;
        __asm__ volatile("movzbl (%1,%2), %0" : "=r"(r) : "r"(p), "r"((long long)(i & 0xfff)) : "memory");
        s += r;
    }
    return s;
}

__attribute__((noinline)) static uint64_t boucle_r1(const uint8_t *p, int n)
{
    uint64_t s = 0;
    for (int i = 0; i < n; i++)
    {
        unsigned r;
        __asm__ volatile("movzbl (%1,%2), %0" : "=r"(r) : "r"(p), "r"((long long)(i & 0xfff)) : "memory");
        s += r;
    }
    return s;
}

__attribute__((noinline)) static uint64_t boucle_l8(const uint8_t *p, int n)
{
    uint64_t s = 0;
    for (int i = 0; i < n; i++)
    {
        uint64_t r;
        __asm__ volatile("movq (%1,%2,8), %0" : "=r"(r) : "r"(p), "r"((long long)(i & 0x1ff)) : "memory");
        s += r;
    }
    return s;
}

__attribute__((noinline)) static void boucle_e4(uint8_t *p, int n)
{
    for (int i = 0; i < n; i++)
        __asm__ volatile("movl %k1, (%0,%2,4)" : : "r"(p), "r"(i), "r"((long long)(i & 0x3ff)) : "memory");
}

static double ns(LARGE_INTEGER t0, LARGE_INTEGER t1, int n)
{
    return (double)(t1.QuadPart - t0.QuadPart) * 1e9 / freq.QuadPart / n;
}

static DWORD WINAPI fil_l1(void *arg)
{
    puits += boucle_l1(base + 0x2000, (int)(INT_PTR)arg);
    return 0;
}

int main(int argc, char **argv)
{
    HANDLE section;
    LARGE_INTEGER t0, t1;
    DWORD ancien;
    int n = argc > 1 ? atoi(argv[1]) : 200000;
    uint64_t s;

    setvbuf(stdout, NULL, _IONBF, 0);
    QueryPerformanceFrequency(&freq);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 0x10000, NULL);
    base = MapViewOfFile(section, FILE_MAP_ALL_ACCESS, 0, 0, 0x10000);
    if (!base) { printf("ECHEC  vue de section : %lu\n", GetLastError()); return 2; }
    for (int i = 0; i < 0x10000; i++) base[i] = (uint8_t)i;
    VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);

    /* chauffe : une faute par site (rejeu, proposition) */
    puits += boucle_l1(base + 0x2000, 16) + boucle_l8(base + 0x2000, 16) + boucle_r1(base + 0x6000, 16);
    boucle_e4(base + 0x3000, 16);

    QueryPerformanceCounter(&t0); s = boucle_l1(base + 0x2000, n); QueryPerformanceCounter(&t1);
    printf("L1 lecture d'un octet, page mixte   : %8.1f ns par acces (%d)\n", ns(t0, t1, n), n);
    puits += s;
    QueryPerformanceCounter(&t0); s = boucle_l8(base + 0x2000, n); QueryPerformanceCounter(&t1);
    printf("L8 lecture de 8 octets, page mixte  : %8.1f ns par acces\n", ns(t0, t1, n));
    puits += s;
    QueryPerformanceCounter(&t0); boucle_e4(base + 0x3000, n); QueryPerformanceCounter(&t1);
    printf("E4 ecriture de 4 octets, page mixte : %8.1f ns par acces\n", ns(t0, t1, n));
    QueryPerformanceCounter(&t0); s = boucle_l1(base + 0x6000, n * 10); QueryPerformanceCounter(&t1);
    printf("N1 meme site que L1, page normale   : %8.1f ns par acces\n", ns(t0, t1, n * 10));
    puits += s;
    QueryPerformanceCounter(&t0); s = boucle_r1(base + 0x6000, n * 10); QueryPerformanceCounter(&t1);
    printf("R1 reference, page normale          : %8.1f ns par acces\n", ns(t0, t1, n * 10));
    puits += s;
    {
        /* A1 : le meme site alterne page mixte et page normale par blocs de 4096
         * (lecture sequentielle d'une image ou les pages mixtes sont parsemees) */
        s = 0;
        QueryPerformanceCounter(&t0);
        for (int r = 0; r < 50; r++) s += boucle_l1(base + 0x2000, 4096) + boucle_l1(base + 0x6000, 4096);
        QueryPerformanceCounter(&t1);
        printf("A1 alternance mixte/normale (4096)  : %8.1f ns par acces\n", ns(t0, t1, 50 * 8192));
        puits += s;
    }
    {
        HANDLE f[4];
        QueryPerformanceCounter(&t0);
        for (int i = 0; i < 4; i++) f[i] = CreateThread(NULL, 0, fil_l1, (void *)(INT_PTR)n, 0, NULL);
        WaitForMultipleObjects(4, f, TRUE, INFINITE);
        QueryPerformanceCounter(&t1);
        printf("F4 L1 a 4 fils (temps mural / acces): %8.1f ns par acces\n", ns(t0, t1, 4 * n));
    }
    /* verification des valeurs lues par le site L1 */
    s = boucle_l1(base + 0x2000, 0x1000);
    printf("%s somme L1 %llu (attendu %llu)\n", s == 0x1000ull * 255 / 2 ? "OK    " : "ECHEC ", (unsigned long long)s,
           (unsigned long long)(0x1000ull * 255 / 2));
    return 0;
}
