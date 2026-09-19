/* DXVK tient-il sur KosmicKrisp ? On cree un peripherique D3D11, on efface une
 * cible avec une couleur connue, puis on relit le pixel : si la valeur revient,
 * le GPU a reellement execute la commande.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <d3d11.h>
#include <dxgi1_2.h>

typedef HRESULT (WINAPI *PFN_CREATE)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                     const D3D_FEATURE_LEVEL *, UINT, UINT,
                                     ID3D11Device **, D3D_FEATURE_LEVEL *,
                                     ID3D11DeviceContext **);

static const char *niveau(D3D_FEATURE_LEVEL l)
{
   switch (l) {
   case D3D_FEATURE_LEVEL_12_1: return "12_1";
   case D3D_FEATURE_LEVEL_12_0: return "12_0";
   case D3D_FEATURE_LEVEL_11_1: return "11_1";
   case D3D_FEATURE_LEVEL_11_0: return "11_0";
   case D3D_FEATURE_LEVEL_10_1: return "10_1";
   case D3D_FEATURE_LEVEL_10_0: return "10_0";
   default: return "inferieur";
   }
}

int main(void)
{
   HMODULE h = LoadLibraryA("d3d11.dll");
   if (!h) { printf("ECHEC: d3d11.dll introuvable\n"); return 1; }
   PFN_CREATE creer = (PFN_CREATE)(void *)GetProcAddress(h, "D3D11CreateDevice");
   if (!creer) { printf("ECHEC: D3D11CreateDevice absent\n"); return 1; }

   ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
   D3D_FEATURE_LEVEL fl = 0;
   HRESULT hr = creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                      D3D11_SDK_VERSION, &dev, &fl, &ctx);
   if (FAILED(hr)) { printf("ECHEC: D3D11CreateDevice -> 0x%08lx\n", (unsigned long)hr); return 1; }
   printf("peripherique cree, niveau de fonctionnalite %s\n", niveau(fl));

   IDXGIDevice *dxgidev = NULL;
   if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgidev))) {
      IDXGIAdapter *ad = NULL;
      if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgidev, &ad))) {
         DXGI_ADAPTER_DESC d;
         if (SUCCEEDED(IDXGIAdapter_GetDesc(ad, &d)))
            printf("adaptateur : %ls  (%lu Mo dedies)\n", d.Description,
                   (unsigned long)(d.DedicatedVideoMemory >> 20));
         IDXGIAdapter_Release(ad);
      }
      IDXGIDevice_Release(dxgidev);
   }

   D3D11_TEXTURE2D_DESC td = { .Width = 64, .Height = 64, .MipLevels = 1, .ArraySize = 1,
      .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0},
      .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_RENDER_TARGET };
   ID3D11Texture2D *cible = NULL;
   hr = ID3D11Device_CreateTexture2D(dev, &td, NULL, &cible);
   if (FAILED(hr)) { printf("ECHEC: CreateTexture2D -> 0x%08lx\n", (unsigned long)hr); return 1; }

   ID3D11RenderTargetView *rtv = NULL;
   hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)cible, NULL, &rtv);
   if (FAILED(hr)) { printf("ECHEC: CreateRenderTargetView -> 0x%08lx\n", (unsigned long)hr); return 1; }

   const float couleur[4] = { 0.25f, 0.50f, 0.75f, 1.0f };
   ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, couleur);

   D3D11_TEXTURE2D_DESC sd = td;
   sd.Usage = D3D11_USAGE_STAGING; sd.BindFlags = 0;
   sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
   ID3D11Texture2D *lecture = NULL;
   hr = ID3D11Device_CreateTexture2D(dev, &sd, NULL, &lecture);
   if (FAILED(hr)) { printf("ECHEC: texture de lecture -> 0x%08lx\n", (unsigned long)hr); return 1; }

   ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)lecture, (ID3D11Resource *)cible);
   ID3D11DeviceContext_Flush(ctx);

   D3D11_MAPPED_SUBRESOURCE m;
   hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)lecture, 0, D3D11_MAP_READ, 0, &m);
   if (FAILED(hr)) { printf("ECHEC: Map -> 0x%08lx\n", (unsigned long)hr); return 1; }
   unsigned char *p = m.pData;
   printf("pixel relu : R=%u V=%u B=%u A=%u  (attendu 64 128 191 255)\n", p[0], p[1], p[2], p[3]);
   int bon = p[0] >= 62 && p[0] <= 66 && p[1] >= 126 && p[1] <= 130 &&
             p[2] >= 189 && p[2] <= 193 && p[3] == 255;
   ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)lecture, 0);

   printf("%s\n", bon ? "RESULTAT: le GPU a execute l'effacement, la valeur revient juste"
                      : "RESULTAT: valeur inattendue");
   return bon ? 0 : 1;
}
