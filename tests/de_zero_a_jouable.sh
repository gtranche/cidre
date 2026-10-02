#!/bin/sh
# Orchestrateur : d'un Mac (presque) neuf a un jeu Windows jouable par Steam.
# Enchaine les etapes, chacune idempotente, et s'arrete a la premiere erreur.
#
#   sh tests/de_zero_a_jouable.sh
#
# NOTE : les deux Homebrew (Intel + arm64) et Xcode CLT restent a installer a la
# main (etape0_prerequis les verifie et le dit). Le reste est automatique.
# Les recettes de build sont exactes (recuperees des builds configures) mais la
# seule epreuve qui compte est une vraie machine neuve.
set -e
R=$(cd "$(dirname "$0")" && cd .. && pwd)
cd "$R"

etape() { echo; echo "########## $1"; }

etape "0/6  Prerequis systeme"
sh tests/etape0_prerequis.sh || { echo "Corrigez les prerequis (voir ci-dessus) puis relancez." >&2; exit 1; }

etape "1/6  Toolchain (llvm-mingw)"
sh tests/etape0_toolchain.sh

etape "2/6  Clonage des arbres amont + patches"
[ -d src/mesa/.git ] && [ -d third_party/FEX/.git ] || sh tests/etape1_appliquer_correctifs.sh --cloner
sh tests/etape1_appliquer_correctifs.sh

etape "3/6  Construction de FEX (+ installation dans Wine)"
sh tests/construire_fex.sh --installer

etape "4/6  Construction de la pile arm64 (Mesa, Wine, DXVK)"
sh tests/construire_pile_arm64.sh

etape "5/6  Prefixe Wine + DXVK"
export WINEPREFIX="$R/wine/pfx-arm64ec"
if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
   WINEDEBUG=-all "$R/wine/wine11-arm64/bin/wineboot" -u || true
fi
# DXVK async (gplasync) dans le prefixe (dxgi/d3d11), + FEX
P="$WINEPREFIX/drive_c/windows/system32"
for d in d3d11 dxgi; do
   cp "$R/build/dxvk-async-winarm64ec/src/$d/$d.dll" "$P/$d.dll" 2>/dev/null || true
done
WINEPREFIX="$WINEPREFIX" sh tests/installer_fex.sh >/dev/null 2>&1 || true

etape "6/6  Integration Steam (bouton Jouer)"
echo "Fermez Steam, puis :"
echo "  sh tests/brancher_jeux_steam.sh --ecrire     # pose l'option sur les jeux Windows-only"
echo "  sh tests/installer_agent_steam.sh            # agent qui la remet apres chaque reecriture"
echo
echo "FINI. Installez vos jeux Windows dans Steam, cliquez Jouer."
echo "(Besoins par jeu -- ex. Vermintide 2 : LuaJIT + -eac-untrusted -- deja cables"
echo " dans lancer_depuis_steam.sh.)"
