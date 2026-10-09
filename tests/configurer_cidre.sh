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
WB="$R/wine/wine11-arm64/bin/wineboot"; WS="$R/wine/wine11-arm64/bin/wineserver"
# La partie 32 bits manque-t-elle ? Un prefixe cree par les runtimes 1.4.4 a
# 1.4.7 -- ou aucun programme 32 bits ne demarrait -- est reste avec un
# syswow64 vide et sans la vue 32 bits du registre. Wine ne le rattrape pas
# seul : sans ces fichiers, le programme 32 bits qui devrait les poser ne
# demarre pas (« could not load kernel32.dll »). Consequences : aucun jeu 32
# bits, et les lanceurs Unreal qui ne trouvent pas le runtime Visual C++ au
# registre 32 bits proposent de l'installer, puis echouent (« descripteur
# invalide »).
sans_32_bits() {
   [ -d "$R/wine/wine11-arm64/lib/wine/i386-windows" ] && [ ! -f "$WINEPREFIX/drive_c/windows/syswow64/ntdll.dll" ]
}
if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   "$WB" -u >/dev/null 2>&1 || true
elif sans_32_bits; then
   # Reparation qui ne touche a rien d'autre : Wine cree un prefixe neuf a
   # cote, on en greffe les seuls fichiers systeme 32 bits absents, puis Wine
   # complete le registre du vrai prefixe. Les jeux, sauvegardes et reglages
   # qu'il contient restent en place.
   echo "  prefixe sans partie 32 bits : reparation (une minute), le reste n'est pas touche"
   "$WS" -k 2>/dev/null; "$WS" -w 2>/dev/null
   NEUF=$(mktemp -d "$R/wine/.pfx-neuf.XXXXXX") && {
      WINEPREFIX="$NEUF" "$WB" -u >/dev/null 2>&1 || true
      WINEPREFIX="$NEUF" "$WS" -w 2>/dev/null
      if [ -f "$NEUF/drive_c/windows/syswow64/ntdll.dll" ]; then
         ( cd "$NEUF/drive_c/windows/syswow64" &&
           find . -type d | while IFS= read -r d; do mkdir -p "$WINEPREFIX/drive_c/windows/syswow64/$d"; done &&
           find . -type f | while IFS= read -r f; do
              [ -e "$WINEPREFIX/drive_c/windows/syswow64/$f" ] || cp "$f" "$WINEPREFIX/drive_c/windows/syswow64/$f"
           done )
         "$WB" -u >/dev/null 2>&1 || true
         "$WS" -w 2>/dev/null
      fi
      rm -rf "$NEUF"
   }
   if sans_32_bits; then echo "  reparation impossible : les jeux 32 bits ne demarreront pas"
   else echo "  partie 32 bits en place ($(ls "$WINEPREFIX/drive_c/windows/syswow64" | wc -l | tr -d ' ') fichiers)"; fi
fi

# Le runtime Visual C++, declare au registre dans ses deux vues. Wine fournit
# ces bibliotheques (msvcp140, vcruntime140...) et les declare lui-meme, mais la
# vue 32 bits -- celle que lisent les installeurs et les lanceurs Unreal -- est
# ecrite par un programme 32 bits : la ou il n'a pas pu tourner, le lanceur du
# jeu croit le runtime absent, propose de l'installer, et son installeur
# echoue. On l'ecrit donc d'ici, depuis le cote 64 bits. La version est celle
# du redistribuable courant de Microsoft : seuls des controles de version la
# lisent.
VC="$WINEPREFIX/drive_c/cidre-vcruntime.reg"
{
   echo 'Windows Registry Editor Version 5.00'
   for vue in 'SOFTWARE\Microsoft' 'SOFTWARE\Wow6432Node\Microsoft'; do
      for arch in x64 x86 arm64; do
         printf '\n[HKEY_LOCAL_MACHINE\\%s\\VisualStudio\\14.0\\VC\\Runtimes\\%s]\n' "$vue" "$arch"
         echo '"Installed"=dword:00000001'
         echo '"Major"=dword:0000000e'
         echo '"Minor"=dword:0000002c'
         echo '"Bld"=dword:0000898b'
         echo '"Rbld"=dword:00000000'
         echo '"Version"="v14.44.35211.00"'
      done
   done
} >"$VC"
"$R/wine/wine11-arm64/bin/wine" reg import 'C:\cidre-vcruntime.reg' >/dev/null 2>&1 &&
   echo "  runtime Visual C++ declare au registre (14.44, vues 64 et 32 bits)"
rm -f "$VC"

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
# Les DLL du client Steam de Windows, que les jeux proteges par le DRM de Steam
# exigent. Leur absence n'empeche pas les autres jeux : on continue.
sh "$R/tests/installer_client_steam_windows.sh" "$WINEPREFIX" ||
   echo "  DLL du client Steam absentes -- les jeux proteges par le DRM de Steam ne demarreront pas ; relancer \`cidre setup\` une fois en ligne"
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
