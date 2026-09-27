#!/bin/sh
# Lancer un jeu Steam Windows x86_64 sur la pile arm64.
#
#   lancer_jeu_steam_arm64.sh <appid> <chemin/vers/jeu.exe>
#
# Deux prealables, sans quoi SteamAPI_Init echoue et le jeu se ferme au bout
# de quelques minutes sans rien dire : le pont doit etre designe par le
# registre (preparer_pont_steam_arm64.sh) et un processus doit occuper
# ActiveProcess\pid. Le client qui repond est celui de macOS, en natif arm64.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
APPID=$1; EXE=$2
[ -n "$APPID" ] && [ -n "$EXE" ] || { sed -n '2,6p' "$0"; exit 2; }
: "${WINEPREFIX:?WINEPREFIX requis}"

pgrep -f faux_steam >/dev/null 2>&1 || {
   WINEDEBUG=-all "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >/dev/null 2>&1 &
   sleep 30
}
cd "$(dirname "$EXE")"
SteamAppId=$APPID SteamGameId=$APPID SteamOverlayGameId=$APPID \
   exec "$R/tests/etape2_pile_arm64ec.sh" "$(basename "$EXE")"
