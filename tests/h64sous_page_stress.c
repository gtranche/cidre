/* Temoin de stress des acces aux pages d'hote mixtes (FEX 0211, chemin lent et
 * chemin rapide ; Wine 0212). Chaque lecture faite par une instruction reecrite
 * est comparee a la meme donnee lue par une seconde vue de la section, qui n'est
 * jamais mixte (oracle).
 *
 *   S1  formes d'acces (registre + indice echelonne, deplacements negatifs,
 *       immediat, SIMD) sur la page 2 pendant que la page 1 est NOACCESS
 *   S2  ecritures par ces formes, relues par l'autre vue
 *   S3  4 fils lecteurs pendant que le fil principal change sans arret les droits
 *       de la page 3 (READONLY <-> READWRITE) et la page 1 (NOACCESS <-> READWRITE :
 *       page d'hote mixte, puis normale, puis mixte)
 *   S5  le cache d'un site apres fermeture de la page lue : une page de 4 Kio lue
 *       par un site (cache rempli) puis fermee doit faire faute a la lecture
 *       suivante, puis rouverte avec un autre contenu doit rendre ce contenu
 *   S4  vue en copie sur ecriture (FILE_MAP_COPY d'un fichier) : lecture par
 *       l'alias, puis ecriture native pendant que la page n'est plus mixte (copie
 *       privee), puis de nouveau mixte : la lecture doit voir la valeur ecrite
 *
 * Resultats (M1 Max, wine11 + 0211/0212) : sans 0215, S3 meurt a chaque passe (violation
 * d'acces non geree sur la page 2, permise : la lecture faute pendant qu'une voisine de
 * la meme page d'hote passe par NOACCESS) ; avec 0215, 4 passes sur 4 vertes, S5 garde
 * ses fautes (la page fermee fait toujours faute). La copie sur ecriture (S4) est aussi
 * ecartee en natif (alias mach_vm_remap d'une page MAP_PRIVATE : session D2R, alias_cow.c).
 *
 * x86_64-w64-mingw32-clang -O1 h64sous_page_stress.c -o h64sous_page_stress.exe
 * Lancement : wine h64sous_page_stress.exe dans un prefixe de temoin (vue de section,
 * fichier temporaire pour S4) ; code de sortie 0 si tout passe. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static uint8_t *base, *autre;
static volatile int fin;
static volatile LONG erreurs_s3, lectures_s3;
static int echecs;
static volatile LONG fautes_s5;

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    DWORD ancien;
    ULONG_PTR a;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    a = ep->ExceptionRecord->ExceptionInformation[1];
    if (!base || a < (ULONG_PTR)base + 0x2000 || a >= (ULONG_PTR)base + 0x3000) return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&fautes_s5);
    VirtualProtect(base + 0x2000, 0x1000, PAGE_READWRITE, &ancien);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static void verifier(int ok, const char *quoi)
{
    printf("%s %s\n", ok ? "OK    " : "ECHEC ", quoi);
    if (!ok) echecs++;
}

/* Une instruction par fonction : un site JIT chacune. */
__attribute__((noinline)) static unsigned f_octet(const uint8_t *b, long long i)
{
    unsigned r;
    __asm__ volatile("movzbl (%1,%2), %0" : "=r"(r) : "r"(b), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static unsigned f_mot(const uint8_t *b, long long i)
{
    unsigned r;
    __asm__ volatile("movzwl 0x10(%1,%2,2), %0" : "=r"(r) : "r"(b), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static unsigned f_dmot_neg(const uint8_t *b, long long i)
{
    unsigned r;
    __asm__ volatile("movl -0x40(%1,%2,4), %0" : "=r"(r) : "r"(b), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static uint64_t f_qmot_imm(const uint8_t *b)
{
    uint64_t r;
    __asm__ volatile("movq 0x7f8(%1), %0" : "=r"(r) : "r"(b) : "memory");
    return r;
}
__attribute__((noinline)) static uint64_t f_qmot_idx(const uint8_t *b, long long i)
{
    uint64_t r;
    __asm__ volatile("movq 0x100(%1,%2,8), %0" : "=r"(r) : "r"(b), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static uint64_t f_simd(const uint8_t *b, long long i)
{
    uint64_t lo, hi;
    __asm__ volatile("movdqu (%2,%3), %%xmm0\n\tmovq %%xmm0, %0\n\tpextrq $1, %%xmm0, %1"
                     : "=r"(lo), "=r"(hi) : "r"(b), "r"(i) : "xmm0", "memory");
    return lo ^ (hi * 31);
}
__attribute__((noinline)) static int64_t f_octet_signe(const uint8_t *b, long long i)
{
    int64_t r;
    __asm__ volatile("movsbq (%1,%2), %0" : "=r"(r) : "r"(b), "r"(i) : "memory");
    return r;
}
__attribute__((noinline)) static void e_octet(uint8_t *b, long long i, unsigned v)
{
    __asm__ volatile("movb %b2, (%0,%1)" : : "r"(b), "r"(i), "r"(v) : "memory");
}
__attribute__((noinline)) static void e_qmot(uint8_t *b, long long i, uint64_t v)
{
    __asm__ volatile("movq %2, -0x8(%0,%1,8)" : : "r"(b), "r"(i), "r"(v) : "memory");
}

/* Toutes les formes sur la page 2 (0x2000-0x2fff) de b ; oracle sur o. Rend le nombre d'ecarts. */
static int formes(const uint8_t *b, const uint8_t *o, unsigned graine)
{
    int ecarts = 0;
    for (int k = 0; k < 64; k++)
    {
        long long i = (graine * 2654435761u + k * 97u) % 0x7c0;
        const uint8_t *p = b + 0x2000, *q = o + 0x2000;
        if (f_octet(p, i) != f_octet(q, i)) ecarts++;
        if (f_mot(p, i / 2) != f_mot(q, i / 2)) ecarts++;
        if (f_dmot_neg(p + 0x40, i / 4) != f_dmot_neg(q + 0x40, i / 4)) ecarts++;
        if (f_qmot_idx(p, i / 8 % 0x1e0) != f_qmot_idx(q, i / 8 % 0x1e0)) ecarts++;
        if (f_simd(p, i) != f_simd(q, i)) ecarts++;
        if (f_octet_signe(p, i) != f_octet_signe(q, i)) ecarts++;
        if (f_qmot_imm(p + (k & 7) * 8) != f_qmot_imm(q + (k & 7) * 8)) ecarts++;
    }
    return ecarts;
}

static DWORD WINAPI lecteur(void *arg)
{
    unsigned g = (unsigned)(INT_PTR)arg;
    while (!fin)
    {
        int e = formes(base, autre, g++);
        InterlockedAdd(&erreurs_s3, e);
        InterlockedIncrement(&lectures_s3);
    }
    return 0;
}

int main(void)
{
    HANDLE section, f[4];
    DWORD ancien;
    char quoi[200];
    int e;

    setvbuf(stdout, NULL, _IONBF, 0);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 0x10000, NULL);
    base = MapViewOfFile(section, FILE_MAP_ALL_ACCESS, 0, 0, 0x10000);
    autre = MapViewOfFile(section, FILE_MAP_READ, 0, 0, 0x10000);
    if (!base || !autre) { printf("ECHEC  vues : %lu\n", GetLastError()); return 2; }
    for (int i = 0; i < 0x10000; i++) base[i] = (uint8_t)(i * 7 + (i >> 8) * 13);
    VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
    VirtualProtect(base + 0x3000, 0x1000, PAGE_READONLY, &ancien);

    /* S1 : plusieurs passes (rejeu et proposition, puis talon, puis cache du talon) */
    e = 0;
    for (unsigned g = 0; g < 2000; g++) e += formes(base, autre, g);
    snprintf(quoi, sizeof(quoi), "S1 formes d'acces, 2000 passes de 448 lectures : %d ecart(s)", e);
    verifier(e == 0, quoi);

    /* S2 : ecritures par les formes, relues par l'autre vue */
    e = 0;
    for (int k = 0; k < 4000; k++)
    {
        long long i = (k * 131) % 0xff0;
        e_octet(base + 0x2000, i, k & 0xff);
        if (autre[0x2000 + i] != (uint8_t)k) e++;
        e_qmot(base + 0x2000, (i & 0x1f0) / 8 + 1, 0x0102030405060708ull * k);
        if (*(volatile uint64_t *)(autre + 0x2000 + (i & 0x1f0) / 8 * 8) != 0x0102030405060708ull * k) e++;
    }
    snprintf(quoi, sizeof(quoi), "S2 ecritures, 8000 : %d ecart(s)", e);
    verifier(e == 0, quoi);

    /* S3 : lecteurs pendant les changements de droits */
    fin = 0; erreurs_s3 = 0; lectures_s3 = 0;
    for (int t = 0; t < 4; t++) f[t] = CreateThread(NULL, 0, lecteur, (void *)(INT_PTR)(t * 1000), 0, NULL);
    for (int k = 0; k < 3000; k++)
    {
        VirtualProtect(base + 0x3000, 0x1000, (k & 1) ? PAGE_READWRITE : PAGE_READONLY, &ancien);
        if (!(k % 10)) VirtualProtect(base + 0x1000, 0x1000, (k / 10) & 1 ? PAGE_READWRITE : PAGE_NOACCESS, &ancien);
    }
    VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
    Sleep(200);
    fin = 1;
    WaitForMultipleObjects(4, f, TRUE, INFINITE);
    snprintf(quoi, sizeof(quoi), "S3 4 lecteurs, droits changeants : %ld passes, %ld ecart(s)", lectures_s3, erreurs_s3);
    verifier(erreurs_s3 == 0 && lectures_s3 > 0, quoi);

    /* S5 : cache du site contre fermeture et reouverture de la page lue */
    AddVectoredExceptionHandler(1, gestionnaire);
    e = 0;
    for (int k = 0; k < 200; k++)
    {
        unsigned v1, v2;
        fautes_s5 = 0;
        v1 = f_octet(base + 0x2000, 0x321);                                  /* cache du site rempli */
        if (v1 != autre[0x2321]) e++;
        VirtualProtect(base + 0x2000, 0x1000, PAGE_NOACCESS, &ancien);       /* page lue fermee */
        base[0x5321] = (uint8_t)k;                                           /* (bouge la generation ailleurs) */
        v2 = f_octet(base + 0x2000, 0x321);                                  /* doit faire faute, rouverte en RW */
        if (fautes_s5 != 1) e++;
        base[0x2321] = (uint8_t)(k * 3 + 1);                                 /* autre contenu */
        if (f_octet(base + 0x2000, 0x321) != (uint8_t)(k * 3 + 1)) e++;
        (void)v2;
    }
    snprintf(quoi, sizeof(quoi), "S5 page lue fermee puis rouverte, 200 tours : %d ecart(s)", e);
    verifier(e == 0, quoi);

    /* S4 : vue en copie sur ecriture */
    {
        WCHAR chemin[MAX_PATH], dossier[MAX_PATH];
        HANDLE fic, sec;
        uint8_t *v, *w;
        DWORD ecrits;
        static uint8_t contenu[0x10000];
        int ok;

        GetTempPathW(MAX_PATH, dossier);
        GetTempFileNameW(dossier, L"spc", 0, chemin);
        fic = CreateFileW(chemin, GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_FLAG_DELETE_ON_CLOSE, NULL);
        for (int i = 0; i < 0x10000; i++) contenu[i] = (uint8_t)(i ^ 0x5a);
        WriteFile(fic, contenu, sizeof(contenu), &ecrits, NULL);
        sec = CreateFileMappingW(fic, NULL, PAGE_WRITECOPY, 0, 0, NULL);
        v = MapViewOfFile(sec, FILE_MAP_COPY, 0, 0, 0x10000);
        w = MapViewOfFile(sec, FILE_MAP_READ, 0, 0, 0x10000);
        if (!v || !w)
        {
            printf("info   S4 indisponible : %lu\n", GetLastError());
        }
        else
        {
            unsigned avant, apres, attendu;
            VirtualProtect(v + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
            avant = 0;
            for (int k = 0; k < 64; k++) avant += f_octet(v + 0x2000, 0x123);   /* reecriture, alias */
            VirtualProtect(v + 0x1000, 0x1000, PAGE_WRITECOPY, &ancien);         /* plus mixte */
            v[0x2123] = 0xc3;                                                    /* copie privee */
            VirtualProtect(v + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);          /* de nouveau mixte */
            apres = f_octet(v + 0x2000, 0x123);
            attendu = 0xc3;
            ok = apres == attendu && avant == 64u * (uint8_t)(0x2123 ^ 0x5a) && w[0x2123] == (uint8_t)(0x2123 ^ 0x5a);
            snprintf(quoi, sizeof(quoi), "S4 copie sur ecriture : avant %u (attendu %u), apres %#x (attendu %#x), vue du fichier %#x",
                     avant, 64u * (uint8_t)(0x2123 ^ 0x5a), apres, attendu, w[0x2123]);
            verifier(ok, quoi);
            /* ecriture par l'alias pendant que la page est mixte, puis lecture native */
            e_octet(v + 0x2000, 0x124, 0xa7);
            VirtualProtect(v + 0x1000, 0x1000, PAGE_WRITECOPY, &ancien);
            snprintf(quoi, sizeof(quoi), "S4 ecriture par l'alias puis lecture native : %#x (attendu 0xa7), fichier %#x",
                     v[0x2124], w[0x2124]);
            verifier(v[0x2124] == 0xa7 && w[0x2124] == (uint8_t)(0x2124 ^ 0x5a), quoi);
        }
    }

    printf("%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
