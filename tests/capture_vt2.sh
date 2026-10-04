#!/bin/sh
# Diagnostic : capture Metal BORNEE d'une frame VT2 en jeu (chantier barrieres).
#
# A poser dans les options de lancement Steam de Vermintide 2 (appid 552500),
# suivi de %command% :
#
#   /chemin/vers/cidre/tests/capture_vt2.sh %command%
#
# Puis : lancer le jeu, entrer dans la Forteresse (scene de reference, GPU 100 %).
# Une fois la vue stable, depuis un terminal :
#
#   touch /tmp/cidre_capture_now
#
# -> les 2 frames suivantes sont capturees dans un .gputrace, la capture s'arrete
# seule. Ouvrir le .gputrace avec Xcode (double-clic) : la timeline par encodeur
# dit si les passes ont des TROUS (bulles de synchro -> alleger les barrieres =
# vrai gain) ou sont COLLEES (GPU sature -> viser le bandwidth / memoryless).
#
# Suivre la confirmation depuis un terminal :
#   tail -f build/logs/steam-552500.log | grep CIDRE_CAPTURE
#
# NE PAS combiner avec MESA_KK_GPU_CAPTURE=1 (capture session entiere, inutilisable).
set -e
R=$(cd "$(dirname "$0")" && cd .. && pwd)

# Apple exige ce drapeau pour autoriser la capture GPU programmatique.
export MTL_CAPTURE_ENABLED=1

# Mecanisme de capture du driver KosmicKrisp (voir kk_wsi.c, kk_capture_on_present).
export CIDRE_CAPTURE_SENTINEL="${CIDRE_CAPTURE_SENTINEL:-/tmp/cidre_capture_now}"
export CIDRE_CAPTURE_NFRAMES="${CIDRE_CAPTURE_NFRAMES:-2}"
export MESA_KK_GPU_CAPTURE_DIRECTORY="${MESA_KK_GPU_CAPTURE_DIRECTORY:-$HOME/Desktop}"

# Sentinelle propre au demarrage : on ne capture pas une frame de chargement.
rm -f "$CIDRE_CAPTURE_SENTINEL"

echo "[capture_vt2] arme. En Forteresse, faire : touch $CIDRE_CAPTURE_SENTINEL" >&2
echo "[capture_vt2] .gputrace -> $MESA_KK_GPU_CAPTURE_DIRECTORY" >&2

exec sh "$R/tests/lancer_depuis_steam.sh" "$@"
