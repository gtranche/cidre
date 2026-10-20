/* Temoin : instructions du code JIT de FEX reecrites vers un talon (sous-pages,
 * FEX SousPages.cpp + Wine cidre_sous_pages). Une meme instruction x86 sert
 * d'abord sur une page de 4 Kio permise d'une page d'hote mixte (faute rejouee
 * par Wine, proposee a FEX, reecrite), puis repasse par le talon : sur la page
 * permise (alias), sur la page fermee (violation d'acces exacte), sur une page
 * d'hote redevenue normale, sur une page de garde, en ecriture, en atomique, en
 * SIMD, a plusieurs fils.
 *
 * Disposition (vue de section de 64 Kio, page d'hote = sous-pages 0 a 3) :
 *   0 : RW   1 : NOACCESS   2 : RW   3 : READONLY   ; 4-7 : RW (page d'hote normale)
 * K4 (page de garde) est informatif.
 * x86_64-w64-mingw32-clang -O1 h64sous_page_talon.c -o h64sous_page_talon.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define V1 0x1111111111111111ull
#define V2 0x2222222222222222ull

static uint8_t *base;
static volatile ULONG_PTR faute_adresse, faute_type;
static volatile DWORD faute_code;
static volatile int fautes, echecs;

static void verifier(int ok, const char *quoi)
{
    printf("%s %s\n", ok ? "OK    " : "ECHEC ", quoi);
    if (!ok) echecs++;
}

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    DWORD ancien, code = ep->ExceptionRecord->ExceptionCode;
    ULONG_PTR a;
    if (code != EXCEPTION_ACCESS_VIOLATION && code != STATUS_GUARD_PAGE_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    a = ep->ExceptionRecord->ExceptionInformation[1];
    if (a < (ULONG_PTR)base || a >= (ULONG_PTR)base + 0x10000) return EXCEPTION_CONTINUE_SEARCH;
    faute_code = code;
    faute_adresse = a;
    faute_type = ep->ExceptionRecord->ExceptionInformation[0];
    if (++fautes > 20) return EXCEPTION_CONTINUE_SEARCH;
    if (code == STATUS_GUARD_PAGE_VIOLATION) return EXCEPTION_CONTINUE_EXECUTION;   /* la garde est partie */
    if ((a & ~(ULONG_PTR)0xfff) == (ULONG_PTR)base + 0x1000)
    {
        VirtualProtect(base + 0x1000, 0x1000, PAGE_READWRITE, &ancien);
        *(volatile uint64_t *)(base + 0x1008) = V2;
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    if ((a & ~(ULONG_PTR)0xfff) == (ULONG_PTR)base + 0x3000)
    {
        VirtualProtect(base + 0x3000, 0x1000, PAGE_READWRITE, &ancien);
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

/* Chaque fonction = une instruction memoire de l'invite, donc un site JIT. */
__attribute__((noinline)) static uint64_t lire8(const volatile uint64_t *p) { return *p; }
__attribute__((noinline)) static void ecrire8(volatile uint64_t *p, uint64_t v) { *p = v; }
__attribute__((noinline)) static unsigned lire_octet_indexe(const uint8_t *p, long long i)
{
    unsigned r;
    __asm__ volatile("movzbl (%1,%2), %0" : "=r"(r) : "r"(p), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static uint64_t lire_dans_base(uint64_t *p)
{
    uint64_t r = (uint64_t)p;
    __asm__ volatile("movq (%0), %0" : "+r"(r) : : "memory");
    return r;
}
__attribute__((noinline)) static uint64_t xadd8(volatile uint64_t *p, uint64_t v)
{
    __asm__ volatile("lock xaddq %0, (%1)" : "+r"(v) : "r"(p) : "memory");
    return v;
}
__attribute__((noinline)) static int cmpxchg8(volatile uint64_t *p, uint64_t attendu, uint64_t nouveau)
{
    uint8_t ok;
    __asm__ volatile("lock cmpxchgq %3, (%1)\n\tsetz %0" : "=q"(ok), "+r"(p), "+a"(attendu) : "r"(nouveau) : "memory", "cc");
    return ok;
}
__attribute__((noinline)) static void copier16(void *d, const void *s)
{
    __asm__ volatile("movdqu (%1), %%xmm0\n\tmovdqu %%xmm0, (%0)" : : "r"(d), "r"(s) : "xmm0", "memory");
}

static void fermer1(void) { DWORD a; VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &a); }

static DWORD WINAPI fil_xadd(void *arg)
{
    for (int i = 0; i < 100000; i++) xadd8((volatile uint64_t *)(base + 0x2400), 1);
    return 0;
}

int main(void)
{
    HANDLE section;
    uint8_t *autre;
    char quoi[160];
    DWORD ancien;
    uint64_t v;

    setvbuf(stdout, NULL, _IONBF, 0);
    AddVectoredExceptionHandler(1, gestionnaire);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, 0x10000, NULL);
    base = MapViewOfFile(section, FILE_MAP_ALL_ACCESS, 0, 0, 0x10000);
    autre = MapViewOfFile(section, FILE_MAP_READ, 0, 0, 0x10000);
    if (!base || !autre) { printf("ECHEC  vue de section : %lu\n", GetLastError()); return 2; }
    memset(base, 0, 0x10000);
    *(uint64_t *)(base + 0x1008) = V1;
    *(uint64_t *)(base + 0x2010) = 0x2020202020202020ull;
    *(uint64_t *)(base + 0x3018) = 0x3030303030303030ull;
    *(uint64_t *)(base + 0x5010) = 0x5050505050505050ull;
    for (int i = 0; i < 256; i++) base[0x2800 + i] = (uint8_t)i;
    *(uint64_t *)(base + 0x2900) = (uint64_t)(base + 0x2010);
    fermer1();
    VirtualProtect(base + 0x3000, 0x1000, PAGE_READONLY, &ancien);

    /* K1 : meme lecture, page permise (deux fois : rejeu puis talon), puis page fermee */
    fautes = 0;
    v = lire8((uint64_t *)(base + 0x2010)) + lire8((uint64_t *)(base + 0x2010)) + lire8((uint64_t *)(base + 0x2010));
    snprintf(quoi, sizeof(quoi), "K1a lecture permise x3 : %llx fautes %d", (unsigned long long)v, fautes);
    verifier(fautes == 0 && v == 3 * 0x2020202020202020ull, quoi);
    faute_adresse = 0; faute_type = 99;
    v = lire8((uint64_t *)(base + 0x1008));
    snprintf(quoi, sizeof(quoi), "K1b meme lecture, page NOACCESS : faute %d type %lu adresse +%#lx valeur %llx", fautes,
             (unsigned long)faute_type, (unsigned long)(faute_adresse - (ULONG_PTR)base), (unsigned long long)v);
    verifier(fautes == 1 && faute_code == EXCEPTION_ACCESS_VIOLATION && faute_type == 0 &&
             faute_adresse == (ULONG_PTR)base + 0x1008 && v == V2, quoi);
    fermer1();
    fautes = 0;
    v = lire8((uint64_t *)(base + 0x2010));
    verifier(fautes == 0 && v == 0x2020202020202020ull, "K1c relecture permise apres la faute");

    /* K2 : meme ecriture, page RW puis READONLY ; seconde vue */
    fautes = 0;
    ecrire8((uint64_t *)(base + 0x2020), 1);
    ecrire8((uint64_t *)(base + 0x2020), 2);
    ecrire8((uint64_t *)(base + 0x2028), 3);
    snprintf(quoi, sizeof(quoi), "K2a ecritures permises : fautes %d, vu par l'autre vue %llx %llx", fautes,
             (unsigned long long)*(volatile uint64_t *)(autre + 0x2020), (unsigned long long)*(volatile uint64_t *)(autre + 0x2028));
    verifier(fautes == 0 && *(volatile uint64_t *)(autre + 0x2020) == 2 && *(volatile uint64_t *)(autre + 0x2028) == 3, quoi);
    faute_type = 99;
    ecrire8((uint64_t *)(base + 0x3020), 7);
    snprintf(quoi, sizeof(quoi), "K2b meme ecriture, page READONLY : faute %d type %lu adresse +%#lx valeur %llx", fautes,
             (unsigned long)faute_type, (unsigned long)(faute_adresse - (ULONG_PTR)base),
             (unsigned long long)*(volatile uint64_t *)(base + 0x3020));
    verifier(fautes == 1 && faute_type == 1 && faute_adresse == (ULONG_PTR)base + 0x3020 &&
             *(volatile uint64_t *)(base + 0x3020) == 7, quoi);
    VirtualProtect(base + 0x3000, 0x1000, PAGE_READONLY, &ancien);

    /* K3 : page d'hote redevenue normale, puis de nouveau mixte */
    VirtualProtect(base + 0x1000, 0x1000, PAGE_READWRITE, &ancien);
    fautes = 0;
    v = lire8((uint64_t *)(base + 0x2010)) + lire8((uint64_t *)(base + 0x1008));
    fermer1();
    v += lire8((uint64_t *)(base + 0x2010));
    snprintf(quoi, sizeof(quoi), "K3 page normale puis mixte : %llx fautes %d", (unsigned long long)v, fautes);
    verifier(fautes == 0 && v == 2 * 0x2020202020202020ull + V2, quoi);

    /* K4 : page de garde vue par le site reecrit */
    VirtualProtect(base + 0x1000, 0x1000, PAGE_READWRITE | PAGE_GUARD, &ancien);
    fautes = 0;
    v = lire8((uint64_t *)(base + 0x1008));
    snprintf(quoi, sizeof(quoi), "K4 page de garde : fautes %d code %lx adresse +%#lx valeur %llx", fautes,
             (unsigned long)faute_code, (unsigned long)(faute_adresse - (ULONG_PTR)base), (unsigned long long)v);
    /* informatif : la garde d'une page de 4 Kio sous une page d'hote de 16 Kio
     * depend de Wine (0201 ne compte pas une page de garde comme fermee) */
    printf("info   %s\n", quoi);
    fautes = 0;
    v = lire8((uint64_t *)(base + 0x1008));
    verifier(fautes == 0 && v == V2, "K4 lecture suivante sans faute");
    fermer1();

    /* K5 : octet indexe (le cas de D2R), puis meme instruction hors de la page */
    {
        unsigned s = 0;
        fautes = 0;
        for (int i = 0; i < 256; i++) s += lire_octet_indexe(base + 0x2800, i);
        for (int i = 0; i < 8; i++) s += lire_octet_indexe(base + 0x5000, 0x10 + i);
        snprintf(quoi, sizeof(quoi), "K5 octets indexes : somme %u fautes %d", s, fautes);
        verifier(fautes == 0 && s == 255 * 128 + 8 * 0x50, quoi);
        faute_type = 99;
        s = lire_octet_indexe(base + 0x1000, 0x10);
        snprintf(quoi, sizeof(quoi), "K5 octet indexe sur la page NOACCESS : faute %d adresse +%#lx", fautes,
                 (unsigned long)(faute_adresse - (ULONG_PTR)base));
        verifier(fautes == 1 && faute_adresse == (ULONG_PTR)base + 0x1010 && s == 0, quoi);
        fermer1();
    }

    /* K6 : la base est aussi la destination (mov rax, [rax]) */
    fautes = 0;
    v = lire_dans_base((uint64_t *)(base + 0x2900));
    v = lire_dans_base((uint64_t *)(base + 0x2900));
    snprintf(quoi, sizeof(quoi), "K6 mov rax,[rax] : %llx fautes %d", (unsigned long long)v, fautes);
    verifier(fautes == 0 && v == (uint64_t)(base + 0x2010), quoi);

    /* K7 : atomiques (xadd, cmpxchg), puis xadd a 4 fils sur la meme adresse */
    {
        HANDLE f[4];
        volatile uint64_t *m = (volatile uint64_t *)(base + 0x2400);
        int ok1, ok2;
        fautes = 0;
        *m = 10;
        v = xadd8(m, 5);
        v += xadd8(m, 5);
        ok1 = cmpxchg8(m, 20, 30);
        ok2 = cmpxchg8(m, 20, 40);
        ok2 = cmpxchg8(m, 20, 40);
        snprintf(quoi, sizeof(quoi), "K7a xadd/cmpxchg : rendus %llu, %d %d, memoire %llu fautes %d", (unsigned long long)v, ok1, ok2,
                 (unsigned long long)*m, fautes);
        verifier(fautes == 0 && v == 25 && ok1 == 1 && ok2 == 0 && *m == 30, quoi);
        *m = 0;
        for (int i = 0; i < 4; i++) f[i] = CreateThread(NULL, 0, fil_xadd, NULL, 0, NULL);
        WaitForMultipleObjects(4, f, TRUE, INFINITE);
        snprintf(quoi, sizeof(quoi), "K7b xadd a 4 fils : %llu (attendu 400000) fautes %d", (unsigned long long)*m, fautes);
        verifier(fautes == 0 && *m == 400000, quoi);
    }

    /* K8 : SIMD 16 octets, lecture et ecriture */
    {
        uint8_t tmp[16];
        fautes = 0;
        copier16(tmp, base + 0x2800);
        copier16(tmp, base + 0x2800);
        copier16(base + 0x2a00, base + 0x2810);
        copier16(base + 0x2a00, base + 0x2810);
        snprintf(quoi, sizeof(quoi), "K8 movdqu : %u %u %u fautes %d", tmp[0], tmp[15], *(volatile uint8_t *)(base + 0x2a0f), fautes);
        verifier(fautes == 0 && tmp[0] == 0 && tmp[15] == 15 && *(volatile uint8_t *)(base + 0x2a0f) == 0x1f &&
                 *(volatile uint8_t *)(autre + 0x2a00) == 0x10, quoi);
    }

    printf("%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
