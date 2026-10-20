/* Temoin : une protection de 4 Kio plus stricte que ses voisines, dans une page
 * d'hote de 16 Kio (Apple Silicon). Cas du chargeur protege de Diablo II
 * Resurrected : D2R.exe, projete sur une section, est dechiffre page de 4 Kio par
 * page de 4 Kio ; une page encore chiffree est PAGE_NOACCESS et son gestionnaire
 * d'exception la dechiffre a la premiere faute. Sous Wine, la page d'hote prenait
 * l'union des droits de ses quatre pages : la lecture de la page NOACCESS passait
 * sans faute et rendait l'octet chiffre.
 *
 * Disposition (vue de section de 64 Kio, page d'hote = sous-pages 0 a 3) :
 *   0 : RX (une fonction y est copiee)   1 : NOACCESS (valeur V1)
 *   2 : RW                               3 : READONLY
 * Verifications :
 *   A  lire la page 1 fait faute (lecture, adresse exacte) ; le gestionnaire la
 *      passe en RW, y ecrit V2 et reprend : la lecture rend V2
 *   B  lectures et ecritures permises sur la page 2 pendant que 1 est NOACCESS,
 *      vues aussi par une seconde vue de la section
 *   C  lecture de donnees sur la page 0 (RX) et la page 3 (READONLY)
 *   D  appel d'une fonction situee sur la page 0
 *   E  ecrire sur la page 3 (READONLY) fait faute en ecriture
 *   F  une lecture a cheval entre les pages 2 et 3 (non alignee)
 *   G  un switch dont la table de sauts est sur la page 1 (le cas de D2R)
 *   H  cout : lectures de la page 2 pendant que 1 est NOACCESS (ns par lecture)
 *   J  formes SIMD a un element (movhps, pinsrd, movddup, insertps, pextrd) et cmpxchg16b
 *   I  meme disposition par VirtualAlloc (informatif)
 * x86_64-w64-mingw32-clang -O1 h64sous_page.c -o h64sous_page.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define V1 0x1111111111111111ull
#define V2 0x2222222222222222ull

static uint8_t *base;
static volatile ULONG_PTR faute_adresse, faute_type;
static volatile int fautes, echecs;
static volatile int mode_g;

static void verifier(int ok, const char *quoi)
{
    printf("%s %s\n", ok ? "OK    " : "ECHEC ", quoi);
    if (!ok) echecs++;
}

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    DWORD ancien;
    ULONG_PTR a;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    a = ep->ExceptionRecord->ExceptionInformation[1];
    if (a < (ULONG_PTR)base || a >= (ULONG_PTR)base + 0x10000) return EXCEPTION_CONTINUE_SEARCH;
    faute_adresse = a;
    faute_type = ep->ExceptionRecord->ExceptionInformation[0];
    if (++fautes > 20) return EXCEPTION_CONTINUE_SEARCH;
    if ((a & ~(ULONG_PTR)0xfff) == (ULONG_PTR)base + 0x1000)
    {
        /* comme le chargeur : « dechiffrer » la page, puis la rendre lisible */
        VirtualProtect(base + 0x1000, 0x1000, PAGE_READWRITE, &ancien);
        if (mode_g)
        {
            uint32_t *table = (uint32_t *)(base + 0x1100);
            for (int i = 0; i < 4; i++) table[i] ^= 0x80000000u;
        }
        else *(volatile uint64_t *)(base + 0x1008) = V2;
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    if ((a & ~(ULONG_PTR)0xfff) == (ULONG_PTR)base + 0x3000)
    {
        VirtualProtect(base + 0x3000, 0x1000, PAGE_READWRITE, &ancien);
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

/* mov eax, 0x12345678 ; ret */
static const uint8_t fonction[] = { 0xb8, 0x78, 0x56, 0x34, 0x12, 0xc3 };

__attribute__((noinline)) static int aiguiller(uint32_t *table, int i)
{
    /* un switch a la main : rdx = base + table[i] ; jmp rdx */
    int r;
    __asm__ volatile(
        "movl (%1,%2,4), %%edx\n\t"
        "addq %3, %%rdx\n\t"
        "call *%%rdx\n\t"
        "movl %%eax, %0"
        : "=r"(r) : "r"(table), "r"((long long)i), "r"(base) : "rdx", "rax", "rcx", "memory");
    return r;
}

static void disposer(uint8_t *b)
{
    DWORD ancien;
    memset(b, 0, 0x4000);
    memcpy(b + 0x100, fonction, sizeof(fonction));
    *(uint64_t *)(b + 0x200) = 0x0a0a0a0a0a0a0a0aull;
    *(uint64_t *)(b + 0x1008) = V1;
    *(uint64_t *)(b + 0x2010) = 0x2020202020202020ull;
    *(uint64_t *)(b + 0x3018) = 0x3030303030303030ull;
    memset(b + 0x2ff8, 0x5a, 8);
    memset(b + 0x3000, 0xa5, 8);
    if (!VirtualProtect(b, 0x1000, PAGE_EXECUTE_READ, &ancien) ||
        !VirtualProtect(b + 0x1000, 0x1000, PAGE_NOACCESS, &ancien) ||
        !VirtualProtect(b + 0x3000, 0x1000, PAGE_READONLY, &ancien))
        printf("ECHEC  VirtualProtect : %lu\n", GetLastError());
}

static void essais(uint8_t *b, const char *nom, HANDLE section)
{
    char quoi[128];
    uint8_t *autre = NULL;
    DWORD ancien;
    int r, fautes_a_ok;

    printf("--- %s a %p\n", nom, b);
    base = b;
    disposer(b);
    if (section) autre = MapViewOfFile(section, FILE_MAP_READ, 0, 0, 0x10000);

    /* A */
    fautes = 0; faute_adresse = 0; faute_type = 99;
    uint64_t v = *(volatile uint64_t *)(b + 0x1008);
    snprintf(quoi, sizeof(quoi), "A lecture NOACCESS : faute %d type %lu adresse +%#lx valeur %llx", fautes,
             (unsigned long)faute_type, (unsigned long)(faute_adresse - (ULONG_PTR)b), (unsigned long long)v);
    fautes_a_ok = fautes == 1 && faute_type == 0 && faute_adresse == (ULONG_PTR)b + 0x1008 && v == V2;
    verifier(fautes_a_ok, quoi);

    /* B : page 1 de nouveau NOACCESS */
    VirtualProtect(b + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
    fautes = 0;
    *(volatile uint64_t *)(b + 0x2010) += 1;
    *(volatile uint32_t *)(b + 0x2020) = 0xdeadbeef;
    *(volatile uint8_t *)(b + 0x2030) = 0x77;
    snprintf(quoi, sizeof(quoi), "B lecture/ecriture RW voisine : fautes %d, %llx", fautes,
             (unsigned long long)*(volatile uint64_t *)(b + 0x2010));
    verifier(fautes == 0 && *(volatile uint64_t *)(b + 0x2010) == 0x2020202020202021ull &&
             *(volatile uint32_t *)(b + 0x2020) == 0xdeadbeef && *(volatile uint8_t *)(b + 0x2030) == 0x77, quoi);
    if (autre)
        verifier(*(volatile uint64_t *)(autre + 0x2010) == 0x2020202020202021ull &&
                 *(volatile uint32_t *)(autre + 0x2020) == 0xdeadbeef, "B ecritures vues par la seconde vue");

    /* C */
    verifier(*(volatile uint64_t *)(b + 0x200) == 0x0a0a0a0a0a0a0a0aull &&
             *(volatile uint64_t *)(b + 0x3018) == 0x3030303030303030ull && fautes == 0,
             "C lecture RX et READONLY voisines");

    /* D */
    r = ((int (*)(void))(b + 0x100))();
    verifier(r == 0x12345678 && fautes == 0, "D appel d'une fonction sur la page RX voisine");

    /* E */
    fautes = 0; faute_type = 99;
    *(volatile uint8_t *)(b + 0x3020) = 1;
    snprintf(quoi, sizeof(quoi), "E ecriture READONLY : faute %d type %lu adresse +%#lx", fautes,
             (unsigned long)faute_type, (unsigned long)(faute_adresse - (ULONG_PTR)b));
    verifier(fautes == 1 && faute_type == 1 && faute_adresse == (ULONG_PTR)b + 0x3020 &&
             *(volatile uint8_t *)(b + 0x3020) == 1, quoi);
    VirtualProtect(b + 0x3000, 0x1000, PAGE_READONLY, &ancien);

    /* F */
    fautes = 0;
    v = *(volatile uint64_t *)(b + 0x2ffc);
    snprintf(quoi, sizeof(quoi), "F lecture a cheval 2/3 : %llx", (unsigned long long)v);
    verifier(fautes == 0 && v == 0xa5a5a5a55a5a5a5aull, quoi);

    /* G : table de sauts chiffree (bit 31) sur la page 1 (sans faute, le saut
     * partirait dans le vide : seulement la ou A a passe) */
    if (fautes_a_ok)
    {
        uint32_t *table = (uint32_t *)(b + 0x1100);
        VirtualProtect(b + 0x1000, 0x1000, PAGE_READWRITE, &ancien);
        for (int i = 0; i < 4; i++) table[i] = 0x100 ^ 0x80000000u;
        VirtualProtect(b + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
        fautes = 0; mode_g = 1;
        r = aiguiller(table, 2);
        mode_g = 0;
        snprintf(quoi, sizeof(quoi), "G switch, table sur la page NOACCESS : faute %d rend %x", fautes, r);
        verifier(fautes == 1 && r == 0x12345678, quoi);
    }

    /* J : formes SIMD a un element et cmpxchg16b sur la page 2 pendant que 1 est
     *     NOACCESS (movhps, pinsrd, movddup, insertps, movhps en ecriture, pextrw) */
    {
        uint64_t lo, hi;
        uint32_t ext;
        VirtualProtect(b + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
        *(volatile uint64_t *)(b + 0x2100) = 0x1122334455667788ull;
        *(volatile uint32_t *)(b + 0x2108) = 0xcafef00du;
        *(volatile uint64_t *)(b + 0x2110) = 0x0102030405060708ull;
        fautes = 0;
        __asm__ volatile("pcmpeqd %%xmm0, %%xmm0\n\t"
                         "movhps (%2), %%xmm0\n\t"
                         "movq %%xmm0, %0\n\t"
                         "pextrq $1, %%xmm0, %1\n\t"
                         : "=r"(lo), "=r"(hi) : "r"(b + 0x2100) : "xmm0", "memory");
        snprintf(quoi, sizeof(quoi), "J1 movhps : %llx %llx fautes %d", (unsigned long long)hi, (unsigned long long)lo, fautes);
        verifier(fautes == 0 && hi == 0x1122334455667788ull && lo == ~0ull, quoi);
        __asm__ volatile("pxor %%xmm0, %%xmm0\n\t"
                         "pinsrd $2, (%2), %%xmm0\n\t"
                         "movq %%xmm0, %0\n\t"
                         "pextrq $1, %%xmm0, %1\n\t"
                         : "=r"(lo), "=r"(hi) : "r"(b + 0x2108) : "xmm0", "memory");
        snprintf(quoi, sizeof(quoi), "J2 pinsrd : %llx %llx fautes %d", (unsigned long long)hi, (unsigned long long)lo, fautes);
        verifier(fautes == 0 && hi == 0xcafef00dull && lo == 0, quoi);
        __asm__ volatile("movddup (%2), %%xmm0\n\t"
                         "movq %%xmm0, %0\n\t"
                         "pextrq $1, %%xmm0, %1\n\t"
                         : "=r"(lo), "=r"(hi) : "r"(b + 0x2110) : "xmm0", "memory");
        snprintf(quoi, sizeof(quoi), "J3 movddup : %llx %llx fautes %d", (unsigned long long)hi, (unsigned long long)lo, fautes);
        verifier(fautes == 0 && hi == 0x0102030405060708ull && lo == hi, quoi);
        __asm__ volatile("pxor %%xmm0, %%xmm0\n\t"
                         "insertps $0x20, (%2), %%xmm0\n\t"
                         "pextrq $1, %%xmm0, %1\n\t"
                         "movq %%xmm0, %0\n\t"
                         : "=r"(lo), "=r"(hi) : "r"(b + 0x2108) : "xmm0", "memory");
        snprintf(quoi, sizeof(quoi), "J4 insertps : %llx %llx fautes %d", (unsigned long long)hi, (unsigned long long)lo, fautes);
        verifier(fautes == 0 && hi == 0xcafef00dull && lo == 0, quoi);
        __asm__ volatile("movq %1, %%xmm0\n\t"
                         "pinsrq $1, %1, %%xmm0\n\t"
                         "movhps %%xmm0, (%0)\n\t"
                         : : "r"(b + 0x2118), "r"(0x5555aaaa5555aaaaull) : "xmm0", "memory");
        snprintf(quoi, sizeof(quoi), "J5 movhps en ecriture : %llx fautes %d", (unsigned long long)*(volatile uint64_t *)(b + 0x2118), fautes);
        verifier(fautes == 0 && *(volatile uint64_t *)(b + 0x2118) == 0x5555aaaa5555aaaaull, quoi);
        __asm__ volatile("movdqu (%1), %%xmm0\n\t"
                         "pextrw $3, %%xmm0, %%eax\n\t"
                         "pextrd $2, %%xmm0, (%1)\n\t"
                         "movl %%eax, %0\n\t"
                         : "=r"(ext) : "r"(b + 0x2100) : "xmm0", "rax", "memory");
        snprintf(quoi, sizeof(quoi), "J6 pextrd en ecriture : %x %llx fautes %d", ext, (unsigned long long)*(volatile uint64_t *)(b + 0x2100), fautes);
        verifier(fautes == 0 && ext == 0x1122 && *(volatile uint32_t *)(b + 0x2100) == 0xcafef00du, quoi);
        {
            /* cmpxchg16b : reussite puis echec */
            volatile uint64_t *m = (volatile uint64_t *)(b + 0x2200);
            uint8_t ok1, ok2;
            uint64_t a = 1, d = 2;
            m[0] = 1; m[1] = 2;
            __asm__ volatile("lock cmpxchg16b (%3)\n\tsetz %0" : "=q"(ok1), "+a"(a), "+d"(d) : "r"(m), "b"(3ull), "c"(4ull) : "memory", "cc");
            a = 1; d = 2;
            __asm__ volatile("lock cmpxchg16b (%3)\n\tsetz %0" : "=q"(ok2), "+a"(a), "+d"(d) : "r"(m), "b"(5ull), "c"(6ull) : "memory", "cc");
            snprintf(quoi, sizeof(quoi), "J7 cmpxchg16b : %d %d memoire %llx %llx lu %llx %llx fautes %d", ok1, ok2,
                     (unsigned long long)m[0], (unsigned long long)m[1], (unsigned long long)a, (unsigned long long)d, fautes);
            verifier(fautes == 0 && ok1 == 1 && ok2 == 0 && m[0] == 3 && m[1] == 4 && a == 3 && d == 4, quoi);
        }
    }

    /* H */
    {
        LARGE_INTEGER f, t0, t1;
        volatile uint64_t s = 0;
        VirtualProtect(b + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
        QueryPerformanceFrequency(&f);
        QueryPerformanceCounter(&t0);
        for (int i = 0; i < 100000; i++) s += *(volatile uint64_t *)(b + 0x2010);
        QueryPerformanceCounter(&t1);
        printf("info   H 100000 lectures voisines : %.0f ns par lecture\n",
               (double)(t1.QuadPart - t0.QuadPart) * 1e9 / f.QuadPart / 100000);
    }
    if (autre) UnmapViewOfFile(autre);
}

int main(int argc, char **argv)
{
    HANDLE section;
    uint8_t *b;

    setvbuf(stdout, NULL, _IONBF, 0);
    AddVectoredExceptionHandler(1, gestionnaire);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, 0x10000, NULL);
    b = MapViewOfFile(section, FILE_MAP_ALL_ACCESS | FILE_MAP_EXECUTE, 0, 0, 0x10000);
    if (!b) { printf("ECHEC  vue de section : %lu\n", GetLastError()); return 2; }
    essais(b, "vue de section", section);
    {
        int echecs_section = echecs;
        b = VirtualAlloc(NULL, 0x10000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        essais(b, "VirtualAlloc (informatif)", NULL);
        echecs = echecs_section;
    }
    printf("%s : %d echec(s) sur la vue de section\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
