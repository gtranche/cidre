/* Temoin de la lecture du code de l'invite dans les pages d'hote mixtes (FEX 0211 L1 : le decodeur lit par l'alias de
 * Wine). Diablo II Resurrected execute du code dechiffre a la demande : une page de 4 Kio ouverte (RX) au milieu de
 * voisines NOACCESS, re-protegee sans cesse, donc retraduite sans cesse ; sans L1, chaque octet lu par le decodeur
 * de FEX y fait faute et Wine le rejoue (~2,4 us).
 *
 *   C1  une fonction copiee dans la page 2 (RX), pages 1 et 3 NOACCESS : resultat juste, 2000 appels
 *   C2  la meme, re-protegee (RX) avant chaque appel : retraduction a chaque fois ; resultat juste ; temps par tour
 *       (a comparer entre FEX sans et avec L1)
 *   C3  un appel dans la page 1 (NOACCESS) fait toujours faute (le decodeur ne lit pas une page fermee par l'alias)
 *
 * x86_64-w64-mingw32-clang -O1 h64sous_page_code.c -o h64sous_page_code.exe
 * Lancement : wine h64sous_page_code.exe ; code de sortie 0 si tout passe. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef unsigned (*fonction)(unsigned);
static volatile LONG fautes;
static uint8_t *base;

/* Corps copie dans la page : somme de 0..n-1 avec quelques operations, sans appel ni donnee externe. */
static const uint8_t corps[] = {
    0x31, 0xc0,             /* xor eax, eax        */
    0x31, 0xd2,             /* xor edx, edx        */
    0x85, 0xc9,             /* test ecx, ecx       */
    0x74, 0x0b,             /* jz fin              */
    0x01, 0xd0,             /* boucle: add eax, edx */
    0x8d, 0x04, 0x40,       /* lea eax, [rax+rax*2] */
    0xff, 0xc2,             /* inc edx             */
    0x39, 0xca,             /* cmp edx, ecx        */
    0x72, 0xf5,             /* jb boucle           */
    0xc3,                   /* fin: ret            */
};

static unsigned reference(unsigned n)
{
    unsigned a = 0;
    for (unsigned d = 0; d < n; d++) { a += d; a *= 3; }
    return a;
}

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    ULONG_PTR a = (ULONG_PTR)ep->ExceptionRecord->ExceptionAddress;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    if (!base || a < (ULONG_PTR)base + 0x1000 || a >= (ULONG_PTR)base + 0x2000) return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&fautes);
    /* retour a l'appelant : le call a empile l'adresse de retour */
    ep->ContextRecord->Rip = *(DWORD64 *)ep->ContextRecord->Rsp;
    ep->ContextRecord->Rsp += 8;
    ep->ContextRecord->Rax = 0xdeadbeef;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    HANDLE section;
    DWORD ancien;
    LARGE_INTEGER f, t0, t1;
    fonction g;
    int echecs = 0, e;

    setvbuf(stdout, NULL, _IONBF, 0);
    /* Vue de section : le mode « pages mixtes » de Wine (0201) ne vaut que pour les images et les sections. */
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, 0x10000, NULL);
    base = section ? MapViewOfFile(section, FILE_MAP_ALL_ACCESS | FILE_MAP_EXECUTE, 0, 0, 0x10000) : NULL;
    if (!base) { printf("ECHEC  vue : %lu\n", GetLastError()); return 2; }
    memcpy(base + 0x2000, corps, sizeof(corps));
    memcpy(base + 0x1000, corps, sizeof(corps));
    VirtualProtect(base + 0x2000, 0x1000, PAGE_EXECUTE_READ, &ancien);
    VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);
    VirtualProtect(base + 0x3000, 0x1000, PAGE_NOACCESS, &ancien);
    VirtualProtect(base, 0x1000, PAGE_NOACCESS, &ancien);
    g = (fonction)(base + 0x2000);
    QueryPerformanceFrequency(&f);

    /* C1 */
    e = 0;
    for (unsigned k = 0; k < 2000; k++) if (g(k % 97) != reference(k % 97)) e++;
    printf("%s C1 code sur page mixte, 2000 appels : %d ecart(s)\n", e ? "ECHEC " : "OK    ", e);
    if (e) echecs++;

    /* C2 */
    e = 0;
    QueryPerformanceCounter(&t0);
    for (unsigned k = 0; k < 2000; k++)
    {
        VirtualProtect(base + 0x2000, 0x1000, PAGE_EXECUTE_READ, &ancien); /* invalide la traduction */
        if (g(k % 97) != reference(k % 97)) e++;
    }
    QueryPerformanceCounter(&t1);
    printf("%s C2 retraduction a chaque appel, 2000 tours : %d ecart(s), %.1f us par tour\n", e ? "ECHEC " : "OK    ", e,
           (t1.QuadPart - t0.QuadPart) * 1e6 / f.QuadPart / 2000);
    if (e) echecs++;

    /* C3 */
    AddVectoredExceptionHandler(1, gestionnaire);
    e = 0;
    for (int k = 0; k < 20; k++) if (((fonction)(base + 0x1000))(5) != 0xdeadbeef) e++;
    printf("%s C3 appel dans une page fermee : %ld faute(s) sur 20, %d retour(s) faux\n", (fautes == 20 && !e) ? "OK    " : "ECHEC ",
           (long)fautes, e);
    if (fautes != 20 || e) echecs++;

    printf("%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
