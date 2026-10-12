#!/bin/sh
# Construit FEX en deux modules PE que Wine attend : libarm64ecfex.dll (invites
# x86-64, triple arm64ec) et libwow64fex.dll (invites 32 bits, triple aarch64).
# La recette est celle des CMakeCache de build-ec et build-wow64 : sans x18
# (les deux definitions et la bibliotheque d'import du TEB, etape1), sans LTO.
# Un dossier de construction neuf donne les memes DLL (verifie le 2026-10-12).
# Seules les deux cibles utiles sont construites : libFEXCore.dll, la variante
# partagee que personne ne charge, ne se lie pas dans cette configuration.
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

SANS_X18="-D__MINGW_TEB_SANS_X18 -DFEX_TEB_SANS_X18"
LIEN="-static -Wl,--file-alignment=4096,/mllvm:-align-loops=1"

construire() {
   triple=$1; dir=$2; cible=$3; teb=$4
   [ -f "$R/outils/$teb" ] || { echo "$teb absent : 'sh tests/etape1_appliquer_correctifs.sh' d'abord" >&2; exit 1; }
   echo "== $dir ($triple) =="
   cmake -S "$FEX" -B "$FEX/$dir" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
      -DMINGW_TRIPLE="$triple" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DTUNE_CPU=generic \
      -DENABLE_LTO=False \
      -DCMAKE_C_FLAGS="$SANS_X18" -DCMAKE_CXX_FLAGS="$SANS_X18" -DCMAKE_ASM_FLAGS="$SANS_X18" \
      -DCMAKE_SHARED_LINKER_FLAGS="$LIEN $R/outils/$teb" \
      -DCMAKE_EXE_LINKER_FLAGS="$LIEN" \
      -DENABLE_CCACHE=OFF >/dev/null
   ninja -C "$FEX/$dir" -j"$J" "$cible"
}

construire arm64ec-w64-mingw32 build-ec arm64ecfex libntdll_teb_arm64ec.a
construire aarch64-w64-mingw32 build-wow64 wow64fex libntdll_teb_aarch64.a

ls -l "$FEX/build-ec/Bin/libarm64ecfex.dll" "$FEX/build-wow64/Bin/libwow64fex.dll"
if [ "${1:-}" = "--installer" ]; then
   sh "$R/tests/installer_fex.sh"
else
   echo "construit. 'sh tests/installer_fex.sh' pour les poser dans Wine (xtajit64/xtajit)."
fi
