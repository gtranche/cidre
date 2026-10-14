/* Sonde des capacites D3D12 telles qu'un jeu les voit (vkd3d-proton -> KosmicKrisp).
 * Cree un device sur l'adaptateur par defaut au plus haut Feature Level accepte, puis
 * imprime ce qu'Unreal 5 et les autres moteurs interrogent : Shader Model, WaveOps,
 * liaison des ressources, atomiques 64 bits, mesh shaders, barrieres ameliorees...
 *   d3d12caps.exe            (sortie texte, une ligne par capacite)
 * Lancer : sh tests/sonde_d3d12caps.sh (copie du prefixe, pile dx12).
 * Construire : arm64ec-w64-mingw32-clang -O2 d3d12caps.c -o d3d12caps.exe -ld3d12 -ldxgi -luuid */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>

static ID3D12Device *dev;

#define LIGNE(nom, fmt, ...) printf("  %-44s " fmt "\n", nom, __VA_ARGS__)

static BOOL caps(D3D12_FEATURE f, void *data, UINT taille) {
   return SUCCEEDED(ID3D12Device_CheckFeatureSupport(dev, f, data, taille));
}

int main(void) {
   static const D3D_FEATURE_LEVEL niveaux[] = {D3D_FEATURE_LEVEL_12_2, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
                                                D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
   static const char *noms[] = {"12_2", "12_1", "12_0", "11_1", "11_0"};
   int i, fl = -1;
   setvbuf(stdout, NULL, _IONBF, 0);
   for (i = 0; i < 5; i++) {
      HRESULT hr = D3D12CreateDevice(NULL, niveaux[i], &IID_ID3D12Device, (void **)&dev);
      if (SUCCEEDED(hr)) { fl = i; break; }
   }
   if (fl < 0) { printf("D3D12CreateDevice a echoue a tous les Feature Levels\n"); return 1; }
   printf("D3D12 : device cree au Feature Level %s\n", noms[fl]);

   D3D12_FEATURE_DATA_SHADER_MODEL sm = {D3D_HIGHEST_SHADER_MODEL};
   if (caps(D3D12_FEATURE_SHADER_MODEL, &sm, sizeof(sm)))
      LIGNE("Shader Model maximum", "%x.%x", sm.HighestShaderModel >> 4, sm.HighestShaderModel & 0xf);
   else {
      /* certains runtimes refusent une valeur au-dela de ce qu'ils connaissent : on redescend */
      for (sm.HighestShaderModel = D3D_SHADER_MODEL_6_6; sm.HighestShaderModel >= D3D_SHADER_MODEL_5_1; sm.HighestShaderModel--)
         if (caps(D3D12_FEATURE_SHADER_MODEL, &sm, sizeof(sm))) break;
      LIGNE("Shader Model maximum", "%x.%x (demande redescendue)", sm.HighestShaderModel >> 4, sm.HighestShaderModel & 0xf);
   }

   D3D12_FEATURE_DATA_ROOT_SIGNATURE rs = {D3D_ROOT_SIGNATURE_VERSION_1_1};
   if (caps(D3D12_FEATURE_ROOT_SIGNATURE, &rs, sizeof(rs))) LIGNE("Root signature", "1.%d", rs.HighestVersion == D3D_ROOT_SIGNATURE_VERSION_1_1);

   D3D12_FEATURE_DATA_D3D12_OPTIONS o = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS, &o, sizeof(o))) {
      LIGNE("ResourceBindingTier", "%d", o.ResourceBindingTier);
      LIGNE("ResourceHeapTier", "%d", o.ResourceHeapTier);
      LIGNE("TiledResourcesTier", "%d", o.TiledResourcesTier);
      LIGNE("TypedUAVLoadAdditionalFormats", "%d", o.TypedUAVLoadAdditionalFormats);
      LIGNE("ROVsSupported", "%d", o.ROVsSupported);
      LIGNE("ConservativeRasterizationTier", "%d", o.ConservativeRasterizationTier);
      LIGNE("DoublePrecisionFloatShaderOps", "%d", o.DoublePrecisionFloatShaderOps);
      LIGNE("MinPrecisionSupport", "%d", o.MinPrecisionSupport);
   }
   D3D12_FEATURE_DATA_D3D12_OPTIONS1 o1 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS1, &o1, sizeof(o1))) {
      LIGNE("WaveOps", "%d (lanes %u-%u)", o1.WaveOps, o1.WaveLaneCountMin, o1.WaveLaneCountMax);
      LIGNE("Int64ShaderOps", "%d", o1.Int64ShaderOps);
   }
   D3D12_FEATURE_DATA_D3D12_OPTIONS3 o3 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS3, &o3, sizeof(o3))) {
      LIGNE("BarycentricsSupported", "%d", o3.BarycentricsSupported);
      LIGNE("ViewInstancingTier", "%d", o3.ViewInstancingTier);
   }
   D3D12_FEATURE_DATA_D3D12_OPTIONS4 o4 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS4, &o4, sizeof(o4))) LIGNE("Native16BitShaderOpsSupported", "%d", o4.Native16BitShaderOpsSupported);
   D3D12_FEATURE_DATA_D3D12_OPTIONS5 o5 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS5, &o5, sizeof(o5))) LIGNE("RaytracingTier", "%d", o5.RaytracingTier);
   D3D12_FEATURE_DATA_D3D12_OPTIONS6 o6 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS6, &o6, sizeof(o6))) LIGNE("VariableShadingRateTier", "%d", o6.VariableShadingRateTier);
   D3D12_FEATURE_DATA_D3D12_OPTIONS7 o7 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS7, &o7, sizeof(o7))) {
      LIGNE("MeshShaderTier", "%d", o7.MeshShaderTier);
      LIGNE("SamplerFeedbackTier", "%d", o7.SamplerFeedbackTier);
   }
   D3D12_FEATURE_DATA_D3D12_OPTIONS9 o9 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS9, &o9, sizeof(o9))) {
      LIGNE("AtomicInt64OnTypedResourceSupported", "%d", o9.AtomicInt64OnTypedResourceSupported);
      LIGNE("AtomicInt64OnGroupSharedSupported", "%d", o9.AtomicInt64OnGroupSharedSupported);
      LIGNE("DerivativesInMeshAndAmplification", "%d", o9.DerivativesInMeshAndAmplificationShadersSupported);
      LIGNE("WaveMMATier", "%d", o9.WaveMMATier);
   }
   D3D12_FEATURE_DATA_D3D12_OPTIONS11 o11 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS11, &o11, sizeof(o11)))
      LIGNE("AtomicInt64OnDescriptorHeapResource", "%d", o11.AtomicInt64OnDescriptorHeapResourceSupported);
   D3D12_FEATURE_DATA_D3D12_OPTIONS12 o12 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS12, &o12, sizeof(o12))) LIGNE("EnhancedBarriersSupported", "%d", o12.EnhancedBarriersSupported);
   D3D12_FEATURE_DATA_D3D12_OPTIONS16 o16 = {0};
   if (caps(D3D12_FEATURE_D3D12_OPTIONS16, &o16, sizeof(o16))) LIGNE("GPUUploadHeapSupported", "%d", o16.GPUUploadHeapSupported);
   ID3D12Device_Release(dev);
   return 0;
}
