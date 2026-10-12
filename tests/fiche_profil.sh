#!/bin/sh
# La base de profils par jeu (profils/<appid>.toml, voir profils/README.md) :
# ou est la fiche d'un jeu, ce qu'elle contient, et sa mise a jour depuis GitHub.
#
#   fiche_profil.sh chemin <appid>          le fichier de la fiche (cache, sinon copie livree) ; rien si aucune
#   fiche_profil.sh plat <appid>            les options de lancement de la fiche, en lignes TOML `cle = valeur`
#                                           ([cidre], plus moteur/anticheat de [jeu] et etat/source de [compat])
#   fiche_profil.sh json <appid>            la fiche en JSON : {"jeu":{},"cidre":{},"compat":{},"reglages_jeu":[...],"variantes":[...],"rapports":n}
#   fiche_profil.sh reglages <appid>        [reglages_jeu] en lignes TAB, une entree (section INI visee) par numero :
#                                           `n TAB fichier|format|section TAB val`, puis `n TAB valeur TAB cle TAB val`
#   fiche_profil.sh variantes <appid>       les conditions `si` des blocs [[machine]] qui s'appliquent ici, une par ligne
#   fiche_profil.sh index [json]            l'index de la base : `appid <TAB> nom <TAB> etat <TAB> date <TAB> origine`
#   fiche_profil.sh generer-index           regenere profils/index.toml depuis les fiches du depot (sur la sortie)
#   fiche_profil.sh maj [json]              telecharge l'index puis les fiches dans le cache
#   fiche_profil.sh toml <fichier>          (outil) le fichier a plat : `section <TAB> cle <TAB> type <TAB> valeur`
#
# `plat`, `json` et `reglages` rendent la fiche telle qu'elle vaut sur CETTE
# machine : les blocs [[machine]] dont la condition `si` est vraie (tests/machine.sh)
# sont fondus dans [cidre] et [[reglages_jeu]], les autres ignores. `toml` rend
# le fichier tel quel.
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
# donne les sections rapports.1, rapports.2... ; sous un [[machine]], [machine.cidre]
# donne machine.N.cidre et [[machine.reglages_jeu]] machine.N.reglages_jeu.1, .2...
# Une table en ligne `k = { a = 1 }` donne la section `section.k`. LC_ALL=C : on
# travaille en octets, les accents des notes passent tels quels.
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
      # le chemin d une section, chaque tableau de tables deja ouvert sur ce chemin
      # remplace par son dernier element : [a.b] apres un [[a]] est a.N.b, et
      # [a.b.c] apres un [[a.b]] est a.N.b.M.c
      function chemin(s,   n, c, k, p) {
         n = split(s, c, "."); p = ""
         for (k = 1; k <= n; k++) { p = (k == 1 ? c[k] : p "." c[k]); if (k < n && (p in tableau)) p = p "." tableau[p] }
         return p
      }
      { sub(/\r$/, "") }
      /^[ \t]*(#|$)/ { next }
      /^[ \t]*\[\[/ { s = $0; gsub(/^[ \t]*\[\[[ \t]*|[ \t]*\]\].*$/, "", s); s = chemin(s); section = s "." (++tableau[s]); next }
      /^[ \t]*\[/ {
         s = $0; gsub(/^[ \t]*\[[ \t]*|[ \t]*\].*$/, "", s); gsub(/"/, "", s)
         section = chemin(s); next
      }
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

# Une fiche a plat telle qu elle vaut sur cette machine. Un bloc [[machine]] porte
# une condition `si` (tests/machine.sh) ; s il s applique, son [machine.cidre]
# s ajoute a [cidre] et ses [[machine.reglages_jeu]] aux [[reglages_jeu]], dans
# l ordre de la fiche : la derniere valeur d une cle gagne, et les entrees de
# reglages qui visent le meme fichier et la meme section n en font qu une. Les
# sections machine.* ne sortent pas ; `machine.N TAB si` reste pour les blocs
# appliques (commande `variantes`). Sans bloc [[machine]], rien ne change.
fiche_plat() { # <fiche>
   B=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
   toml_plat "$1" >"$B"
   if ! LC_ALL=C grep -q '^machine\.' "$B"; then cat "$B"; rm -f "$B"; return; fi
   ok=" "
   for n in $(LC_ALL=C awk -F'\t' '$1 ~ /^machine\.[0-9]+$/ && $2 == "si" { print substr($1, 9) }' "$B"); do
      si=$(LC_ALL=C awk -F'\t' -v s="machine.$n" '$1 == s && $2 == "si" { print $4; exit }' "$B")
      sh "$R/tests/machine.sh" si "$si" 2>/dev/null && ok="$ok$n "
   done
   LC_ALL=C awk -F'\t' -v ok="$ok" '
      {
         sec = $1
         if (sec ~ /^machine\./) {
            n = sec; sub(/^machine\./, "", n); sub(/\..*$/, "", n)
            if (index(ok, " " n " ") == 0) next
            if (sec == "machine." n) { if ($2 == "si") print; next }
            sub(/^machine\.[0-9]+\./, "", sec)
            if (sec != "cidre" && sec !~ /^reglages_jeu(\.[0-9]+)?(\.valeurs)?$/) next
            sec = sec "@" n    # les entrees d un bloc ne se confondent pas avec celles de la base
         }
         if (sec ~ /^cidre(@|$)/) {
            # une cle de [cidre] : place de sa premiere apparition, valeur de la derniere
            if (!($2 in cv)) co[++cn] = $2
            cv[$2] = $4; ct[$2] = $3; next
         }
         if (sec ~ /^reglages_jeu(\.[0-9]+)?(\.valeurs)?(@[0-9]+)?$/) {
            val = sub(/\.valeurs/, "", sec)
            if (!(sec in vue)) { vue[sec] = 1; ordre[++no] = sec }
            if (val) { cles[sec, ++nc[sec]] = $2; vals[sec, nc[sec]] = $4; types[sec, nc[sec]] = $3 }
            else attr[sec, $2] = $4
            next
         }
         print
      }
      END {
         for (k = 1; k <= cn; k++) print "cidre\t" co[k] "\t" ct[co[k]] "\t" cv[co[k]]
         # les entrees de reglages, dans l ordre : celles qui visent le meme fichier et
         # la meme section INI n en font qu une, la derniere valeur d une cle gagne
         for (k = 1; k <= no; k++) {
            sec = ordre[k]; id = attr[sec, "fichier"] SUBSEP attr[sec, "section"]
            if (!(id in parid)) { parid[id] = ++en; ef[en] = attr[sec, "fichier"]; es[en] = attr[sec, "section"] }
            e = parid[id]
            if (attr[sec, "format"] != "") efo[e] = attr[sec, "format"]
            for (j = 1; j <= nc[sec]; j++) {
               c = cles[sec, j]
               if (!((e, c) in vv)) vo[e, ++vn[e]] = c
               vv[e, c] = vals[sec, j]; vt[e, c] = types[sec, j]
            }
         }
         for (e = 1; e <= en; e++) {
            if (ef[e] != "") print "reglages_jeu." e "\tfichier\ts\t" ef[e]
            if (efo[e] != "") print "reglages_jeu." e "\tformat\ts\t" efo[e]
            if (es[e] != "") print "reglages_jeu." e "\tsection\ts\t" es[e]
            for (k = 1; k <= vn[e]; k++) print "reglages_jeu." e ".valeurs\t" vo[e, k] "\t" vt[e, vo[e, k]] "\t" vv[e, vo[e, k]]
         }
      }' "$B"
   rm -f "$B"
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
# les sections de reglages d une fiche a plat : `reglages_jeu` (forme simple) ou
# `reglages_jeu.1`, `reglages_jeu.2`... ([[reglages_jeu]]), dans l ordre
reglages_entrees() { # <fichier a plat>
   LC_ALL=C awk -F'\t' '$1 ~ /^reglages_jeu(\.[0-9]+)?$/ && !vu[$1]++ { print $1 }' "$1"
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
      fiche_plat "$f" | LC_ALL=C awk -F'\t' '
         $1 == "cidre" || ($1 == "jeu" && ($2 == "moteur" || $2 == "anticheat")) || ($1 == "compat" && ($2 == "etat" || $2 == "source")) {
            v = $4
            if ($3 == "s") { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            print $2 " = " v
         }' ;;
   json)
      f=$(chemin "$ARG") || { echo null; exit 0; }
      P=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
      fiche_plat "$f" >"$P"
      printf '{"jeu":%s,"cidre":%s,"compat":%s,' "$(objet_json "$P" jeu)" "$(objet_json "$P" cidre)" "$(objet_json "$P" compat)"
      # "reglages_jeu" : toujours un tableau, une entree par section visee ([reglages_jeu]
      # simple = une entree ; [[reglages_jeu]] = une par element), vide s il n y en a pas
      printf '"reglages_jeu":['; sep=""
      for e in $(reglages_entrees "$P"); do
         printf '%s{"fichier":%s,"format":%s,"section":%s,"valeurs":%s}' "$sep" \
            "$(json_val s "$(awk -F'\t' -v s="$e" '$1==s && $2=="fichier" {print $4; exit}' "$P")")" \
            "$(json_val s "$(awk -F'\t' -v s="$e" '$1==s && $2=="format" {print $4; exit}' "$P")")" \
            "$(json_val s "$(awk -F'\t' -v s="$e" '$1==s && $2=="section" {print $4; exit}' "$P")")" \
            "$(objet_json "$P" "$e.valeurs")"
         sep=","
      done
      printf '],"variantes":['; sep=""
      # les conditions des blocs [[machine]] appliques ici (vide le plus souvent)
      LC_ALL=C awk -F'\t' '$1 ~ /^machine\.[0-9]+$/ && $2 == "si" { print $4 }' "$P" >"$P.v"
      while IFS= read -r v; do printf '%s%s' "$sep" "$(json_val s "$v")"; sep=","; done <"$P.v"
      rm -f "$P.v"
      printf '],'
      printf '"rapports":%s}\n' "$(awk -F'\t' '$1 ~ /^rapports\.[0-9]+$/ && !vu[$1]++ {n++} END {print n+0}' "$P")"
      rm -f "$P" ;;
   reglages)
      # Une entree = une section INI visee : [reglages_jeu] simple (entree 1) ou
      # chaque element d un [[reglages_jeu]]. Lignes `n TAB fichier|format|section
      # TAB val` et `n TAB valeur TAB cle TAB val`.
      f=$(chemin "$ARG") || exit 0
      P=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
      fiche_plat "$f" >"$P"
      n=0
      for e in $(reglages_entrees "$P"); do
         n=$((n + 1))
         LC_ALL=C awk -F'\t' -v s="$e" -v n="$n" '
            $1 == s { print n "\t" $2 "\t" $4 }
            $1 == s ".valeurs" { print n "\tvaleur\t" $2 "\t" $4 }' "$P"
      done
      rm -f "$P" ;;
   variantes)
      f=$(chemin "$ARG") || exit 0
      fiche_plat "$f" | LC_ALL=C awk -F'\t' '$1 ~ /^machine\.[0-9]+$/ && $2 == "si" { print $4 }' ;;
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
