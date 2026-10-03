#!/bin/sh
# Comme lancer_depuis_steam.sh, mais pour un jeu EAC-EOS qu'on veut demarrer en
# mode NON PROTEGE (hors ligne / solo).
#
# A poser dans les options de lancement du jeu, dans Steam :
#
#   /chemin/vers/cidre/tests/lancer_eos_depuis_steam.sh %command%
#
# On exporte l'interrupteur officiel d'Epic EOS_USE_ANTICHEATCLIENTNULL : l'amorceur
# start_protected_game.exe le reconnait, saute le telechargement et le mappage du
# module anti-triche, et lance le jeu avec un « null client ». Ce n'est pas un
# contournement -- c'est une fonction de l'amorceur d'Epic, journalisee en clair --
# et ca ne donne que les modes que Epic place hors du perimetre de l'anti-triche
# (hors ligne, solo, non protege). Les parties en ligne protegees restent refusees
# cote serveur, et c'est voulu.
#
# Tout le reste (pont Steam, faux client de service, pile arm64ec) est delegue a
# lancer_depuis_steam.sh, inchange.
set -e
export EOS_USE_ANTICHEATCLIENTNULL=1
R=$(cd "$(dirname "$0")" && pwd)
exec sh "$R/lancer_depuis_steam.sh" "$@"
