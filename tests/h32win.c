/*
 * Invite i386 : creer une fenetre.
 *
 * WS_OVERLAPPEDWINDOW porte WS_SYSMENU, donc la creation construit le menu
 * systeme -- le chemin ou le verrou USER se perdait.
 */
#include <windows.h>
#include <stdio.h>

static LRESULT CALLBACK proc( HWND h, UINT m, WPARAM w, LPARAM l )
{
    return DefWindowProcW( h, m, w, l );
}

int main(void)
{
    WNDCLASSEXW wc = { sizeof(wc) };
    HWND hwnd;
    RECT r = { 0 };

    wc.lpfnWndProc   = proc;
    wc.hInstance     = GetModuleHandleW( NULL );
    wc.lpszClassName = L"essai_i386";
    if (!RegisterClassExW( &wc )) { printf( "RegisterClassEx : %lu\n", GetLastError() ); return 1; }
    printf( "classe enregistree\n" ); fflush( stdout );

    hwnd = CreateWindowExW( 0, L"essai_i386", L"essai", WS_OVERLAPPEDWINDOW,
                            10, 10, 320, 240, NULL, NULL, wc.hInstance, NULL );
    printf( "CreateWindowEx = %p (%lu)\n", hwnd, GetLastError() ); fflush( stdout );
    if (!hwnd) return 1;

    SetLastError( 0 );
    if (!GetClientRect( hwnd, &r )) printf( "GetClientRect a echoue : %lu\n", GetLastError() );
    printf( "client = %ldx%ld\n", r.right - r.left, r.bottom - r.top );
    if (!GetWindowRect( hwnd, &r )) printf( "GetWindowRect a echoue : %lu\n", GetLastError() );
    printf( "fenetre = %ld,%ld %ldx%ld\n", r.left, r.top, r.right - r.left, r.bottom - r.top );
    fflush( stdout );

    ShowWindow( hwnd, SW_SHOW );
    UpdateWindow( hwnd );
    DestroyWindow( hwnd );
    printf( "i386 fenetre : ok\n" );
    return 0;
}
