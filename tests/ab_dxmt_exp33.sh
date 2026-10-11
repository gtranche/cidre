#!/bin/sh
# A/B DXMT (D3D11 -> Metal, 1 saut) contre DXVK (D3D11 -> Vulkan -> KosmicKrisp) sur
# Expedition 33 (1903340, x64, D3D11 FL11_1), pile arm64ec de Cidre.
#
# DXMT est bati dans src/dxmt/build contre NOTRE Wine 11.18 (meson, cross-file arm64ec,
# -Dwine_install_path=wine/wine11-arm64). Ses DLL sont des builtins Wine : posees dans
# lib/wine/aarch64-windows et chargees =b ; l'unixlib winemetal.so va dans aarch64-unix ;
# une copie de winemetal.dll en system32 du prefixe pour que le chargeur resolve l'import.
# NON DESTRUCTIF : les builtins Wine d'origine sont sauvegardes avant d'etre remplaces.
#
#   sh tests/ab_dxmt_exp33.sh dxmt [poser]   # pose DXMT, puis lance (sauf "poser")
#   sh tests/ab_dxmt_exp33.sh dxvk [poser]   # remet les builtins Wine + DXVK, puis lance
#   sh tests/ab_dxmt_exp33.sh restore        # remet l'etat d'origine sans lancer
#   sh tests/ab_dxmt_exp33.sh etat           # dit ce qui est pose
set -e
MODE=${1:?dxmt|dxvk|restore|etat}
R=$(cd "$(dirname "$0")" && cd .. && pwd)
B=$R/src/dxmt/build/src
WINDLL=$R/wine/wine11-arm64/lib/wine/aarch64-windows
UNIX=$R/wine/wine11-arm64/lib/wine/aarch64-unix
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
SYS32=$PFX/drive_c/windows/system32
SF="$HOME/Library/Application Support/Cidre/games/1903340/Sandfall/Binaries/Win64/SandFall-Win64-Shipping.exe"
BK=$R/wine/.wine-builtin-backup
LOGS=$R/build/logs/dxmt
DLLS="d3d11.dll dxgi.dll d3d10core.dll"

sauver_builtins() {
   mkdir -p "$BK"
   for d in $DLLS; do
      [ -f "$BK/$d" ] || cp -p "$WINDLL/$d" "$BK/$d"
   done
}
restaurer() {
   for d in $DLLS; do
      [ -f "$BK/$d" ] && cp -p "$BK/$d" "$WINDLL/$d"
   done
   rm -f "$WINDLL/winemetal.dll" "$UNIX/winemetal.so" "$SYS32/winemetal.dll"
   echo "[ab] builtins Wine d'origine remis, winemetal retire ; DXVK (system32) intact." >&2
}
etat() {
   if strings "$WINDLL/d3d11.dll" | grep -q 'dxmt' && [ -f "$UNIX/winemetal.so" ]; then
      echo "pose : DXMT"
   else
      echo "pose : builtins Wine (DXVK via system32)"
   fi
}
verifier_winemac() {
   nm "$UNIX/winemac.so" 2>/dev/null | grep -q ' D _macdrv_functions$' || {
      echo "[ab] macdrv_functions absent de winemac.so (patch 0100 pas installe). Abandon." >&2; exit 3; }
}

case "$MODE" in
   etat) etat; exit 0 ;;
   restore) restaurer; exit 0 ;;
   dxvk)
      restaurer
      unset CIDRE_DLL_OVERRIDES
      # le lanceur lit l'option d3d11 du profil : on lui dit le mode de CE run
      export CIDRE_D3D11=dxvk
      ;;
   dxmt)
      verifier_winemac
      for f in "$B/d3d11/d3d11.dll" "$B/dxgi/dxgi.dll" "$B/d3d10/d3d10core.dll" \
               "$B/winemetal/winemetal.dll" "$B/winemetal/unix/winemetal.so"; do
         [ -f "$f" ] || { echo "[ab] manque $f : meson compile -C src/dxmt/build" >&2; exit 1; }
      done
      sauver_builtins
      cp -p "$B/d3d11/d3d11.dll"          "$WINDLL/d3d11.dll"
      cp -p "$B/dxgi/dxgi.dll"            "$WINDLL/dxgi.dll"
      cp -p "$B/d3d10/d3d10core.dll"      "$WINDLL/d3d10core.dll"
      cp -p "$B/winemetal/winemetal.dll"  "$WINDLL/winemetal.dll"
      cp -p "$B/winemetal/unix/winemetal.so" "$UNIX/winemetal.so"
      cp -p "$B/winemetal/winemetal.dll"  "$SYS32/winemetal.dll"
      # =b gagne sur le dxgi,d3d11=n d'etape2 (ajoute apres, separe par ';')
      export CIDRE_DLL_OVERRIDES="dxgi,d3d11,d3d10core,winemetal=b"
      export CIDRE_D3D11=dxmt   # le lanceur sait maintenant poser DXMT lui-meme (option d3d11)
      export DXMT_LOG_LEVEL=info DXMT_LOG_PATH="$LOGS" MTL_HUD_ENABLED=1
      # L'overlay Steam (gameoverlayrenderer.dylib, injecte par DYLD_INSERT_LIBRARIES)
      # accroche presentDrawable: ; avec DXMT la premiere image s'affiche puis plus
      # rien n'avance (encodeur et finish DXMT a l'arret, GPU jamais termine).
      # Verifie le 2026-10-11 sur Expedition 33 : sans overlay, ca tourne.
      export CIDRE_OVERLAY=${CIDRE_OVERLAY:-0}
      mkdir -p "$LOGS"
      echo "[ab] DXMT pose (journal DXMT : $LOGS)" >&2
      ;;
   *) echo "mode inconnu : $MODE" >&2; exit 2 ;;
esac
[ "${2:-}" = poser ] && { etat; exit 0; }

[ -f "$SF" ] || { echo "[ab] jeu introuvable : $SF" >&2; exit 1; }
echo "[ab] mode=$MODE -> lancement de $(basename "$SF")" >&2
exec env SteamAppId=1903340 SteamGameId=1903340 SteamOverlayGameId=1903340 \
     sh "$R/tests/lancer_depuis_steam.sh" "$SF" Sandfall
