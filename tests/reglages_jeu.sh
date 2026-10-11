#!/bin/sh
# Pose les reglages du jeu lui-meme ([reglages_jeu] de sa fiche, cf.
# profils/README.md) dans son fichier de reglages : un jeu qui n'est jouable
# qu'avec ses propres options baissees (Expedition 33 : prereglage Moyen et
# resolution a 66 %, x2,5 mesure). Appele par lancer_depuis_steam.sh avant le
# jeu, tant que le profil utilisateur ne porte pas reglages_jeu_appliques = true.
#
#   reglages_jeu.sh <appid>
#
# Une fiche peut viser plusieurs sections INI (liste [[reglages_jeu]]) : chaque
# entree est traitee a son tour, dans l'ordre de la fiche.
#
# Codes de retour : 0 = tous les reglages poses, ou deja en place (le lanceur
# note alors reglages_jeu_appliques = true et n'y touche plus) ; 3 = rien a faire
# pour l'instant (pas de fiche, pas de [reglages_jeu], ou un fichier du jeu pas
# encore cree : on reessaiera au prochain lancement, les entrees deja posees
# seront alors « deja en place ») ; 1 = erreur.
#
# Seules les cles voulues sont reecrites, si leur valeur differe : les autres
# lignes passent telles quelles, fins de ligne CRLF comprises, les guillemets et
# l'espacement de la ligne sont gardes. Avec `section`, la cle n'est cherchee que
# dans cette section INI, et une cle absente y est ajoutee (la section aussi, a la
# fin, si elle manque). Sans section, une cle absente n'est pas ajoutee. Avant la
# premiere ecriture, le fichier est copie en <fichier>.avant-cidre, jamais ecrase.
set -u
APPID=${1:-}
[ -n "$APPID" ] || exit 3
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}

REGL=$(sh "$R/tests/fiche_profil.sh" reglages "$APPID") || exit 1
[ -n "$REGL" ] || exit 3
UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
[ -n "$UH" ] || { echo "    reglages du jeu : pas de dossier utilisateur dans le prefixe"; exit 3; }

# Une entree : <numero>. Rend 0 (pose ou deja la), 3 (pas maintenant), 1 (erreur).
entree() {
   N=$1
   champ() { printf '%s\n' "$REGL" | awk -F'\t' -v n="$N" -v c="$1" '$1 == n && $2 == c { print $3; exit }'; }
   REL=$(champ fichier); FORMAT=$(champ format); SECTION=$(champ section)
   [ -n "$REL" ] || { echo "    reglages du jeu : entree $N sans fichier, rien a faire"; return 3; }
   case $REL in /*|*..*) echo "    reglages du jeu : chemin refuse ($REL)"; return 1 ;; esac
   [ "${FORMAT:-ini}" = ini ] || { echo "    reglages du jeu : format « $FORMAT » inconnu, rien a faire"; return 3; }
   F="$(dirname "$UH")/$REL"
   [ -f "$F" ] || { echo "    reglages du jeu : $REL absent (premier lancement ?), on reessaiera"; return 3; }

   V=$(mktemp "${TMPDIR:-/tmp}/reglages.XXXXXX")
   printf '%s\n' "$REGL" | awk -F'\t' -v n="$N" '$1 == n && $2 == "valeur" { print $3 "\t" $4 }' >"$V"
   [ -s "$V" ] || { rm -f "$V"; echo "    reglages du jeu : entree $N sans valeur, rien a faire"; return 3; }

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
   ' "$V" "$F" >"$F.cidre-tmp" || { rm -f "$V" "$F.cidre-tmp"; echo "    reglages du jeu : echec de la reecriture de $REL"; return 1; }
   rm -f "$V"

   ou=${SECTION:+ [$SECTION]}
   if cmp -s "$F" "$F.cidre-tmp"; then
      rm -f "$F.cidre-tmp"
      echo "    reglages du jeu : deja en place dans $REL$ou"
   else
      [ -f "$F.avant-cidre" ] || cp -p "$F" "$F.avant-cidre"
      # cat, pas mv : le fichier garde ses droits et son inode
      cat "$F.cidre-tmp" >"$F" && echo "    reglages du jeu : poses dans $REL$ou (copie d'origine : $(basename "$F").avant-cidre)"
      rm -f "$F.cidre-tmp"
   fi
   return 0
}

RC=0
for n in $(printf '%s\n' "$REGL" | cut -f1 | awk '!vu[$0]++'); do
   entree "$n"; rc=$?
   # une erreur l emporte ; sinon un « pas maintenant » suffit a reporter le marqueur
   [ $rc -eq 1 ] && RC=1
   [ $rc -eq 3 ] && [ $RC -ne 1 ] && RC=3
done
exit $RC
