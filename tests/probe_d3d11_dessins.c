/* Sonde D3D11 pour les compteurs de dessins par passe de DXMT (patch 0115,
 * DXMT_COUNTERS=1) : une fenetre, une swapchain, et par image deux passes dont
 * on connait le contenu exact, pour comparer aux lignes DXMT_DESSINS du journal.
 *
 *   passe « ombres » : 256x256, profondeur seule Depth16, pas de pixel shader
 *      5 x DrawIndexed(300)                    -> 1500 sommets
 *      2 x DrawIndexedInstanced(30, 100)       -> 6000 sommets
 *      attendu : dessins/img=7 sommets/img=7500 p10=256 p50=256 p90=2560 moy=1071
 *                <64=0% <256=0% <1024=71% indexes=100% instancies=29%
 *                (inst/dessin=29 sommets/instance=222) indirects=0%
 *   passe « couleur » : back buffer 320x240
 *      1 x Draw(3), 3 x Draw(60)               -> 183 sommets
 *      1 x DrawInstanced(6, 50)                -> 300 sommets
 *      1 x DrawIndexed(1200)                   -> 1200 sommets
 *      1 x DrawInstancedIndirect, 1 x DrawIndexedInstancedIndirect (comptes sans sommets)
 *      attendu : dessins/img=8 sommets/img=1683 p10=3 p50=56 p90=1024 moy=280
 *                <64=67% <256=67% <1024=83% indexes=25% instancies=13%
 *                (inst/dessin=9 sommets/instance=231) indirects=25%
 *
 * (p10/p50/p90 = borne basse de la classe en quart d'octave : 60 -> 56, 300 -> 256,
 * 3000 -> 2560, 1200 -> 1024.) Les sommets sont fabriques par SV_VertexID et
 * SV_InstanceID : aucun tampon de sommets, un tampon d'index 0..5999.
 *
 * Construction (PE x86-64, donc le chemin arm64ec de DXMT que prend un jeu) :
 *   toolchain/llvm-mingw/bin/x86_64-w64-mingw32-gcc -O1 -o build/probe_d3d11_dessins.exe \
 *      tests/probe_d3d11_dessins.c -ldxguid -luuid -luser32
 * Lancement (DLL de src/dxmt/build-essai copiees dans <dll>/aarch64-windows et
 * winemetal.so dans <dll>/aarch64-unix) :
 *   WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11,d3d10core,winemetal=b" WINEDLLPATH=<dll> \
 *   DXMT_COUNTERS=1 DXMT_COUNTERS_INTERVAL=10 DXMT_LOG_LEVEL=warn \
 *      sh tests/etape2_pile_arm64ec.sh build/probe_d3d11_dessins.exe [images=25]
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <d3d11.h>
#include <d3dcompiler.h>

typedef HRESULT (WINAPI *PFN_CREATE)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                     const D3D_FEATURE_LEVEL *, UINT, UINT,
                                     const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **,
                                     ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *PFN_COMPILE)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *,
                                      ID3DInclude *, LPCSTR, LPCSTR, UINT, UINT,
                                      ID3DBlob **, ID3DBlob **);

static const char *HLSL =
"struct VSOut { float4 pos : SV_Position; };\n"
"VSOut vs_main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {\n"
"   float a = (vid % 3) * 2.0943951 + iid * 0.1;\n"
"   float2 c = float2(((vid / 3) % 16) / 8.0 - 0.95, (iid % 16) / 8.0 - 0.95);\n"
"   VSOut o; o.pos = float4(c + 0.05 * float2(cos(a), sin(a)), 0.5, 1); return o;\n"
"}\n"
"float4 ps_main(VSOut i) : SV_Target { return float4(0.2, 0.6, 0.9, 1); }\n";

#define W 320
#define H 240
#define OK(expr, quoi) do { if (FAILED(expr)) { printf("ECHEC: %s\n", quoi); return 1; } } while (0)

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
   if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
   return DefWindowProcW(h, m, w, l);
}

int main(int argc, char **argv)
{
   int images = argc > 1 ? atoi(argv[1]) : 25;
   HMODULE hd = LoadLibraryA("d3d11.dll");
   HMODULE hc = LoadLibraryA("d3dcompiler_47.dll");
   if (!hd || !hc) { printf("ECHEC: DLL manquante\n"); return 1; }
   PFN_CREATE creer = (PFN_CREATE)(void *)GetProcAddress(hd, "D3D11CreateDeviceAndSwapChain");
   PFN_COMPILE compiler_hlsl = (PFN_COMPILE)(void *)GetProcAddress(hc, "D3DCompile");
   if (!creer || !compiler_hlsl) { printf("ECHEC: point d'entree manquant\n"); return 1; }

   WNDCLASSEXW wc = { .cbSize = sizeof wc, .lpfnWndProc = wndproc, .hInstance = GetModuleHandleW(NULL),
                      .lpszClassName = L"sonde_dessins" };
   RegisterClassExW(&wc);
   HWND hwnd = CreateWindowExW(0, wc.lpszClassName, L"sonde dessins DXMT", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                               60, 60, W, H, NULL, NULL, wc.hInstance, NULL);
   if (!hwnd) { printf("ECHEC: fenetre\n"); return 1; }

   DXGI_SWAP_CHAIN_DESC scd = { .BufferDesc = { .Width = W, .Height = H, .Format = DXGI_FORMAT_R8G8B8A8_UNORM },
      .SampleDesc = {1, 0}, .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT, .BufferCount = 2,
      .OutputWindow = hwnd, .Windowed = TRUE, .SwapEffect = DXGI_SWAP_EFFECT_DISCARD };
   const D3D_FEATURE_LEVEL fls[] = { D3D_FEATURE_LEVEL_11_0 };
   IDXGISwapChain *sc = NULL; ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL fl;
   OK(creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, fls, 1, D3D11_SDK_VERSION, &scd, &sc, &dev, &fl, &ctx),
      "peripherique + swapchain");

   ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
   OK(compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "vs_main", "vs_5_0", 0, 0, &vsb, &err), "compilation VS");
   OK(compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "ps_main", "ps_5_0", 0, 0, &psb, &err), "compilation PS");
   ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
   OK(ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs), "VS");
   OK(ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps), "PS");

   ID3D11Texture2D *bb = NULL; ID3D11RenderTargetView *rtv = NULL;
   OK(IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb), "back buffer");
   OK(ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv), "RTV");

   D3D11_TEXTURE2D_DESC dd = { .Width = 256, .Height = 256, .MipLevels = 1, .ArraySize = 1, .Format = DXGI_FORMAT_D16_UNORM,
      .SampleDesc = {1, 0}, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_DEPTH_STENCIL };
   ID3D11Texture2D *dt = NULL; ID3D11DepthStencilView *dsv = NULL;
   OK(ID3D11Device_CreateTexture2D(dev, &dd, NULL, &dt), "texture de profondeur");
   OK(ID3D11Device_CreateDepthStencilView(dev, (ID3D11Resource *)dt, NULL, &dsv), "DSV");

   static unsigned short index[6000];
   for (int i = 0; i < 6000; i++) index[i] = (unsigned short)i;
   D3D11_BUFFER_DESC ibd = { .ByteWidth = sizeof index, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_INDEX_BUFFER };
   D3D11_SUBRESOURCE_DATA ibi = { .pSysMem = index };
   ID3D11Buffer *ib = NULL;
   OK(ID3D11Device_CreateBuffer(dev, &ibd, &ibi, &ib), "tampon d'index");

   /* [0] DrawInstancedIndirect : 30 sommets x 2 ; [16] DrawIndexedInstancedIndirect : 90 index x 3 */
   static const unsigned args[9] = { 30, 2, 0, 0,   90, 3, 0, 0, 0 };
   D3D11_BUFFER_DESC abd = { .ByteWidth = sizeof args, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_UNORDERED_ACCESS,
      .MiscFlags = D3D11_RESOURCE_MISC_DRAWINDIRECT_ARGS };
   D3D11_SUBRESOURCE_DATA abi = { .pSysMem = args };
   ID3D11Buffer *ab = NULL;
   OK(ID3D11Device_CreateBuffer(dev, &abd, &abi, &ab), "tampon d'arguments indirects");

   ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
   ID3D11DeviceContext_IASetIndexBuffer(ctx, ib, DXGI_FORMAT_R16_UINT, 0);
   ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);

   int presentees = 0;
   for (int n = 0; n < images; n++) {
      MSG msg;
      while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }

      /* passe « ombres » : profondeur seule */
      D3D11_VIEWPORT vo = { 0, 0, 256, 256, 0, 1 };
      ID3D11DeviceContext_RSSetViewports(ctx, 1, &vo);
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, dsv);
      ID3D11DeviceContext_ClearDepthStencilView(ctx, dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
      ID3D11DeviceContext_PSSetShader(ctx, NULL, NULL, 0);
      for (int i = 0; i < 5; i++) ID3D11DeviceContext_DrawIndexed(ctx, 300, i * 300, 0);
      for (int i = 0; i < 2; i++) ID3D11DeviceContext_DrawIndexedInstanced(ctx, 30, 100, 0, 0, 0);

      /* passe « couleur » : back buffer */
      D3D11_VIEWPORT vc = { 0, 0, W, H, 0, 1 };
      const float fond[4] = { 0.05f, 0.05f, 0.1f, 1 };
      ID3D11DeviceContext_RSSetViewports(ctx, 1, &vc);
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
      ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, fond);
      ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
      ID3D11DeviceContext_Draw(ctx, 3, 0);
      for (int i = 0; i < 3; i++) ID3D11DeviceContext_Draw(ctx, 60, 0);
      ID3D11DeviceContext_DrawInstanced(ctx, 6, 50, 0, 0);
      ID3D11DeviceContext_DrawIndexed(ctx, 1200, 0, 0);
      ID3D11DeviceContext_DrawInstancedIndirect(ctx, ab, 0);
      ID3D11DeviceContext_DrawIndexedInstancedIndirect(ctx, ab, 16);

      ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, NULL);
      if (SUCCEEDED(IDXGISwapChain_Present(sc, 0, 0))) presentees++;
   }

   /* Tout liberer : les lignes « sortie » sortent a la destruction du contexte d'encodage. */
   ID3D11DeviceContext_ClearState(ctx);
   ID3D11DeviceContext_Flush(ctx);
   ID3D11Buffer_Release(ab); ID3D11Buffer_Release(ib);
   ID3D11DepthStencilView_Release(dsv); ID3D11Texture2D_Release(dt);
   ID3D11RenderTargetView_Release(rtv); ID3D11Texture2D_Release(bb);
   ID3D11PixelShader_Release(ps); ID3D11VertexShader_Release(vs);
   IDXGISwapChain_Release(sc);
   ID3D11DeviceContext_Release(ctx);
   ULONG reste = ID3D11Device_Release(dev);
   DestroyWindow(hwnd);
   printf("RESULTAT: %d images presentees sur %d (references restantes sur le peripherique : %lu)\n",
          presentees, images, (unsigned long)reste);
   return presentees == images ? 0 : 1;
}
