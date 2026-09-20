/* Sonde : reproduit la sequence de test_shared_resource qui arrete la suite d3d11.
 * Chaque etape est annoncee avant d'etre executee et la sortie est vidangee, de
 * sorte que la derniere ligne imprimee designe l'appel fautif. */
#define COBJMACROS
#include <stdio.h>
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <winternl.h>

#define STEP(fmt, ...) do { printf("  " fmt "\n", ##__VA_ARGS__); fflush(stdout); } while (0)

static void run(UINT misc)
{
    D3D_FEATURE_LEVEL got_fl, want_fl = D3D_FEATURE_LEVEL_11_1;
    D3D11_TEXTURE2D_DESC desc;
    ID3D11Device *device = NULL;
    ID3D11Device1 *device1 = NULL;
    ID3D11Texture2D *tex = NULL, *tex2 = NULL;
    IDXGIResource *res = NULL;
    IDXGIResource1 *res1 = NULL;
    HANDLE h = (HANDLE)0xdeadbeef, h2 = NULL, handle = NULL;
    HRESULT hr;
    BOOL bret;

    printf("== MiscFlags %#x ==\n", misc);
    fflush(stdout);

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, &want_fl, 1,
            D3D11_SDK_VERSION, &device, &got_fl, NULL);
    if (FAILED(hr)) { printf("  peripherique refuse %#lx\n", hr); return; }
    hr = ID3D11Device_QueryInterface(device, &IID_ID3D11Device1, (void **)&device1);
    if (FAILED(hr)) { printf("  pas d'ID3D11Device1 %#lx\n", hr); goto done; }

    memset(&desc, 0, sizeof(desc));
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.Width = desc.Height = 256;
    desc.MipLevels = desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.MiscFlags = misc;

    STEP("CreateTexture2D");
    hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &tex);
    if (FAILED(hr)) { printf("  texture refusee %#lx\n", hr); goto done; }

    STEP("QueryInterface IDXGIResource / IDXGIResource1");
    ID3D11Texture2D_QueryInterface(tex, &IID_IDXGIResource, (void **)&res);
    hr = ID3D11Texture2D_QueryInterface(tex, &IID_IDXGIResource1, (void **)&res1);
    if (FAILED(hr)) { printf("  pas d'IDXGIResource1 %#lx\n", hr); goto done; }

    STEP("GetSharedHandle");
    hr = IDXGIResource_GetSharedHandle(res, &h);
    printf("     hr=%#lx h=%p\n", hr, h); fflush(stdout);
    if (SUCCEEDED(hr) && (misc & D3D11_RESOURCE_MISC_SHARED_NTHANDLE) == 0)
        handle = h;

    STEP("CreateSharedHandle");
    h = (HANDLE)0xdeadbeef;
    hr = IDXGIResource1_CreateSharedHandle(res1, NULL,
            GENERIC_ALL | DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE, NULL, &h);
    printf("     hr=%#lx h=%p\n", hr, h); fflush(stdout);
    if (SUCCEEDED(hr) && (misc & D3D11_RESOURCE_MISC_SHARED_NTHANDLE))
        handle = h;

    if (!misc) goto done;

    STEP("DuplicateHandle");
    bret = DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), &h2, 0, FALSE,
            DUPLICATE_SAME_ACCESS);
    printf("     bret=%d err=%lu\n", bret, GetLastError()); fflush(stdout);
    if (bret) { STEP("CloseHandle du duplicata"); CloseHandle(h2); }

    {
        char buffer[1024];
        OBJECT_TYPE_INFORMATION *type = (OBJECT_TYPE_INFORMATION *)buffer;
        NTSTATUS status;
        ULONG len = 0;

        STEP("NtQueryObject");
        status = NtQueryObject(h, ObjectTypeInformation, buffer, sizeof(buffer), &len);
        printf("     status=%#lx len=%lu\n", (DWORD)status, len); fflush(stdout);
        STEP("wcscmp sur TypeName.Buffer=%p (le tampon n'est pas initialise)", type->TypeName.Buffer);
        printf("     wcscmp=%d\n", wcscmp(type->TypeName.Buffer, L"DxgkSharedResource")); fflush(stdout);
    }

    STEP("OpenSharedResource(%p)", handle);
    hr = ID3D11Device_OpenSharedResource(device, handle, &IID_ID3D11Texture2D, (void **)&tex2);
    printf("     hr=%#lx\n", hr); fflush(stdout);
    if (SUCCEEDED(hr)) ID3D11Texture2D_Release(tex2);

    STEP("OpenSharedResource1(%p)", handle);
    hr = ID3D11Device1_OpenSharedResource1(device1, handle, &IID_ID3D11Texture2D, (void **)&tex2);
    printf("     hr=%#lx\n", hr); fflush(stdout);
    if (SUCCEEDED(hr)) ID3D11Texture2D_Release(tex2);

    STEP("CloseHandle(%p)", handle);
    bret = CloseHandle(handle);
    printf("     bret=%d err=%lu\n", bret, GetLastError()); fflush(stdout);

done:
    if (res) IDXGIResource_Release(res);
    if (res1) IDXGIResource1_Release(res1);
    if (tex) ID3D11Texture2D_Release(tex);
    if (device1) ID3D11Device1_Release(device1);
    if (device) ID3D11Device_Release(device);
    printf("  -- fin du cas --\n"); fflush(stdout);
}

int main(void)
{
    static const UINT cases[] = {
        0,
        D3D11_RESOURCE_MISC_SHARED,
        D3D11_RESOURCE_MISC_SHARED_NTHANDLE,
        D3D11_RESOURCE_MISC_SHARED | D3D11_RESOURCE_MISC_SHARED_NTHANDLE,
        D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX,
        D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX | D3D11_RESOURCE_MISC_SHARED_NTHANDLE,
    };
    unsigned i;
    for (i = 0; i < ARRAYSIZE(cases); ++i)
        run(cases[i]);
    printf("sonde terminee\n");
    return 0;
}
