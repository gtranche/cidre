#!/bin/sh
# Ce que Cidre sait de la machine, pour les variantes par machine des fiches de
# la base de profils (blocs [[machine]] et [[compat.machines]], cf.
# profils/README.md) : un jeu limite par la carte graphique ne se regle pas
# pareil sur un M1 Max et sur un M4 de base branche sur un ecran 4,5K, et un jeu
# qui a besoin des atomiques 64 bits de Metal ne passe en D3D12 qu'a partir du M2.
#
#   machine.sh [fait ...]        les faits demandes (tous sans argument), une ligne `fait=valeur`
#   machine.sh json [fait ...]   les faits demandes (tous sans argument), en JSON
#   machine.sh si "<condition>"  code 0 si la condition est vraie sur cette machine, 1 sinon
#   machine.sh syntaxe "<condition>"   code 0 si la condition est bien formee (faits connus), 2 sinon
#
# Faits :
#   puce            le nom de la puce ("Apple M4", "Apple M1 Max"), pour l'affichage
#   generation      le numero de la puce : 1 pour un M1, M1 Pro, M1 Max ou M1 Ultra, 4 pour un M4
#   gamme           base, pro, max ou ultra
#   famille_gpu     la famille Metal de la carte graphique, la plus haute que Metal
#                   reconnait (MTLGPUFamilyApple<N>) : 7 = M1, 8 = M2, 9 = M3 et M4.
#                   C'est elle qui dit ce que la carte sait faire (les atomiques
#                   64 bits min/max a partir de 8). Lue par un appel a Metal
#                   (osascript, ~0,1 s), sinon par la generation de l'AGX (ioreg)
#   coeurs_gpu      nombre de coeurs de la carte graphique (10 sur un M4 de base)
#   memoire_go      memoire vive, en Go
#   ecran_largeur   largeur de l'ecran principal en points -- ce que le jeu voit en
#   ecran_hauteur   plein ecran (2240 x 1260 sur un iMac 4,5K, 1728 x 1117 sur un
#                   MacBook Pro 16") ; lu par system_profiler (~0,3 s), seulement
#                   si on le demande
#   macos           la version majeure de macOS (26, 27)
#   macos_version   la version complete ("26.5.2"), pour l'affichage
#
# Une condition : `fait op valeur`, plusieurs termes relies par ` et ` (tous
# vrais). Les faits numeriques (generation, famille_gpu, coeurs_gpu, memoire_go,
# ecran_largeur, ecran_hauteur, macos) se comparent a un nombre, op parmi
# <= >= < > == != ; `gamme` se compare a un mot, par == ou != seulement
# (`gamme == max`). puce et macos_version ne se comparent pas. Une condition mal
# formee, un fait inconnu (code 2) ou illisible sur cette machine (code 1) : la
# condition n'est pas vraie, la variante ne s'applique pas, la partie commune de
# la fiche sert. Un runtime d'avant un fait (famille_gpu, generation, gamme,
# macos : Cidre <= 1.5.11) le tient pour inconnu.
#
# CIDRE_MACHINE="coeurs_gpu=10 famille_gpu=9" remplace les faits nommes par ces
# valeurs (tests, ou essayer la variante d'une autre machine).
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
puce() { force puce || sysctl -n machdep.cpu.brand_string 2>/dev/null; }
famille_gpu() {
   # Metal lui-meme : la plus haute MTLGPUFamilyApple<N> (1000 + N) reconnue
   f=$(osascript -l JavaScript -e 'ObjC.import("Metal"); var d = $.MTLCreateSystemDefaultDevice(), n = 0; if (d) for (var f = 1; f <= 30; f++) if (d.supportsFamily(1000 + f)) n = f; n' 2>/dev/null)
   case $f in ''|0|*[!0-9]*)
      # repli : la generation de l AGX (AGXAcceleratorG13X = M1...), les seules connues
      case $(ioreg -rc AGXAccelerator -d1 2>/dev/null | sed -n 's/.*"IOClass" = "AGXAcceleratorG\([0-9]*\).*/\1/p' | head -1) in
         13) f=7 ;; 14) f=8 ;; 15|16) f=9 ;; *) f= ;;
      esac ;;
   esac
   printf '%s\n' "$f"
}
fait() { # <nom> : la valeur, vide si le fait est inconnu
   force "$1" && return
   case $1 in
      puce) puce ;;
      generation) puce | sed -n 's/^Apple M\([0-9][0-9]*\).*/\1/p' ;;
      gamme)
         case $(puce) in
            "Apple M"[0-9]*" Ultra") echo ultra ;; "Apple M"[0-9]*" Max") echo max ;;
            "Apple M"[0-9]*" Pro") echo pro ;; "Apple M"[0-9]|"Apple M"[0-9][0-9]) echo base ;;
         esac ;;
      famille_gpu) famille_gpu ;;
      coeurs_gpu) ioreg -rc AGXAccelerator -d1 2>/dev/null | sed -n 's/.*"gpu-core-count" = \([0-9]*\).*/\1/p' | head -1 ;;
      memoire_go) echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) ;;
      ecran_largeur) ecran | cut -d' ' -f1 ;;
      ecran_hauteur) ecran | cut -d' ' -f2 ;;
      macos) sw_vers -productVersion 2>/dev/null | cut -d. -f1 ;;
      macos_version) sw_vers -productVersion 2>/dev/null ;;
   esac
}
TOUS="puce generation gamme famille_gpu coeurs_gpu memoire_go ecran_largeur ecran_hauteur macos macos_version"
NOMBRES="generation famille_gpu coeurs_gpu memoire_go ecran_largeur ecran_hauteur macos"
MOTS="gamme"
parmi() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

case ${1:-} in
   json)
      shift
      printf '{'; sep=
      for f in ${*:-$TOUS}; do
         v=$(fait "$f")
         case $v in ''|*[!0-9]*) v="\"$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')\"" ;; esac
         printf '%s"%s":%s' "$sep" "$f" "$v"; sep=,
      done
      echo '}' ;;
   si|syntaxe)
      # chaque terme `fait op valeur` ; le premier faux (ou mal forme) arrete
      mode=$1; reste=${2:-}
      [ -n "$reste" ] || exit 2
      while [ -n "$reste" ]; do
         case $reste in *" et "*) terme=${reste%%" et "*}; reste=${reste#*" et "} ;; *) terme=$reste; reste= ;; esac
         set -- $terme
         [ $# -eq 3 ] || exit 2
         case $2 in '<='|'>='|'<'|'>'|'=='|'!=') ;; *) exit 2 ;; esac
         if parmi "$1" "$NOMBRES"; then
            case $3 in ''|*[!0-9]*) exit 2 ;; esac
         elif parmi "$1" "$MOTS"; then
            case $2 in '=='|'!=') ;; *) exit 2 ;; esac
            case $3 in ''|*[!a-z]*) exit 2 ;; esac
         else
            exit 2
         fi
         [ "$mode" = si ] || continue
         v=$(fait "$1")
         if parmi "$1" "$MOTS"; then
            case $v in ''|*[!a-z]*) exit 1 ;; esac
            case $2 in '==') [ "$v" = "$3" ] ;; '!=') [ "$v" != "$3" ] ;; esac || exit 1
            continue
         fi
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
