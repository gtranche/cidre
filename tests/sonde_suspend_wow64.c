/* Suspendre un fil au milieu du pont WoW64, puis le reprendre.
 *
 * C'est ce que fait un ramasse-miettes qui arrete le monde, Mono compris. Si
 * la reprise restaure un selecteur de code incoherent, le code 64 bits du pont
 * se decodera en 32 bits, comme dans sonde_jit_wow64.
 */
#include <windows.h>
#include <stdio.h>

static volatile LONG tourne = 1;
static volatile LONG appels;

static DWORD WINAPI marteau(void *arg)
{
    (void)arg;
    while (tourne) {
        Sleep(0);                 /* NtDelayExecution : traverse le pont */
        InterlockedIncrement(&appels);
    }
    return 0;
}

int main(int argc, char **argv)
{
    int cycles = (argc > 1) ? atoi(argv[1]) : 2000;
    HANDLE fil;
    CONTEXT ctx;
    int i;

    fil = CreateThread(NULL, 0, marteau, NULL, 0, NULL);
    if (!fil) { printf("CreateThread a echoue\n"); return 1; }

    for (i = 1; i <= cycles; i++) {
        SuspendThread(fil);
        ctx.ContextFlags = CONTEXT_FULL;
        GetThreadContext(fil, &ctx);      /* ce que fait un ramasse-miettes */
        ResumeThread(fil);
        if (i % 250 == 0) {
            printf("cycle %4d : %ld appels systeme traverses\n", i, appels);
            fflush(stdout);
        }
    }

    tourne = 0;
    WaitForSingleObject(fil, 5000);
    printf("TERMINE SANS PLANTAGE : %d suspensions, %ld traversees\n", cycles, appels);
    return 0;
}
