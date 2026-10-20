/* h64cible_chiffree.c : du code ARM64EC de Wine appelle une fonction x64 dont la page est encore NOACCESS
 * (dechiffrement a la premiere execution, comme le chargeur de D2R). Un gestionnaire vectorise imite le
 * chargeur : il ne traite qu'une faute d'EXECUTION dans la page (rend la page RX, reprend). Sous Windows,
 * l'appel atteint le code x64, qui faute a l'execution. Sous Wine ARM64EC, arm64x_check_call lit d'abord les
 * octets de la cible : faute de LECTURE dans ntdll, que le gestionnaire ne reconnait pas -> mort.
 *   cas Q : qsort de msvcrt (code EC) avec un comparateur x64 dans une page fermee ;
 *   cas F : CreateThread avec une fonction de depart x64 dans une page fermee.
 * La page est fermee sur 16 Kio (une page d'hote entiere sous macOS) : une seule page de 4 Kio dans de la
 * memoire privee resterait lisible (0201 ne ferme les sous-pages que dans les vues de section).
 * x86_64-w64-mingw32-gcc -O1 -o h64cible_chiffree.exe h64cible_chiffree.c
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static BYTE *page;
static volatile LONG execs, autres;

static LONG CALLBACK veh(EXCEPTION_POINTERS *e)
{
    EXCEPTION_RECORD *r = e->ExceptionRecord;
    DWORD old;
    if (r->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || r->NumberParameters < 2) return EXCEPTION_CONTINUE_SEARCH;
    if ((BYTE *)r->ExceptionInformation[1] < page || (BYTE *)r->ExceptionInformation[1] >= page + 0x4000)
        return EXCEPTION_CONTINUE_SEARCH;
    if (r->ExceptionInformation[0] != 8)
    {
        InterlockedIncrement(&autres);
        return EXCEPTION_CONTINUE_SEARCH;   /* comme le chargeur : seule l'execution est attendue ici */
    }
    InterlockedIncrement(&execs);
    VirtualProtect(page, 0x4000, PAGE_EXECUTE_READ, &old);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static void fermer(void)
{
    DWORD old;
    VirtualProtect(page, 0x4000, PAGE_NOACCESS, &old);
}

int main(int argc, char **argv)
{
    /* comparateur x64 : int cmp(const int *a, const int *b) { return *a - *b; } ; fil : return 0x1234 */
    static const BYTE cmp[] = { 0x8b, 0x01, 0x2b, 0x02, 0xc3 };          /* mov eax,[rcx] ; sub eax,[rdx] ; ret */
    static const BYTE fil[] = { 0xb8, 0x34, 0x12, 0x00, 0x00, 0xc3 };   /* mov eax,0x1234 ; ret */
    int t[8] = { 5, 3, 8, 1, 9, 2, 7, 4 }, echecs = 0, i;
    DWORD code = 0;
    HANDLE h;

    setvbuf(stdout, NULL, _IONBF, 0);
    page = VirtualAlloc(NULL, 0x10000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    memcpy(page, cmp, sizeof(cmp));
    memcpy(page + 0x40, fil, sizeof(fil));
    AddVectoredExceptionHandler(1, veh);

    fermer();
    qsort(t, 8, sizeof(int), (int (*)(const void *, const void *))page);
    for (i = 1; i < 8; i++) if (t[i - 1] > t[i]) break;
    printf("cas Q (qsort, comparateur ferme) : %s ; fautes d'execution %ld, autres fautes %ld\n",
           i == 8 ? "OK" : "ECHEC (tri faux)", execs, autres);
    if (i != 8) echecs++;

    fermer(); execs = autres = 0;
    h = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)(page + 0x40), NULL, 0, NULL);
    WaitForSingleObject(h, 10000);
    GetExitCodeThread(h, &code);
    printf("cas F (CreateThread, depart ferme) : %s (code %lx) ; fautes d'execution %ld, autres fautes %ld\n",
           code == 0x1234 ? "OK" : "ECHEC", code, execs, autres);
    if (code != 0x1234) echecs++;
    printf("h64cible_chiffree : %d echec(s)\n", echecs);
    return echecs;
}
