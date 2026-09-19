/* Application D3D12 reelle sur la pile ouverte : fenetre Win32, swapchain DXGI,
 * tampon de profondeur, texture echantillonnee, constantes par image, cube
 * anime et eclaire, boucle de presentation avec synchronisation par cloture.
 *
 * Le HLSL est compile a l'execution par d3dcompiler_47 (compilateur de Wine).
 * A la fin, le back buffer est relu et verifie : on exige de la geometrie
 * reellement dessinee (plusieurs teintes distinctes) et un fond intact.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

#define W 800
#define H 600
#define FRAMES 3
#define TEX 64
#define NFRAMES 240

#define CK(x) do { HRESULT _hr=(x); if(FAILED(_hr)){ printf("ECHEC %s -> 0x%08lx (l.%d)\n",#x,(unsigned long)_hr,__LINE__); exit(1);} } while(0)

static ID3D12Device *dev;
static ID3D12CommandQueue *queue;
static IDXGISwapChain3 *swap;
static ID3D12DescriptorHeap *rtv_heap, *dsv_heap, *srv_heap;
static ID3D12Resource *rt[FRAMES], *depth, *vb, *ib, *cb, *tex;
static ID3D12CommandAllocator *alloc[FRAMES];
static ID3D12GraphicsCommandList *cl;
static ID3D12RootSignature *rs;
static ID3D12PipelineState *pso;
static ID3D12Fence *fence;
static UINT64 fence_val[FRAMES], fence_next = 1;
static HANDLE fence_event;
static UINT rtv_size;
static D3D12_VERTEX_BUFFER_VIEW vbv;
static D3D12_INDEX_BUFFER_VIEW ibv;
static UINT8 *cb_cpu;

struct vtx { float px,py,pz; float nx,ny,nz; float u,v; };
struct scene { float mvp[16]; float light[4]; };

static const char *hlsl =
"cbuffer Scene : register(b0) { row_major float4x4 mvp; float4 light; }\n"
"Texture2D tex : register(t0);\n"
"SamplerState smp : register(s0);\n"
"struct VSIn { float3 pos : POSITION; float3 nrm : NORMAL; float2 uv : TEXCOORD; };\n"
"struct VSOut { float4 pos : SV_Position; float3 nrm : NORMAL; float2 uv : TEXCOORD; };\n"
"VSOut vs_main(VSIn i) { VSOut o; o.pos = mul(float4(i.pos,1.0), mvp); o.nrm = i.nrm; o.uv = i.uv; return o; }\n"
"float4 ps_main(VSOut i) : SV_Target {\n"
"  float d = saturate(dot(normalize(i.nrm), normalize(light.xyz))) * 0.75 + 0.25;\n"
"  return float4(tex.Sample(smp, i.uv).rgb * d, 1.0);\n"
"}\n";

static void mat_mul(float *o, const float *a, const float *b){
   float t[16];
   for(int r=0;r<4;r++) for(int c=0;c<4;c++){
      float s=0; for(int k=0;k<4;k++) s+=a[r*4+k]*b[k*4+c];
      t[r*4+c]=s; }
   memcpy(o,t,sizeof t);
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l){
   if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
   return DefWindowProcA(h, m, w, l);
}

static void wait_gpu(UINT idx){
   UINT64 v = fence_next++;
   CK(ID3D12CommandQueue_Signal(queue, fence, v));
   fence_val[idx] = v;
   if (ID3D12Fence_GetCompletedValue(fence) < v) {
      CK(ID3D12Fence_SetEventOnCompletion(fence, v, fence_event));
      WaitForSingleObject(fence_event, INFINITE);
   }
}

int main(int argc, char **argv){
   int NCUBES = (argc > 1) ? atoi(argv[1]) : 1;
   if (NCUBES < 1) NCUBES = 1;
   WNDCLASSA wc = {0};
   wc.lpfnWndProc = wndproc; wc.hInstance = GetModuleHandleA(NULL);
   wc.lpszClassName = "pile_ouverte_cube"; wc.hCursor = LoadCursorA(NULL,(LPCSTR)IDC_ARROW);
   RegisterClassA(&wc);
   RECT r = {0,0,W,H}; AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
   HWND hwnd = CreateWindowExA(0, wc.lpszClassName, "Cube D3D12 -- pile ouverte",
      WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
      r.right-r.left, r.bottom-r.top, NULL, NULL, wc.hInstance, NULL);
   if (!hwnd) { printf("ECHEC CreateWindow\n"); return 1; }
   ShowWindow(hwnd, SW_SHOW);

   CK(D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void**)&dev));

   D3D12_COMMAND_QUEUE_DESC qd = {0};
   qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
   CK(ID3D12Device_CreateCommandQueue(dev, &qd, &IID_ID3D12CommandQueue, (void**)&queue));

   IDXGIFactory4 *fac;
   CK(CreateDXGIFactory2(0, &IID_IDXGIFactory4, (void**)&fac));
   DXGI_SWAP_CHAIN_DESC1 sd = {0};
   sd.Width = W; sd.Height = H; sd.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
   sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
   sd.BufferCount = FRAMES; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
   IDXGISwapChain1 *sc1;
   CK(IDXGIFactory4_CreateSwapChainForHwnd(fac, (IUnknown*)queue, hwnd, &sd, NULL, NULL, &sc1));
   CK(IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void**)&swap));
   IDXGISwapChain1_Release(sc1);

   D3D12_DESCRIPTOR_HEAP_DESC hd = {0};
   hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV; hd.NumDescriptors = FRAMES;
   CK(ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void**)&rtv_heap));
   hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_DSV; hd.NumDescriptors = 1;
   CK(ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void**)&dsv_heap));
   hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV; hd.NumDescriptors = 1;
   hd.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
   CK(ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void**)&srv_heap));
   rtv_size = ID3D12Device_GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

   D3D12_CPU_DESCRIPTOR_HANDLE rtvh;
   rtv_heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(rtv_heap, &rtvh);
   for (UINT i = 0; i < FRAMES; i++) {
      CK(IDXGISwapChain3_GetBuffer(swap, i, &IID_ID3D12Resource, (void**)&rt[i]));
      D3D12_CPU_DESCRIPTOR_HANDLE h = rtvh; h.ptr += (SIZE_T)i * rtv_size;
      ID3D12Device_CreateRenderTargetView(dev, rt[i], NULL, h);
      CK(ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT,
         &IID_ID3D12CommandAllocator, (void**)&alloc[i]));
   }

   D3D12_HEAP_PROPERTIES hp_def = { D3D12_HEAP_TYPE_DEFAULT };
   D3D12_HEAP_PROPERTIES hp_up  = { D3D12_HEAP_TYPE_UPLOAD };

   D3D12_RESOURCE_DESC dd = {0};
   dd.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
   dd.Width = W; dd.Height = H; dd.DepthOrArraySize = 1; dd.MipLevels = 1;
   dd.Format = DXGI_FORMAT_D32_FLOAT; dd.SampleDesc.Count = 1;
   dd.Flags = D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL;
   D3D12_CLEAR_VALUE dcv = { DXGI_FORMAT_D32_FLOAT };
   dcv.DepthStencil.Depth = 1.0f;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_def, D3D12_HEAP_FLAG_NONE, &dd,
      D3D12_RESOURCE_STATE_DEPTH_WRITE, &dcv, &IID_ID3D12Resource, (void**)&depth));
   D3D12_CPU_DESCRIPTOR_HANDLE dsvh;
   dsv_heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(dsv_heap, &dsvh);
   ID3D12Device_CreateDepthStencilView(dev, depth, NULL, dsvh);

   static const struct vtx verts[24] = {
      {-1,-1,-1, 0,0,-1, 0,1},{ 1,-1,-1, 0,0,-1, 1,1},{ 1, 1,-1, 0,0,-1, 1,0},{-1, 1,-1, 0,0,-1, 0,0},
      {-1,-1, 1, 0,0, 1, 1,1},{-1, 1, 1, 0,0, 1, 1,0},{ 1, 1, 1, 0,0, 1, 0,0},{ 1,-1, 1, 0,0, 1, 0,1},
      {-1, 1,-1, 0,1,0, 0,1},{ 1, 1,-1, 0,1,0, 1,1},{ 1, 1, 1, 0,1,0, 1,0},{-1, 1, 1, 0,1,0, 0,0},
      {-1,-1,-1, 0,-1,0, 0,0},{-1,-1, 1, 0,-1,0, 0,1},{ 1,-1, 1, 0,-1,0, 1,1},{ 1,-1,-1, 0,-1,0, 1,0},
      { 1,-1,-1, 1,0,0, 0,1},{ 1,-1, 1, 1,0,0, 1,1},{ 1, 1, 1, 1,0,0, 1,0},{ 1, 1,-1, 1,0,0, 0,0},
      {-1,-1,-1,-1,0,0, 1,1},{-1, 1,-1,-1,0,0, 1,0},{-1, 1, 1,-1,0,0, 0,0},{-1,-1, 1,-1,0,0, 0,1},
   };
   static const UINT16 idx[36] = {
      0,1,2, 0,2,3,   4,5,6, 4,6,7,   8,9,10, 8,10,11,
      12,13,14, 12,14,15,  16,17,18, 16,18,19,  20,21,22, 20,22,23 };

   D3D12_RESOURCE_DESC bd = {0};
   bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; bd.Height = 1;
   bd.DepthOrArraySize = 1; bd.MipLevels = 1; bd.Format = DXGI_FORMAT_UNKNOWN;
   bd.SampleDesc.Count = 1; bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

   bd.Width = sizeof verts;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_up, D3D12_HEAP_FLAG_NONE, &bd,
      D3D12_RESOURCE_STATE_GENERIC_READ, NULL, &IID_ID3D12Resource, (void**)&vb));
   void *p; D3D12_RANGE nr = {0,0};
   CK(ID3D12Resource_Map(vb, 0, &nr, &p)); memcpy(p, verts, sizeof verts);
   ID3D12Resource_Unmap(vb, 0, NULL);
   vbv.BufferLocation = ID3D12Resource_GetGPUVirtualAddress(vb);
   vbv.StrideInBytes = sizeof(struct vtx); vbv.SizeInBytes = sizeof verts;

   bd.Width = sizeof idx;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_up, D3D12_HEAP_FLAG_NONE, &bd,
      D3D12_RESOURCE_STATE_GENERIC_READ, NULL, &IID_ID3D12Resource, (void**)&ib));
   CK(ID3D12Resource_Map(ib, 0, &nr, &p)); memcpy(p, idx, sizeof idx);
   ID3D12Resource_Unmap(ib, 0, NULL);
   ibv.BufferLocation = ID3D12Resource_GetGPUVirtualAddress(ib);
   ibv.Format = DXGI_FORMAT_R16_UINT; ibv.SizeInBytes = sizeof idx;

   bd.Width = (UINT64)256 * NCUBES;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_up, D3D12_HEAP_FLAG_NONE, &bd,
      D3D12_RESOURCE_STATE_GENERIC_READ, NULL, &IID_ID3D12Resource, (void**)&cb));
   CK(ID3D12Resource_Map(cb, 0, &nr, (void**)&cb_cpu));

   /* Texture en damier colore, montee par un tampon intermediaire. */
   D3D12_RESOURCE_DESC td = {0};
   td.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
   td.Width = TEX; td.Height = TEX; td.DepthOrArraySize = 1; td.MipLevels = 1;
   td.Format = DXGI_FORMAT_R8G8B8A8_UNORM; td.SampleDesc.Count = 1;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_def, D3D12_HEAP_FLAG_NONE, &td,
      D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void**)&tex));

   D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp; UINT64 up_size = 0;
   ID3D12Device_GetCopyableFootprints(dev, &td, 0, 1, 0, &fp, NULL, NULL, &up_size);
   ID3D12Resource *tex_up;
   bd.Width = up_size;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_up, D3D12_HEAP_FLAG_NONE, &bd,
      D3D12_RESOURCE_STATE_GENERIC_READ, NULL, &IID_ID3D12Resource, (void**)&tex_up));
   UINT8 *tp;
   CK(ID3D12Resource_Map(tex_up, 0, &nr, (void**)&tp));
   for (UINT y = 0; y < TEX; y++) {
      UINT8 *row = tp + fp.Footprint.RowPitch * y;
      for (UINT x = 0; x < TEX; x++) {
         int c = ((x >> 3) ^ (y >> 3)) & 1;
         row[x*4+0] = c ? 235 : 40;
         row[x*4+1] = c ? 120 : 160;
         row[x*4+2] = c ? 40  : 235;
         row[x*4+3] = 255;
      }
   }
   ID3D12Resource_Unmap(tex_up, 0, NULL);

   D3D12_SHADER_RESOURCE_VIEW_DESC sv = {0};
   sv.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
   sv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
   sv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
   sv.Texture2D.MipLevels = 1;
   D3D12_CPU_DESCRIPTOR_HANDLE srvh;
   srv_heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(srv_heap, &srvh);
   ID3D12Device_CreateShaderResourceView(dev, tex, &sv, srvh);

   /* Signature racine : CBV racine b0, table SRV t0, echantillonneur statique s0. */
   D3D12_DESCRIPTOR_RANGE range = {0};
   range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV; range.NumDescriptors = 1;
   D3D12_ROOT_PARAMETER rp[2] = {0};
   rp[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
   rp[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
   rp[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
   rp[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
   rp[1].DescriptorTable.NumDescriptorRanges = 1;
   rp[1].DescriptorTable.pDescriptorRanges = &range;
   D3D12_STATIC_SAMPLER_DESC ss = {0};
   ss.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
   ss.AddressU = ss.AddressV = ss.AddressW = D3D12_TEXTURE_ADDRESS_MODE_WRAP;
   ss.MaxLOD = D3D12_FLOAT32_MAX;
   ss.ComparisonFunc = D3D12_COMPARISON_FUNC_NEVER;
   ss.BorderColor = D3D12_STATIC_BORDER_COLOR_TRANSPARENT_BLACK;
   ss.ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
   D3D12_ROOT_SIGNATURE_DESC rsd = {0};
   rsd.NumParameters = 2; rsd.pParameters = rp;
   rsd.NumStaticSamplers = 1; rsd.pStaticSamplers = &ss;
   rsd.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
   ID3DBlob *sig = NULL, *err = NULL;
   CK(D3D12SerializeRootSignature(&rsd, D3D_ROOT_SIGNATURE_VERSION_1, &sig, &err));
   CK(ID3D12Device_CreateRootSignature(dev, 0, ID3D10Blob_GetBufferPointer(sig),
      ID3D10Blob_GetBufferSize(sig), &IID_ID3D12RootSignature, (void**)&rs));

   ID3DBlob *vs = NULL, *ps = NULL;
   HRESULT hr = D3DCompile(hlsl, strlen(hlsl), NULL, NULL, NULL, "vs_main", "vs_5_0", 0, 0, &vs, &err);
   if (FAILED(hr)) { printf("ECHEC compilation VS 0x%08lx : %.400s\n", (unsigned long)hr,
      err ? (char*)ID3D10Blob_GetBufferPointer(err) : "(pas de message)"); return 1; }
   hr = D3DCompile(hlsl, strlen(hlsl), NULL, NULL, NULL, "ps_main", "ps_5_0", 0, 0, &ps, &err);
   if (FAILED(hr)) { printf("ECHEC compilation PS 0x%08lx : %.400s\n", (unsigned long)hr,
      err ? (char*)ID3D10Blob_GetBufferPointer(err) : "(pas de message)"); return 1; }
   printf("HLSL compile par d3dcompiler_47 : VS %zu octets, PS %zu octets\n",
          (size_t)ID3D10Blob_GetBufferSize(vs), (size_t)ID3D10Blob_GetBufferSize(ps));

   D3D12_INPUT_ELEMENT_DESC il[3] = {
      {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0},
      {"NORMAL",  0,DXGI_FORMAT_R32G32B32_FLOAT,0,12,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0},
      {"TEXCOORD",0,DXGI_FORMAT_R32G32_FLOAT,   0,24,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0},
   };
   D3D12_GRAPHICS_PIPELINE_STATE_DESC pd = {0};
   pd.pRootSignature = rs;
   pd.VS.pShaderBytecode = ID3D10Blob_GetBufferPointer(vs); pd.VS.BytecodeLength = ID3D10Blob_GetBufferSize(vs);
   pd.PS.pShaderBytecode = ID3D10Blob_GetBufferPointer(ps); pd.PS.BytecodeLength = ID3D10Blob_GetBufferSize(ps);
   pd.InputLayout.pInputElementDescs = il; pd.InputLayout.NumElements = 3;
   pd.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
   pd.RasterizerState.CullMode = D3D12_CULL_MODE_BACK;
   pd.RasterizerState.DepthClipEnable = TRUE;
   pd.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
   pd.DepthStencilState.DepthEnable = TRUE;
   pd.DepthStencilState.DepthWriteMask = D3D12_DEPTH_WRITE_MASK_ALL;
   pd.DepthStencilState.DepthFunc = D3D12_COMPARISON_FUNC_LESS;
   pd.DepthStencilState.StencilEnable = FALSE;
   pd.DepthStencilState.FrontFace.StencilFailOp = D3D12_STENCIL_OP_KEEP;
   pd.DepthStencilState.FrontFace.StencilDepthFailOp = D3D12_STENCIL_OP_KEEP;
   pd.DepthStencilState.FrontFace.StencilPassOp = D3D12_STENCIL_OP_KEEP;
   pd.DepthStencilState.FrontFace.StencilFunc = D3D12_COMPARISON_FUNC_ALWAYS;
   pd.DepthStencilState.BackFace = pd.DepthStencilState.FrontFace;
   pd.BlendState.RenderTarget[0].SrcBlend = D3D12_BLEND_ONE;
   pd.BlendState.RenderTarget[0].DestBlend = D3D12_BLEND_ZERO;
   pd.BlendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
   pd.BlendState.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
   pd.BlendState.RenderTarget[0].DestBlendAlpha = D3D12_BLEND_ZERO;
   pd.BlendState.RenderTarget[0].BlendOpAlpha = D3D12_BLEND_OP_ADD;
   pd.BlendState.RenderTarget[0].LogicOp = D3D12_LOGIC_OP_NOOP;
   pd.SampleMask = UINT_MAX;
   pd.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
   pd.NumRenderTargets = 1; pd.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM;
   pd.DSVFormat = DXGI_FORMAT_D32_FLOAT;
   pd.SampleDesc.Count = 1;
   CK(ID3D12Device_CreateGraphicsPipelineState(dev, &pd, &IID_ID3D12PipelineState, (void**)&pso));

   CK(ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc[0], pso,
      &IID_ID3D12GraphicsCommandList, (void**)&cl));
   D3D12_TEXTURE_COPY_LOCATION dst = { .pResource = tex,
      .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0 };
   D3D12_TEXTURE_COPY_LOCATION src = { .pResource = tex_up,
      .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = fp };
   ID3D12GraphicsCommandList_CopyTextureRegion(cl, &dst, 0,0,0, &src, NULL);
   D3D12_RESOURCE_BARRIER tb = {0};
   tb.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
   tb.Transition.pResource = tex;
   tb.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
   tb.Transition.StateAfter = D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
   tb.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
   ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &tb);
   CK(ID3D12GraphicsCommandList_Close(cl));
   ID3D12CommandList *lists[1] = { (ID3D12CommandList*)cl };
   ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);

   CK(ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void**)&fence));
   fence_event = CreateEventA(NULL, FALSE, FALSE, NULL);
   wait_gpu(0);

   D3D12_VIEWPORT vp = {0,0,(float)W,(float)H,0,1};
   D3D12_RECT sc = {0,0,W,H};
   const float clear[4] = {0.08f, 0.10f, 0.16f, 1.0f};
   D3D12_GPU_DESCRIPTOR_HANDLE srv_gpu;
   srv_heap->lpVtbl->GetGPUDescriptorHandleForHeapStart(srv_heap, &srv_gpu);

   LARGE_INTEGER freq, t0, t1; QueryPerformanceFrequency(&freq); QueryPerformanceCounter(&t0);
   UINT drawn = 0;

   for (UINT f = 0; f < NFRAMES; f++) {
      MSG msg;
      while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
         TranslateMessage(&msg); DispatchMessageA(&msg);
         if (msg.message == WM_QUIT) goto done;
      }

      UINT bi = IDXGISwapChain3_GetCurrentBackBufferIndex(swap);
      CK(ID3D12CommandAllocator_Reset(alloc[bi]));
      CK(ID3D12GraphicsCommandList_Reset(cl, alloc[bi], pso));

      float a = (float)f * 0.031f, b = (float)f * 0.021f;
      float ca = cosf(a), sa = sinf(a), cbb = cosf(b), sbb = sinf(b);
      float ry[16] = { ca,0,sa,0,  0,1,0,0,  -sa,0,ca,0,  0,0,0,1 };
      float rx[16] = { 1,0,0,0,  0,cbb,-sbb,0,  0,sbb,cbb,0,  0,0,0,1 };
      float view[16] = { 1,0,0,0,  0,1,0,0,  0,0,1,0,  0,0,6,1 };
      float fovy = 1.0f, aspect = (float)W/(float)H, zn = 0.1f, zf = 100.f;
      float yy = 1.0f/tanf(fovy*0.5f), xx = yy/aspect;
      float proj[16] = { xx,0,0,0,  0,yy,0,0,  0,0,zf/(zf-zn),1,  0,0,-zn*zf/(zf-zn),0 };
      int side = 1; while (side * side * side < NCUBES) side++;
      float spread = (side > 1) ? 3.0f : 0.0f;
      for (int c = 0; c < NCUBES; c++) {
         int cx = c % side, cy = (c / side) % side, cz = c / (side * side);
         float ox = (cx - (side-1)*0.5f) * spread;
         float oy = (cy - (side-1)*0.5f) * spread;
         float oz = (cz - (side-1)*0.5f) * spread;
         float trans[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, ox,oy,oz,1 };
         float dist = 6.0f + spread * side * 0.9f;
         float viewn[16] = { 1,0,0,0,  0,1,0,0,  0,0,1,0,  0,0,dist,1 };
         struct scene s;
         mat_mul(s.mvp, rx, ry);
         mat_mul(s.mvp, s.mvp, trans);
         mat_mul(s.mvp, s.mvp, viewn);
         mat_mul(s.mvp, s.mvp, proj);
         s.light[0] = 0.4f; s.light[1] = 0.8f; s.light[2] = -0.5f; s.light[3] = 0.f;
         memcpy(cb_cpu + 256 * c, &s, sizeof s);
      }

      D3D12_RESOURCE_BARRIER rb = {0};
      rb.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      rb.Transition.pResource = rt[bi];
      rb.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
      rb.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
      rb.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &rb);

      D3D12_CPU_DESCRIPTOR_HANDLE h = rtvh; h.ptr += (SIZE_T)bi * rtv_size;
      ID3D12GraphicsCommandList_OMSetRenderTargets(cl, 1, &h, FALSE, &dsvh);
      ID3D12GraphicsCommandList_ClearRenderTargetView(cl, h, clear, 0, NULL);
      ID3D12GraphicsCommandList_ClearDepthStencilView(cl, dsvh, D3D12_CLEAR_FLAG_DEPTH, 1.0f, 0, 0, NULL);
      ID3D12GraphicsCommandList_RSSetViewports(cl, 1, &vp);
      ID3D12GraphicsCommandList_RSSetScissorRects(cl, 1, &sc);
      ID3D12GraphicsCommandList_SetGraphicsRootSignature(cl, rs);
      ID3D12DescriptorHeap *heaps[1] = { srv_heap };
      ID3D12GraphicsCommandList_SetDescriptorHeaps(cl, 1, heaps);
      ID3D12GraphicsCommandList_SetGraphicsRootDescriptorTable(cl, 1, srv_gpu);
      ID3D12GraphicsCommandList_IASetPrimitiveTopology(cl, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
      ID3D12GraphicsCommandList_IASetVertexBuffers(cl, 0, 1, &vbv);
      ID3D12GraphicsCommandList_IASetIndexBuffer(cl, &ibv);
      for (int c = 0; c < NCUBES; c++) {
         ID3D12GraphicsCommandList_SetGraphicsRootConstantBufferView(cl, 0,
            ID3D12Resource_GetGPUVirtualAddress(cb) + (UINT64)256 * c);
         ID3D12GraphicsCommandList_DrawIndexedInstanced(cl, 36, 1, 0, 0, 0);
      }

      rb.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
      rb.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
      ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &rb);
      CK(ID3D12GraphicsCommandList_Close(cl));
      ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);
      CK(IDXGISwapChain3_Present(swap, 0, 0));
      wait_gpu(bi);
      drawn++;
   }
done:
   QueryPerformanceCounter(&t1);
   double secs = (double)(t1.QuadPart - t0.QuadPart) / (double)freq.QuadPart;
   printf("%d cube(s), %u images en %.2f s  (%.1f img/s, %.0f appels de dessin/s)\n",
          NCUBES, drawn, secs, drawn / secs, drawn * (double)NCUBES / secs);

   /* Verification : relire la derniere image presentee. */
   UINT bi = (IDXGISwapChain3_GetCurrentBackBufferIndex(swap) + FRAMES - 1) % FRAMES;
   D3D12_RESOURCE_DESC rdesc = { 0 };
   rt[bi]->lpVtbl->GetDesc(rt[bi], &rdesc);
   D3D12_PLACED_SUBRESOURCE_FOOTPRINT rfp; UINT64 rsize = 0;
   ID3D12Device_GetCopyableFootprints(dev, &rdesc, 0, 1, 0, &rfp, NULL, NULL, &rsize);
   D3D12_HEAP_PROPERTIES hp_rb = { D3D12_HEAP_TYPE_READBACK };
   ID3D12Resource *rbuf;
   bd.Width = rsize;
   CK(ID3D12Device_CreateCommittedResource(dev, &hp_rb, D3D12_HEAP_FLAG_NONE, &bd,
      D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void**)&rbuf));
   CK(ID3D12CommandAllocator_Reset(alloc[0]));
   CK(ID3D12GraphicsCommandList_Reset(cl, alloc[0], NULL));
   D3D12_RESOURCE_BARRIER rb2 = {0};
   rb2.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
   rb2.Transition.pResource = rt[bi];
   rb2.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
   rb2.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
   rb2.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
   ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &rb2);
   D3D12_TEXTURE_COPY_LOCATION rd = { .pResource = rbuf,
      .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = rfp };
   D3D12_TEXTURE_COPY_LOCATION rs2 = { .pResource = rt[bi],
      .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0 };
   ID3D12GraphicsCommandList_CopyTextureRegion(cl, &rd, 0,0,0, &rs2, NULL);
   CK(ID3D12GraphicsCommandList_Close(cl));
   ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);
   wait_gpu(0);

   UINT8 *px;
   CK(ID3D12Resource_Map(rbuf, 0, &nr, (void**)&px));
   UINT distinct = 0, bg = 0, lit = 0;
   UINT32 seen[64]; UINT nseen = 0;
   for (UINT y = 0; y < H; y += 4) {
      const UINT8 *row = px + rfp.Footprint.RowPitch * y;
      for (UINT x = 0; x < W; x += 4) {
         UINT32 c = *(const UINT32*)(row + x*4) | 0xff000000u;
         UINT32 q = (c & 0xe0e0e0u);
         if (row[x*4+0] < 40 && row[x*4+1] < 45 && row[x*4+2] < 55) { bg++; continue; }
         lit++;
         UINT k; for (k = 0; k < nseen; k++) if (seen[k] == q) break;
         if (k == nseen && nseen < 64) { seen[nseen++] = q; distinct++; }
      }
   }
   /* Capture de l'image finale en BMP 24 bits, pour regarder le resultat. */
   {
      FILE *f = fopen("cube.bmp", "wb");
      if (f) {
         UINT row_b = (W * 3 + 3) & ~3u;
         UINT img_b = row_b * H;
         UINT8 hdr[54] = {0};
         hdr[0]='B'; hdr[1]='M';
         UINT32 fsz = 54 + img_b;
         memcpy(hdr+2,&fsz,4); UINT32 off = 54; memcpy(hdr+10,&off,4);
         UINT32 ih = 40; memcpy(hdr+14,&ih,4);
         INT32 w32 = W, h32 = H; memcpy(hdr+18,&w32,4); memcpy(hdr+22,&h32,4);
         UINT16 planes = 1, bpp = 24; memcpy(hdr+26,&planes,2); memcpy(hdr+28,&bpp,2);
         memcpy(hdr+34,&img_b,4);
         fwrite(hdr,1,54,f);
         UINT8 *line = malloc(row_b);
         for (INT y = (INT)H - 1; y >= 0; y--) {
            const UINT8 *srow = px + rfp.Footprint.RowPitch * (UINT)y;
            memset(line, 0, row_b);
            for (UINT x = 0; x < W; x++) {
               line[x*3+0] = srow[x*4+2];
               line[x*3+1] = srow[x*4+1];
               line[x*3+2] = srow[x*4+0];
            }
            fwrite(line,1,row_b,f);
         }
         free(line);
         fclose(f);
         printf("image finale ecrite dans cube.bmp (%ux%u)\n", W, H);
      }
   }

   ID3D12Resource_Unmap(rbuf, 0, NULL);

   UINT total = (H/4) * (W/4);
   printf("\nderniere image : %u points echantillonnes, %u de fond, %u de geometrie, %u teintes distinctes\n",
          total, bg, lit, distinct);

   int fail = 0;
   if (bg == 0) { printf("ECHEC : aucun fond, l'effacement n'a pas eu lieu\n"); fail++; }
   if (lit < total / 20) { printf("ECHEC : trop peu de geometrie (%u points)\n", lit); fail++; }
   if (distinct < 3) { printf("ECHEC : %u teintes, la texture ou l'eclairage manquent\n", distinct); fail++; }
   if (drawn != NFRAMES) { printf("ECHEC : %u images sur %u\n", drawn, NFRAMES); fail++; }

   printf("\n%s (%d echec(s))\n", fail ? "ECHECS" : "TOUT PASSE", fail);
   return fail ? 1 : 0;
}
