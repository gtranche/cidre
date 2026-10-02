#!/bin/sh
# Recupere la toolchain de cross-compilation : llvm-mingw (le coeur -- fournit
# aarch64/arm64ec/i386-w64-mingw32 + la cible msvc x86_64). Idempotent : ne
# retelecharge pas si l'archive est deja la et verifiee, ne reextrait pas si
# deja extraite. Verifie le sha256 avant d'extraire.
#
#   sh tests/etape0_toolchain.sh
#
# Le patch TEB/x18 de winnt.h est applique separement par etape1 (il depend de
# la toolchain extraite ici).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
TC="$R/toolchain"
VER=20260908
NAME="llvm-mingw-${VER}-ucrt-macos-universal"
TARBALL="${NAME}.tar.xz"
URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${VER}/${TARBALL}"
SHA="d1dc5d1ecf3a3ced5ed5544c72f1acd0c8e84eb3024d520ecc6b143eec62a149"

mkdir -p "$TC/dl"
if [ -x "$TC/$NAME/bin/arm64ec-w64-mingw32-clang" ]; then
   echo "llvm-mingw deja extrait ($NAME)"
else
   DL="$TC/dl/$TARBALL"
   if [ -f "$DL" ] && shasum -a 256 "$DL" | grep -q "$SHA"; then
      echo "archive deja telechargee et verifiee"
   else
      echo "telechargement : $URL"
      curl -fL --retry 3 -o "$DL.partiel" "$URL"
      mv "$DL.partiel" "$DL"
      shasum -a 256 "$DL" | grep -q "$SHA" || { echo "ERREUR sha256 : archive corrompue, supprimee" >&2; rm -f "$DL"; exit 1; }
      echo "sha256 verifie"
   fi
   echo "extraction dans $TC/"
   tar -xJf "$DL" -C "$TC"
fi
ln -sfn "$NAME" "$TC/llvm-mingw"
echo "llvm-mingw : $("$TC/llvm-mingw/bin/arm64ec-w64-mingw32-clang" --version | head -1)"
echo "OK. (dxc, innoextract, le venv Python meson/ninja : voir INSTALL.md, pas encore scriptes.)"
