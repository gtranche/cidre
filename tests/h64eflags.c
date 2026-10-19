/* Temoin : EFLAGS a travers une exception (int3 + gestionnaire vectorise + reprise).
 * Aller : le gestionnaire doit voir PF, AF, CF, ZF, SF, OF, DF tels qu'avant l'int3.
 * Retour : les drapeaux poses par le gestionnaire dans le contexte doivent etre ceux
 * du code repris (lus par pushfq juste apres l'int3).
 * x86_64-w64-mingw32-clang -O1 h64eflags.c -o h64eflags.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

#define MASQUE 0xcd5 /* CF PF AF ZF SF DF OF */

static volatile DWORD vu, a_poser, df_gestionnaire;

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_BREAKPOINT) return EXCEPTION_CONTINUE_SEARCH;
    uint64_t f;
    __asm__ volatile("pushfq\n\tpopq %0" : "=r"(f));
    df_gestionnaire = (DWORD)f & 0x400;
    vu = ep->ContextRecord->EFlags & MASQUE;
    ep->ContextRecord->EFlags = (ep->ContextRecord->EFlags & ~MASQUE) | a_poser;
    ep->ContextRecord->Rip += 1;
    return EXCEPTION_CONTINUE_EXECUTION;
}

/* charge les drapeaux 'avant' par popfq, int3, relit par pushfq */
static DWORD essai(DWORD avant, DWORD poser)
{
    uint64_t apres;
    a_poser = poser;
    __asm__ volatile(
        "pushfq\n\t"
        "andq $~0xcd5, (%%rsp)\n\t"
        "orq %1, (%%rsp)\n\t"
        "popfq\n\t"
        "int3\n\t"
        "nop\n\t"
        "pushfq\n\t"
        "popq %0\n\t"
        "cld\n\t"
        : "=r"(apres) : "r"((uint64_t)avant) : "cc", "memory");
    return (DWORD)apres & MASQUE;
}

int main(void)
{
    static const struct { const char *nom; DWORD bit; } bits[] = {
        {"CF", 0x1}, {"PF", 0x4}, {"AF", 0x10}, {"ZF", 0x40}, {"SF", 0x80}, {"DF", 0x400}, {"OF", 0x800}};
    int echecs = 0;
    AddVectoredExceptionHandler(1, gestionnaire);
    for (int i = 0; i < 7; i++)
    {
        DWORD b = bits[i].bit;
        DWORD r = essai(b, 0);
        int aller = (vu == b), retour_zero = (r == 0);
        r = essai(0, b);
        int retour = (r == b);
        printf("%s : aller %s (vu %03lx)  retour efface %s  retour pose %s (lu %03lx)\n", bits[i].nom, aller ? "OK" : "ECHEC",
               (unsigned long)vu, retour_zero ? "OK" : "ECHEC", retour ? "OK" : "ECHEC", (unsigned long)r);
        echecs += !aller + !retour_zero + !retour;
        if (b == 0x400)
        {
            essai(0x400, 0x400);
            printf("DF dans le gestionnaire : %s\n", df_gestionnaire ? "ECHEC (leve)" : "OK (efface)");
            echecs += df_gestionnaire != 0;
        }
    }
    printf("h64eflags : %d echecs\n", echecs);
    return echecs != 0;
}
