/* Une faute de page rattrapee casse-t-elle la bascule 32->64 bits ?
 *
 * Le pont WoW64 de Wine fait un saut lointain vers un selecteur 64 bits. Si ce
 * saut transfere le controle sans changer de mode, les instructions 64 bits qui
 * suivent se decodent en 32 bits et l'appel indirect faute sur son propre
 * deplacement. On reproduit ici le motif de Mono : proteger une page, y ecrire,
 * rattraper la faute, deproteger, continuer -- puis refaire des appels systeme.
 */
#include <windows.h>
#include <stdio.h>

static void *page;
static volatile LONG fautes;

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *p)
{
    DWORD vieux;

    if (p->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&fautes);
    VirtualProtect(page, 4096, PAGE_READWRITE, &vieux);
    return EXCEPTION_CONTINUE_EXECUTION;
}

/* Sleep(0) traverse le pont : NtDelayExecution est un appel systeme. */
static void appels(int n)
{
    int i;
    for (i = 0; i < n; i++)
        Sleep(0);
}

static int g_cycles = 200;

/* Chaque fil a sa propre page : on veut des fautes simultanees, pas une
   competition sur la meme protection memoire. */
static DWORD WINAPI travail(void *arg)
{
    void *mienne = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_NOACCESS);
    DWORD vieux;
    int c;

    (void)arg;
    if (!mienne)
        return 1;
    for (c = 1; c <= g_cycles; c++) {
        VirtualProtect(mienne, 4096, PAGE_NOACCESS, &vieux);
        *(volatile char *)mienne = 1;
        appels(20);
    }
    return 0;
}

int main(int argc, char **argv)
{
    int cycles = (argc > 1) ? atoi(argv[1]) : 200;
    int nfils  = (argc > 2) ? atoi(argv[2]) : 1;
    HANDLE fils[64];
    DWORD vieux;
    int c, i;

    g_cycles = cycles;
    AddVectoredExceptionHandler(1, gestionnaire);
    page = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_NOACCESS);
    if (!page) {
        printf("VirtualAlloc a echoue\n");
        return 1;
    }

    appels(2000);
    printf("temoin : 2000 appels systeme sans aucune faute -> ok\n");
    fflush(stdout);

    if (nfils > 1) {
        if (nfils > 64) nfils = 64;
        printf("%d fils, %d cycles chacun\n", nfils, cycles);
        fflush(stdout);
        for (i = 0; i < nfils; i++)
            fils[i] = CreateThread(NULL, 0, travail, NULL, 0, NULL);
        WaitForMultipleObjects(nfils, fils, TRUE, INFINITE);
        printf("TERMINE SANS PLANTAGE apres %ld fautes\n", fautes);
        return 0;
    }

    for (c = 1; c <= cycles; c++) {
        VirtualProtect(page, 4096, PAGE_NOACCESS, &vieux);
        *(volatile char *)page = 1;
        appels(50);
        if (c % 25 == 0) {
            printf("cycle %3d : %ld fautes rattrapees, appels systeme ok\n", c, fautes);
            fflush(stdout);
        }
    }

    printf("TERMINE SANS PLANTAGE apres %ld fautes\n", fautes);
    return 0;
}
