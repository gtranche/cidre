#!/bin/sh
# Construit cidre-outil (tests/cidre_outil.c) : le pseudo-terminal de SteamCMD et
# la lecture des caches binaires de Steam, pour le script `cidre`.
#
#   construire_cidre_outil.sh [source.c [sortie]]
#
# Sur la machine de build seulement. L'empaqueteur livre le binaire dans le
# runtime (build/cidre-outil) ; un depot de developpement le construit au
# premier besoin (`cidre` le fait de lui-meme).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:-$R/tests/cidre_outil.c}
OUT=${2:-$R/build/cidre-outil}
mkdir -p "$(dirname "$OUT")"
# Par un fichier voisin puis mv : une autre commande `cidre` peut etre en train
# d'executer l'ancien.
cc -arch arm64 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -o "$OUT.$$" "$SRC"
mv "$OUT.$$" "$OUT"
