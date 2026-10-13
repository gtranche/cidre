/* Sonde D3D11 pour d3d11.groupedBufferLoad et d3d11.uncheckedBufferRead de DXMT
 * (patch 0121) : l'image est-elle la meme, au bit pres, quand les chargements de
 * tampons (ld_structured, ld_raw) ne font plus qu'un test de borne par
 * instruction, et quand la lecture d'un Buffer<T> n'en fait plus ?
 *
 * Hors ecran : un triangle plein ecran, cible R32G32B32A32_FLOAT de 256x256 relue
 * par une texture de transfert. Le vertex shader et le pixel shader lisent un
 * StructuredBuffer (elements de 12 mots), un ByteAddressBuffer (Load4, Load3,
 * Load2) et deux Buffer<T> (float4, uint4) ; l'index lu depend du pixel, les
 * decalages viennent d'un cbuffer. Par cas, la sonde imprime le condense FNV-1a
 * 64 bits de l'image.
 *
 * Cas (decalages) :
 *   dedans   tous les index dans les tampons
 *   bord     les index depassent la fin, par elements entiers : D3D11 rend zero
 *   cheval   Load4 du tampon brut a cheval sur sa fin (2 mots dedans, 2 dehors) :
 *            seul cas ou d3d11.groupedBufferLoad change l'image (tout a zero)
 *   type     Buffer<T> lu au-dela de sa fin : zero en D3D11, au choix de Metal
 *            avec d3d11.uncheckedBufferRead
 *
 *   probe_d3d11_tampons.exe compiler <dossier>   ecrit <dossier>/<entree>.dxbc par D3DCompile
 *   probe_d3d11_tampons.exe rendre [<dossier>]   rend, en lisant les .dxbc du dossier s'ils y sont
 * Lanceur : tests/sonde_tampons.sh.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <d3d11.h>
#include <d3dcompiler.h>

typedef HRESULT (WINAPI *PFN_CREATE)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                     const D3D_FEATURE_LEVEL *, UINT, UINT,
                                     ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *PFN_COMPILE)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO *,
                                      ID3DInclude *, LPCSTR, LPCSTR, UINT, UINT,
                                      ID3DBlob **, ID3DBlob **);

static const char *HLSL =
   "struct Elem { float4 a; float3 b; uint c; float2 d; uint2 e; };\n"
   "StructuredBuffer<Elem> elems : register(t0);\n"
   "ByteAddressBuffer brut : register(t1);\n"
   "Buffer<float4> typf : register(t2);\n"
   "Buffer<uint4> typu : register(t3);\n"
   "cbuffer C : register(b0) { uint dec_elem; uint dec_brut; uint dec_typ; uint pas_brut; };\n"
   "struct V2P { float4 pos : SV_Position; float4 v0 : V0; float4 v1 : V1; float4 v2 : V2; nointerpolation uint4 v3 : V3; };\n"
   "V2P vs_tampons(uint id : SV_VertexID) {\n"
   "   V2P o; float2 p = float2((id << 1) & 2, id & 2);\n"
   "   o.pos = float4(p * float2(2, -2) + float2(-1, 1), 0.5, 1);\n"
   "   Elem e = elems[id + dec_elem];\n"
   "   uint4 w = brut.Load4((id + dec_brut) * pas_brut);\n"
   "   uint3 w3 = brut.Load3(4 + dec_brut * pas_brut);\n"
   "   o.v0 = e.a; o.v1 = float4(e.b, e.d.x);\n"
   "   o.v2 = typf.Load(id + dec_typ) + float4(w3, e.d.y) * (1.0 / 1024);\n"
   "   o.v3 = w + uint4(e.c, e.e, typu.Load(id + dec_typ).x);\n"
   "   return o;\n"
   "}\n"
   "float4 ps_tampons(V2P i) : SV_Target {\n"
   "   uint k = (uint)i.pos.x + 256 * (uint)i.pos.y;\n"
   "   Elem e = elems[(k % 41) + dec_elem];\n"
   "   uint4 w = brut.Load4(((k % 37) + dec_brut) * pas_brut);\n"
   "   uint2 w2 = brut.Load2(((k % 29) + dec_brut) * pas_brut + 8);\n"
   "   float4 t = typf.Load((k % 53) + dec_typ);\n"
   "   uint4 u = typu.Load((k % 47) + dec_typ);\n"
   "   float4 s = i.v0 + i.v1 * 0.5 + i.v2 * 0.25 + float4(i.v3 % 97) / 97;\n"
   "   s += e.a + float4(e.b, e.c * (1.0 / 65536)) + float4(e.d, e.e) * 0.125;\n"
   "   s += float4(w % 1021) / 1021 + float4(w2 % 509, u.xy % 127) / 509 + t;\n"
   "   return s + 0.25;\n"
   "}\n";

static const struct { const char *entree, *cible; } SHADERS[] = {
   { "vs_tampons", "vs_5_0" }, { "ps_tampons", "ps_5_0" },
};
enum { NB_SHADERS = sizeof SHADERS / sizeof SHADERS[0] };

enum { NB_ELEMS = 64, MOTS_ELEM = 12, MOTS_BRUT = 1022, NB_TYP = 96 };
/* decalages d'element, de brut (en pas), de Buffer<T>, et pas du brut en octets */
static const struct { const char *nom; UINT dec_elem, dec_brut, dec_typ, pas_brut; } CAS[] = {
   { "dedans", 3, 5, 7, 16 },
   { "bord", NB_ELEMS - 20, 256, 7, 16 },   /* elements au-dela de la fin, brut entierement dehors (256 * 16 = 4096 > 4088) */
   { "cheval", 3, 219, 7, 16 },     /* (36 + 219) * 16 = 4080 : mots 1020 et 1021 dedans, 1022 et 1023 dehors */
   { "type", 3, 5, NB_TYP - 30, 16 },
};
enum { NB_CAS = sizeof CAS / sizeof CAS[0] };

#define COTE 256
#define OK(expr, quoi) do { if (FAILED(expr)) { printf("ECHEC: %s\n", quoi); fflush(stdout); return 1; } } while (0)

static void *octets[NB_SHADERS];
static size_t tailles[NB_SHADERS];

static int lire(const char *dossier, int i)
{
   char chemin[1024];
   snprintf(chemin, sizeof chemin, "%s\\%s.dxbc", dossier, SHADERS[i].entree);
   FILE *f = fopen(chemin, "rb");
   if (!f) return 0;
   fseek(f, 0, SEEK_END); tailles[i] = ftell(f); fseek(f, 0, SEEK_SET);
   octets[i] = malloc(tailles[i]);
   size_t lus = fread(octets[i], 1, tailles[i], f);
   fclose(f);
   return lus == tailles[i] && tailles[i] > 0;
}

static int compiler(PFN_COMPILE compiler_hlsl, int i)
{
   ID3DBlob *b = NULL, *err = NULL;
   /* EvaluateAttribute* n'existe que pour le profil pixel */
   static const D3D_SHADER_MACRO pixel[] = { { "ETAGE_PIXEL", "1" }, { NULL, NULL } };
   if (!compiler_hlsl) return 0;
   if (FAILED(compiler_hlsl(HLSL, strlen(HLSL), "sonde_tampons.hlsl", SHADERS[i].cible[0] == 'p' ? pixel : NULL, NULL,
                            SHADERS[i].entree, SHADERS[i].cible,
                            0, 0, &b, &err))) {
      printf("ECHEC: compilation %s : %s\n", SHADERS[i].entree, err ? (char *)ID3D10Blob_GetBufferPointer(err) : "?");
      return 0;
   }
   tailles[i] = ID3D10Blob_GetBufferSize(b);
   octets[i] = malloc(tailles[i]);
   memcpy(octets[i], ID3D10Blob_GetBufferPointer(b), tailles[i]);
   return 1;
}

int main(int argc, char **argv)
{
   const char *mode = argc > 1 ? argv[1] : "rendre";
   const char *dossier = argc > 2 ? argv[2] : NULL;
   const char *chemin_compilateur = getenv("SONDE_D3DCOMPILER");
   HMODULE hc = LoadLibraryA(chemin_compilateur && *chemin_compilateur ? chemin_compilateur : "d3dcompiler_47.dll");
   PFN_COMPILE compiler_hlsl = hc ? (PFN_COMPILE)(void *)GetProcAddress(hc, "D3DCompile") : NULL;

   if (!strcmp(mode, "compiler")) {
      if (!dossier || !compiler_hlsl) { printf("ECHEC: dossier ou d3dcompiler manquant\n"); return 1; }
      for (int i = 0; i < NB_SHADERS; i++) {
         char chemin[1024];
         if (!compiler(compiler_hlsl, i)) return 1;
         snprintf(chemin, sizeof chemin, "%s\\%s.dxbc", dossier, SHADERS[i].entree);
         FILE *f = fopen(chemin, "wb");
         if (!f || fwrite(octets[i], 1, tailles[i], f) != tailles[i]) { printf("ECHEC: ecriture %s\n", chemin); return 1; }
         fclose(f);
         printf("compile %s : %u octets\n", SHADERS[i].entree, (unsigned)tailles[i]);
      }
      return 0;
   }

   int lus = 0;
   for (int i = 0; i < NB_SHADERS; i++) {
      if (dossier && lire(dossier, i)) { lus++; continue; }
      if (!compiler(compiler_hlsl, i)) return 1;
   }
   printf("shaders : %d lus dans le dossier, %d compiles ici\n", lus, NB_SHADERS - lus);

   HMODULE hd = LoadLibraryA("d3d11.dll");
   PFN_CREATE creer = hd ? (PFN_CREATE)(void *)GetProcAddress(hd, "D3D11CreateDevice") : NULL;
   if (!creer) { printf("ECHEC: d3d11.dll\n"); return 1; }
   const D3D_FEATURE_LEVEL fls[] = { D3D_FEATURE_LEVEL_11_0 };
   ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL fl;
   OK(creer(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, fls, 1, D3D11_SDK_VERSION, &dev, &fl, &ctx), "peripherique");

   void *objets[NB_SHADERS] = { 0 };
   for (int i = 0; i < NB_SHADERS; i++) {
      HRESULT hr;
      if (SHADERS[i].cible[0] == 'v')
         hr = ID3D11Device_CreateVertexShader(dev, octets[i], tailles[i], NULL, (ID3D11VertexShader **)&objets[i]);
      else
         hr = ID3D11Device_CreatePixelShader(dev, octets[i], tailles[i], NULL, (ID3D11PixelShader **)&objets[i]);
      if (FAILED(hr)) { printf("ECHEC: creation de %s\n", SHADERS[i].entree); return 1; }
   }

   /* tampons : chaque mot vaut un flottant ou un entier distinct, reconnaissable */
   static union { float f; UINT u; } elems[NB_ELEMS * MOTS_ELEM], brut[MOTS_BRUT];
   static float typf[NB_TYP * 4]; static UINT typu[NB_TYP * 4];
   for (int e = 0; e < NB_ELEMS; e++)
      for (int m = 0; m < MOTS_ELEM; m++) {
         if (m == 7 || m >= 10) elems[e * MOTS_ELEM + m].u = 1000 * e + 17 * m + 1;
         else elems[e * MOTS_ELEM + m].f = (float)(e + 1) + (float)(m + 1) / 16;
      }
   for (int m = 0; m < MOTS_BRUT; m++) brut[m].u = 2654435761u * (m + 1);
   for (int m = 0; m < NB_TYP * 4; m++) { typf[m] = (float)(m + 1) / 8; typu[m] = 40503u * (m + 3); }
   ID3D11Buffer *b_elems = NULL, *b_brut = NULL, *b_typf = NULL, *b_typu = NULL, *b_cb = NULL;
   ID3D11ShaderResourceView *srv[4] = { 0 };
   D3D11_SUBRESOURCE_DATA init = { 0 };
   D3D11_BUFFER_DESC bd = { .ByteWidth = sizeof elems, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_SHADER_RESOURCE,
      .MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED, .StructureByteStride = MOTS_ELEM * 4 };
   init.pSysMem = elems;
   OK(ID3D11Device_CreateBuffer(dev, &bd, &init, &b_elems), "tampon structure");
   OK(ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)b_elems, NULL, &srv[0]), "vue du tampon structure");
   bd.ByteWidth = sizeof brut; bd.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS; bd.StructureByteStride = 0;
   init.pSysMem = brut;
   OK(ID3D11Device_CreateBuffer(dev, &bd, &init, &b_brut), "tampon brut");
   D3D11_SHADER_RESOURCE_VIEW_DESC sd = { .Format = DXGI_FORMAT_R32_TYPELESS, .ViewDimension = D3D11_SRV_DIMENSION_BUFFEREX };
   sd.BufferEx.FirstElement = 0; sd.BufferEx.NumElements = MOTS_BRUT; sd.BufferEx.Flags = D3D11_BUFFEREX_SRV_FLAG_RAW;
   OK(ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)b_brut, &sd, &srv[1]), "vue du tampon brut");
   bd.ByteWidth = sizeof typf; bd.MiscFlags = 0;
   init.pSysMem = typf;
   OK(ID3D11Device_CreateBuffer(dev, &bd, &init, &b_typf), "tampon type flottant");
   D3D11_SHADER_RESOURCE_VIEW_DESC st = { .Format = DXGI_FORMAT_R32G32B32A32_FLOAT, .ViewDimension = D3D11_SRV_DIMENSION_BUFFER };
   st.Buffer.FirstElement = 0; st.Buffer.NumElements = NB_TYP;
   OK(ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)b_typf, &st, &srv[2]), "vue du tampon type flottant");
   init.pSysMem = typu;
   OK(ID3D11Device_CreateBuffer(dev, &bd, &init, &b_typu), "tampon type entier");
   st.Format = DXGI_FORMAT_R32G32B32A32_UINT;
   OK(ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)b_typu, &st, &srv[3]), "vue du tampon type entier");
   D3D11_BUFFER_DESC cd = { .ByteWidth = 16, .Usage = D3D11_USAGE_DEFAULT, .BindFlags = D3D11_BIND_CONSTANT_BUFFER };
   OK(ID3D11Device_CreateBuffer(dev, &cd, NULL, &b_cb), "cbuffer");

   D3D11_TEXTURE2D_DESC td = { .Width = COTE, .Height = COTE, .MipLevels = 1, .ArraySize = 1,
      .Format = DXGI_FORMAT_R32G32B32A32_FLOAT, .SampleDesc = {1, 0}, .Usage = D3D11_USAGE_DEFAULT,
      .BindFlags = D3D11_BIND_RENDER_TARGET };
   ID3D11Texture2D *cible = NULL, *transfert = NULL, *prof = NULL;
   ID3D11RenderTargetView *rtv = NULL; ID3D11DepthStencilView *dsv = NULL;
   OK(ID3D11Device_CreateTexture2D(dev, &td, NULL, &cible), "cible");
   OK(ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)cible, NULL, &rtv), "RTV");
   td.Usage = D3D11_USAGE_STAGING; td.BindFlags = 0; td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
   OK(ID3D11Device_CreateTexture2D(dev, &td, NULL, &transfert), "texture de transfert");
   D3D11_TEXTURE2D_DESC dd = { .Width = COTE, .Height = COTE, .MipLevels = 1, .ArraySize = 1,
      .Format = DXGI_FORMAT_D32_FLOAT, .SampleDesc = {1, 0}, .Usage = D3D11_USAGE_DEFAULT,
      .BindFlags = D3D11_BIND_DEPTH_STENCIL };
   OK(ID3D11Device_CreateTexture2D(dev, &dd, NULL, &prof), "texture de profondeur");
   OK(ID3D11Device_CreateDepthStencilView(dev, (ID3D11Resource *)prof, NULL, &dsv), "DSV");

   D3D11_DEPTH_STENCIL_DESC dsd = { .DepthEnable = TRUE, .DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL,
      .DepthFunc = D3D11_COMPARISON_LESS_EQUAL };
   ID3D11DepthStencilState *dss = NULL;
   OK(ID3D11Device_CreateDepthStencilState(dev, &dsd, &dss), "etat de profondeur");
   D3D11_RASTERIZER_DESC rd = { .FillMode = D3D11_FILL_SOLID, .CullMode = D3D11_CULL_NONE, .DepthClipEnable = TRUE };
   ID3D11RasterizerState *rs = NULL;
   OK(ID3D11Device_CreateRasterizerState(dev, &rd, &rs), "etat de trame");

   D3D11_VIEWPORT vp = { 0, 0, COTE, COTE, 0, 1 };
   ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
   ID3D11DeviceContext_RSSetState(ctx, rs);
   ID3D11DeviceContext_OMSetDepthStencilState(ctx, dss, 0);
   ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

   for (int c = 0; c < NB_CAS; c++) {
      static const float noir[4] = { 0, 0, 0, 0 };
      const UINT cb[4] = { CAS[c].dec_elem, CAS[c].dec_brut, CAS[c].dec_typ, CAS[c].pas_brut };
      ID3D11DeviceContext_UpdateSubresource(ctx, (ID3D11Resource *)b_cb, 0, NULL, cb, 0, 0);
      ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, noir);
      ID3D11DeviceContext_ClearDepthStencilView(ctx, dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
      ID3D11DeviceContext_VSSetShader(ctx, objets[0], NULL, 0);
      ID3D11DeviceContext_PSSetShader(ctx, objets[1], NULL, 0);
      ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, &b_cb);
      ID3D11DeviceContext_PSSetConstantBuffers(ctx, 0, 1, &b_cb);
      ID3D11DeviceContext_VSSetShaderResources(ctx, 0, 4, srv);
      ID3D11DeviceContext_PSSetShaderResources(ctx, 0, 4, srv);
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, dsv);
      ID3D11DeviceContext_Draw(ctx, 3, 0);
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, NULL);
      ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)transfert, (ID3D11Resource *)cible);
      D3D11_MAPPED_SUBRESOURCE m;
      OK(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)transfert, 0, D3D11_MAP_READ, 0, &m), "lecture de la cible");
      unsigned long long condense = 0xcbf29ce484222325ull;
      int couverts = 0;
      float somme[4] = { 0, 0, 0, 0 };
      for (int y = 0; y < COTE; y++) {
         const unsigned char *ligne = (const unsigned char *)m.pData + y * m.RowPitch;
         for (int x = 0; x < COTE * 16; x++) { condense ^= ligne[x]; condense *= 0x100000001b3ull; }
         for (int x = 0; x < COTE; x++) {
            const float *p = (const float *)(ligne + x * 16);
            if (p[0] != 0 || p[1] != 0 || p[2] != 0 || p[3] != 0) couverts++;
            for (int k = 0; k < 4; k++) somme[k] += p[k];
         }
      }
      const float *centre = (const float *)((const unsigned char *)m.pData + 100 * m.RowPitch + 77 * 16);
      printf("cas %-10s condense=%016llx couverts=%d moyenne=%.5f,%.5f,%.5f,%.5f pixel(77,100)=%.6f,%.6f,%.6f,%.6f\n",
             CAS[c].nom, condense, couverts, somme[0] / (COTE * COTE), somme[1] / (COTE * COTE),
             somme[2] / (COTE * COTE), somme[3] / (COTE * COTE), centre[0], centre[1], centre[2], centre[3]);
      fflush(stdout);
      ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)transfert, 0);
   }
   printf("FIN\n");
   return 0;
}
