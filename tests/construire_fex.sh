#!/bin/sh
# Construit FEX en deux modules PE que Wine attend : libarm64ecfex.dll (invites
# x86-64, triple arm64ec) et libwow64fex.dll (invites 32 bits, triple aarch64).
# Aucune ligne du code de FEX n'est touchee -- deux options de cmake suffisent
# (NOTES 222). La recette est exactement celle des CMakeCache existants.
#
#   sh tests/construire_fex.sh            construit build-ec et build-wow64
#   sh tests/construire_fex.sh --installer  construit puis installe dans Wine
#
# Prerequis : etape0_toolchain.sh (llvm-mingw) et etape1 --cloner (FEX clone).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
FEX="$R/third_party/FEX"
[ -d "$FEX/.git" ] || { echo "FEX absent : 'sh tests/etape1_appliquer_correctifs.sh --cloner' d'abord" >&2; exit 1; }
[ -x "$R/toolchain/llvm-mingw/bin/arm64ec-w64-mingw32-clang" ] || { echo "toolchain absente : 'sh tests/etape0_toolchain.sh' d'abord" >&2; exit 1; }

export PATH="$R/toolchain/llvm-mingw/bin:$R/toolchain/bin:$PATH"
TOOLCHAIN_FILE="$FEX/Data/CMake/toolchain_mingw.cmake"
J=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

construire() {
   triple=$1; dir=$2
   echo "== $dir ($triple) =="
   cmake -S "$FEX" -B "$FEX/$dir" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
      -DMINGW_TRIPLE="$triple" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DTUNE_CPU=generic \
      -DENABLE_CCACHE=OFF >/dev/null
   ninja -C "$FEX/$dir" -j"$J"
}

construire arm64ec-w64-mingw32 build-ec
construire aarch64-w64-mingw32 build-wow64

ls -l "$FEX/build-ec/Bin/libarm64ecfex.dll" "$FEX/build-wow64/Bin/libwow64fex.dll"
if [ "${1:-}" = "--installer" ]; then
   sh "$R/tests/installer_fex.sh"
else
   echo "construit. 'sh tests/installer_fex.sh' pour les poser dans Wine (xtajit64/xtajit)."
fi
