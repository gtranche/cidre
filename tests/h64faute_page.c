/* Temoin : faute d'execution d'une instruction a cheval entre une page RX et une
 * page NOACCESS. Sur x86, l'adresse fautive (ExceptionInformation[1]) est le debut
 * de la seconde page. Le gestionnaire rend la page signalee executable et reprend.
 * x86_64-w64-mingw32-clang -O1 h64faute_page.c -o h64faute_page.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

static uint8_t *pages;
static volatile ULONG_PTR signalee;
static volatile int fautes;

static LONG CALLBACK gestionnaire(EXCEPTION_POINTERS *ep)
{
    DWORD ancien;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || ep->ExceptionRecord->ExceptionInformation[0] != 8)
        return EXCEPTION_CONTINUE_SEARCH;
    signalee = ep->ExceptionRecord->ExceptionInformation[1];
    if (++fautes > 5) { ep->ContextRecord->Rip = 0; return EXCEPTION_CONTINUE_SEARCH; }
    /* comme le chargeur protege : rendre executable la page signalee */
    VirtualProtect((void *)(signalee & ~(ULONG_PTR)0xfff), 0x1000, PAGE_EXECUTE_READ, &ancien);
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    DWORD ancien;
    pages = VirtualAlloc(NULL, 0x10000, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    /* mov eax, 0x12345678 ; ret -- les 3 derniers octets de l'immediat sur la page suivante */
    uint8_t *ins = pages + 0x8000 - 2;
    static const uint8_t code[] = {0xb8, 0x78, 0x56, 0x34, 0x12, 0xc3};
    memcpy(ins, code, sizeof(code));
    VirtualProtect(pages, 0x8000, PAGE_EXECUTE_READ, &ancien);
    VirtualProtect(pages + 0x8000, 0x8000, PAGE_NOACCESS, &ancien);
    AddVectoredExceptionHandler(1, gestionnaire);
    int r = ((int (*)(void))ins)();
    printf("valeur %08x, %d faute(s), adresse signalee %p (attendue %p) : %s\n", r, fautes, (void *)signalee, pages + 0x8000,
           (r == 0x12345678 && fautes == 1 && signalee == (ULONG_PTR)(pages + 0x8000)) ? "OK" : "ECHEC");
    return !(r == 0x12345678 && fautes == 1);
}
