#!/bin/sh
# Lance un executable Windows a travers la pile ouverte.
#
#   lancer_jeu.sh /chemin/vers/jeu.exe [arguments...]
#
# Se place dans le repertoire de l'executable, ce dont la plupart des jeux ont
# besoin pour trouver leurs donnees, puis delegue a etape2_pile_wine.sh.
#
# Utilisable directement comme cible d'un « jeu non-Steam » dans le Steam macOS
# natif : ajouter ce script, et mettre le chemin du .exe en argument de lancement.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

[ $# -ge 1 ] || { echo "usage : $(basename "$0") jeu.exe [arguments...]" >&2; exit 2; }

exe=$1; shift
[ -f "$exe" ] || { echo "introuvable : $exe" >&2; exit 2; }

exe=$(cd "$(dirname "$exe")" && pwd)/$(basename "$exe")
cd "$(dirname "$exe")"

exec "$R/tests/etape2_pile_wine.sh" "$exe" "$@"
