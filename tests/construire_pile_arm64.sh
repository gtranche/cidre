#!/bin/sh
# Construit la pile arm64 native : Mesa/KosmicKrisp, Wine 11 arm64, DXVK arm64ec
# (stock + async gplasync). Recettes recuperees des builds configures (exactes).
# Idempotent : reutilise un build-dir deja configure (ninja/make incrementaux).
#   sh tests/construire_pile_arm64.sh
# Prerequis : etape0_prerequis, etape0_toolchain, etape1 --cloner, construire_fex.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$R/toolchain/bin:$PATH"
MINGW="$R/toolchain/llvm-mingw/bin"
J=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "== objet cxa_globals (lien DXVK arm64ec) =="
CXA="$R/outils/cxa_globals_sans_x18_arm64ec.o"
if [ ! -f "$CXA" ]; then
   "$MINGW/arm64ec-w64-mingw32-clang" -c "$R/outils/cxa_globals_sans_x18.c" -o "$CXA"
fi
ls -l "$CXA"

echo "== Mesa / KosmicKrisp (arm64) -> prefix/ =="
[ -f "$R/build/mesa/build.ninja" ] || meson setup "$R/build/mesa" "$R/src/mesa" \
   --native-file "$R/llvm-native.ini" -Dbuildtype=release \
   -Degl=disabled -Dgallium-drivers= -Dgbm=disabled -Dglx=disabled \
   -Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true -Dopengl=false \
   -Dplatforms=macos -Dprefix="$R/prefix" -Dvulkan-drivers=kosmickrisp
ninja -C "$R/build/mesa" -j"$J"
ninja -C "$R/build/mesa" install >/dev/null

echo "== Wine 11 arm64 -> wine/wine11-arm64 =="
if [ ! -f "$R/build/wine11-arm64-ec/Makefile" ]; then
   mkdir -p "$R/build/wine11-arm64-ec"
   ( cd "$R/build/wine11-arm64-ec" && "$R/src/wine11/configure" \
        --prefix="$R/wine/wine11-arm64" \
        --host=aarch64-apple-darwin --build=aarch64-apple-darwin \
        --enable-archs=i386,arm64ec,aarch64 --disable-tests --without-x )
fi
make -C "$R/build/wine11-arm64-ec" -j"$J" \
   aarch64_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" \
   arm64ec_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" install

echo "== DXVK arm64ec (stock + async gplasync) =="
CROSS="$R/src/dxvk/build-winarm64ec.txt"
# arbre async = copie de src/dxvk + patch gplasync
if [ ! -d "$R/src/dxvk-async" ]; then
   cp -R "$R/src/dxvk" "$R/src/dxvk-async"
   patch -d "$R/src/dxvk-async" -p1 < "$R/dxvk-gplasync-2.7.1-1.patch"
fi
for pair in "src/dxvk:build/dxvk-winarm64ec" "src/dxvk-async:build/dxvk-async-winarm64ec"; do
   srcd=${pair%%:*}; bld=${pair##*:}
   [ -f "$R/$bld/build.ninja" ] || meson setup "$R/$bld" "$R/$srcd" \
      --cross-file "$CROSS" -Dbuildtype=release -Dcpp_link_args="$CXA"
   ninja -C "$R/$bld" -j"$J"
done

echo
echo "Pile arm64 construite. Ensuite : FEX (construire_fex.sh --installer), le"
echo "prefixe (wineboot -u), deployer DXVK, et brancher_jeux_steam.sh."
