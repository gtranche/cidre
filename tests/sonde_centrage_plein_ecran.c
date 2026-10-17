/* Sonde : image d'un jeu D3D9 plein ecran centree sous un mode d'ecran emule.
 *
 * Un jeu demande un mode d'un autre format que l'ecran (1024x768 en 4:3,
 * 1920x1200 en 16:10 sur un ecran 16:9). Sous mode_emule, Wine met le mode a
 * l'echelle et le centre ; dans l'espace plein ecran macOS, la fenetre est
 * pourtant tenue a la taille de l'ecran. Avant Wine 0171, l'image partait
 * collee a gauche (ou en haut) et la surface GDI de la fenetre restait a nu
 * sur l'autre bord (Fahrenheit 312840, iMac M4 4,5K, 2026-10-17).
 *
 * La sonde cree une fenetre popup, un device D3D9 plein ecran au mode demande,
 * et presente pendant <secondes> une mire : bande ROUGE sur le 1/8 gauche,
 * bande VERTE sur le 1/8 droit, BLEU au milieu. Une capture d'ecran
 * (tests/sonde_centrage_mesurer.py) dit ou tombent le rouge et le vert : leurs
 * marges a l'ecran doivent etre egales, et noires.
 *
 *   sonde_centrage_plein_ecran.exe [largeur hauteur secondes]   (1024 768 12)
 *   i686-w64-mingw32-gcc -O1 -o sonde_centrage_plein_ecran.exe sonde_centrage_plein_ecran.c -ld3d9 -lgdi32
 *
 * Code de sortie 0 si le device a ete cree et la mire presentee. */
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>

static LRESULT CALLBACK proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_KEYDOWN && wp == VK_ESCAPE) PostQuitMessage(0);
    if (msg == WM_SIZE || msg == WM_ACTIVATEAPP || msg == WM_CLOSE || msg == WM_DESTROY)
        printf("message %04x %08lx\n", msg, (unsigned long)lp);
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int main(int argc, char **argv)
{
    UINT w = argc > 2 ? atoi(argv[1]) : 1024, h = argc > 2 ? atoi(argv[2]) : 768;
    DWORD duree = (argc > 3 ? atoi(argv[3]) : 12) * 1000, debut;
    D3DPRESENT_PARAMETERS pp = {0};
    IDirect3DDevice9 *dev = NULL;
    WNDCLASSA wc = {0};
    IDirect3D9 *d3d;
    RECT rc, wr;
    HRESULT hr;
    HWND hwnd;
    MSG msg;
    int images = 0;

    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    wc.hbrBackground = GetStockObject(WHITE_BRUSH); /* GDI a nu = blanc */
    wc.lpszClassName = "sonde_centrage";
    RegisterClassA(&wc);
    /* Fenetre a la taille du bureau d'abord, comme un jeu qui ouvre plein
       ecran avant de changer de mode : c'est elle que Cidre promeut en espace. */
    hwnd = CreateWindowA("sonde_centrage", "sonde_centrage", WS_POPUP | WS_VISIBLE, 0, 0,
                         GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN),
                         NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("CreateWindow echoue (%lu)\n", GetLastError()); return 2; }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    for (debut = GetTickCount(); GetTickCount() - debut < 1500;)
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }

    if (!(d3d = Direct3DCreate9(D3D_SDK_VERSION))) { printf("Direct3DCreate9 = NULL\n"); return 3; }
    pp.Windowed = FALSE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferWidth = w;
    pp.BackBufferHeight = h;
    pp.BackBufferCount = 1;
    pp.hDeviceWindow = hwnd;
    pp.FullScreen_RefreshRateInHz = 0;
    pp.PresentationInterval = D3DPRESENT_INTERVAL_ONE;
    hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
                                 D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { printf("CreateDevice %ux%u plein ecran : %08lx\n", w, h, hr); return 4; }

    GetWindowRect(hwnd, &wr);
    GetClientRect(hwnd, &rc);
    printf("mode %ux%u ; ecran %dx%d ; fenetre %ld,%ld-%ld,%ld ; client %ldx%ld\n", w, h,
           GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN),
           wr.left, wr.top, wr.right, wr.bottom, rc.right, rc.bottom);
    fflush(stdout);

    for (debut = GetTickCount(); GetTickCount() - debut < duree;)
    {
        D3DRECT gauche = {0, 0, w / 8, h}, droite = {w - w / 8, 0, w, h};

        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT)
            {
                printf("WM_QUIT (%lu) apres %d images\n", (unsigned long)msg.wParam, images);
                duree = 0;
            }
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0, 0, 255), 1.0f, 0);
        IDirect3DDevice9_Clear(dev, 1, &gauche, D3DCLEAR_TARGET, D3DCOLOR_XRGB(255, 0, 0), 1.0f, 0);
        IDirect3DDevice9_Clear(dev, 1, &droite, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0, 255, 0), 1.0f, 0);
        if (FAILED(hr = IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL)))
        {
            printf("Present : %08lx apres %d images\n", hr, images);
            break;
        }
        if (!images++) { printf("PRET\n"); fflush(stdout); }
    }
    printf("%d images presentees\n", images);
    IDirect3DDevice9_Release(dev);
    IDirect3D9_Release(d3d);
    DestroyWindow(hwnd);
    return images ? 0 : 5;
}
