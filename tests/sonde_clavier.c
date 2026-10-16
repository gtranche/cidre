/* Sonde du clavier vu par un jeu (tests/sonde_clavier.c), pour CIDRE_CLAVIER (wine11 0151).
 * Sans argument : la disposition annoncee (GetKeyboardLayout, son nom), puis
 * pour chaque touche du bloc principal, par code de balayage (= position) :
 * le code virtuel (MapVirtualKey VSC_TO_VK), le caractere de ce code virtuel
 * (VK_TO_CHAR, ce que lisent Unreal et SDL), le texte tape (ToUnicode) et le
 * nom de la touche (GetKeyNameText). Une ligne « WASD » resume ce que voit un
 * jeu qui lit VK_W, VK_A, VK_S, VK_D : la position ou il les trouve.
 * « fenetre [secondes] » : ouvre une fenetre et ecrit chaque WM_KEYDOWN /
 * WM_CHAR recu (code virtuel, balayage, caractere) -- a taper a la main.
 * A lancer dans un prefixe clone, jamais dans pfx-arm64ec.
 * construire : x86_64-w64-mingw32-gcc -O1 -o sonde_clavier.exe sonde_clavier.c -luser32 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Positions QWERTY des codes de balayage du bloc principal (jeu de 1). */
static const struct { UINT scan; const char *qwerty; } touches[] = {
    {0x02,"1"},{0x03,"2"},{0x04,"3"},{0x05,"4"},{0x06,"5"},{0x07,"6"},{0x08,"7"},
    {0x09,"8"},{0x0A,"9"},{0x0B,"0"},{0x0C,"-"},{0x0D,"="},
    {0x10,"Q"},{0x11,"W"},{0x12,"E"},{0x13,"R"},{0x14,"T"},{0x15,"Y"},{0x16,"U"},
    {0x17,"I"},{0x18,"O"},{0x19,"P"},{0x1A,"["},{0x1B,"]"},
    {0x1E,"A"},{0x1F,"S"},{0x20,"D"},{0x21,"F"},{0x22,"G"},{0x23,"H"},{0x24,"J"},
    {0x25,"K"},{0x26,"L"},{0x27,";"},{0x28,"'"},{0x2B,"\\"},
    {0x56,"<>"},{0x2C,"Z"},{0x2D,"X"},{0x2E,"C"},{0x2F,"V"},{0x30,"B"},{0x31,"N"},
    {0x32,"M"},{0x33,","},{0x34,"."},{0x35,"/"},
};

/* En UTF-8, « - » si vide et « _ » pour une espace : une colonne par valeur. */
static void utf8(const WCHAR *w, int n, char *out, int size)
{
    int len = n > 0 ? WideCharToMultiByte(CP_UTF8, 0, w, n, out, size - 1, NULL, NULL) : 0;
    out[len > 0 ? len : 0] = 0;
    for (char *p = out; *p; p++) if (*p == ' ') *p = '_';
    if (!out[0] || (unsigned char)out[0] < ' ') strcpy(out, "-");
}

static const char *qwerty_de(UINT scan)
{
    for (int i = 0; i < (int)(sizeof(touches) / sizeof(touches[0])); i++)
        if (touches[i].scan == scan) return touches[i].qwerty;
    return "?";
}

static void table(void)
{
    HKL avant = GetKeyboardLayout(0), hkl, liste[16];
    WCHAR nom[KL_NAMELENGTH] = {0};
    BYTE etat[256] = {0};
    int n;

    /* Le pilote d'affichage n'annonce sa disposition qu'a sa premiere
     * intervention dans le fil (fenetre, MapVirtualKey...) : avant, win32u
     * rend celle de la langue. Un jeu la lit d'ordinaire apres sa fenetre. */
    MapVirtualKeyW(0x11, MAPVK_VSC_TO_VK);
    hkl = GetKeyboardLayout(0);
    n = GetKeyboardLayoutList(16, liste);
    GetKeyboardLayoutNameW(nom);
    printf("avant le pilote : HKL %08lx\n", (unsigned long)(ULONG_PTR)avant);
    printf("disposition annoncee : HKL %08lx, nom %ls ; liste :", (unsigned long)(ULONG_PTR)hkl, nom);
    for (int i = 0; i < n; i++) printf(" %08lx", (unsigned long)(ULONG_PTR)liste[i]);
    printf("\n\nscan qwerty vk   vk->car texte nom\n");
    for (int i = 0; i < (int)(sizeof(touches) / sizeof(touches[0])); i++)
    {
        UINT scan = touches[i].scan, vk = MapVirtualKeyW(scan, MAPVK_VSC_TO_VK);
        UINT car = MapVirtualKeyW(vk, MAPVK_VK_TO_CHAR);
        WCHAR texte[8], nomt[32], c = (WCHAR)(car & 0xffff);
        char t8[32], n8[64], c8[8];
        int lt = ToUnicode(vk, scan, etat, texte, 8, 0);
        int ln = GetKeyNameTextW((LONG)(scan << 16), nomt, 32);

        if (lt < 0) ToUnicode(vk, scan, etat, texte, 8, 0); /* vider la touche morte */
        utf8(texte, lt < 0 ? 1 : lt, t8, sizeof(t8));
        utf8(nomt, ln, n8, sizeof(n8));
        utf8(&c, c ? 1 : 0, c8, sizeof(c8));
        printf("0x%02x %-6s 0x%02x  %-7s  %-5s  %s%s\n", scan, touches[i].qwerty, vk, c8, t8, n8,
               (car & 0x80000000) ? "  (morte)" : "");
    }
    printf("\nWASD : un jeu qui lit les codes virtuels trouve");
    for (const char *p = "WASD"; *p; p++)
    {
        UINT scan = MapVirtualKeyW(*p, MAPVK_VK_TO_VSC);
        printf(" VK_%c a la position %s (0x%02x)", *p, qwerty_de(scan), scan);
    }
    printf("\n");
}

static LRESULT CALLBACK proc(HWND w, UINT m, WPARAM wp, LPARAM lp)
{
    switch (m)
    {
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
    {
        UINT scan = (lp >> 16) & 0xff;
        printf("WM_KEYDOWN vk 0x%02x scan 0x%02x (position %s) vk->car 0x%04x\n", (UINT)wp, scan,
               qwerty_de(scan), MapVirtualKeyW((UINT)wp, MAPVK_VK_TO_CHAR) & 0xffff);
        break;
    }
    case WM_CHAR:
    {
        WCHAR c = (WCHAR)wp; char c8[8];
        utf8(&c, 1, c8, sizeof(c8));
        printf("WM_CHAR    '%s' (U+%04X)\n", c8, (UINT)wp);
        break;
    }
    case WM_INPUTLANGCHANGE:
        printf("WM_INPUTLANGCHANGE HKL %08lx\n", (unsigned long)lp);
        break;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(w, m, wp, lp);
}

static void fenetre(int secondes)
{
    WNDCLASSW wc = {0};
    MSG msg;
    DWORD fin = GetTickCount() + secondes * 1000;
    HWND w;

    wc.lpfnWndProc = proc; wc.hInstance = GetModuleHandleW(NULL); wc.lpszClassName = L"sonde_clavier";
    RegisterClassW(&wc);
    w = CreateWindowW(L"sonde_clavier", L"sonde clavier : tapez", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                      100, 100, 480, 200, NULL, NULL, wc.hInstance, NULL);
    SetForegroundWindow(w); SetFocus(w);
    printf("fenetre ouverte %d s : tapez (ZQSD, M, texte)\n", secondes);
    while (GetTickCount() < fin)
    {
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        MsgWaitForMultipleObjects(0, NULL, FALSE, 50, QS_ALLINPUT);
    }
    DestroyWindow(w);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 1 && !strcmp(argv[1], "fenetre")) fenetre(argc > 2 ? atoi(argv[2]) : 30);
    else table();
    return 0;
}
