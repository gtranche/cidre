/* Clique un bouton d'une boite de dialogue designee par son titre.
   Usage : cliquer_bouton.exe "titre de la fenetre" "texte du bouton" */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *g_bouton;
static HWND g_trouve;

static BOOL CALLBACK enfant(HWND h, LPARAM p)
{
    char texte[256] = "";
    GetWindowTextA(h, texte, sizeof(texte));
    if (!strcmp(texte, g_bouton)) {
        g_trouve = h;
        return FALSE;
    }
    (void)p;
    return TRUE;
}

int main(int argc, char **argv)
{
    HWND dlg;

    if (argc < 3) {
        printf("usage : %s titre bouton\n", argv[0]);
        return 2;
    }
    dlg = FindWindowA(NULL, argv[1]);
    if (!dlg) {
        printf("fenetre introuvable : %s\n", argv[1]);
        return 1;
    }
    g_bouton = argv[2];
    EnumChildWindows(dlg, enfant, 0);
    if (!g_trouve) {
        printf("bouton introuvable : %s\n", argv[2]);
        return 1;
    }
    PostMessageA(g_trouve, BM_CLICK, 0, 0);
    printf("clique sur \"%s\"\n", argv[2]);
    return 0;
}
