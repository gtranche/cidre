#!/bin/sh
# cidre install <appid> [auto|macos|windows]
# Installe le BON depot d'un jeu dans la bibliotheque Steam, SANS la console Steam,
# via SteamCMD. Les jeux restent vus par Steam (amis/succes/overlay). Pour les jeux
# Windows, cable ensuite le wrapper Cidre. Login SteamCMD = direct a SteamCMD, jamais
# vu par Cidre.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
STEAM="$HOME/Library/Application Support/Steam"
SAPPS="$STEAM/steamapps"
SCMD_DIR="$R/tools/steamcmd"
SCMD="$SCMD_DIR/steamcmd.sh"

APPID=${1:-}; PLAT=${2:-auto}
[ -n "$APPID" ] || { echo "usage: cidre install <appid> [auto|macos|windows]"; exit 2; }

# 1) SteamCMD present ? sinon on telecharge le tarball officiel (pas le cask brew,
#    qui a des soucis Gatekeeper).
if [ ! -x "$SCMD" ]; then
   echo "== installation de SteamCMD (tarball officiel) =="
   mkdir -p "$SCMD_DIR"
   curl -fsSL -o "$SCMD_DIR/steamcmd_osx.tar.gz" \
      "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" || {
      echo "echec telechargement steamcmd" >&2; exit 1; }
   ( cd "$SCMD_DIR" && tar xzf steamcmd_osx.tar.gz )
   xattr -cr "$SCMD_DIR" 2>/dev/null || true
fi

# 2) plateforme : auto -> macos si version Apple Silicon dispo, sinon windows.
if [ "$PLAT" = auto ]; then
   if strings "$STEAM/appcache/appinfo.vdf" 2>/dev/null | grep -q "macosapplesilicon" \
      && grep -aqs "$APPID" "$STEAM/appcache/appinfo.vdf" ; then PLAT=macos; else PLAT=windows; fi
   # garde-fou : la detection appinfo est approximative -> on confirmera a l'ecran
fi
case "$PLAT" in macos|windows) ;; *) echo "plateforme invalide: $PLAT" >&2; exit 2;; esac

NOM=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$SAPPS/appmanifest_$APPID.acf" 2>/dev/null | head -1)
INSTALLDIR=$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$SAPPS/appmanifest_$APPID.acf" 2>/dev/null | head -1)
[ -n "$INSTALLDIR" ] || INSTALLDIR="app_$APPID"

echo "== $NOM ($APPID) -> installation en version $PLAT =="
echo "   (SteamCMD va demander ta connexion Steam ; Cidre ne voit jamais ton mot de passe)"

# 3) Steam doit etre ferme (SteamCMD et le client partagent la config).
if pgrep -f steam_osx >/dev/null 2>&1; then
   echo "== fermeture de Steam (necessaire pendant l'install) =="
   osascript -e 'tell application "Steam" to quit' 2>/dev/null; sleep 4
   pgrep -f steam_osx >/dev/null 2>&1 && { echo "ferme Steam puis relance la commande" >&2; exit 1; }
fi

DEST="$SAPPS/common/$INSTALLDIR"
echo "== SteamCMD : telechargement du depot $PLAT vers $DEST =="
"$SCMD" +force_install_dir "$DEST" +login +@sSteamCmdForcePlatformType "$PLAT" \
   +app_update "$APPID" validate +quit
RC=$?
[ $RC -eq 0 ] || { echo "SteamCMD a echoue (code $RC)" >&2; exit $RC; }

# 4) relocaliser l'appmanifest vers la bibliotheque Steam pour que le client le voie.
GEN="$DEST/steamapps/appmanifest_$APPID.acf"
if [ -f "$GEN" ]; then
   cp -f "$GEN" "$SAPPS/appmanifest_$APPID.acf"
   echo "== appmanifest installe dans la bibliotheque Steam =="
fi

# 5) routage Cidre : brancher re-detecte natif vs windows et pose/retire le wrapper.
echo "== cablage (wrapper Cidre si Windows, retire si natif) =="
sh "$R/tests/brancher_jeux_steam.sh" --ecrire 2>/dev/null || true

echo
echo "FINI. $NOM est installe en $PLAT. Relance Steam et clique Jouer (ou: cidre play $APPID)."
[ "$PLAT" = windows ] && echo "Pense a ajouter son dossier de save dans outil-steam/saves.conf si besoin (ou je le fais)."
