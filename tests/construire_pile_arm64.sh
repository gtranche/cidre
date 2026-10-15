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

echo "== objets TLS sans x18 (lien arm64ec) =="
CXA="$R/outils/cxa_globals_sans_x18_arm64ec.o"
if [ ! -f "$CXA" ]; then
   "$MINGW/arm64ec-w64-mingw32-clang" -c "$R/outils/cxa_globals_sans_x18.c" -o "$CXA"
fi
# Runtime emutls sans x18 : vkd3d-proton se construit en -femulated-tls (ses
# variables __thread fautaient sur [x18,#0x58], mort sur macOS) et appelle ce
# __emutls_get_address, servi en TLS Win32 que le Wine corrige rend x18-free.
EMU="$R/outils/emutls_sans_x18_arm64ec.o"
if [ ! -f "$EMU" ]; then
   "$MINGW/arm64ec-w64-mingw32-clang" -O2 -c "$R/outils/emutls_sans_x18.c" -o "$EMU"
fi
ls -l "$CXA" "$EMU"

echo "== Mesa / KosmicKrisp (arm64) -> prefix/ =="
[ -f "$R/build/mesa/build.ninja" ] || meson setup "$R/build/mesa" "$R/src/mesa" \
   --native-file "$R/llvm-native.ini" -Dbuildtype=release \
   -Degl=disabled -Dgallium-drivers= -Dgbm=disabled -Dglx=disabled \
   -Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true -Dopengl=false \
   -Dplatforms=macos -Dprefix="$R/prefix" -Dvulkan-drivers=kosmickrisp
ninja -C "$R/build/mesa" -j"$J"
ninja -C "$R/build/mesa" install >/dev/null

echo "== Wine 11 arm64 -> wine/wine11-arm64 =="
# bison >= 3 (celui de macOS est trop vieux) et les compilateurs mingw.
WPATH="/opt/homebrew/opt/bison/bin:/usr/local/opt/bison/bin:$MINGW:$PATH"
# SDL2 (Homebrew, brew install sdl2) : winebus.sys le charge par dlopen et lui
# laisse les manettes ; configure sans SDL, winebus ignore les manettes IOHID
# (« ignoring hidraw device ») et aucun jeu ne voit la manette. Un arbre
# configure sans SDL est reconfigure (tout Wine se recompile une fois).
# GStreamer (tests/construire_gstreamer.sh, dans prefix/) : winegstreamer, seul
# decodeur H.264/AAC de Wine 11 et repli du demultiplexeur .mp4 sans FFmpeg.
# Sans lui, aucune video Media Foundation ne joue (Sherlock Holmes Chapter One
# restait sur un ecran noir). Un arbre configure sans GStreamer est reconfigure.
[ -f "$R/prefix/lib/pkgconfig/gstreamer-1.0.pc" ] || sh "$R/tests/construire_gstreamer.sh"
if [ ! -f "$R/build/wine11-arm64-ec/Makefile" ] ||
   ! grep -q '^#define SONAME_LIBSDL2 ' "$R/build/wine11-arm64-ec/include/config.h" ||
   ! grep -q '^GSTREAMER_LIBS *=.*-lgstreamer-1.0' "$R/build/wine11-arm64-ec/Makefile"; then
   mkdir -p "$R/build/wine11-arm64-ec"
   ( cd "$R/build/wine11-arm64-ec" && PATH=$WPATH \
        PKG_CONFIG_PATH="$R/prefix/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" "$R/src/wine11/configure" \
        --prefix="$R/wine/wine11-arm64" \
        --host=aarch64-apple-darwin --build=aarch64-apple-darwin \
        --enable-archs=i386,arm64ec,aarch64 --disable-tests --without-x \
        --without-oss --without-gphoto --without-sane --without-pcap --without-usb \
        --without-krb5 --without-gssapi --without-ffmpeg \
        LDFLAGS="-L$R/prefix/lib" CPPFLAGS="-I$R/prefix/include" )
   grep -q '^#define SONAME_LIBSDL2 ' "$R/build/wine11-arm64-ec/include/config.h" ||
      { echo "SDL2 introuvable pour Wine : brew install sdl2" >&2; exit 1; }
   grep -q '^GSTREAMER_LIBS *=.*-lgstreamer-1.0' "$R/build/wine11-arm64-ec/Makefile" ||
      { echo "GStreamer introuvable pour Wine : sh tests/construire_gstreamer.sh (brew install glib)" >&2; exit 1; }
fi
PATH=$WPATH make -C "$R/build/wine11-arm64-ec" -j"$J" \
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

echo "== vkd3d-proton arm64ec (vrai D3D12, option dx12) =="
# Meme chaine arm64ec que DXVK. hexpthk=1 -> chargeable par un jeu x64 sous FEX
# (l'ancien build arm64 pur etait inchargeable). enable_tests=false : on ne veut
# que les DLL. lancer_depuis_steam.sh les installe en system32 quand dx12 = true.
[ -f "$R/build/vkd3d-winarm64ec/build.ninja" ] || meson setup "$R/build/vkd3d-winarm64ec" "$R/src/vkd3d-proton" \
   --cross-file "$CROSS" -Dbuildtype=release -Denable_tests=false \
   -Dc_args=-femulated-tls -Dcpp_args=-femulated-tls \
   -Dc_link_args="$EMU" -Dcpp_link_args="$CXA $EMU"
ninja -C "$R/build/vkd3d-winarm64ec" -j"$J"

echo
echo "Pile arm64 construite. Ensuite : FEX (construire_fex.sh --installer), le"
echo "prefixe (wineboot -u), deployer DXVK, et brancher_jeux_steam.sh."
