/* Temoin Direct3D 9 : ce que fait un vieux jeu au demarrage, et rien d'autre.
 *
 * Direct3DCreate9, adaptateur par defaut (GetAdapterIdentifier dit qui repond :
 * DXVK annonce un GPU AMD, wined3d le pilote OpenGL), GetDeviceCaps, CreateDevice
 * fenetre (materiel, a defaut logiciel), Clear d'une couleur connue, Present,
 * puis relecture du pixel par GetRenderTargetData. Code de sortie 0 si le pixel
 * relu est le bon.
 *
 * Fahrenheit Remastered (312840, i386) ouvrait une erreur Direct3D au demarrage
 * avec le d3d9 builtin de Wine ; le lanceur pose desormais le d3d9 i386 de DXVK
 * (option d3d9). Construit en i686 et en x86_64 :
 *   i686-w64-mingw32-gcc -O1 -o probe_d3d9_32.exe probe_d3d9.c -ld3d9
 */
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

#define COULEUR 0x00336699u

int main(void)
{
    WNDCLASSA wc = { 0 };
    HWND hwnd;
    IDirect3D9 *d3d;
    D3DADAPTER_IDENTIFIER9 id;
    D3DCAPS9 caps;
    D3DPRESENT_PARAMETERS pp = { 0 };
    IDirect3DDevice9 *dev = NULL;
    IDirect3DSurface9 *rt = NULL, *sys = NULL;
    D3DLOCKED_RECT lr;
    HRESULT hr;
    DWORD px;
    const char *mode = "materiel";

    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "probe_d3d9";
    RegisterClassA(&wc);
    hwnd = CreateWindowA("probe_d3d9", "probe_d3d9", WS_OVERLAPPEDWINDOW, 0, 0, 320, 240, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("CreateWindow echoue (%lu)\n", GetLastError()); return 2; }

    d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) { printf("Direct3DCreate9 = NULL\n"); return 3; }
    printf("adaptateurs : %u\n", IDirect3D9_GetAdapterCount(d3d));
    hr = IDirect3D9_GetAdapterIdentifier(d3d, D3DADAPTER_DEFAULT, 0, &id);
    if (FAILED(hr)) { printf("GetAdapterIdentifier = %08lx\n", hr); return 4; }
    printf("adaptateur  : %s (pilote %s, vendeur %04lx)\n", id.Description, id.Driver, id.VendorId);
    hr = IDirect3D9_GetDeviceCaps(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, &caps);
    printf("GetDeviceCaps = %08lx  VS %lu.%lu  PS %lu.%lu\n", hr,
           (caps.VertexShaderVersion >> 8) & 0xff, caps.VertexShaderVersion & 0xff,
           (caps.PixelShaderVersion >> 8) & 0xff, caps.PixelShaderVersion & 0xff);

    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferWidth = 320;
    pp.BackBufferHeight = 240;
    pp.hDeviceWindow = hwnd;
    hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
                                 D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) {
        printf("CreateDevice (materiel) = %08lx\n", hr);
        mode = "logiciel";
        hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
                                     D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
    }
    if (FAILED(hr)) { printf("CreateDevice (logiciel) = %08lx\n", hr); return 5; }
    printf("CreateDevice (%s) = 0\n", mode);

    IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, COULEUR, 1.0f, 0);
    hr = IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
    printf("Present = %08lx\n", hr);
    IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, COULEUR, 1.0f, 0);
    IDirect3DDevice9_GetRenderTarget(dev, 0, &rt);
    IDirect3DDevice9_CreateOffscreenPlainSurface(dev, 320, 240, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &sys, NULL);
    hr = IDirect3DDevice9_GetRenderTargetData(dev, rt, sys);
    if (FAILED(hr)) { printf("GetRenderTargetData = %08lx\n", hr); return 6; }
    IDirect3DSurface9_LockRect(sys, &lr, NULL, D3DLOCK_READONLY);
    px = ((DWORD *)lr.pBits)[0] & 0x00ffffff;
    IDirect3DSurface9_UnlockRect(sys);
    printf("pixel relu : %06lx (attendu %06x) -> %s\n", px, COULEUR, px == COULEUR ? "OK" : "FAUX");

    IDirect3DSurface9_Release(sys);
    IDirect3DSurface9_Release(rt);
    IDirect3DDevice9_Release(dev);
    IDirect3D9_Release(d3d);
    DestroyWindow(hwnd);
    return px == COULEUR ? 0 : 7;
}
