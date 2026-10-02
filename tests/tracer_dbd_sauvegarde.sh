#!/bin/sh
# Trace ciblee du moment ou Dead by Daylight refuse le profil (« SAVE GAME ERROR /
# Error code: 0 ») au premier lancement. Tout le reste de la pile est deja verifie
# bon (backend 200, transport 13492 octets fideles sans gzip, AES-256 et SHA-256
# corrects) : le refus se produit dans le traitement du profil INTERNE au jeu, sur
# une entree pourtant correcte. Cette trace cherche donc, cote pile Wine/FEX, deux
# choses :
#   1. l'exception que le jeu attrape et transforme en boite de dialogue (+seh) ;
#   2. la livraison du corps HTTP du profil au jeu (+winhttp,+wininet) -- confirme
#      que les 13492 octets arrivent, ou montre que le jeu utilise son propre curl
#      embarque (alors rien ici, mais +seh reste utile).
#
# A poser dans les OPTIONS DE LANCEMENT du jeu, dans Steam, a la place du lanceur
# habituel :
#
#   /Users/gtranche/Dev/proton-ouvert/tests/tracer_dbd_sauvegarde.sh %command%
#
# Lance le jeu, attends la boite « SAVE GAME ERROR », clique « fermer le jeu »,
# puis analyse :  sh tests/analyser_trace_dbd.sh
#
# Le mode EOS non protege (EOS_USE_ANTICHEATCLIENTNULL) et toute la pile arm64ec
# sont delegues a lancer_eos_depuis_steam.sh, inchange.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

# Canaux : ni -all (on veut voir), ni +relay (volume ingerable). Surchargeable :
#   WINEDEBUG_TRACE="+seh,+file"  sh tracer_dbd_sauvegarde.sh %command%
export WINEDEBUG=${WINEDEBUG_TRACE:-+seh,+winhttp,+wininet}

# Journal dedie, horodate, separe du journal Steam normal.
mkdir -p "$R/build/logs"
HORO=$(date '+%Y.%m.%d-%H.%M.%S')
export PROTON_OUVERT_JOURNAL="$R/build/logs/trace-dbd-sauvegarde-$HORO.log"
# Pointeur stable vers la derniere trace, pour l'analyseur.
ln -sf "$PROTON_OUVERT_JOURNAL" "$R/build/logs/trace-dbd-sauvegarde-derniere.log"

echo "=== trace DbD sauvegarde ===" >&2
echo "canaux   : $WINEDEBUG" >&2
echo "journal  : $PROTON_OUVERT_JOURNAL" >&2
echo "analyse  : sh $R/tests/analyser_trace_dbd.sh" >&2

exec sh "$R/tests/lancer_eos_depuis_steam.sh" "$@"
