#!/bin/sh
# Publie une release GitHub du runtime, DEPUIS ta machine (ou le build existe).
#   sh tests/publier_release.sh vX.Y.Z ["notes de release"]
# Empaquette puis cree/complete la release et y attache le tarball via gh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:?usage: publier_release.sh vX.Y.Z [notes]}
NOTES=${2:-"Runtime Cidre $TAG (pile deja compilee). Install : sh installer_cidre.sh"}
command -v gh >/dev/null || { echo "gh requis (brew install gh ; gh auth login)" >&2; exit 1; }

TARBALL="$R/cidre-runtime.tar.zst"
# Le .tar.xz est celui que telecharge Verger (macOS le decompresse sans zstd) :
# sans lui, Verger refuse la release.
TARBALL_XZ="$R/cidre-runtime.tar.xz"
echo "== empaquetage =="
CIDRE_VERSION=${TAG#v} sh "$R/tests/empaqueter_runtime.sh" "$TARBALL"
SZ=$(ls -lh "$TARBALL" | awk '{print $5}')

# Asset unique, executable : on genere un .command double-cliquable a partir de
# l'installeur (source unique de verite). Il va chercher le tarball de la release
# et l'installe. Le trap garde la fenetre Terminal ouverte pour afficher le bilan,
# meme si une etape echoue.
echo "== generation de l'asset executable (.command) =="
mkdir -p "$R/build"
CMD="$R/build/installer-cidre.command"
{
   echo '#!/bin/sh'
   echo '# cidre -- installeur double-cliquable (macOS Apple Silicon).'
   echo '# Premiere fois : clic droit > Ouvrir (Gatekeeper). Ou : sh ce-fichier.'
   echo 'cd "$HOME" || exit 1'
   echo 'trap '"'"'printf "\n[Entree pour fermer] "; read -r _'"'"' EXIT'
   tail -n +2 "$R/installer_cidre.sh"
} > "$CMD"
chmod +x "$CMD"

echo "== construction de l'app d'install (.app) =="
APPZIP="$R/build/Installer-Cidre.zip"
sh "$R/tests/construire_app_install.sh" "$APPZIP" >/dev/null && echo "  $APPZIP"

echo "== release $TAG ($SZ) =="
if gh release view "$TAG" -R gtranche/cidre >/dev/null 2>&1; then
   gh release upload "$TAG" "$TARBALL" "$TARBALL_XZ" "$CMD" "$APPZIP" "$R/installer_cidre.sh" \
      -R gtranche/cidre --clobber
else
   gh release create "$TAG" "$TARBALL" "$TARBALL_XZ" "$CMD" "$APPZIP" "$R/installer_cidre.sh" \
      -R gtranche/cidre --title "Cidre $TAG" --notes "$NOTES"
fi
echo "Publie : https://github.com/gtranche/cidre/releases/tag/$TAG"
echo "Asset a lancer : installer-cidre.command (double-clic) ou installer_cidre.sh (sh)"
