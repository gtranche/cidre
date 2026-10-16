#!/bin/sh
# Trouve les jeux Steam Windows deja installes sur ce Mac par un autre outil :
# le client Steam Windows d'une bouteille CrossOver, Whisky ou Heroic. Ce sont
# les memes depots Steam, les memes fichiers que ceux de `cidre dl` : on peut
# les reprendre (`cidre import`) au lieu de les telecharger une seconde fois.
# Lecture seule : rien n'est ecrit, nulle part.
#
#   trouver_jeux_bouteilles.sh [--json] [--rapide] [--complet] [--verbeux]
#   trouver_jeux_bouteilles.sh --bouteilles
#
# Une ligne par jeu, champs separes par une tabulation :
#   appid  nom  source (crossover|whisky|heroic)  bouteille  chemin  buildid  taille
# `chemin` est le dossier du jeu (steamapps/common/<installdir>), `taille` le
# SizeOnDisk du manifeste, en octets. Tri par appid, puis du build le plus
# recent au plus ancien quand un jeu est dans plusieurs bouteilles.
#
# Un jeu est retenu si son appmanifest_<appid>.acf dit l'installation complete
# (StateFlags 4, ou 6 : complete, une mise a jour attend), si son dossier existe
# et s'il pese au moins 90 % de ce que dit le manifeste. Les jeux deja dans le
# dossier Cidre (games/<appid>) sont passes.
#
#   --json      la meme liste en JSON (pour `cidre bottles --json`), avec
#               "maj_en_attente" (StateFlags 6)
#   --rapide    sans peser les dossiers (`cidre library` : la pesee d'une grosse
#               bibliotheque prend des secondes ; `cidre import` la refait)
#   --complet   trois colonnes de plus : StateFlags, racine de la bouteille,
#               chemin du manifeste (pour `cidre import`)
#   --verbeux   dit sur la sortie d'erreur pourquoi un jeu n'est pas retenu
#   --bouteilles  les bouteilles elles-memes, avec ou sans jeu : une ligne
#               `source <TAB> nom <TAB> racine` (pour y chercher des sauvegardes)
#
# Ou chercher. Chaque variable est une liste de dossiers separes par `:` ; la
# definir vide desactive la source (les essais n'explorent pas la machine).
#   CIDRE_BOUTEILLES_CROSSOVER  dossiers de bouteilles CrossOver
#       defaut : ~/Library/Application Support/CrossOver/Bottles, et le dossier
#       choisi dans les preferences de CrossOver (BottleDir)
#   CIDRE_BOUTEILLES_WHISKY     dossiers de bouteilles Whisky
#       defaut : ~/Library/Containers/com.isaacmarovitz.Whisky/Bottles, et les
#       bouteilles que note BottleVM.plist -- toutes, celles de ce dossier
#       comme celles rangees ailleurs (CIDRE_WHISKY_REGISTRE pour en lire un
#       autre)
#   CIDRE_BOUTEILLES_HEROIC     dossiers de prefixes Heroic
#       defaut : ~/Games/Heroic/Prefixes, et les prefixes que nomme la
#       configuration de Heroic (CIDRE_HEROIC_CONFIG pour en lire une autre)
# Dans une bouteille : le client Steam de drive_c/Program Files (x86)/Steam, et
# les bibliotheques qu'il a ajoutees sur d'autres lecteurs (libraryfolders.vdf,
# lettres resolues par dosdevices/).
set -u
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
JEUX_CIDRE="$CIDRE_DIR/games"
JSON=non; RAPIDE=non; COMPLET=non; VERBEUX=non; BOUTEILLES=non
for a in "$@"; do
   case $a in
      --json) JSON=oui ;; --rapide) RAPIDE=oui ;; --complet) COMPLET=oui ;; --verbeux) VERBEUX=oui ;;
      --bouteilles) BOUTEILLES=oui ;;
      *) echo "usage: trouver_jeux_bouteilles.sh [--json] [--rapide] [--complet] [--verbeux] | --bouteilles" >&2; exit 2 ;;
   esac
done
TAB=$(printf '\t'); US=$(printf '\037')
dire() { [ "$VERBEUX" = oui ] && echo "$1" >&2; return 0; }
# une liste « a:b » en lignes
lignes() { printf '%s\n' "$1" | tr ':' '\n'; }
# le chemin physique d'un dossier (liens resolus), pour ne pas compter deux fois
physique() { (cd "$1" 2>/dev/null && pwd -P); }
# file:///Users/x/Mes%20bouteilles/ -> /Users/x/Mes bouteilles
chemin_url() {
   LC_ALL=C awk -v u="$1" 'BEGIN {
      sub(/^file:\/\/(localhost)?/, "", u); sub(/\/$/, "", u)
      h = "0123456789abcdef"; r = ""
      while ((i = index(u, "%")) > 0) {
         a = index(h, tolower(substr(u, i + 1, 1))); b = index(h, tolower(substr(u, i + 2, 1)))
         if (!a || !b) { r = r substr(u, 1, i); u = substr(u, i + 1); continue }
         r = r substr(u, 1, i - 1) sprintf("%c", (a - 1) * 16 + b - 1); u = substr(u, i + 3)
      }
      print r u }'
}

# Les bouteilles : « source TAB nom TAB racine », une par ligne.
bouteilles() {
   # CrossOver : un dossier par bouteille, qui porte son nom.
   if [ "${CIDRE_BOUTEILLES_CROSSOVER+x}" ]; then L=$CIDRE_BOUTEILLES_CROSSOVER
   else
      L="$HOME/Library/Application Support/CrossOver/Bottles"
      d=$(defaults read com.codeweavers.CrossOver BottleDir 2>/dev/null) && [ -n "$d" ] && L="$L:$d"
   fi
   lignes "$L" | while IFS= read -r d; do
      [ -n "$d" ] || continue
      for b in "$d"/*/; do
         [ -d "${b}drive_c" ] && printf 'crossover\t%s\t%s\n' "$(basename "$b")" "${b%/}"
      done
   done
   # Whisky : un dossier par bouteille, nomme par un UUID ; le nom donne par
   # l'utilisateur est dans Metadata.plist (info > name). Verifie sur des
   # bouteilles ecrites par Whisky 2.3.5 lui-meme : son registre BottleVM.plist
   # note TOUTES les bouteilles (paths[].relative, une URL file:// sans barre
   # finale), y compris celles du dossier Bottles -- le tri par chemin physique,
   # plus bas, ne les compte qu'une fois ; une bouteille neuve n'a pas de
   # drive_c tant que Wine n'y a pas tourne : elle est passee.
   if [ "${CIDRE_BOUTEILLES_WHISKY+x}" ]; then L=$CIDRE_BOUTEILLES_WHISKY; REG=${CIDRE_WHISKY_REGISTRE:-}
   else
      L="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"
      REG=${CIDRE_WHISKY_REGISTRE:-$HOME/Library/Containers/com.isaacmarovitz.Whisky/BottleVM.plist}
   fi
   { lignes "$L" | while IFS= read -r d; do
        [ -n "$d" ] || continue
        for b in "$d"/*/; do [ -d "$b" ] && printf '%s\n' "${b%/}"; done
     done
     # les bouteilles du registre : des URL file://
     [ -f "$REG" ] && plutil -extract paths json -o - "$REG" 2>/dev/null | sed 's#\\/#/#g' | tr '"' '\n' |
        grep '^file://' | while IFS= read -r u; do chemin_url "$u"; done
   } | while IFS= read -r b; do
      [ -d "$b/drive_c" ] || continue
      n=$(/usr/libexec/PlistBuddy -c 'Print :info:name' "$b/Metadata.plist" 2>/dev/null) || n=
      printf 'whisky\t%s\t%s\n' "$(printf '%s' "${n:-$(basename "$b")}" | tr '\t' ' ')" "$b"
   done
   # Heroic : des prefixes Wine, sous son dossier Prefixes ou la ou la
   # configuration (generale, ou d'un jeu) le dit.
   if [ "${CIDRE_BOUTEILLES_HEROIC+x}" ]; then L=$CIDRE_BOUTEILLES_HEROIC; CONF=${CIDRE_HEROIC_CONFIG:-}
   else
      L="$HOME/Games/Heroic/Prefixes"
      CONF=${CIDRE_HEROIC_CONFIG:-$HOME/Library/Application Support/heroic}
   fi
   { lignes "$L" | while IFS= read -r d; do
        [ -n "$d" ] || continue
        for b in "$d"/*/; do [ -d "$b" ] && printf '%s\n' "${b%/}"; done
     done
     [ -d "$CONF" ] && cat "$CONF/config.json" "$CONF"/GamesConfig/*.json 2>/dev/null |
        sed -nE 's/.*"(winePrefix|defaultWinePrefix)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' | sed 's#\\/#/#g; s#\\\\#\\#g'
   } | while IFS= read -r b; do
      [ -d "$b/drive_c" ] && printf 'heroic\t%s\t%s\n' "$(basename "$b")" "${b%/}"
   done
}

# « C:\\Program Files (x86)\\Steam » (libraryfolders.vdf) -> chemin sur le Mac
chemin_windows() { # <racine de la bouteille> <chemin Windows>
   p=$(printf '%s' "$2" | sed 's/\\\\/\//g; s/\\/\//g')
   case $p in [A-Za-z]:*) ;; *) return 1 ;; esac
   l=$(printf '%s' "$p" | cut -c1 | tr '[:upper:]' '[:lower:]'); reste=${p#??}
   if [ -e "$1/dosdevices/$l:" ]; then printf '%s\n' "$1/dosdevices/$l:$reste"
   elif [ "$l" = c ]; then printf '%s\n' "$1/drive_c$reste"
   else return 1; fi
}
# Les bibliotheques Steam d'une bouteille (dossiers steamapps), sans doublon.
bibliotheques() { # <racine>
   for s in "$1/drive_c/Program Files (x86)/Steam" "$1/drive_c/Program Files/Steam"; do
      [ -d "$s/steamapps" ] || continue
      physique "$s/steamapps"
      sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
         "$s/steamapps/libraryfolders.vdf" "$s/config/libraryfolders.vdf" 2>/dev/null | tr -d '\r' |
      while IFS= read -r p; do
         u=$(chemin_windows "$1" "$p") && [ -d "$u/steamapps" ] && physique "$u/steamapps"
      done
   done | awk '!vu[$0]++'
}
# Les champs de premier niveau d'un manifeste, separes par US (0x1f) : une
# tabulation avalerait les champs vides a la lecture.
manifeste() {
   LC_ALL=C awk -v US="$US" '
      { sub(/\r$/, "") }
      /^[ \t]*\{/ { prof++; next }
      /^[ \t]*\}/ { prof--; next }
      prof == 1 {
         l = $0; sub(/^[ \t]*"/, "", l)
         i = index(l, "\""); if (!i) next
         k = tolower(substr(l, 1, i - 1)); v = substr(l, i + 1)
         sub(/^[ \t]*"/, "", v); sub(/"[ \t]*$/, "", v)
         gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v); gsub(/[\t\037]/, " ", v)
         if (!(k in c)) c[k] = v
      }
      END { printf "%s%s%s%s%s%s%s%s%s%s%s\n", c["appid"], US, c["name"], US, c["stateflags"], US, c["installdir"], US, c["buildid"], US, c["sizeondisk"] }' "$1"
}
nombre() { case $1 in ''|*[!0-9]*) return 1 ;; esac; }

T=$(mktemp "${TMPDIR:-/tmp}/bouteilles.XXXXXX") || exit 1
trap 'rm -f "$T" "$T.b"' EXIT
# (dans un fichier : les boucles ci-dessous lisent leur entree, pas un tube)
bouteilles >"$T.b"
if [ "$BOUTEILLES" = oui ]; then
   vues=
   while IFS="$TAB" read -r src nomb racine; do
      racine=$(physique "$racine") || continue
      case "$US$vues$US" in *"$US$racine$US"*) continue ;; esac
      vues="$vues$US$racine"
      printf '%s\t%s\t%s\n' "$src" "$nomb" "$racine"
   done <"$T.b"
   exit 0
fi
vues=
while IFS="$TAB" read -r src nomb racine; do
   # une bouteille connue par deux chemins (un prefixe Heroic qui est une
   # bouteille CrossOver) ne compte qu'une fois
   # (et les chemins rendus sont les chemins physiques : la ou sont les fichiers)
   racine=$(physique "$racine") || continue
   case "$US$vues$US" in *"$US$racine$US"*) continue ;; esac
   vues="$vues$US$racine"
   bibliotheques "$racine" | while IFS= read -r lib; do
      for m in "$lib"/appmanifest_*.acf; do
         [ -f "$m" ] || continue
         IFS="$US" read -r appid nom etat rep build taille <<EOF
$(manifeste "$m")
EOF
         nombre "$appid" && [ "$m" = "$lib/appmanifest_$appid.acf" ] || { dire "ignore : $m (manifeste illisible)"; continue; }
         [ "$appid" = 228980 ] && continue   # Steamworks Common Redistributables
         qui="$appid ${nom:-?} ($src : $nomb)"
         # deja dans un emplacement Cidre (CIDRE_JEUX_CONNUS, donne par `cidre` ;
         # sinon le dossier principal)
         if [ -n "${CIDRE_JEUX_CONNUS+x}" ]; then
            case " $CIDRE_JEUX_CONNUS " in *" $appid "*) dire "ignore : $qui, deja dans le dossier Cidre"; continue ;; esac
         elif [ -d "$JEUX_CIDRE/$appid" ]; then dire "ignore : $qui, deja dans le dossier Cidre"; continue; fi
         case $etat in 4|6) ;; *) dire "ignore : $qui, installation incomplete (StateFlags ${etat:-absent})"; continue ;; esac
         case $rep in ''|.|..|*/*) dire "ignore : $qui, installdir invalide"; continue ;; esac
         dossier="$lib/common/$rep"
         [ -d "$dossier" ] || { dire "ignore : $qui, dossier absent ($dossier)"; continue; }
         nombre "$build" || build=0
         nombre "$taille" || taille=0
         if [ "$RAPIDE" = non ] && [ "$taille" -gt 0 ]; then
            ko=$(du -sk "$dossier" 2>/dev/null | cut -f1)
            if [ $(( ${ko:-0} * 10 )) -lt $(( taille / 1024 * 9 )) ]; then
               dire "ignore : $qui, dossier incomplet ($(( ${ko:-0} / 1024 )) Mo sur $(( taille / 1048576 )) attendus)"; continue
            fi
         fi
         printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$appid" "${nom:-$rep}" "$src" "$nomb" "$dossier" "$build" "$taille" "$etat" "$racine" "$m"
      done
   done
done <"$T.b" >"$T"

sort -t "$TAB" -k1,1n -k6,6nr "$T" |
if [ "$JSON" = oui ]; then
   LC_ALL=C awk -F'\t' '
      function js(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/[\001-\037]/, " ", s); return "\"" s "\"" }
      { printf "%s\n  {\"appid\":%s,\"nom\":%s,\"source\":%s,\"bouteille\":%s,\"chemin\":%s,\"buildid\":%s,\"taille\":%s,\"maj_en_attente\":%s}", \
           (NR == 1 ? "[" : ","), $1, js($2), js($3), js($4), js($5), $6, $7, ($8 == 6 ? "true" : "false") }
      END { if (NR) print "\n]"; else print "[]" }'
elif [ "$COMPLET" = oui ]; then cat
else cut -f1-7
fi
