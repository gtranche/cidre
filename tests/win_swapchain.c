/* Fenetre + swapchain DXGI + presentation, a travers la pile ouverte.
 *
 * Efface le back buffer en vert, presente quelques images, puis relit la
 * derniere image presentee pour prouver que la chaine a vraiment ecrit dedans.
 * Compile en PE avec mingw-w64 ; voir tests/build_win_swapchain.sh.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

#define W 320
#define H 240
#define FRAMES 3

static int fail;
#define CHECK(cond, ...) do { if (!(cond)) { printf("  ECHEC " __VA_ARGS__); printf("\n"); fail++; } } while (0)

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
   if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
   return DefWindowProcW(h, m, w, l);
}

int main(void)
{
   HRESULT hr;

   WNDCLASSEXW wc = {.cbSize = sizeof(wc), .lpfnWndProc = wndproc,
                     .hInstance = GetModuleHandleW(NULL),
                     .lpszClassName = L"pile_ouverte"};
   RegisterClassExW(&wc);
   HWND hwnd = CreateWindowExW(0, L"pile_ouverte", L"pile ouverte",
                               WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, W, H,
                               NULL, NULL, wc.hInstance, NULL);
   printf("fenetre : %p\n", (void *)hwnd);
   CHECK(hwnd != NULL, "CreateWindowEx");
   if (!hwnd) return 1;

   ID3D12Device *device = NULL;
   hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device,
                          (void **)&device);
   printf("D3D12CreateDevice : hr=%#lx\n", (unsigned long)hr);
   CHECK(SUCCEEDED(hr) && device, "device");
   if (!device) return 1;

   D3D12_COMMAND_QUEUE_DESC qd = {.Type = D3D12_COMMAND_LIST_TYPE_DIRECT};
   ID3D12CommandQueue *queue = NULL;
   hr = ID3D12Device_CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue,
                                        (void **)&queue);
   CHECK(SUCCEEDED(hr), "CreateCommandQueue hr=%#lx", (unsigned long)hr);

   IDXGIFactory4 *factory = NULL;
   hr = CreateDXGIFactory2(0, &IID_IDXGIFactory4, (void **)&factory);
   printf("CreateDXGIFactory2 : hr=%#lx\n", (unsigned long)hr);
   CHECK(SUCCEEDED(hr) && factory, "factory");
   if (!factory) return 1;

   DXGI_SWAP_CHAIN_DESC1 scd = {
      .Width = W, .Height = H, .Format = DXGI_FORMAT_R8G8B8A8_UNORM,
      .SampleDesc = {1, 0}, .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
      .BufferCount = 2, .SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD};
   IDXGISwapChain1 *sc1 = NULL;
   hr = IDXGIFactory4_CreateSwapChainForHwnd(factory, (IUnknown *)queue, hwnd,
                                             &scd, NULL, NULL, &sc1);
   printf("CreateSwapChainForHwnd : hr=%#lx\n", (unsigned long)hr);
   CHECK(SUCCEEDED(hr) && sc1, "swapchain");
   if (!sc1) return 1;

   IDXGISwapChain3 *sc = NULL;
   IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void **)&sc);
   CHECK(sc != NULL, "IDXGISwapChain3");
   if (!sc) return 1;

   D3D12_DESCRIPTOR_HEAP_DESC hd = {.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
                                    .NumDescriptors = 2};
   ID3D12DescriptorHeap *rtvs = NULL;
   ID3D12Device_CreateDescriptorHeap(device, &hd, &IID_ID3D12DescriptorHeap,
                                     (void **)&rtvs);
   UINT rtv_size = ID3D12Device_GetDescriptorHandleIncrementSize(
      device, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
   D3D12_CPU_DESCRIPTOR_HANDLE rtv0;
   rtvs->lpVtbl->GetCPUDescriptorHandleForHeapStart(rtvs, &rtv0);

   ID3D12Resource *back[2] = {0};
   for (UINT i = 0; i < 2; i++) {
      hr = IDXGISwapChain3_GetBuffer(sc, i, &IID_ID3D12Resource,
                                     (void **)&back[i]);
      CHECK(SUCCEEDED(hr) && back[i], "GetBuffer %u hr=%#lx", i,
            (unsigned long)hr);
      if (!back[i]) return 1;
      D3D12_CPU_DESCRIPTOR_HANDLE h = {rtv0.ptr + i * rtv_size};
      ID3D12Device_CreateRenderTargetView(device, back[i], NULL, h);
   }

   ID3D12CommandAllocator *alloc = NULL;
   ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                       &IID_ID3D12CommandAllocator,
                                       (void **)&alloc);
   ID3D12GraphicsCommandList *list = NULL;
   ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                  alloc, NULL, &IID_ID3D12GraphicsCommandList,
                                  (void **)&list);
   ID3D12GraphicsCommandList_Close(list);

   ID3D12Fence *fence = NULL;
   ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence,
                            (void **)&fence);
   UINT64 fence_value = 0;
   HANDLE ev = CreateEventW(NULL, FALSE, FALSE, NULL);

   const float green[4] = {0.0f, 1.0f, 0.0f, 1.0f};
   UINT last = 0;

   for (int f = 0; f < FRAMES; f++) {
      UINT idx = IDXGISwapChain3_GetCurrentBackBufferIndex(sc);
      last = idx;

      ID3D12CommandAllocator_Reset(alloc);
      ID3D12GraphicsCommandList_Reset(list, alloc, NULL);

      D3D12_RESOURCE_BARRIER b = {
         .Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
         .Transition = {.pResource = back[idx],
                        .StateBefore = D3D12_RESOURCE_STATE_PRESENT,
                        .StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET,
                        .Subresource =
                           D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES}};
      ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);

      D3D12_CPU_DESCRIPTOR_HANDLE h = {rtv0.ptr + idx * rtv_size};
      ID3D12GraphicsCommandList_ClearRenderTargetView(list, h, green, 0, NULL);

      b.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
      b.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
      ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
      ID3D12GraphicsCommandList_Close(list);

      ID3D12CommandList *lists[] = {(ID3D12CommandList *)list};
      ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);

      hr = IDXGISwapChain3_Present(sc, 1, 0);
      printf("image %d : back buffer %u, Present hr=%#lx\n", f, idx,
             (unsigned long)hr);
      CHECK(SUCCEEDED(hr), "Present");

      ID3D12CommandQueue_Signal(queue, fence, ++fence_value);
      if (ID3D12Fence_GetCompletedValue(fence) < fence_value) {
         ID3D12Fence_SetEventOnCompletion(fence, fence_value, ev);
         WaitForSingleObject(ev, 2000);
      }

      MSG msg;
      while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
         TranslateMessage(&msg);
         DispatchMessageW(&msg);
      }
   }

   /* Relire le back buffer efface : prouve que la chaine a bien ecrit dedans,
    * sans dependre de ce qui est affiche a l'ecran. */
   D3D12_RESOURCE_DESC rd;
   back[last]->lpVtbl->GetDesc(back[last], &rd);
   UINT64 total = 0;
   D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp;
   ID3D12Device_GetCopyableFootprints(device, &rd, 0, 1, 0, &fp, NULL, NULL,
                                      &total);

   D3D12_HEAP_PROPERTIES hp = {.Type = D3D12_HEAP_TYPE_READBACK};
   D3D12_RESOURCE_DESC bd = {.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER,
                             .Width = total, .Height = 1, .DepthOrArraySize = 1,
                             .MipLevels = 1, .SampleDesc = {1, 0},
                             .Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR};
   ID3D12Resource *rb = NULL;
   hr = ID3D12Device_CreateCommittedResource(device, &hp, D3D12_HEAP_FLAG_NONE,
                                             &bd, D3D12_RESOURCE_STATE_COPY_DEST,
                                             NULL, &IID_ID3D12Resource,
                                             (void **)&rb);
   CHECK(SUCCEEDED(hr) && rb, "readback hr=%#lx", (unsigned long)hr);

   if (rb) {
      ID3D12CommandAllocator_Reset(alloc);
      ID3D12GraphicsCommandList_Reset(list, alloc, NULL);
      D3D12_RESOURCE_BARRIER b = {
         .Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
         .Transition = {.pResource = back[last],
                        .StateBefore = D3D12_RESOURCE_STATE_PRESENT,
                        .StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE,
                        .Subresource =
                           D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES}};
      ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);

      D3D12_TEXTURE_COPY_LOCATION dst = {
         .pResource = rb,
         .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
         .PlacedFootprint = fp};
      D3D12_TEXTURE_COPY_LOCATION src = {
         .pResource = back[last],
         .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
         .SubresourceIndex = 0};
      ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src,
                                                  NULL);

      b.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
      b.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
      ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
      ID3D12GraphicsCommandList_Close(list);

      ID3D12CommandList *lists[] = {(ID3D12CommandList *)list};
      ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);
      ID3D12CommandQueue_Signal(queue, fence, ++fence_value);
      if (ID3D12Fence_GetCompletedValue(fence) < fence_value) {
         ID3D12Fence_SetEventOnCompletion(fence, fence_value, ev);
         WaitForSingleObject(ev, 2000);
      }

      void *map = NULL;
      D3D12_RANGE all = {0, (SIZE_T)total};
      hr = ID3D12Resource_Map(rb, 0, &all, &map);
      CHECK(SUCCEEDED(hr) && map, "Map hr=%#lx", (unsigned long)hr);
      if (map) {
         const unsigned char *px = (const unsigned char *)map +
                                   fp.Footprint.RowPitch * (H / 2) + (W / 2) * 4;
         printf("pixel central du back buffer : %02x %02x %02x %02x "
                "(attendu 00 ff 00 ff)\n", px[0], px[1], px[2], px[3]);
         CHECK(px[0] == 0x00 && px[1] == 0xff && px[2] == 0x00 &&
               px[3] == 0xff, "couleur du back buffer");
      }
   }

   printf("\n%s (%d echec(s))\n", fail ? "ECHECS" : "TOUT PASSE", fail);
   return fail ? 1 : 0;
}
