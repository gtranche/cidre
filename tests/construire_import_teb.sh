#!/bin/sh
# Construit la bibliotheque d'importation qui donne acces a __wine_teb_tsd_key.
# Elle se passe en option d'edition de liens ; aucun fichier de FEX n'est modifie.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
T="$R/toolchain/llvm-mingw-20260908-ucrt-macos-universal/bin"
arch=${1:-arm64ec}
out="$R/outils/libntdll_teb_$arch.a"
"$T/$arch-w64-mingw32-dlltool" -d "$R/outils/ntdll_teb.def" -k -l "$out"
"$T/llvm-nm" --no-sort "$out" | grep -i teb | sort -u
echo "$out"
