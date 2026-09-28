/*
 * Invite i386 : creer et detruire la chaine d'echange, en boucle.
 *
 * Le second gel de DREDGE tombe entre la fin de la creation du peripherique
 * D3D11 et la creation de la chaine d'echange -- la trace de DXVK s'arrete
 * pile entre les conversions de formats et « Presenter: Actual swapchain
 * properties ». Ce chemin passe par user32, win32u, le pilote Mac et la
 * creation d'une surface Vulkan, donc par le fil principal de Cocoa.
 *
 * On le parcourt en boucle, avec un chien de garde : attendre le jeu pour
 * reproduire coute dix minutes par essai, ce test doit couter dix secondes.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

#define TOURS 60
#define L 640
#define H 360

static volatile LONG tour;
static volatile LONG fini;
static const char *etape = "depart";

static DWORD WINAPI chien_de_garde( void *p )
{
    LONG vu = -1;
    int immobile = 0;

    while (!fini)
    {
        LONG n = tour;

        if (n == vu)
        {
            if (++immobile >= 30)
            {
                printf( "BLOQUE au tour %ld, etape \"%s\"\n", n, etape );
                fflush( stdout );
                ExitProcess( 1 );
            }
        }
        else { immobile = 0; vu = n; }
        Sleep( 1000 );
    }
    return 0;
}

static LRESULT CALLBACK proc( HWND h, UINT m, WPARAM w, LPARAM l )
{
    return DefWindowProcW( h, m, w, l );
}

static void pomper( HWND h )
{
    MSG msg;
    while (PeekMessageW( &msg, NULL, 0, 0, PM_REMOVE ))
    {
        TranslateMessage( &msg );
        DispatchMessageW( &msg );
    }
    (void)h;
}

int main(void)
{
    WNDCLASSEXW wc = { sizeof(wc) };
    LONG i;
    int echecs = 0;

    wc.lpfnWndProc   = proc;
    wc.hInstance     = GetModuleHandleW( NULL );
    wc.lpszClassName = L"essai_swap";
    RegisterClassExW( &wc );
    CreateThread( NULL, 0, chien_de_garde, NULL, 0, NULL );

    for (i = 0; i < TOURS; i++)
    {
        DXGI_SWAP_CHAIN_DESC sd = { 0 };
        ID3D11Device *dev = NULL;
        ID3D11DeviceContext *ctx = NULL;
        IDXGISwapChain *sw = NULL;
        ID3D11Texture2D *dos = NULL;
        ID3D11RenderTargetView *cible = NULL;
        D3D_FEATURE_LEVEL niveau;
        float vert[4] = { 0.f, 1.f, 0.f, 1.f };
        HWND hwnd;
        HRESULT hr;
        int f;

        etape = "CreateWindowEx";
        hwnd = CreateWindowExW( 0, L"essai_swap", L"essai", WS_OVERLAPPEDWINDOW,
                                CW_USEDEFAULT, CW_USEDEFAULT, L, H, NULL, NULL, wc.hInstance, NULL );
        if (!hwnd) { printf( "CreateWindowEx : %lu\n", GetLastError() ); return 2; }
        ShowWindow( hwnd, SW_SHOW );
        pomper( hwnd );

        sd.BufferCount       = 2;
        sd.BufferDesc.Width  = L;
        sd.BufferDesc.Height = H;
        sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        sd.BufferUsage       = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow      = hwnd;
        sd.SampleDesc.Count  = 1;
        sd.Windowed          = TRUE;

        etape = "D3D11CreateDeviceAndSwapChain";
        hr = D3D11CreateDeviceAndSwapChain( NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                            D3D11_SDK_VERSION, &sd, &sw, &dev, &niveau, &ctx );
        if (FAILED( hr ))
        {
            printf( "tour %ld : creation hr=%#lx\n", i, (unsigned long)hr );
            echecs++;
            DestroyWindow( hwnd );
            InterlockedIncrement( &tour );
            continue;
        }

        etape = "GetBuffer";
        hr = IDXGISwapChain_GetBuffer( sw, 0, &IID_ID3D11Texture2D, (void **)&dos );
        if (SUCCEEDED( hr ))
        {
            ID3D11Device_CreateRenderTargetView( dev, (ID3D11Resource *)dos, NULL, &cible );
            for (f = 0; f < 2; f++)
            {
                etape = "ClearRenderTargetView + Present";
                if (cible) ID3D11DeviceContext_ClearRenderTargetView( ctx, cible, vert );
                IDXGISwapChain_Present( sw, 0, 0 );
                pomper( hwnd );
            }
        }

        etape = "liberation";
        if (cible) ID3D11RenderTargetView_Release( cible );
        if (dos) ID3D11Texture2D_Release( dos );
        if (sw) { IDXGISwapChain_SetFullscreenState( sw, FALSE, NULL ); IDXGISwapChain_Release( sw ); }
        if (ctx) ID3D11DeviceContext_Release( ctx );
        if (dev) ID3D11Device_Release( dev );
        DestroyWindow( hwnd );
        pomper( hwnd );

        InterlockedIncrement( &tour );
        if ((i + 1) % 10 == 0) { printf( "  %ld tours\n", i + 1 ); fflush( stdout ); }
    }

    fini = 1;
    printf( "i386 chaine d'echange : %s (%d tours, %d echecs de creation)\n",
            echecs ? "ECART" : "ok", TOURS, echecs );
    return echecs ? 1 : 0;
}
