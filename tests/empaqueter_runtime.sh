#!/bin/sh
# Empaquette le RUNTIME (binaires deja construits) en un tarball a livrer en
# release GitHub. Ne contient PAS les sources, le build, la toolchain, ni le
# prefixe (regenere a l'install). L'installeur (installer_proton_ouvert.sh) le
# decompresse, relocalise l'ICD et regenere le prefixe.
#   sh tests/empaqueter_runtime.sh [sortie.tar.zst]
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$R/proton-ouvert-runtime.tar.zst}
STAGE=$(mktemp -d)/proton-ouvert
mkdir -p "$STAGE"

echo "== Wine 11 arm64 (elague : sans include/doc/man) =="
mkdir -p "$STAGE/wine/wine11-arm64"
( cd "$R/wine/wine11-arm64" && tar cf - \
    --exclude='include' --exclude='share/man' --exclude='share/doc' \
    bin lib share ) | ( cd "$STAGE/wine/wine11-arm64" && tar xf - )

echo "== KosmicKrisp + loader Vulkan (prefix/) =="
mkdir -p "$STAGE/prefix"
( cd "$R/prefix" && tar cf - lib share bin 2>/dev/null ) | ( cd "$STAGE/prefix" && tar xf - )
# L'ICD json : chemin a reecrire a l'install -> on le neutralise avec un jeton.
for j in "$STAGE/prefix/share/vulkan/icd.d/"*.json; do
   [ -f "$j" ] && sed -i '' "s#$R#@@PROTON_OUVERT@@#g" "$j"
done

echo "== DXVK arm64ec (stock + async gplasync) =="
mkdir -p "$STAGE/dxvk/stock" "$STAGE/dxvk/async"
for d in d3d11 dxgi d3d10core d3d9 d3d8; do
   cp "$R/build/dxvk-winarm64ec/src/$d/$d.dll" "$STAGE/dxvk/stock/" 2>/dev/null || true
   cp "$R/build/dxvk-async-winarm64ec/src/$d/$d.dll" "$STAGE/dxvk/async/" 2>/dev/null || true
done

echo "== scripts de lancement + integration Steam =="
mkdir -p "$STAGE/tests"
cp "$R/tests/"etape2_pile_arm64ec.sh "$R/tests/"lancer_depuis_steam.sh \
   "$R/tests/"brancher_jeux_steam.sh "$R/tests/"installer_agent_steam.sh \
   "$R/tests/"installer_fex.sh "$STAGE/tests/" 2>/dev/null || true
cp -R "$R/tests/outils_fenetre" "$STAGE/tests/" 2>/dev/null || true
cp "$R/outil-steam/jeux.conf" "$STAGE/" 2>/dev/null || true

echo "== compression (zstd) =="
( cd "$(dirname "$STAGE")" && tar cf - proton-ouvert ) | zstd -15 -T0 -o "$OUT" -f
rm -rf "$(dirname "$STAGE")"
echo
echo "RUNTIME empaquete : $OUT"
ls -lh "$OUT" | awk '{print "  taille : "$5}'
