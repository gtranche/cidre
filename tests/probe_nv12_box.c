/* Sonde : UpdateSubresource sur une texture NV12 avec une boite impaire.
 * Sur Windows l'operation est un non-opérant. On remplit la source avec un
 * octet temoin distinct de zero pour distinguer « la copie a eu lieu » de
 * « la region a ete mise a zero par ailleurs ». */
#define COBJMACROS
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <d3d11.h>

#define W 640
#define H 480
#define TEMOIN 0xab

static ID3D11Device *device;
static ID3D11DeviceContext *ctx;

static unsigned char motif(unsigned i, unsigned j) { return (i & 7) << 3 | (j & 7); }

static int essai(unsigned bx, unsigned by, unsigned bw, unsigned bh)
{
    D3D11_TEXTURE2D_DESC desc = {0}, sdesc = {0};
    D3D11_SUBRESOURCE_DATA init = {0};
    D3D11_MAPPED_SUBRESOURCE map;
    ID3D11Texture2D *tex = NULL, *stage = NULL;
    unsigned char *contenu, *source;
    unsigned i, j;
    HRESULT hr;

    contenu = calloc(W * H * 3 / 2, 1);
    source = malloc(bw * bh * 3 / 2);
    memset(source, TEMOIN, bw * bh * 3 / 2);
    for (i = 0; i < H; ++i)
        for (j = 0; j < W; ++j)
            contenu[i * W + j] = motif(i, j);
    for (i = 0; i < H / 2; ++i)
        for (j = 0; j < W / 2; ++j)
        {
            contenu[W * (H + i) + j * 2] = 1 << 6 | (i & 7) << 3 | (j & 7);
            contenu[W * (H + i) + j * 2 + 1] = 1 << 7 | (i & 7) << 3 | (j & 7);
        }

    desc.Width = W; desc.Height = H; desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_NV12; desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    init.pSysMem = contenu; init.SysMemPitch = W;
    hr = ID3D11Device_CreateTexture2D(device, &desc, &init, &tex);
    if (FAILED(hr)) { printf("  creation NV12 refusee %#lx\n", hr); goto fin; }

    sdesc = desc;
    sdesc.Usage = D3D11_USAGE_STAGING; sdesc.BindFlags = 0;
    sdesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = ID3D11Device_CreateTexture2D(device, &sdesc, NULL, &stage);
    if (FAILED(hr)) { printf("  creation staging refusee %#lx\n", hr); goto fin; }

    {
        D3D11_BOX box;
        box.left = bx; box.top = by; box.front = 0;
        box.right = bx + bw; box.bottom = by + bh; box.back = 1;
        ID3D11DeviceContext_UpdateSubresource(ctx, (ID3D11Resource *)tex, 0, &box, source, bw, 0);
    }

    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)stage, (ID3D11Resource *)tex);
    hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)stage, 0, D3D11_MAP_READ, 0, &map);
    if (FAILED(hr)) { printf("  Map refuse %#lx\n", hr); goto fin; }

    {
        const unsigned char *p = map.pData;
        unsigned char lu = p[by * map.RowPitch + bx];
        unsigned char att = motif(by, bx);
        unsigned temoins = 0;
        for (i = by; i < by + bh; ++i)
            for (j = bx; j < bx + bw; ++j)
                if (p[i * map.RowPitch + j] == TEMOIN) ++temoins;
        printf("  boite %u,%u %ux%u : luma(%u,%u) lu %#04x, intact %#04x ; %u/%u octets = %#04x\n",
                bx, by, bw, bh, bx, by, lu, att, temoins, bw * bh, TEMOIN);
        ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)stage, 0);
        fflush(stdout);
    }

fin:
    if (stage) ID3D11Texture2D_Release(stage);
    if (tex) ID3D11Texture2D_Release(tex);
    free(contenu); free(source);
    return 0;
}

int main(void)
{
    D3D_FEATURE_LEVEL fl;
    UINT support = 0;
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
            D3D11_SDK_VERSION, &device, &fl, &ctx);
    if (FAILED(hr)) { printf("peripherique refuse %#lx\n", hr); return 1; }
    ID3D11Device_CheckFormatSupport(device, DXGI_FORMAT_NV12, &support);
    printf("niveau %#x, support NV12 %#x (TEXTURE2D %s)\n", fl, support,
            (support & D3D11_FORMAT_SUPPORT_TEXTURE2D) ? "oui" : "non");

    printf("boite paire (doit copier) :\n");
    essai(10, 20, 4, 6);
    printf("boites impaires (doivent etre des non-operants) :\n");
    essai(10, 20, 4, 7);
    essai(10, 20, 5, 6);
    essai(10, 21, 4, 6);
    essai(11, 20, 4, 6);

    ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(device);
    return 0;
}
