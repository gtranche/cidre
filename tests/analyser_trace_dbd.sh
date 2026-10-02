#!/bin/sh
# Analyse la trace produite par tracer_dbd_sauvegarde.sh : exceptions attrapees par
# le jeu, livraison du corps HTTP du profil, et derniere activite avant la fermeture.
#
#   sh tests/analyser_trace_dbd.sh [chemin_du_journal]
#
# Sans argument : prend la derniere trace (build/logs/trace-dbd-sauvegarde-derniere.log).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
J=${1:-$R/build/logs/trace-dbd-sauvegarde-derniere.log}
[ -f "$J" ] || { echo "journal introuvable : $J" >&2; echo "lance d'abord le jeu via tracer_dbd_sauvegarde.sh" >&2; exit 1; }

echo "journal : $J  ($(wc -l <"$J") lignes)"
echo

echo "=== 1. Exceptions C++ (0xe06d7363) et violations d'acces (0xc0000005) ==="
# C'est le signal cle : une exception attrapee par le jeu -> boite « SAVE GAME ERROR ».
grep -aiE "e06d7363|c0000005|dispatch_exception|RaiseException|unhandled|first chance" "$J" \
  | grep -aivE "wineboot|services\.exe|rpcss" | tail -40 || echo "  (aucune)"
echo

echo "=== 2. HTTP : le corps du profil (13492 octets) arrive-t-il au jeu ? ==="
# Si le jeu passe par wininet/winhttp de Wine, on voit les tailles lues.
if grep -aqiE "winhttp|wininet|InternetReadFile|WinHttpReadData" "$J"; then
   grep -aiE "InternetReadFile|WinHttpReadData|HttpSendRequest|WinHttpReceiveResponse|content-length|13492|FullProfile" "$J" | tail -40
else
   echo "  Aucun appel wininet/winhttp de Wine : le jeu utilise probablement son"
   echo "  propre client HTTP embarque (libcurl UE). Le transport reste verifie bon"
   echo "  par la capture (Content-Length 13492, sans gzip) ; on se fie au point 1."
fi
echo

echo "=== 3. Modules charges juste avant la fin (contexte du plantage/refus) ==="
grep -aiE "Loaded|loaddll|Initializing|openssl|crypt|libeay|ssleay|ucrtbase|vcruntime|msvcp" "$J" | tail -20 || echo "  (rien)"
echo

echo "=== 4. 40 dernieres lignes de la trace (etat au moment de la fermeture) ==="
tail -40 "$J"
