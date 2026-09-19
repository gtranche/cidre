#!/bin/sh
# Compile un echantillon Microsoft DirectX-Graphics-Samples pour la pile ouverte.
# L'arbre tiers n'est jamais modifie : on copie les sources puis on applique des
# substitutions purement mecaniques (retours agreges, Wrappers::FileHandle).
#   usage: build_dx_sample.sh <chemin/relatif/vers/src> <NomSortie>
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
SRC="$R/third_party/DirectX-Graphics-Samples/$1"
NAME="$2"
[ -d "$SRC" ] || { echo "source introuvable: $SRC" >&2; exit 1; }

CXX=$(echo "$R"/toolchain/llvm-mingw-*/bin/x86_64-w64-mingw32-clang++)
WORK="$R/build/samples/src/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$SRC"/*.cpp "$SRC"/*.h "$WORK"/ 2>/dev/null
OUT="$R/build/samples/$NAME"
mkdir -p "$OUT"
cp "$SRC"/*.hlsl "$OUT"/ 2>/dev/null || true

for f in "$WORK"/*.cpp "$WORK"/*.h; do
   [ -f "$f" ] || continue
   sed -i '' \
      -e 's/\([A-Za-z_][A-Za-z0-9_]*\)->GetCPUDescriptorHandleForHeapStart()/D3DX_CpuStart(\1.Get())/g' \
      -e 's/\([A-Za-z_][A-Za-z0-9_]*\)->GetGPUDescriptorHandleForHeapStart()/D3DX_GpuStart(\1.Get())/g' \
      -e 's/, L#x)/, D3DX_WIDE(#x))/g' \
      -e 's/, L#x, n)/, D3DX_WIDE(#x), n)/g' \
      "$f"
done

# Capture hors ecran optionnelle : $3 = nom du BMP. On insere une copie de la
# cible de rendu juste avant Present, sans toucher au rendu lui-meme.
if [ -n "$3" ]; then
   for f in "$WORK"/*.cpp; do
      [ -f "$f" ] || continue
      sed -i '' \
         -e 's|ThrowIfFailed(m_swapChain->Present(1, 0));|D3DX_CaptureOnce(m_device.Get(), m_commandQueue.Get(), m_renderTargets[m_frameIndex].Get(), m_width, m_height, "'"$3"'", '"${CAPFRAME:-30}"');\
        ThrowIfFailed(m_swapChain->Present(1, 0));|' \
         "$f"
   done
fi

"$CXX" -std=c++17 -O2 -DUNICODE -D_UNICODE \
   -include "$R/build/samples/inc/mingw_shim.h" \
   -include "$R/build/samples/inc/d3dx_capture.h" \
   -Wno-address-of-temporary -Wno-deprecated-declarations \
   -I "$R/third_party/DirectX-Headers/include/directx" \
   -I "$R/third_party/DirectX-Headers/include" \
   -I "$R/third_party/DirectXMath/Inc" \
   -I "$R/build/samples/inc" -I "$WORK" \
   "$WORK"/*.cpp \
   -o "$OUT/$NAME.exe" \
   -ld3d12 -ldxgi -ld3dcompiler -ldxguid -luuid -lshell32 -lgdi32 -static-libgcc -static-libstdc++
echo "construit: build/samples/$NAME/$NAME.exe"
