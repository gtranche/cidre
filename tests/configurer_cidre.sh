#!/bin/sh
# Configure un runtime Cidre deja decompresse a cet emplacement : c'est ce que
# lance `cidre setup`, apres une installation ou une mise a jour (par Verger,
# ou par installer_cidre.sh). Ne telecharge pas le runtime, ne construit rien.
# Rejouable : chaque etape ne refait que ce qui manque.
#
# Chaque etape s'annonce par une ligne `== k/6 titre ==`, que Verger affiche.
#
#   CIDRE_SANS_STEAM=1 : ne touche pas au client Steam (pas de wrapper pose).
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$R/wine/wine11-arm64" ] || { echo "runtime invalide : $R/wine/wine11-arm64 absent" >&2; exit 1; }

echo "== 1/6 Pilote Vulkan =="
# L'ICD livre porte un chemin a relocaliser vers l'emplacement d'installation.
for j in "$R/prefix/share/vulkan/icd.d/"*.json; do
   [ -f "$j" ] && sed -i '' "s#@@CIDRE@@#$R#g" "$j" && echo "  $(basename "$j") -> $R"
done

echo "== 2/6 Prefixe Wine =="
# Sans mono ni gecko. Un prefixe existant (et ses sauvegardes) est garde.
export WINEPREFIX="$R/wine/pfx-arm64ec"
export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=d;mshtml=d"
if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   "$R/wine/wine11-arm64/bin/wineboot" -u >/dev/null 2>&1 || true
fi

echo "== 3/6 DXVK et FEX =="
P="$WINEPREFIX/drive_c/windows/system32"
Pw="$WINEPREFIX/drive_c/windows/syswow64"
mkdir -p "$P" "$Pw"
for d in d3d11 dxgi d3d10core d3d9 d3d8; do
   [ -f "$R/dxvk/async/$d.dll" ] && cp "$R/dxvk/async/$d.dll" "$P/" 2>/dev/null || true
done
WINE_ARM64="$R/wine/wine11-arm64" WINEPREFIX="$WINEPREFIX" sh "$R/tests/installer_fex.sh" >/dev/null 2>&1 || true

echo "== 4/6 Pont Steam =="
# Sans ce pont, le steam_api64.dll du jeu ne trouve pas de client (registre
# ActiveProcess vide) et SteamAPI_Init echoue -- le jeu « se lance et se ferme ».
if WINE="$R/wine/wine11-arm64/bin/wine" WINEPREFIX="$WINEPREFIX" \
     B="$R/wine/wine11-arm64/lib/wine" sh "$R/tests/preparer_pont_steam_arm64.sh" >/dev/null 2>&1; then
   echo "  pont installe (lsteamclient en system32, faux_steam.exe, cles de registre)"
else
   echo "  pont : echec -- un jeu Steam risque de se fermer au lancement"
fi

echo "== 5/6 SteamCMD =="
# Pour telecharger les jeux (`cidre dl`) et lire la bibliotheque du compte.
# Les paquets a jour de Valve, pas son archive de 2020 : elle ne contient qu'un
# binaire Intel, qui ne demarre pas sur un Mac Apple Silicon sans Rosetta.
SCMD_DIR="$R/tools/steamcmd"
# Un SteamCMD deja la mais incapable de tourner ici (l'ancienne archive, jamais
# mise a jour faute de Rosetta) est a refaire.
if [ -x "$SCMD_DIR/steamcmd.sh" ] && { [ "$(uname -m)" != arm64 ] || file "$SCMD_DIR/steamcmd" 2>/dev/null | grep -q arm64; }; then
   echo "  deja la"
elif sh "$R/tests/installer_steamcmd.sh" "$SCMD_DIR"; then
   :
else
   # Dit a Verger (et a `cidre status`) que l'installation est incomplete.
   echo "  SteamCMD n'a pas pu etre installe -- relancer \`cidre setup\` une fois en ligne"
   SETUP_INCOMPLET=1
fi

echo "== 6/6 Integration Steam =="
if [ -n "${CIDRE_SANS_STEAM:-}" ]; then
   echo "  ignoree (CIDRE_SANS_STEAM)"
elif pgrep -f steam_osx >/dev/null 2>&1; then
   echo "  Steam tourne : ferme-le puis relance \`cidre wrap\` pour poser le wrapper sur tes jeux Windows."
else
   STEAM="$HOME/Library/Application Support/Steam" \
     sh "$R/tests/brancher_jeux_steam.sh" --ecrire 2>/dev/null || \
     echo "  Steam non detecte -- lance \`cidre wrap\` apres l'avoir installe et connecte."
fi

if [ -n "${SETUP_INCOMPLET:-}" ]; then
   echo "Cidre est installe, mais incomplet : $R"
   exit 4
fi
echo "Cidre est pret : $R"
