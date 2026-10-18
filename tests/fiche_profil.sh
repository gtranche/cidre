#!/bin/sh
# La base de profils par jeu (profils/<appid>.toml, voir profils/README.md) :
# ou est la fiche d'un jeu, ce qu'elle contient, et sa mise a jour depuis GitHub.
#
#   fiche_profil.sh chemin <appid>          le fichier de la fiche (cache, sinon copie livree, sinon fiche
#                                           provisoire) ; rien si aucune
#   fiche_profil.sh plat <appid>            les options de lancement de la fiche, en lignes TOML `cle = valeur`
#                                           ([cidre], plus moteur/anticheat de [jeu] et etat/source de [compat])
#   fiche_profil.sh json <appid>            la fiche en JSON : {"jeu":{},"cidre":{},"compat":{},"protondb":{}|null,
#                                           "reglages_jeu":[...],"variantes":[...],"compat_reference":{},"compat_machines":[...],
#                                           "origine":"cache|livree|provisoire","rapports":n} ; "compat" est celle de CETTE machine
#   fiche_profil.sh reglages <appid>        [reglages_jeu] en lignes TAB, une entree (section INI visee) par numero :
#                                           `n TAB fichier|format|section|id|creer TAB val`, puis `n TAB valeur TAB cle TAB val`
#   fiche_profil.sh compat <appid>          la compatibilite sur cette machine (`cle TAB valeur`), puis les entrees par
#                                           famille de Mac : `machines TAB nom TAB voie TAB etat TAB applique`
#   fiche_profil.sh variantes <appid>       les conditions `si` des blocs [[machine]] qui s'appliquent ici, une par ligne
#   fiche_profil.sh index [json]            l'index de la base : `appid <TAB> nom <TAB> etat <TAB> date <TAB> origine`
#   fiche_profil.sh generer-index [dossier] regenere l'index des fiches du depot, ou de ce dossier (sur la sortie)
#   fiche_profil.sh maj [json]              met le cache a jour : l'archive de la base (une requete), sinon
#                                           l'index puis les fiches une a une
#   fiche_profil.sh provisoire <appid>      jeu sans fiche : en ecrit une provisoire (resume ProtonDB, nom et
#                                           plateformes du magasin Steam) ; rien s'il a deja une fiche
#   fiche_profil.sh toml <fichier>          (outil) le fichier a plat : `section <TAB> cle <TAB> type <TAB> valeur`
#
# Les cles de [cidre] sont celles de outil-steam/profils.toml. Une liste s'y ecrit
# en chaine, elements separes par des espaces (le sous-ensemble de TOML reste plat) :
#   tso_sans = "UnityPlayer.dll"                  module exempte du TSO de FEX (0179)
#   tso_sans = "UnityPlayer.dll GameAssembly.dll"  plusieurs
#   tso_sans = "UnityPlayer.dll;1522d00-15246a0"   une plage seulement (syntaxe de FEX)
#
# `plat`, `json`, `reglages` et `compat` rendent la fiche telle qu'elle vaut sur
# CETTE machine : les blocs [[machine]] dont la condition `si` est vraie
# (tests/machine.sh) sont fondus dans [cidre] et [[reglages_jeu]], les autres
# ignores ; l'entree [[compat.machines]] qui vaut ici remplace [compat]. `toml`
# rend le fichier tel quel.
#
# Le cache (CIDRE_PROFILS_BASE, par defaut ~/Library/Application Support/Cidre/
# profils-base/) prime sur la copie livree ($R/profils/), sauf quand celle-ci est
# plus recente que lui (livree_plus_recente) ; tous deux priment sur les fiches
# provisoires (CIDRE_PROFILS_PROVISOIRES, par defaut .../Cidre/profils-provisoires/).
# Pas de python : awk et curl.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
BASE=${CIDRE_PROFILS_BASE:-$CIDRE_DIR/profils-base}
LIVRE=$R/profils
PROV=${CIDRE_PROFILS_PROVISOIRES:-$CIDRE_DIR/profils-provisoires}
URL=${CIDRE_PROFILS_URL:-https://raw.githubusercontent.com/gtranche/cidre/main/profils/}
# la base entiere en une archive (tar.gz a plat : index.toml + <appid>.toml), publiee
# par .github/workflows/profils.yml ; vide = pas d archive (fiches une a une)
ARCHIVE=${CIDRE_PROFILS_ARCHIVE-https://github.com/gtranche/cidre/releases/download/profils-base/profils-base.tar.gz}
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
#
# La compatibilite par famille de Mac ([[compat.machines]], une entree par groupe
# de machines et par voie de rendu, chacune sa condition `si`) : chaque entree
# sort avec `applique` (vrai ou faux ici). Les entrees qui s appliquent et
# parlent de la voie de la fiche sur cette machine (`voie` absente, ou egale a
# d3d12 si [cidre] fondu dit dx12 = true, sinon a son d3d11, sinon au `voie` de
# [compat]) remplacent [compat] tout entier, la derniere gagnant ; `pour` dit
# alors laquelle (son `nom`, sinon sa condition). Le [compat] ecrit reste sous
# compat.reference.
fiche_plat() { # <fiche>
   B=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
   toml_plat "$1" >"$B"
   if ! LC_ALL=C grep -q '^machine\.\|^compat\.machines\.' "$B"; then cat "$B"; rm -f "$B"; return; fi
   # les faits que nomment les conditions, lus une fois (un appel a Metal coute
   # ~0,1 s) et passes aux evaluations comme s ils etaient imposes ; ceux que
   # l utilisateur impose deja passent devant
   faits=$(LC_ALL=C awk -F'\t' '($1 ~ /^machine\.[0-9]+$/ || $1 ~ /^compat\.machines\.[0-9]+$/) && $2 == "si" { n = split($4, t, " "); for (k = 1; k <= n; k++) if (t[k] ~ /^[a-z_]+$/ && t[k] != "et" && !vu[t[k]]++) print t[k] }' "$B")
   lus=""
   for f in $faits; do
      case $f in puce|macos_version) continue ;; esac
      case " ${CIDRE_MACHINE:-} " in *" $f="*) continue ;; esac
      lus="$lus $(sh "$R/tests/machine.sh" "$f" 2>/dev/null | tr -d ' ')"
   done
   ok=" "; okc=" "
   for n in $(LC_ALL=C awk -F'\t' '$1 ~ /^machine\.[0-9]+$/ && $2 == "si" { print substr($1, 9) }' "$B"); do
      si=$(LC_ALL=C awk -F'\t' -v s="machine.$n" '$1 == s && $2 == "si" { print $4; exit }' "$B")
      CIDRE_MACHINE="${CIDRE_MACHINE:-}$lus" sh "$R/tests/machine.sh" si "$si" 2>/dev/null && ok="$ok$n "
   done
   for n in $(LC_ALL=C awk -F'\t' '$1 ~ /^compat\.machines\.[0-9]+$/ && $2 == "si" { print substr($1, 17) }' "$B"); do
      si=$(LC_ALL=C awk -F'\t' -v s="compat.machines.$n" '$1 == s && $2 == "si" { print $4; exit }' "$B")
      CIDRE_MACHINE="${CIDRE_MACHINE:-}$lus" sh "$R/tests/machine.sh" si "$si" 2>/dev/null && okc="$okc$n "
   done
   LC_ALL=C awk -F'\t' -v ok="$ok" -v okc="$okc" '
      {
         sec = $1
         if (sec == "compat") {
            # [compat] sort a la fin, une fois les entrees par famille vues
            if (!($2 in rv)) ro[++rn] = $2
            rv[$2] = $4; rt[$2] = $3; next
         }
         if (sec ~ /^compat\.machines\.[0-9]+$/) {
            n = substr(sec, 17)
            if (!(n in vuc)) { vuc[n] = 1; co_n[++ncm] = n }
            mv[n, $2] = $4; mt[n, $2] = $3; mo[n, ++mn[n]] = $2
            print; next
         }
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
         # la compat ici : la voie de la fiche sur cette machine, puis les entrees
         # par famille qui s appliquent et parlent de cette voie
         voie = (cv["dx12"] == "true") ? "d3d12" : (("d3d11" in cv) ? cv["d3d11"] : rv["voie"])
         choisie = 0
         for (k = 1; k <= ncm; k++) {
            n = co_n[k]; a = (index(okc, " " n " ") > 0)
            print "compat.machines." n "\tapplique\tb\t" (a ? "true" : "false")
            if (a && (((n, "voie") in mv) ? (mv[n, "voie"] == voie) : 1)) choisie = n
         }
         for (k = 1; k <= rn; k++) print "compat.reference\t" ro[k] "\t" rt[ro[k]] "\t" rv[ro[k]]
         if (!choisie) { for (k = 1; k <= rn; k++) print "compat\t" ro[k] "\t" rt[ro[k]] "\t" rv[ro[k]] }
         else {
            n = choisie
            print "compat\tpour\ts\t" (((n, "nom") in mv) ? mv[n, "nom"] : mv[n, "si"])
            for (j = 1; j <= mn[n]; j++) { c = mo[n, j]; if (c != "nom" && c != "si" && c != "options") print "compat\t" c "\t" mt[n, c] "\t" mv[n, c] }
            if (!((n, "voie") in mv) && ("voie" in rv)) print "compat\tvoie\ts\t" rv["voie"]
         }
         # les entrees de reglages, dans l ordre : celles qui visent le meme fichier et
         # la meme section INI n en font qu une, la derniere valeur d une cle gagne.
         # Une entree a `id` reste a part (son id avec elle) : posee une fois sur un
         # jeu deja marque, elle ne doit ni perdre son id ni entrainer les autres.
         for (k = 1; k <= no; k++) {
            sec = ordre[k]; id = attr[sec, "fichier"] SUBSEP attr[sec, "section"] SUBSEP attr[sec, "id"]
            if (!(id in parid)) { parid[id] = ++en; ef[en] = attr[sec, "fichier"]; es[en] = attr[sec, "section"]; ei[en] = attr[sec, "id"] }
            e = parid[id]
            if (attr[sec, "format"] != "") efo[e] = attr[sec, "format"]
            if (attr[sec, "creer"] != "") ecr[e] = attr[sec, "creer"]
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
            if (ei[e] != "") print "reglages_jeu." e "\tid\ts\t" ei[e]
            if (ecr[e] != "") print "reglages_jeu." e "\tcreer\tb\t" ecr[e]
            for (k = 1; k <= vn[e]; k++) print "reglages_jeu." e ".valeurs\t" vo[e, k] "\t" vt[e, vo[e, k]] "\t" vv[e, vo[e, k]]
         }
      }' "$B"
   rm -f "$B"
}

# un identifiant de jeu sur : chiffres, ou local-... ; rien d autre dans un chemin
id_sur() { case $1 in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac; return 0; }
empreinte() { md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -c1-32; }
# La copie livree d une fiche est-elle plus recente que sa copie en cache ? Le
# cache vient d une archive batie sur les fiches du depot, puis enrichie par
# l import : index-depot.toml (tests/outils/index_depot.py) y dit de quelle
# version du depot part chaque fiche, et quelles versions l ont precedee. Une
# copie livree connue (cette version, ou une plus ancienne) laisse le cache
# servir ; inconnue (corrigee depuis la derniere archive, modifiee localement,
# ou absente de l index), elle sert. Un cache sans index-depot.toml (archive
# d avant, ou fiches une a une) : la copie livree sert si elle est plus recente
# que la derniere mise a jour (horodatage).
livree_plus_recente() { # <appid>
   cmp -s "$BASE/$1.toml" "$LIVRE/$1.toml" && return 1
   [ -f "$BASE/index-depot.toml" ] || { [ "$LIVRE/$1.toml" -nt "$BASE/horodatage" ]; return; }
   LC_ALL=C awk -v a="[$1]" -v e="$(empreinte "$LIVRE/$1.toml")" '
      /^\[/ { if (dedans) exit; dedans = ($0 == a); next }
      dedans && /^(empreinte|anciennes)[ \t]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); if (index(" " v " ", " " e " ")) { connue = 1; exit } }
      END { exit connue }' "$BASE/index-depot.toml"
}
chemin() { # <appid> : la fiche a lire, cache d abord, sauf copie livree plus recente
   id_sur "$1" || return 1
   if [ -f "$BASE/$1.toml" ] && [ -f "$LIVRE/$1.toml" ] && livree_plus_recente "$1"; then echo "$LIVRE/$1.toml"; return 0; fi
   for f in "$BASE/$1.toml" "$LIVRE/$1.toml" "$PROV/$1.toml"; do [ -f "$f" ] && { echo "$f"; return 0; }; done
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

# `maj` par l archive : telechargee, verifiee (rien que des fiches a plat, chaque
# fiche de l index presente), deballee a cote du cache puis echangee avec lui d un
# coup. Les fiches provisoires que la base couvre desormais s en vont. rc 0 = cache
# remplace ; 1 = archive absente ou refusee (l appelant passe aux fiches une a une).
maj_archive() {
   A=$(mktemp -d "${TMPDIR:-/tmp}/profils-archive.XXXXXX")
   code=$(curl -sS -L --connect-timeout 10 --max-time 300 -o "$A/base.tar.gz" -w '%{http_code}' "$ARCHIVE" 2>"$A/erreurs"); rc=$?
   case $rc:$code in
      0:200|0:000) ;;
      *) echo "base de profils : archive indisponible ($rc/$code, $ARCHIVE) ; fiches une a une" >&2; rm -rf "$A"; return 1 ;;
   esac
   if ! tar -tzf "$A/base.tar.gz" >"$A/liste" 2>/dev/null || [ ! -s "$A/liste" ] \
      || LC_ALL=C grep -qv '^\(\./\)\{0,1\}[A-Za-z0-9_-]*\.toml$' "$A/liste" \
      || ! LC_ALL=C grep -q '^\(\./\)\{0,1\}index\.toml$' "$A/liste"; then
      echo "base de profils : archive refusee (contenu inattendu) ; fiches une a une" >&2; rm -rf "$A"; return 1
   fi
   mkdir -p "$(dirname "$BASE")"
   N="$BASE.nouveau.$$"; rm -rf "$N"; mkdir -p "$N"
   if ! tar -xzf "$A/base.tar.gz" -C "$N" 2>/dev/null; then
      echo "base de profils : archive illisible ; fiches une a une" >&2; rm -rf "$A" "$N"; return 1
   fi
   # l index ne va jamais sans les fiches qu il nomme
   manque=$(toml_plat "$N/index.toml" | cut -f1 | awk '!vu[$0]++' | while read -r a; do [ -f "$N/$a.toml" ] || echo "$a"; done | head -3)
   if [ -n "$manque" ]; then
      echo "base de profils : archive incomplete (pas de fiche pour $(echo $manque)) ; fiches une a une" >&2
      rm -rf "$A" "$N"; return 1
   fi
   # fiches nouvelles ou changees : empreintes de l ancien index contre le nouveau
   n=$( { [ -f "$BASE/index.toml" ] && toml_plat "$BASE/index.toml" | sed 's/^/A\t/'; toml_plat "$N/index.toml" | sed 's/^/N\t/'; } \
      | LC_ALL=C awk -F'\t' '$1 == "N" { ids[$2] = 1 } $3 == "empreinte" { e[$1, $2] = $5 }
         END { for (a in ids) { t++; if (e["A", a] != e["N", a]) c++ } print c + 0, t + 0 }')
   total=${n#* }; n=${n% *}
   date '+%Y-%m-%dT%H:%M:%S%z' >"$N/horodatage"
   if [ -d "$BASE" ]; then mv "$BASE" "$BASE.ancien.$$" && mv "$N" "$BASE" && rm -rf "$BASE.ancien.$$"
   else mv "$N" "$BASE"; fi
   for f in "$PROV"/*.toml; do [ -f "$f" ] && [ -f "$BASE/$(basename "$f")" ] && rm -f "$f"; done
   rm -rf "$A"
   if [ "$FORMAT" = json ] || [ "$ARG" = json ]; then
      printf '{"ok":true,"mode":"archive","fiches":%s,"gardees":%s,"total":%s,"rates":[],"horodatage":"%s"}\n' "$n" "$((total - n))" "$total" "$(cat "$BASE/horodatage")"
   else
      echo "base de profils : $total fiche(s) (archive), $n nouvelle(s) ou mise(s) a jour, dans $BASE"
   fi
   return 0
}

case $CMD in
   toml) toml_plat "$ARG" ;;
   chemin) chemin "$ARG" ;;
   plat)
      f=$(chemin "$ARG") || exit 0
      fiche_plat "$f" | LC_ALL=C awk -F'\t' '
         $1 == "cidre" || ($1 == "jeu" && ($2 == "moteur" || $2 == "anticheat" || $2 == "api" || $2 == "api_disponibles")) || ($1 == "compat" && ($2 == "etat" || $2 == "source")) {
            v = $4
            if ($3 == "s") { gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); v = "\"" v "\"" }
            print $2 " = " v
         }' ;;
   json)
      f=$(chemin "$ARG") || { echo null; exit 0; }
      # avant fiche_plat, qui reprend $f pour ses propres boucles
      case $f in "$BASE"/*) origine=cache ;; "$LIVRE"/*) origine=livree ;; *) origine=provisoire ;; esac
      P=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
      fiche_plat "$f" >"$P"
      printf '{"jeu":%s,"cidre":%s,"compat":%s,' "$(objet_json "$P" jeu)" "$(objet_json "$P" cidre)" "$(objet_json "$P" compat)"
      # le resume ProtonDB importe ([compat.protondb]), ou null
      if LC_ALL=C grep -q '^compat\.protondb	' "$P"; then printf '"protondb":%s,' "$(objet_json "$P" compat.protondb)"
      else printf '"protondb":null,'; fi
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
      # "compat" est celle de cette machine ; "compat_reference" le [compat] ecrit
      # (la machine de reference), "compat_machines" toutes les entrees par famille
      if LC_ALL=C grep -q '^compat\.reference	' "$P"; then r=compat.reference; else r=compat; fi
      printf '"compat_reference":%s,"compat_machines":[' "$(objet_json "$P" "$r")"; sep=""
      for e in $(LC_ALL=C awk -F'\t' '$1 ~ /^compat\.machines\.[0-9]+$/ && !vu[$1]++ { print $1 }' "$P"); do
         printf '%s%s' "$sep" "$(objet_json "$P" "$e")"; sep=","
      done
      printf '],'
      printf '"origine":"%s","rapports":%s}\n' "$origine" "$(awk -F'\t' '$1 ~ /^rapports\.[0-9]+$/ && !vu[$1]++ {n++} END {print n+0}' "$P")"
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
   compat)
      # la compat sur cette machine, `cle TAB valeur` ; puis chaque entree par
      # famille : `machines TAB nom TAB voie TAB etat TAB applique`
      f=$(chemin "$ARG") || exit 0
      P=$(mktemp "${TMPDIR:-/tmp}/fiche.XXXXXX")
      fiche_plat "$f" >"$P"
      LC_ALL=C awk -F'\t' '
         $1 == "compat" { print $2 "\t" $4 }
         $1 ~ /^compat\.machines\.[0-9]+$/ { if (!($1 in vu)) { vu[$1] = 1; o[++n] = $1 } v[$1, $2] = $4 }
         END { for (k = 1; k <= n; k++) { e = o[k]; print "machines\t" (v[e, "nom"] != "" ? v[e, "nom"] : v[e, "si"]) "\t" v[e, "voie"] "\t" v[e, "etat"] "\t" v[e, "applique"] } }' "$P"
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
      echo "# Index de la base de profils : une table par fiche (nom, etat, date, empreinte)."
      echo "# Genere par \`sh tests/fiche_profil.sh generer-index > profils/index.toml\` ;"
      echo "# tests/tester_profils.sh verifie qu'il est a jour. C'est lui que \`cidre profils maj\`"
      echo "# telecharge d'abord, pour savoir quelles fiches prendre : seules celles dont"
      echo "# l'empreinte (md5 du fichier) a change sont retelechargees."
      for f in "${ARG:-$LIVRE}"/*.toml; do
         [ -f "$f" ] || continue
         a=$(basename "$f" .toml); case $a in index|index-depot) continue ;; esac
         toml_plat "$f" | LC_ALL=C awk -F'\t' -v a="$a" -v h="$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -c1-32)" '
            ($1 == "jeu" && $2 == "nom") || ($1 == "compat" && ($2 == "etat" || $2 == "date")) { gsub(/\\/, "\\\\", $4); gsub(/"/, "\\\"", $4); c[$2] = $4 }
            END { print ""; print "[" a "]"; print "nom = \"" c["nom"] "\""; print "etat = \"" (c["etat"] == "" ? "non-teste" : c["etat"]) "\""; print "date = \"" c["date"] "\""; print "empreinte = \"" h "\"" }'
      done ;;
   maj)
      command -v curl >/dev/null 2>&1 || { echo "curl introuvable" >&2; exit 1; }
      # L archive de la base d abord (CIDRE_PROFILS_ARCHIVE ; vide = jamais) : une
      # requete, toutes les fiches du catalogue. Sans archive publiee, ou en echec :
      # l index puis les fiches une a une, comme avant.
      if [ -n "$ARCHIVE" ]; then maj_archive && exit 0; fi
      # L index d abord, puis chaque fiche qu il nomme, dans un dossier de travail ;
      # on ne remplace le cache qu une fois tout recu. Les fiches sorties de l index
      # quittent le cache. Sans reseau : message, code 1, la copie livree sert.
      T=$(mktemp -d "${TMPDIR:-/tmp}/profils-maj.XXXXXX")
      prendre() { curl -fsSL --connect-timeout 10 --max-time 60 -o "$T/$1" "$URL$1" 2>>"$T/erreurs"; }
      if ! prendre index.toml; then
         rm -rf "$T"
         [ "$ARG" = json ] && echo '{"ok":false,"erreur":"index.toml injoignable"}' || echo "base de profils : index injoignable ($URL) ; la copie livree sert" >&2
         exit 1
      fi
      # Incremental : une fiche deja en cache dont l'empreinte (md5, portee par
      # l'index) n'a pas change n'est pas retelechargee. Un index sans empreintes
      # (ancien) retelecharge tout.
      n=0; gardees=0; rates=""
      for a in $(toml_plat "$T/index.toml" | cut -f1 | awk '!vu[$0]++'); do
         id_sur "$a" || continue
         e=$(toml_plat "$T/index.toml" | LC_ALL=C awk -F'\t' -v a="$a" '$1 == a && $2 == "empreinte" { print $4; exit }')
         if [ -n "$e" ] && [ -f "$BASE/$a.toml" ] && [ "$(empreinte "$BASE/$a.toml")" = "$e" ]; then
            gardees=$((gardees + 1)); continue
         fi
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
         printf '{"ok":true,"fiches":%s,"gardees":%s,"rates":[' "$n" "$gardees"; sep=""
         for a in $rates; do printf '%s"%s"' "$sep" "$a"; sep=","; done
         printf '],"horodatage":"%s"}\n' "$(cat "$BASE/horodatage")"
      else
         echo "base de profils : $n fiche(s) mise(s) a jour dans $BASE ($gardees inchangee(s))"
         [ -z "$rates" ] || echo "  non recues :$rates" >&2
      fi
      [ -z "$rates" ] ;;
   provisoire)
      # Un jeu qu on installe et que la base ne connait pas : une fiche provisoire,
      # locale, hors du cache (que `maj` remplace en bloc). Le resume public de
      # ProtonDB (palier, confiance, nombre de rapports), le nom et les plateformes
      # du magasin Steam ; deux requetes courtes, curl, awk et sed (pas de python :
      # sur un Mac dont la licence Xcode n est pas acceptee, python3 echoue). Rien
      # si le jeu a deja une fiche, provisoire comprise. rc 0 = ecrite ou deja la ;
      # 3 = ProtonDB ne connait pas le jeu (rien d ecrit) ; 1 = reseau ou erreur.
      a=$ARG
      case $a in ''|*[!0-9]*) echo "usage: fiche_profil.sh provisoire <appid Steam>" >&2; exit 2 ;; esac
      chemin "$a" >/dev/null && exit 0
      command -v curl >/dev/null 2>&1 || { echo "curl introuvable" >&2; exit 1; }
      PDB=${CIDRE_PROTONDB_URL:-https://www.protondb.com/api/v1/reports/summaries/}
      MAG=${CIDRE_STEAM_MAGASIN_URL:-https://api.steampowered.com/IStoreBrowseService/GetItems/v1}
      T=$(mktemp -d "${TMPDIR:-/tmp}/fiche-provisoire.XXXXXX")
      code=$(curl -sS -L --connect-timeout 5 --max-time 15 -o "$T/resume.json" -w '%{http_code}' "$PDB$a.json" 2>/dev/null); rc=$?
      # 200 en http ; 000 et code 0 pour un file:// (tests) ; 404, ou 37 (fichier absent) : jeu inconnu
      case $rc:$code in
         0:200|0:000) ;;
         0:404|37:*) rm -rf "$T"; echo "ProtonDB ne connait pas $a : pas de fiche provisoire" >&2; exit 3 ;;
         *) rm -rf "$T"; echo "ProtonDB injoignable ($rc/$code) : pas de fiche provisoire pour $a" >&2; exit 1 ;;
      esac
      # le resume : un objet JSON plat (cles connues, chaines sans virgule ni guillemet, nombres)
      LC_ALL=C tr -d '\n\r' <"$T/resume.json" | LC_ALL=C awk -v RS=, '
         {
            if (!match($0, /"[A-Za-z]+"[ \t]*:/)) next
            k = substr($0, RSTART + 1, RLENGTH - 1); sub(/"[ \t]*:$/, "", k)
            v = substr($0, RSTART + RLENGTH); gsub(/^[ \t]+|[ \t}]+$/, "", v)
            if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2); if (v !~ /^[A-Za-z0-9 _.-]*$/) next; print k "\ts\t" v }
            else if (v ~ /^-?[0-9]+(\.[0-9]+)?$/) print k "\tn\t" v
         }' >"$T/resume"
      grep -q '^tier	s	' "$T/resume" || { rm -rf "$T"; echo "resume ProtonDB illisible pour $a" >&2; exit 1; }
      # nom et plateformes : le magasin Steam (sans compte) ; facultatif
      demande=$(printf '{"ids":[{"appid":%s}],"context":{"language":"english","country_code":"US"},"data_request":{"include_platforms":true}}' "$a" \
         | sed 's/{/%7B/g; s/}/%7D/g; s/\[/%5B/g; s/\]/%5D/g; s/"/%22/g; s/:/%3A/g; s/,/%2C/g')
      case $MAG in file://*) ;; *) MAG="$MAG?input_json=$demande" ;; esac   # file:// : une reponse toute faite (tests)
      curl -fsS --connect-timeout 5 --max-time 15 -o "$T/magasin.json" "$MAG" 2>/dev/null || : >"$T/magasin.json"
      LC_ALL=C awk '
         # la premiere chaine "cle":"..." (echappements \" et \\ compris) a partir de s
         function chaine(s, cle,   i, j, c, v) {
            i = index(s, "\"" cle "\":\""); if (!i) return ""
            v = ""
            for (j = i + length(cle) + 4; j <= length(s); j++) {
               c = substr(s, j, 1)
               if (c == "\\") { j++; c = substr(s, j, 1); if (c == "u") { j += 4; continue } }
               else if (c == "\"") break
               v = v c
            }
            return v
         }
         { t = t $0 }
         END {
            if (t !~ /"success":1[,}]/) exit
            n = chaine(t, "name"); gsub(/[\001-\037]/, "", n)
            if (n != "") print "nom\t" n
            p = ""; i = index(t, "\"platforms\":{")
            if (i) {
               q = substr(t, i, 200); sub(/}.*/, "", q)
               if (q ~ /"windows":true/) p = p " windows"
               if (q ~ /"mac":true/) p = p " macos"
               if (q ~ /"steamos_linux":true/) p = p " linux"
            }
            # dans l ordre de l importeur : linux macos windows
            if (p != "") { m = ""; if (p ~ /linux/) m = m " linux"; if (p ~ /macos/) m = m " macos"; if (p ~ /windows/) m = m " windows"; print "plateformes\t" substr(m, 2) }
         }' "$T/magasin.json" >"$T/magasin"
      jour=$(date +%Y-%m-%d)
      nom=$(awk -F'\t' '$1 == "nom" { print $2; exit }' "$T/magasin")
      pf=$(awk -F'\t' '$1 == "plateformes" { print $2; exit }' "$T/magasin")
      esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
      {
         printf '# %s -- fiche PROVISOIRE, ecrite par Cidre a l installation (%s) :\n' "${nom:-$a}" "$jour"
         echo "# le jeu n'a pas encore de fiche dans la base. Seuls le resume public de ProtonDB"
         echo "# et le magasin Steam y sont repris ; la vraie fiche (\`cidre profils maj\`) passe"
         echo "# devant des qu'elle existe. Fichier local, jamais publie."
         echo
         echo "[jeu]"
         echo "appid = $a"
         [ -z "$nom" ] || printf 'nom = "%s"\n' "$(esc "$nom")"   # printf : le echo de sh lit les \
         [ -z "$pf" ] || echo "plateformes_steam = \"$pf\""
         echo "provisoire = true"
         if [ -n "$nom$pf" ]; then
            echo; echo "[jeu.sources]"
            [ -z "$nom" ] || echo "nom = \"steam $jour\""
            [ -z "$pf" ] || echo "plateformes_steam = \"steam $jour\""
         fi
         echo
         echo "[compat]"
         echo "etat = \"non-teste\""
         echo "date = \"$jour\""
         echo
         echo "[compat.protondb]"
         # memes cles que tests/outils/importer_profils.py ; score en pourcents
         LC_ALL=C awk -F'\t' '
            { v[$1] = $3; t[$1] = $2 }
            function sortir(src, dst) { if (!(src in v)) return; if (t[src] == "s") print dst " = \"" v[src] "\""; else print dst " = " v[src] }
            END {
               sortir("tier", "palier"); sortir("trendingTier", "tendance"); sortir("bestReportedTier", "meilleur_palier")
               sortir("confidence", "confiance"); sortir("total", "rapports")
               if ("score" in v && t["score"] == "n") printf "score = %d\n", int(v["score"] * 100 + 0.5)
            }' "$T/resume"
         echo "source = \"protondb\""
         echo "date = \"$jour\""
         echo "url = \"https://www.protondb.com/app/$a\""
      } >"$T/fiche.toml"
      # la fiche doit se relire avant d entrer
      toml_plat "$T/fiche.toml" | LC_ALL=C grep -q '^compat\.protondb	palier	' || { rm -rf "$T"; echo "fiche provisoire illisible pour $a" >&2; exit 1; }
      mkdir -p "$PROV" && mv -f "$T/fiche.toml" "$PROV/$a.toml.tmp" && mv -f "$PROV/$a.toml.tmp" "$PROV/$a.toml"
      rm -rf "$T"
      echo "$PROV/$a.toml" ;;
   *) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
