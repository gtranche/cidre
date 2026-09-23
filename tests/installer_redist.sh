#!/bin/sh
# Installe dans le prefixe les redistribuables DirectX qu'un jeu embarque.
#
#   installer_redist.sh <dossier du jeu>
#
# Beaucoup de jeux DirectX 9 livrent leur propre copie de d3dx9 et de
# d3dcompiler sous __redist/DirectX. Les versions de Wine sont incompletes :
# son compilateur HLSL refuse les shaders de Braid, par exemple. On extrait
# donc les .cab 32 bits et on installe les DLL de Microsoft dans syswow64.
#
# Les overrides correspondants sont poses par etape2_pile_wow64.sh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

[ $# -ge 1 ] || { echo "usage : $(basename "$0") <dossier du jeu>" >&2; exit 2; }
jeu=$1
[ -d "$jeu" ] || { echo "introuvable : $jeu" >&2; exit 2; }

redist=$(find "$jeu" -maxdepth 3 -type d -iname DirectX 2>/dev/null | head -1)
[ -n "$redist" ] || { echo "pas de __redist/DirectX dans $jeu, rien a faire"; exit 0; }

pfx=${WINEPREFIX:-$R/wine/pfx-wow64}
dst="$pfx/drive_c/windows/syswow64"
[ -d "$dst" ] || { echo "pas de syswow64 dans $pfx" >&2; exit 1; }

sept=$(command -v 7z || echo /opt/homebrew/bin/7z)
[ -x "$sept" ] || { echo "7z introuvable, impossible d'ouvrir les .cab" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=0
for cab in "$redist"/*_x86.cab; do
   [ -f "$cab" ] || continue
   case "$(basename "$cab")" in
      *d3dx9_*|*D3DCompiler_*) ;;
      *) continue;;
   esac
   rm -rf "$tmp/x"; mkdir -p "$tmp/x"
   "$sept" x -o"$tmp/x" "$cab" >/dev/null 2>&1 || continue
   for dll in "$tmp/x"/*.dll; do
      [ -f "$dll" ] || continue
      base=$(basename "$dll" | tr 'A-Z' 'a-z')
      cp "$dll" "$dst/$base"
      echo "   $base"
      n=$((n + 1))
   done
done
echo "$n DLL Microsoft installees dans syswow64"
