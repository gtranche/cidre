#!/bin/sh
# Installe un jeu depuis un installeur hors-ligne GOG (Windows) dans le prefixe.
#
#   installer_jeu.sh ~/Downloads/setup_braid_1.0_\(12345\).exe [nom]
#
# Les installeurs GOG sont des InnoSetup : ils acceptent une installation
# silencieuse. Le jeu atterrit dans C:\Jeux\<nom> du prefixe, et le script
# affiche les executables trouves, a passer ensuite a lancer_jeu.sh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

[ $# -ge 1 ] || { echo "usage : $(basename "$0") installeur.exe [nom]" >&2; exit 2; }
src=$1
[ -f "$src" ] || { echo "introuvable : $src" >&2; exit 2; }

nom=${2:-$(basename "$src" .exe | sed 's/^setup_//; s/_[0-9].*$//')}
pfx=${WINEPREFIX:-$R/wine/pfx-wow64}
dst="$pfx/drive_c/Jeux/$nom"

printf 'installation de « %s » dans C:\\Jeux\\%s\n' "$nom" "$nom"
mkdir -p "$(dirname "$dst")"

WINEPREFIX=$pfx "$R/tests/etape2_pile_wow64.sh" "$src" \
   /VERYSILENT /SUPPRESSMSGBOXES /NOGUI /NORESTART /NOICONS \
   "/DIR=C:\\Jeux\\$nom" || {
      echo "l'installation silencieuse a echoue ; relance sans /VERYSILENT pour voir la fenetre" >&2
      exit 1
   }

echo
if [ -d "$dst" ]; then
   echo "executables installes :"
   find "$dst" -maxdepth 3 -iname "*.exe" ! -iname "unins*" 2>/dev/null | sed "s|^|   |"
   echo
   echo "lancer avec :"
   echo "   tests/lancer_jeu.sh '<un des chemins ci-dessus>'"
else
   echo "rien dans $dst : l'installeur a peut-etre choisi un autre repertoire" >&2
   exit 1
fi
