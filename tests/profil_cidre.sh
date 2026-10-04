#!/bin/sh
# Resout le profil de lancement d'un jeu : les reglages livres
# (outil-steam/profils.toml) surcharges par ceux de l'utilisateur
# (~/Library/Application Support/Cidre/profils.toml, ecrit par Verger).
#
#   profil_cidre.sh <id> [env|json|perso]
#   profil_cidre.sh <id> set <cle> <valeur>     ecrit un reglage utilisateur
#   profil_cidre.sh <id> unset [cle]            l'enleve (sans cle : tous ceux du jeu)
#
# env  (defaut) : une ligne `cle=valeur` par option resolue
# json          : un objet {"cle": valeur, ...}
# perso         : en JSON, les seuls reglages que l'utilisateur a poses sur ce jeu
#
# Priorite, cle par cle : [appid] utilisateur > [appid] livre > [defaut]
# utilisateur > [defaut] livre. Un fichier absent n'est pas une erreur.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
APPID=${1:-}; FORMAT=${2:-env}
LIVRE="$R/outil-steam/profils.toml"
PERSO=${CIDRE_PROFILS:-$HOME/Library/Application Support/Cidre/profils.toml}

# Ecriture : on reecrit le fichier utilisateur en ne touchant que la section du
# jeu ; le reste (autres jeux, [defaut], commentaires) passe tel quel.
case $FORMAT in set|unset)
   [ -n "$APPID" ] || { echo "usage : profil_cidre.sh <id> set <cle> <valeur> | unset [cle]" >&2; exit 2; }
   CLE=${3:-}; VAL=${4:-}
   [ "$FORMAT" = unset ] || [ -n "$CLE" ] || { echo "cle manquante" >&2; exit 2; }
   mkdir -p "$(dirname "$PERSO")"
   [ -f "$PERSO" ] || : >"$PERSO"
   awk -v id="$APPID" -v mode="$FORMAT" -v cle="$CLE" -v val="$VAL" '
      function entete(l) { if (l !~ /^[ \t]*\[/) return ""; gsub(/^[ \t]*\[[ \t]*"?|"?[ \t]*\].*$/, "", l); return l }
      function cle_de(l,   i, c) { i = index(l, "="); if (!i || l ~ /^[ \t]*#/) return ""; c = substr(l, 1, i - 1); gsub(/[ \t]/, "", c); return c }
      # fin de la section du jeu : y poser la cle si elle n y etait pas
      function clore() { if (dedans && mode == "set" && !pose) { print cle " = " val; pose = 1 } dedans = 0 }
      {
         e = entete($0)
         if (e != "" || $0 ~ /^[ \t]*\[/) {
            clore()
            if (e == id) {
               vue = 1; dedans = 1
               if (mode == "unset" && cle == "") next    # la section entiere s en va
            }
            print; next
         }
         if (dedans) {
            if (mode == "unset" && cle == "") next
            if (cle_de($0) == cle) {
               if (mode == "set" && !pose) { print cle " = " val; pose = 1 }
               next
            }
            # garder les lignes vides de fin de section apres la cle ajoutee
            if ($0 ~ /^[ \t]*$/ && mode == "set" && !pose) { print cle " = " val; pose = 1 }
         }
         print
      }
      END {
         clore()
         if (mode == "set" && !vue) { if (NR) print ""; print "[" id "]"; print cle " = " val }
      }
   ' "$PERSO" >"$PERSO.tmp" && mv "$PERSO.tmp" "$PERSO"
   exit ;;
esac

for f in "$LIVRE" "$PERSO"; do [ -f "$f" ] && cat "$f"; printf '\n#@fichier-suivant\n'; done |
awk -v appid="$APPID" -v format="$FORMAT" '
   # rang d une valeur : 2 si elle vient de la section du jeu, +1 si du fichier utilisateur
   /^#@fichier-suivant$/ { fichier++; section = ""; next }
   { sub(/\r$/, "") }
   /^[ \t]*(#|$)/ { next }
   /^[ \t]*\[/ {
      section = $0
      gsub(/^[ \t]*\[[ \t]*"?|"?[ \t]*\].*$/, "", section)
      next
   }
   section == "defaut" || (appid != "" && section == appid) {
      i = index($0, "="); if (!i) next
      cle = substr($0, 1, i - 1); val = substr($0, i + 1)
      gsub(/[ \t]/, "", cle); if (cle !~ /^[a-z0-9_]+$/) next
      sub(/^[ \t]+/, "", val)
      if (val ~ /^"/) {
         # chaine : jusqu au premier guillemet non echappe
         s = ""
         for (j = 2; j <= length(val); j++) {
            ch = substr(val, j, 1)
            if (ch == "\\") { s = s substr(val, ++j, 1); continue }
            if (ch == "\"") break
            s = s ch
         }
         val = s; chaine = 1
      } else { sub(/[ \t]*(#.*)?$/, "", val); chaine = 0 }
      rang = (section == "defaut" ? 0 : 2) + fichier
      if (!(cle in valeur)) ordre[++n] = cle
      if (!(cle in valeur) || rang >= rangde[cle]) { valeur[cle] = val; rangde[cle] = rang; estchaine[cle] = chaine }
   }
   END {
      if (format == "json" || format == "perso") {
         printf "{"; premier = 1
         for (k = 1; k <= n; k++) {
            c = ordre[k]; v = valeur[c]
            # perso : seulement ce qui vient de la section du jeu dans le fichier utilisateur
            if (format == "perso" && rangde[c] != 3) continue
            if (estchaine[c] || v !~ /^(true|false|-?[0-9]+)$/) { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            printf "%s\"%s\":%s", (premier ? "" : ","), c, v; premier = 0
         }
         print "}"
      } else
         for (k = 1; k <= n; k++) print ordre[k] "=" valeur[ordre[k]]
   }
'
