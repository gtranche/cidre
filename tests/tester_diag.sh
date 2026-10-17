#!/bin/sh
# Essais de `cidre diag` sans compte Cloudflare ni jeu lance :
#   - le masquage (tests/masquer_diag.awk) sur des lignes types ;
#   - la cle de controle des codes : la meme en shell et dans le Worker ;
#   - le circuit complet sur le Worker servi en local (node, seau en memoire) :
#     archive chiffree -> code -> tests/outils/lire_diag.sh -> resume ; code mal
#     tape, jeton faux, service absent ou injoignable.
#   - avec CIDRE_DIAG_JEU=<appid> : `diag_cidre.sh` sur ce jeu, sans doctor
#     (lecture seule : ni Wine ni jeu lances), et rien de personnel dans l'archive.
#
#   sh tests/tester_diag.sh
# Il faut node (le Worker) ; tout se passe dans un dossier temporaire.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d) || exit 1
SERVEUR=
trap '[ -n "$SERVEUR" ] && kill $SERVEUR 2>/dev/null; rm -rf "$T"' EXIT
ok=0 ko=0
verifier() { # <intitule> <condition shell>
   if eval "$2"; then ok=$((ok + 1)); else ko=$((ko + 1)); echo "ECHEC : $1"; fi
}

# --- Masquage ---------------------------------------------------------------
printf 'chemin\t/Users/marie\t~\nchemin\tmarie\t‹utilisateur›\ncompte_steam\tmarie_jeux\t‹steam›\nmachine\tMacBook-Pro-de-Marie\t‹mac›\n' >"$T/lit"
cat >"$T/brut" <<'EOF'
/Users/marie/Library/Logs ; C:\users\Marie\AppData ; marie_jeux s'est connecte
steamid 76561198012345678 [U:1:52079950] userdata/52079950/config
token=abcdefghijk1234 "access_token": "eyJhbGciOiJFZERTQSJ9.eyJpc3MiOiJyOnN0ZWFt.c2lnbmF0dXJl" password: true
mail marie.dupont@gmail.com ip 192.168.1.23 et 127.0.0.1 version 10.0.19045.1 dll 1.0.0.1x
ipv6 2a01:cb00:1234:5678:9abc:def0:1234:5678 mac a4:83:e7:12:34:56 heure 12:34:56
  "crashReporterKey" : "8E1F2C3D-AAAA-BBBB",
Wine 0024:trace:seh:dispatch 0x7ffe0000 MacBook-Pro-de-Marie.local d3d11=dxmt tso=true
EOF
DIAG_LITTERAUX="$T/lit" DIAG_COMPTES="$T/cpt" LC_ALL=C awk -f "$R/tests/masquer_diag.awk" "$T/brut" >"$T/masque"
verifier "nom de session masque" "! grep -qi marie '$T/masque'"
verifier "dossier personnel en ~" "grep -q '^~/Library/Logs' '$T/masque'"
verifier "compte Steam masque en entier" "grep -q '‹steam› s.est connecte' '$T/masque'"
verifier "SteamID64, [U:1:], userdata" "! grep -qE '76561198012345678|52079950' '$T/masque'"
verifier "jetons" "! grep -qE 'abcdefghijk1234|eyJhbGci' '$T/masque'"
verifier "une valeur banale reste" "grep -q 'password: true' '$T/masque'"
verifier "e-mail" "grep -q 'mail ‹e-mail› ' '$T/masque'"
verifier "IPv4 privee masquee, 127.0.0.1 gardee" "grep -q 'ip ‹ip› et 127.0.0.1' '$T/masque'"
verifier "une version a quatre nombres reste" "grep -q '10.0.19045.1 dll 1.0.0.1x' '$T/masque'"
verifier "IPv6 et adresse materielle, pas l'heure" "grep -q 'ipv6 ‹ip› mac ‹ip› heure 12:34:56' '$T/masque'"
verifier "identifiant du rapport de plantage" "grep -q '\"crashReporterKey\" : \"‹jeton›\"' '$T/masque'"
verifier "les traces de Wine et le profil restent" "grep -q '0024:trace:seh:dispatch 0x7ffe0000 ‹mac›.local d3d11=dxmt tso=true' '$T/masque'"
verifier "comptes par categorie" "grep -q '^identifiant_steam	3' '$T/cpt' && grep -q '^ip	3' '$T/cpt'"

# --- Cle de controle : shell = Worker ----------------------------------------
if command -v node >/dev/null 2>&1; then
   A=23456789ABCDEFGHJKMNPQRSTVWXYZ
   node --input-type=module -e "
      import { ALPHABET, controle } from '$R/service/diag-depot/worker.js';
      for (let i = 0; i < 300; i++) { let s = ''; for (let j = 0; j < 5; j++) s += ALPHABET[Math.floor(Math.random() * 30)]; console.log(s + controle(s)); }
   " >"$T/codes"
   faux=0
   while read -r c; do sh "$R/tests/envoyer_diag.sh" code-valide "$c" || faux=$((faux + 1)); done <"$T/codes"
   verifier "300 codes du Worker valides pour le shell" "[ $faux -eq 0 ] && [ \$(wc -l <'$T/codes') -eq 300 ]"
   c=$(head -1 "$T/codes"); d=$(printf '%s' "$c" | cut -c1); e=$(printf '%s' "$c" | cut -c2)
   [ "$d" = 2 ] && n=3 || n=2
   verifier "un signe faux : refuse" "! sh '$R/tests/envoyer_diag.sh' code-valide '$n$(printf '%s' "$c" | cut -c2-)'"
   [ "$d" = "$e" ] || verifier "deux voisins echanges : refuse" "! sh '$R/tests/envoyer_diag.sh' code-valide '$e$d$(printf '%s' "$c" | cut -c3-)'"
   verifier "forme du code donne au testeur acceptee" "sh '$R/tests/envoyer_diag.sh' code-valide 'cidre-$(printf '%s' "$c" | cut -c1-4)-$(printf '%s' "$c" | cut -c5-6)'"
else
   echo "(node absent : cle de controle et circuit complet non essayes)"
fi

# --- Circuit complet sur le Worker local ------------------------------------
if command -v node >/dev/null 2>&1; then
   PORT=$((20000 + $$ % 20000))
   node "$R/service/diag-depot/local/serveur_local.mjs" $PORT app-essai admin-essai >"$T/serveur" 2>&1 &
   SERVEUR=$!
   i=0; while [ $i -lt 50 ] && ! grep -q pret "$T/serveur" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
   export CIDRE_DIR="$T/cidre"; mkdir -p "$CIDRE_DIR/diagnostics" "$T/equipe"
   /usr/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$T/equipe/cle_privee.pem" 2>/dev/null
   /usr/bin/openssl pkey -in "$T/equipe/cle_privee.pem" -pubout -out "$CIDRE_DIR/diag-cle.pem"
   printf 'url=http://127.0.0.1:%s\njeton=app-essai\ncle=diag-cle.pem\n' $PORT >"$CIDRE_DIR/diag-service.conf"
   printf 'url=http://127.0.0.1:%s\njeton_admin=admin-essai\ncle_privee=%s\n' $PORT "$T/equipe/cle_privee.pem" >"$T/equipe/conf"
   export CIDRE_DIAG_CONF="$T/equipe/conf" CIDRE_DIAGS_RECUS="$T/recus"
   # une archive comme en fait diag_cidre.sh
   D="$CIDRE_DIR/diagnostics/diag-1137300-20261017-120000"
   mkdir -p "$D/plantages"
   printf 'diagnostic Cidre du 2026-10-17 12:00 -- jeu 1137300 (Sherlock)\ncause probable : essai\n' >"$D/resume.txt"
   head -c 200000 /dev/urandom | base64 >"$D/journal.txt"
   ( cd "$CIDRE_DIR/diagnostics" && tar -czf diag-1137300-20261017-120000.tar.gz diag-1137300-20261017-120000 )
   A="$D.tar.gz"
   verifier "service vu configure et chiffre" "sh '$R/tests/envoyer_diag.sh' service --json | grep -q '\"configure\":true,\"chiffre\":true'"
   sh "$R/tests/envoyer_diag.sh" envoyer "$A" --json >"$T/envoi"; rc=$?
   code=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' "$T/envoi")
   verifier "envoi : code 0 et code court" "[ $rc -eq 0 ] && printf '%s' '$code' | grep -qE '^CIDRE-[2-9A-HJ-NP-TV-Z]{4}-[2-9A-HJ-NP-TV-Z]{2}$'"
   verifier "le code est garde a cote de l'archive" "grep -q '^$code' '$CIDRE_DIR/diagnostics/envois.tsv'"
   verifier "le service ne garde que du chiffre" "curl -s -H 'Authorization: Bearer admin-essai' http://127.0.0.1:$PORT/diag/$code | head -c 12 | grep -q CIDRE-DIAG-1"
   minuscule=$(printf '%s' "$code" | tr 'A-Z' 'a-z' | tr '-' ' ')
   sh "$R/tests/outils/lire_diag.sh" "$minuscule" >"$T/lu"; rc=$?
   verifier "lire_diag : dechiffre et deballe" "[ $rc -eq 0 ] && cmp -s '$D/journal.txt' '$T/recus/$code/journal.txt'"
   verifier "lire_diag : resume de 20 lignes au plus, avec la cause" "[ \$(wc -l <'$T/lu') -le 20 ] && grep -q 'cause probable : essai' '$T/lu' && grep -q 'jeu 1137300' '$T/lu'"
   verifier "lire_diag --liste" "sh '$R/tests/outils/lire_diag.sh' --liste | grep -q '^$code'"
   verifier "lire_diag --fichier (archive envoyee a la main)" "sh '$R/tests/outils/lire_diag.sh' --fichier '$A' | grep -q 'cause probable : essai'"
   verifier "code mal tape : refuse avant le reseau" "! sh '$R/tests/outils/lire_diag.sh' CIDRE-0000-00 2>/dev/null"
   printf 'url=http://127.0.0.1:%s\njeton_admin=faux\n' $PORT >"$T/equipe/conf2"
   CIDRE_DIAG_CONF="$T/equipe/conf2" sh "$R/tests/outils/lire_diag.sh" "$code" >/dev/null 2>&1; rc=$?
   verifier "jeton d'administration faux : code 3" "[ $rc -eq 3 ]"
   # sans cle publique : l'archive part telle quelle, lire_diag la lit aussi
   sed -i '' '/^cle=/d' "$CIDRE_DIR/diag-service.conf"
   c2=$(sh "$R/tests/envoyer_diag.sh" envoyer "$A")
   verifier "envoi sans chiffrement, relu" "sh '$R/tests/outils/lire_diag.sh' '$c2' | grep -q 'cause probable : essai'"
   sed -i '' 's/^jeton=.*/jeton=faux/' "$CIDRE_DIR/diag-service.conf"
   sh "$R/tests/envoyer_diag.sh" envoyer "$A" --json >"$T/refus"; rc=$?
   verifier "jeton d'application faux : code 5, erreur refuse" "[ $rc -eq 5 ] && grep -q '\"erreur\":\"refuse\"' '$T/refus'"
   kill $SERVEUR 2>/dev/null; wait $SERVEUR 2>/dev/null; SERVEUR=
   sed -i '' 's/^jeton=.*/jeton=app-essai/' "$CIDRE_DIR/diag-service.conf"
   sh "$R/tests/envoyer_diag.sh" envoyer "$A" --json >"$T/reseau"; rc=$?
   verifier "service injoignable : code 4, erreur reseau" "[ $rc -eq 4 ] && grep -q '\"erreur\":\"reseau\"' '$T/reseau'"
   rm -f "$CIDRE_DIR/diag-service.conf"
   CIDRE_DIR="$CIDRE_DIR" sh -c "cd /; R_FAUX=1 sh '$R/tests/envoyer_diag.sh' envoyer '$A' --json" >"$T/sans"; rc=$?
   if [ -f "$R/outil-steam/diag-service.conf" ]; then echo "(outil-steam/diag-service.conf livre : cas « non configure » non essaye)"
   else verifier "service non configure : code 3, erreur non_configure" "[ $rc -eq 3 ] && grep -q '\"erreur\":\"non_configure\"' '$T/sans'"; fi
   unset CIDRE_DIR CIDRE_DIAG_CONF CIDRE_DIAGS_RECUS
fi

# --- Sur un vrai jeu (lecture seule) ----------------------------------------
if [ -n "${CIDRE_DIAG_JEU:-}" ]; then
   RT=${CIDRE_DIAG_RACINE:-$R}
   CIDRE_DIAG_RACINE="$RT" sh "$R/tests/diag_cidre.sh" "$CIDRE_DIAG_JEU" --sans-doctor --json >"$T/vrai"; rc=$?
   verifier "diag_cidre.sh sur $CIDRE_DIAG_JEU" "[ $rc -eq 0 ] && grep -q '\"resume\":\[' '$T/vrai'"
   if [ -x /usr/bin/jq ]; then
      verifier "sortie JSON valide" "/usr/bin/jq -e '.archive and (.fichiers | length > 5)' '$T/vrai' >/dev/null"
      d=$(/usr/bin/jq -r .dossier "$T/vrai")
      moi=$(id -un); complet=$(id -F)
      verifier "ni nom de session ni nom complet dans l'archive" "! grep -rqiF -e '$moi' -e '$complet' '$d'"
      verifier "aucun SteamID64" "! grep -rqE '7656119[0-9]{10}' '$d'"
      verifier "resume de 20 lignes au plus" "[ \$(wc -l <'$d/resume.txt') -le 20 ]"
      verifier "aucune capture sans --capture" "[ ! -f '$d/capture.png' ]"
   fi
fi

echo "tester_diag : $ok bons, $ko echecs"
[ $ko -eq 0 ]
