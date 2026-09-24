/* Du code genere a l'execution qui traverse le pont WoW64.
 *
 * C'est ce que fait Mono, et c'est la difference restante entre DREDGE, qui
 * plante de facon deterministe, et les sondes qui ne reproduisent rien. On
 * reecrit la fonction a chaque tour pour forcer Rosetta a la retraduire.
 */
#include <windows.h>
#include <stdio.h>

typedef void (WINAPI *fn_stub)(void);

/* push 0 ; mov eax,<cible> ; call eax ; ret */
static void ecrire(unsigned char *p, FARPROC cible)
{
    *p++ = 0x6a; *p++ = 0x00;
    *p++ = 0xb8;
    *(DWORD *)p = (DWORD)(ULONG_PTR)cible; p += 4;
    *p++ = 0xff; *p++ = 0xd0;
    *p++ = 0xc3;
}

int main(int argc, char **argv)
{
    int tours    = (argc > 1) ? atoi(argv[1]) : 20000;
    int reecrire = (argc > 2) ? atoi(argv[2]) : 1;
    unsigned char *code;
    FARPROC cible;
    int i;

    cible = GetProcAddress(GetModuleHandleA("kernel32.dll"), "Sleep");
    if (!cible) { printf("Sleep introuvable\n"); return 1; }

    code = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!code) { printf("VirtualAlloc a echoue\n"); return 1; }

    printf("mode = %s\n",
           reecrire == 0 ? "ecrit une fois" :
           reecrire == 1 ? "reecriture dans une page RWX" :
                           "reecriture avec bascule W^X");
    fflush(stdout);

    if (!reecrire)
        ecrire(code, cible);

    for (i = 1; i <= tours; i++) {
        if (reecrire == 1) {
            ecrire(code, cible);
            FlushInstructionCache(GetCurrentProcess(), code, 16);
        } else if (reecrire == 2) {
            DWORD vieux;
            VirtualProtect(code, 4096, PAGE_READWRITE, &vieux);
            ecrire(code, cible);
            VirtualProtect(code, 4096, PAGE_EXECUTE_READ, &vieux);
            FlushInstructionCache(GetCurrentProcess(), code, 16);
        }
        ((fn_stub)code)();

        if (i % (tours > 50 ? 100 : 1) == 0) { printf("tour %d ok\n", i); fflush(stdout); }
    }

    printf("TERMINE SANS PLANTAGE apres %d appels depuis du code genere\n", tours);
    return 0;
}
