/* Sonde D3D11 : l'initialisation de Heaps/HashLink (Dead Cells), appel pour appel.
 *
 * Le 2026-10-13 Dead Cells lance « en DXMT » s'arrete sur « Failed to initialize
 * DirectX driver (DXError 887A0004 line 112) » : DXGI_ERROR_UNSUPPORTED rendu par
 * la primitive dx_create de HashLink (libs/directx/directx.cpp), c'est-a-dire par
 * D3D11CreateDeviceAndSwapChain. deadcells.exe est un PE32 i386 ; la sonde se
 * compile donc dans les deux largeurs (i686 et x86_64) et dit, a chaque etape, le
 * HRESULT et QUI a repondu : le d3d11.dll charge est-il celui de DXMT (il tire
 * winemetal.dll) ou le builtin de Wine (il tire wined3d.dll) ?
 *
 * Sequence, celle de h3d.impl.DirectXDriver.reset() puis resize() :
 *   1. fenetre, GetClientRect ; DXGI_SWAP_CHAIN_DESC : R8G8B8A8_UNORM, 1 echantillon,
 *      RENDER_TARGET_OUTPUT, 2 tampons, FLIP_DISCARD, fenetre ; niveaux 11_1 -> 9_1,
 *      drapeaux 0 ; D3D11CreateDeviceAndSwapChain(NULL, HARDWARE, ...) ; sur
 *      E_INVALIDARG, second essai sans liste de niveaux (comme HashLink) ;
 *   2. ResizeBuffers(2, l, h, R8G8B8A8_UNORM, 0) ;
 *   3. profondeur R24G8_TYPELESS (DEPTH_STENCIL | SHADER_RESOURCE), deux vues
 *      D24_UNORM_S8_UINT (dont une en lecture seule), une vue R24_UNORM_X8_TYPELESS ;
 *   4. GetBuffer(0), vue de rendu, effacement ;
 *   5. un triangle : tampon de sommets DYNAMIC rempli par Map(WRITE_DISCARD), shaders
 *      compiles par D3DCompile (le jeu embarque d3dcompiler_47.dll) ;
 *   6. relecture par une texture STAGING (Map READ) : centre = triangle, coin = fond ;
 *   7. Present(1, 0), trois fois.
 * Les etapes 5 et 6 passent par la memoire que DXMT i386 place lui-meme sous les
 * tampons Metal (BufferAllocationFlag::CpuPlaced) : c'est la que des pages hotes de
 * 16 Kio se verraient.
 *
 * Sortie : une ligne par etape, « FIN ok » si tout a rendu S_OK et que les deux
 * pixels sont justes. Lanceur : tests/sonde_heaps.sh.
 *
 *   probe_d3d11_heaps.exe                          la sequence ci-dessus, fenetre cachee
 *   probe_d3d11_heaps.exe plein <secondes> <mode>  fenetre montree, puis le plein ecran de
 *       Heaps et une boucle de rendu (fond bleu, triangle rouge, Present(1, 0)), une ligne
 *       d'etat par seconde. mode : 0 = sans bordure seul (WS_POPUP qui couvre l'ecran),
 *       1 = sans bordure puis SetFullscreenState(TRUE) (plein ecran exclusif de DXGI,
 *       c'est lui qui change le mode d'ecran), 2 = SetFullscreenState(TRUE) seul.
 *       A regarder a l'ecran ou par capture : la sonde ne sait pas ce qui s'affiche.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <d3d11.h>
#include <d3dcompiler.h>

typedef HRESULT (WINAPI *PFN_CREATE_SC)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                        const D3D_FEATURE_LEVEL *, UINT, UINT,
                                        const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **,
                                        ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *PFN_COMPILE)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *,
                                      ID3DInclude *, LPCSTR, LPCSTR, UINT, UINT,
                                      ID3DBlob **, ID3DBlob **);

static const char *HLSL =
   "struct V2P { float4 pos : SV_Position; float4 coul : COLOR; };\n"
   "V2P vs(float2 p : POSITION, float4 c : COLOR) { V2P o; o.pos = float4(p, 0.5, 1); o.coul = c; return o; }\n"
   "float4 ps(V2P i) : SV_Target { return i.coul; }\n";

static int echecs;

static void etape(const char *quoi, HRESULT hr)
{
   printf("%-58s hr=%08lX%s\n", quoi, (unsigned long)hr, FAILED(hr) ? "  ECHEC" : "");
   fflush(stdout);
   if (FAILED(hr)) echecs++;
}

/* Qui a repondu : chemin du d3d11.dll charge, et lequel de winemetal / wined3d il a tire. */
static void qui(void)
{
   char chemin[MAX_PATH] = "?";
   HMODULE h = GetModuleHandleA("d3d11.dll");
   int metal = GetModuleHandleA("winemetal.dll") != NULL;
   int wined3d = GetModuleHandleA("wined3d.dll") != NULL;
   int vulkan = GetModuleHandleA("winevulkan.dll") != NULL || GetModuleHandleA("vulkan-1.dll") != NULL;
   if (h) GetModuleFileNameA(h, chemin, sizeof chemin);
   printf("d3d11.dll charge : %s\n", chemin);
   printf("rendu : %s (winemetal.dll %s, wined3d.dll %s, vulkan %s)\n",
          metal ? "DXMT" : wined3d ? "builtin Wine (wined3d)" : vulkan ? "DXVK" : "inconnu",
          metal ? "charge" : "absent", wined3d ? "charge" : "absent", vulkan ? "charge" : "absent");
   fflush(stdout);
}

static ID3DBlob *compiler(PFN_COMPILE compiler_hlsl, const char *entree, const char *cible)
{
   ID3DBlob *b = NULL, *err = NULL;
   HRESULT hr = compiler_hlsl ? compiler_hlsl(HLSL, strlen(HLSL), "sonde_heaps.hlsl", NULL, NULL, entree, cible, 0, 0, &b, &err)
                              : E_NOINTERFACE;
   char quoi[64];
   snprintf(quoi, sizeof quoi, "D3DCompile %s (%s)", entree, cible);
   etape(quoi, hr);
   return b;
}

static LRESULT CALLBACK procedure(HWND h, UINT m, WPARAM w, LPARAM l)
{
   if (m == WM_CLOSE) { PostQuitMessage(0); return 0; }
   return DefWindowProcA(h, m, w, l);
}

/* Le plein ecran de Heaps, puis une boucle de rendu : ce que fait le jeu une fois lance. */
static int boucle_plein(HWND fenetre, IDXGISwapChain *chaine, ID3D11Device *dev, ID3D11DeviceContext *ctx,
                        ID3D11RenderTargetView *cible, int secondes, int mode)
{
   static const float bleu[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
   UINT largeur = 0, hauteur = 0, images = 0;
   DWORD debut, derniere;
   HRESULT hr;
   RECT r;

   if (mode == 0 || mode == 1) {
      /* win_set_fullscreen de HashLink : WS_POPUP, la fenetre couvre son ecran */
      MONITORINFO mi = { sizeof mi };
      GetMonitorInfoA(MonitorFromWindow(fenetre, MONITOR_DEFAULTTOPRIMARY), &mi);
      SetWindowLongA(fenetre, GWL_STYLE, WS_POPUP | WS_VISIBLE);
      SetWindowPos(fenetre, NULL, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top, SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      printf("sans bordure : ecran %ldx%ld\n", mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top);
   }
   if (mode == 1 || mode == 2) etape("SetFullscreenState(TRUE)", IDXGISwapChain_SetFullscreenState(chaine, TRUE, NULL));

   debut = derniere = GetTickCount();
   for (;;) {
      MSG msg;
      DWORD t = GetTickCount();
      while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
         if (msg.message == WM_QUIT) goto fin;
         TranslateMessage(&msg); DispatchMessageA(&msg);
      }
      if (t - debut >= (DWORD)secondes * 1000) break;

      /* Driver.resize de Heaps : le tampon suit la zone cliente */
      GetClientRect(fenetre, &r);
      if (r.right > 0 && r.bottom > 0 && ((UINT)r.right != largeur || (UINT)r.bottom != hauteur)) {
         ID3D11Texture2D *fond = NULL;
         char quoi[80];
         largeur = r.right; hauteur = r.bottom;
         ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, NULL);
         if (cible) ID3D11RenderTargetView_Release(cible);
         cible = NULL;
         snprintf(quoi, sizeof quoi, "ResizeBuffers(2, %u, %u)", largeur, hauteur);
         etape(quoi, IDXGISwapChain_ResizeBuffers(chaine, 2, largeur, hauteur, DXGI_FORMAT_R8G8B8A8_UNORM, 0));
         hr = IDXGISwapChain_GetBuffer(chaine, 0, &IID_ID3D11Texture2D, (void **)&fond);
         if (SUCCEEDED(hr)) hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)fond, NULL, &cible);
         if (fond) ID3D11Texture2D_Release(fond);
         if (FAILED(hr)) { etape("cible apres ResizeBuffers", hr); break; }
      }
      if (!cible) { Sleep(10); continue; }

      D3D11_VIEWPORT vue = { 0, 0, (float)largeur, (float)hauteur, 0, 1 };
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &cible, NULL);
      ID3D11DeviceContext_RSSetViewports(ctx, 1, &vue);
      ID3D11DeviceContext_ClearRenderTargetView(ctx, cible, bleu);
      ID3D11DeviceContext_Draw(ctx, 3, 0);
      hr = IDXGISwapChain_Present(chaine, 1, 0);
      if (FAILED(hr)) { etape("Present(1, 0)", hr); break; }
      images++;

      if (t - derniere >= 1000) {
         BOOL plein = FALSE;
         RECT f;
         IDXGISwapChain_GetFullscreenState(chaine, &plein, NULL);
         GetWindowRect(fenetre, &f);
         printf("t=%lus images=%u exclusif=%d tampon=%ux%u fenetre=%ldx%ld a %ld,%ld premier_plan=%d\n",
                (unsigned long)((t - debut) / 1000), images, (int)plein, largeur, hauteur,
                f.right - f.left, f.bottom - f.top, f.left, f.top, GetForegroundWindow() == fenetre);
         fflush(stdout);
         derniere = t;
      }
   }
fin:
   if (mode == 1 || mode == 2) etape("SetFullscreenState(FALSE)", IDXGISwapChain_SetFullscreenState(chaine, FALSE, NULL));
   printf("FIN %s (%u images)\n", !echecs && images ? "ok" : "echec", images);
   fflush(stdout);
   return !echecs && images ? 0 : 1;
}

int main(int argc, char **argv)
{
   int plein = argc > 1 && !strcmp(argv[1], "plein");
   int plein_secondes = argc > 2 ? atoi(argv[2]) : 10, plein_mode = argc > 3 ? atoi(argv[3]) : 1;

   static const D3D_FEATURE_LEVEL niveaux[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
      D3D_FEATURE_LEVEL_9_3, D3D_FEATURE_LEVEL_9_2, D3D_FEATURE_LEVEL_9_1,
   };
   enum { NB_NIVEAUX = sizeof niveaux / sizeof niveaux[0], L = 640, H = 360 };
   DXGI_SWAP_CHAIN_DESC desc;
   IDXGISwapChain *chaine = NULL;
   ID3D11Device *dev = NULL;
   ID3D11DeviceContext *ctx = NULL;
   D3D_FEATURE_LEVEL niveau = 0;
   RECT r;
   HRESULT hr;

   printf("sonde heaps : invite %u bits\n", (unsigned)(sizeof(void *) * 8));

   /* la fenetre n'est pas montree : la sonde ne prend le premier plan a personne */
   WNDCLASSA wc = { 0 };
   wc.lpfnWndProc = procedure;
   wc.hInstance = GetModuleHandleA(NULL);
   wc.lpszClassName = "SondeHeaps";
   RegisterClassA(&wc);
   RECT cadre = { 0, 0, L, H };
   AdjustWindowRect(&cadre, WS_OVERLAPPEDWINDOW, FALSE);
   HWND fenetre = CreateWindowA("SondeHeaps", "sonde heaps", WS_OVERLAPPEDWINDOW, 0, 0,
                                cadre.right - cadre.left, cadre.bottom - cadre.top, NULL, NULL, wc.hInstance, NULL);
   if (!fenetre) { printf("ECHEC: pas de fenetre\n"); return 1; }
   if (plein) { ShowWindow(fenetre, SW_SHOW); UpdateWindow(fenetre); }
   GetClientRect(fenetre, &r);

   HMODULE hd = LoadLibraryA("d3d11.dll");
   PFN_CREATE_SC creer = hd ? (PFN_CREATE_SC)(void *)GetProcAddress(hd, "D3D11CreateDeviceAndSwapChain") : NULL;
   if (!creer) { printf("ECHEC: d3d11.dll ou D3D11CreateDeviceAndSwapChain introuvable\n"); return 1; }

   /* 1. dx_create de HashLink */
   ZeroMemory(&desc, sizeof desc);
   desc.BufferDesc.Width = r.right;
   desc.BufferDesc.Height = r.bottom;
   desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
   desc.SampleDesc.Count = 1;
   desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
   desc.BufferCount = 2;
   desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
   desc.Windowed = TRUE;
   desc.OutputWindow = fenetre;
   hr = creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, niveaux, NB_NIVEAUX, D3D11_SDK_VERSION,
              &desc, &chaine, &dev, &niveau, &ctx);
   etape("D3D11CreateDeviceAndSwapChain (11_1..9_1, FLIP_DISCARD)", hr);
   if (hr == E_INVALIDARG) {
      hr = creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                 &desc, &chaine, &dev, &niveau, &ctx);
      etape("D3D11CreateDeviceAndSwapChain (sans liste de niveaux)", hr);
   }
   qui();
   if (FAILED(hr)) {
      printf("=> c'est le « DXError %08lX line 112 » de HashLink%s\n", (unsigned long)hr,
             hr == DXGI_ERROR_UNSUPPORTED ? " (DXGI_ERROR_UNSUPPORTED)" : "");
      printf("FIN echec\n");
      return 1;
   }
   printf("niveau de fonctionnalite : %x\n", (unsigned)niveau);

   /* 2. Driver.resize */
   etape("ResizeBuffers(2, l, h, R8G8B8A8_UNORM, 0)", IDXGISwapChain_ResizeBuffers(chaine, 2, r.right, r.bottom, DXGI_FORMAT_R8G8B8A8_UNORM, 0));

   /* 3. profondeur par defaut */
   D3D11_TEXTURE2D_DESC dt = { 0 };
   dt.Width = r.right; dt.Height = r.bottom; dt.MipLevels = 1; dt.ArraySize = 1;
   dt.Format = DXGI_FORMAT_R24G8_TYPELESS; dt.SampleDesc.Count = 1;
   dt.Usage = D3D11_USAGE_DEFAULT; dt.BindFlags = D3D11_BIND_DEPTH_STENCIL | D3D11_BIND_SHADER_RESOURCE;
   ID3D11Texture2D *prof = NULL;
   etape("CreateTexture2D profondeur R24G8_TYPELESS", ID3D11Device_CreateTexture2D(dev, &dt, NULL, &prof));
   ID3D11DepthStencilView *vprof = NULL, *vprof_ls = NULL;
   D3D11_DEPTH_STENCIL_VIEW_DESC dv = { 0 };
   dv.Format = DXGI_FORMAT_D24_UNORM_S8_UINT; dv.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
   if (prof) etape("CreateDepthStencilView D24_UNORM_S8_UINT", ID3D11Device_CreateDepthStencilView(dev, (ID3D11Resource *)prof, &dv, &vprof));
   dv.Flags = D3D11_DSV_READ_ONLY_DEPTH | D3D11_DSV_READ_ONLY_STENCIL;
   if (prof) etape("CreateDepthStencilView en lecture seule", ID3D11Device_CreateDepthStencilView(dev, (ID3D11Resource *)prof, &dv, &vprof_ls));
   D3D11_SHADER_RESOURCE_VIEW_DESC sv = { 0 };
   sv.Format = DXGI_FORMAT_R24_UNORM_X8_TYPELESS; sv.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
   sv.Texture2D.MipLevels = (UINT)-1;
   ID3D11ShaderResourceView *lprof = NULL;
   if (prof) etape("CreateShaderResourceView R24_UNORM_X8_TYPELESS", ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)prof, &sv, &lprof));

   /* 4. cible par defaut */
   ID3D11Texture2D *fond = NULL;
   ID3D11RenderTargetView *cible = NULL;
   etape("GetBuffer(0)", IDXGISwapChain_GetBuffer(chaine, 0, &IID_ID3D11Texture2D, (void **)&fond));
   if (fond) etape("CreateRenderTargetView", ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)fond, NULL, &cible));
   if (!cible) { printf("FIN echec\n"); return 1; }
   static const float bleu[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
   ID3D11DeviceContext_ClearRenderTargetView(ctx, cible, bleu);
   if (vprof) ID3D11DeviceContext_ClearDepthStencilView(ctx, vprof, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);

   /* 5. un triangle rouge au centre, sommets ecrits par Map(WRITE_DISCARD) */
   HMODULE hc = LoadLibraryA("d3dcompiler_47.dll");
   PFN_COMPILE compiler_hlsl = hc ? (PFN_COMPILE)(void *)GetProcAddress(hc, "D3DCompile") : NULL;
   ID3DBlob *bvs = compiler(compiler_hlsl, "vs", "vs_5_0"), *bps = compiler(compiler_hlsl, "ps", "ps_5_0");
   if (!bvs || !bps) { printf("FIN echec\n"); return 1; }
   ID3D11VertexShader *vs = NULL;
   ID3D11PixelShader *ps = NULL;
   ID3D11InputLayout *disposition = NULL;
   etape("CreateVertexShader", ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(bvs), ID3D10Blob_GetBufferSize(bvs), NULL, &vs));
   etape("CreatePixelShader", ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(bps), ID3D10Blob_GetBufferSize(bps), NULL, &ps));
   static const D3D11_INPUT_ELEMENT_DESC elements[] = {
      { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 },
      { "COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0 },
   };
   etape("CreateInputLayout", ID3D11Device_CreateInputLayout(dev, elements, 2, ID3D10Blob_GetBufferPointer(bvs), ID3D10Blob_GetBufferSize(bvs), &disposition));
   static const float sommets[3][6] = {
      { 0.0f, 0.8f, 1, 0, 0, 1 }, { 0.8f, -0.8f, 1, 0, 0, 1 }, { -0.8f, -0.8f, 1, 0, 0, 1 },
   };
   D3D11_BUFFER_DESC db = { 0 };
   db.ByteWidth = sizeof sommets; db.Usage = D3D11_USAGE_DYNAMIC;
   db.BindFlags = D3D11_BIND_VERTEX_BUFFER; db.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
   ID3D11Buffer *tampon = NULL;
   etape("CreateBuffer DYNAMIC (sommets)", ID3D11Device_CreateBuffer(dev, &db, NULL, &tampon));
   D3D11_MAPPED_SUBRESOURCE m;
   if (tampon) {
      hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)tampon, 0, D3D11_MAP_WRITE_DISCARD, 0, &m);
      etape("Map WRITE_DISCARD (sommets)", hr);
      if (SUCCEEDED(hr)) {
         printf("   memoire des sommets : %p\n", m.pData);
         memcpy(m.pData, sommets, sizeof sommets);
         ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)tampon, 0);
      }
   }
   D3D11_VIEWPORT vue = { 0, 0, (float)r.right, (float)r.bottom, 0, 1 };
   UINT pas = sizeof sommets[0], decalage = 0;
   ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &cible, vprof);
   ID3D11DeviceContext_RSSetViewports(ctx, 1, &vue);
   ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
   ID3D11DeviceContext_IASetInputLayout(ctx, disposition);
   ID3D11DeviceContext_IASetVertexBuffers(ctx, 0, 1, &tampon, &pas, &decalage);
   ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
   ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
   ID3D11DeviceContext_Draw(ctx, 3, 0);

   if (plein) {
      if (fond) ID3D11Texture2D_Release(fond);
      ExitProcess(boucle_plein(fenetre, chaine, dev, ctx, cible, plein_secondes, plein_mode));
   }

   /* 6. relecture */
   D3D11_TEXTURE2D_DESC dr;
   ID3D11Texture2D_GetDesc(fond, &dr);
   dr.Usage = D3D11_USAGE_STAGING; dr.BindFlags = 0; dr.CPUAccessFlags = D3D11_CPU_ACCESS_READ; dr.MiscFlags = 0;
   ID3D11Texture2D *relue = NULL;
   int pixels_justes = 0;
   etape("CreateTexture2D STAGING (relecture)", ID3D11Device_CreateTexture2D(dev, &dr, NULL, &relue));
   if (relue) {
      ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)relue, (ID3D11Resource *)fond);
      hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)relue, 0, D3D11_MAP_READ, 0, &m);
      etape("Map READ (relecture)", hr);
      if (SUCCEEDED(hr)) {
         const unsigned char *p = m.pData;
         const unsigned char *centre = p + (size_t)(dr.Height / 2) * m.RowPitch + (size_t)(dr.Width / 2) * 4;
         const unsigned char *coin = p + 2 * m.RowPitch + 2 * 4;
         printf("   memoire relue : %p ; centre = %02x%02x%02x%02x (attendu ff0000ff), coin = %02x%02x%02x%02x (attendu 0000ffff)\n",
                (void *)p, centre[0], centre[1], centre[2], centre[3], coin[0], coin[1], coin[2], coin[3]);
         pixels_justes = centre[0] == 0xff && centre[1] == 0 && centre[2] == 0 && centre[3] == 0xff
                      && coin[0] == 0 && coin[1] == 0 && coin[2] == 0xff && coin[3] == 0xff;
         ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)relue, 0);
      }
   }
   printf("pixels : %s\n", pixels_justes ? "justes" : "FAUX");

   /* 7. presentation */
   for (int i = 0; i < 3; i++) {
      hr = IDXGISwapChain_Present(chaine, 1, 0);
      if (FAILED(hr) || i == 2) etape("Present(1, 0) x3", hr);
      if (FAILED(hr)) break;
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &cible, vprof);
      ID3D11DeviceContext_ClearRenderTargetView(ctx, cible, bleu);
   }

   printf("FIN %s\n", !echecs && pixels_justes ? "ok" : "echec");
   fflush(stdout);
   /* sortie sans demontage : la sonde eprouve l'initialisation, pas la liberation */
   ExitProcess(!echecs && pixels_justes ? 0 : 1);
}
