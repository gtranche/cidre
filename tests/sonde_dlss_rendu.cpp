// Sonde hors jeu du DLSS de DXMT avec un VRAI rendu GPU dans le meme tampon de commandes
// que MetalFX, comme Expedition 33 (les sondes precedentes televersaient leurs entrees
// depuis le CPU : jamais de gel). Par image :
//   1. passe de scene : N dessins (triangle plein ecran, nuanceur de pixels a boucle
//      reglable) dans la couleur R11G11B10 1244x780 (contenu 1241x779) et la profondeur
//      R32G8X24 (D32S8, inversee, ecrite par le nuanceur) ;
//   2. passe de vecteurs : dessin des vecteurs dilates R16G16 1383x868 ;
//   3. DLSS (nvngx de DXMT -> MetalFX temporel, exposition auto) vers RGBA16F 1384x868 ;
//   4. post-traitement : dessin qui lit la sortie DLSS et ecrit le backbuffer 1728x1084 ;
//   5. Present.
// Nuanceurs compiles a l'execution par le d3dcompiler_47 de Wine (vkd3d-shader). Fenetre
// jamais montree (CIDRE_PRESENTATION_CACHEE=1). Risque de gel GPU : creneau requis.
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 -I<dxmt>/src/nvngx sonde_dlss_rendu.cpp -ld3d11 -ldxgi -luser32 -static -o sonde_dlss_rendu.exe
//   DXMT_ENABLE_NVEXT=1 CIDRE_PRESENTATION_CACHEE=1 CIDRE_DXMT_STATS=1 wine sonde_dlss_rendu.exe [images] [dessins] [boucle] [dlss|taa] [visible]
// « taa » : meme rendu, sans DLSS (le post lit directement la couleur) : le temoin, comme TSR.
// « visible » : fenetre sans bordure montree a l'ecran (WindowServer compose l'image, comme
// pour le jeu) ; sans CIDRE_PRESENTATION_CACHEE. Aucune capture.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include "nvngx.hpp"

static const unsigned BB_W = 1728, BB_H = 1084, OUT_W = 1384, OUT_H = 868, MV_W = 1383, MV_H = 868;
static const unsigned IN_TW = 1244, IN_TH = 780, IN_CW = 1241, IN_CH = 779;

typedef NVNGX_RESULT (*PFN_Init)(unsigned long long, const wchar_t *, ID3D11Device *, const void *, unsigned int);
typedef NVNGX_RESULT (*PFN_Alloc)(NVNGXParameter **);
typedef NVNGX_RESULT (*PFN_Create)(ID3D11DeviceContext *, unsigned int, NVNGXParameter *, unsigned int **);
typedef NVNGX_RESULT (*PFN_Eval)(ID3D11DeviceContext *, const unsigned int *, NVNGXParameter *, void *);
typedef HRESULT(WINAPI *PFN_Compile)(const void *, SIZE_T, const char *, const D3D_SHADER_MACRO *, ID3DInclude *,
                                     const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);

static const char *HLSL = R"(
cbuffer Par : register(b0) { float4 p; float4 q; }; // p : temps, indice, boucle, profondeur ; q : jitter x y
struct VSO { float4 pos : SV_Position; float2 uv : TEXCOORD0; };
VSO vs(uint id : SV_VertexID) {
  VSO o; float2 uv = float2((id << 1) & 2, id & 2);
  o.pos = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o;
}
struct PSO { float4 c : SV_Target0; float d : SV_Depth; };
PSO ps_scene(VSO i) {
  float2 x = i.pos.xy + q.xy + float2(p.x * 3.0, p.x);
  float v = 0;
  for (int k = 0; k < (int)p.z; k++) v += sin(x.x * 0.05 + k) * cos(x.y * 0.07 + p.y + k);
  PSO o; o.c = float4(abs(v) * 0.5 + 0.2, frac(x.x / 48.0), frac(x.y / 48.0), 1) * 4.0;
  o.d = saturate(p.w + 0.001 * sin(x.x * 0.01)); return o;
}
float4 ps_mv(VSO i) : SV_Target0 { return float4(-3.0, -1.0, 0, 0); }
Texture2D<float4> src : register(t0); SamplerState smp : register(s0);
float4 ps_post(VSO i) : SV_Target0 { float4 c = src.SampleLevel(smp, i.uv * q.zw, 0); return c / (1 + c); }
)";

int main(int argc, char **argv) {
  int images = argc > 1 ? atoi(argv[1]) : 3000;
  int dessins = argc > 2 ? atoi(argv[2]) : 200;
  int boucle = argc > 3 ? atoi(argv[3]) : 8;
  bool dlss = !(argc > 4 && !strcmp(argv[4], "taa"));
  bool visible = argc > 5 && !strcmp(argv[5], "visible");
  printf("%d images, %d dessins de scene par image, boucle %d, %s\n", images, dessins, boucle, dlss ? "DLSS" : "temoin sans DLSS");
  HWND hwnd = CreateWindowExA(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "STATIC", "sonde", WS_POPUP, 0, 0, BB_W, BB_H,
                              nullptr, nullptr, GetModuleHandleA(nullptr), nullptr);
  if (visible) { ShowWindow(hwnd, SW_SHOW); UpdateWindow(hwnd); }
  DXGI_SWAP_CHAIN_DESC sd = {};
  sd.BufferDesc.Width = BB_W; sd.BufferDesc.Height = BB_H; sd.BufferDesc.Format = DXGI_FORMAT_R10G10B10A2_UNORM;
  sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2;
  sd.OutputWindow = hwnd; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  ID3D11Device *dev = nullptr; ID3D11DeviceContext *ctx = nullptr; IDXGISwapChain *sc = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1, got;
  if (!hwnd || FAILED(D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION,
                                                    &sd, &sc, &dev, &got, &ctx))) {
    printf("ECHEC : device\n"); return 1;
  }
  HMODULE dc = LoadLibraryA("d3dcompiler_47.dll");
  auto Compile = dc ? (PFN_Compile)GetProcAddress(dc, "D3DCompile") : nullptr;
  if (!Compile) { printf("ECHEC : d3dcompiler_47\n"); return 1; }
  auto blob = [&](const char *entree, const char *cible) {
    ID3DBlob *b = nullptr, *err = nullptr;
    if (FAILED(Compile(HLSL, strlen(HLSL), "sonde", nullptr, nullptr, entree, cible, 0, 0, &b, &err))) {
      printf("ECHEC : compilation %s : %s\n", entree, err ? (const char *)err->GetBufferPointer() : "?"); exit(1);
    }
    return b;
  };
  ID3DBlob *bvs = blob("vs", "vs_5_0"), *bscene = blob("ps_scene", "ps_5_0"), *bmv = blob("ps_mv", "ps_5_0"), *bpost = blob("ps_post", "ps_5_0");
  ID3D11VertexShader *vs; ID3D11PixelShader *pscene, *pmv, *ppost;
  dev->CreateVertexShader(bvs->GetBufferPointer(), bvs->GetBufferSize(), nullptr, &vs);
  dev->CreatePixelShader(bscene->GetBufferPointer(), bscene->GetBufferSize(), nullptr, &pscene);
  dev->CreatePixelShader(bmv->GetBufferPointer(), bmv->GetBufferSize(), nullptr, &pmv);
  dev->CreatePixelShader(bpost->GetBufferPointer(), bpost->GetBufferSize(), nullptr, &ppost);

  auto tex = [&](unsigned w, unsigned h, DXGI_FORMAT f, UINT bind) {
    D3D11_TEXTURE2D_DESC d = {w, h, 1, 1, f, {1, 0}, D3D11_USAGE_DEFAULT, bind, 0, 0};
    ID3D11Texture2D *t = nullptr; dev->CreateTexture2D(&d, nullptr, &t); return t;
  };
  ID3D11Texture2D *color = tex(IN_TW, IN_TH, DXGI_FORMAT_R11G11B10_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET);
  ID3D11Texture2D *depth = tex(IN_TW, IN_TH, DXGI_FORMAT_R32G8X24_TYPELESS, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL);
  ID3D11Texture2D *mv = tex(MV_W, MV_H, DXGI_FORMAT_R16G16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET);
  ID3D11Texture2D *out = tex(OUT_W, OUT_H, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS);
  ID3D11Texture2D *bb = nullptr; sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
  ID3D11RenderTargetView *rtv_color, *rtv_mv, *rtv_bb; ID3D11DepthStencilView *dsv;
  ID3D11ShaderResourceView *srv_out, *srv_color;
  dev->CreateRenderTargetView(color, nullptr, &rtv_color);
  dev->CreateRenderTargetView(mv, nullptr, &rtv_mv);
  dev->CreateRenderTargetView(bb, nullptr, &rtv_bb);
  D3D11_DEPTH_STENCIL_VIEW_DESC dvd = {}; dvd.Format = DXGI_FORMAT_D32_FLOAT_S8X24_UINT; dvd.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
  dev->CreateDepthStencilView(depth, &dvd, &dsv);
  dev->CreateShaderResourceView(out, nullptr, &srv_out);
  dev->CreateShaderResourceView(color, nullptr, &srv_color);
  D3D11_DEPTH_STENCIL_DESC dsd = {}; dsd.DepthEnable = TRUE; dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
  dsd.DepthFunc = D3D11_COMPARISON_GREATER_EQUAL; // profondeur inversee
  ID3D11DepthStencilState *dss; dev->CreateDepthStencilState(&dsd, &dss);
  D3D11_SAMPLER_DESC smd = {}; smd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  smd.AddressU = smd.AddressV = smd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP; smd.MaxLOD = D3D11_FLOAT32_MAX;
  ID3D11SamplerState *smp; dev->CreateSamplerState(&smd, &smp);
  D3D11_BUFFER_DESC bd = {32, D3D11_USAGE_DYNAMIC, D3D11_BIND_CONSTANT_BUFFER, D3D11_CPU_ACCESS_WRITE, 0, 0};
  ID3D11Buffer *cb; dev->CreateBuffer(&bd, nullptr, &cb);
  if (!color || !depth || !mv || !out || !dsv || !srv_out || !cb) { printf("ECHEC : ressources\n"); return 1; }

  HMODULE ngx = LoadLibraryA("nvngx.dll");
  if (dlss && !ngx) { printf("ECHEC : nvngx.dll (DXMT_ENABLE_NVEXT=1 ?)\n"); return 1; }
  PFN_Eval Eval = nullptr; unsigned *h = nullptr; NVNGXParameter *prm = nullptr;
  if (dlss) {
    ((PFN_Init)GetProcAddress(ngx, "NVSDK_NGX_D3D11_Init"))(1, L"C:\\", dev, nullptr, 0x15);
    ((PFN_Alloc)GetProcAddress(ngx, "NVSDK_NGX_D3D11_AllocateParameters"))(&prm);
    prm->Set(NVNGX_Parameter_Width, IN_CW); prm->Set(NVNGX_Parameter_Height, IN_CH);
    prm->Set(NVNGX_Parameter_OutWidth, OUT_W); prm->Set(NVNGX_Parameter_OutHeight, OUT_H);
    prm->Set(NVNGX_Parameter_DLSS_Feature_Create_Flags, (int)(NVNGX_DLSS_FLAG_AUTO_EXPOSURE | NVNGX_DLSS_FLAG_DEPTH_INVERTED));
    if (((PFN_Create)GetProcAddress(ngx, "NVSDK_NGX_D3D11_CreateFeature"))(ctx, NVNGX_FEATURE_SUPERSAMPLING, prm, &h) != NVNGX_RESULT_OK) {
      printf("ECHEC : CreateFeature\n"); return 1;
    }
    Eval = (PFN_Eval)GetProcAddress(ngx, "NVSDK_NGX_D3D11_EvaluateFeature");
  }
  auto poser_cb = [&](float a, float b, float c, float d, float e, float f, float g, float k) {
    D3D11_MAPPED_SUBRESOURCE m; ctx->Map(cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m);
    float v[8] = {a, b, c, d, e, f, g, k}; memcpy(m.pData, v, 32); ctx->Unmap(cb, 0);
  };
  auto vue = [&](unsigned w, unsigned h2) { D3D11_VIEWPORT vp = {0, 0, (float)w, (float)h2, 0, 1}; ctx->RSSetViewports(1, &vp); };

  LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
  for (int t = 0; t < images; t++) {
    float jx = 0.5f - (float)((t * 7) % 16) / 16.0f, jy = 0.5f - (float)((t * 11) % 16) / 16.0f;
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ctx->VSSetShader(vs, nullptr, 0);
    // 1. scene
    float noir[4] = {0, 0, 0, 0};
    ctx->ClearRenderTargetView(rtv_color, noir);
    ctx->ClearDepthStencilView(dsv, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 0.0f, 0);
    ctx->OMSetRenderTargets(1, &rtv_color, dsv);
    ctx->OMSetDepthStencilState(dss, 0);
    ctx->PSSetShader(pscene, nullptr, 0);
    vue(IN_CW, IN_CH);
    for (int k = 0; k < dessins; k++) {
      poser_cb((float)t, (float)k, (float)boucle, (float)k / dessins, jx, jy, 0, 0);
      ctx->PSSetConstantBuffers(0, 1, &cb);
      ctx->Draw(3, 0);
    }
    // 2. vecteurs dilates
    ctx->OMSetRenderTargets(1, &rtv_mv, nullptr);
    ctx->PSSetShader(pmv, nullptr, 0);
    vue(MV_W, MV_H);
    ctx->Draw(3, 0);
    ctx->OMSetRenderTargets(0, nullptr, nullptr);
    // 3. DLSS
    if (dlss) {
      prm->Set(NVNGX_Parameter_Color, (ID3D11Resource *)color); prm->Set(NVNGX_Parameter_Output, (ID3D11Resource *)out);
      prm->Set(NVNGX_Parameter_Depth, (ID3D11Resource *)depth); prm->Set(NVNGX_Parameter_MotionVectors, (ID3D11Resource *)mv);
      prm->Set(NVNGX_Parameter_Jitter_Offset_X, jx); prm->Set(NVNGX_Parameter_Jitter_Offset_Y, jy);
      prm->Set(NVNGX_Parameter_MV_Scale_X, 1.0f); prm->Set(NVNGX_Parameter_MV_Scale_Y, 1.0f);
      prm->Set(NVNGX_Parameter_Reset, t == 0 ? 1 : 0);
      prm->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Width, IN_CW);
      prm->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Height, IN_CH);
      prm->Set(NVNGX_Parameter_DLSS_Pre_Exposure, 0.4f + 0.05f * (float)sin(t * 0.01));
      if (Eval(ctx, h, prm, nullptr) != NVNGX_RESULT_OK) { printf("ECHEC : Evaluate\n"); return 1; }
    }
    // 4. post-traitement vers le backbuffer
    ctx->OMSetRenderTargets(1, &rtv_bb, nullptr);
    ctx->PSSetShader(ppost, nullptr, 0);
    ID3D11ShaderResourceView *s = dlss ? srv_out : srv_color;
    ctx->PSSetShaderResources(0, 1, &s);
    ctx->PSSetSamplers(0, 1, &smp);
    poser_cb(0, 0, 0, 0, 0, 0, dlss ? 1.0f : (float)IN_CW / IN_TW, dlss ? 1.0f : (float)IN_CH / IN_TH);
    ctx->PSSetConstantBuffers(0, 1, &cb);
    vue(BB_W, BB_H);
    ctx->Draw(3, 0);
    ID3D11ShaderResourceView *nul = nullptr; ctx->PSSetShaderResources(0, 1, &nul);
    sc->Present(0, 0);
    if (visible) { MSG msg; while (PeekMessageA(&msg, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }
  }
  QueryPerformanceCounter(&t1);
  double s = (t1.QuadPart - t0.QuadPart) / (double)fq.QuadPart;
  printf("%d images en %.2f s (%.1f images/s)\nOK\n", images, s, images / s);
  return 0;
}
