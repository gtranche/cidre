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
echo "== release $TAG ($SZ) =="
if gh release view "$TAG" -R gtranche/proton-ouvert >/dev/null 2>&1; then
   gh release upload "$TAG" "$TARBALL" -R gtranche/proton-ouvert --clobber
else
   gh release create "$TAG" "$TARBALL" -R gtranche/proton-ouvert \
      --title "proton-ouvert $TAG" --notes "$NOTES"
fi
echo "Publie : https://github.com/gtranche/proton-ouvert/releases/tag/$TAG"
