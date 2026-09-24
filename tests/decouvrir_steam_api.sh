#!/bin/sh
# Faire dire a un jeu de quelles methodes Steamworks il a besoin.
#
#   decouvrir_steam_api.sh <appid> <chemin\vers\jeu.exe>
#
# La table de decouverte journalise chaque emplacement appele et rend zero sans
# jamais relayer : le jeu ne tournera pas, c'est voulu. Rien d'inconnu n'est
# appele cote client natif, donc la session Steam de l'utilisateur ne risque
# rien. Ce premier passage sert uniquement a relever l'ordre exact des
# emplacements et les chaines de version demandees.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-wow64}
WINE=$R/wine/wine10-wow64/bin/wine
# /usr/local/bin porte FreeType : sans lui le journal se noie dans les avertissements
PATH=/usr/local/bin:$PATH; export PATH
APPID=$1
EXE=$2
[ -n "$APPID" ] && [ -n "$EXE" ] || { sed -n '2,12p' "$0"; exit 2; }

JOURNAL=${JOURNAL:-/tmp/decouverte-$APPID.txt}
echo "appid $APPID, journal $JOURNAL"

WINEPREFIX="$PFX" \
SteamAppId=$APPID SteamGameId=$APPID SteamOverlayGameId=$APPID \
WINEDEBUG=-all,err+lsteamclient \
"$WINE" "$EXE" > "$JOURNAL" 2>&1 || true

echo "--- emplacements appeles, dans l'ordre ---"
grep -oE "(ISteamClient|[A-Za-z0-9_]+) emplacement [0-9]+\(.*" "$JOURNAL" | cat -n | head -80
echo "--- resume par interface ---"
grep -oE "^.*emplacement [0-9]+" "$JOURNAL" | sed 's/.*err:lsteamclient:repartir //' | sort -u
