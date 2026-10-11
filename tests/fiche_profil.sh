#!/bin/sh
# La base de profils par jeu (profils/<appid>.toml, voir profils/README.md) :
# ou est la fiche d'un jeu, ce qu'elle contient, et sa mise a jour depuis GitHub.
#
#   fiche_profil.sh chemin <appid>          le fichier de la fiche (cache, sinon copie livree) ; rien si aucune
#   fiche_profil.sh plat <appid>            les options de lancement de la fiche, en lignes TOML `cle = valeur`
#                                           ([cidre], plus moteur/anticheat de [jeu] et etat/source de [compat])
#   fiche_profil.sh json <appid>            la fiche en JSON : {"jeu":{},"cidre":{},"compat":{},"reglages_jeu":{}|null,"rapports":n}
#   fiche_profil.sh reglages <appid>        [reglages_jeu] en lignes TAB : fichier/format/section, puis `valeur <TAB> cle <TAB> val`
#   fiche_profil.sh index [json]            l'index de la base : `appid <TAB> nom <TAB> etat <TAB> date <TAB> origine`
#   fiche_profil.sh generer-index           regenere profils/index.toml depuis les fiches du depot (sur la sortie)
#   fiche_profil.sh maj [json]              telecharge l'index puis les fiches dans le cache
#   fiche_profil.sh toml <fichier>          (outil) le fichier a plat : `section <TAB> cle <TAB> type <TAB> valeur`
#
# Le cache (CIDRE_PROFILS_BASE, par defaut ~/Library/Application Support/Cidre/
# profils-base/) prime sur la copie livree ($R/profils/). Pas de python : awk et curl.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
BASE=${CIDRE_PROFILS_BASE:-$CIDRE_DIR/profils-base}
LIVRE=$R/profils
URL=${CIDRE_PROFILS_URL:-https://raw.githubusercontent.com/gtranche/cidre/main/profils/}
CMD=${1:-}; ARG=${2:-}; FORMAT=${3:-}

# Le sous-ensemble de TOML des fiches, a plat : une ligne `section TAB cle TAB
# type TAB valeur` par cle (type : s chaine, b booleen, n nombre). [[rapports]]
# donne les sections rapports.1, rapports.2... Une table en ligne `k = { a = 1 }`
# donne la section `section.k`. LC_ALL=C : on travaille en octets, les accents
# des notes passent tels quels.
toml_plat() {
   LC_ALL=C awk '
      # chaine entre guillemets a partir de v[j] ; POS = indice apres le guillemet fermant
      function lire_chaine(v, j,   s, ch, n) {
         s = ""; n = length(v)
         for (j++; j <= n; j++) {
            ch = substr(v, j, 1)
            if (ch == "\\") { j++; s = s substr(v, j, 1); continue }
            if (ch == "\"") break
            s = s ch
         }
         POS = j + 1; return s
      }
      # une valeur a partir de v[j] : chaine, ou scalaire jusqu a , } # ou la fin ; pose TYPE et POS
      function lire_valeur(v, j,   ch, s, n) {
         n = length(v)
         while (j <= n && substr(v, j, 1) ~ /[ \t]/) j++
         ch = substr(v, j, 1)
         if (ch == "\"") { TYPE = "s"; return lire_chaine(v, j) }
         if (ch == "\047") { s = ""; for (j++; j <= n && substr(v, j, 1) != "\047"; j++) s = s substr(v, j, 1); POS = j + 1; TYPE = "s"; return s }
         s = ""
         for (; j <= n; j++) { ch = substr(v, j, 1); if (ch ~ /[,}#]/) break; s = s ch }
         POS = j; sub(/[ \t]+$/, "", s)
         TYPE = (s ~ /^(true|false)$/) ? "b" : "n"; return s
      }
      # une cle a partir de v[j] : entre guillemets, ou nue ; POS apres la cle
      function lire_cle(v, j,   s, n) {
         n = length(v)
         while (j <= n && substr(v, j, 1) ~ /[ \t]/) j++
         if (substr(v, j, 1) == "\"") return lire_chaine(v, j)
         s = ""
         for (; j <= n && substr(v, j, 1) ~ /[A-Za-z0-9_.-]/; j++) s = s substr(v, j, 1)
         POS = j; return s
      }
      function emettre(sec, cle, type, val) { print sec "\t" cle "\t" type "\t" val }
      { sub(/\r$/, "") }
      /^[ \t]*(#|$)/ { next }
      /^[ \t]*\[\[/ { s = $0; gsub(/^[ \t]*\[\[[ \t]*|[ \t]*\]\].*$/, "", s); section = s "." (++tableau[s]); next }
      /^[ \t]*\[/ { s = $0; gsub(/^[ \t]*\[[ \t]*|[ \t]*\].*$/, "", s); gsub(/"/, "", s); section = s; next }
      {
         cle = lire_cle($0, 1); j = POS
         while (j <= length($0) && substr($0, j, 1) ~ /[ \t]/) j++
         if (cle == "" || substr($0, j, 1) != "=") next
         j++
         while (j <= length($0) && substr($0, j, 1) ~ /[ \t]/) j++
         if (substr($0, j, 1) == "{") {
            # table en ligne : k = v, k = v ... jusqu a }
            j++
            while (1) {
               while (j <= length($0) && substr($0, j, 1) ~ /[ \t,]/) j++
               if (j > length($0) || substr($0, j, 1) == "}") break
               k = lire_cle($0, j); j = POS
               while (j <= length($0) && substr($0, j, 1) ~ /[ \t]/) j++
               if (substr($0, j, 1) != "=") break
               v = lire_valeur($0, j + 1); j = POS
               emettre(section "." cle, k, TYPE, v)
            }
            next
         }
         v = lire_valeur($0, j)
         emettre(section, cle, TYPE, v)
      }
   ' "$1"
}

# un identifiant de jeu sur : chiffres, ou local-... ; rien d autre dans un chemin
id_sur() { case $1 in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac; return 0; }
chemin() { # <appid> : la fiche a lire, cache d abord
   id_sur "$1" || return 1
   for f in "$BASE/$1.toml" "$LIVRE/$1.toml"; do [ -f "$f" ] && { echo "$f"; return 0; }; done
   return 1
}
# JSON : une valeur typee d apres la 3e colonne
json_val() { # <type> <valeur>
   case $1 in
      s) printf '"%s"' "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')" ;;
      b) printf '%s' "$2" ;;
      *) case $2 in ''|*[!0-9.eE+-]*) printf '"%s"' "$2" ;; *) printf '%s' "$2" ;; esac ;;
   esac
}
# TOML : une valeur typee, pour `plat`
toml_val() {
   case $1 in
      s) printf '"%s"' "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')" ;;
      *) printf '%s' "$2" ;;
   esac
}
# un objet JSON depuis les lignes a plat d une section
objet_json() { # <fichier a plat> <section>
   LC_ALL=C awk -F'\t' -v sec="$2" '
      $1 == sec {
         v = $4
         if ($3 == "s" || ($3 == "n" && v !~ /^-?[0-9]+(\.[0-9]+)?$/)) { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
         printf "%s\"%s\":%s", (n++ ? "," : ""), $2, v
      }
      BEGIN { printf "{" } END { printf "}" }' "$1"
}

case $CMD in
   toml) toml_plat "$ARG" ;;
   chemin) chemin "$ARG" ;;
   plat)
      f=$(chemin "$ARG") || exit 0
      toml_plat "$f" | LC_ALL=C awk -F'\t' '
         $1 == "cidre" || ($1 == "jeu" && ($2 == "moteur" || $2 == "anticheat")) || ($1 == "compat" && ($2 == "etat" || $2 == "source")) {
            v = $4
            if ($3 == "s") { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            print $2 " = " v
         }' ;;
   json)
      f=$(chemin "$ARG") || { echo null; exit 0; }
      P=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
      toml_plat "$f" >"$P"
      printf '{"jeu":%s,"cidre":%s,"compat":%s,' "$(objet_json "$P" jeu)" "$(objet_json "$P" cidre)" "$(objet_json "$P" compat)"
      if grep -q '^reglages_jeu	' "$P"; then
         printf '"reglages_jeu":{"fichier":%s,"format":%s,"section":%s,"valeurs":%s},' \
            "$(json_val s "$(awk -F'\t' '$1=="reglages_jeu" && $2=="fichier" {print $4; exit}' "$P")")" \
            "$(json_val s "$(awk -F'\t' '$1=="reglages_jeu" && $2=="format" {print $4; exit}' "$P")")" \
            "$(json_val s "$(awk -F'\t' '$1=="reglages_jeu" && $2=="section" {print $4; exit}' "$P")")" \
            "$(objet_json "$P" reglages_jeu.valeurs)"
      else printf '"reglages_jeu":null,'; fi
      printf '"rapports":%s}\n' "$(awk -F'\t' '$1 ~ /^rapports\.[0-9]+$/ && !vu[$1]++ {n++} END {print n+0}' "$P")"
      rm -f "$P" ;;
   reglages)
      f=$(chemin "$ARG") || exit 0
      toml_plat "$f" | LC_ALL=C awk -F'\t' '
         $1 == "reglages_jeu" { print $2 "\t" $4 }
         $1 == "reglages_jeu.valeurs" { print "valeur\t" $2 "\t" $4 }' ;;
   index)
      # L index du cache, sinon celui de la copie livree ; en texte TAB ou en JSON.
      for f in "$BASE/index.toml" "$LIVRE/index.toml"; do [ -f "$f" ] && break; done
      [ -f "$f" ] || { [ "$ARG" = json ] && echo '[]'; exit 0; }
      [ "$f" = "$BASE/index.toml" ] && origine=cache || origine=livree
      toml_plat "$f" | LC_ALL=C awk -F'\t' -v json="$([ "$ARG" = json ] && echo 1 || echo 0)" -v origine="$origine" '
         function j(v) { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); return "\"" v "\"" }
         $1 != "" { if (!($1 in vu)) { vu[$1] = 1; ordre[++n] = $1 } c[$1, $2] = $4 }
         END {
            if (json) printf "["
            for (k = 1; k <= n; k++) {
               a = ordre[k]
               if (json) printf "%s{\"appid\":%s,\"nom\":%s,\"etat\":%s,\"date\":%s,\"origine\":%s}", (k > 1 ? "," : ""), (a ~ /^[0-9]+$/ ? a : j(a)), j(c[a, "nom"]), j(c[a, "etat"]), j(c[a, "date"]), j(origine)
               else print a "\t" c[a, "nom"] "\t" c[a, "etat"] "\t" c[a, "date"] "\t" origine
            }
            if (json) print "]"
         }' ;;
   generer-index)
      echo "# Index de la base de profils : une table par fiche (nom, etat, date)."
      echo "# Genere par \`sh tests/fiche_profil.sh generer-index > profils/index.toml\` ;"
      echo "# tests/tester_profils.sh verifie qu'il est a jour. C'est lui que \`cidre profils maj\`"
      echo "# telecharge d'abord, pour savoir quelles fiches prendre."
      for f in "$LIVRE"/*.toml; do
         [ -f "$f" ] || continue
         a=$(basename "$f" .toml); [ "$a" = index ] && continue
         toml_plat "$f" | LC_ALL=C awk -F'\t' -v a="$a" '
            ($1 == "jeu" && $2 == "nom") || ($1 == "compat" && ($2 == "etat" || $2 == "date")) { gsub(/\\/, "\\\\", $4); gsub(/"/, "\\\"", $4); c[$2] = $4 }
            END { print ""; print "[" a "]"; print "nom = \"" c["nom"] "\""; print "etat = \"" (c["etat"] == "" ? "non-teste" : c["etat"]) "\""; print "date = \"" c["date"] "\"" }'
      done ;;
   maj)
      # L index d abord, puis chaque fiche qu il nomme, dans un dossier de travail ;
      # on ne remplace le cache qu une fois tout recu. Les fiches sorties de l index
      # quittent le cache. Sans reseau : message, code 1, la copie livree sert.
      command -v curl >/dev/null 2>&1 || { echo "curl introuvable" >&2; exit 1; }
      T=$(mktemp -d "${TMPDIR:-/tmp}/profils-maj.XXXXXX")
      prendre() { curl -fsSL --connect-timeout 10 --max-time 60 -o "$T/$1" "$URL$1" 2>>"$T/erreurs"; }
      if ! prendre index.toml; then
         rm -rf "$T"
         [ "$ARG" = json ] && echo '{"ok":false,"erreur":"index.toml injoignable"}' || echo "base de profils : index injoignable ($URL) ; la copie livree sert" >&2
         exit 1
      fi
      n=0; rates=""
      for a in $(toml_plat "$T/index.toml" | cut -f1 | awk '!vu[$0]++'); do
         id_sur "$a" || continue
         if prendre "$a.toml"; then n=$((n + 1)); else rates="$rates $a"; fi
      done
      mkdir -p "$BASE"
      for f in "$T"/*.toml; do mv -f "$f" "$BASE/$(basename "$f")"; done
      # ce qui n est plus dans l index (ni tout juste recu) s en va
      for f in "$BASE"/*.toml; do
         [ -f "$f" ] || continue
         a=$(basename "$f" .toml); [ "$a" = index ] && continue
         toml_plat "$BASE/index.toml" | cut -f1 | grep -qx "$a" || rm -f "$f"
      done
      date '+%Y-%m-%dT%H:%M:%S%z' >"$BASE/horodatage"
      rm -rf "$T"
      if [ "$ARG" = json ]; then
         printf '{"ok":true,"fiches":%s,"rates":[' "$n"; sep=""
         for a in $rates; do printf '%s"%s"' "$sep" "$a"; sep=","; done
         printf '],"horodatage":"%s"}\n' "$(cat "$BASE/horodatage")"
      else
         echo "base de profils : $n fiche(s) mise(s) a jour dans $BASE"
         [ -z "$rates" ] || echo "  non recues :$rates" >&2
      fi
      [ -z "$rates" ] ;;
   *) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
