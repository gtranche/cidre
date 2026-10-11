#!/bin/sh
# Pose les reglages du jeu lui-meme ([reglages_jeu] de sa fiche, cf.
# profils/README.md) dans son fichier de reglages : un jeu qui n'est jouable
# qu'avec ses propres options baissees (Expedition 33 : prereglage Moyen et
# resolution a 66 %, x2,5 mesure). Appele par lancer_depuis_steam.sh avant le
# jeu, tant que le profil utilisateur ne porte pas reglages_jeu_appliques = true.
#
#   reglages_jeu.sh <appid>
#
# Codes de retour : 0 = reglages poses, ou deja en place (le lanceur note alors
# reglages_jeu_appliques = true et n'y touche plus) ; 3 = rien a faire pour
# l'instant (pas de fiche, pas de [reglages_jeu], ou fichier du jeu pas encore
# cree : on reessaiera au prochain lancement) ; 1 = erreur.
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
champ() { printf '%s\n' "$REGL" | awk -F'\t' -v c="$1" '$1 == c { print $2; exit }'; }
REL=$(champ fichier); FORMAT=$(champ format); SECTION=$(champ section)
[ -n "$REL" ] || { echo "    reglages du jeu : [reglages_jeu] sans fichier, rien a faire"; exit 3; }
case $REL in /*|*..*) echo "    reglages du jeu : chemin refuse ($REL)"; exit 1 ;; esac
[ "${FORMAT:-ini}" = ini ] || { echo "    reglages du jeu : format « $FORMAT » inconnu, rien a faire"; exit 3; }

UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
[ -n "$UH" ] || { echo "    reglages du jeu : pas de dossier utilisateur dans le prefixe"; exit 3; }
F="$(dirname "$UH")/$REL"
[ -f "$F" ] || { echo "    reglages du jeu : $REL absent (premier lancement ?), on reessaiera"; exit 3; }

V=$(mktemp "${TMPDIR:-/tmp}/reglages.XXXXXX")
printf '%s\n' "$REGL" | awk -F'\t' '$1 == "valeur" { print $2 "\t" $3 }' >"$V"
[ -s "$V" ] || { rm -f "$V"; echo "    reglages du jeu : aucune valeur, rien a faire"; exit 3; }

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
' "$V" "$F" >"$F.cidre-tmp" || { rm -f "$V" "$F.cidre-tmp"; echo "    reglages du jeu : echec de la reecriture de $REL"; exit 1; }
rm -f "$V"

if cmp -s "$F" "$F.cidre-tmp"; then
   rm -f "$F.cidre-tmp"
   echo "    reglages du jeu : deja en place dans $REL"
else
   [ -f "$F.avant-cidre" ] || cp -p "$F" "$F.avant-cidre"
   # cat, pas mv : le fichier garde ses droits et son inode
   cat "$F.cidre-tmp" >"$F" && echo "    reglages du jeu : poses dans $REL (copie d'origine : $(basename "$F").avant-cidre)"
   rm -f "$F.cidre-tmp"
fi
exit 0
