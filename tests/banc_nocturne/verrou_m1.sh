#!/bin/sh
# verrou_m1.sh : verrou partage du M1 entre les sessions (manches en jeu, temoins hors jeu, banc nocturne).
#   sh verrou_m1.sh prendre <qui> <minutes> [objet]   0 = pris ; 1 = tenu par un autre (son contenu sur stderr)
#   sh verrou_m1.sh rendre <qui>                      ne rend que son propre verrou
#   sh verrou_m1.sh etat                              libre | tenu (contenu) | perime (contenu)
# Fichier : ${CIDRE_VERROU_M1:-~/Dev/cidre-coordination/m1.verrou}, lignes cle=valeur :
#   qui=<nom de session ou banc-nocturne>  pid=<CIDRE_VERROU_PID du detenteur, vide par defaut>
#   depuis=<epoch> jusqua=<epoch> objet=<texte libre>
# Creation atomique (noclobber : O_EXCL). Un verrou est PERIME, donc reprenable, si son pid est mort, ou s'il n'a
# pas de pid et que son echeance est passee. Un pid vivant garde le verrou meme apres l'echeance (signale).
# Une session sans processus durable (Claude) prend sans pid et rend a la fin ; l'echeance la protege d'un oubli.
set -u
F=${CIDRE_VERROU_M1:-$HOME/Dev/cidre-coordination/m1.verrou}
val() { sed -n "s/^$1=//p" "$F" 2>/dev/null | head -1; }
perime() { # 0 si le verrou existant est perime
   p=$(val pid); j=$(val jusqua)
   if [ -n "$p" ]; then ! kill -0 "$p" 2>/dev/null; return; fi
   [ -n "$j" ] && [ "$(date +%s)" -gt "$j" ]
}
ecrire() { # qui minutes objet pid
   maintenant=$(date +%s)
   ( set -C; printf 'qui=%s\npid=%s\ndepuis=%s\njusqua=%s\nobjet=%s\n# pris le %s\n' \
        "$1" "$4" "$maintenant" "$((maintenant + $2 * 60))" "$3" "$(date '+%Y-%m-%d %H:%M:%S')" > "$F" ) 2>/dev/null
}
case ${1:-} in
prendre)
   QUI=${2:?qui}; MIN=${3:?minutes}; OBJ=${4:-}; PID=${CIDRE_VERROU_PID:-}
   mkdir -p "$(dirname "$F")"
   ecrire "$QUI" "$MIN" "$OBJ" "$PID" && exit 0
   # reprise d'un verrou perime, sous un second verrou (mkdir est atomique) : on rejuge, on archive, on cree
   if perime && mkdir "$F.reprise" 2>/dev/null; then
      ok=1
      if [ ! -f "$F" ] || perime; then
         mv "$F" "$F.perime-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
         ecrire "$QUI" "$MIN" "$OBJ" "$PID" && ok=0
      fi
      rmdir "$F.reprise"
      [ $ok = 0 ] && { echo "verrou perime repris" >&2; exit 0; }
   fi
   echo "M1 tenu :" >&2; sed 's/^/   /' "$F" >&2; exit 1 ;;
rendre)
   QUI=${2:?qui}
   [ -f "$F" ] || exit 0
   [ "$(val qui)" = "$QUI" ] || { echo "verrou tenu par $(val qui), pas par $QUI : laisse" >&2; exit 1; }
   rm -f "$F" ;;
etat)
   if [ ! -f "$F" ]; then echo libre
   elif perime; then echo "perime :"; sed 's/^/   /' "$F"
   else
      echo "tenu :"; sed 's/^/   /' "$F"
      j=$(val jusqua); [ -n "$j" ] && [ "$(date +%s)" -gt "$j" ] && echo "   (echeance passee, pid $(val pid) vivant)"
   fi ;;
*) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
