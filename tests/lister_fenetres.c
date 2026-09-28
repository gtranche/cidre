/* Enumere les fenetres de premier niveau et leurs controles, pour lire le
   contenu d'une boite de dialogue qu'on ne peut pas voir autrement. */
#include <windows.h>
#include <stdio.h>

static BOOL CALLBACK enfant(HWND h, LPARAM p)
{
    char classe[128] = "", texte[512] = "";
    GetClassNameA(h, classe, sizeof(classe));
    GetWindowTextA(h, texte, sizeof(texte));
    printf("    enfant  classe=%-20s texte=\"%s\"\n", classe, texte);
    (void)p;
    return TRUE;
}

static BOOL CALLBACK racine(HWND h, LPARAM p)
{
    char classe[128] = "", texte[512] = "";
    DWORD pid = 0;
    GetClassNameA(h, classe, sizeof(classe));
    GetWindowTextA(h, texte, sizeof(texte));
    GetWindowThreadProcessId(h, &pid);
    printf("fenetre pid=%lu %s classe=%-20s titre=\"%s\"\n",
           (unsigned long)pid, IsWindowVisible(h) ? "visible" : "cachee ", classe, texte);
    EnumChildWindows(h, enfant, 0);
    (void)p;
    return TRUE;
}

int main(void)
{
    EnumWindows(racine, 0);
    fflush(stdout);
    return 0;
}
