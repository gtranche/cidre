/* Ressource D3D12 partagee (D3D12_HEAP_FLAG_SHARED) puis CreateSharedHandle : ce que fait
 * Expedition 33 au chargement. Avant le correctif vkd3d 0146, d3d12core appelait
 * vkGetMemoryWin32HandleKHR = NULL (VK_KHR_external_memory_win32 absent sous KosmicKrisp).
 * Attendu apres 0146 : ressource creee (privee), handle refuse (E_NOTIMPL), pas de faute. */
#define COBJMACROS
#define INITGUID
#include <stdio.h>
#include <windows.h>
#include <d3d12.h>
int main(void)
{
   ID3D12Device *dev = NULL;
   HRESULT hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev);
   printf("D3D12CreateDevice : %#lx\n", hr);
   if (FAILED(hr)) return 1;
   D3D12_HEAP_PROPERTIES hp = { D3D12_HEAP_TYPE_DEFAULT };
   D3D12_RESOURCE_DESC rd = { D3D12_RESOURCE_DIMENSION_TEXTURE2D, 0, 256, 256, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, {1, 0},
                              D3D12_TEXTURE_LAYOUT_UNKNOWN, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET };
   ID3D12Resource *res = NULL;
   hr = ID3D12Device_CreateCommittedResource(dev, &hp, D3D12_HEAP_FLAG_SHARED, &rd, D3D12_RESOURCE_STATE_COMMON, NULL,
                                             &IID_ID3D12Resource, (void **)&res);
   printf("CreateCommittedResource(SHARED) : %#lx\n", hr);
   fflush(stdout);
   if (SUCCEEDED(hr)) {
      HANDLE h = NULL;
      hr = ID3D12Device_CreateSharedHandle(dev, (ID3D12DeviceChild *)res, NULL, GENERIC_ALL, NULL, &h);
      printf("CreateSharedHandle : %#lx handle %p\n", hr, h);
      ID3D12Resource_Release(res);
   }
   ID3D12Fence *f = NULL;
   hr = ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_SHARED, &IID_ID3D12Fence, (void **)&f);
   printf("CreateFence(SHARED) : %#lx\n", hr);
   if (SUCCEEDED(hr)) {
      HANDLE h = NULL;
      hr = ID3D12Device_CreateSharedHandle(dev, (ID3D12DeviceChild *)f, NULL, GENERIC_ALL, NULL, &h);
      printf("CreateSharedHandle(fence) : %#lx handle %p\n", hr, h);
      ID3D12Fence_Release(f);
   }
   ID3D12Device_Release(dev);
   printf("FIN sans faute\n");
   return 0;
}
