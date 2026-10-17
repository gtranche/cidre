#!/bin/sh
# Envoie une archive de diagnostic (tests/diag_cidre.sh) au service de depot
# (service/diag-depot) et rend le code court que le testeur donne a l'equipe :
# CIDRE-7K3P-Q9. Jamais de lui-meme : `cidre diag` et Verger ne l'appellent
# qu'apres l'accord du testeur, pour cette archive-la.
#
#   envoyer_diag.sh envoyer <archive> [--json]
#   envoyer_diag.sh service [--json]          le service est-il configure ? chiffre-t-on ?
#   envoyer_diag.sh code-valide <code>        code 0 si la cle de controle du code est bonne
#
# Configuration (`cle=valeur`), la premiere trouvee :
#   $CIDRE_DIR/diag-service.conf       (posee a la main, pour essayer un autre service)
#   $R/outil-steam/diag-service.conf   (livree avec le runtime)
#     url=https://cidre-diag.<compte>.workers.dev
#     jeton=<jeton d'application, le meme pour tous : il ecarte les envois au hasard, pas un secret>
#     cle=diag-cle.pem                  (cle publique RSA, relative au fichier de configuration)
# Avec une cle, l'archive est chiffree avant de partir (enveloppe CIDRE-DIAG-1,
# ci-dessous) : seul le detenteur de la cle privee la relit, meme le service ne
# le peut pas. Le LibreSSL de macOS suffit (openssl pkeyutl, enc).
#
# Enveloppe CIDRE-DIAG-1 :
#   ligne 1 : CIDRE-DIAG-1
#   ligne 2 : base64 sur une ligne de RSA-OAEP(cle publique, "<cle aes hex> <iv hex> <sha256 hex de l'archive>")
#   ligne 3 : le format de l'archive (tar.zst, tar.gz)
#   puis    : AES-256-CBC(archive)
#
# Sortie de `envoyer` : le code, ou en --json
#   {"code":"CIDRE-7K3P-Q9","expire":"2026-11-16","chiffre":true,"octets":n}
#   {"erreur":"non_configure"|"reseau"|"refuse"|"archive","message":"..."}
# Codes : 0 envoye, 2 usage, 3 service non configure, 4 service injoignable,
# 5 refuse par le service (taille, debit, jeton), 6 archive illisible.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
OPENSSL=${CIDRE_OPENSSL:-/usr/bin/openssl}
# Alphabet des codes : ni 0/O, ni 1/I/L, ni U (lu V) -- 30 signes
ALPHABET=23456789ABCDEFGHJKMNPQRSTVWXYZ

cmd=${1:-}; [ $# -gt 0 ] && shift
JSON=non; ARG=
for a in "$@"; do case $a in --json) JSON=oui ;; *) ARG=$a ;; esac; done

js() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
echec() { # <code> <erreur> <message>
   if [ $JSON = oui ]; then printf '{"erreur":"%s","message":%s}\n' "$2" "$(js "$3")"; else echo "$3" >&2; fi
   exit "$1"
}

CONF=
for c in "$CIDRE_DIR/diag-service.conf" "$R/outil-steam/diag-service.conf"; do
   [ -f "$c" ] && { CONF=$c; break; }
done
conf() { [ -n "$CONF" ] && sed -n "s/^$1=//p" "$CONF" | head -1 | tr -d '\r'; }
URL=$(conf url); URL=${URL%/}; JETON=$(conf jeton); CLE=$(conf cle)
if [ -n "$CLE" ]; then case $CLE in /*) ;; *) CLE="$(dirname "$CONF")/$CLE" ;; esac; [ -f "$CLE" ] || CLE=; fi
configure=false; [ -n "$URL" ] && [ -n "$JETON" ] && configure=true
chiffre=false; [ -n "$CLE" ] && chiffre=true

# La cle de controle (Luhn mod 30) : une faute de frappe sur un signe, ou deux
# signes voisins echanges, se voit avant d'interroger le service.
controle() { # <5 signes> -> le 6e
   printf '%s' "$1" | awk -v A="$ALPHABET" '{
      n = length(A); f = 2; s = 0
      for (i = length($0); i >= 1; i--) {
         v = index(A, substr($0, i, 1)) - 1; a = f * v
         f = (f == 2) ? 1 : 2
         s += int(a / n) + (a % n)
      }
      print substr(A, (n - (s % n)) % n + 1, 1)
   }'
}

case $cmd in
service)
   if [ $JSON = oui ]; then
      printf '{"configure":%s,"chiffre":%s,"url":%s}\n' "$configure" "$chiffre" "$(js "$URL")"
   else
      echo "service : $( [ $configure = true ] && echo "$URL" || echo "non configure" )"
      echo "chiffrement : $( [ $chiffre = true ] && echo "oui ($CLE)" || echo non )"
   fi ;;
code-valide)
   c=$(printf '%s' "$ARG" | tr 'a-z' 'A-Z' | tr -d ' -' | sed 's/^CIDRE//')
   case $c in ??????) ;; *) exit 1 ;; esac
   case $c in *[!$ALPHABET]*) exit 1 ;; esac
   [ "$(controle "$(printf '%s' "$c" | cut -c1-5)")" = "$(printf '%s' "$c" | cut -c6)" ] ;;
envoyer)
   A=$ARG
   [ -n "$A" ] || { echo "usage: envoyer_diag.sh envoyer <archive> [--json]" >&2; exit 2; }
   [ -f "$A" ] && [ -r "$A" ] || echec 6 archive "Archive introuvable : $A"
   [ $configure = true ] || echec 3 non_configure "Le service de diagnostic n'est pas configure sur ce Mac : envoie l'archive a la main ($A)."
   case $A in *.tar.zst) FORMAT=tar.zst ;; *.tar.gz) FORMAT=tar.gz ;; *) FORMAT=autre ;; esac
   T=$(mktemp -d) || exit 1
   trap 'rm -rf "$T"' EXIT
   P="$A"
   if [ $chiffre = true ]; then
      k=$("$OPENSSL" rand -hex 32) && iv=$("$OPENSSL" rand -hex 16) || echec 6 archive "Chiffrement impossible (openssl rand)."
      h=$(shasum -a 256 "$A" | cut -d' ' -f1)
      printf '%s %s %s' "$k" "$iv" "$h" >"$T/cle"
      P="$T/envoi.cidre"
      { echo CIDRE-DIAG-1
        "$OPENSSL" pkeyutl -encrypt -pubin -inkey "$CLE" -pkeyopt rsa_padding_mode:oaep -in "$T/cle" | base64 | tr -d '\n'; echo
        echo "$FORMAT"
        "$OPENSSL" enc -aes-256-cbc -K "$k" -iv "$iv" -in "$A"
      } >"$P" || echec 6 archive "Chiffrement impossible."
      rm -f "$T/cle"
      # une cle publique illisible donne une ligne 2 vide
      [ -n "$(sed -n 2p "$P" | head -c 10)" ] || echec 6 archive "Cle publique du service illisible ($CLE)."
   fi
   octets=$(stat -f %z "$P")
   appid=$(basename "$A" | sed -n 's/^diag-\([a-z0-9-]*\)-[0-9]\{8\}-[0-9]\{6\}\..*/\1/p')
   version=$(cat "$R/VERSION" 2>/dev/null || echo dev)
   rep=$(curl -sS --max-time 120 --connect-timeout 15 -w '\n%{http_code}' -X POST "$URL/depot" \
         -H "X-Cidre-Jeton: $JETON" -H "Content-Type: application/octet-stream" \
         -H "X-Cidre-Jeu: ${appid:-?}" -H "X-Cidre-Version: $version" \
         -H "X-Cidre-Chiffre: $( [ $chiffre = true ] && echo 1 || echo 0 )" -H "X-Cidre-Format: $FORMAT" \
         --data-binary @"$P" 2>"$T/err")
   rc=$?
   [ $rc -eq 0 ] || echec 4 reseau "Le service de diagnostic ne repond pas ($(head -1 "$T/err" | cut -c1-120)). L'archive reste ici : $A"
   http=$(printf '%s\n' "$rep" | tail -1); corps=$(printf '%s\n' "$rep" | sed '$d')
   code=$(printf '%s' "$corps" | sed -n 's/.*"code" *: *"\(CIDRE-[A-Z0-9-]*\)".*/\1/p')
   expire=$(printf '%s' "$corps" | sed -n 's/.*"expire" *: *"\([^"]*\)".*/\1/p')
   if [ "$http" != 201 ] || [ -z "$code" ]; then
      msg=$(printf '%s' "$corps" | sed -n 's/.*"message" *: *"\([^"]*\)".*/\1/p')
      echec 5 refuse "Le service a refuse l'envoi (HTTP $http)${msg:+ : $msg}. L'archive reste ici : $A"
   fi
   # le code est garde a cote de l'archive : le testeur peut le retrouver
   printf '%s\t%s\t%s\n' "$code" "$(date '+%Y-%m-%d %H:%M')" "$A" >>"$CIDRE_DIR/diagnostics/envois.tsv" 2>/dev/null
   if [ $JSON = oui ]; then
      printf '{"code":"%s","expire":%s,"chiffre":%s,"octets":%s}\n' "$code" "$(js "$expire")" "$chiffre" "$octets"
   else
      echo "$code"
   fi ;;
*)
   echo "usage: envoyer_diag.sh envoyer <archive> [--json] | service [--json] | code-valide <code>" >&2; exit 2 ;;
esac
