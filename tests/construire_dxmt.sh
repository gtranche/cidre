#!/bin/sh
# Construit DXMT (D3D11 -> Metal en un saut) en arm64x contre notre Wine 11, sans
# aucune lecture TLS par x18 : -femulated-tls et les deux objets runtime de Cidre
# (emutls_sans_x18, cxa_globals_sans_x18) a la liaison, comme vkd3d-proton dans
# construire_pile_arm64.sh. Sur macOS x18 (TEB) n'est pas entretenu : une variable
# thread_local native lue par « ldr [x18, #0x58] » faute apres une preemption
# (gel vu sur Expedition 33, patch 0114). Idempotent : reutilise un build-dir
# deja configure (ninja incremental).
#   sh tests/construire_dxmt.sh          # configure (si besoin), compile, verifie x18
#   sh tests/construire_dxmt.sh poser    # idem, puis pose les 5 fichiers dans $R/dxmt/
#                                        # (le dossier que prefere le lanceur), le
#                                        # precedent etant garde dans $R/dxmt.precedent/
# Variables : DXMT_SRC (src/dxmt), DXMT_BUILD (src/dxmt/build), NATIVE_LLVM
# (/opt/homebrew/opt/llvm@15), WINE_INSTALL (wine/wine11-arm64).
# Prerequis : Xcode + composant Metal Toolchain (xcodebuild -downloadComponent
# MetalToolchain), brew llvm@15 arm64, ninja arm64 (/opt/homebrew/bin, pas le
# /usr/local/bin x86_64), meson de toolchain/bin, llvm-mingw de toolchain/.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export PATH="/opt/homebrew/bin:$R/toolchain/llvm-mingw/bin:$R/toolchain/bin:$PATH"
MINGW="$R/toolchain/llvm-mingw/bin"
J=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
SRC=${DXMT_SRC:-$R/src/dxmt}
BLD=${DXMT_BUILD:-$SRC/build}
NATIVE_LLVM=${NATIVE_LLVM:-/opt/homebrew/opt/llvm@15}
WINE_INSTALL=${WINE_INSTALL:-$R/wine/wine11-arm64}
ACTION=${1:-construire}

[ -f "$SRC/build-arm64ec.txt" ] || { echo "ECHEC : $SRC/build-arm64ec.txt absent (etape1 --cloner ?)"; exit 1; }
[ -x "$MINGW/arm64ec-w64-mingw32-clang" ] || { echo "ECHEC : llvm-mingw absent de $MINGW"; exit 1; }
[ -d "$NATIVE_LLVM" ] || { echo "ECHEC : LLVM natif absent ($NATIVE_LLVM)"; exit 1; }
[ -d "$WINE_INSTALL/lib/wine" ] || { echo "ECHEC : Wine absent ($WINE_INSTALL)"; exit 1; }

echo "== objets TLS sans x18 (lien arm64ec) =="
CXA="$R/outils/cxa_globals_sans_x18_arm64ec.o"
[ -f "$CXA" ] || "$MINGW/arm64ec-w64-mingw32-clang" -c "$R/outils/cxa_globals_sans_x18.c" -o "$CXA"
EMU="$R/outils/emutls_sans_x18_arm64ec.o"
[ -f "$EMU" ] || "$MINGW/arm64ec-w64-mingw32-clang" -O2 -c "$R/outils/emutls_sans_x18.c" -o "$EMU"
ls -l "$CXA" "$EMU"

echo "== cross-file derive (build-arm64ec.txt + emulated-tls) =="
# Le cross-file amont ne porte que -marm64x ; on le derive plutot que de le
# patcher : les chemins des objets sont ceux de Cidre, pas ceux de DXMT.
mkdir -p "$R/build"
CROSS="$R/build/dxmt-cross-arm64ec-tls.txt"
sed -e "s|^c_args = \['-marm64x'\]|c_args = ['-marm64x', '-femulated-tls']|" \
    -e "s|^cpp_args = \['-marm64x'\]|cpp_args = ['-marm64x', '-femulated-tls']|" \
    -e "s|^c_link_args = \['-marm64x'\]|c_link_args = ['-marm64x', '$EMU', '$CXA']|" \
    -e "s|^cpp_link_args = \['-marm64x'\]|cpp_link_args = ['-marm64x', '$EMU', '$CXA']|" \
    "$SRC/build-arm64ec.txt" > "$CROSS.tmp"
for cle in "c_args = .*femulated-tls" "cpp_args = .*femulated-tls" "c_link_args = .*cxa_globals_sans_x18" "cpp_link_args = .*cxa_globals_sans_x18"; do
   grep -q "$cle" "$CROSS.tmp" || { echo "ECHEC : le cross-file amont a change de forme, derivation impossible ($cle)"; rm -f "$CROSS.tmp"; exit 1; }
done
if [ -f "$CROSS" ] && cmp -s "$CROSS" "$CROSS.tmp"; then rm -f "$CROSS.tmp"; else mv "$CROSS.tmp" "$CROSS"; fi
grep "args" "$CROSS"

echo "== DXMT -> $BLD =="
configurer() {
   meson setup "$BLD" "$SRC" --cross-file "$CROSS" --buildtype release \
      -Dnative_llvm_path="$NATIVE_LLVM" -Dwine_install_path="$WINE_INSTALL"
}
if [ ! -f "$BLD/build.ninja" ]; then
   configurer
elif ! grep -qF "cross_file = ['$CROSS']" "$BLD/meson-private/cmd_line.txt" 2>/dev/null; then
   # Build-dir configure avec un autre cross-file (celui d'amont, sans emulated-tls) :
   # meson ignore un --cross-file passe a --reconfigure, il faut repartir a neuf.
   echo "build-dir configure avec un autre cross-file : reconfiguration a neuf"
   rm -rf "$BLD"
   configurer
elif [ "$CROSS" -nt "$BLD/build.ninja" ]; then
   # drapeaux ou objets changes : meson ne relit le cross-file que sur demande
   meson setup --reconfigure "$BLD" "$SRC" --cross-file "$CROSS"
fi
meson compile -C "$BLD" -j "$J"

echo "== verification : aucune lecture TLS par x18 hors libc++abi natif =="
# Dans un binaire arm64x, __cxa_get_globals(_fast) de libc++abi existe en deux
# copies : arm64ec (remplacee par cxa_globals_sans_x18) et arm64 natif (celle que
# le lien n'atteint pas, et qu'un jeu x64 n'execute jamais). Seule cette copie
# native est toleree.
rc=0
for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll; do
   dll="$BLD/src/$f"
   [ -f "$dll" ] || { echo "ECHEC : $dll absent"; rc=1; continue; }
   sites=$("$MINGW/llvm-objdump" -d --no-show-raw-insn "$dll" \
      | awk '/^[0-9a-f]+ <.*>:$/ { fn=$2 } /\[x18, #(88|0x58)\]/ { print fn }' | sort | uniq -c)
   total=$(echo "$sites" | awk '{ s += $1 } END { print s + 0 }')
   autres=$(echo "$sites" | grep -v -e '<__cxa_get_globals>:' -e '<__cxa_get_globals_fast>:' | grep -c . || true)
   if [ "$autres" -gt 0 ]; then
      echo "ECHEC : $f lit le TLS par x18 hors libc++abi natif :"; echo "$sites" | sed 's/^/   /'; rc=1
   else
      if [ "$total" -eq 0 ]; then echo "  $f : aucune lecture TLS par x18"
      else echo "  $f : $total lecture(s) [x18,#0x58], toutes dans la copie arm64 native de libc++abi (inatteignable d'un jeu x64)"; fi
   fi
done
[ $rc -eq 0 ] || exit $rc

if [ "$ACTION" = "poser" ]; then
   echo "== pose dans $R/dxmt/ (precedent -> $R/dxmt.precedent/) =="
   if [ -d "$R/dxmt" ]; then
      rm -rf "$R/dxmt.precedent"
      mv "$R/dxmt" "$R/dxmt.precedent"
   fi
   mkdir -p "$R/dxmt"
   for f in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll winemetal/winemetal.dll winemetal/unix/winemetal.so; do
      cp "$BLD/src/$f" "$R/dxmt/"
   done
   for f in COPYING.LIB LICENSE README.md; do cp "$SRC/$f" "$R/dxmt/$f" 2>/dev/null || true; done
   ls -l "$R/dxmt"
   echo "Pose faite. Le lanceur (option d3d11 = dxmt) prend $R/dxmt/ au prochain lancement ;"
   echo "pour revenir en arriere : rm -rf $R/dxmt && mv $R/dxmt.precedent $R/dxmt"
else
   echo "Construit et verifie. Pour poser dans $R/dxmt/ : sh tests/construire_dxmt.sh poser"
fi
