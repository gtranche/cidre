#!/bin/sh
# Publie une release GitHub du runtime, DEPUIS ta machine (ou le build existe).
#   sh tests/publier_release.sh vX.Y.Z ["notes de release"]
# Empaquette puis cree/complete la release et y attache le tarball via gh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:?usage: publier_release.sh vX.Y.Z [notes]}
NOTES=${2:-"Runtime proton-ouvert $TAG (pile deja compilee). Install : sh installer_proton_ouvert.sh"}
command -v gh >/dev/null || { echo "gh requis (brew install gh ; gh auth login)" >&2; exit 1; }

TARBALL="$R/proton-ouvert-runtime.tar.zst"
echo "== empaquetage =="
sh "$R/tests/empaqueter_runtime.sh" "$TARBALL"
SZ=$(ls -lh "$TARBALL" | awk '{print $5}')

# Asset unique, executable : on genere un .command double-cliquable a partir de
# l'installeur (source unique de verite). Il va chercher le tarball de la release
# et l'installe. Le trap garde la fenetre Terminal ouverte pour afficher le bilan,
# meme si une etape echoue.
echo "== generation de l'asset executable (.command) =="
mkdir -p "$R/build"
CMD="$R/build/installer-proton-ouvert.command"
{
   echo '#!/bin/sh'
   echo '# proton-ouvert -- installeur double-cliquable (macOS Apple Silicon).'
   echo '# Premiere fois : clic droit > Ouvrir (Gatekeeper). Ou : sh ce-fichier.'
   echo 'cd "$HOME" || exit 1'
   echo 'trap '"'"'printf "\n[Entree pour fermer] "; read -r _'"'"' EXIT'
   tail -n +2 "$R/installer_proton_ouvert.sh"
} > "$CMD"
chmod +x "$CMD"

echo "== release $TAG ($SZ) =="
if gh release view "$TAG" -R gtranche/proton-ouvert >/dev/null 2>&1; then
   gh release upload "$TAG" "$TARBALL" "$CMD" "$R/installer_proton_ouvert.sh" \
      -R gtranche/proton-ouvert --clobber
else
   gh release create "$TAG" "$TARBALL" "$CMD" "$R/installer_proton_ouvert.sh" \
      -R gtranche/proton-ouvert --title "proton-ouvert $TAG" --notes "$NOTES"
fi
echo "Publie : https://github.com/gtranche/proton-ouvert/releases/tag/$TAG"
echo "Asset a lancer : installer-proton-ouvert.command (double-clic) ou installer_proton_ouvert.sh (sh)"
