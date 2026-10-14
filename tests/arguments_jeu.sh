#!/bin/sh
# Arguments de ligne de commande a ajouter au jeu, depuis l'option `arguments` d'une
# fiche (ou CIDRE_ARGUMENTS) : une chaine, arguments separes par des espaces, sans
# guillemets ni echappement (un argument qui contient un espace n'est pas pris en
# charge). Rend un argument par ligne, dans l'ordre. Une option (argument qui
# commence par `-`) que la ligne de commande porte deja n'est pas ajoutee, ni les
# valeurs qui la suivent (Steam peut transmettre les memes options de lancement :
# `-window-mode windowed` deja present -> `-window-mode borderless` est ignore).
# Aucune expansion : `*` ou `?` restent tels quels.
#   arguments_jeu.sh "<chaine>" [arguments deja presents...]
set -f
CHAINE=${1:-}; [ $# -gt 0 ] && shift
sauter=non
for a in $CHAINE; do
   case $a in
      -*)
         sauter=non
         for b in "$@"; do [ "$a" = "$b" ] && { sauter=oui; break; }; done ;;
   esac
   [ $sauter = oui ] || printf '%s\n' "$a"
done
