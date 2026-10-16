#!/bin/sh
# Resout le profil de lancement d'un jeu : les reglages generaux livres
# (outil-steam/profils.toml, [defaut]), la fiche du jeu dans la base de profils
# (profils/<appid>.toml, section [cidre] ; cache telecharge par `cidre profils
# maj`, sinon copie livree -- cf. profils/README.md et tests/fiche_profil.sh),
# surcharges par ceux de l'utilisateur (~/Library/Application Support/Cidre/
# profils.toml, ecrit par `cidre set` et Verger).
#
#   profil_cidre.sh <id> [env|json|perso]
#   profil_cidre.sh <id> set <cle> <valeur>     ecrit un reglage utilisateur
#   profil_cidre.sh <id> unset [cle]            l'enleve (sans cle : tous ceux du jeu)
#
# env  (defaut) : une ligne `cle=valeur` par option resolue
# json          : un objet {"cle": valeur, ...}
# perso         : en JSON, les seuls reglages que l'utilisateur a poses sur ce jeu
#
# Priorite, cle par cle : [appid] utilisateur > fiche de la base ([cidre]) >
# [defaut] utilisateur > [defaut] livre. Un fichier absent n'est pas une erreur.
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

# Trois fichiers a la suite : les reglages livres, la fiche du jeu dans la base de
# profils (sa section [cidre], aplatie par fiche_profil.sh en une section [appid]),
# le profil utilisateur. Le rang d une valeur : 2 si elle vient de la section du
# jeu, +1 si elle vient du fichier utilisateur ; a rang egal, le dernier gagne.
{
   [ -f "$LIVRE" ] && cat "$LIVRE"; printf '\n#@fichier-suivant\n'
   case $APPID in ''|defaut) ;; *) echo "[$APPID]"; sh "$R/tests/fiche_profil.sh" plat "$APPID" 2>/dev/null ;; esac
   printf '\n#@fichier-suivant\n'
   [ -f "$PERSO" ] && cat "$PERSO"; printf '\n#@fichier-suivant\n'
} |
awk -v appid="$APPID" -v format="$FORMAT" -v perso=2 '
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
      rang = (section == "defaut" ? 0 : 2) + (fichier == perso)
      if (!(cle in valeur)) ordre[++n] = cle
      if (!(cle in valeur) || rang >= rangde[cle]) { valeur[cle] = val; rangde[cle] = rang; estchaine[cle] = chaine }
   }
   END {
      # D3D12 seulement : le vrai D3D12 (vkd3d-proton, option dx12) par defaut. Le
      # d3d12 integre a Wine echoue a tous les Feature Levels sur KosmicKrisp, et un
      # jeu sans autre API ne demarrerait pas. Un jeu qui offre aussi D3D11 ou
      # Vulkan garde dx12 = false : son repli prend l API plus rapide (DXMT).
      # api_disponibles vient du catalogue importe (PCGamingWiki) : il ne sert qu en
      # l absence de choix. Un choix explicite passe avant : dx12 pose par la fiche
      # ou l utilisateur (rang >= 1), d3d11 pose pour ce jeu (rang >= 2 ; celui de
      # [defaut] n en est pas un), ou une api de la fiche autre que d3d12 (Exp33 :
      # api = "d3d11", d3d11 = "dxmt", que PCGW donne pour D3D12 seulement).
      choix = ("dx12" in valeur && rangde["dx12"] >= 1) || ("d3d11" in valeur && rangde["d3d11"] >= 2) \
         || ("api" in valeur && rangde["api"] >= 2 && valeur["api"] != "d3d12")
      if (valeur["api_disponibles"] == "d3d12" && !choix) {
         if (!("dx12" in valeur)) ordre[++n] = "dx12"
         valeur["dx12"] = "true"; estchaine["dx12"] = 0
      }
      if (format == "json" || format == "perso") {
         printf "{"; premier = 1
         for (k = 1; k <= n; k++) {
            c = ordre[k]; v = valeur[c]
            # perso : seulement ce qui vient de la section du jeu dans le fichier utilisateur
            # (pour `defaut` : la section [defaut] du fichier utilisateur, rang 1)
            if (format == "perso" && rangde[c] != (appid == "defaut" ? 1 : 3)) continue
            if (estchaine[c] || v !~ /^(true|false|-?[0-9]+)$/) { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            printf "%s\"%s\":%s", (premier ? "" : ","), c, v; premier = 0
         }
         print "}"
      } else
         for (k = 1; k <= n; k++) print ordre[k] "=" valeur[ordre[k]]
   }
'
