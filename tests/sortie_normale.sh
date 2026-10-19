#!/bin/sh
# Un jeu sorti sur un code d'erreur : est-ce, pour CE jeu, sa fin normale ?
# Certains jeux se ferment toujours sur un code non nul, sans rien perdre :
# Fahrenheit Remastered (312840) sort sur 1 a chaque fermeture par son menu,
# apres avoir vide ses pools memoire et sauvegarde (M4, 2026-10-19). Verger
# affichait une alerte « sans signature connue » a chaque partie.
#
# La fiche le dit (profils/README.md, outil-steam/profils.toml) :
#   sortie_normale = "1"          codes de fin normale, separes par des espaces
#   sortie_normale_apres = 60     apres combien de secondes de jeu au moins (60 par
#                                 defaut) : un jeu qui tombe au demarrage sur ce
#                                 meme code reste une erreur
#
#   sortie_normale.sh <code> <secondes de jeu> <codes> [<secondes minimum>]
#
# Sort sur 0 et ecrit la ligne du journal quand la sortie est normale ; sur 1,
# sans rien ecrire, sinon. Le lanceur garde alors le journal tel quel, n'appelle
# pas expliquer_sortie.sh et sort sur 0 (pas d'alerte dans Verger).
set -u
RC=${1:?usage: sortie_normale.sh <code> <secondes> <codes> [<minimum>]}
DUREE=${2:?usage: sortie_normale.sh <code> <secondes> <codes> [<minimum>]}
CODES=$(printf '%s' "${3:-}" | tr -d '"' | tr ',;' '  ')
MIN=$(printf '%s' "${4:-}" | tr -d '"')
case $MIN in ''|*[!0-9]*) MIN=60 ;; esac
case $RC in ''|*[!0-9]*|0) exit 1 ;; esac
case $DUREE in ''|*[!0-9]*) exit 1 ;; esac
for c in $CODES; do
   [ "$c" = "$RC" ] || continue
   [ "$DUREE" -ge "$MIN" ] || exit 1
   echo "    le jeu s'est ferme sur le code $RC apres $DUREE s : fin normale pour ce jeu (fiche : sortie_normale = \"$(echo $CODES)\", des $MIN s de jeu)"
   exit 0
done
exit 1
