#!/bin/sh
# Reprend dans le dossier Cidre un jeu Steam Windows deja installe dans une
# bouteille CrossOver, Whisky ou Heroic (tests/trouver_jeux_bouteilles.sh), au
# lieu de le telecharger une seconde fois. C'est `cidre import`.
#
#   reprendre_jeu_bouteille.sh <appid> [<bouteille>] [--deplacer]
#
# Le jeu arrive dans games/<appid> sous la forme que laisse `cidre dl` (SteamCMD
# avec force_install_dir) : les fichiers du jeu a la racine, et son manifeste
# dans steamapps/appmanifest_<appid>.acf -- c'est lui qui donne a `cidre list`,
# `cidre library`, `cidre updates` et Verger le nom, la taille et le build. Un
# `cidre dl <appid>` ulterieur met le jeu a jour sur place.
#
# Sans option, la bouteille n'est pas modifiee : le jeu est clone (APFS, `cp
# -c`), ce qui est immediat et ne prend pas de place tant que les deux copies
# sont identiques. Entre deux volumes, ou hors APFS, c'est une copie ordinaire :
# on le dit, et on refuse si la place manque.
#
#   --deplacer  deplace le jeu au lieu de le cloner, et retire son manifeste de
#               la bouteille : elle est liberee, son client Steam ne voit plus
#               le jeu. Fermer d'abord l'outil qui la fait tourner.
#   <bouteille> quand le jeu est dans plusieurs : son nom, ou source:nom
#               (crossover:Steam), ou sa racine. Sinon, le build le plus recent.
#
# Les sauvegardes restent dans le prefixe de la bouteille (drive_c/users/...) :
# on dit ou, et on note la reprise dans reprises.conf (appid, source, bouteille,
# racine, mode, date) pour qui voudra les ramener.
# Codes de retour : 0 repris, 1 refuse (rien n'a change), 2 usage.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
JEUX="$CIDRE_DIR/games"
usage() { echo "usage: cidre import <appid> [<bouteille>] [--move]" >&2; exit 2; }
APPID=; QUI=; DEPLACER=non
for a in "$@"; do
   case $a in
      --deplacer|--move) DEPLACER=oui ;;
      -*) usage ;;
      *) if [ -z "$APPID" ]; then APPID=$a; elif [ -z "$QUI" ]; then QUI=$a; else usage; fi ;;
   esac
done
case $APPID in ''|*[!0-9]*) usage ;; esac
DEST="$JEUX/$APPID"
[ -e "$DEST" ] && { echo "$APPID est deja dans le dossier Cidre : $DEST" >&2; exit 1; }

# Le jeu, tel que le decrit le detecteur (il pese le dossier : pas de --rapide).
L=$(sh "$R/tests/trouver_jeux_bouteilles.sh" --complet | awk -F'\t' -v a="$APPID" -v q="$QUI" \
      '$1 == a && (q == "" || $4 == q || $3 ":" $4 == q || $9 == q) { print; exit }')
if [ -z "$L" ]; then
   echo "jeu $APPID introuvable dans les bouteilles${QUI:+ ($QUI)}" >&2
   # pourquoi : ce que le detecteur a ecarte pour cet appid
   sh "$R/tests/trouver_jeux_bouteilles.sh" --verbeux 2>&1 >/dev/null | grep "^ignore : $APPID " >&2
   exit 1
fi
col() { printf '%s\n' "$L" | cut -f"$1"; }
NOM=$(col 2); SOURCE=$(col 3); BOUTEILLE=$(col 4); SRC=$(col 5); RACINE=$(col 9); MANIFESTE=$(col 10)
# (le detecteur construit ce chemin ; on ne deplace rien qui n'ait cette forme)
case $SRC in */steamapps/common/?*) ;; *) echo "chemin inattendu : $SRC" >&2; exit 1 ;; esac
[ -n "$(find "$SRC" -maxdepth 4 -iname '*.exe' 2>/dev/null | head -1)" ] ||
   { echo "aucun .exe dans $SRC : ce n'est pas la version Windows du jeu" >&2; exit 1; }

mkdir -p "$JEUX" || exit 1
volume() { stat -f %d "$1"; }
apfs() { mount | grep -F "$(df -P "$1" | awk 'NR == 2 { print $1 }') on " | grep -q '(apfs'; }
# ce que contient un dossier : nombre de fichiers et total de leurs octets
contenu() { find "$1" -type f -exec stat -f %z {} + 2>/dev/null | awk '{ n++; t += $1 } END { print n + 0, t + 0 }'; }
MEME=non; [ "$(volume "$SRC")" = "$(volume "$JEUX")" ] && MEME=oui
if [ "$MEME" = non ] || { [ "$DEPLACER" = non ] && ! apfs "$JEUX"; }; then
   # copie ordinaire : chaque octet est ecrit une seconde fois
   besoin=$(du -sk "$SRC" | cut -f1); libre=$(df -Pk "$JEUX" | awk 'NR == 2 { print $4 }')
   echo "attention : pas de clone possible (autre volume, ou volume non APFS) : copie de $(( besoin / 1024 )) Mo, $(( libre / 1024 )) Mo libres" >&2
   [ "$libre" -gt "$besoin" ] || { echo "place insuffisante sur le volume du dossier Cidre" >&2; exit 1; }
   MODE=copie
else MODE=clone; fi
[ "$DEPLACER" = oui ] && MODE=deplace

# On travaille a cote (dossier cache : `cidre list` ne le voit pas), et le jeu
# n'apparait sous son appid qu'une fois complet.
TMP="$JEUX/.reprise-$APPID.$$"
DEPLACE=non   # le dossier de la bouteille est-il parti (renomme) dans TMP ?
annuler() {
   if [ "$DEPLACE" = oui ]; then
      # TMP est le jeu lui-meme : on le rend a la bouteille, on ne l'efface jamais
      rm -f "$TMP/steamapps/appmanifest_$APPID.acf"; rmdir "$TMP/steamapps" 2>/dev/null
      mv "$TMP" "$SRC" || echo "le jeu est reste dans $TMP : le remettre a la main dans $SRC" >&2
   else rm -rf "$TMP"; fi
}
trap 'annuler' EXIT
trap 'exit 1' INT TERM HUP
if [ "$DEPLACER" = oui ] && [ "$MEME" = oui ]; then
   mv "$SRC" "$TMP" || { echo "deplacement refuse : $SRC" >&2; exit 1; }
   DEPLACE=oui
else
   avant=$(contenu "$SRC")
   mkdir "$TMP" && cp -c -R -p "$SRC/" "$TMP" || { echo "copie interrompue : rien n'est repris" >&2; exit 1; }
   apres=$(contenu "$TMP")
   [ "$avant" = "$apres" ] || { echo "copie incomplete ($apres fichiers/octets sur $avant) : rien n'est repris" >&2; exit 1; }
fi
# Le manifeste, comme SteamCMD l'aurait ecrit : sans le chemin du client Steam
# de la bouteille, et « installe » (un build en retard se voit a `cidre
# updates`, qui compare buildid au build publie).
mkdir -p "$TMP/steamapps" &&
   sed -e '/^[[:space:]]*"LauncherPath"/d' \
       -e 's/^\([[:space:]]*"StateFlags"[[:space:]]*\)"[0-9]*"/\1"4"/' "$MANIFESTE" >"$TMP/steamapps/appmanifest_$APPID.acf" &&
   [ -s "$TMP/steamapps/appmanifest_$APPID.acf" ] || { echo "manifeste illisible : $MANIFESTE" >&2; exit 1; }
mv "$TMP" "$DEST" || { echo "impossible de creer $DEST" >&2; exit 1; }
trap - EXIT
# La bouteille n'est touchee qu'ici, et seulement sur demande : le jeu est en
# place dans le dossier Cidre.
if [ "$DEPLACER" = oui ]; then
   [ "$DEPLACE" = oui ] || rm -rf "${SRC:?}"
   rm -f "$MANIFESTE"
fi

touch "$CIDRE_DIR/reprises.conf"
awk -F'\t' -v a="$APPID" '$1 != a' "$CIDRE_DIR/reprises.conf" >"$CIDRE_DIR/reprises.conf.tmp"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$APPID" "$SOURCE" "$BOUTEILLE" "$RACINE" "$MODE" "$(date +%s)" >>"$CIDRE_DIR/reprises.conf.tmp"
mv "$CIDRE_DIR/reprises.conf.tmp" "$CIDRE_DIR/reprises.conf"

echo "repris : $NOM ($APPID), depuis $SOURCE « $BOUTEILLE »"
case $MODE in
   clone)   echo "  mode        : clone APFS (immediat, pas de place prise ; la bouteille est intacte)" ;;
   copie)   echo "  mode        : copie (la bouteille est intacte)" ;;
   deplace) echo "  mode        : deplace (la bouteille n'a plus ce jeu)" ;;
esac
echo "  dossier     : $DEST"
u=$(ls -d "$RACINE/drive_c/users/"*/AppData 2>/dev/null | grep -v '/users/Public/' | head -1)
[ -z "$u" ] || echo "  sauvegardes : restees dans la bouteille, sous $(dirname "$u")"
