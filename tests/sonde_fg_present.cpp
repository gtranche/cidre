// Sonde hors jeu du chemin complet DLSS -> generation d'images -> presentation de
// DXMT (0184 + 0185), comme un jeu Unreal : par image, une scene analytique rendue
// a basse definition avec jitter, DLSS (nvngx de DXMT -> MetalFX temporel) vers une
// texture RGBA16F, copiee dans le backbuffer d'une swapchain RGBA16F, puis Present.
// La fenetre n'est jamais montree : CIDRE_PRESENTATION_CACHEE=1 fait presenter DXMT
// quand meme (0154). Avec CIDRE_DXMT_FG=1, DXMT presente une image generee avant
// chaque vraie ; CIDRE_DXMT_RELIRE / CIDRE_DXMT_RELIRE_IMAGE relisent dans le
// processus les images vraies et generees, que tests/sonde_fg_present.py compare a
// la scene vraie.
//
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 -I<dxmt>/src/nvngx sonde_fg_present.cpp -ld3d11 -ldxgi -luser32 -o sonde_fg_present.exe
//   DXMT_ENABLE_NVEXT=1 CIDRE_DXMT_FG=1 CIDRE_PRESENTATION_CACHEE=1 CIDRE_DXMT_STATS=1 \
//     CIDRE_DXMT_RELIRE=img.ppm CIDRE_DXMT_RELIRE_IMAGE=39,40 wine sonde_fg_present.exe [images] [ms par image]
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "nvngx.hpp"

static const unsigned OUT_W = 1728, OUT_H = 1084;
static const float VX = 6.0f, VY = 2.0f;

typedef NVNGX_RESULT (*PFN_Init)(unsigned long long, const wchar_t *, ID3D11Device *, const void *, unsigned int);
typedef NVNGX_RESULT (*PFN_Alloc)(NVNGXParameter **);
typedef NVNGX_RESULT (*PFN_Create)(ID3D11DeviceContext *, unsigned int, NVNGXParameter *, unsigned int **);
typedef NVNGX_RESULT (*PFN_Eval)(ID3D11DeviceContext *, const unsigned int *, NVNGXParameter *, void *);

// la meme scene que sonde_fg_metalfx.cpp (et sonde_fg_present.py)
static float scene(float x, float y, float t) {
  x -= VX * t; y -= VY * t;
  int cx = (int)std::floor(x / 24.0f), cy = (int)std::floor(y / 24.0f);
  float v = ((cx + cy) & 1) ? 0.8f : 0.2f;
  float d = std::fmod(std::fabs(x + 2.0f * y), 61.0f);
  if (d < 2.0f) v = 1.0f;
  float dx = x + VX * t - 200, dy = y + VY * t - 150;
  if (dx * dx + dy * dy < 60 * 60) v = 0.5f;
  return v;
}
static float halton(int i, int b) {
  float f = 1, r = 0;
  for (i += 1; i > 0; i /= b) { f /= b; r += f * (i % b); }
  return r;
}
static uint16_t f32_to_f16(float f) {
  uint32_t x; memcpy(&x, &f, 4);
  uint32_t s = (x >> 16) & 0x8000; int e = ((x >> 23) & 0xff) - 127 + 15; uint32_t m = x & 0x7fffff;
  if (e <= 0) return (uint16_t)s;
  if (e >= 31) return (uint16_t)(s | 0x7c00);
  return (uint16_t)(s | (e << 10) | (m >> 13));
}

int main(int argc, char **argv) {
  int images = argc > 1 ? atoi(argv[1]) : 60;
  int ms_image = argc > 2 ? atoi(argv[2]) : 25; // ~40 images/s, comme Exp33 limite par le CPU
  // « sousrect » : comme Unreal, rendu dans un sous-rectangle de textures a la taille de sortie,
  // vecteurs dilates a la definition de sortie (en pixels de sortie), sans MV_LOWRES
  bool sousrect = argc > 3 && !strcmp(argv[3], "sousrect");
  HWND hwnd = CreateWindowExA(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "STATIC", "sonde", WS_POPUP, 0, 0, OUT_W, OUT_H,
                              nullptr, nullptr, GetModuleHandleA(nullptr), nullptr);
  if (!hwnd) { printf("ECHEC : fenetre\n"); return 1; }
  DXGI_SWAP_CHAIN_DESC sd = {};
  sd.BufferDesc.Width = OUT_W; sd.BufferDesc.Height = OUT_H; sd.BufferDesc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
  sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2;
  sd.OutputWindow = hwnd; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  ID3D11Device *dev = nullptr; ID3D11DeviceContext *ctx = nullptr; IDXGISwapChain *sc = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1, got;
  if (FAILED(D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &sd,
                                           &sc, &dev, &got, &ctx))) {
    printf("ECHEC : D3D11CreateDeviceAndSwapChain\n"); return 1;
  }
  ID3D11Texture2D *bb = nullptr; sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);

  HMODULE ngx = LoadLibraryA("nvngx.dll");
  if (!ngx) { printf("ECHEC : nvngx.dll (DXMT_ENABLE_NVEXT=1 ?)\n"); return 1; }
  auto Init = (PFN_Init)GetProcAddress(ngx, "NVSDK_NGX_D3D11_Init");
  auto Alloc = (PFN_Alloc)GetProcAddress(ngx, "NVSDK_NGX_D3D11_AllocateParameters");
  auto Create = (PFN_Create)GetProcAddress(ngx, "NVSDK_NGX_D3D11_CreateFeature");
  auto Eval = (PFN_Eval)GetProcAddress(ngx, "NVSDK_NGX_D3D11_EvaluateFeature");
  Init(1, L"C:\\", dev, nullptr, 0x15);
  const unsigned in_w = OUT_W / 2, in_h = OUT_H / 2;             // zone rendue
  const unsigned tex_w = sousrect ? OUT_W : in_w, tex_h = sousrect ? OUT_H : in_h; // textures d'entree
  auto tex = [&](unsigned w, unsigned h, DXGI_FORMAT f, UINT bind) {
    D3D11_TEXTURE2D_DESC d = {w, h, 1, 1, f, {1, 0}, D3D11_USAGE_DEFAULT, bind, 0, 0};
    ID3D11Texture2D *t = nullptr; dev->CreateTexture2D(&d, nullptr, &t); return t;
  };
  ID3D11Texture2D *color = tex(tex_w, tex_h, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  ID3D11Texture2D *depth = tex(tex_w, tex_h, DXGI_FORMAT_R32_TYPELESS, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL);
  const unsigned mv_w = sousrect ? OUT_W : in_w, mv_h = sousrect ? OUT_H : in_h;
  ID3D11Texture2D *mv = tex(mv_w, mv_h, DXGI_FORMAT_R16G16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  ID3D11Texture2D *out = tex(OUT_W, OUT_H, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS);
  D3D11_DEPTH_STENCIL_VIEW_DESC dvd = {}; dvd.Format = DXGI_FORMAT_D32_FLOAT; dvd.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
  ID3D11DepthStencilView *dsv = nullptr; dev->CreateDepthStencilView(depth, &dvd, &dsv);
  {
    std::vector<uint16_t> m(mv_w * mv_h * 2);
    uint16_t mx = f32_to_f16(sousrect ? -VX : -VX * in_w / OUT_W), my = f32_to_f16(sousrect ? -VY : -VY * in_h / OUT_H);
    for (size_t i = 0; i < m.size(); i += 2) { m[i] = mx; m[i + 1] = my; }
    ctx->UpdateSubresource(mv, 0, nullptr, m.data(), mv_w * 4, 0);
  }
  NVNGXParameter *p = nullptr; Alloc(&p);
  p->Set(NVNGX_Parameter_Width, in_w); p->Set(NVNGX_Parameter_Height, in_h);
  p->Set(NVNGX_Parameter_OutWidth, OUT_W); p->Set(NVNGX_Parameter_OutHeight, OUT_H);
  p->Set(NVNGX_Parameter_DLSS_Feature_Create_Flags, sousrect ? 0 : (int)NVNGX_DLSS_FLAG_MV_LOWRES);
  unsigned *h = nullptr;
  if (Create(ctx, NVNGX_FEATURE_SUPERSAMPLING, p, &h) != NVNGX_RESULT_OK) { printf("ECHEC : CreateFeature\n"); return 1; }

  LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
  std::vector<uint16_t> c(tex_w * tex_h * 4);
  for (int t = 0; t < images; t++) {
    LARGE_INTEGER d0, d1; QueryPerformanceCounter(&d0);
    // jitter dans la convention DLSS (moins le decalage du point d'echantillonnage)
    float jx = halton(t % 16, 2) - 0.5f, jy = halton(t % 16, 3) - 0.5f;
    for (unsigned y = 0; y < in_h; y++)
      for (unsigned x = 0; x < in_w; x++) {
        uint16_t hv = f32_to_f16(scene((x + 0.5f + jx) * 2, (y + 0.5f + jy) * 2, (float)t)), one = f32_to_f16(1);
        uint16_t *px = &c[(y * tex_w + x) * 4]; px[0] = px[1] = px[2] = hv; px[3] = one;
      }
    ctx->UpdateSubresource(color, 0, nullptr, c.data(), tex_w * 8, 0);
    ctx->ClearDepthStencilView(dsv, D3D11_CLEAR_DEPTH, 0.5f, 0);
    p->Set(NVNGX_Parameter_Color, (ID3D11Resource *)color); p->Set(NVNGX_Parameter_Output, (ID3D11Resource *)out);
    p->Set(NVNGX_Parameter_Depth, (ID3D11Resource *)depth); p->Set(NVNGX_Parameter_MotionVectors, (ID3D11Resource *)mv);
    p->Set(NVNGX_Parameter_Jitter_Offset_X, -jx); p->Set(NVNGX_Parameter_Jitter_Offset_Y, -jy);
    p->Set(NVNGX_Parameter_MV_Scale_X, 1.0f); p->Set(NVNGX_Parameter_MV_Scale_Y, 1.0f);
    p->Set(NVNGX_Parameter_Reset, t == 0 ? 1 : 0);
    p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Width, in_w);
    p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Height, in_h);
    if (Eval(ctx, h, p, nullptr) != NVNGX_RESULT_OK) { printf("ECHEC : Evaluate\n"); return 1; }
    ctx->CopyResource(bb, out);
    sc->Present(0, 0);
    QueryPerformanceCounter(&d1);
    int reste = ms_image - (int)(1000.0 * (d1.QuadPart - d0.QuadPart) / fq.QuadPart);
    if (reste > 0) Sleep(reste);
  }
  QueryPerformanceCounter(&t1);
  printf("%d images en %.2f s (%.1f images/s rendues)\nOK\n", images, (t1.QuadPart - t0.QuadPart) / (double)fq.QuadPart,
         images / ((t1.QuadPart - t0.QuadPart) / (double)fq.QuadPart));
  return 0;
}
