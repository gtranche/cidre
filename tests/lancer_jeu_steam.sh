#!/bin/sh
# Lancer un jeu Steam Windows sur le client Steam macOS natif.
#
#   lancer_jeu_steam.sh <appid> <chemin/vers/jeu.exe> [secondes]
#
# Deux choses avant le jeu : le pont doit etre installe et designe par le
# registre (preparer_pont_steam.sh), et un processus doit occuper
# ActiveProcess\pid, sans quoi SteamAPI_Init attend Steam indefiniment. Le
# client qui repond reellement est celui de macOS, derriere l'unixlib.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-wow64}
WINE=$R/wine/wine10-wow64/bin/wine
PATH=/usr/local/bin:$PATH; export PATH
APPID=$1; EXE=$2; DUREE=${3:-90}
[ -n "$APPID" ] && [ -n "$EXE" ] || { sed -n '2,10p' "$0"; exit 2; }
JOURNAL=${JOURNAL:-/tmp/jeu-$APPID.txt}

WINEPREFIX="$PFX" WINEDEBUG=-all "$WINE" c:\\faux_steam.exe >/dev/null 2>&1 &
sleep 5
echo "faux client en place, journal $JOURNAL"

: > "$JOURNAL"
WINEPREFIX="$PFX" SteamAppId=$APPID SteamGameId=$APPID SteamOverlayGameId=$APPID \
  WINEDEBUG=-all,err+lsteamclient "$WINE" "$EXE" >> "$JOURNAL" 2>&1 &

i=0
while [ $i -lt "$DUREE" ]; do
   pgrep -f "$(basename "$EXE")" >/dev/null 2>&1 || break
   sleep 3; i=$((i + 3))
done
pkill -f "$(basename "$EXE")" 2>/dev/null || true
pkill -f faux_steam 2>/dev/null || true
echo "--- arrete apres ${i}s ---"
