#!/bin/sh
# Sauvegarde/restauration des saves des jeux Windows lances par Cidre, vers un
# dossier synchronise (iCloud par defaut : CIDRE_SAVES_DIR). Steam Cloud ne peut
# pas resoudre les roots Windows sur macOS, donc on replique sa logique. Mode
# DOSSIER : on sauve tout le dossier du jeu sauf le superflu. JAMAIS destructif :
# copie horodatee en .history/ avant toute ecriture. Non bloquant.
#
#   sync_saves_steam.sh <id> <restore|backup>
#   sync_saves_steam.sh <id> etat        ou en est la synchro, en JSON
#
# Ou sont les sauvegardes d'un jeu : outil-steam/saves.conf (livre), surcharge
# par ~/Library/Application Support/Cidre/saves.conf (`cidre saves set`).
set -u
APPID=${1:-}; SENS=${2:-}
[ -n "$APPID" ] && [ -n "$SENS" ] || exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
DEST=${CIDRE_SAVES_DIR:-$ICLOUD/CidreSaves}
JUNK='/cache/|/logs/|/crash|dumps/|image_cache/|/shader|PopsFeed|PopsMods|EarlyCrashReports|/Temp/|\.log$'
MAXSZ=104857600   # 100 Mo : au-dela ce n'est pas une sauvegarde

# La ligne du jeu : celle de l'utilisateur passe avant celle qu'on livre.
reldir=$(cat "$CIDRE_DIR/saves.conf" "$R/outil-steam/saves.conf" 2>/dev/null \
         | awk -F'\t' -v a="$APPID" '$1==a {print $2; exit}')
non_configure() { [ "$SENS" = etat ] && printf '{"id":"%s","configure":false}\n' "$APPID"; exit 0; }
[ -n "$reldir" ] || non_configure

# Le dossier des sauvegardes : sous le dossier utilisateur du prefixe Wine, ou
# (`jeu:`) dans le dossier du jeu lui-meme -- certains jeux y rangent leurs saves.
case $reldir in
   jeu:*)
      racine=$(sh "$R/cidre" chemin "$APPID" 2>/dev/null)
      [ -n "$racine" ] || non_configure
      SRC="$racine/${reldir#jeu:}" ;;
   *)
      UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
      [ -n "$UH" ] || non_configure
      SRC="$(dirname "$UH")/$reldir" ;;
esac
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
json() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

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
   etat)
      # Compare les deux cotes, fichier par fichier. Un fichier absent de la
      # copie, ou different et plus recent en local, est « a sauvegarder » ;
      # absent en local, ou different et plus recent dans la copie, « a restaurer ».
      T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
      : >"$T/local"; : >"$T/copie"
      [ -d "$SRC" ] && lister "$SRC" >"$T/local"
      [ -d "$BAK" ] && find "$BAK" -type f 2>/dev/null | grep -av "/.history/" >"$T/copie"
      nl=0; ol=0; ml=0; nc=0; oc=0; mc=0; as=0; ar=0
      while IFS= read -r f; do
         set -- $(stat -f '%m %z' "$f" 2>/dev/null); [ $# -eq 2 ] || continue
         nl=$((nl + 1)); ol=$((ol + $2)); [ "$1" -gt "$ml" ] && ml=$1
         b="$BAK/${f#$SRC/}"
         if [ ! -f "$b" ]; then as=$((as + 1))
         elif ! cmp -s "$f" "$b"; then
            if [ "$(stat -f %m "$b")" -gt "$1" ]; then ar=$((ar + 1)); else as=$((as + 1)); fi
         fi
      done <"$T/local"
      while IFS= read -r b; do
         set -- $(stat -f '%m %z' "$b" 2>/dev/null); [ $# -eq 2 ] || continue
         nc=$((nc + 1)); oc=$((oc + $2)); [ "$1" -gt "$mc" ] && mc=$1
         [ -f "$SRC/${b#$BAK/}" ] || ar=$((ar + 1))
      done <"$T/copie"
      if   [ $nl -eq 0 ] && [ $nc -eq 0 ]; then e=vide
      elif [ $nc -eq 0 ]; then e=jamais_sauvegarde
      elif [ $as -gt 0 ] && [ $ar -gt 0 ]; then e=divergent
      elif [ $as -gt 0 ]; then e=a_sauvegarder
      elif [ $ar -gt 0 ]; then e=a_restaurer
      else e=a_jour; fi
      h=$(ls "$BAK/.history" 2>/dev/null | wc -l | tr -d ' ')
      # la copie part-elle vraiment sur iCloud ?
      ic=false; case $DEST in "$ICLOUD"/*) [ -d "$ICLOUD" ] && ic=true ;; esac
      printf '{"id":"%s","configure":true,"etat":"%s","dossier":%s,"copie":%s,"icloud":%s,' \
         "$APPID" "$e" "$(json "$SRC")" "$(json "$BAK")" "$ic"
      printf '"local":{"fichiers":%s,"octets":%s,"modifie":%s},"sauvegarde":{"fichiers":%s,"octets":%s,"modifie":%s},' \
         "$nl" "$ol" "$ml" "$nc" "$oc" "$mc"
      printf '"a_sauvegarder":%s,"a_restaurer":%s,"historique":%s}\n' "$as" "$ar" "$h" ;;
esac
exit 0
