/* Sonde D3D11 pour la lecture des tampons types (Buffer<T>) : un VS lit ses
 * sommets par Buffer<uint> (R32_UINT) et Buffer<float4> (RGBA32F, FirstElement
 * non nul, index hors bornes qui doit lire 0) et Buffer<float2> (RG32F, reste
 * en lecture de texture) ; le PS lit un Buffer<float4>. Un tampon DEFAULT et un
 * tampon DYNAMIC (Map DISCARD a chaque image, renommage des sous-allocations)
 * alternent. N images, relecture periodique de deux pixels et comparaison a la
 * valeur attendue. Sert a rejouer sous Wine+DXMT l'option d3d11.rawTypedBufferLoad.
 * Usage : probe_d3d11_tbuf.exe [images=300] */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <string.h>
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
"Buffer<float4> Scene : register(t0);\n"
"Buffer<uint>   Idx   : register(t1);\n"
"Buffer<float2> Uv    : register(t2);\n"
"cbuffer CB : register(b0) { uint Base; uint Oob; uint Pad0; uint Pad1; };\n"
"struct VSOut { float4 pos : SV_Position; float3 col : COLOR; };\n"
"VSOut vs_main(uint id : SV_VertexID) {\n"
"   uint i = Idx[id + Base];\n"
"   float4 p = Scene[i * 2];\n"
"   float4 c = Scene[i * 2 + 1];\n"
"   float4 z = Scene[Oob];\n"            /* hors bornes : 0 */
"   float2 uv = Uv[i];\n"
"   VSOut o; o.pos = float4(p.xy + z.xy, 0, 1);\n"
"   o.col = c.rgb + z.rgb + float3(uv, 0) * 0.0 + float3(0, 0, uv.x * 0.25);\n"
"   return o;\n"
"}\n"
"Buffer<float4> Pal : register(t0);\n"
"RWByteAddressBuffer Out : register(u0);\n"
"[numthreads(8,1,1)] void cs_main(uint3 t : SV_DispatchThreadID) {\n"
"   float4 v = Scene[t.x] + Scene[Oob + t.x];\n"   /* 2e lecture hors bornes : 0 */
"   Out.Store4(t.x * 16, asuint(v));\n"
"}\n"
"float4 ps_main(VSOut i) : SV_Target { return float4(i.col + Pal[3].rgb, 1); }\n";

static ID3D11Buffer *tampon(ID3D11Device *dev, UINT octets, UINT usage, const void *init) {
   D3D11_BUFFER_DESC bd = { .ByteWidth = octets, .Usage = usage, .BindFlags = D3D11_BIND_SHADER_RESOURCE,
      .CPUAccessFlags = usage == D3D11_USAGE_DYNAMIC ? D3D11_CPU_ACCESS_WRITE : 0 };
   D3D11_SUBRESOURCE_DATA sd = { init, 0, 0 };
   ID3D11Buffer *b = NULL;
   if (FAILED(ID3D11Device_CreateBuffer(dev, &bd, init ? &sd : NULL, &b))) { printf("ECHEC: tampon\n"); exit(1); }
   return b;
}
static ID3D11ShaderResourceView *vue(ID3D11Device *dev, ID3D11Buffer *b, DXGI_FORMAT f, UINT premier, UINT n) {
   D3D11_SHADER_RESOURCE_VIEW_DESC d = { .Format = f, .ViewDimension = D3D11_SRV_DIMENSION_BUFFER };
   d.Buffer.FirstElement = premier; d.Buffer.NumElements = n;
   ID3D11ShaderResourceView *v = NULL;
   if (FAILED(ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)b, &d, &v))) { printf("ECHEC: vue\n"); exit(1); }
   return v;
}

int main(int argc, char **argv)
{
   int images = argc > 1 ? atoi(argv[1]) : 300;
   HMODULE hd = LoadLibraryA("d3d11.dll");
   HMODULE hc = LoadLibraryA("d3dcompiler_47.dll");
   if (!hd || !hc) { printf("ECHEC: DLL manquante\n"); return 1; }
   PFN_CREATE creer = (PFN_CREATE)(void *)GetProcAddress(hd, "D3D11CreateDevice");
   PFN_COMPILE compiler_hlsl = (PFN_COMPILE)(void *)GetProcAddress(hc, "D3DCompile");
   ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL fl;
   const D3D_FEATURE_LEVEL fls[] = { D3D_FEATURE_LEVEL_11_0 };
   if (FAILED(creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, fls, 1, D3D11_SDK_VERSION, &dev, &fl, &ctx))) {
      printf("ECHEC: creation du peripherique\n"); return 1; }

   ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
   HRESULT hr = compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "vs_main", "vs_5_0", 0, 0, &vsb, &err);
   if (FAILED(hr)) { printf("ECHEC: compilation VS %s\n", err ? (char *)ID3D10Blob_GetBufferPointer(err) : ""); return 1; }
   hr = compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "ps_main", "ps_5_0", 0, 0, &psb, &err);
   if (FAILED(hr)) { printf("ECHEC: compilation PS %s\n", err ? (char *)ID3D10Blob_GetBufferPointer(err) : ""); return 1; }
   ID3DBlob *csb = NULL;
   hr = compiler_hlsl(HLSL, strlen(HLSL), "p.hlsl", NULL, NULL, "cs_main", "cs_5_0", 0, 0, &csb, &err);
   if (FAILED(hr)) { printf("ECHEC: compilation CS %s\n", err ? (char *)ID3D10Blob_GetBufferPointer(err) : ""); return 1; }
   ID3D11ComputeShader *cs = NULL;
   if (FAILED(ID3D11Device_CreateComputeShader(dev, ID3D10Blob_GetBufferPointer(csb), ID3D10Blob_GetBufferSize(csb), NULL, &cs))) {
      printf("ECHEC: creation du CS\n"); return 1; }
   ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
   if (FAILED(ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs)) ||
       FAILED(ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps))) {
      printf("ECHEC: creation des shaders\n"); return 1; }

   /* Scene : 2 elements de bourrage puis 3 sommets x (position, couleur) = 8 elements ; vue a partir de 2, 6 elements */
   float scene[8][4] = { {9,9,9,9}, {9,9,9,9},
      {-0.9f,-0.9f,0,1}, {1.0f,0.5f,0.25f,1}, {0.0f,0.9f,0,1}, {1.0f,0.5f,0.25f,1}, {0.9f,-0.9f,0,1}, {1.0f,0.5f,0.25f,1} };
   unsigned idx[8] = { 7, 7, 7, 7, 0, 1, 2, 7 };       /* Base = 4 */
   float uv[4][2] = { {1,0}, {1,0}, {1,0}, {1,0} };     /* uv.x = 1 -> +0.25 en bleu */
   float pal[4][4] = { {0,0,0,0}, {0,0,0,0}, {0,0,0,0}, {0, 0.25f, 0, 0} };
   ID3D11Buffer *bScene = tampon(dev, sizeof scene, D3D11_USAGE_DEFAULT, scene);
   ID3D11Buffer *bSceneDyn = tampon(dev, sizeof scene, D3D11_USAGE_DYNAMIC, NULL);
   ID3D11Buffer *bIdx = tampon(dev, sizeof idx, D3D11_USAGE_DEFAULT, idx);
   ID3D11Buffer *bUv = tampon(dev, sizeof uv, D3D11_USAGE_DEFAULT, uv);
   ID3D11Buffer *bPal = tampon(dev, sizeof pal, D3D11_USAGE_DEFAULT, pal);
   ID3D11ShaderResourceView *vScene = vue(dev, bScene, DXGI_FORMAT_R32G32B32A32_FLOAT, 2, 6);
   ID3D11ShaderResourceView *vSceneDyn = vue(dev, bSceneDyn, DXGI_FORMAT_R32G32B32A32_FLOAT, 2, 6);
   ID3D11ShaderResourceView *vIdx = vue(dev, bIdx, DXGI_FORMAT_R32_UINT, 0, 8);
   ID3D11ShaderResourceView *vUv = vue(dev, bUv, DXGI_FORMAT_R32G32_FLOAT, 0, 4);
   ID3D11ShaderResourceView *vPal = vue(dev, bPal, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 4);
   unsigned cbdata[4] = { 4, 1000000u, 0, 0 };       /* Base, Oob */
   D3D11_BUFFER_DESC cbd = { .ByteWidth = sizeof cbdata, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_CONSTANT_BUFFER };
   D3D11_SUBRESOURCE_DATA cbs = { cbdata, 0, 0 }; ID3D11Buffer *cb = NULL;
   ID3D11Device_CreateBuffer(dev, &cbd, &cbs, &cb);

   D3D11_TEXTURE2D_DESC td = { .Width = 64, .Height = 64, .MipLevels = 1, .ArraySize = 1,
      .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0}, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_RENDER_TARGET };
   ID3D11Texture2D *cible = NULL; ID3D11RenderTargetView *rtv = NULL;
   ID3D11Device_CreateTexture2D(dev, &td, NULL, &cible);
   ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)cible, NULL, &rtv);
   D3D11_TEXTURE2D_DESC sd = td; sd.Usage = D3D11_USAGE_STAGING; sd.BindFlags = 0; sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
   ID3D11Texture2D *lec = NULL; ID3D11Device_CreateTexture2D(dev, &sd, NULL, &lec);

   D3D11_BUFFER_DESC od = { .ByteWidth = 8 * 16, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_UNORDERED_ACCESS,
      .MiscFlags = D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS };
   ID3D11Buffer *bOut = NULL; ID3D11Device_CreateBuffer(dev, &od, NULL, &bOut);
   D3D11_UNORDERED_ACCESS_VIEW_DESC ud = { .Format = DXGI_FORMAT_R32_TYPELESS, .ViewDimension = D3D11_UAV_DIMENSION_BUFFER };
   ud.Buffer.NumElements = 32; ud.Buffer.Flags = D3D11_BUFFER_UAV_FLAG_RAW;
   ID3D11UnorderedAccessView *uOut = NULL;
   if (FAILED(ID3D11Device_CreateUnorderedAccessView(dev, (ID3D11Resource *)bOut, &ud, &uOut))) { printf("ECHEC: UAV\n"); return 1; }
   D3D11_BUFFER_DESC rd = { .ByteWidth = 8 * 16, .Usage = D3D11_USAGE_STAGING, .CPUAccessFlags = D3D11_CPU_ACCESS_READ };
   ID3D11Buffer *bLec = NULL; ID3D11Device_CreateBuffer(dev, &rd, NULL, &bLec);

   /* requetes timestamp (UE5 en emet pour ses temps GPU) : disjoint + 2 timestamps par image, GetData a chaque image */
   D3D11_QUERY_DESC qd = { D3D11_QUERY_TIMESTAMP_DISJOINT, 0 }, qt = { D3D11_QUERY_TIMESTAMP, 0 };
   ID3D11Query *qDis = NULL, *qT0 = NULL, *qT1 = NULL;
   ID3D11Device_CreateQuery(dev, &qd, &qDis); ID3D11Device_CreateQuery(dev, &qt, &qT0); ID3D11Device_CreateQuery(dev, &qt, &qT1);
   int ts_ok = 0, ts_tot = 0;

   const float noir[4] = {0, 0, 0, 1};
   D3D11_VIEWPORT vp = {0, 0, 64, 64, 0, 1};
   int faux = 0, verifs = 0;
   for (int img = 0; img < images; ++img) {
      int dyn = img & 1;
      if (dyn) {
         D3D11_MAPPED_SUBRESOURCE m;
         if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)bSceneDyn, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) { printf("ECHEC: Map dyn\n"); return 1; }
         memcpy(m.pData, scene, sizeof scene);
         ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)bSceneDyn, 0);
      }
      ID3D11DeviceContext_Begin(ctx, (ID3D11Asynchronous *)qDis);
      ID3D11DeviceContext_End(ctx, (ID3D11Asynchronous *)qT0);
      ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, noir);
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
      ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
      ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
      ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
      ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
      ID3D11ShaderResourceView *vues[3] = { dyn ? vSceneDyn : vScene, vIdx, vUv };
      ID3D11DeviceContext_VSSetShaderResources(ctx, 0, 3, vues);
      ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, &cb);
      ID3D11DeviceContext_PSSetShaderResources(ctx, 0, 1, &vPal);
      ID3D11DeviceContext_Draw(ctx, 3, 0);
      ID3D11DeviceContext_CSSetShader(ctx, cs, NULL, 0);
      ID3D11DeviceContext_CSSetShaderResources(ctx, 0, 1, &vues[0]);
      ID3D11DeviceContext_CSSetConstantBuffers(ctx, 0, 1, &cb);
      ID3D11DeviceContext_CSSetUnorderedAccessViews(ctx, 0, 1, &uOut, NULL);
      ID3D11DeviceContext_Dispatch(ctx, 1, 1, 1);
      ID3D11UnorderedAccessView *nul = NULL; ID3D11DeviceContext_CSSetUnorderedAccessViews(ctx, 0, 1, &nul, NULL);
      ID3D11DeviceContext_End(ctx, (ID3D11Asynchronous *)qT1);
      ID3D11DeviceContext_End(ctx, (ID3D11Asynchronous *)qDis);
      if (img >= 2) {
         UINT64 t0 = 0, t1 = 0; D3D11_QUERY_DATA_TIMESTAMP_DISJOINT dj = {0, 0};
         ID3D11DeviceContext_Flush(ctx);
         for (int tours = 0; tours < 100000; ++tours) {
            if (ID3D11DeviceContext_GetData(ctx, (ID3D11Asynchronous *)qDis, &dj, sizeof dj, 0) == S_OK &&
                ID3D11DeviceContext_GetData(ctx, (ID3D11Asynchronous *)qT0, &t0, sizeof t0, 0) == S_OK &&
                ID3D11DeviceContext_GetData(ctx, (ID3D11Asynchronous *)qT1, &t1, sizeof t1, 0) == S_OK) break;
         }
         ts_tot++; if (t1 >= t0 && dj.Frequency) ts_ok++;
      }
      if (img % 50 == 49 || img == images - 1) {
         ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)bLec, (ID3D11Resource *)bOut);
         ID3D11DeviceContext_Flush(ctx);
         D3D11_MAPPED_SUBRESOURCE mo;
         if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)bLec, 0, D3D11_MAP_READ, 0, &mo))) { printf("ECHEC: Map CS\n"); return 1; }
         float *o = mo.pData; int okcs = 1;
         for (int k = 0; k < 8; ++k) for (int c = 0; c < 4; ++c) {
            float att = k < 6 ? scene[2 + k][c] : 0.0f;   /* vue de 6 elements : k >= 6 hors bornes */
            if (o[k * 4 + c] != att) okcs = 0;
         }
         verifs++; if (!okcs) faux++;
         printf("image %d : calcul %s (ex. [0]=%g %g %g %g, [6]=%g %g %g %g)\n", img, okcs ? "ok" : "FAUX",
                o[0], o[1], o[2], o[3], o[24], o[25], o[26], o[27]);
         ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)bLec, 0);
         ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)lec, (ID3D11Resource *)cible);
         ID3D11DeviceContext_Flush(ctx);
         D3D11_MAPPED_SUBRESOURCE m;
         if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)lec, 0, D3D11_MAP_READ, 0, &m))) { printf("ECHEC: Map\n"); return 1; }
         unsigned char *base = m.pData;
         unsigned char *centre = base + 40 * m.RowPitch + 32 * 4;
         unsigned char *coin = base + 2 * m.RowPitch + 2 * 4;
         /* attendu : (1, 0.5+0.25, 0.25+0.25) = (255, 191, 128) au centre, noir au coin */
         int ok = abs(centre[0] - 255) <= 1 && abs(centre[1] - 191) <= 1 && abs(centre[2] - 128) <= 1 && coin[0] + coin[1] + coin[2] == 0;
         verifs++; if (!ok) faux++;
         printf("image %d (%s) : centre R=%u V=%u B=%u  coin R=%u V=%u B=%u  %s\n", img, dyn ? "dynamique" : "default",
                centre[0], centre[1], centre[2], coin[0], coin[1], coin[2], ok ? "ok" : "FAUX");
         ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)lec, 0);
      }
   }
   printf("timestamps : %d/%d images avec t1 >= t0 et frequence non nulle\n", ts_ok, ts_tot);
   printf("%s : %d verifications, %d fausses\n", faux ? "RESULTAT: rendu incorrect" : "RESULTAT: lectures de tampons types correctes", verifs, faux);
   return faux ? 1 : 0;
}
