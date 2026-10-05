#!/bin/sh
# Chantier barrieres : mesure A/B SURE du GPU-ms de VT2 (552500), sans capture
# Metal (la capture tue VT2). Lance VT2 directement par la pile Cidre, Steam
# reste natif. Logue le GPU-ms/soumission via le feedback MTL4.
#
# Usage :
#   tests/mesure_vt2.sh            # baseline : barrieres ALL->ALL (connu-bon)
#   tests/mesure_vt2.sh narrow     # relachement CIBLE (stages reelles par type)
#   tests/mesure_vt2.sh global     # ancien relachement GLOBAL frag->frag (debug)
#
# Protocole : lancer en baseline, entrer dans la Forteresse, laisser tourner
# ~10 s (plusieurs lignes [CIDRE_GPU] dans le log), noter GPU-ms/soum moy, quitter.
# Relancer avec `narrow`, MEME scene, comparer le GPU-ms ET verifier le rendu
# (artefacts ?). GPU-ms plus bas + rendu correct = gain reel. Inchange = pas de
# gain (barrieres pas le goulot). Artefacts = barrieres portantes (hazard rate).
#
# Suivre en direct :
#   tail -f build/logs/steam-552500.log | grep CIDRE_GPU
set -e
R=$(cd "$(dirname "$0")" && cd .. && pwd)

export CIDRE_GPU_STATS=1
case "${1:-baseline}" in
   narrow) export CIDRE_NARROW_BARRIERS=1
           echo "[mesure_vt2] barrieres RELACHEES CIBLE (stages par type)" >&2 ;;
   global) export CIDRE_NARROW_BARRIERS=global
           echo "[mesure_vt2] barrieres RELACHEES GLOBAL frag->frag (debug)" >&2 ;;
   baseline|"") echo "[mesure_vt2] barrieres baseline (ALL->ALL, connu-bon)" >&2 ;;
   *) echo "usage: mesure_vt2.sh [baseline|narrow|global]" >&2; exit 2 ;;
esac

APPID=552500
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Warhammer Vermintide 2/binaries/vermintide2.exe"
[ -f "$GAME" ] || { echo "[mesure_vt2] introuvable : $GAME" >&2; exit 1; }
echo "[mesure_vt2] GPU-ms -> $R/build/logs/steam-552500.log (grep CIDRE_GPU)" >&2
exec env SteamAppId=$APPID SteamGameId=$APPID SteamOverlayGameId=$APPID \
     sh "$R/tests/lancer_depuis_steam.sh" "$GAME"
