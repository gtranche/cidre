/* Un fil reecrit la page de code pendant qu'un autre l'execute.
 *
 * C'est le motif de Mono : le compilateur ecrit, les fils de travail appellent.
 * La bascule W^X du correctif 0063 fait alterner la page entre inscriptible et
 * executable ; si deux fils s'en disputent l'usage, Rosetta peut voir une
 * ecriture sur une page encore executable.
 */
#include <windows.h>
#include <stdio.h>

typedef void (WINAPI *fn_stub)(void);

static unsigned char *code;
static FARPROC cible;
static volatile LONG tourne = 1;
static volatile LONG ecritures, appels;

static void ecrire(unsigned char *p)
{
    *p++ = 0x6a; *p++ = 0x00;                       /* push 0        */
    *p++ = 0xb8;                                    /* mov eax, imm32 */
    *(DWORD *)p = (DWORD)(ULONG_PTR)cible; p += 4;
    *p++ = 0xff; *p++ = 0xd0;                       /* call eax      */
    *p++ = 0xc3;                                    /* ret           */
}

static DWORD WINAPI ecrivain(void *arg)
{
    (void)arg;
    while (tourne) {
        ecrire(code);
        FlushInstructionCache(GetCurrentProcess(), code, 16);
        InterlockedIncrement(&ecritures);
    }
    return 0;
}

static DWORD WINAPI appelant(void *arg)
{
    (void)arg;
    while (tourne) {
        ((fn_stub)code)();
        InterlockedIncrement(&appels);
    }
    return 0;
}

int main(int argc, char **argv)
{
    int secondes = (argc > 1) ? atoi(argv[1]) : 20;
    HANDLE fils[5];
    int i;

    cible = GetProcAddress(GetModuleHandleA("kernel32.dll"), "Sleep");
    code = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!cible || !code) { printf("preparation impossible\n"); return 1; }
    ecrire(code);

    fils[0] = CreateThread(NULL, 0, ecrivain, NULL, 0, NULL);
    for (i = 1; i < 5; i++)
        fils[i] = CreateThread(NULL, 0, appelant, NULL, 0, NULL);

    for (i = 0; i < secondes; i++) {
        Sleep(1000);
        printf("%2ds : %ld ecritures, %ld appels\n", i + 1, ecritures, appels);
        fflush(stdout);
    }
    tourne = 0;
    WaitForMultipleObjects(5, fils, TRUE, 5000);
    printf("TERMINE SANS PLANTAGE : %ld ecritures, %ld appels\n", ecritures, appels);
    return 0;
}
