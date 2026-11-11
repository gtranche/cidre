#!/bin/sh
# Construit, depuis la serie du depot, les pieces de la pile Diablo IV (ilot TSO) : voir INTEGRATION_D4.md.
#
#   sh tests/construire_pile_d4.sh kk     pilote KosmicKrisp (build/mesa-d4), cle de code figee (KK_CODEGEN_FIGE)
#   sh tests/construire_pile_d4.sh fex    xtajit64.dll (third_party/FEX/build-ec), drapeaux de construire_fex.sh
#   sh tests/construire_pile_d4.sh wine   Wine 11 arm64 (build/wine11-arm64-ec -> wine/wine11-arm64), deux drapeaux TEB
#   sh tests/construire_pile_d4.sh pe     DLL PE de l'ilot sans ldp q (outils/construire_pe_sans_ldp.py --thunks)
#   sh tests/construire_pile_d4.sh ilot   artefacts de l'ilot (wine/ilot) pour tests/ilot.sh, avec leur manifeste
#   sh tests/construire_pile_d4.sh marqueurs   sha1 et marqueurs des pieces construites (build/pile-d4)
#
# Prerequis : etape1 (src/mesa, src/wine11, third_party/FEX patches par la serie), toolchain/ (llvm-mingw, ninja),
# prefix/ (dependances : mesa_clc, gstreamer...). CIDRE_PREFIXE_DEPS remplace prefix/ (lu seulement).
# Sorties : build/pile-d4/ (kk/, xtajit64.dll, pe/), wine/wine11-arm64 (wine), wine/ilot (ilot).
# Rien n'est pose dans un prefixe ni dans le Cidre installe.
#
# KK_CODEGEN_FIGE : cle de code figee a celle du pilote du joueur (tests/cle_kk_figee.sh : pourquoi, et la garde
# qui verifie apres coup que les sources hachees sont bien celles de kk-0494). CIDRE_KK_CODEGEN_FIGE=0 calcule.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
TC=${CIDRE_TOOLCHAIN:-$R/toolchain}
DEPS=${CIDRE_PREFIXE_DEPS:-$R/prefix}
OUT=$R/build/pile-d4
J=${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}
mkdir -p "$OUT"

# compilateurs C de l'hote forces en arm64 : le ninja de la toolchain peut tourner sous Rosetta et transmet sa
# personnalite x86_64 a ses fils (blake3_neon.c refuse alors de compiler)
enveloppes() {
   E=$OUT/cc-arm64; mkdir -p "$E"
   for c in cc c++ clang clang++; do
      printf '#!/bin/sh\nexec /usr/bin/%s -arch arm64 "$@"\n' "$c" > "$E/$c"; chmod +x "$E/$c"
   done
   echo "$E"
}

marqueur() { LC_ALL=C grep -a -o -m1 "$2" "$1" 2>/dev/null | head -1; }

case ${1:-} in
kk)
   [ -d "$R/src/mesa/src/kosmickrisp" ] || { echo "src/mesa absent : etape1 d'abord" >&2; exit 1; }
   B=$R/build/mesa-d4
   PATH="$(enveloppes):$DEPS/bin:/opt/homebrew/bin:$TC/bin:$PATH"; export PATH
   [ -f "$B/build.ninja" ] || meson setup "$B" "$R/src/mesa" --native-file "$R/llvm-native.ini" -Dbuildtype=release \
      -Degl=disabled -Dgallium-drivers= -Dgbm=disabled -Dglx=disabled -Dinstall-mesa-clc=true \
      -Dinstall-precomp-compiler=true -Dopengl=false -Dplatforms=macos -Dprefix="$OUT/prefix-kk" \
      -Dvulkan-drivers=kosmickrisp
   KK_CODEGEN_FIGE=$(sh "$R/tests/cle_kk_figee.sh" valeur)
   if [ -n "$KK_CODEGEN_FIGE" ]; then export KK_CODEGEN_FIGE; else unset KK_CODEGEN_FIGE; fi
   ninja -C "$B" -j"$J" src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
   L=$B/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
   file "$L" | grep -q arm64 || { echo "ECHEC : $L n'est pas arm64" >&2; file "$L"; exit 4; }
   mkdir -p "$OUT/kk"
   cp "$L" "$OUT/kk/libvulkan_kosmickrisp.dylib.neuf" && mv "$OUT/kk/libvulkan_kosmickrisp.dylib.neuf" "$OUT/kk/libvulkan_kosmickrisp.dylib"
   printf '{"ICD":{"api_version":"1.4.362","library_path":"%s"},"file_format_version":"1.0.1"}\n' \
      "$OUT/kk/libvulkan_kosmickrisp.dylib" > "$OUT/kk/kosmickrisp_d4_icd.json"
   shasum "$OUT/kk/libvulkan_kosmickrisp.dylib"
   marqueur "$OUT/kk/libvulkan_kosmickrisp.dylib" 'KK_CODEGEN=[0-9]*-[0-9a-f]*'
   sh "$R/tests/cle_kk_figee.sh" verifier "$B"
   ;;
fex)
   FEX=$R/third_party/FEX
   [ -d "$FEX/.git" ] || { echo "FEX absent : etape1 --cloner d'abord" >&2; exit 1; }
   [ -f "$R/outils/libntdll_teb_arm64ec.a" ] || { echo "outils/libntdll_teb_arm64ec.a absent : etape1 d'abord" >&2; exit 1; }
   PATH="$TC/llvm-mingw/bin:$TC/bin:$PATH"; export PATH
   SANS_X18="-D__MINGW_TEB_SANS_X18 -DFEX_TEB_SANS_X18"
   LIEN="-static -Wl,--file-alignment=4096,/mllvm:-align-loops=1"
   [ -f "$FEX/build-ec/build.ninja" ] || cmake -S "$FEX" -B "$FEX/build-ec" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$FEX/Data/CMake/toolchain_mingw.cmake" -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DTUNE_CPU=generic -DENABLE_LTO=False \
      -DCMAKE_C_FLAGS="$SANS_X18" -DCMAKE_CXX_FLAGS="$SANS_X18" -DCMAKE_ASM_FLAGS="$SANS_X18" \
      -DCMAKE_SHARED_LINKER_FLAGS="$LIEN $R/outils/libntdll_teb_arm64ec.a" -DCMAKE_EXE_LINKER_FLAGS="$LIEN" \
      -DENABLE_CCACHE=OFF >/dev/null
   ninja -C "$FEX/build-ec" -j"$J" arm64ecfex
   cp "$FEX/build-ec/Bin/libarm64ecfex.dll" "$OUT/xtajit64.dll.neuf" && mv "$OUT/xtajit64.dll.neuf" "$OUT/xtajit64.dll"
   shasum "$OUT/xtajit64.dll"
   ;;
wine)
   [ -f "$R/src/wine11/dlls/ntdll/unix/ilot.c" ] || { echo "src/wine11 sans 0290 : etape1 d'abord" >&2; exit 1; }
   WPATH="/opt/homebrew/opt/bison/bin:/usr/local/opt/bison/bin:$TC/llvm-mingw/bin:$TC/bin:$PATH"
   B=$R/build/wine11-arm64-ec
   if [ ! -f "$B/Makefile" ]; then
      mkdir -p "$B"
      # configure.ac n'est pas touche par la serie de l'ilot ; configure est regenere si une autre l'a change
      [ "$R/src/wine11/configure" -nt "$R/src/wine11/configure.ac" ] || (cd "$R/src/wine11" && autoconf -f && rm -rf autom4te.cache)
      ( cd "$B" && PATH=$WPATH PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" "$R/src/wine11/configure" \
           --prefix="$R/wine/wine11-arm64" --host=aarch64-apple-darwin --build=aarch64-apple-darwin \
           --enable-archs=i386,arm64ec,aarch64 --disable-tests --without-x \
           --without-oss --without-gphoto --without-sane --without-pcap --without-usb \
           --without-krb5 --without-gssapi --without-ffmpeg \
           LDFLAGS="-L$DEPS/lib" CPPFLAGS="-I$DEPS/include" >"$B/configure.log" 2>&1 ) \
         || { echo "configure a echoue : $B/configure.log" >&2; exit 1; }
   fi
   # les deux drapeaux TEB, toujours (sans eux NtCurrentTeb() repasse par x18, efface par macOS)
   PATH=$WPATH make -C "$B" -j"$J" aarch64_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" \
      arm64ec_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" install
   W=$R/wine/wine11-arm64/lib/wine
   "$TC/llvm-mingw/bin/llvm-readobj" --file-headers "$W/aarch64-windows/ntdll.dll" | grep -q ARM64X \
      || { echo "ntdll.dll n'est pas ARM64X" >&2; exit 4; }
   marqueur "$W/aarch64-unix/ntdll.so" 'garde controlee' >/dev/null || { echo "ntdll.so sans l'ilot (0290/0293)" >&2; exit 4; }
   shasum "$W/aarch64-unix/ntdll.so" "$W/aarch64-unix/win32u.so" "$W/aarch64-windows/ntdll.dll"
   ;;
pe)
   B=$R/build/wine11-arm64-ec
   [ -f "$B/Makefile" ] || { echo "Wine non construit : construire_pile_d4.sh wine d'abord" >&2; exit 1; }
   python3 -I "$R/outils/construire_pe_sans_ldp.py" --build "$B" --src "$R/src/wine11" --sortie "$OUT/pe" \
      --toolchain "$TC/llvm-mingw/bin" --thunks ntdll kernelbase kernel32 ucrtbase msvcrt
   ;;
ilot)
   # Depuis 0290/0293/0294 dans la serie, ntdll.so et win32u.so du runtime de Cidre portent deja l'ilot (inactif
   # sans CIDRE_ILOT) et xtajit64 est le FEX de la serie : seules les cinq DLL PE sans ldp q (et 0309) different.
   # (rangees comme un runtime, puis importees par ilot.sh : un seul format de manifeste)
   D=$OUT/ilot-dev/lib/wine/aarch64-windows; mkdir -p "$D"
   for d in ntdll kernelbase kernel32 ucrtbase msvcrt; do
      [ -f "$OUT/pe/$d.dll" ] || { echo "$OUT/pe/$d.dll absent : construire_pile_d4.sh pe d'abord" >&2; exit 1; }
      cp "$OUT/pe/$d.dll" "$D/$d.dll"
   done
   CIDRE_ILOT_REL=${CIDRE_ILOT_REL:-$R/wine/wine11-arm64} sh "$R/tests/ilot.sh" importer "$OUT/ilot-dev"
   ;;
marqueurs)
   for f in "$OUT/kk/libvulkan_kosmickrisp.dylib" "$OUT/xtajit64.dll" "$R/wine/wine11-arm64/lib/wine/aarch64-unix/ntdll.so" \
            "$R/wine/wine11-arm64/lib/wine/aarch64-unix/win32u.so" "$OUT/pe/ntdll.dll"; do
      [ -f "$f" ] && echo "$(shasum "$f" | cut -c1-8)  $f"
   done
   ;;
*) sed -n '2,9p' "$0"; exit 2 ;;
esac
