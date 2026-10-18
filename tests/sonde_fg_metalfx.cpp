// Sonde hors jeu de la generation d'images MetalFX de DXMT (0185) : un programme
// D3D11 x64 qui donne a MTLFXFrameInterpolator, par l'interface privee
// IMTLD3D11ContextExtCidre, deux images d'une scene analytique (t-1 et t, a la
// definition de sortie, comme le backbuffer d'un jeu apres DLSS), la profondeur
// et les vecteurs de mouvement a la definition de rendu (convention DLSS : vers
// l'image precedente, en pixels de rendu). L'image generee est comparee a la
// scene vraie a t-1/2 (PSNR), au melange 50/50 des deux images et a l'image t
// seule. On essaie les vecteurs en pixels de rendu (echelle 1) et en pixels de
// sortie (echelle sortie/rendu) : la bonne convention bat nettement le melange.
//
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 -I<dxmt>/src/d3d11 -I<dxmt>/src/util sonde_fg_metalfx.cpp -ld3d11 -o sonde_fg_metalfx.exe
//   wine sonde_fg_metalfx.exe [prefixe-des-ppm] [vx vy] [format: bgra8|rgba16f|rgb10a2]
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "d3d11_interfaces.hpp"

static const unsigned OUT_W = 1728, OUT_H = 1084, IN_W = 864, IN_H = 542;
static float VX = 6.0f, VY = 2.0f; // glissement par image, en pixels de sortie

static float scene(float x, float y, float t) {
  x -= VX * t; y -= VY * t;
  int cx = (int)std::floor(x / 24.0f), cy = (int)std::floor(y / 24.0f);
  float v = ((cx + cy) & 1) ? 0.8f : 0.2f;
  float d = std::fmod(std::fabs(x + 2.0f * y), 61.0f);
  if (d < 2.0f) v = 1.0f;
  // disque fixe (interface) : ne bouge pas
  float dx = x + VX * t - 200, dy = y + VY * t - 150;
  if (dx * dx + dy * dy < 60 * 60) v = 0.5f;
  return v;
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

static double psnr(const std::vector<float> &a, const std::vector<float> &b) {
  double se = 0; size_t n = 0;
  for (unsigned y = 24; y < OUT_H - 24; y++)
    for (unsigned x = 24; x < OUT_W - 24; x++) { double d = a[y * OUT_W + x] - b[y * OUT_W + x]; se += d * d; n++; }
  double mse = se / n; return mse > 0 ? 10 * std::log10(1.0 / mse) : 99;
}

int main(int argc, char **argv) {
  const char *pre = argc > 1 && strcmp(argv[1], "-") ? argv[1] : nullptr;
  if (argc > 3) { VX = atof(argv[2]); VY = atof(argv[3]); }
  const char *fmtname = argc > 4 ? argv[4] : "bgra8";
  DXGI_FORMAT fmt = !strcmp(fmtname, "rgba16f") ? DXGI_FORMAT_R16G16B16A16_FLOAT
                  : !strcmp(fmtname, "rgb10a2") ? DXGI_FORMAT_R10G10B10A2_UNORM : DXGI_FORMAT_B8G8R8A8_UNORM;
  unsigned bpp = fmt == DXGI_FORMAT_R16G16B16A16_FLOAT ? 8 : 4;
  printf("glissement %.2f, %.2f px de sortie par image ; couleur %s\n", VX, VY, fmtname);

  ID3D11Device *dev = nullptr; ID3D11DeviceContext *ctx = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1, got;
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &dev, &got, &ctx))) {
    printf("ECHEC : D3D11CreateDevice\n"); return 1;
  }
  IMTLD3D11ContextExtCidre *ext = nullptr;
  if (FAILED(ctx->QueryInterface(__uuidof(IMTLD3D11ContextExtCidre), (void **)&ext))) {
    printf("ECHEC : DXMT sans IMTLD3D11ContextExtCidre (0185 absent ?)\n"); return 1;
  }
  auto tex = [&](unsigned w, unsigned h, DXGI_FORMAT f, UINT bind) {
    D3D11_TEXTURE2D_DESC d = {w, h, 1, 1, f, {1, 0}, D3D11_USAGE_DEFAULT, bind, 0, 0};
    ID3D11Texture2D *t = nullptr; dev->CreateTexture2D(&d, nullptr, &t); return t;
  };
  UINT cbind = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  ID3D11Texture2D *c0 = tex(OUT_W, OUT_H, fmt, cbind), *c1 = tex(OUT_W, OUT_H, fmt, cbind);
  ID3D11Texture2D *out = tex(OUT_W, OUT_H, fmt, cbind | D3D11_BIND_UNORDERED_ACCESS);
  ID3D11Texture2D *depth = tex(IN_W, IN_H, DXGI_FORMAT_R32_TYPELESS, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL);
  ID3D11Texture2D *mv = tex(IN_W, IN_H, DXGI_FORMAT_R16G16_FLOAT, D3D11_BIND_SHADER_RESOURCE);
  D3D11_TEXTURE2D_DESC sd = {OUT_W, OUT_H, 1, 1, fmt, {1, 0}, D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ, 0};
  ID3D11Texture2D *staging = nullptr; dev->CreateTexture2D(&sd, nullptr, &staging);
  if (!c0 || !c1 || !out || !depth || !mv || !staging) { printf("ECHEC : textures\n"); return 1; }
  D3D11_DEPTH_STENCIL_VIEW_DESC dvd = {}; dvd.Format = DXGI_FORMAT_D32_FLOAT; dvd.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
  ID3D11DepthStencilView *dsv = nullptr; dev->CreateDepthStencilView(depth, &dvd, &dsv);
  ctx->ClearDepthStencilView(dsv, D3D11_CLEAR_DEPTH, 0.5f, 0);

  auto remplir = [&](ID3D11Texture2D *t, float temps, std::vector<float> &cpu) {
    std::vector<uint8_t> b(OUT_W * OUT_H * bpp);
    cpu.resize(OUT_W * OUT_H);
    for (unsigned y = 0; y < OUT_H; y++)
      for (unsigned x = 0; x < OUT_W; x++) {
        float v = scene(x + 0.5f, y + 0.5f, temps); cpu[y * OUT_W + x] = v;
        uint8_t *p = &b[(y * OUT_W + x) * bpp];
        if (bpp == 8) { uint16_t h = f32_to_f16(v), one = f32_to_f16(1); memcpy(p, &h, 2); memcpy(p + 2, &h, 2); memcpy(p + 4, &h, 2); memcpy(p + 6, &one, 2); }
        else if (fmt == DXGI_FORMAT_R10G10B10A2_UNORM) { uint32_t q = (uint32_t)(v * 1023 + 0.5f); uint32_t w = q | (q << 10) | (q << 20) | (3u << 30); memcpy(p, &w, 4); }
        else { uint8_t q = (uint8_t)(v * 255 + 0.5f); p[0] = p[1] = p[2] = q; p[3] = 255; }
      }
    ctx->UpdateSubresource(t, 0, nullptr, b.data(), OUT_W * bpp, 0);
  };
  auto lire = [&](std::vector<float> &cpu) {
    ctx->CopyResource(staging, out);
    D3D11_MAPPED_SUBRESOURCE m;
    if (FAILED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) return false;
    cpu.resize(OUT_W * OUT_H);
    for (unsigned y = 0; y < OUT_H; y++) {
      const uint8_t *row = (const uint8_t *)m.pData + y * m.RowPitch;
      for (unsigned x = 0; x < OUT_W; x++) {
        const uint8_t *p = row + x * bpp; float v;
        if (bpp == 8) { uint16_t h; memcpy(&h, p, 2); v = f16_to_f32(h); }
        else if (fmt == DXGI_FORMAT_R10G10B10A2_UNORM) { uint32_t w; memcpy(&w, p, 4); v = (w & 0x3ff) / 1023.0f; }
        else v = p[2] / 255.0f; // BGRA : rouge en [2] (gris, peu importe)
        cpu[y * OUT_W + x] = v;
      }
    }
    ctx->Unmap(staging, 0);
    return true;
  };
  auto ecrire = [&](const char *suffixe, const std::vector<float> &cpu) {
    if (!pre) return;
    char nom[512]; snprintf(nom, sizeof nom, "%s-%s.ppm", pre, suffixe);
    FILE *f = fopen(nom, "wb"); fprintf(f, "P5\n%u %u\n255\n", OUT_W, OUT_H);
    for (float v : cpu) { int b = (int)(v * 255 + 0.5f); fputc(b < 0 ? 0 : b > 255 ? 255 : b, f); }
    fclose(f);
  };

  // vecteurs en pixels de rendu, vers l'image precedente
  {
    std::vector<uint16_t> m(IN_W * IN_H * 2);
    uint16_t mx = f32_to_f16(-VX * IN_W / OUT_W), my = f32_to_f16(-VY * IN_H / OUT_H);
    for (size_t i = 0; i < m.size(); i += 2) { m[i] = mx; m[i + 1] = my; }
    ctx->UpdateSubresource(mv, 0, nullptr, m.data(), IN_W * 4, 0);
  }
  std::vector<float> a, b, vrai(OUT_W * OUT_H), melange(OUT_W * OUT_H), gen;
  for (unsigned y = 0; y < OUT_H; y++)
    for (unsigned x = 0; x < OUT_W; x++) vrai[y * OUT_W + x] = scene(x + 0.5f, y + 0.5f, 9.5f);
  int code = 0; double meilleur = -1; float meilleure_echelle = 0;
  const float echelles[] = {1.0f, (float)OUT_W / IN_W};
  for (float ech : echelles) {
    // une courte histoire : quelques paires successives, on mesure la derniere (t = 9 -> 10)
    LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq);
    double ms = 0; int n = 0;
    for (int t = 1; t <= 10; t++) {
      remplir(c0, (float)(t - 1), a);
      remplir(c1, (float)t, b);
      MTL_FRAME_INTERPOLATE_D3D11_DESC d = {};
      d.Color = c1; d.PrevColor = c0; d.Depth = depth; d.MotionVector = mv; d.Output = out;
      d.MotionVectorScaleX = ech; d.MotionVectorScaleY = ech == 1.0f ? 1.0f : (float)OUT_H / IN_H;
      d.DeltaTime = 1.0f / 40; d.NearPlane = 0.1f; d.FarPlane = 1000.0f; d.FieldOfView = 60.0f;
      d.AspectRatio = (float)OUT_W / OUT_H; d.Reset = t == 1; d.DepthReversed = FALSE;
      QueryPerformanceCounter(&t0);
      HRESULT hr = ext->CidreFrameInterpolate(&d);
      if (FAILED(hr)) { printf("ECHEC : CidreFrameInterpolate = %#lx\n", hr); return 1; }
      if (!lire(gen)) { printf("ECHEC : relecture\n"); return 1; }
      QueryPerformanceCounter(&t1);
      if (t > 2) { ms += 1000.0 * (t1.QuadPart - t0.QuadPart) / fq.QuadPart; n++; }
    }
    for (size_t i = 0; i < melange.size(); i++) melange[i] = 0.5f * (a[i] + b[i]);
    double pg = psnr(gen, vrai), pm = psnr(melange, vrai), pb = psnr(b, vrai);
    double moy = 0; for (float v : gen) moy += v; moy /= gen.size();
    printf("vecteurs x%.2f : generee %.2f dB, melange %.2f dB, image t %.2f dB ; moyenne %.3f ; %.2f ms (interpolation + relecture)\n",
           ech, pg, pm, pb, moy, ms / n);
    if (moy < 0.15 || moy > 0.85) { printf("ECHEC : image generee noire ou saturee\n"); code = 1; }
    if (pg > meilleur) { meilleur = pg; meilleure_echelle = ech; }
    char suf[32]; snprintf(suf, sizeof suf, "x%.0f", ech); ecrire(suf, gen);
    if (pg <= pm) printf("  (ne bat pas le melange)\n");
  }
  ecrire("vrai", vrai); ecrire("melange", melange);
  if (meilleur <= psnr(melange, vrai)) { printf("ECHEC : aucune convention ne bat le melange\n"); code = 1; }
  printf("meilleure echelle des vecteurs : x%.2f (%.2f dB)\n%s\n", meilleure_echelle, meilleur, code ? "ECHEC" : "OK");
  return code;
}
