/* Sonde D3D11 pour d3d11.narrowVaryings de DXMT (patch 0116) : l'image est-elle
 * la meme, au bit pres, que les varyings soient declares en float4 (amont) ou a
 * la largeur lue par le pixel shader ?
 *
 * Hors ecran : une grille de 16x16 quads en perspective (w de 1 a 3), fabriquee
 * par SV_VertexID, rendue dans une cible R32G32B32A32_FLOAT de 256x256, relue
 * par une texture de transfert. Pour chaque cas la sonde imprime le condense
 * FNV-1a 64 bits des 256x256x16 octets et le nombre de pixels couverts.
 * Le lanceur (tests/sonde_varyings.sh) fait tourner la sonde deux fois,
 * DXMT_CONFIG="d3d11.narrowVaryings=False" puis "=True", et compare les lignes.
 *
 * Cas (vertex shader, pixel shader) :
 *   tout        VS a 9 varyings float4/uint4/int3, PS qui lit tout (temoin : rien a reduire)
 *   partiel     meme VS, PS qui lit .xy, .z, .xw, .zw, .yz (uint), .x (int), .xz (noperspective)
 *   type        meme VS, PS dont la structure d'entree declare float3/uint3 la ou le VS ecrit
 *               des float4 (que des largeurs 3 : le compilateur de Microsoft tasserait des
 *               float2 ou des float dans un meme registre, et les deux signatures ne se
 *               correspondraient plus)
 *   w           meme VS, PS qui ne lit que des .w
 *   position    meme VS, PS qui ne lit que SV_Position
 *   autre_vs    second VS (autre calcul), meme PS que « partiel » (une variante de PS, deux VS)
 *   tasse       VS a varyings tasses par registre (float2+float2, float3+float), PS qui lit tout
 *   tasse_b     meme VS, PS qui ne lit que le second element de chaque registre
 *   tire        PS avec EvaluateAttributeCentroid (interpolation tiree : pas de reduction)
 *   gs          VS + geometry shader + PS de « partiel » (le GS n'est pas touche, et le meme
 *               PS sert reduit dans « partiel » et non reduit ici)
 *   profondeur  passe sans pixel shader avec le premier VS, puis « partiel » rejoue
 *
 * Deux modes, un meme source :
 *   probe_d3d11_varyings.exe compiler <dossier>   ecrit <dossier>/<entree>.dxbc par D3DCompile
 *   probe_d3d11_varyings.exe rendre [<dossier>]   rend ; lit <dossier>/<entree>.dxbc s'il existe,
 *                                                 compile sinon
 * SONDE_D3DCOMPILER = chemin d'un d3dcompiler_47.dll (defaut : celui de Wine). Le
 * compilateur HLSL de Wine ne tasse pas les registres et declare les entrees
 * entieres ; celui de Microsoft (32 bits dans un dossier de jeu, d'ou le mode
 * « compiler » bati en i686) donne les masques partiels que produit un vrai jeu.
 *
 * Construction :
 *   toolchain/llvm-mingw/bin/x86_64-w64-mingw32-gcc -O1 -o build/probe_d3d11_varyings.exe \
 *      tests/probe_d3d11_varyings.c -ldxguid -luuid
 *   toolchain/llvm-mingw/bin/i686-w64-mingw32-gcc -O1 -o build/probe_d3d11_varyings32.exe \
 *      tests/probe_d3d11_varyings.c -ldxguid -luuid
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
"float h(uint n, uint k) {\n"
"   n = n * 747796405u + k * 2891336453u + 12345u;\n"
"   n = ((n >> ((n >> 28) + 4u)) ^ n) * 277803737u;\n"
"   n = (n >> 22) ^ n;\n"
"   return (n & 0xffffu) / 65535.0;\n"
"}\n"
"float4 h4(uint n, uint k) { return float4(h(n, k), h(n, k + 1), h(n, k + 2), h(n, k + 3)); }\n"
"uint coin(uint vid, out float4 pos) {\n"
"   uint q = vid / 6, c = vid % 6;\n"
"   uint cx = (c == 1 || c == 4 || c == 5) ? 1 : 0, cy = (c == 2 || c == 3 || c == 5) ? 1 : 0;\n"
"   uint gx = q % 16 + cx, gy = q / 16 + cy;\n"
"   uint n = gx + gy * 17;\n"
"   float w = 1.0 + 2.0 * h(n, 99);\n"
"   pos = float4((gx / 8.0 - 1.0) * 0.9 * w, (gy / 8.0 - 1.0) * 0.9 * w, 0.25 * w + 0.5 * h(n, 98) * w, w);\n"
"   return n;\n"
"}\n"
"struct V {\n"
"   float4 pos : SV_Position;\n"
"   float4 t0 : TEXCOORD0; float4 t1 : TEXCOORD1; float4 t2 : TEXCOORD2; float4 t3 : TEXCOORD3;\n"
"   float4 t4 : TEXCOORD4; float4 t5 : TEXCOORD5;\n"
"   nointerpolation uint4 u0 : TEXCOORD6;\n"
"   noperspective float4 n0 : TEXCOORD7;\n"
"   nointerpolation int3 i0 : TEXCOORD8;\n"
"};\n"
"V vs_a(uint vid : SV_VertexID) {\n"
"   V o; uint n = coin(vid, o.pos);\n"
"   o.t0 = h4(n, 0); o.t1 = h4(n, 4); o.t2 = h4(n, 8); o.t3 = h4(n, 12); o.t4 = h4(n, 16); o.t5 = h4(n, 20);\n"
"   o.u0 = uint4(n, n * 3, n * 5 + 1, n * 7 + 2); o.n0 = h4(n, 24);\n"
"   o.i0 = int3(-int(n), int(n) * 2 - 100, 7 - int(n));\n"
"   return o;\n"
"}\n"
"V vs_b(uint vid : SV_VertexID) {\n"
"   V o; uint n = coin(vid, o.pos);\n"
"   o.t0 = h4(n, 40).wzyx * 2; o.t1 = sqrt(h4(n, 44)); o.t2 = h4(n, 48) - 0.5; o.t3 = h4(n, 52) * h4(n, 53);\n"
"   o.t4 = h4(n, 56); o.t5 = 1 - h4(n, 60);\n"
"   o.u0 = uint4(n * 11, n + 4, n * 13 + 1, n ^ 21); o.n0 = h4(n, 64).yxwz;\n"
"   o.i0 = int3(int(n) - 50, -3 * int(n), int(n) + 9);\n"
"   return o;\n"
"}\n"
"float4 ps_tout(V i) : SV_Target {\n"
"   return i.t0 + i.t1 * 2 + i.t2 * 3 + i.t3 * 4 + i.t4 * 5 + i.t5 * 6 + i.n0 * 7\n"
"        + float4(i.u0) / 4096.0 + float4(i.i0, 1) / 512.0;\n"
"}\n"
"float4 ps_partiel(V i) : SV_Target {\n"
"   return float4(i.t0.xy, i.t1.z, i.t3.w) + float4(i.t3.x, i.t5.zw, i.n0.x) * 0.5\n"
"        + float4(float2(i.u0.yz) / 4096.0, i.i0.x / 512.0, i.n0.z) + i.t2.x;\n"
"}\n"
"struct VType {\n"
"   float4 pos : SV_Position;\n"
"   float3 t0 : TEXCOORD0; float3 t1 : TEXCOORD1; float3 t2 : TEXCOORD2; float4 t3 : TEXCOORD3;\n"
"   float3 t4 : TEXCOORD4; float3 t5 : TEXCOORD5;\n"
"   nointerpolation uint3 u0 : TEXCOORD6;\n"
"   noperspective float3 n0 : TEXCOORD7;\n"
"   nointerpolation int3 i0 : TEXCOORD8;\n"
"};\n"
"float4 ps_type(VType i) : SV_Target {\n"
"   return float4(i.t0, i.t1.x) + float4(i.t1.yz, i.t2.xy) * 2 + float4(i.t2.z, i.t3.xyw) * 3\n"
"        + float4(i.t4, i.t5.x) * 4 + float4(i.t5.yz, i.n0.xy) * 5 + i.n0.z\n"
"        + float4(float3(i.u0), i.i0.x + i.i0.y + i.i0.z) / 4096.0;\n"
"}\n"
"float4 ps_w(V i) : SV_Target { return float4(i.t0.w, i.t1.w, i.t4.w, i.n0.w) + i.u0.w / 4096.0; }\n"
"float4 ps_position(V i) : SV_Target { return float4(frac(i.pos.xy / 16.0), i.pos.z, 1); }\n"
"#ifdef ETAGE_PIXEL\n"
"float4 ps_tire(V i) : SV_Target {\n"
"   float2 a = EvaluateAttributeCentroid(i.t0.xy);\n"
"   return float4(a, i.t1.xy) + float4(i.t2.z, i.t3.yw, i.n0.y);\n"
"}\n"
"#endif\n"
"struct T {\n"
"   float4 pos : SV_Position;\n"
"   float2 a : TEXCOORD0; float2 b : TEXCOORD1; float3 c : TEXCOORD2; float d : TEXCOORD3;\n"
"   float e : TEXCOORD4; float f : TEXCOORD5; float2 g : TEXCOORD6;\n"
"   nointerpolation uint m : TEXCOORD7; nointerpolation uint3 k : TEXCOORD8;\n"
"};\n"
"T vs_tasse(uint vid : SV_VertexID) {\n"
"   T o; uint n = coin(vid, o.pos);\n"
"   o.a = h4(n, 70).xy; o.b = h4(n, 72).xy; o.c = h4(n, 74).xyz; o.d = h(n, 77); o.e = h(n, 78); o.f = h(n, 79);\n"
"   o.g = h4(n, 80).xy; o.m = n * 17 + 3; o.k = uint3(n, n * 2, n * 3);\n"
"   return o;\n"
"}\n"
"float4 ps_tasse(T i) : SV_Target {\n"
"   return float4(i.a, i.b) + float4(i.c, i.d) * 2 + float4(i.e, i.f, i.g) * 3 + float4(i.m, i.k) / 4096.0;\n"
"}\n"
"float4 ps_tasse_b(T i) : SV_Target { return float4(i.b, i.d, i.g.y) + float4(i.f, i.k.yz, i.c.y) / 64.0; }\n"
"[maxvertexcount(3)] void gs_melange(triangle V v[3], inout TriangleStream<V> s) {\n"
"   for (int k = 0; k < 3; k++) {\n"
"      V o = v[k];\n"
"      o.t0 = v[k].t0 * 0.5 + v[(k + 1) % 3].t1 * 0.5;\n"
"      o.t3 = v[k].t3.wzyx;\n"
"      s.Append(o);\n"
"   }\n"
"}\n";

#define COTE 256
#define SOMMETS (16 * 16 * 6)
#define OK(expr, quoi) do { if (FAILED(expr)) { printf("ECHEC: %s\n", quoi); fflush(stdout); return 1; } } while (0)

static const struct { const char *entree, *cible; } SHADERS[] = {
   { "vs_a", "vs_5_0" }, { "vs_b", "vs_5_0" }, { "vs_tasse", "vs_5_0" },
   { "ps_tout", "ps_5_0" }, { "ps_partiel", "ps_5_0" }, { "ps_type", "ps_5_0" }, { "ps_w", "ps_5_0" },
   { "ps_position", "ps_5_0" }, { "ps_tire", "ps_5_0" }, { "ps_tasse", "ps_5_0" }, { "ps_tasse_b", "ps_5_0" },
   { "gs_melange", "gs_5_0" },
};
enum { NB_SHADERS = sizeof SHADERS / sizeof SHADERS[0] };

static const struct { const char *nom, *vs, *gs, *ps; int profondeur_avant; } CAS[] = {
   { "tout", "vs_a", NULL, "ps_tout", 0 },
   { "partiel", "vs_a", NULL, "ps_partiel", 0 },
   { "type", "vs_a", NULL, "ps_type", 0 },
   { "w", "vs_a", NULL, "ps_w", 0 },
   { "position", "vs_a", NULL, "ps_position", 0 },
   { "autre_vs", "vs_b", NULL, "ps_partiel", 0 },
   { "tasse", "vs_tasse", NULL, "ps_tasse", 0 },
   { "tasse_b", "vs_tasse", NULL, "ps_tasse_b", 0 },
   { "tire", "vs_a", NULL, "ps_tire", 0 },
   { "gs", "vs_a", "gs_melange", "ps_partiel", 0 },
   { "profondeur", "vs_a", NULL, "ps_partiel", 1 },
};
enum { NB_CAS = sizeof CAS / sizeof CAS[0] };

static void *octets[NB_SHADERS];
static size_t tailles[NB_SHADERS];

static int indice(const char *entree)
{
   for (int i = 0; i < NB_SHADERS; i++)
      if (!strcmp(SHADERS[i].entree, entree)) return i;
   return -1;
}

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
   if (FAILED(compiler_hlsl(HLSL, strlen(HLSL), "sonde.hlsl", SHADERS[i].cible[0] == 'p' ? pixel : NULL, NULL,
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
      else if (SHADERS[i].cible[0] == 'g')
         hr = ID3D11Device_CreateGeometryShader(dev, octets[i], tailles[i], NULL, (ID3D11GeometryShader **)&objets[i]);
      else
         hr = ID3D11Device_CreatePixelShader(dev, octets[i], tailles[i], NULL, (ID3D11PixelShader **)&objets[i]);
      if (FAILED(hr)) { printf("ECHEC: creation de %s\n", SHADERS[i].entree); return 1; }
   }

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
      ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, noir);
      ID3D11DeviceContext_ClearDepthStencilView(ctx, dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
      ID3D11DeviceContext_VSSetShader(ctx, objets[indice(CAS[c].vs)], NULL, 0);
      ID3D11DeviceContext_GSSetShader(ctx, CAS[c].gs ? objets[indice(CAS[c].gs)] : NULL, NULL, 0);
      if (CAS[c].profondeur_avant) {
         /* passe de profondeur seule : meme vertex shader, pas de pixel shader */
         ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, dsv);
         ID3D11DeviceContext_PSSetShader(ctx, NULL, NULL, 0);
         ID3D11DeviceContext_Draw(ctx, SOMMETS, 0);
      }
      ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, dsv);
      ID3D11DeviceContext_PSSetShader(ctx, objets[indice(CAS[c].ps)], NULL, 0);
      ID3D11DeviceContext_Draw(ctx, SOMMETS, 0);
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
