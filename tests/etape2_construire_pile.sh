#!/bin/sh
# Construit la pile ouverte x86_64 de bout en bout.
#
#   PE Windows -> vkd3d-proton (PE) -> Wine 10 -> loader Vulkan -> KosmicKrisp -> Metal 4
#
# Tout est x86_64 : Metal 4 est accessible aux processus traduits par Rosetta (verifie, § 31),
# ce qui evite d'avoir besoin d'un Wine arm64 avec WoW64.
#
# Prerequis, tous deja presents sur la machine de test :
#   - Homebrew Intel (/usr/local) : bison >= 3, mingw-w64, zstd
#   - Homebrew arm64 (/opt/homebrew) : llvm, spirv-tools, cmake, glslang  (outils de build)
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
J=${J:-8}

BISON=/usr/local/opt/bison/bin
MINGW=/usr/local/opt/mingw-w64/bin

echo "== 1/5  outils de compilation Mesa, natifs arm64 =="
PATH=$R/toolchain/bin:$PATH meson configure "$R/build/mesa" \
    -Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true >/dev/null
PATH=$R/toolchain/bin:$PATH ninja -C "$R/build/mesa" >/dev/null
PATH=$R/toolchain/bin:$PATH ninja -C "$R/build/mesa" install >/dev/null

echo "== 2/5  KosmicKrisp x86_64 =="
# -Dmesa-clc=system / -Dprecomp-compiler=system : reutilise les outils natifs ci-dessus,
# sinon meson les reconstruit pour la cible et bute sur SPIRV-Tools, absent en x86_64.
PATH=$R/prefix/bin:$R/toolchain/bin:$PATH \
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig \
  meson setup "$R/build/mesa-x64" "$R/src/mesa" --wipe \
    --cross-file "$R/x86_64-darwin.ini" --native-file "$R/llvm-native.ini" \
    -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dplatforms=macos \
    -Dglx=disabled -Degl=disabled -Dopengl=false -Dgbm=disabled \
    -Dmesa-clc=system -Dprecomp-compiler=system \
    -Dbuildtype=release -Dprefix="$R/prefix-x64" >/dev/null
PATH=$R/prefix/bin:$R/toolchain/bin:$PATH ninja -C "$R/build/mesa-x64" >/dev/null
PATH=$R/prefix/bin:$R/toolchain/bin:$PATH ninja -C "$R/build/mesa-x64" install >/dev/null

echo "== 3/5  loader Vulkan x86_64 =="
cmake -S "$R/src/Vulkan-Loader" -B "$R/build/vk-loader-x64" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=x86_64 -DVULKAN_HEADERS_INSTALL_DIR="$R/prefix" \
      -DCMAKE_INSTALL_PREFIX="$R/prefix-x64" >/dev/null
cmake --build "$R/build/vk-loader-x64" -j"$J" >/dev/null
cmake --install "$R/build/vk-loader-x64" >/dev/null

echo "== 4/5  Wine 10 x86_64 =="
# --host/--build explicites : sans eux configure devine arm64 (config.guess) et injecte
# -D__aarch64__, ce qui fait entrer winnt.h en conflit avec lui-meme.
# --without-ffmpeg : winedmo se construit malgre l'absence des libs 64 bits et casse l'edition
# de liens.  LDFLAGS pointe sur notre loader : Wine grave alors SONAME_LIBVULKAN dessus.
mkdir -p "$R/build/wine"
cd "$R/build/wine"
PATH=$BISON:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin \
CC="clang -arch x86_64" CXX="clang++ -arch x86_64" MACOSX_DEPLOYMENT_TARGET=11.0 \
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
CPPFLAGS="-I$R/prefix/include" LDFLAGS="-L$R/prefix-x64/lib" \
  "$R/src/wine/configure" --prefix="$R/wine/wine10" \
    --host=x86_64-apple-darwin --build=x86_64-apple-darwin \
    --enable-archs=x86_64 --disable-tests --without-x --without-oss --without-freetype \
    --without-gnutls --without-gphoto --without-sane --without-pcap --without-usb \
    --without-gstreamer --without-krb5 --without-gssapi --without-sdl --without-ffmpeg >/dev/null
grep -q 'SONAME_LIBVULKAN "libvulkan' include/config.h || {
    echo "ECHEC: Wine n'a pas trouve notre loader Vulkan"; exit 1; }
PATH=$BISON:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin MACOSX_DEPLOYMENT_TARGET=11.0 make -j"$J" >/dev/null
PATH=$BISON:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin make install >/dev/null

echo "== 5/5  vkd3d-proton en PE Windows =="
PATH=$MINGW:$R/toolchain/bin:$PATH \
  meson setup "$R/build/vkd3d-win64" "$R/src/vkd3d-proton" --wipe \
    --cross-file "$R/src/vkd3d-proton/build-win64.txt" --buildtype release \
    -Denable_tests=true -Dprefix="$R/wine/vkd3d" >/dev/null
PATH=$MINGW:$R/toolchain/bin:$PATH ninja -C "$R/build/vkd3d-win64" >/dev/null

mkdir -p "$R/wine/bin"
cp "$R/build/vkd3d-win64/tests/d3d12.exe" "$R/wine/bin/"
echo
echo "Pile construite. Lancer :  ./tests/etape2_pile_wine.sh wine/bin/d3d12.exe"
