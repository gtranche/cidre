#!/bin/sh
# Pose les reglages du jeu lui-meme ([reglages_jeu] de sa fiche, cf.
# profils/README.md) dans son fichier de reglages : un jeu qui n'est jouable
# qu'avec ses propres options baissees (Expedition 33 : prereglage Moyen et
# resolution a 66 %, x2,5 mesure). Appele par lancer_depuis_steam.sh avant le
# jeu, tant que le profil utilisateur ne porte pas reglages_jeu_appliques = true.
#
#   reglages_jeu.sh <appid>
#   reglages_jeu.sh <appid> nouvelles <ids>         les seules entrees a `id` absent de <ids> (liste a virgules) :
#                                                   pour un jeu deja marque, une entree ajoutee depuis a la fiche
#   reglages_jeu.sh <appid> temoin                  la valeur du temoin de la fiche (voir plus bas), vide s'il n'y en a pas
#   reglages_jeu.sh <appid> temoin-change <avant>   apres la partie : si le temoin ne vaut plus <avant>, retire le marqueur
#   reglages_jeu.sh - ruche <ruche> <cle>           hors fiche : pose sous <cle> de <ruche> (user.reg, system.reg) les
#                                                   lignes `nom TAB donnee` lues sur l'entree (format brut, voir poser_registre)
#
# Une fiche peut viser plusieurs sections INI (liste [[reglages_jeu]]) : chaque
# entree est traitee a son tour, dans l'ordre de la fiche. Les reglages sont ceux
# qui valent sur cette machine : les blocs [[machine]] de la fiche dont la
# condition est vraie y sont deja fondus (fiche_profil.sh, tests/machine.sh).
#
# Codes de retour : 0 = tous les reglages poses, ou deja en place (le lanceur
# note alors reglages_jeu_appliques = true et n'y touche plus) ; 3 = rien a faire
# pour l'instant (pas de fiche, pas de [reglages_jeu], ou un fichier du jeu pas
# encore cree : on reessaiera au prochain lancement, les entrees deja posees
# seront alors « deja en place ») ; 1 = erreur.
#
# Quatre formats (cle `format` de l'entree) : `ini` (defaut), `gvas` pour une
# sauvegarde Unreal ou le jeu range des reglages (proprietes entieres remplacees
# sur place, cf. poser_gvas), `registre` et `playerprefs` (les PlayerPrefs
# d'Unity) pour un jeu qui les garde dans le registre du prefixe (cf.
# poser_registre). `fichier` peut contenir un `*` pour un dossier au
# nom inconnu d'avance (un par compte) : chaque fichier qui correspond est traite.
#
# Format ini : seules les cles voulues sont reecrites, si leur valeur differe : les autres
# lignes passent telles quelles, fins de ligne CRLF comprises, les guillemets et
# l'espacement de la ligne sont gardes. Avec `section`, la cle n'est cherchee que
# dans cette section INI, et une cle absente y est ajoutee (la section aussi, a la
# fin, si elle manque). Sans section, une cle absente n'est pas ajoutee. Avant la
# premiere ecriture, le fichier est copie en <fichier>.avant-cidre, jamais ecrase.
#
# Le temoin ([reglages_jeu_temoin] de la fiche : fichier INI + cle). Certains
# jeux refont leur detection du materiel quand la carte graphique vue change
# (passage de DXVK a DXMT, autre machine) et remettent alors leurs reglages a
# leurs propres valeurs -- apres que le lanceur a pose ceux de la fiche et note
# le marqueur. Expedition 33 le fait quand UserConfigHardwareProfile change. Le
# lanceur releve le temoin avant le jeu et le compare a la sortie : s'il a
# change, le marqueur est retire et les reglages sont reposes au lancement
# suivant (le temoin, lui, ne bouge plus).
set -u
APPID=${1:-}
[ -n "$APPID" ] || exit 3
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}

temoin() { # la valeur de la cle temoin dans son fichier ; vide sans temoin, sans fichier ou sans la cle
   f=$(sh "$R/tests/fiche_profil.sh" chemin "$APPID") || return 0
   t=$(sh "$R/tests/fiche_profil.sh" toml "$f" | awk -F'\t' '$1 == "reglages_jeu_temoin" && ($2 == "fichier" || $2 == "cle") { print $2 "=" $4 }')
   rel=$(printf '%s\n' "$t" | sed -n 's/^fichier=//p'); cle=$(printf '%s\n' "$t" | sed -n 's/^cle=//p')
   case $rel in ''|/*|*..*) return 0 ;; esac
   case $cle in ''|*[!A-Za-z0-9_.]*) return 0 ;; esac
   u=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
   [ -n "$u" ] && [ -f "$(dirname "$u")/$rel" ] || return 0
   tr -d '\r' <"$(dirname "$u")/$rel" | awk -v c="$cle" '{ i = index($0, "="); if (i && substr($0, 1, i - 1) == c) { print substr($0, i + 1); exit } }'
}
case ${2:-} in
   temoin) temoin; exit 0 ;;
   temoin-change)
      # rien a dire si le temoin n existait pas avant (premier lancement) ou n existe plus
      apres=$(temoin)
      [ -n "${3:-}" ] && [ -n "$apres" ] && [ "$apres" != "$3" ] || exit 0
      if [ "$(sh "$R/tests/profil_cidre.sh" "$APPID" | sed -n 's/^reglages_jeu_appliques=//p')" = true ]; then
         sh "$R/tests/profil_cidre.sh" "$APPID" unset reglages_jeu_appliques
         echo "    reglages du jeu : le jeu a refait sa detection du materiel pendant cette partie (temoin : $3 -> $apres) et repris ses propres reglages ; ceux de la fiche seront reposes au prochain lancement"
      fi
      exit 0 ;;
esac

# (l appel `ruche` ne lit pas de fiche : il passe droit a poser_registre, plus bas)
if [ "${2:-}" != ruche ]; then
   REGL=$(sh "$R/tests/fiche_profil.sh" reglages "$APPID") || exit 1
   [ -n "$REGL" ] || exit 3
   UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
   [ -n "$UH" ] || { echo "    reglages du jeu : pas de dossier utilisateur dans le prefixe"; exit 3; }
fi

# Le fichier reecrit ($F.cidre-tmp) remplace l original s il en differe : copie
# d origine d abord (une seule fois), puis cat -- pas mv, le fichier garde ses
# droits et son inode. <nom affiche> <precision entre crochets>
remplacer() {
   if cmp -s "$F" "$F.cidre-tmp"; then
      rm -f "$F.cidre-tmp"
      echo "    reglages du jeu : deja en place dans $1$2"
   else
      [ -f "$F.avant-cidre" ] || cp -p "$F" "$F.avant-cidre"
      cat "$F.cidre-tmp" >"$F" && echo "    reglages du jeu : poses dans $1$2 (copie d'origine : $(basename "$F").avant-cidre)"
      rm -f "$F.cidre-tmp"
   fi
}

# Format ini : le fichier $F, les valeurs voulues dans $V (`cle TAB valeur`), la
# section $SECTION au besoin. Rend 0, ou 1 si la reecriture echoue.
poser_ini() { # <nom affiche>
   LC_ALL=C awk -F'\t' -v section="$SECTION" '
      # les cles manquantes de la section visee, ajoutees a sa fin (avant ses lignes vides)
      function ajouter(   k, c) {
         for (k = 1; k <= nv; k++) { c = ordre[k]; if (!fait[c]) { print c "=" voulu[c] eol; fait[c] = 1 } }
      }
      NR == FNR { i = index($0, "\t"); c = substr($0, 1, i - 1); voulu[c] = substr($0, i + 1); ordre[++nv] = c; next }
      {
         fin = ""; if (sub(/\r$/, "")) fin = "\r"
         if (FNR == 1) eol = fin
         if ($0 ~ /^[ \t]*\[/) {
            if (section != "" && sec == section) { ajouter(); vue = 1 }
            printf "%s", attente; attente = ""
            sec = $0; gsub(/^[ \t]*\[[ \t]*|[ \t]*\].*$/, "", sec)
            print $0 fin; next
         }
         if (section != "" && sec == section && $0 ~ /^[ \t]*$/) { attente = attente $0 fin "\n"; next }
         printf "%s", attente; attente = ""
         i = index($0, "=")
         if (i && (section == "" || sec == section) && $0 !~ /^[ \t]*[;#]/) {
            c = substr($0, 1, i - 1); gsub(/^[ \t]+|[ \t]+$/, "", c)
            if ((c in voulu) && !fait[c]) {
               v = substr($0, i + 1); debut = substr($0, 1, i)
               match(v, /^[ \t]*/); debut = debut substr(v, 1, RLENGTH); v = substr(v, RLENGTH + 1)
               g = (v ~ /^"/) ? "\"" : ""
               $0 = debut g voulu[c] g; fait[c] = 1
            }
         }
         print $0 fin
      }
      END {
         if (section != "" && sec == section) { ajouter(); vue = 1 }
         printf "%s", attente
         if (section != "" && !vue) {
            # section absente : on la cree a la fin
            for (k = 1; k <= nv; k++) if (!fait[ordre[k]]) manque = 1
            if (manque) { print eol; print "[" section "]" eol; ajouter() }
         }
      }
   ' "$V" "$F" >"$F.cidre-tmp" || { rm -f "$F.cidre-tmp"; echo "    reglages du jeu : echec de la reecriture de $1"; return 1; }
   remplacer "$1" "${SECTION:+ [$SECTION]}"
   return 0
}

# Format gvas : une sauvegarde Unreal (SaveGame, en-tete « GVAS »), ou le jeu
# range des reglages qu il recopie ensuite dans son INI (Expedition 33 : la
# qualite graphique, SharedGameUserSettings.sav). Chaque cle de $V est le nom
# d une propriete entiere (IntProperty) ; sa valeur est remplacee sur place --
# 4 octets, la taille et le reste du fichier ne changent pas. Une propriete
# n est touchee que si son en-tete est exactement celui attendu et qu elle
# n apparait qu une fois ; sinon elle est laissee, une ligne le dit, et les
# autres sont posees. Rend 0, ou 1 si le fichier n est pas une sauvegarde GVAS.
poser_gvas() { # <nom affiche>
   nom=$1
   [ "$(head -c 4 "$F" 2>/dev/null)" = GVAS ] || { echo "    reglages du jeu : $nom n'est pas une sauvegarde Unreal (GVAS)"; return 1; }
   [ "$(wc -c <"$F")" -le 4194304 ] || { echo "    reglages du jeu : $nom est trop gros pour etre retouche"; return 1; }
   cp "$F" "$F.cidre-tmp" || return 1
   HEX=$(od -An -v -tx1 "$F" | tr -d ' \n')
   while IFS='	' read -r c v; do
      case $v in ''|*[!0-9]*) echo "    reglages du jeu : $c = « $v » n'est pas un entier, laisse"; continue ;; esac
      [ "$v" -le 2147483647 ] 2>/dev/null || { echo "    reglages du jeu : $c = $v est hors bornes, laisse"; continue; }
      # l en-tete d une IntProperty : longueur du nom (zero final compris), le nom,
      # « IntProperty », pas de sous-type, 4 octets de valeur, pas de GUID
      motif=$(printf '%02x000000%s000c000000496e7450726f70657274790000000000040000000' $((${#c} + 1)) "$(printf '%s' "$c" | od -An -v -tx1 | tr -d ' \n')")0
      # positions du motif alignees sur un octet (en octets, depuis 0)
      pos=$(printf '%s\n' "$HEX" | awk -v m="$motif" '{ d = 1; while ((i = index(substr($0, d), m)) > 0) { p = d + i - 1; if (p % 2 == 1) printf "%d ", (p - 1) / 2; d = p + 1 } }')
      n=$(echo $pos | wc -w | tr -d ' ')
      [ "$n" -eq 1 ] || { echo "    reglages du jeu : propriete entiere $c trouvee $n fois dans $(basename "$F"), laissee"; continue; }
      o=$((pos + ${#motif} / 2))
      printf "$(printf '\\%03o\\%03o\\%03o\\%03o' $((v & 255)) $((v >> 8 & 255)) $((v >> 16 & 255)) $((v >> 24 & 255)))" |
         dd of="$F.cidre-tmp" bs=1 seek="$o" conv=notrunc 2>/dev/null || { rm -f "$F.cidre-tmp"; echo "    reglages du jeu : echec de la reecriture de $(basename "$F")"; return 1; }
   done <"$V"
   [ "$(wc -c <"$F.cidre-tmp")" -eq "$(wc -c <"$F")" ] || { rm -f "$F.cidre-tmp"; echo "    reglages du jeu : echec de la reecriture de $(basename "$F")"; return 1; }
   remplacer "$nom" ""
   return 0
}

# Formats registre et playerprefs : le jeu range ses reglages dans le registre
# du prefixe, sous HKEY_CURRENT_USER. `fichier` est alors "user.reg" (la ruche
# de l utilisateur, a la racine du prefixe) et `section` la cle, relative a
# HKEY_CURRENT_USER (« Software\Editeur\Jeu »). Une valeur faite de chiffres est
# un entier (REG_DWORD), toute autre une chaine. playerprefs = les PlayerPrefs
# d Unity (PEAK : toutes ses options graphiques) : le nom de la valeur recoit le
# suffixe _h<hachage> qu Unity lui donne, et une chaine est rangee en binaire,
# zero final compris, comme Unity l ecrit. La cle est creee si elle manque (le
# jeu n a jamais tourne : ses reglages valent des le premier lancement). Le
# registre n est ecrit que si aucun wineserver ne tient le prefixe : le serveur
# garde le registre en memoire et recrirait le fichier a sa sortie. Rend 0, 3
# (prefixe en cours d usage : on reessaiera) ou 1.
# Format brut (l appel `ruche`, jamais une fiche) : la donnee est ecrite telle
# qu elle doit figurer dans la ruche (`"win7"`, `dword:0000000a`), et une donnee
# vide retire la valeur ; une cle absente n est creee que s il y a a y poser.
serveur_wine_en_cours() {
   case ${CIDRE_SERVEUR_WINE:-} in oui) return 0 ;; non) return 1 ;; esac
   [ -S "/tmp/.wine-$(id -u)/server-$(stat -f '%Xd-%Xi' "$PFX" 2>/dev/null)/socket" ] && pgrep -x wineserver >/dev/null 2>&1
}
poser_registre() { # <nom affiche>
   if [ -z "$SECTION" ] || printf '%s' "$SECTION" | LC_ALL=C grep -q '[^ -~]\|[]["]'; then
      echo "    reglages du jeu : cle de registre absente ou refusee (« $SECTION »)"; return 1
   fi
   if serveur_wine_en_cours; then
      echo "    reglages du jeu : le prefixe est en cours d'usage (wineserver), registre laisse ; on reessaiera"
      return 3
   fi
   : >"$V.ok"
   while IFS='	' read -r c v; do
      if [ -z "$c" ] || printf '%s' "$c$v" | LC_ALL=C grep -q '[^ -~]'; then
         echo "    reglages du jeu : $c : seuls les caracteres ASCII imprimables sont pris en charge, laisse"; continue
      fi
      case $v in
         *[0-9].[0-9]*|.[0-9]*)
            if [ "$FORMAT" = playerprefs ] && ! printf '%s' "$v" | grep -q '[^0-9.-]'; then
               echo "    reglages du jeu : $c = $v : les nombres decimaux ne sont pas pris en charge, laisse"; continue
            fi ;;
         -[0-9]*|[0-9]*)
            case ${v#-} in
               *[!0-9]*) ;;
               *) [ ${#v} -le 11 ] && [ "$v" -ge -2147483648 ] && [ "$v" -le 4294967295 ] ||
                     { echo "    reglages du jeu : $c = $v est hors bornes, laisse"; continue; } ;;
            esac ;;
      esac
      printf '%s\t%s\n' "$c" "$v" >>"$V.ok"
   done <"$V"
   [ -s "$V.ok" ] || { rm -f "$V.ok"; echo "    reglages du jeu : aucune valeur a poser dans $1 [$SECTION]"; return 1; }
   # la cle passe par l environnement : `awk -v` interpreterait ses barres obliques inverses
   CLE=$SECTION LC_ALL=C awk -v mode="$FORMAT" -v maintenant="$(date +%s)" '
      function echapper(s,   i, ch, r) {
         r = ""
         for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1); if (ch == "\\" || ch == "\"") r = r "\\"; r = r ch }
         return r
      }
      # le hachage qu Unity ajoute au nom d un PlayerPrefs : h = h * 33 ^ c depuis 5381, sur 32 bits
      function hachage(s,   h, i, c, bas, x, b, p) {
         h = 5381
         for (i = 1; i <= length(s); i++) {
            h = (h * 33) % 4294967296; c = ord[substr(s, i, 1)]
            bas = h % 256; h -= bas; x = 0; p = 1
            for (b = 0; b < 8; b++) { if (int(bas / p) % 2 != int(c / p) % 2) x += p; p *= 2 }
            h += x
         }
         return sprintf("%.0f", h)
      }
      function donnee(v,   i, r) {
         if (mode == "brut") return v
         if (v ~ /^-?[0-9]+$/) { v += 0; if (v < 0) v += 4294967296; return sprintf("dword:%08x", v) }
         if (mode != "playerprefs") return "\"" echapper(v) "\""
         r = "hex:"
         for (i = 1; i <= length(v); i++) r = r sprintf("%02x,", ord[substr(v, i, 1)])
         return r "00"
      }
      # le nom d une ligne de valeur `"nom"=...`, en minuscules ; vide pour toute autre ligne
      function nom_de(l,   i, ch, r) {
         if (substr(l, 1, 1) != "\"") return ""
         r = ""
         for (i = 2; i <= length(l); i++) {
            ch = substr(l, i, 1)
            if (ch == "\\") { i++; r = r substr(l, i, 1); continue }
            if (ch == "\"") break
            r = r ch
         }
         return (substr(l, i + 1, 1) == "=") ? tolower(r) : ""
      }
      # les valeurs manquantes, a la fin de la cle (avant sa ligne vide)
      function ajouter(   k) {
         for (k = 1; k <= nv; k++) if (!fait[ordre[k]]) { if (!retire[ordre[k]]) print ligne[ordre[k]]; fait[ordre[k]] = 1 }
      }
      BEGIN { for (i = 32; i < 127; i++) ord[sprintf("%c", i)] = i; cle = ENVIRON["CLE"]; cle_e = tolower(echapper(cle)) }
      NR == FNR {
         i = index($0, "\t"); c = substr($0, 1, i - 1)
         n = (mode == "playerprefs") ? c "_h" hachage(c) : c
         k = tolower(n); if (!(k in ligne)) ordre[++nv] = k
         ligne[k] = "\"" echapper(n) "\"=" donnee(substr($0, i + 1))
         retire[k] = (mode == "brut" && substr($0, i + 1) == ""); if (!retire[k]) a_poser = 1
         next
      }
      # la suite (lignes finissant par \) d une valeur binaire qu on vient de remplacer
      saute { if ($0 !~ /\\$/) saute = 0; next }
      /^\[/ {
         if (dedans) { ajouter(); vue = 1 }
         printf "%s", attente; attente = ""
         k = $0; sub(/^\[/, "", k); sub(/\][^\]]*$/, "", k)
         dedans = (tolower(k) == cle_e)
         print; vide = 0; next
      }
      dedans && $0 == "" { attente = attente "\n"; next }
      {
         printf "%s", attente; attente = ""
         if (dedans) {
            n = nom_de($0)
            if (n != "" && (n in ligne)) {
               if ($0 ~ /\\$/) saute = 1
               if (!fait[n]) { if (!retire[n]) print ligne[n]; fait[n] = 1 }
               next
            }
         }
         print; vide = ($0 == "")
      }
      END {
         if (dedans) { ajouter(); vue = 1 }
         printf "%s", attente
         if (!vue && a_poser) {
            # cle absente : on la cree a la fin (Wine cree les cles parentes en la lisant)
            if (!vide) print ""
            print "[" echapper(cle) "] " maintenant; ajouter(); print ""
         }
      }
   ' "$V.ok" "$F" >"$F.cidre-tmp" || { rm -f "$F.cidre-tmp" "$V.ok"; echo "    reglages du jeu : echec de la reecriture de $1"; return 1; }
   rm -f "$V.ok"
   remplacer "$1" " [$SECTION]"
   return 0
}
poser_playerprefs() { poser_registre "$@"; }

# Une entree : <numero>. Rend 0 (pose ou deja la), 3 (pas maintenant), 1 (erreur).
entree() {
   N=$1
   champ() { printf '%s\n' "$REGL" | awk -F'\t' -v n="$N" -v c="$1" '$1 == n && $2 == c { print $3; exit }'; }
   REL=$(champ fichier); FORMAT=$(champ format); SECTION=$(champ section)
   [ -n "$REL" ] || { echo "    reglages du jeu : entree $N sans fichier, rien a faire"; return 3; }
   case $REL in /*|*..*) echo "    reglages du jeu : chemin refuse ($REL)"; return 1 ;; esac
   FORMAT=${FORMAT:-ini}
   case $FORMAT in ini|gvas|registre|playerprefs) ;; *) echo "    reglages du jeu : format « $FORMAT » inconnu, rien a faire"; return 3 ;; esac
   # ou vit le fichier : le dossier utilisateur du prefixe, ou le prefixe lui-meme
   # pour le registre (user.reg, la ruche de HKEY_CURRENT_USER, et elle seule)
   BASE=$(dirname "$UH")
   case $FORMAT in registre|playerprefs)
      [ "$REL" = user.reg ] || { echo "    reglages du jeu : registre : seul user.reg (HKEY_CURRENT_USER) est pris en charge ($REL)"; return 1; }
      BASE=$PFX ;;
   esac
   # Un `*` dans le chemin vaut pour un dossier qu on ne connait pas d avance
   # (Saved/SaveGames/<identifiant du compte>/) : chaque fichier qui correspond.
   case $REL in
      *'*'*) FICHIERS=$(cd "$BASE" 2>/dev/null && IFS= && for f in $REL; do [ -f "$f" ] && printf '%s\n' "$f"; done) ;;
      *) FICHIERS=$REL; [ -f "$BASE/$REL" ] || FICHIERS= ;;
   esac
   [ -n "$FICHIERS" ] || { echo "    reglages du jeu : $REL absent (premier lancement ?), on reessaiera"; return 3; }

   V=$(mktemp "${TMPDIR:-/tmp}/reglages.XXXXXX")
   printf '%s\n' "$REGL" | awk -F'\t' -v n="$N" '$1 == n && $2 == "valeur" { print $3 "\t" $4 }' >"$V"
   [ -s "$V" ] || { rm -f "$V"; echo "    reglages du jeu : entree $N sans valeur, rien a faire"; return 3; }

   rce=0
   printf '%s\n' "$FICHIERS" >"$V.fichiers"
   while IFS= read -r rel; do
      F="$BASE/$rel"
      "poser_$FORMAT" "$rel" </dev/null; r=$?
      [ $r -eq 1 ] && rce=1
      [ $r -eq 3 ] && [ $rce -ne 1 ] && rce=3
   done <"$V.fichiers"
   rm -f "$V" "$V.fichiers"
   return $rce
}

# Hors fiche : un reglage du prefixe qui n est pas celui d un jeu (la version de
# Windows, tests/version_windows.sh). Memes gardes et meme ecriture qu une entree
# au format registre, sur la ruche et la cle donnees.
if [ "${2:-}" = ruche ]; then
   case ${3:-} in user.reg|system.reg) ;; *) echo "    reglages du jeu : ruche « ${3:-} » refusee (user.reg ou system.reg)"; exit 1 ;; esac
   F="$PFX/$3"; SECTION=${4:-}; FORMAT=brut
   [ -f "$F" ] || { echo "    reglages du jeu : $3 absent du prefixe"; exit 3; }
   V=$(mktemp "${TMPDIR:-/tmp}/reglages.XXXXXX")
   cat >"$V"
   poser_registre "$3"; rc=$?
   rm -f "$V"
   exit $rc
fi

RC=0
for n in $(printf '%s\n' "$REGL" | cut -f1 | awk '!vu[$0]++'); do
   if [ "${2:-}" = nouvelles ]; then
      id=$(printf '%s\n' "$REGL" | awk -F'\t' -v n="$n" '$1 == n && $2 == "id" { print $3; exit }')
      case ",${3:-}," in *",$id,"*) continue ;; esac
      [ -n "$id" ] || continue
   fi
   entree "$n"; rc=$?
   # une erreur l emporte ; sinon un « pas maintenant » suffit a reporter le marqueur
   [ $rc -eq 1 ] && RC=1
   [ $rc -eq 3 ] && [ $RC -ne 1 ] && RC=3
done
exit $RC
