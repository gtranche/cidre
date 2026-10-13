#!/bin/sh
# DXMT est le rendu Direct3D 11 par defaut, mais un jeu peut le refuser au
# demarrage (DXGI_ERROR_UNSUPPORTED : un format, un niveau de fonctionnalite ou
# un mode de presentation que DXMT ne fait pas). Le cas qui a fait ecrire ce
# script, Dead Cells le 2026-10-13, n'en etait pas un : jeu 32 bits, DXMT pose
# pour le 64 bits seulement, c'est le d3d11 builtin de Wine qui refusait
# (tests/sonde_heaps.sh) ; depuis, le lanceur pose DXMT i386 ou part en dxvk
# d'emblee. Le filet reste pour les vrais refus. Ce script lit le journal du
# lancement qui vient de finir et, si
# le jeu a ete lance en DXMT et porte une signature de refus, enregistre le
# repli d3d11 = dxvk dans le profil utilisateur de ce jeu, pour que le
# prochain lancement passe. Il ecrit ce qu'il a fait (une ligne, style
# journal) et rend 0 ; rien et 1 sinon. `cidre set <id> d3d11 dxmt` annule.
#
#   repli_dxmt.sh <id> <journal>
set -u
JEU=${1:?usage: repli_dxmt.sh <id> <journal>}
JOURNAL=${2:?usage: repli_dxmt.sh <id> <journal>}
R=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$JOURNAL" ] || exit 1
debut=$(grep -n '^=== ' "$JOURNAL" | tail -1 | cut -d: -f1)
S=$(tail -n +"${debut:-1}" "$JOURNAL")
a() { case $S in *"$1"*) return 0 ;; esac; return 1; }
# lance en DXMT ?
a "d3d11 : dxmt pose" || exit 1
# deja replie dans ce meme journal (on ne boucle pas)
a "repli automatique vers dxvk" && exit 1
# les signatures d'un refus au demarrage. « Failed to create swap chain » seul
# n'en est PAS une : Expedition 33 l'ecrit des centaines de fois et tourne.
if a "887A0004" || a "DXGI_ERROR_UNSUPPORTED" || a "Failed to initialize DirectX" \
   || { a "D3D11CreateDevice" && a "failed"; } || a "E_NOINTERFACE" && a "d3d11"; then
   sh "$R/tests/profil_cidre.sh" "$JEU" set d3d11 dxvk >/dev/null 2>&1 || exit 1
   echo "    d3d11 : repli automatique vers dxvk pour $JEU (DXMT refuse par le jeu au demarrage) -- cidre set $JEU d3d11 dxmt pour reessayer"
   exit 0
fi
exit 1
