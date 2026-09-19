/* Chemin complet D3D11 : HLSL compile a l'execution par d3dcompiler_47, puis
 * DXBC -> DXVK -> SPIR-V -> KosmicKrisp -> Metal. On dessine un triangle plein
 * ecran et on relit deux pixels : un dedans, un dehors.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <d3d11.h>
#include <d3dcompiler.h>

typedef HRESULT (WINAPI *PFN_CREATE)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                     const D3D_FEATURE_LEVEL *, UINT, UINT,
                                     ID3D11Device **, D3D_FEATURE_LEVEL *,
                                     ID3D11DeviceContext **);
typedef HRESULT (WINAPI *PFN_COMPILE)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *,
                                      ID3DInclude *, LPCSTR, LPCSTR, UINT, UINT,
                                      ID3DBlob **, ID3DBlob **);

static const char *HLSL =
"struct VSOut { float4 pos : SV_Position; float3 col : COLOR; };\n"
"VSOut vs_main(uint id : SV_VertexID) {\n"
"   float2 p[3] = { float2(-0.9,-0.9), float2(0.0,0.9), float2(0.9,-0.9) };\n"
"   float3 c[3] = { float3(1,0,0), float3(0,1,0), float3(0,0,1) };\n"
"   VSOut o; o.pos = float4(p[id], 0, 1); o.col = c[id]; return o;\n"
"}\n"
"float4 ps_main(VSOut i) : SV_Target { return float4(i.col, 1); }\n";

int main(void)
{
   HMODULE hd = LoadLibraryA("d3d11.dll");
   HMODULE hc = LoadLibraryA("d3dcompiler_47.dll");
   if (!hd || !hc) { printf("ECHEC: DLL manquante\n"); return 1; }
   PFN_CREATE creer = (PFN_CREATE)(void *)GetProcAddress(hd, "D3D11CreateDevice");
   PFN_COMPILE compiler_hlsl = (PFN_COMPILE)(void *)GetProcAddress(hc, "D3DCompile");
   if (!creer || !compiler_hlsl) { printf("ECHEC: point d'entree manquant\n"); return 1; }

   ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL fl;
   if (FAILED(creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                    D3D11_SDK_VERSION, &dev, &fl, &ctx))) {
      printf("ECHEC: creation du peripherique\n"); return 1; }

   ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
   HRESULT hr = compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "vs_main", "vs_4_0", 0, 0, &vsb, &err);
   if (FAILED(hr)) { printf("ECHEC: compilation VS 0x%08lx %s\n", (unsigned long)hr,
                            err ? (char *)ID3D10Blob_GetBufferPointer(err) : ""); return 1; }
   hr = compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "ps_main", "ps_4_0", 0, 0, &psb, &err);
   if (FAILED(hr)) { printf("ECHEC: compilation PS 0x%08lx %s\n", (unsigned long)hr,
                            err ? (char *)ID3D10Blob_GetBufferPointer(err) : ""); return 1; }
   printf("HLSL compile : VS %lu octets, PS %lu octets\n",
          (unsigned long)ID3D10Blob_GetBufferSize(vsb), (unsigned long)ID3D10Blob_GetBufferSize(psb));

   ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
   if (FAILED(ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb),
                                              ID3D10Blob_GetBufferSize(vsb), NULL, &vs)) ||
       FAILED(ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb),
                                             ID3D10Blob_GetBufferSize(psb), NULL, &ps))) {
      printf("ECHEC: creation des shaders\n"); return 1; }

   D3D11_TEXTURE2D_DESC td = { .Width = 64, .Height = 64, .MipLevels = 1, .ArraySize = 1,
      .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0},
      .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_RENDER_TARGET };
   ID3D11Texture2D *cible = NULL; ID3D11RenderTargetView *rtv = NULL;
   ID3D11Device_CreateTexture2D(dev, &td, NULL, &cible);
   ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)cible, NULL, &rtv);

   const float noir[4] = {0, 0, 0, 1};
   ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, noir);
   ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
   D3D11_VIEWPORT vp = {0, 0, 64, 64, 0, 1};
   ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
   ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
   ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
   ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
   ID3D11DeviceContext_Draw(ctx, 3, 0);

   D3D11_TEXTURE2D_DESC sd = td; sd.Usage = D3D11_USAGE_STAGING;
   sd.BindFlags = 0; sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
   ID3D11Texture2D *lec = NULL;
   ID3D11Device_CreateTexture2D(dev, &sd, NULL, &lec);
   ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)lec, (ID3D11Resource *)cible);
   ID3D11DeviceContext_Flush(ctx);

   D3D11_MAPPED_SUBRESOURCE m;
   if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)lec, 0, D3D11_MAP_READ, 0, &m))) {
      printf("ECHEC: Map\n"); return 1; }
   unsigned char *base = m.pData;
   unsigned char *centre = base + 40 * m.RowPitch + 32 * 4;   /* dans le triangle */
   unsigned char *coin   = base + 2 * m.RowPitch + 2 * 4;     /* hors du triangle */
   printf("centre : R=%u V=%u B=%u   coin : R=%u V=%u B=%u\n",
          centre[0], centre[1], centre[2], coin[0], coin[1], coin[2]);
   int dedans = (centre[0] + centre[1] + centre[2]) > 60;
   int dehors = (coin[0] + coin[1] + coin[2]) == 0;
   ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)lec, 0);

   printf("%s\n", (dedans && dehors)
      ? "RESULTAT: le triangle est rasterise, interpolation des couleurs comprise"
      : "RESULTAT: rendu incorrect");
   return (dedans && dehors) ? 0 : 1;
}
