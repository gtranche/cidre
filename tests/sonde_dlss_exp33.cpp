// Sonde hors jeu du DLSS de DXMT avec EXACTEMENT les entrees qu'Expedition 33 donne a
// DLSS (journal « cidre-dlss » du 2026-10-19) : couleur R11G11B10_FLOAT 692x436 (contenu
// 692x434), profondeur R32G8X24 (Depth32Float_Stencil8) inversee, vecteurs dilates
// R16G16_FLOAT 1383x868 en pixels de sortie, sortie R16G16B16A16_FLOAT 1384x868,
// exposition automatique, puis copie de la sortie dans un backbuffer 1728x1084 et Present.
// Option « taille » : commence en 1241x779 (texture 1244x780) et passe a 692x434 a mi-course,
// comme le jeu (deux scalers). La fenetre n'est jamais montree (CIDRE_PRESENTATION_CACHEE=1).
// Les deux gels GPU du M1 sous DLSS sont venus de ce jeu : le risque existe ici aussi,
// a ne lancer qu'avec un creneau de la coordination.
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 -I<dxmt>/src/nvngx sonde_dlss_exp33.cpp -ld3d11 -ldxgi -luser32 -static -o sonde_dlss_exp33.exe
//   DXMT_ENABLE_NVEXT=1 CIDRE_PRESENTATION_CACHEE=1 CIDRE_DXMT_STATS=1 wine sonde_dlss_exp33.exe [images] [ms] [taille|grand] [charge N]
// « grand » : 1241x779 (texture 1244x780) tout du long, un seul scaler, comme le jeu.
// « charge N » : 16 images d'entree precalculees puis recyclees (le CPU emule ne limite
// plus, ~80 images/s et plus, comme le jeu) et N copies par image d'une texture
// 3456x2234 RGBA16F, pour charger le GPU comme un jeu.
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

static const unsigned BB_W = 1728, BB_H = 1084, OUT_W = 1384, OUT_H = 868, MV_W = 1383, MV_H = 868;
static const float VX = 6.0f, VY = 2.0f;

typedef NVNGX_RESULT (*PFN_Init)(unsigned long long, const wchar_t *, ID3D11Device *, const void *, unsigned int);
typedef NVNGX_RESULT (*PFN_Alloc)(NVNGXParameter **);
typedef NVNGX_RESULT (*PFN_Create)(ID3D11DeviceContext *, unsigned int, NVNGXParameter *, unsigned int **);
typedef NVNGX_RESULT (*PFN_Eval)(ID3D11DeviceContext *, const unsigned int *, NVNGXParameter *, void *);
typedef NVNGX_RESULT (*PFN_Release)(unsigned int *);

static float scene(float x, float y, float t) {
  x -= VX * t; y -= VY * t;
  int cx = (int)std::floor(x / 24.0f), cy = (int)std::floor(y / 24.0f);
  float v = ((cx + cy) & 1) ? 0.8f : 0.2f;
  if (std::fmod(std::fabs(x + 2.0f * y), 61.0f) < 2.0f) v = 1.0f;
  return v * 4.0f; // du HDR, comme une couleur de scene avant tonemapping
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
// R11G11B10_FLOAT : flottants sans signe a 5 bits d'exposant (6, 6 et 5 bits de mantisse)
static uint32_t r11g11b10(float v) {
  uint16_t h = f32_to_f16(v);
  uint32_t r = (h >> 4) & 0x7ff, b = (h >> 5) & 0x3ff;
  return r | (r << 11) | (b << 22);
}

int main(int argc, char **argv) {
  int images = argc > 1 ? atoi(argv[1]) : 600;
  int ms_image = argc > 2 ? atoi(argv[2]) : 12; // ~80 images/s, comme Exp33 sous DLSS
  bool taille = argc > 3 && !strcmp(argv[3], "taille");
  bool grand = argc > 3 && !strcmp(argv[3], "grand"); // 1241x779 tout du long, comme le jeu en passe a
  int charge = (argc > 5 && !strcmp(argv[4], "charge")) ? atoi(argv[5]) : -1;
  bool recycler = charge >= 0;
  HWND hwnd = CreateWindowExA(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "STATIC", "sonde", WS_POPUP, 0, 0, BB_W, BB_H,
                              nullptr, nullptr, GetModuleHandleA(nullptr), nullptr);
  DXGI_SWAP_CHAIN_DESC sd = {};
  sd.BufferDesc.Width = BB_W; sd.BufferDesc.Height = BB_H; sd.BufferDesc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
  sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2;
  sd.OutputWindow = hwnd; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  ID3D11Device *dev = nullptr; ID3D11DeviceContext *ctx = nullptr; IDXGISwapChain *sc = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1, got;
  if (!hwnd || FAILED(D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION,
                                                    &sd, &sc, &dev, &got, &ctx))) {
    printf("ECHEC : device ou fenetre\n"); return 1;
  }
  ID3D11Texture2D *bb = nullptr; sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
  HMODULE ngx = LoadLibraryA("nvngx.dll");
  if (!ngx) { printf("ECHEC : nvngx.dll (DXMT_ENABLE_NVEXT=1 ?)\n"); return 1; }
  auto Init = (PFN_Init)GetProcAddress(ngx, "NVSDK_NGX_D3D11_Init");
  auto Alloc = (PFN_Alloc)GetProcAddress(ngx, "NVSDK_NGX_D3D11_AllocateParameters");
  auto Create = (PFN_Create)GetProcAddress(ngx, "NVSDK_NGX_D3D11_CreateFeature");
  auto Eval = (PFN_Eval)GetProcAddress(ngx, "NVSDK_NGX_D3D11_EvaluateFeature");
  auto Rel = (PFN_Release)GetProcAddress(ngx, "NVSDK_NGX_D3D11_ReleaseFeature");
  Init(1, L"C:\\", dev, nullptr, 0x15);
  auto tex = [&](unsigned w, unsigned h, DXGI_FORMAT f, UINT bind) {
    D3D11_TEXTURE2D_DESC d = {w, h, 1, 1, f, {1, 0}, D3D11_USAGE_DEFAULT, bind, 0, 0};
    ID3D11Texture2D *t = nullptr; dev->CreateTexture2D(&d, nullptr, &t); return t;
  };
  ID3D11Texture2D *mv = tex(MV_W, MV_H, DXGI_FORMAT_R16G16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  ID3D11Texture2D *out = tex(OUT_W, OUT_H, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS);
  {
    std::vector<uint16_t> m(MV_W * MV_H * 2);
    for (size_t i = 0; i < m.size(); i += 2) { m[i] = f32_to_f16(-VX); m[i + 1] = f32_to_f16(-VY); }
    ctx->UpdateSubresource(mv, 0, nullptr, m.data(), MV_W * 4, 0);
  }
  ID3D11Texture2D *lourd_a = nullptr, *lourd_b = nullptr;
  if (charge > 0) {
    lourd_a = tex(3456, 2234, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET);
    lourd_b = tex(3456, 2234, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET);
  }
  struct Passe { unsigned tw, th, cw, ch; } passes[2] = {{1244, 780, 1241, 779}, {692, 436, 692, 434}};
  int debut = (taille || grand) ? 0 : 1;
  int fin = grand ? 1 : 2;
  LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
  int faites = 0;
  for (int pi = debut; pi < fin; pi++) {
    Passe P = passes[pi];
    ID3D11Texture2D *color = tex(P.tw, P.th, DXGI_FORMAT_R11G11B10_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET);
    ID3D11Texture2D *depth = tex(P.tw, P.th, DXGI_FORMAT_R32G8X24_TYPELESS, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL);
    D3D11_DEPTH_STENCIL_VIEW_DESC dvd = {}; dvd.Format = DXGI_FORMAT_D32_FLOAT_S8X24_UINT; dvd.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
    ID3D11DepthStencilView *dsv = nullptr; dev->CreateDepthStencilView(depth, &dvd, &dsv);
    if (!color || !depth || !dsv) { printf("ECHEC : textures d'entree\n"); return 1; }
    // masque de biais d'Unreal (DLSS.Input.Bias.Current.Color.Mask), si SONDE_MASQUE=1 :
    // R8_UNORM a la taille d'entree, une bande verticale « reactive »
    ID3D11Texture2D *masque = nullptr;
    if (getenv("SONDE_MASQUE")) {
      masque = tex(P.tw, P.th, DXGI_FORMAT_R8_UNORM, D3D11_BIND_SHADER_RESOURCE);
      std::vector<uint8_t> m(P.tw * P.th);
      for (unsigned y = 0; y < P.th; y++)
        for (unsigned x = 0; x < P.tw; x++) m[y * P.tw + x] = (x / 64) % 2 ? 255 : 0;
      ctx->UpdateSubresource(masque, 0, nullptr, m.data(), P.tw, 0);
    }
    NVNGXParameter *p = nullptr; Alloc(&p);
    p->Set(NVNGX_Parameter_Width, P.cw); p->Set(NVNGX_Parameter_Height, P.ch);
    p->Set(NVNGX_Parameter_OutWidth, OUT_W); p->Set(NVNGX_Parameter_OutHeight, OUT_H);
    p->Set(NVNGX_Parameter_DLSS_Feature_Create_Flags, (int)(NVNGX_DLSS_FLAG_AUTO_EXPOSURE | NVNGX_DLSS_FLAG_DEPTH_INVERTED));
    unsigned *h = nullptr;
    if (Create(ctx, NVNGX_FEATURE_SUPERSAMPLING, p, &h) != NVNGX_RESULT_OK) { printf("ECHEC : CreateFeature\n"); return 1; }
    std::vector<uint32_t> c(P.tw * P.th);
    int n = taille ? images / 2 : images;
    std::vector<std::vector<uint32_t>> pre;
    if (recycler) // 16 images precalculees : la scene glisse de 16 pas puis recommence
      for (int k = 0; k < 16; k++) {
        float jx = halton(k, 2) - 0.5f, jy = halton(k, 3) - 0.5f;
        float sx = (float)OUT_W / P.cw, sy = (float)OUT_H / P.ch;
        std::vector<uint32_t> b(P.tw * P.th);
        for (unsigned y = 0; y < P.ch; y++)
          for (unsigned x = 0; x < P.cw; x++)
            b[y * P.tw + x] = r11g11b10(scene((x + 0.5f + jx) * sx, (y + 0.5f + jy) * sy, (float)k));
        pre.push_back(std::move(b));
      }
    for (int t = 0; t < n; t++, faites++) {
      LARGE_INTEGER d0, d1; QueryPerformanceCounter(&d0);
      float jx = halton(t % 16, 2) - 0.5f, jy = halton(t % 16, 3) - 0.5f;
      float sx = (float)OUT_W / P.cw, sy = (float)OUT_H / P.ch;
      if (recycler) {
        ctx->UpdateSubresource(color, 0, nullptr, pre[t % 16].data(), P.tw * 4, 0);
      } else {
        for (unsigned y = 0; y < P.ch; y++)
          for (unsigned x = 0; x < P.cw; x++)
            c[y * P.tw + x] = r11g11b10(scene((x + 0.5f + jx) * sx, (y + 0.5f + jy) * sy, (float)faites));
        ctx->UpdateSubresource(color, 0, nullptr, c.data(), P.tw * 4, 0);
      }
      for (int k = 0; k < charge; k++) ctx->CopyResource((k & 1) ? lourd_a : lourd_b, (k & 1) ? lourd_b : lourd_a);
      ctx->ClearDepthStencilView(dsv, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 0.25f, 0); // inversee : proche = 1
      p->Set(NVNGX_Parameter_Color, (ID3D11Resource *)color); p->Set(NVNGX_Parameter_Output, (ID3D11Resource *)out);
      p->Set(NVNGX_Parameter_Depth, (ID3D11Resource *)depth); p->Set(NVNGX_Parameter_MotionVectors, (ID3D11Resource *)mv);
      p->Set(NVNGX_Parameter_Jitter_Offset_X, -jx); p->Set(NVNGX_Parameter_Jitter_Offset_Y, -jy);
      p->Set(NVNGX_Parameter_MV_Scale_X, 1.0f); p->Set(NVNGX_Parameter_MV_Scale_Y, 1.0f);
      p->Set(NVNGX_Parameter_Reset, t == 0 ? 1 : 0);
      p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Width, P.cw);
      p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Height, P.ch);
      p->Set(NVNGX_Parameter_DLSS_Pre_Exposure, 1.0f);
      if (masque) p->Set("DLSS.Input.Bias.Current.Color.Mask", (ID3D11Resource *)masque);
      if (Eval(ctx, h, p, nullptr) != NVNGX_RESULT_OK) { printf("ECHEC : Evaluate\n"); return 1; }
      D3D11_BOX box = {0, 0, 0, OUT_W, OUT_H, 1};
      ctx->CopySubresourceRegion(bb, 0, 0, 0, 0, out, 0, &box);
      sc->Present(0, 0);
      QueryPerformanceCounter(&d1);
      int reste = ms_image - (int)(1000.0 * (d1.QuadPart - d0.QuadPart) / fq.QuadPart);
      if (reste > 0) Sleep(reste);
    }
    Rel(h);
    if (masque) masque->Release();
    dsv->Release(); depth->Release(); color->Release();
  }
  QueryPerformanceCounter(&t1);
  printf("%d images en %.2f s (%.1f images/s)\nOK\n", faites, (t1.QuadPart - t0.QuadPart) / (double)fq.QuadPart,
         faites / ((t1.QuadPart - t0.QuadPart) / (double)fq.QuadPart));
  return 0;
}
