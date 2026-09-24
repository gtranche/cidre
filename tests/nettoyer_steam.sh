#!/bin/sh
# Remet la configuration Steam dans l'etat ou on l'a trouvee.
#
# Quatre choses ont ete posees pendant les essais de la journee. Trois se sont
# revelees sans effet et sont retirees ; la quatrieme, steam_dev.cfg, est la
# seule qui marche et n'est retiree qu'avec --tout.
#
#   nettoyer_steam.sh          retire ce qui ne sert a rien
#   nettoyer_steam.sh --tout   retire aussi steam_dev.cfg
set -e
S=$HOME/Library/Application\ Support/Steam

if pgrep -f "steam_osx" >/dev/null; then
   echo "Steam tourne : il reecrirait ses fichiers en quittant. Arrete-le d'abord."
   exit 1
fi

# 1. L'outil de compatibilite, que le client macOS ne scanne jamais (section 188).
if [ -L "$S/compatibilitytools.d/proton-ouvert" ]; then
   rm "$S/compatibilitytools.d/proton-ouvert"
   rmdir "$S/compatibilitytools.d" 2>/dev/null || true
   echo "retire : le lien dans compatibilitytools.d"
fi

# 2. La table de correspondance, lue mais jamais suivie d'effet.
C="$S/config/config.vdf"
if [ -f "$C.avant-proton-ouvert" ]; then
   mv "$C.avant-proton-ouvert" "$C"
   echo "restaure : config.vdf"
fi

# 3. Le raccourci non-Steam vers DREDGE, qui servait de sonde.
U=$(ls -d "$S"/userdata/[0-9]* 2>/dev/null | head -1)
if [ -n "$U" ] && [ -f "$U/config/shortcuts.vdf.avant-proton-ouvert" ]; then
   mv "$U/config/shortcuts.vdf.avant-proton-ouvert" "$U/config/shortcuts.vdf"
   rm -f "$U/config/shortcuts.vdf.guillemets"
   echo "restaure : shortcuts.vdf"
fi

# 4. Le seul qui marche : il debloque le telechargement des jeux Windows.
if [ "$1" = "--tout" ]; then
   rm -f "$S/Steam.AppBundle/Steam/Contents/MacOS/steam_dev.cfg"
   echo "retire : steam_dev.cfg — les jeux Windows redeviennent indisponibles"
else
   echo "garde  : steam_dev.cfg (--tout pour le retirer aussi)"
fi
