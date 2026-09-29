/*
 * Invite i386 : la chaine d'echange pendant que les verrous travaillent.
 *
 * h32swap cree et detruit soixante fois fenetre, peripherique D3D11 et chaine
 * d'echange sans broncher. Le gel de DREDGE tombe pourtant pile la. Ce que le
 * jeu a en plus, c'est son systeme de travaux : une vingtaine de fils qui se
 * disputent verrous SRW et variables de condition pendant que le fil principal
 * ouvre le peripherique graphique.
 *
 * On reunit les deux, avec un chien de garde. Le but n'est pas de verifier un
 * resultat mais de reproduire un blocage en dix secondes plutot qu'en dix
 * minutes.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

#define TOURS 40
#define FILS  16
#define L 640
#define H 360

static SRWLOCK srw[4];
static CONDITION_VARIABLE cv;
static CRITICAL_SECTION cv_section;
static volatile LONG cv_pret;
static volatile LONG travaux;
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
            if (++immobile >= 40)
            {
                printf( "BLOQUE au tour %ld, etape \"%s\" (travaux=%ld)\n", n, etape, travaux );
                fflush( stdout );
                ExitProcess( 1 );
            }
        }
        else { immobile = 0; vu = n; }
        Sleep( 1000 );
    }
    return 0;
}

static DWORD WINAPI travailleur( void *p )
{
    LONG moi = (LONG)(ULONG_PTR)p;

    while (!fini)
    {
        int k = (int)(travaux & 3);

        if (moi & 1)
        {
            AcquireSRWLockExclusive( &srw[k] );
            InterlockedIncrement( &travaux );
            ReleaseSRWLockExclusive( &srw[k] );
        }
        else
        {
            AcquireSRWLockShared( &srw[k] );
            InterlockedIncrement( &travaux );
            ReleaseSRWLockShared( &srw[k] );
        }

        if (!(moi & 3))
        {
            EnterCriticalSection( &cv_section );
            cv_pret = 1;
            WakeAllConditionVariable( &cv );
            LeaveCriticalSection( &cv_section );
        }
        else if ((moi & 3) == 1)
        {
            EnterCriticalSection( &cv_section );
            while (!cv_pret && !fini) SleepConditionVariableCS( &cv, &cv_section, 50 );
            cv_pret = 0;
            LeaveCriticalSection( &cv_section );
        }
    }
    return 0;
}

static LRESULT CALLBACK proc( HWND h, UINT m, WPARAM w, LPARAM l )
{
    return DefWindowProcW( h, m, w, l );
}

static void pomper(void)
{
    MSG msg;
    while (PeekMessageW( &msg, NULL, 0, 0, PM_REMOVE )) { TranslateMessage( &msg ); DispatchMessageW( &msg ); }
}

int main(void)
{
    WNDCLASSEXW wc = { sizeof(wc) };
    HANDLE h[FILS];
    LONG i;
    int echecs = 0, n;

    wc.lpfnWndProc   = proc;
    wc.hInstance     = GetModuleHandleW( NULL );
    wc.lpszClassName = L"essai_swap2";
    RegisterClassExW( &wc );
    for (n = 0; n < 4; n++) InitializeSRWLock( &srw[n] );
    InitializeCriticalSection( &cv_section );
    InitializeConditionVariable( &cv );
    CreateThread( NULL, 0, chien_de_garde, NULL, 0, NULL );
    for (n = 0; n < FILS; n++) h[n] = CreateThread( NULL, 0, travailleur, (void *)(ULONG_PTR)n, 0, NULL );

    for (i = 0; i < TOURS; i++)
    {
        DXGI_SWAP_CHAIN_DESC sd = { 0 };
        ID3D11Device *dev = NULL;
        ID3D11DeviceContext *ctx = NULL;
        IDXGISwapChain *sw = NULL;
        D3D_FEATURE_LEVEL niveau;
        HWND hwnd;
        HRESULT hr;

        etape = "CreateWindowEx";
        hwnd = CreateWindowExW( 0, L"essai_swap2", L"essai", WS_OVERLAPPEDWINDOW,
                                CW_USEDEFAULT, CW_USEDEFAULT, L, H, NULL, NULL, wc.hInstance, NULL );
        if (!hwnd) { printf( "CreateWindowEx : %lu\n", GetLastError() ); break; }
        ShowWindow( hwnd, SW_SHOW );
        pomper();

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
        if (FAILED( hr )) { echecs++; }
        else
        {
            etape = "Present";
            IDXGISwapChain_Present( sw, 0, 0 );
            pomper();
            etape = "liberation";
            IDXGISwapChain_Release( sw );
            ID3D11DeviceContext_Release( ctx );
            ID3D11Device_Release( dev );
        }
        DestroyWindow( hwnd );
        pomper();
        InterlockedIncrement( &tour );
        if ((i + 1) % 10 == 0) { printf( "  %ld tours (travaux=%ld)\n", i + 1, travaux ); fflush( stdout ); }
    }

    fini = 1;
    for (n = 0; n < FILS; n++) WaitForSingleObject( h[n], 3000 );
    printf( "i386 chaine d'echange sous charge : %s (%d tours, %d echecs, %ld travaux)\n",
            echecs ? "ECART" : "ok", TOURS, echecs, travaux );
    return echecs ? 1 : 0;
}
