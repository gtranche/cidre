#!/bin/sh
# Mesure GPU-ms (CIDRE_GPU_STATS) + lancement direct d'un jeu Cidre quelconque,
# sans Steam. Barrieres selon le profil du jeu (ou forcees avec "narrow").
#
#   tests/mesure_jeu.sh <appid> <chemin-exe> [narrow]
#
# Log : build/logs/steam-<appid>.log (grep CIDRE_GPU). Suivi en direct :
#   tail -n0 -F build/logs/steam-<appid>.log | grep CIDRE_GPU
set -e
R=$(cd "$(dirname "$0")" && cd .. && pwd)
APPID=${1:?usage: mesure_jeu.sh <appid> <exe> [narrow]}
EXE=${2:?chemin executable requis}
[ -f "$EXE" ] || { echo "[mesure_jeu] introuvable : $EXE" >&2; exit 1; }

export CIDRE_GPU_STATS=1
[ "${3:-}" = narrow ] && { export CIDRE_NARROW_BARRIERS=1; echo "[mesure_jeu] barrieres forcees CIBLE" >&2; }

echo "[mesure_jeu] $APPID -> $(basename "$EXE") (GPU stats on)" >&2
exec env SteamAppId="$APPID" SteamGameId="$APPID" SteamOverlayGameId="$APPID" \
     sh "$R/tests/lancer_depuis_steam.sh" "$EXE"
