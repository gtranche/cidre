#!/bin/sh
# Applique les series de correctifs aux trois arbres amont.
#
#   mesa          -> KosmicKrisp : 29 correctifs (0001..0037, hors vkd3d et wine)
#   wine          -> ARM64/macOS, memoire externe, suites de tests
#                    (0028, 0035, 0036, 0038, 0040, 0041)
#   vkd3d-proton  -> 5 correctifs (0004, 0007, 0008, 0014, 0016)
#   dxvk          -> 3 correctifs (0039, 0042, 0043)
#
# Usage :
#   etape1_appliquer_correctifs.sh            verifie les arbres existants
#   etape1_appliquer_correctifs.sh --cloner   clone les trois arbres aux commits ci-dessous
#
# Enchainer ensuite sur etape2_construire_pile.sh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

MESA_URL=https://gitlab.freedesktop.org/mesa/mesa.git
MESA_REV=5f253b93041eb8d101e6ddef2613006bfde859cd
WINE_URL=https://gitlab.winehq.org/wine/wine.git
WINE_REV=b073859675060c9211fcbccfd90e4e87520dc2c2
VKD3D_URL=https://github.com/HansKristian-Work/vkd3d-proton.git
VKD3D_REV=5d0db7414b0b3f1afa7c9a84acf9ff483cb805d1
DXVK_URL=https://github.com/doitsujin/dxvk.git
DXVK_REV=c3dd74be6baec53786d4e064a572185b70347a17

cloner() {
   url=$1; rev=$2; dst=$3
   [ -d "$dst" ] && { echo "   $dst existe deja, ignore"; return 0; }
   echo "   clonage $dst"
   git clone -q --filter=blob:none "$url" "$dst"
   git -C "$dst" checkout -q "$rev"
   git -C "$dst" submodule update -q --init --recursive 2>/dev/null || true
}

if [ "${1:-}" = "--cloner" ]; then
   echo "== clonage des arbres amont =="
   mkdir -p "$R/src"
   cloner "$MESA_URL"  "$MESA_REV"  "$R/src/mesa"
   cloner "$WINE_URL"  "$WINE_REV"  "$R/src/wine"
   cloner "$VKD3D_URL" "$VKD3D_REV" "$R/src/vkd3d-proton"
   cloner "$DXVK_URL"  "$DXVK_REV"  "$R/src/dxvk"
fi

serie_mesa() {
   for f in "$R"/00[0-3][0-9]-kosmickrisp-*.patch; do
      case "$(basename "$f")" in 0000-*) continue;; esac
      echo "$f"
   done
}

appliquer() {
   arbre=$1; shift
   echo "== $arbre =="
   n=0
   for f in "$@"; do
      [ -f "$f" ] || { echo "   ABSENT : $f" >&2; exit 1; }
      if patch -d "$R/src/$arbre" -p1 --silent < "$f"; then
         n=$((n + 1))
      else
         echo "   ECHEC sur $(basename "$f")" >&2
         exit 1
      fi
   done
   echo "   $n correctifs appliques"
}

appliquer mesa $(serie_mesa)
appliquer wine "$R"/0028-*.patch "$R"/0035-*.patch "$R"/0036-*.patch \
               "$R"/0038-*.patch "$R"/0040-*.patch "$R"/0041-*.patch
appliquer vkd3d-proton "$R"/0004-*.patch "$R"/0007-*.patch "$R"/0008-*.patch \
                       "$R"/0014-*.patch "$R"/0016-*.patch
appliquer dxvk "$R"/0039-*.patch "$R"/0042-*.patch "$R"/0043-*.patch

echo
echo "Les trois arbres sont patches. Enchainer sur :"
echo "   $R/tests/etape2_construire_pile.sh"
