// Sonde hors jeu de GetData sur D3D11_QUERY_EVENT (correctif Cidre 0228 : miroir de
// l'evenement de la file, sans appel Unix). A chaque image : un calcul de quelques ms
// ecrit un tampon, End(requete), puis attente active GetData(DONOTFLUSH) comme un jeu
// qui attend le GPU. Quand GetData rend S_OK : la copie relue doit porter la valeur de
// l'image (sinon la requete a ete signalee avant le GPU), et on compte les Map(DO_NOT_WAIT)
// encore « occupes » (DXMT ne rend la copie qu'apres son fil de fin ; avec 0228, la
// requete n'est vue signalee qu'apres lui : 0 attendu). GetData par image et latence.
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 sonde_getdata_event.cpp -ld3d11 -static -o sonde_getdata_event.exe
//   wine sonde_getdata_event.exe [images, 200]          (CIDRE_DXMT_SIGNALED_UNIX=1 : ancien chemin)
// Codes : 0 ok, 2 valeur fausse (requete signalee avant le GPU), 1 echec.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <algorithm>

typedef HRESULT(WINAPI *PFN_Compile)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *, ID3DInclude *, LPCSTR, LPCSTR,
                                     UINT, UINT, ID3DBlob **, ID3DBlob **);

static const char *CS = R"(
RWStructuredBuffer<uint> b : register(u0);
cbuffer c : register(b0) { uint image; uint tours; uint pad0; uint pad1; };
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint h = id.x;
  [loop] for (uint k = 0; k < tours; k++)
    h = h * 1664525u + 1013904223u;
  b[id.x] = image + (h == 0x12345678u ? 1u : 0u);
}
)";

int main(int argc, char **argv) {
  int images = argc > 1 ? atoi(argv[1]) : 200;
  const UINT N = 1u << 18;
  ID3D11Device *dev = nullptr;
  ID3D11DeviceContext *ctx = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1;
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &dev, nullptr,
                               &ctx))) {
    printf("ECHEC : D3D11CreateDevice\n");
    return 1;
  }
  HMODULE dc = LoadLibraryA("d3dcompiler_47.dll");
  auto Compile = dc ? (PFN_Compile)GetProcAddress(dc, "D3DCompile") : nullptr;
  ID3DBlob *code = nullptr, *err = nullptr;
  if (!Compile || FAILED(Compile(CS, strlen(CS), "cs", nullptr, nullptr, "main", "cs_5_0", 0, 0, &code, &err))) {
    printf("ECHEC : compilation %s\n", err ? (const char *)err->GetBufferPointer() : "");
    return 1;
  }
  ID3D11ComputeShader *cs = nullptr;
  dev->CreateComputeShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &cs);
  D3D11_BUFFER_DESC bd = {};
  bd.ByteWidth = N * 4; bd.Usage = D3D11_USAGE_DEFAULT; bd.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
  bd.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED; bd.StructureByteStride = 4;
  ID3D11Buffer *buf = nullptr, *lecture = nullptr, *cb = nullptr;
  dev->CreateBuffer(&bd, nullptr, &buf);
  bd.Usage = D3D11_USAGE_STAGING; bd.BindFlags = 0; bd.CPUAccessFlags = D3D11_CPU_ACCESS_READ; bd.MiscFlags = 0;
  dev->CreateBuffer(&bd, nullptr, &lecture);
  D3D11_BUFFER_DESC cd = {};
  cd.ByteWidth = 16; cd.Usage = D3D11_USAGE_DYNAMIC; cd.BindFlags = D3D11_BIND_CONSTANT_BUFFER; cd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  dev->CreateBuffer(&cd, nullptr, &cb);
  D3D11_UNORDERED_ACCESS_VIEW_DESC ud = {};
  ud.ViewDimension = D3D11_UAV_DIMENSION_BUFFER; ud.Buffer.NumElements = N;
  ID3D11UnorderedAccessView *uav = nullptr;
  dev->CreateUnorderedAccessView(buf, &ud, &uav);
  D3D11_QUERY_DESC qd = {D3D11_QUERY_EVENT, 0};
  ID3D11Query *q = nullptr;
  if (!cs || !buf || !lecture || !cb || !uav || FAILED(dev->CreateQuery(&qd, &q))) { printf("ECHEC : ressources\n"); return 1; }

  const char *opt = getenv("CIDRE_DXMT_SIGNALED_UNIX");
  printf("sonde_getdata_event : %d images, chemin %s\n", images, opt && !strcmp(opt, "1") ? "Unix (repli)" : "miroir (0228)");
  std::vector<double> lat;
  std::vector<uint64_t> polls;
  int tot = 0, faux = 0;
  for (int i = 0; i < images; i++) {
    D3D11_MAPPED_SUBRESOURCE m;
    ctx->Map(cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m);
    uint32_t c[4] = {(uint32_t)i + 1, 2000, 0, 0};
    memcpy(m.pData, c, 16);
    ctx->Unmap(cb, 0);
    ctx->CSSetShader(cs, nullptr, 0);
    ctx->CSSetConstantBuffers(0, 1, &cb);
    ctx->CSSetUnorderedAccessViews(0, 1, &uav, nullptr);
    ctx->Dispatch(N / 64, 1, 1);
    ctx->CopyResource(lecture, buf);
    ctx->End(q);
    ctx->Flush();
    auto t0 = std::chrono::steady_clock::now();
    uint64_t n = 0;
    HRESULT hr;
    do {
      n++;
      hr = ctx->GetData(q, nullptr, 0, D3D11_ASYNC_GETDATA_DONOTFLUSH);
    } while (hr == S_FALSE && n < 2000000000ull);
    double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    if (hr != S_OK) { printf("ECHEC : GetData = %#lx\n", (unsigned long)hr); return 1; }
    // signalee : la copie doit etre la, sans attendre
    hr = ctx->Map(lecture, 0, D3D11_MAP_READ, D3D11_MAP_FLAG_DO_NOT_WAIT, &m);
    if (hr == DXGI_ERROR_WAS_STILL_DRAWING) {
      tot++;
      ctx->Map(lecture, 0, D3D11_MAP_READ, 0, &m);
    }
    uint32_t v0 = ((uint32_t *)m.pData)[0], vn = ((uint32_t *)m.pData)[N - 1];
    ctx->Unmap(lecture, 0);
    if (v0 < (uint32_t)i + 1 || vn < (uint32_t)i + 1) faux++;
    lat.push_back(ms);
    polls.push_back(n);
  }
  std::sort(lat.begin(), lat.end());
  std::sort(polls.begin(), polls.end());
  double somme = 0; for (double x : lat) somme += x;
  printf("resultat : %d images, GetData par image median %llu (max %llu), attente mediane %.3f ms p99 %.3f ms moyenne %.3f ms, "
         "Map(DO_NOT_WAIT) encore occupe %d, valeur fausse %d\n",
         images, (unsigned long long)polls[polls.size() / 2], (unsigned long long)polls.back(), lat[lat.size() / 2],
         lat[(size_t)(lat.size() * 0.99)], somme / images, tot, faux);
  return faux ? 2 : 0;
}
