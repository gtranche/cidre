/* Temoin (arm64 natif) : une page de 4 Kio passee en PAGE_EXECUTE_READWRITE a cote
 * d'une page de code, dans la meme page d'hote de 16 Kio. macOS refuse ecriture et
 * execution ensemble ; Wine retirait l'execution a toute la page d'hote et le code
 * natif voisin fautait. Cas du chargeur protege de Diablo II Resurrected, qui pose
 * un crochet dans ntdll. Verifie aussi qu'on peut ecrire puis executer la page RWX.
 * aarch64-w64-mingw32-clang -O1 a64rwx_voisine.c -o a64rwx_voisine.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int echecs;
static void verifier(int ok, const char *quoi)
{
    printf("%s %s\n", ok ? "OK    " : "ECHEC ", quoi);
    if (!ok) echecs++;
}

/* mov w0, #imm ; ret */
static void poser(uint8_t *p, unsigned imm)
{
    uint32_t c[2] = { 0x52800000u | (imm << 5), 0xd65f03c0u };
    memcpy(p, c, sizeof(c));
}

int main(void)
{
    HANDLE section;
    uint8_t *b;
    DWORD ancien;
    char quoi[128];
    int r;

    setvbuf(stdout, NULL, _IONBF, 0);
    section = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, 0x10000, NULL);
    b = MapViewOfFile(section, FILE_MAP_ALL_ACCESS | FILE_MAP_EXECUTE, 0, 0, 0x10000);
    if (!b) { printf("ECHEC  vue : %lu\n", GetLastError()); return 2; }
    poser(b + 0x100, 42);
    poser(b + 0x1100, 7);
    VirtualProtect(b, 0x2000, PAGE_EXECUTE_READ, &ancien);
    FlushInstructionCache(GetCurrentProcess(), b, 0x2000);
    r = ((int (*)(void))(b + 0x100))();
    verifier(r == 42, "A code natif, page RX");

    VirtualProtect(b + 0x1000, 0x1000, PAGE_EXECUTE_READWRITE, &ancien);
    r = ((int (*)(void))(b + 0x100))();
    snprintf(quoi, sizeof(quoi), "B code natif voisin d'une page RWX : %d", r);
    verifier(r == 42, quoi);

    poser(b + 0x1100, 9);
    FlushInstructionCache(GetCurrentProcess(), b + 0x1000, 0x1000);
    r = ((int (*)(void))(b + 0x1100))();
    snprintf(quoi, sizeof(quoi), "C ecrire puis executer la page RWX : %d", r);
    verifier(r == 9, quoi);

    for (int i = 0; i < 1000; i++)
    {
        poser(b + 0x1100, i & 0xff);
        FlushInstructionCache(GetCurrentProcess(), b + 0x1000, 0x1000);
        if (((int (*)(void))(b + 0x1100))() != (i & 0xff)) { r = -1; break; }
        if (((int (*)(void))(b + 0x100))() != 42) { r = -2; break; }
    }
    snprintf(quoi, sizeof(quoi), "D 1000 tours ecrire/executer : %d", r);
    verifier(r != -1 && r != -2, quoi);
    printf("%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs);
    return echecs ? 1 : 0;
}
