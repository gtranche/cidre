#!/bin/sh
# Construit l'app d'install native "Installer proton-ouvert.app" a partir de
# l'applet AppleScript + l'installeur embarque, et la zippe pour la release.
#   sh tests/construire_app_install.sh [sortie.zip]
# L'app telecharge le runtime (barre de progression native) puis delegue la
# config a installer_proton_ouvert.sh (source unique de verite, embarquee).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$R/build/Installer-proton-ouvert.zip}
APP="$R/build/Installer proton-ouvert.app"
command -v osacompile >/dev/null || { echo "osacompile absent (macOS requis)" >&2; exit 1; }

mkdir -p "$R/build"
rm -rf "$APP"
echo "== compilation de l'applet =="
osacompile -o "$APP" "$R/app/installeur.applescript"

echo "== embarquer l'installeur (source unique) =="
cp "$R/installer_proton_ouvert.sh" "$APP/Contents/Resources/installer_proton_ouvert.sh"

echo "== Info.plist (identite, version, hidpi) =="
PL="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PL" >/dev/null 2>&1 || true; }
pb "Set :CFBundleName Installer proton-ouvert"
pb "Add :CFBundleDisplayName string Installer proton-ouvert" ; pb "Set :CFBundleDisplayName Installer proton-ouvert"
pb "Add :CFBundleIdentifier string org.protonouvert.installeur" ; pb "Set :CFBundleIdentifier org.protonouvert.installeur"
pb "Add :CFBundleShortVersionString string 1.0.0" ; pb "Set :CFBundleShortVersionString 1.0.0"
pb "Add :CFBundleVersion string 1" ; pb "Set :CFBundleVersion 1"
pb "Add :LSMinimumSystemVersion string 13.0" ; pb "Set :LSMinimumSystemVersion 13.0"
pb "Add :NSHighResolutionCapable bool true" ; pb "Set :NSHighResolutionCapable true"
pb "Add :LSApplicationCategoryType string public.app-category.utilities"

echo "== zip (ditto, preserve le bundle) =="
rm -f "$OUT"
( cd "$R/build" && ditto -c -k --sequesterRsrc --keepParent "Installer proton-ouvert.app" "$OUT" )
echo
echo "APP : $APP"
echo "ZIP : $OUT"
ls -lh "$OUT" | awk '{print "  taille : "$5}'
