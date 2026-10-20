// Temoin du correctif wine11 0188 : DirectWrite rend des glyphes a un invite
// 32 bits (relais wow64 de dwrite.so rebases). Runtime sans 0188 : « AUCUN
// PIXEL » et des avances aberrantes (9956964 pour « E » en Arial) ; avec :
// environ 1 300 pixels par mot, comme en 64 bits.
//   i686-w64-mingw32-clang++ -O1 -static -o h32dwrite.exe h32dwrite.cpp -ldwrite
#include <windows.h>
#include <dwrite.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    const wchar_t *familles[] = { L"Arial", L"Segoe UI", L"Tahoma", L"Times New Roman" };
    IDWriteFactory *f = NULL;
    HRESULT hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&f);
    printf("factory %08lx\n", hr);
    if (FAILED(hr)) return 1;
    IDWriteFontCollection *col = NULL;
    hr = f->GetSystemFontCollection(&col, FALSE);
    printf("collection %08lx, %u familles\n", hr, col ? col->GetFontFamilyCount() : 0);
    int total = 0;
    for (auto nom : familles) {
        UINT32 idx = 0; BOOL existe = FALSE;
        col->FindFamilyName(nom, &idx, &existe);
        if (!existe) { printf("%ls : absente\n", nom); continue; }
        IDWriteFontFamily *fam = NULL; IDWriteFont *font = NULL; IDWriteFontFace *face = NULL;
        col->GetFontFamily(idx, &fam);
        fam->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, &font);
        font->CreateFontFace(&face);
        UINT32 cps[5] = { 'E', 'm', 'a', 'i', 'l' };
        UINT16 gl[5] = {0};
        face->GetGlyphIndices(cps, 5, gl);
        DWRITE_GLYPH_RUN run = {};
        float av[5] = { 12, 14, 10, 6, 6 };
        run.fontFace = face; run.fontEmSize = 24; run.glyphCount = 5; run.glyphIndices = gl; run.glyphAdvances = av;
        IDWriteGlyphRunAnalysis *an = NULL;
        hr = f->CreateGlyphRunAnalysis(&run, 1.0f, NULL, DWRITE_RENDERING_MODE_NATURAL, DWRITE_MEASURING_MODE_NATURAL, 0, 30, &an);
        RECT r = {};
        int allumes = 0;
        if (SUCCEEDED(hr)) {
            an->GetAlphaTextureBounds(DWRITE_TEXTURE_CLEARTYPE_3x1, &r);
            int w = r.right - r.left, h = r.bottom - r.top;
            if (w > 0 && h > 0) {
                BYTE *buf = (BYTE *)calloc(w * h, 3);
                hr = an->CreateAlphaTexture(DWRITE_TEXTURE_CLEARTYPE_3x1, &r, buf, w * h * 3);
                for (int i = 0; i < w * h * 3; i++) allumes += buf[i] != 0;
                free(buf);
            }
        }
        DWRITE_GLYPH_METRICS gm[5] = {};
        face->GetDesignGlyphMetrics(gl, 5, gm, FALSE);
        printf("%ls : glyphes %u %u %u, avance E %u, analyse %08lx, boite %ldx%ld, pixels %d\n", nom, gl[0], gl[1], gl[2],
               gm[0].advanceWidth, hr, r.right - r.left, r.bottom - r.top, allumes);
        total += allumes;
    }
    printf("resultat %s\n", total ? "ok" : "AUCUN PIXEL");
    return total ? 0 : 1;
}
