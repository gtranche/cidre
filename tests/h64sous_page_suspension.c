/* Temoin des acces post-indexes (LODS) aux pages d'hote mixtes sous suspension de fil (FEX 0211, chemin
 * rapide de sp8 ; Wine 0212). Bissection de la nuit du 21/10 : le chemin rapide tue D2R des que la famille
 * post-indexee (ldr/ldrh/ldrb w, [x], #n : LODSD/LODSW/LODSB) y passe. Hypothese : une suspension (SuspendThread,
 * GetThreadContext/SetThreadContext de l'anti-debogage) qui tombe pendant que le registre de base est rebase
 * sur l'alias.
 *
 *   P1  un fil lit la page 2 (permise, page 1 NOACCESS : page d'hote mixte) par LODSB, LODSW, LODSD en boucle
 *       et compare chaque somme a celle de l'autre vue (oracle) ; le fil principal le suspend, lit son
 *       contexte, le reecrit tel quel et le reprend, sans arret. Ecarts, RSI hors de la vue (adresse de
 *       l'alias visible dans le contexte) et morts comptes.
 *   P2  meme lecteur pendant que le fil principal change sans arret les droits de la page 3, voisine dans la
 *       meme page d'hote (READONLY <-> READWRITE : la generation de Wine change a chaque fois).
 *   P3  la page lue elle-meme est fermee (NOACCESS) pendant la boucle : la lecture suivante doit faire faute
 *       (gestionnaire vectorise, qui rouvre la page) ; une fermeture sans faute dans les 200 ms est une faute
 *       manquee (cache du chemin rapide perime).
 *
 * x86_64-w64-mingw32-clang -O1 h64sous_page_suspension.c -o h64sous_page_suspension.exe
 * Lancement : wine h64sous_page_suspension.exe ; code de sortie 0 si tout passe. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static uint8_t *base, *autre;
static volatile int fin;
static volatile LONG ecarts, tours, fautes;

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    DWORD ancien;
    ULONG_PTR a;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    a = ep->ExceptionRecord->ExceptionInformation[1];
    if (!base || a < (ULONG_PTR)base + 0x2000 || a >= (ULONG_PTR)base + 0x3000) return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&fautes);
    VirtualProtect(base + 0x2000, 0x1000, PAGE_READONLY, &ancien);
    return EXCEPTION_CONTINUE_EXECUTION;
}

/* Une boucle LODS par fonction : un site JIT chacune (post-indexe, DF = 0). */
__attribute__((noinline)) static unsigned lodsb_somme(const uint8_t *p, unsigned long long n)
{
    unsigned s = 0, v;
    __asm__ volatile("cld\n1:\n\txorl %%eax, %%eax\n\tlodsb\n\taddl %%eax, %0\n\tdecq %%rcx\n\tjnz 1b"
                     : "+r"(s), "+S"(p), "+c"(n), "=&a"(v) : : "memory", "cc");
    return s;
}
__attribute__((noinline)) static unsigned lodsw_somme(const uint8_t *p, unsigned long long n)
{
    unsigned s = 0, v;
    __asm__ volatile("cld\n1:\n\txorl %%eax, %%eax\n\tlodsw\n\taddl %%eax, %0\n\tdecq %%rcx\n\tjnz 1b"
                     : "+r"(s), "+S"(p), "+c"(n), "=&a"(v) : : "memory", "cc");
    return s;
}
__attribute__((noinline)) static unsigned lodsd_somme(const uint8_t *p, unsigned long long n)
{
    unsigned s = 0, v;
    __asm__ volatile("cld\n1:\n\tlodsl\n\taddl %%eax, %0\n\tdecq %%rcx\n\tjnz 1b"
                     : "+r"(s), "+S"(p), "+c"(n), "=&a"(v) : : "memory", "cc");
    return s;
}

/* REP MOVS : FEX la traduit en boucle post-indexee (ldr w12, [x11], #n ; str w12, [x10], #n), la forme
 * des sites de D2R. */
__attribute__((noinline)) static void movsb_copie(uint8_t *d, const uint8_t *p, unsigned long long n)
{
    __asm__ volatile("cld\n\trep movsb" : "+D"(d), "+S"(p), "+c"(n) : : "memory");
}
__attribute__((noinline)) static void movsw_copie(uint8_t *d, const uint8_t *p, unsigned long long n)
{
    __asm__ volatile("cld\n\trep movsw" : "+D"(d), "+S"(p), "+c"(n) : : "memory");
}
__attribute__((noinline)) static void movsd_copie(uint8_t *d, const uint8_t *p, unsigned long long n)
{
    __asm__ volatile("cld\n\trep movsl" : "+D"(d), "+S"(p), "+c"(n) : : "memory");
}

static int copies(const uint8_t *p, const uint8_t *q)
{
    static __thread uint8_t a[0x1000], b[0x1000];
    int e = 0;
    movsb_copie(a, p + 1, 0xfff); movsb_copie(b, q + 1, 0xfff); if (memcmp(a, b, 0xfff)) e++;
    movsw_copie(a, p + 2, 0x7ff); movsw_copie(b, q + 2, 0x7ff); if (memcmp(a, b, 0xffe)) e++;
    movsd_copie(a, p + 4, 0x3ff); movsd_copie(b, q + 4, 0x3ff); if (memcmp(a, b, 0xffc)) e++;
    return e;
}

static DWORD WINAPI lecteur(void *arg)
{
    const uint8_t *p = base + 0x2000, *q = autre + 0x2000;
    (void)arg;
    while (!fin)
    {
        int e = 0;
        if (lodsb_somme(p, 0x1000) != lodsb_somme(q, 0x1000)) e++;
        if (lodsw_somme(p, 0x800) != lodsw_somme(q, 0x800)) e++;
        if (lodsd_somme(p, 0x400) != lodsd_somme(q, 0x400)) e++;
        e += copies(p, q);
        if (e) InterlockedAdd(&ecarts, e);
        InterlockedIncrement(&tours);
    }
    return 0;
}

int main(void)
{
    HANDLE section, f;
    DWORD ancien, rc;
    CONTEXT c;
    long suspensions = 0, hors = 0, refus = 0;
    int echecs = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 0x10000, NULL);
    base = MapViewOfFile(section, FILE_MAP_ALL_ACCESS, 0, 0, 0x10000);
    autre = MapViewOfFile(section, FILE_MAP_READ, 0, 0, 0x10000);
    if (!base || !autre) { printf("ECHEC  vues : %lu\n", GetLastError()); return 2; }
    for (int i = 0; i < 0x10000; i++) base[i] = (uint8_t)(i * 7 + (i >> 8) * 13);
    VirtualProtect(base + 0x1000, 0x1000, PAGE_NOACCESS, &ancien);

    f = CreateThread(NULL, 0, lecteur, NULL, 0, NULL);
    Sleep(300); /* rejeux, propositions, sites reecrits */
    for (int k = 0; k < 20000; k++)
    {
        if (SuspendThread(f) == (DWORD)-1) { refus++; continue; }
        c.ContextFlags = CONTEXT_FULL;
        if (GetThreadContext(f, &c))
        {
            if (c.Rsi && (c.Rsi < (DWORD64)base || c.Rsi >= (DWORD64)base + 0x10000) &&
                (c.Rsi < (DWORD64)autre || c.Rsi >= (DWORD64)autre + 0x10000) && c.Rcx > 0 && c.Rcx <= 0x1000 &&
                (c.Rsi >> 32) == ((DWORD64)base >> 32))
                hors++;
            if (!SetThreadContext(f, &c)) refus++;
        }
        else refus++;
        ResumeThread(f);
        suspensions++;
        if (!(k & 63)) Sleep(0);
    }
    fin = 1;
    rc = WaitForSingleObject(f, 5000);
    printf("%s P1 LODS sur page mixte sous suspension : %ld tours, %ld suspensions, %ld ecart(s), %ld RSI hors de la vue, %ld refus, fil %s\n",
           (ecarts || hors || rc != WAIT_OBJECT_0 || !tours) ? "ECHEC " : "OK    ", tours, suspensions, ecarts, hors, refus,
           rc == WAIT_OBJECT_0 ? "fini" : "bloque");
    if (ecarts || hors || rc != WAIT_OBJECT_0 || !tours) echecs++;

    /* P2 : droits changeants sur la page voisine de la meme page d'hote */
    fin = 0; ecarts = 0; tours = 0;
    f = CreateThread(NULL, 0, lecteur, NULL, 0, NULL);
    for (int k = 0; k < 4000 || tours < 2000; k++)
    {
        VirtualProtect(base + 0x3000, 0x1000, (k & 1) ? PAGE_READWRITE : PAGE_READONLY, &ancien);
        if (k > 400000) break;
    }
    fin = 1;
    rc = WaitForSingleObject(f, 5000);
    printf("%s P2 LODS, droits changeants sur la voisine : %ld tours, %ld ecart(s), fil %s\n",
           (ecarts || rc != WAIT_OBJECT_0 || !tours) ? "ECHEC " : "OK    ", tours, ecarts, rc == WAIT_OBJECT_0 ? "fini" : "bloque");
    if (ecarts || rc != WAIT_OBJECT_0 || !tours) echecs++;

    /* P3 : la page lue fermee doit faire faute a la lecture suivante */
    {
        long manquees = 0, fermetures = 0;
        AddVectoredExceptionHandler(1, gestionnaire);
        fin = 0; ecarts = 0; tours = 0;
        f = CreateThread(NULL, 0, lecteur, NULL, 0, NULL);
        Sleep(100);
        for (int k = 0; k < 300; k++)
        {
            LONG avant = fautes;
            VirtualProtect(base + 0x2000, 0x1000, PAGE_NOACCESS, &ancien);
            fermetures++;
            for (int t = 0; t < 200 && fautes == avant; t++) Sleep(1);
            if (fautes == avant) { manquees++; VirtualProtect(base + 0x2000, 0x1000, PAGE_READONLY, &ancien); }
        }
        fin = 1;
        rc = WaitForSingleObject(f, 5000);
        printf("%s P3 page lue fermee pendant LODS : %ld fermetures, %ld fautes, %ld manquee(s), %ld ecart(s), fil %s\n",
               (manquees || ecarts || rc != WAIT_OBJECT_0) ? "ECHEC " : "OK    ", fermetures, (long)fautes, manquees, ecarts,
               rc == WAIT_OBJECT_0 ? "fini" : "bloque");
        if (manquees || ecarts || rc != WAIT_OBJECT_0) echecs++;
    }
    printf("%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
