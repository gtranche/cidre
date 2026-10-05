#!/bin/sh
# Brancher la pile sur TOUS les jeux Steam installes, d'un coup.
#
#   brancher_jeux_steam.sh            montre ce qui serait fait
#   brancher_jeux_steam.sh --ecrire   l'ecrit
#   brancher_jeux_steam.sh --retirer  retire nos options et rien d'autre
#
# Pourquoi une commande plutot qu'un reglage : sur macOS, Steam n'a pas de
# mecanisme global. Les outils de compatibilite en seraient un -- toute la
# machinerie est dans steamclient.dylib -- mais le client macOS ne les cable
# pas : mesure au §276, Steam lance le .exe nu et echoue en « OS Error 0 ».
# Il ne reste que les options de lancement, qui sont par jeu. Alors on les pose
# toutes en une fois, et on la relance quand on installe un jeu.
#
# Poser l'option sur un jeu natif ne coute rien : lancer_depuis_steam.sh regarde
# si le binaire commence par « MZ » et, sinon, s'efface et lance tel quel.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
STEAM=${STEAM:-$HOME/Library/Application Support/Steam}
MODE=${1:-montrer}

# L'option de lancement. Steam la decoupe en arguments a la maniere d'un shell :
# il ecrit lui-meme %command% entre apostrophes quand le chemin du jeu a un
# espace (« Application Support »), et le jeu arrive en un seul argument
# (logs/gameprocess_log.txt). Un runtime installe par Verger vit lui aussi sous
# « Application Support » : son chemin prend donc les memes apostrophes, qui
# n'ont pas besoin d'echappement dans le VDF. Un chemin sans rien de special
# reste nu, comme il l'a toujours ete.
LANCEUR="$R/tests/lancer_depuis_steam.sh"
case $LANCEUR in
   *[\'\"\\]*)
      echo "chemin du runtime avec apostrophe, guillemet ou barre oblique inverse :" >&2
      echo "  $R" >&2
      echo "Steam ne saurait pas le relire dans une option de lancement. Deplacez-le." >&2
      exit 2 ;;
   *[!A-Za-z0-9/._-]*) CMD="'$LANCEUR' %command%" ;;
   *) CMD="$LANCEUR %command%" ;;
esac

# Le compte : userdata a un dossier par compte, nomme par la partie basse de
# son identifiant 64 bits, plus « anonymous » et « 0 » qui ne sont a personne.
# On prend celui que le client a ouvert en dernier, d'apres
# config/loginusers.vdf (MostRecent, sinon le Timestamp le plus grand) ; a
# defaut, le localconfig.vdf modifie le plus recemment parmi les vrais comptes.
ID64=$(LC_ALL=C awk '
   /^[ \t]*"[0-9]+"[ \t\r]*$/ { id = $0; gsub(/[^0-9]/, "", id) }
   /"MostRecent"[ \t]*"1"/ { recent = id }
   match($0, /"Timestamp"[ \t]*"[0-9]+"/) {
      t = substr($0, RSTART, RLENGTH - 1); sub(/.*"/, "", t)
      if (t + 0 >= max) { max = t + 0; dernier = id }
   }
   END { print (recent != "" ? recent : dernier) }
' "$STEAM/config/loginusers.vdf" 2>/dev/null || true)
F=
case $ID64 in
   ''|*[!0-9]*) ;;
   *) F="$STEAM/userdata/$((ID64 - 76561197960265728))/config/localconfig.vdf" ;;
esac
[ -f "$F" ] || F=$(ls -t "$STEAM"/userdata/[1-9]*/config/localconfig.vdf 2>/dev/null | head -1)
[ -f "$F" ] || { echo "localconfig.vdf introuvable sous $STEAM/userdata" >&2; exit 2; }
echo "compte Steam : $(basename "$(dirname "$(dirname "$F")")")"
echo

# Un jeu a-t-il une version macOS NATIVE ? -- un bundle .app, ou un executable
# Mach-O dans son depot. Si oui, on ne l'enveloppe pas : Steam le lance
# nativement, et poser notre couche par-dessus donnerait au mieux une version
# Windows degradee (Surviving Mars : texte abime, §277) la ou le natif tourne.
# Signal filesystem, portable : pas besoin de lire les caches binaires de Steam.
a_version_macos() {
   find "$1" -maxdepth 3 -name "*.app" -type d 2>/dev/null | grep -q . && return 0
   find "$1" -maxdepth 2 -type f -perm +111 ! -name "*.exe" ! -name "*.dll" 2>/dev/null \
      | head -100 | tr '\n' '\0' | xargs -0 file 2>/dev/null | grep -q "Mach-O" && return 0
   return 1
}

# Les jeux installes, et ceux qui portent un executable Windows SANS version
# macOS native.
JEUX=""
IGNORES=""
for acf in "$STEAM"/steamapps/appmanifest_*.acf; do
   [ -f "$acf" ] || continue
   appid=$(basename "$acf" | sed 's/appmanifest_//; s/\.acf//')
   dir=$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$acf" | head -1)
   nom=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$acf" | head -1)
   [ -n "$dir" ] && [ -d "$STEAM/steamapps/common/$dir" ] || continue
   find "$STEAM/steamapps/common/$dir" -maxdepth 3 -name "*.exe" 2>/dev/null | grep -q . || continue
   if a_version_macos "$STEAM/steamapps/common/$dir"; then
      IGNORES="$IGNORES$appid	$nom
"
      continue
   fi
   JEUX="$JEUX$appid	$nom
"
done

if [ -n "$IGNORES" ]; then
   echo "ignores (version macOS native, lances par Steam directement) :"
   printf '%s' "$IGNORES" | while IFS='	' read -r a n; do printf "  %-9s %s\n" "$a" "$n"; done
   echo
fi

[ -n "$JEUX" ] || { echo "aucun jeu Windows-only a brancher"; exit 0; }
echo "jeux Windows-only a brancher :"
printf '%s' "$JEUX" | while IFS='	' read -r a n; do printf "  %-9s %s\n" "$a" "$n"; done

[ "$MODE" = "--ecrire" ] || [ "$MODE" = "--retirer" ] || {
   echo; echo "rien ecrit. Relancez avec --ecrire pour poser les options."; exit 0; }

# Le garde-fou ne vaut que pour l'ecriture : Steam garde ce fichier en memoire
# et le reecrit en quittant, ce qui effacerait notre travail sans rien dire.
if pgrep -f "Steam.AppBundle/Steam/Contents/MacOS/steam_osx" >/dev/null 2>&1; then
   echo; echo "Steam tourne : il reecrirait ce fichier en quittant. Fermez-le d'abord." >&2
   exit 1
fi

# Le fichier est recrit sur place (memes droits), en gardant sa derniere ligne
# telle qu'elle est -- et seulement s'il change : l'agent de session relance ce
# script toutes les demi-heures, inutile de sauvegarder et de recrire a chaque
# fois un fichier deja bon.
TMP="$F.cidre-$$"
[ -n "$(tail -c 1 "$F")" ] && SANS_FIN=1 || SANS_FIN=
LC_ALL=C RETIRER=$([ "$MODE" = "--retirer" ] && echo 1) CMD="$CMD" \
   APPIDS="$(printf '%s' "$JEUX" | cut -f1 | tr '\n' ' ')" \
   NATIFS="$(printf '%s' "$IGNORES" | cut -f1 | tr '\n' ' ')" \
   SORTIE="$TMP" SANS_FIN=$SANS_FIN awk -f "$R/tests/brancher_jeux_steam.awk" "$F"
if cmp -s "$TMP" "$F"; then
   rm -f "$TMP"
   echo; echo "rien a changer."
   exit 0
fi
cp -p "$F" "$F.sauvegarde-$(date '+%Y%m%d-%H%M%S')"
cat "$TMP" >"$F"
rm -f "$TMP"
echo; echo "fait. Rouvrez Steam."
