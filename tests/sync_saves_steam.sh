#!/bin/sh
# Sauvegarde/restauration des saves des jeux Windows lances par Cidre, vers un
# dossier synchronise (iCloud par defaut : CIDRE_SAVES_DIR). Steam Cloud ne peut
# pas resoudre les roots Windows sur macOS, donc on replique sa logique. Mode
# DOSSIER : on sauve tout le dossier du jeu sauf le superflu. JAMAIS destructif :
# copie horodatee en .history/ avant toute ecriture. Non bloquant.
#   sync_saves_steam.sh <appid> <restore|backup>
set -u
APPID=${1:-}; SENS=${2:-}
[ -n "$APPID" ] && [ -n "$SENS" ] || exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
DEST=${CIDRE_SAVES_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/CidreSaves}
CONF="$R/outil-steam/saves.conf"
[ -f "$CONF" ] || exit 0
JUNK='/cache/|/logs/|/crash|dumps/|image_cache/|/shader|PopsFeed|PopsMods|EarlyCrashReports|/Temp/|\.log$'
MAXSZ=104857600   # 100 Mo : au-dela ce n'est pas une sauvegarde

UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1); [ -n "$UH" ] || exit 0
UH=$(dirname "$UH")
reldir=$(awk -F'\t' -v a="$APPID" '$1==a {print $2; exit}' "$CONF")
[ -n "$reldir" ] || exit 0
SRC="$UH/$reldir"
BAK="$DEST/$APPID"

# liste des fichiers "save" sous un dossier (exclut le superflu et les gros)
lister() { # <racine>
   find "$1" -type f 2>/dev/null | grep -avE "$JUNK" | while IFS= read -r f; do
      sz=$(wc -c <"$f" 2>/dev/null || echo 0)
      [ "$sz" -le "$MAXSZ" ] && printf '%s\n' "$f"
   done
}
copie() { # <src> <dst> : archive l'ancien dst s'il differe, puis copie
   [ -f "$1" ] || return 0
   if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
      h="$3/$(dirname "${2#$4/}")"; mkdir -p "$h" 2>/dev/null && cp -p "$2" "$h/" 2>/dev/null
   fi
   mkdir -p "$(dirname "$2")" 2>/dev/null && cp -p "$1" "$2" 2>/dev/null
}

TS=$(date '+%Y%m%d-%H%M%S')
case "$SENS" in
   backup)
      [ -d "$SRC" ] || exit 0
      lister "$SRC" | while IFS= read -r f; do
         copie "$f" "$BAK/${f#$SRC/}" "$BAK/.history/cloud-$TS" "$BAK"
      done
      echo "    saves: backup $APPID -> iCloud" ;;
   restore)
      [ -d "$BAK" ] || exit 0
      find "$BAK" -type f 2>/dev/null | grep -av "/.history/" | while IFS= read -r dst; do
         rel=${dst#$BAK/}; loc="$SRC/$rel"
         if [ ! -f "$loc" ] || [ "$dst" -nt "$loc" ]; then
            copie "$dst" "$loc" "$BAK/.history/local-$TS" "$SRC"
            echo "    saves: restore $rel"
         fi
      done ;;
esac
exit 0
