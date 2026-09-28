/*
 * Ou est la fenetre du jeu, en coordonnees ecran.
 *
 * Sert a capturer la seule fenetre du jeu plutot que tout le bureau : on
 * enumere les fenetres visibles, on retient la plus grande qui porte une
 * classe Unity ou un titre, et on imprime son rectangle sous la forme attendue
 * par « screencapture -R ».
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static HWND trouvee;
static LONG aire;

static BOOL CALLBACK visiter( HWND h, LPARAM l )
{
    WCHAR classe[128] = {0}, titre[256] = {0};
    RECT r;
    LONG a;

    if (!IsWindowVisible( h )) return TRUE;
    if (!GetWindowRect( h, &r )) return TRUE;
    a = (r.right - r.left) * (r.bottom - r.top);
    if (a < 100 * 100) return TRUE;
    GetClassNameW( h, classe, 128 );
    GetWindowTextW( h, titre, 256 );
    wprintf( L"fenetre %p classe=%ls titre=\"%ls\" rect=%ld,%ld %ldx%ld\n", h, classe, titre,
             r.left, r.top, r.right - r.left, r.bottom - r.top );
    if (a > aire) { aire = a; trouvee = h; }
    return TRUE;
}

int main( int argc, char **argv )
{
    RECT r;

    EnumWindows( visiter, 0 );
    if (!trouvee) { printf( "aucune fenetre\n" ); return 1; }
    GetWindowRect( trouvee, &r );
    printf( "RECT %ld,%ld,%ld,%ld\n", r.left, r.top, r.right - r.left, r.bottom - r.top );

    /* « ourect.exe activer » met la fenetre au premier plan : Unity suspend le
     * rendu quand l'application perd le focus, et un jeu au repos ne prouve
     * rien. */
    if (argc > 1 && !strcmp( argv[1], "activer" ))
    {
        ShowWindow( trouvee, SW_RESTORE );
        SetForegroundWindow( trouvee );
        printf( "premier plan demande, actif = %p\n", GetForegroundWindow() );
    }
    return 0;
}
