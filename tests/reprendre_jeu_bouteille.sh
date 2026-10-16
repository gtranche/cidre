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
#               le jeu. Refuse tant que la bouteille est en cours d'usage (son
#               wineserver tourne, son client Steam ou un jeu est ouvert) : on
#               ne retire pas un jeu sous les pieds du client qui le suit.
#   <bouteille> quand le jeu est dans plusieurs : son nom, ou source:nom
#               (crossover:Steam), ou sa racine. Sinon, le build le plus recent.
#
# Les sauvegardes sont dans le prefixe de la bouteille (drive_c/users/...), pas
# dans le dossier du jeu : `cidre import` les ramene ensuite
# (tests/reprendre_saves_bouteille.sh), d'apres la reprise notee ici dans
# reprises.conf (appid, source, bouteille, racine, mode, date).
#
# Pour les essais : CIDRE_PS (la commande qui liste les processus avec leur
# environnement, `ps -axwwE -o pid=,command=` par defaut) et CIDRE_LSOF (celle
# qui donne le dossier de travail des wineserver, `lsof -a -c wineserver -d cwd
# -Fpn` par defaut).
# Codes de retour : 0 repris, 1 refuse (rien n'a change), 2 usage.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
# l'emplacement Cidre ou va le jeu (`cidre import` donne celui par defaut, ou --vers)
JEUX=${CIDRE_JEUX_DEST:-$CIDRE_DIR/games}
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
# deja dans un autre emplacement (CIDRE_JEUX_CONNUS : les appids que `cidre` y connait)
case " ${CIDRE_JEUX_CONNUS:-} " in *" $APPID "*) echo "$APPID est deja dans un emplacement Cidre (\`cidre info $APPID\`)" >&2; exit 1 ;; esac

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


# --deplacer : la bouteille tourne-t-elle ? Ce qu'on sait voir sans rien lui
# demander, une raison par ligne (rien : elle est libre) :
#   - un wineserver dont le dossier de travail est celui de ce prefixe : Wine le
#     nomme server-<volume>-<inode du prefixe> (en hexadecimal, sous
#     /tmp/.wine-<uid>/), et son serveur y reste tant qu'il vit -- le dossier,
#     lui, survit au serveur : c'est le processus qu'on cherche ;
#   - un processus lance avec WINEPREFIX = cette bouteille (CrossOver, Whisky et
#     Heroic le posent tous) : son client Steam, un jeu, un outil.
occupee() { # <racine de la bouteille>
   cle=$(stat -f 'server-%Xd-%Xi' "$1" 2>/dev/null | tr 'A-F' 'a-f')
   [ -z "$cle" ] || ${CIDRE_LSOF:-lsof -a -c wineserver -d cwd -Fpn} 2>/dev/null | awk -v c="/$cle" '
      /^p/ { pid = substr($0, 2) }
      /^n/ && substr($0, length($0) - length(c) + 1) == c { print "son wineserver tourne (processus " pid ")" }'
   ${CIDRE_PS:-ps -axwwE -o pid=,command=} 2>/dev/null | LC_ALL=C awk -v r="$1" '
      {  # WINEPREFIX=<racine>, suivi de la variable suivante ou de la fin de la ligne
         i = index($0, "WINEPREFIX=" r); if (!i) next
         reste = substr($0, i + 11 + length(r)); sub(/^\//, "", reste)
         if (reste != "" && reste !~ /^ [A-Za-z_][A-Za-z0-9_]*=/) next
         pid = $1; ligne = tolower($0)
         if (ligne ~ /wineserver/) print "son wineserver tourne (processus " pid ")"
         else if (ligne ~ /steam\.exe|steamwebhelper/) { if (!steam++) print "son client Steam est ouvert (processus " pid ")" }
         else if (!autre++) print "un programme Windows y tourne (processus " pid ")"
      }'
}
if [ "$DEPLACER" = oui ]; then
   quoi=$(occupee "$RACINE" | awk -F' [(]processus' '!vu[$1]++')
   if [ -n "$quoi" ]; then
      case $SOURCE in crossover) outil=CrossOver ;; whisky) outil=Whisky ;; heroic) outil=Heroic ;; *) outil=$SOURCE ;; esac
      {  echo "deplacement refuse : la bouteille « $BOUTEILLE » ($outil) est en cours d'usage :"
         printf '%s\n' "$quoi" | sed 's/^/  - /'
         echo "Ferme le client Steam de cette bouteille et les jeux qui y tournent, puis quitte $outil, et relance : cidre import $APPID --move"
         echo "Sans --move, le jeu peut etre repris tout de suite : il est clone, et la bouteille n'est pas modifiee."
      } >&2
      exit 1
   fi
fi
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
