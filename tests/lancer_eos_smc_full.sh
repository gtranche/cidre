#!/bin/sh
# Lanceur Steam pour un jeu EAC-EOS avec DÉTECTION COMPLÈTE du code auto-modifiant.
#
# FEX_SMCCHECKS=full valide le code avant chaque exécution, au lieu de la détection par
# protection de page (mtrack, défaut) que le piège des pages 16 Kio de macOS peut laisser
# passer. Gain réel pour les jeux ANTI-TAMPER : ça supprime les cascades de null-derefs et
# les tempêtes d'exceptions SEH dues à du code périmé (mesuré sur DbD : 0 faute c0000005
# contre ~126 000). Plus lent, mais correct.
#
# ATTENTION : ceci ne rend PAS DbD jouable. DbD est 100 % en ligne et exige le vrai EAC
# (désactivé en null-client) ; SMC=full n'enlève que le symptôme (la tempête), pas le mur
# EAC. Voir eac-bridge-macos/docs/EAC_DECK.md. Utile pour les jeux anti-tamper qui, eux,
# ont un mode hors-ligne/non protégé légitime.
#
# Option de lancement Steam :
#   /Users/gtranche/Dev/proton-ouvert/tests/lancer_eos_smc_full.sh %command%
set -e
R=$(cd "$(dirname "$0")" && pwd)
export FEX_SMCCHECKS=full
exec sh "$R/lancer_eos_depuis_steam.sh" "$@"
