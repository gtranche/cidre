#!/bin/sh
# Empaquette le RUNTIME (binaires deja construits) en un tarball a livrer en
# release GitHub. Ne contient PAS les sources, le build, la toolchain, ni le
# prefixe (regenere a l'install). Verger (ou installer_cidre.sh) le decompresse
# puis lance `cidre setup`, qui relocalise l'ICD et regenere le prefixe.
#   CIDRE_VERSION=1.1.0 sh tests/empaqueter_runtime.sh [sortie.tar.zst]
# Sort deux archives du meme contenu : .tar.zst (installer_cidre.sh) et .tar.xz
# (Verger : macOS sait decompresser xz sans rien installer, pas zstd).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$R/cidre-runtime.tar.zst}
# La version que `cidre status` annonce et que Verger compare a la derniere
# release : celle du tag qu'on s'apprete a publier, sans le « v ».
: "${CIDRE_VERSION:?donne la version a publier, ex. CIDRE_VERSION=1.1.0}"
STAGE=$(mktemp -d)/cidre
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
   [ -f "$j" ] && sed -i '' "s#$R#@@CIDRE@@#g" "$j"
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
   "$R/tests/"preparer_pont_steam_arm64.sh "$R/tests/"sync_saves_steam.sh \
   "$R/tests/"installer_fex.sh "$R/tests/"profil_cidre.sh \
   "$R/tests/"cidre_install.sh "$R/tests/"bibliotheque_steam.py \
   "$R/tests/"configurer_cidre.sh "$STAGE/tests/" 2>/dev/null || true
# La CLI `cidre` : le contrat que pilote Verger (list/info --json, play, dl, sync).
cp "$R/cidre" "$STAGE/" 2>/dev/null || true
cp -R "$R/tests/outils_fenetre" "$STAGE/tests/" 2>/dev/null || true
mkdir -p "$STAGE/outil-steam" "$STAGE/build"
# jeux.conf est lu par lancer_depuis_steam.sh en $R/outil-steam/jeux.conf :
# le livrer a CE chemin, pas a la racine (sinon la table de lanceurs est muette).
cp "$R/outil-steam/jeux.conf" "$STAGE/outil-steam/" 2>/dev/null || true
cp "$R/outil-steam/saves.conf" "$STAGE/outil-steam/" 2>/dev/null || true
cp "$R/outil-steam/profils.toml" "$STAGE/outil-steam/" 2>/dev/null || true
# Le faux client Steam (occupe ActiveProcess\\pid pour que SteamAPI_Init ne
# patiente pas apres un client Windows absent). preparer_pont_steam_arm64.sh le
# lit en $R/build/faux_steam.exe et le depose dans le prefixe.
cp "$R/build/faux_steam.exe" "$STAGE/build/" 2>/dev/null || true

echo "$CIDRE_VERSION" >"$STAGE/VERSION"

echo "== compression (zstd) =="
( cd "$(dirname "$STAGE")" && tar cf - cidre ) | zstd -15 -T${CIDRE_FILS:-0} -o "$OUT" -f
echo "== compression (xz) =="
OUT_XZ="${OUT%.zst}"; OUT_XZ="${OUT_XZ%.xz}.xz"
( cd "$(dirname "$STAGE")" && /usr/bin/tar -c --xz --options "xz:compression-level=6,xz:threads=${CIDRE_FILS:-0}" -f "$OUT_XZ" cidre )
rm -rf "$(dirname "$STAGE")"
echo
echo "RUNTIME empaquete (version $CIDRE_VERSION) :"
ls -lh "$OUT" "$OUT_XZ" | awk '{print "  "$5"  "$9}'
