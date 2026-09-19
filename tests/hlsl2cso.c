/* Compile un .hlsl en .cso via d3dcompiler_47 du prefixe Wine.
 * usage: hlsl2cso.exe <fichier.hlsl> <point_entree> <profil> <sortie.cso> */
#include <windows.h>
#include <d3dcompiler.h>
#include <stdio.h>

int main(int argc, char **argv)
{
   if (argc != 5) {
      printf("usage: hlsl2cso <in.hlsl> <entree> <profil> <out.cso>\n");
      return 2;
   }
   WCHAR wsrc[1024];
   MultiByteToWideChar(CP_ACP, 0, argv[1], -1, wsrc, 1024);

   ID3DBlob *code = NULL, *err = NULL;
   HRESULT hr = D3DCompileFromFile(wsrc, NULL, D3D_COMPILE_STANDARD_FILE_INCLUDE,
                                   argv[2], argv[3], 0, 0, &code, &err);
   if (FAILED(hr)) {
      printf("ECHEC 0x%08lx : %.600s\n", (unsigned long)hr,
             err ? (char *)err->lpVtbl->GetBufferPointer(err) : "(pas de message)");
      return 1;
   }
   FILE *f = fopen(argv[4], "wb");
   if (!f) { printf("ECHEC ouverture %s\n", argv[4]); return 1; }
   size_t n = code->lpVtbl->GetBufferSize(code);
   fwrite(code->lpVtbl->GetBufferPointer(code), 1, n, f);
   fclose(f);
   printf("%s : %zu octets (%s %s)\n", argv[4], n, argv[2], argv[3]);
   return 0;
}
