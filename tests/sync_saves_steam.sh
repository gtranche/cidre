#!/bin/sh
# Sauvegarde/restauration des saves des jeux Windows lances par Cidre, vers un
# dossier synchronise par l'utilisateur (iCloud par defaut). Steam Cloud ne peut
# pas resoudre les roots Windows sur macOS, donc on replique sa logique. JAMAIS
# destructif : toute ecriture ecrase est precedee d'une copie horodatee en
# historique. Non bloquant : toute erreur laisse le jeu continuer.
#   sync_saves_steam.sh <appid> <restore|backup>
set -u
APPID=${1:-}; SENS=${2:-}
[ -n "$APPID" ] && [ -n "$SENS" ] || exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
DEST=${CIDRE_SAVES_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/CidreSaves}
CONF="$R/outil-steam/saves.conf"
[ -f "$CONF" ] || exit 0

UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
[ -n "$UH" ] || exit 0
UH=$(dirname "$UH")

ligne=$(awk -F'\t' -v a="$APPID" '$1==a {print $2"\t"$3; exit}' "$CONF")
[ -n "$ligne" ] || exit 0
reldir=$(printf '%s' "$ligne" | cut -f1)
fichiers=$(printf '%s' "$ligne" | cut -f2 | tr '|' ' ')

SRC="$UH/$reldir"
BAK="$DEST/$APPID"
HIST="$BAK/.history/$(date '+%Y%m%d-%H%M%S')"

snap() { # snap <fichier> <dossier-historique>  (copie de securite avant ecrasement)
   [ -f "$1" ] || return 0
   mkdir -p "$2" 2>/dev/null || return 0
   cp -p "$1" "$2/" 2>/dev/null || true
}

case "$SENS" in
   backup)
      mkdir -p "$BAK" 2>/dev/null || exit 0
      for f in $fichiers; do
         for src in "$SRC"/$f; do
            [ -f "$src" ] || continue
            dst="$BAK/$(basename "$src")"
            # si la copie cloud existe et differe, on l'archive avant de l'ecraser
            if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then snap "$dst" "$HIST"; fi
            cp -p "$src" "$dst" 2>/dev/null || true
         done
      done
      echo "    saves: backup -> $BAK" ;;
   restore)
      [ -d "$BAK" ] || exit 0
      for f in $fichiers; do
         for dst in "$BAK"/$f; do
            [ -f "$dst" ] || continue
            local_f="$SRC/$(basename "$dst")"
            # ne restaurer que si le cloud est STRICTEMENT plus recent que le local
            if [ ! -f "$local_f" ] || [ "$dst" -nt "$local_f" ]; then
               snap "$local_f" "$BAK/.history/local-$(date '+%Y%m%d-%H%M%S')"
               mkdir -p "$SRC" 2>/dev/null || true
               cp -p "$dst" "$local_f" 2>/dev/null || true
               echo "    saves: restore $local_f (cloud plus recent)"
            fi
         done
      done ;;
esac
exit 0
