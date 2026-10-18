// Sonde hors jeu du DLSS de DXMT (dlss = "metalfx") : un programme D3D11 x64
// qui fait ce que fait le plugin DLSS d'un jeu -- nvapi64 (NvAPI_Initialize),
// nvngx (Init, parametres de capacite, reglage optimal, CreateFeature,
// EvaluateFeature a chaque image) -- sur une scene analytique : damier fin et
// traits obliques qui glissent de (VX, VY) pixels de sortie par image, rendue
// a basse definition avec un jitter de Halton, profondeur constante, vecteurs
// de mouvement exacts (convention DLSS : vers l'image precedente, en pixels de
// rendu). La sortie relue est comparee a la scene rendue directement en haute
// definition (PSNR), et a un agrandissement bilineaire de l'entree : MetalFX
// temporel doit battre le bilineaire. Le jitter est passe dans les deux
// conventions : celle de DLSS (Unreal : TemporalJitterPixels = moins le decalage
// du point d'echantillonnage, signe -1 ici) doit gagner, DXMT le passant tel quel
// a MetalFX.
//
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 -I<dxmt>/src/nvngx sonde_dlss_metalfx.cpp -ld3d11 -ldxgi -o sonde_dlss_metalfx.exe
//   DXMT_ENABLE_NVEXT=1 wine sonde_dlss_metalfx.exe [sortie.ppm]
//
// Codes de sortie : 0 ok, 1 echec (dit sur la sortie standard).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>
#include <cstdlib>
#include "nvngx.hpp"

static const unsigned OUT_W = 1728, OUT_H = 1084; // la sortie d'Expedition 33 sur le M1
static float VX = 3.0f, VY = 1.0f;                // glissement par image, en pixels de sortie (argv 2 et 3)
static const int IMAGES = 48;

typedef NVNGX_RESULT (*PFN_Init)(unsigned long long, const wchar_t *, ID3D11Device *, const void *, unsigned int);
typedef NVNGX_RESULT (*PFN_GetCaps)(NVNGXParameter **);
typedef NVNGX_RESULT (*PFN_Alloc)(NVNGXParameter **);
typedef NVNGX_RESULT (*PFN_Create)(ID3D11DeviceContext *, unsigned int, NVNGXParameter *, unsigned int **);
typedef NVNGX_RESULT (*PFN_Eval)(ID3D11DeviceContext *, const unsigned int *, NVNGXParameter *, void *);
typedef NVNGX_RESULT (*PFN_Release)(unsigned int *);
typedef NVNGX_RESULT (*PFN_Optimal)(NVNGXParameter *);
typedef void *(__cdecl *PFN_NvQuery)(unsigned int);
typedef int (*PFN_NvInit)();

// la scene, en coordonnees de pixels de sortie, a l'instant t (images)
static float scene(float x, float y, int t) {
  x -= VX * t; y -= VY * t;
  int cx = (int)std::floor(x / 12.0f), cy = (int)std::floor(y / 12.0f);
  float v = ((cx + cy) & 1) ? 0.85f : 0.15f;
  float d = std::fmod(std::fabs(x + 2.0f * y), 37.0f);
  if (d < 1.0f) v = 1.0f; // trait oblique d'un pixel
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
static float f16_to_f32(uint16_t h) {
  uint32_t s = (h & 0x8000) << 16, e = (h >> 10) & 0x1f, m = h & 0x3ff, x;
  if (e == 0) x = s; else if (e == 31) x = s | 0x7f800000 | (m << 13); else x = s | ((e - 15 + 127) << 23) | (m << 13);
  float f; memcpy(&f, &x, 4); return f;
}

static double psnr(const std::vector<float> &a, const std::vector<float> &b, unsigned w, unsigned h, unsigned marge) {
  double se = 0; size_t n = 0;
  for (unsigned y = marge; y < h - marge; y++)
    for (unsigned x = marge; x < w - marge; x++) { double d = a[y * w + x] - b[y * w + x]; se += d * d; n++; }
  double mse = se / n; return mse > 0 ? 10 * std::log10(1.0 / mse) : 99;
}

int main(int argc, char **argv) {
  const char *ppm = argc > 1 && strcmp(argv[1], "-") ? argv[1] : nullptr;
  float MVK = 1.0f; // multiplicateur des vecteurs ecrits (essai de convention), argv 4
  if (argc > 3) { VX = atof(argv[2]); VY = atof(argv[3]); }
  if (argc > 4) MVK = atof(argv[4]);
  printf("glissement : %.2f, %.2f pixels de sortie par image\n", VX, VY);
  ID3D11Device *dev = nullptr; ID3D11DeviceContext *ctx = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1, got;
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &dev, &got, &ctx))) {
    printf("ECHEC : D3D11CreateDevice\n"); return 1;
  }
  IDXGIDevice *xd = nullptr; IDXGIAdapter *ad = nullptr; DXGI_ADAPTER_DESC desc = {};
  dev->QueryInterface(__uuidof(IDXGIDevice), (void **)&xd); xd->GetAdapter(&ad); ad->GetDesc(&desc);
  printf("adaptateur : %ls, VendorId %04x\n", desc.Description, desc.VendorId);
  if (desc.VendorId != 0x10de) printf("  (pas 10de : DXMT_ENABLE_NVEXT=1 absent ?)\n");

  HMODULE nvapi = LoadLibraryA("nvapi64.dll");
  if (!nvapi) { printf("ECHEC : nvapi64.dll ne se charge pas (%lu)\n", GetLastError()); return 1; }
  auto q = (PFN_NvQuery)GetProcAddress(nvapi, "nvapi_QueryInterface");
  int nvr = q ? ((PFN_NvInit)q(0x0150e828))() : -1;
  printf("nvapi : NvAPI_Initialize = %d\n", nvr);

  HMODULE ngx = LoadLibraryA("nvngx.dll");
  if (!ngx) { printf("ECHEC : nvngx.dll ne se charge pas (%lu)\n", GetLastError()); return 1; }
  auto Init = (PFN_Init)GetProcAddress(ngx, "NVSDK_NGX_D3D11_Init");
  auto Caps = (PFN_GetCaps)GetProcAddress(ngx, "NVSDK_NGX_D3D11_GetCapabilityParameters");
  auto Alloc = (PFN_Alloc)GetProcAddress(ngx, "NVSDK_NGX_D3D11_AllocateParameters");
  auto Create = (PFN_Create)GetProcAddress(ngx, "NVSDK_NGX_D3D11_CreateFeature");
  auto Eval = (PFN_Eval)GetProcAddress(ngx, "NVSDK_NGX_D3D11_EvaluateFeature");
  auto Rel = (PFN_Release)GetProcAddress(ngx, "NVSDK_NGX_D3D11_ReleaseFeature");
  if (!Init || !Caps || !Alloc || !Create || !Eval || !Rel) { printf("ECHEC : export nvngx manquant\n"); return 1; }
  if (Init(0x1234, L"C:\\", dev, nullptr, 0x15) != NVNGX_RESULT_OK) { printf("ECHEC : NGX Init\n"); return 1; }

  NVNGXParameter *caps = nullptr; Caps(&caps);
  unsigned dispo = 0; caps->Get("SuperSampling.Available", &dispo);
  void *cb = nullptr; caps->Get(NVNGX_Parameter_DLSSOptimalSettingsCallback, &cb);
  caps->Set(NVNGX_Parameter_Width, OUT_W); caps->Set(NVNGX_Parameter_Height, OUT_H);
  caps->Set(NVNGX_Parameter_PerfQualityValue, (int)NVNGX_PERFQUALITY_MAXPERF);
  unsigned in_w = 0, in_h = 0;
  if (cb) ((PFN_Optimal)cb)(caps);
  caps->Get(NVNGX_Parameter_OutWidth, &in_w); caps->Get(NVNGX_Parameter_OutHeight, &in_h);
  printf("DLSS disponible : %u ; Performance pour %ux%u -> rendu %ux%u\n", dispo, OUT_W, OUT_H, in_w, in_h);
  if (!dispo || !in_w || !in_h) { printf("ECHEC : capacites DLSS\n"); return 1; }

  // textures du jeu : couleur RGBA16F, profondeur D32, vecteurs RG16F, sortie RGBA16F en UAV
  auto tex = [&](unsigned w, unsigned h, DXGI_FORMAT f, UINT bind) {
    D3D11_TEXTURE2D_DESC d = {w, h, 1, 1, f, {1, 0}, D3D11_USAGE_DEFAULT, bind, 0, 0};
    ID3D11Texture2D *t = nullptr; dev->CreateTexture2D(&d, nullptr, &t); return t;
  };
  ID3D11Texture2D *color = tex(in_w, in_h, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  ID3D11Texture2D *depth = tex(in_w, in_h, DXGI_FORMAT_R32_TYPELESS, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL);
  ID3D11Texture2D *mv = tex(in_w, in_h, DXGI_FORMAT_R16G16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  ID3D11Texture2D *out = tex(OUT_W, OUT_H, DXGI_FORMAT_R16G16B16A16_FLOAT, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS);
  D3D11_TEXTURE2D_DESC sd = {OUT_W, OUT_H, 1, 1, DXGI_FORMAT_R16G16B16A16_FLOAT, {1, 0}, D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ, 0};
  ID3D11Texture2D *staging = nullptr; dev->CreateTexture2D(&sd, nullptr, &staging);
  if (!color || !depth || !mv || !out || !staging) { printf("ECHEC : textures\n"); return 1; }
  D3D11_DEPTH_STENCIL_VIEW_DESC dvd = {}; dvd.Format = DXGI_FORMAT_D32_FLOAT; dvd.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
  ID3D11DepthStencilView *dsv = nullptr; dev->CreateDepthStencilView(depth, &dvd, &dsv);
  ctx->ClearDepthStencilView(dsv, D3D11_CLEAR_DEPTH, 0.5f, 0);
  {
    // vecteurs en pixels de rendu, vers l'image precedente : -v * (rendu / sortie)
    std::vector<uint16_t> m(in_w * in_h * 2);
    uint16_t mx = f32_to_f16(-MVK * VX * in_w / OUT_W), my = f32_to_f16(-MVK * VY * in_h / OUT_H);
    for (size_t i = 0; i < m.size(); i += 2) { m[i] = mx; m[i + 1] = my; }
    ctx->UpdateSubresource(mv, 0, nullptr, m.data(), in_w * 4, 0);
  }

  // reference haute definition et agrandissement bilineaire de la derniere entree
  std::vector<float> ref(OUT_W * OUT_H), bil(OUT_W * OUT_H), sortie(OUT_W * OUT_H), entree(in_w * in_h);
  float sx = (float)OUT_W / in_w, sy = (float)OUT_H / in_h;
  int code = 0; double meilleur = -1; int meilleur_signe = 0;

  for (int signe = 1; signe >= -1; signe -= 2) {
    NVNGXParameter *p = nullptr; Alloc(&p);
    p->Set(NVNGX_Parameter_Width, in_w); p->Set(NVNGX_Parameter_Height, in_h);
    p->Set(NVNGX_Parameter_OutWidth, OUT_W); p->Set(NVNGX_Parameter_OutHeight, OUT_H);
    p->Set(NVNGX_Parameter_PerfQualityValue, (int)NVNGX_PERFQUALITY_MAXPERF);
    p->Set(NVNGX_Parameter_DLSS_Feature_Create_Flags, (int)(NVNGX_DLSS_FLAG_MV_LOWRES));
    unsigned *h = nullptr;
    NVNGX_RESULT cr = Create(ctx, NVNGX_FEATURE_SUPERSAMPLING, p, &h);
    if (cr != NVNGX_RESULT_OK || !h) { printf("ECHEC : CreateFeature = %#x\n", cr); return 1; }
    LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq);
    double ms_total = 0;
    for (int t = 0; t < IMAGES; t++) {
      float jx = halton(t % 16, 2) - 0.5f, jy = halton(t % 16, 3) - 0.5f; // en pixels de rendu
      std::vector<uint16_t> c(in_w * in_h * 4);
      for (unsigned y = 0; y < in_h; y++)
        for (unsigned x = 0; x < in_w; x++) {
          float v = scene((x + 0.5f + jx) * sx, (y + 0.5f + jy) * sy, t);
          entree[y * in_w + x] = v;
          uint16_t hv = f32_to_f16(v), one = f32_to_f16(1.0f);
          uint16_t *px = &c[(y * in_w + x) * 4]; px[0] = px[1] = px[2] = hv; px[3] = one;
        }
      ctx->UpdateSubresource(color, 0, nullptr, c.data(), in_w * 8, 0);
      p->Set(NVNGX_Parameter_Color, (ID3D11Resource *)color);
      p->Set(NVNGX_Parameter_Output, (ID3D11Resource *)out);
      p->Set(NVNGX_Parameter_Depth, (ID3D11Resource *)depth);
      p->Set(NVNGX_Parameter_MotionVectors, (ID3D11Resource *)mv);
      p->Set(NVNGX_Parameter_Jitter_Offset_X, signe * jx);
      p->Set(NVNGX_Parameter_Jitter_Offset_Y, signe * jy);
      p->Set(NVNGX_Parameter_MV_Scale_X, 1.0f); p->Set(NVNGX_Parameter_MV_Scale_Y, 1.0f);
      p->Set(NVNGX_Parameter_Reset, t == 0 ? 1 : 0);
      p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Width, in_w);
      p->Set(NVNGX_Parameter_DLSS_Render_Subrect_Dimensions_Height, in_h);
      p->Set(NVNGX_Parameter_DLSS_Pre_Exposure, 1.0f);
      QueryPerformanceCounter(&t0);
      NVNGX_RESULT er = Eval(ctx, h, p, nullptr);
      ctx->CopyResource(staging, out);
      D3D11_MAPPED_SUBRESOURCE map;
      if (er != NVNGX_RESULT_OK || FAILED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &map))) { printf("ECHEC : Evaluate/Map\n"); return 1; }
      QueryPerformanceCounter(&t1);
      if (t >= 8) ms_total += 1000.0 * (t1.QuadPart - t0.QuadPart) / fq.QuadPart;
      if (t == IMAGES - 1) {
        for (unsigned y = 0; y < OUT_H; y++) {
          const uint16_t *row = (const uint16_t *)((const char *)map.pData + y * map.RowPitch);
          for (unsigned x = 0; x < OUT_W; x++) sortie[y * OUT_W + x] = f16_to_f32(row[x * 4]);
        }
      }
      ctx->Unmap(staging, 0);
    }
    int t = IMAGES - 1;
    float jx = halton(t % 16, 2) - 0.5f, jy = halton(t % 16, 3) - 0.5f;
    for (unsigned y = 0; y < OUT_H; y++)
      for (unsigned x = 0; x < OUT_W; x++) {
        ref[y * OUT_W + x] = scene(x + 0.5f, y + 0.5f, t);
        // bilineaire : position de rendu (sans le jitter de la derniere image)
        float u = (x + 0.5f) / sx - 0.5f - jx, v = (y + 0.5f) / sy - 0.5f - jy;
        int u0 = (int)std::floor(u), v0 = (int)std::floor(v); float fu = u - u0, fv = v - v0;
        auto e = [&](int a, int b) { a = a < 0 ? 0 : a >= (int)in_w ? in_w - 1 : a; b = b < 0 ? 0 : b >= (int)in_h ? in_h - 1 : b; return entree[b * in_w + a]; };
        bil[y * OUT_W + x] = (e(u0, v0) * (1 - fu) + e(u0 + 1, v0) * fu) * (1 - fv) + (e(u0, v0 + 1) * (1 - fu) + e(u0 + 1, v0 + 1) * fu) * fv;
      }
    double moy = 0; for (float v : sortie) moy += v; moy /= sortie.size();
    double p_mfx = psnr(sortie, ref, OUT_W, OUT_H, 16), p_bil = psnr(bil, ref, OUT_W, OUT_H, 16);
    printf("jitter signe %+d : MetalFX %.2f dB, bilineaire %.2f dB, moyenne %.3f (attendu ~0.5), %.2f ms par image (Evaluate + relecture)\n",
           signe, p_mfx, p_bil, moy, ms_total / (IMAGES - 8));
    if (moy < 0.2 || moy > 0.8) { printf("ECHEC : sortie noire ou saturee\n"); code = 1; }
    if (p_mfx > meilleur) { meilleur = p_mfx; meilleur_signe = signe; }
    if (signe == -1 && ppm) {
      FILE *f = fopen(ppm, "wb");
      fprintf(f, "P5\n%u %u\n255\n", OUT_W, OUT_H);
      for (float v : sortie) { int b = (int)(v * 255 + 0.5f); fputc(b < 0 ? 0 : b > 255 ? 255 : b, f); }
      fclose(f);
    }
    if (signe == -1 && p_mfx <= p_bil && meilleur <= p_bil) { printf("ECHEC : MetalFX ne bat pas le bilineaire\n"); code = 1; }
    Rel(h);
  }
  printf("meilleur signe de jitter : %+d (%.2f dB)%s\n%s\n", meilleur_signe, meilleur, meilleur_signe == -1 ? " = convention DLSS" : " : convention DLSS PERDANTE", code ? "ECHEC" : "OK");
  return code;
}
