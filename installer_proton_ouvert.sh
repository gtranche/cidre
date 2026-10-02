#!/bin/sh
# Installe proton-ouvert (runtime deja compile) pour JOUER. Ne construit rien.
#
#   sh installer_proton_ouvert.sh [DESTINATION] [chemin/vers/runtime.tar.zst | URL]
#
# Par defaut : installe sous ~/Library/Application Support/proton-ouvert et va
# chercher le tarball de la derniere release si aucun n'est fourni.
set -e
DEST=${1:-$HOME/Library/Application Support/proton-ouvert}
SRC=${2:-}
REL_URL="https://github.com/@@OWNER@@/@@REPO@@/releases/latest/download/proton-ouvert-runtime.tar.zst"

command -v zstd >/dev/null || { echo "zstd requis (brew install zstd)" >&2; exit 1; }
mkdir -p "$DEST"

echo "== 1. Recuperation du runtime =="
TAR=""
if [ -n "$SRC" ] && [ -f "$SRC" ]; then TAR="$SRC"; echo "  tarball local : $SRC"
else
   URL=${SRC:-$REL_URL}; TAR="$DEST/.runtime.tar.zst"
   echo "  telechargement : $URL"; curl -fL --retry 3 -o "$TAR" "$URL"
fi

echo "== 2. Decompression dans $DEST =="
zstd -dc "$TAR" | ( cd "$DEST" && tar xf - )
R="$DEST/proton-ouvert"
[ -d "$R/wine/wine11-arm64" ] || { echo "runtime invalide (wine absent)" >&2; exit 1; }

echo "== 3. Relocalisation de l'ICD Vulkan =="
for j in "$R/prefix/share/vulkan/icd.d/"*.json; do
   [ -f "$j" ] && sed -i '' "s#@@PROTON_OUVERT@@#$R#g" "$j" && echo "  $(basename "$j") -> $R"
done

echo "== 4. Preparation du prefixe Wine (sans mono/gecko) =="
export WINEPREFIX="$R/wine/pfx-arm64ec"
export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=d;mshtml=d"
if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   "$R/wine/wine11-arm64/bin/wineboot" -u >/dev/null 2>&1 || true
fi

echo "== 5. DXVK (async) + FEX dans le prefixe =="
P="$WINEPREFIX/drive_c/windows/system32"
Pw="$WINEPREFIX/drive_c/windows/syswow64"
mkdir -p "$P" "$Pw"
for d in d3d11 dxgi d3d10core d3d9 d3d8; do
   [ -f "$R/dxvk/async/$d.dll" ] && cp "$R/dxvk/async/$d.dll" "$P/" 2>/dev/null || true
done
WINE_ARM64="$R/wine/wine11-arm64" WINEPREFIX="$WINEPREFIX" sh "$R/tests/installer_fex.sh" >/dev/null 2>&1 || true

echo "== 6. Integration Steam =="
if pgrep -f steam_osx >/dev/null 2>&1; then
   echo "  Steam tourne : fermez-le, puis lancez 'sh $R/tests/brancher_jeux_steam.sh --ecrire'."
else
   STEAM="$HOME/Library/Application Support/Steam" \
     sh "$R/tests/brancher_jeux_steam.sh" --ecrire 2>/dev/null || \
     echo "  (Steam non detecte -- lancez brancher_jeux_steam.sh --ecrire apres l'avoir installe/connecte.)"
fi

echo
echo "INSTALLE sous $R"
echo "Lancez un jeu Windows depuis Steam (bouton Jouer). Les scripts attendent la"
echo "pile a cet emplacement ; ne le deplacez pas sans relancer l'etape 3."
