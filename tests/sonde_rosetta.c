/* Ce que Wine rapporte comme nom de processeur, vu depuis un processus 32 bits.
   C'est la chaine sur laquelle repose la detection de Rosetta 2 du CW HACK 20760. */
#include <windows.h>
#include <stdio.h>

typedef LONG (WINAPI *fn_query)(int, void *, ULONG, ULONG *);

int main(void)
{
    char buffer[64] = { 0 };
    fn_query query = (fn_query)GetProcAddress(GetModuleHandleA("ntdll.dll"),
                                              "NtQuerySystemInformation");
    LONG st;

    if (!query) { printf("NtQuerySystemInformation introuvable\n"); return 1; }
    st = query(105 /* SystemProcessorBrandString */, buffer, sizeof(buffer), NULL);
    printf("status=0x%08lx  chaine=\"%s\"\n", (unsigned long)st, buffer);
    printf("detection Rosetta 2 : %s\n",
           (!st && strstr(buffer, "VirtualApple")) ? "OUI" : "NON");
    return 0;
}
