#!/bin/sh
# Ce que Cidre sait de la machine, pour les variantes par machine des fiches de
# la base de profils (blocs [[machine]], cf. profils/README.md) : un jeu limite
# par la carte graphique ne se regle pas pareil sur un M1 Max et sur un M4 de
# base branche sur un ecran 4,5K.
#
#   machine.sh [fait ...]        les faits demandes (tous sans argument), une ligne `fait=valeur`
#   machine.sh json              tous les faits, en JSON
#   machine.sh si "<condition>"  code 0 si la condition est vraie sur cette machine, 1 sinon
#   machine.sh syntaxe "<condition>"   code 0 si la condition est bien formee (faits connus), 2 sinon
#
# Faits :
#   puce            le nom de la puce ("Apple M4", "Apple M1 Max")
#   coeurs_gpu      nombre de coeurs de la carte graphique (10 sur un M4 de base)
#   memoire_go      memoire vive, en Go
#   ecran_largeur   largeur de l'ecran principal en points -- ce que le jeu voit en
#   ecran_hauteur   plein ecran (2240 x 1260 sur un iMac 4,5K, 1728 x 1117 sur un
#                   MacBook Pro 16") ; lu par system_profiler (~0,3 s), seulement
#                   si on le demande
#
# Une condition : `fait op nombre`, op parmi <= >= < > == !=, plusieurs termes
# relies par ` et ` (tous vrais). Seuls les faits numeriques se comparent. Une
# condition mal formee, un fait inconnu (code 2) ou illisible sur cette machine
# (code 1) : la condition n'est pas vraie, la variante ne s'applique pas, la
# partie commune de la fiche sert.
#
# CIDRE_MACHINE="coeurs_gpu=10 ecran_largeur=2240" remplace les faits nommes par
# ces valeurs (tests, ou essayer la variante d'une autre machine).
set -u

force() { # <fait> : sa valeur dans CIDRE_MACHINE, code 1 s il n y est pas
   for kv in ${CIDRE_MACHINE:-}; do
      case $kv in "$1="*) printf '%s\n' "${kv#*=}"; return 0 ;; esac
   done
   return 1
}
ECRAN=
ecran() { # "largeur hauteur" de l ecran principal, en points ; lu une fois
   [ -n "$ECRAN" ] || ECRAN=$(system_profiler SPDisplaysDataType 2>/dev/null | awk '
      # un bloc par ecran : Resolution, puis au besoin « UI Looks like », puis Main Display
      /Resolution:/ { l = $2; h = $4; if ($0 ~ /Retina/) { l = int(l / 2); h = int(h / 2) } if (!premier) premier = l " " h }
      /UI Looks like:/ { l = $4; h = $6 }
      /Main Display: Yes/ { print l, h; vu = 1; exit }
      END { if (!vu && premier) print premier }')
   printf '%s\n' "${ECRAN:-0 0}"
}
fait() { # <nom> : la valeur, vide si le fait est inconnu
   force "$1" && return
   case $1 in
      puce) sysctl -n machdep.cpu.brand_string 2>/dev/null ;;
      coeurs_gpu) ioreg -rc AGXAccelerator -d1 2>/dev/null | sed -n 's/.*"gpu-core-count" = \([0-9]*\).*/\1/p' | head -1 ;;
      memoire_go) echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) ;;
      ecran_largeur) ecran | cut -d' ' -f1 ;;
      ecran_hauteur) ecran | cut -d' ' -f2 ;;
   esac
}
TOUS="puce coeurs_gpu memoire_go ecran_largeur ecran_hauteur"

case ${1:-} in
   json)
      printf '{'; sep=
      for f in $TOUS; do
         v=$(fait "$f")
         case $v in ''|*[!0-9]*) v="\"$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')\"" ;; esac
         printf '%s"%s":%s' "$sep" "$f" "$v"; sep=,
      done
      echo '}' ;;
   si|syntaxe)
      # chaque terme `fait op nombre` ; le premier faux (ou mal forme) arrete
      mode=$1; reste=${2:-}
      [ -n "$reste" ] || exit 2
      while [ -n "$reste" ]; do
         case $reste in *" et "*) terme=${reste%%" et "*}; reste=${reste#*" et "} ;; *) terme=$reste; reste= ;; esac
         set -- $terme
         [ $# -eq 3 ] || exit 2
         case $1 in coeurs_gpu|memoire_go|ecran_largeur|ecran_hauteur) ;; *) exit 2 ;; esac
         case $2 in '<='|'>='|'<'|'>'|'=='|'!=') ;; *) exit 2 ;; esac
         case $3 in ''|*[!0-9]*) exit 2 ;; esac
         [ "$mode" = si ] || continue
         v=$(fait "$1")
         case $v in ''|*[!0-9]*) exit 1 ;; esac
         case $2 in
            '<=') [ "$v" -le "$3" ] ;; '>=') [ "$v" -ge "$3" ] ;;
            '<')  [ "$v" -lt "$3" ] ;; '>')  [ "$v" -gt "$3" ] ;;
            '==') [ "$v" -eq "$3" ] ;; '!=') [ "$v" -ne "$3" ] ;;
         esac || exit 1
      done
      exit 0 ;;
   *)
      for f in ${*:-$TOUS}; do echo "$f=$(fait "$f")"; done ;;
esac
