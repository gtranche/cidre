#!/bin/sh
# Resout le profil de lancement d'un jeu : les reglages livres
# (outil-steam/profils.toml) surcharges par ceux de l'utilisateur
# (~/Library/Application Support/Cidre/profils.toml, ecrit par Verger).
#
#   profil_cidre.sh <appid> [env|json]
#
# env  (defaut) : une ligne `cle=valeur` par option resolue
# json          : un objet {"cle": valeur, ...}
#
# Priorite, cle par cle : [appid] utilisateur > [appid] livre > [defaut]
# utilisateur > [defaut] livre. Un fichier absent n'est pas une erreur.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
APPID=${1:-}; FORMAT=${2:-env}
LIVRE="$R/outil-steam/profils.toml"
PERSO=${CIDRE_PROFILS:-$HOME/Library/Application Support/Cidre/profils.toml}

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
      if (format == "json") {
         printf "{"
         for (k = 1; k <= n; k++) {
            c = ordre[k]; v = valeur[c]
            if (estchaine[c] || v !~ /^(true|false|-?[0-9]+)$/) { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            printf "%s\"%s\":%s", (k > 1 ? "," : ""), c, v
         }
         print "}"
      } else
         for (k = 1; k <= n; k++) print ordre[k] "=" valeur[ordre[k]]
   }
'
