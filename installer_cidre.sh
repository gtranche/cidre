#!/bin/sh
# Installe Cidre (runtime deja compile) pour JOUER. Ne construit rien.
#
#   sh installer_cidre.sh [DESTINATION] [chemin/vers/runtime.tar.zst | URL]
#
# Par defaut : installe sous ~/Library/Application Support/cidre et va
# chercher le tarball de la derniere release si aucun n'est fourni.
set -e
DEST=${1:-$HOME/Library/Application Support/cidre}
SRC=${2:-}
REPO="gtranche/cidre"
REL_URL="https://github.com/$REPO/releases/latest/download/cidre-runtime.tar.zst"

command -v zstd >/dev/null || { echo "zstd requis (brew install zstd)" >&2; exit 1; }
# Le driver Vulkan livre (libvulkan_kosmickrisp.dylib) lie libSPIRV-Tools.dylib
# par chemin absolu Homebrew : sans lui, l'ICD ne se charge pas et rien ne rend.
[ -f /opt/homebrew/opt/spirv-tools/lib/libSPIRV-Tools.dylib ] || { echo "SPIRV-Tools requis -> brew install spirv-tools" >&2; MANQUE_SPIRV=1; }
# Wine rasterise ses polices avec FreeType (tranche arm64 de Homebrew). Sans lui :
# « Wine cannot find the FreeType font library » et aucun texte a l'ecran -- vrai
# prerequis. fontconfig n'est QUE pour l'appariement des polices systeme ; la pile
# tourne sans (Wine embarque ses .fon), donc on le signale comme recommande, pas du.
[ -f /opt/homebrew/lib/libfreetype.6.dylib ] || { echo "  ATTENTION : FreeType absent -> brew install freetype  (sinon : pas de texte)" >&2; MANQUE_FONTES=1; }
[ -f /opt/homebrew/lib/libfontconfig.1.dylib ] || echo "  (optionnel : brew install fontconfig pour un meilleur appariement des polices)"
mkdir -p "$DEST"

echo "== 1. Recuperation du runtime =="
TAR=""
if [ -n "$SRC" ] && [ -f "$SRC" ]; then TAR="$SRC"; echo "  tarball local : $SRC"
else
   URL=${SRC:-$REL_URL}; TAR="$DEST/.runtime.tar.zst"
   echo "  telechargement : $URL"
   if ! curl -fL --retry 3 -o "$TAR" "$URL"; then
      # Depot prive : l'URL publique 404 sans authentification. Repli via gh,
      # s'il est installe et connecte avec acces au depot. (Le jour ou le depot
      # est public, le curl ci-dessus suffit et ce repli ne sert plus.)
      echo "  URL publique indisponible (depot prive ?) -> tentative via gh"
      rm -f "$TAR"
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
         gh release download -R "$REPO" -p "cidre-runtime.tar.zst" -O "$TAR" --clobber \
            || { echo "echec gh (pas d'acces au depot ?). Rendez le depot public, ou passez un tarball local :  sh installer_cidre.sh \"$DEST\" /chemin/runtime.tar.zst" >&2; exit 1; }
      else
         echo "Asset inaccessible : depot prive et gh absent/non connecte." >&2
         echo "  - soit : brew install gh ; gh auth login   (acces au depot requis)" >&2
         echo "  - soit : rendez le depot public (l'URL publique marchera alors)" >&2
         echo "  - soit : fournissez un tarball local en 2e argument." >&2
         exit 1
      fi
   fi
fi

echo "== 2. Decompression dans $DEST =="
zstd -dc "$TAR" | ( cd "$DEST" && tar xf - )
R="$DEST/cidre"
[ -d "$R/wine/wine11-arm64" ] || { echo "runtime invalide (wine absent)" >&2; exit 1; }

echo "== 3. Configuration (cidre setup) =="
# La configuration voyage avec le runtime : c'est la meme que lance Verger.
sh "$R/tests/configurer_cidre.sh"

echo
[ -n "${MANQUE_FONTES:-}" ] && echo "RAPPEL : brew install freetype  (requis pour afficher le texte)"
[ -n "${MANQUE_SPIRV:-}" ] && echo "RAPPEL : brew install spirv-tools  (requis : le driver Vulkan en depend)"
echo "INSTALLE sous $R"
echo "Lancez un jeu Windows depuis Steam (bouton Jouer). Les scripts attendent la"
echo "pile a cet emplacement ; ne le deplacez pas sans relancer l'etape 3."
