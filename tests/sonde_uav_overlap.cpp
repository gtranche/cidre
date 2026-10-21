// Sonde hors jeu de NvAPI_D3D11_BeginUAVOverlap dans DXMT (option Cidre
// CIDRE_DXMT_SANS_UAV_OVERLAP). Un programme D3D11 x64 qui fait K dispatches de
// suite sur le meme UAV, chacun lisant puis reecrivant chaque element
// (b[i] = b[i] + 1, apres un peu de calcul pour etirer la lecture). Avec les
// barrieres que D3D11 impose entre deux dispatches qui ecrivent le meme UAV, le
// resultat vaut K partout. Entre BeginUAVOverlap et EndUAVOverlap, DXMT retire
// ces barrieres (kIntrapassControlBitIgnoreUAVWaW) dans un encodeur de calcul
// concurrent : les dispatches se chevauchent et des increments se perdent. C'est
// ce que l'application promet de ne jamais faire ; ici on le fait expres pour
// voir si les barrieres sont vraiment retirees, puis remises par l'option.
//
//   mode « sans »    : pas d'appel NvAPI, barrieres gardees -> 0 perte attendue
//   mode « overlap » : BeginUAVOverlap/EndUAVOverlap autour des K dispatches
//                      -> pertes attendues ; 0 avec CIDRE_DXMT_SANS_UAV_OVERLAP=1
//   mode « faute »   : un dispatch qui boucle des milliards de fois par fil, pour
//                      provoquer une expiration GPU et voir le journal GPU
//                      (CIDRE_DXMT_JOURNAL_GPU) ecrire sa ligne ERREUR. Sur le M4
//                      seulement : le M1 (G13) a deja gele sur des fautes GPU.
//
//   x86_64-w64-mingw32-clang++ -O2 -std=c++20 sonde_uav_overlap.cpp -ld3d11 -ldxgi -o sonde_uav_overlap.exe
//   DXMT_ENABLE_NVEXT=1 wine sonde_uav_overlap.exe <sans|overlap> [images] [dispatches]
//
// Sortie : une ligne « resultat : » (elements faux, pertes, temps GPU par image).
// Codes : 0 = aucune perte, 2 = pertes, 1 = echec (dit sur la sortie standard).
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

typedef HRESULT(WINAPI *PFN_Compile)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *, ID3DInclude *, LPCSTR, LPCSTR,
                                     UINT, UINT, ID3DBlob **, ID3DBlob **);
typedef void *(__cdecl *PFN_NvQuery)(unsigned int);
typedef int (*PFN_NvInit)();
typedef int (*PFN_NvOverlap)(IUnknown *);

static const char *CS = R"(
RWStructuredBuffer<uint> b : register(u0);
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint v = b[id.x];
  uint h = v ^ id.x;
  [loop] for (uint k = 0; k < 64; k++)  // etire l'intervalle lecture -> ecriture
    h = h * 1664525u + 1013904223u;
  b[id.x] = v + 1u + (h == 0x12345678u ? 1u : 0u);  // h n'est presque jamais egal : +1
}
)";

// mode faute : b[0] = 0xffffffff au depart, donc ~4 milliards de tours par fil
static const char *CS_FAUTE = R"(
RWStructuredBuffer<uint> b : register(u0);
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint n = b[0];
  uint h = id.x;
  [loop] for (uint k = 0; k < n; k++)
    h = h * 1664525u + 1013904223u;
  b[id.x + 1] = h;
}
)";

int main(int argc, char **argv) {
  bool overlap = argc > 1 && !strcmp(argv[1], "overlap");
  bool faute = argc > 1 && !strcmp(argv[1], "faute");
  if (argc < 2 || (!overlap && !faute && strcmp(argv[1], "sans"))) {
    printf("usage : sonde_uav_overlap.exe <sans|overlap|faute> [images] [dispatches]\n");
    return 1;
  }
  int images = argc > 2 ? atoi(argv[2]) : 30;
  int K = argc > 3 ? atoi(argv[3]) : 64;
  const UINT N = 1u << 20; // 16 384 groupes de 64 : de quoi occuper tout le GPU

  ID3D11Device *dev = nullptr;
  ID3D11DeviceContext *ctx = nullptr;
  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_1;
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &dev, nullptr,
                               &ctx))) {
    printf("ECHEC : D3D11CreateDevice\n");
    return 1;
  }

  PFN_NvOverlap begin = nullptr, end = nullptr;
  if (overlap) {
    HMODULE nvapi = LoadLibraryA("nvapi64.dll");
    auto q = nvapi ? (PFN_NvQuery)GetProcAddress(nvapi, "nvapi_QueryInterface") : nullptr;
    if (!q) { printf("ECHEC : nvapi64.dll (DXMT_ENABLE_NVEXT=1 ?)\n"); return 1; }
    auto init = (PFN_NvInit)q(0x0150e828);
    begin = (PFN_NvOverlap)q(0x65b93ca8);
    end = (PFN_NvOverlap)q(0x2216a357);
    if (!init || !begin || !end || init() != 0) { printf("ECHEC : NvAPI_Initialize / UAVOverlap\n"); return 1; }
  }

  HMODULE dc = LoadLibraryA("d3dcompiler_47.dll");
  auto Compile = dc ? (PFN_Compile)GetProcAddress(dc, "D3DCompile") : nullptr;
  if (!Compile) { printf("ECHEC : d3dcompiler_47\n"); return 1; }
  ID3DBlob *code = nullptr, *err = nullptr;
  const char *src = faute ? CS_FAUTE : CS;
  if (FAILED(Compile(src, strlen(src), "cs", nullptr, nullptr, "main", "cs_5_0", 0, 0, &code, &err))) {
    printf("ECHEC : compilation : %s\n", err ? (const char *)err->GetBufferPointer() : "?");
    return 1;
  }
  ID3D11ComputeShader *cs = nullptr;
  if (FAILED(dev->CreateComputeShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &cs))) {
    printf("ECHEC : CreateComputeShader\n");
    return 1;
  }

  D3D11_BUFFER_DESC bd = {};
  bd.ByteWidth = N * 4;
  bd.Usage = D3D11_USAGE_DEFAULT;
  bd.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
  bd.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
  bd.StructureByteStride = 4;
  ID3D11Buffer *buf = nullptr, *lecture = nullptr;
  if (FAILED(dev->CreateBuffer(&bd, nullptr, &buf))) { printf("ECHEC : CreateBuffer\n"); return 1; }
  bd.Usage = D3D11_USAGE_STAGING;
  bd.BindFlags = 0;
  bd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  bd.MiscFlags = 0;
  if (FAILED(dev->CreateBuffer(&bd, nullptr, &lecture))) { printf("ECHEC : CreateBuffer lecture\n"); return 1; }
  D3D11_UNORDERED_ACCESS_VIEW_DESC ud = {};
  ud.Format = DXGI_FORMAT_UNKNOWN;
  ud.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
  ud.Buffer.NumElements = N;
  ID3D11UnorderedAccessView *uav = nullptr;
  if (FAILED(dev->CreateUnorderedAccessView(buf, &ud, &uav))) { printf("ECHEC : UAV\n"); return 1; }

  if (faute) {
    const UINT grand[4] = {0xffffffffu, 0xffffffffu, 0xffffffffu, 0xffffffffu};
    ctx->ClearUnorderedAccessViewUint(uav, grand);
    ctx->CSSetShader(cs, nullptr, 0);
    ctx->CSSetUnorderedAccessViews(0, 1, &uav, nullptr);
    ctx->Dispatch(N / 64 - 1, 1, 1);
    ctx->CopyResource(lecture, buf);
    printf("sonde_uav_overlap : mode faute, dispatch sans fin soumis ; attente de la relecture\n");
    fflush(stdout);
    auto t0 = std::chrono::steady_clock::now();
    D3D11_MAPPED_SUBRESOURCE m;
    HRESULT hr = ctx->Map(lecture, 0, D3D11_MAP_READ, 0, &m);
    double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    if (SUCCEEDED(hr)) ctx->Unmap(lecture, 0);
    printf("resultat : mode faute, Map %s apres %.1f s (le journal GPU doit montrer une ligne ERREUR)\n",
           SUCCEEDED(hr) ? "rendu" : "en echec", s);
    return 0;
  }

  printf("sonde_uav_overlap : mode %s, %d images, %d dispatches de %u elements, CIDRE_DXMT_SANS_UAV_OVERLAP=%s\n",
         argv[1], images, K, N, getenv("CIDRE_DXMT_SANS_UAV_OVERLAP") ? getenv("CIDRE_DXMT_SANS_UAV_OVERLAP") : "");
  uint64_t faux_total = 0, pertes_total = 0;
  double ms_total = 0;
  const UINT zero[4] = {0, 0, 0, 0};
  for (int img = 0; img < images; img++) {
    ctx->ClearUnorderedAccessViewUint(uav, zero);
    ctx->CSSetShader(cs, nullptr, 0);
    ctx->CSSetUnorderedAccessViews(0, 1, &uav, nullptr);
    auto t0 = std::chrono::steady_clock::now();
    if (overlap) begin(ctx);
    for (int k = 0; k < K; k++)
      ctx->Dispatch(N / 64, 1, 1);
    if (overlap) end(ctx);
    ctx->CopyResource(lecture, buf);
    D3D11_MAPPED_SUBRESOURCE m;
    if (FAILED(ctx->Map(lecture, 0, D3D11_MAP_READ, 0, &m))) { printf("ECHEC : Map\n"); return 1; }
    auto t1 = std::chrono::steady_clock::now();
    const uint32_t *v = (const uint32_t *)m.pData;
    uint64_t faux = 0, pertes = 0;
    uint32_t mini = UINT32_MAX;
    for (UINT i = 0; i < N; i++) {
      // h == constante donne +2 : jamais en pratique, compte comme juste au-dessus de K
      if (v[i] < (uint32_t)K) { faux++; pertes += K - v[i]; }
      if (v[i] < mini) mini = v[i];
    }
    ctx->Unmap(lecture, 0);
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    ms_total += ms;
    faux_total += faux;
    pertes_total += pertes;
    if (img < 3 || faux)
      printf("image %d : %llu elements faux (min %u sur %d), %llu increments perdus, %.2f ms\n", img,
             (unsigned long long)faux, mini, K, (unsigned long long)pertes, ms);
  }
  printf("resultat : mode %s, option %s, %llu elements faux sur %llu, %llu increments perdus, %.2f ms par image\n",
         argv[1], getenv("CIDRE_DXMT_SANS_UAV_OVERLAP") ? getenv("CIDRE_DXMT_SANS_UAV_OVERLAP") : "absente",
         (unsigned long long)faux_total, (unsigned long long)N * images, (unsigned long long)pertes_total,
         ms_total / images);
  return faux_total ? 2 : 0;
}
