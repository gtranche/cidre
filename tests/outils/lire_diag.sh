#!/bin/sh
# Cote equipe (la coordination) : retrouve le diagnostic qu'un testeur a envoye
# (`cidre diag`, ou « Envoyer un diagnostic » dans Verger) a partir du code
# qu'il a donne, le dechiffre, le deballe et le resume en 20 lignes.
#
#   lire_diag.sh <CODE>                 CIDRE-7K3P-Q9 (casse, tirets et espaces indifferents)
#   lire_diag.sh --fichier <archive>    une archive recue autrement (Finder, incident GitHub) :
#                                       diag-*.tar.zst / .tar.gz, ou une enveloppe chiffree
#   lire_diag.sh --liste                les diagnostics recus (30 derniers jours)
#   lire_diag.sh --effacer <CODE>       l'efface du service (sinon il part seul apres 30 jours)
#
# Configuration, propre a la machine de l'equipe et jamais dans le depot
# (service/diag-depot/README.md) : ${CIDRE_DIAG_CONF:-~/.config/cidre-diag/conf}
#   url=https://diag.<domaine>
#   jeton_admin=<la cle d administration, JETON_ADMIN du service>
#   cle_privee=~/.config/cidre-diag/cle_privee.pem   (defaut ; la cle qui dechiffre)
# Le diagnostic deballe va dans ${CIDRE_DIAGS_RECUS:-~/Dev/diags-recus}/<CODE>/ :
# resume.txt d'abord, puis journal.txt, doctor.txt, plantages/...
# L'archive vient d'un Mac qu'on ne connait pas : on la deballe dans un dossier
# neuf, avec le tar de macOS (il refuse les chemins absolus et les « .. »), et
# on ne lance rien de ce qu'elle contient.
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
CONF=${CIDRE_DIAG_CONF:-$HOME/.config/cidre-diag/conf}
RECUS=${CIDRE_DIAGS_RECUS:-$HOME/Dev/diags-recus}
OPENSSL=${CIDRE_OPENSSL:-/usr/bin/openssl}

conf() { [ -f "$CONF" ] && sed -n "s/^$1=//p" "$CONF" | head -1 | tr -d '\r' | sed "s|^~|$HOME|"; }
URL=$(conf url); URL=${URL%/}; ADMIN=$(conf jeton_admin)
CLE=$(conf cle_privee); CLE=${CLE:-$HOME/.config/cidre-diag/cle_privee.pem}
besoin_service() {
   [ -n "$URL" ] && [ -n "$ADMIN" ] || { echo "service non configure : $CONF (url=, jeton_admin=) -- service/diag-depot/README.md" >&2; exit 3; }
}
# « cidre 7k3p q9 » -> CIDRE-7K3P-Q9 ; refuse un code dont la cle de controle est fausse
code_net() {
   c=$(printf '%s' "$1" | tr 'a-z' 'A-Z' | tr -d ' -' | sed 's/^CIDRE//')
   sh "$R/tests/envoyer_diag.sh" code-valide "$c" || { echo "code invalide : $1 (une faute de frappe ? ni 0, ni O, ni 1, ni I, ni L, ni U)" >&2; exit 2; }
   printf 'CIDRE-%s-%s' "$(printf '%s' "$c" | cut -c1-4)" "$(printf '%s' "$c" | cut -c5-6)"
}

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# <fichier recu> <dossier> : dechiffre si besoin, verifie, deballe
deballer() {
   f=$1 d=$2
   if [ "$(head -c 12 "$f")" = CIDRE-DIAG-1 ]; then
      [ -f "$CLE" ] || { echo "diagnostic chiffre, et pas de cle privee : $CLE" >&2; exit 4; }
      sed -n 2p "$f" | base64 -D >"$T/cle.enc" 2>/dev/null
      "$OPENSSL" pkeyutl -decrypt -inkey "$CLE" -pkeyopt rsa_padding_mode:oaep -in "$T/cle.enc" -out "$T/cle" 2>/dev/null ||
         { echo "dechiffrement impossible : ce diagnostic n'est pas pour cette cle ($CLE)" >&2; exit 4; }
      read -r k iv h <"$T/cle"
      off=$(head -n 3 "$f" | wc -c | tr -d ' ')
      tail -c "+$((off + 1))" "$f" | "$OPENSSL" enc -d -aes-256-cbc -K "$k" -iv "$iv" -out "$T/archive" 2>/dev/null ||
         { echo "dechiffrement impossible (archive abimee ?)" >&2; exit 4; }
      [ "$(shasum -a 256 "$T/archive" | cut -d' ' -f1)" = "$h" ] || { echo "archive abimee : empreinte differente apres dechiffrement" >&2; exit 4; }
      f="$T/archive"
   fi
   rm -rf "$d.nouveau"; mkdir -p "$d.nouveau"
   case $(head -c 4 "$f" | od -An -tx1 | tr -d ' \n') in
      28b52ffd) command -v zstd >/dev/null || { echo "archive zstd : brew install zstd" >&2; exit 5; }
                zstd -dc "$f" | tar -xf - -C "$d.nouveau" ;;
      1f8b*)    tar -xzf "$f" -C "$d.nouveau" ;;
      *)        echo "format inconnu (ni zstd, ni gzip)" >&2; exit 5 ;;
   esac || { echo "archive illisible" >&2; exit 5; }
   # l'archive porte un dossier diag-<id>-<date>/ : on le remonte
   s=$(find "$d.nouveau" -mindepth 1 -maxdepth 1 -type d -name 'diag-*' | head -1)
   rm -rf "$d"
   if [ -n "$s" ]; then mv "$s" "$d" && rm -rf "$d.nouveau"; else mv "$d.nouveau" "$d"; fi
}

# 20 lignes : l'en-tete, le resume du testeur, le premier plantage
resumer() { # <dossier> <code> [<reçu> <jeu> <version>]
   d=$1
   {
      echo "== $2${3:+ -- recu $3}${4:+ ; jeu $4}${5:+ ; cidre $5} =="
      if [ -f "$d/resume.txt" ]; then grep -v '^capture : non$' "$d/resume.txt" | cut -c1-220
      else echo "(pas de resume.txt : archive d'un Cidre plus ancien ?)"; fi
      p=$(ls -t "$d/plantages" 2>/dev/null | head -1)
      if [ -n "$p" ] && [ -x /usr/bin/jq ]; then
         tail -n +2 "$d/plantages/$p" | /usr/bin/jq -r '"\(.exception.type // "?") \(.exception.signal // "") ; fil : \((.threads // [])[] | select(.triggered == true) | (.frames // [])[:3] | map(.symbol // "?") | join(" < "))"' 2>/dev/null | head -1 | sed "s|^|plantage $p : |" | cut -c1-220
      fi
      echo "-> $d"
   } | head -n 20
}

case ${1:-} in
--liste)
   besoin_service
   curl -fsS --max-time 30 -H "Authorization: Bearer $ADMIN" "$URL/liste" >"$T/l" || { echo "service injoignable ou jeton refuse" >&2; exit 4; }
   if [ -x /usr/bin/jq ]; then /usr/bin/jq -r '.[] | "\(.code)  \(.recu[:16])  jeu \(.jeu)  cidre \(.version)  \(.octets) o\(if .chiffre then "" else "  NON CHIFFRE" end)"' "$T/l"
   else cat "$T/l"; echo; fi ;;
--effacer)
   besoin_service; c=$(code_net "${2:-}") || exit $?
   curl -fsS --max-time 30 -X DELETE -H "Authorization: Bearer $ADMIN" "$URL/diag/$c" && echo "$c efface du service" ;;
--fichier)
   f=${2:?usage: lire_diag.sh --fichier <archive>}
   [ -f "$f" ] || { echo "introuvable : $f" >&2; exit 2; }
   n=$(basename "$f" | sed -E 's/\.(tar\.zst|tar\.gz|cidre)$//')
   mkdir -p "$RECUS"; deballer "$f" "$RECUS/$n"; resumer "$RECUS/$n" "$n" ;;
''|-*)
   echo "usage: lire_diag.sh <CODE> | --fichier <archive> | --liste | --effacer <CODE>" >&2; exit 2 ;;
*)
   besoin_service; c=$(code_net "$1") || exit $?
   http=$(curl -sS --max-time 120 -D "$T/entetes" -o "$T/recu" -w '%{http_code}' -H "Authorization: Bearer $ADMIN" "$URL/diag/$c") ||
      { echo "service injoignable" >&2; exit 4; }
   case $http in
      200) ;;
      404) echo "$c : aucun diagnostic sous ce code (expire apres 30 jours, ou mal recopie)" >&2; exit 1 ;;
      401) echo "jeton d'administration refuse ($CONF)" >&2; exit 3 ;;
      *)   echo "$c : le service repond HTTP $http" >&2; exit 4 ;;
   esac
   ent() { sed -n "s/^$1: *//Ip" "$T/entetes" | tr -d '\r' | head -1; }
   mkdir -p "$RECUS"; deballer "$T/recu" "$RECUS/$c"
   resumer "$RECUS/$c" "$c" "$(ent x-cidre-recu | cut -c1-16 | tr T ' ')" "$(ent x-cidre-jeu)" "$(ent x-cidre-version)" ;;
esac
