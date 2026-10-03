#!/bin/sh
# Construit l'app d'install native "Installer Cidre.app" a partir de
# l'applet AppleScript + l'installeur embarque, et la zippe pour la release.
#   sh tests/construire_app_install.sh [sortie.zip]
# L'app telecharge le runtime (barre de progression native) puis delegue la
# config a installer_cidre.sh (source unique de verite, embarquee).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$R/build/Installer-Cidre.zip}
APP="$R/build/Installer Cidre.app"
command -v osacompile >/dev/null || { echo "osacompile absent (macOS requis)" >&2; exit 1; }

mkdir -p "$R/build"
rm -rf "$APP"
echo "== compilation de l'applet =="
osacompile -o "$APP" "$R/app/installeur.applescript"

echo "== embarquer l'installeur (source unique) =="
cp "$R/installer_cidre.sh" "$APP/Contents/Resources/installer_cidre.sh"

echo "== Info.plist (identite, version, hidpi) =="
PL="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PL" >/dev/null 2>&1 || true; }
pb "Set :CFBundleName Installer Cidre"
pb "Add :CFBundleDisplayName string Installer Cidre" ; pb "Set :CFBundleDisplayName Installer Cidre"
pb "Add :CFBundleIdentifier string org.cidre.installeur" ; pb "Set :CFBundleIdentifier org.cidre.installeur"
pb "Add :CFBundleShortVersionString string 1.0.0" ; pb "Set :CFBundleShortVersionString 1.0.0"
pb "Add :CFBundleVersion string 1" ; pb "Set :CFBundleVersion 1"
pb "Add :LSMinimumSystemVersion string 13.0" ; pb "Set :LSMinimumSystemVersion 13.0"
pb "Add :NSHighResolutionCapable bool true" ; pb "Set :NSHighResolutionCapable true"
pb "Add :LSApplicationCategoryType string public.app-category.utilities"

echo "== zip (ditto, preserve le bundle) =="
rm -f "$OUT"
( cd "$R/build" && ditto -c -k --sequesterRsrc --keepParent "Installer Cidre.app" "$OUT" )
echo
echo "APP : $APP"
echo "ZIP : $OUT"
ls -lh "$OUT" | awk '{print "  taille : "$5}'
