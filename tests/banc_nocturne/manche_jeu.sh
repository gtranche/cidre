#!/bin/sh
# manche_jeu.sh <arbre> <A|B> <nom> <appid> <motif-exe> <secondes> <dossier-sortie>
# Une manche au menu, sur un arbre fantome (monter.sh), jamais sur l'installe : `cidre play` de l'arbre, attente du
# jeu, <secondes> au menu sans rien toucher (meme compte Steam que l'utilisateur : aucune sauvegarde nouvelle),
# releve des images/s (CIDRE_DXMT_STATS, CIDRE_WSI_STATS), `cidre stop` (jamais pkill), attente de la sortie du jeu
# et du wineserver. Refus si un jeu ou un wineserver tourne deja, ou si l'ecran est verrouille.
# Ecrit sur stdout UNE ligne TSV :
#   jeu nom arbre statut demarrage_s vivant arret plateau mediane releves exceptions err remarque
# statut : ok | pas-demarre | sorti (vu, puis parti seul avant la fin : vie en s dans la remarque) | mort | arret-impossible | invalide (ecran verrouille pendant la mesure) | refus
# Code : 0 manche faite (quel qu'en soit le verdict) ; 3 refus ; 4 le jeu ou wineserver ne s'arrete pas (la suite
# de la nuit doit s'arreter : jamais de pkill).
set -u
H=$(cd "$(dirname "$0")" && pwd)
. "$H/commun.sh"
S=${1:?arbre}; T=${2:?A ou B}; NOM=${3:?nom}; ID=${4:?appid}; EXE=${5:?motif exe}; D=${6:?secondes}; OUT=${7:?sortie}
case $S in */arbres/A|*/arbres/B) ;; *) echo "arbre attendu en .../arbres/A|B" >&2; exit 2 ;; esac
[ -f "$S/.banc-arbre" ] || { echo "arbre non monte : $S" >&2; exit 2; }
mkdir -p "$OUT"
TAG=$NOM-$T
ligne() { printf 'jeu\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NOM" "$T" "$@"; }
jeu() { for q in $(pgrep -f "$EXE"); do case $(ps -o comm= -p "$q" 2>/dev/null) in *sh|*zsh|*bash|*grep|*sleep|*sed|*pgrep|"") ;; *) echo "$q"; return ;; esac; done; }

r=$(deja_occupe)
if [ -n "$r" ] || [ -n "$(jeu)" ]; then ligne refus - - - - - - - - "${r:-$EXE tourne}"; exit 3; fi
if ecran_verrouille || hors_console; then ligne refus - - - - - - - - "ecran verrouille"; exit 3; fi

J=$S/build/logs/steam-$ID.log
DEBUT=$( { wc -l < "$J"; } 2>/dev/null || echo 0)
( cd "$S" && exec env CIDRE_HUD=0 CIDRE_DXMT_STATS=1 CIDRE_WSI_STATS=1 ./cidre play "$ID" ) > "$OUT/play-$TAG.txt" 2>&1 &
n=0; while [ -z "$(jeu)" ] && [ $n -lt 240 ]; do sleep 1; n=$((n + 1)); done
DEMARRE=$n; VU=; [ $n -lt 240 ] && VU=1
VERROU=; k=0
if [ -n "$(jeu)" ]; then
   while [ $k -lt "$D" ]; do sleep 5; k=$((k + 5)); ecran_verrouille && VERROU=1; [ -n "$(jeu)" ] || break; done
   VIVANT=$([ -n "$(jeu)" ] && echo oui || echo NON)
elif [ -n "$VU" ]; then
   VIVANT=NON   # vu au lancement, deja parti a la verification suivante
else
   DEMARRE=-; VIVANT=-
fi
( cd "$S" && ./cidre stop ) > "$OUT/stop-$TAG.txt" 2>&1
# sortie du jeu : 3 constats d'absence de suite ; puis le wineserver de l'arbre
r=0; k=0; while [ $r -lt 3 ] && [ $k -lt 60 ]; do sleep 3; k=$((k + 1)); if [ -z "$(jeu)" ]; then r=$((r + 1)); else r=0; fi; done
k=0; while pgrep -x wineserver >/dev/null && [ $k -lt 40 ]; do sleep 3; k=$((k + 1)); done
ARRET=oui; [ -z "$(jeu)" ] || ARRET=NON; pgrep -x wineserver >/dev/null && ARRET="NON (wineserver)"
tail -n +"$((DEBUT + 1))" "$J" > "$OUT/journal-$TAG.log" 2>/dev/null

releves "$OUT/journal-$TAG.log" > "$OUT/images-$TAG.txt"
NR=$(wc -l < "$OUT/images-$TAG.txt" | tr -d ' ')
PLATEAU=$(tail -15 "$OUT/images-$TAG.txt" | awk '{s+=$1; k++} END {if (k) printf "%.1f", s/k; else print "-"}')
MEDIANE=$(sed 1,15d "$OUT/images-$TAG.txt" | sort -n | awk '{v[NR]=$1} END {if (NR) printf "%.1f", (NR%2 ? v[(NR+1)/2] : (v[NR/2]+v[NR/2+1])/2); else print "-"}')
EXC=$(grep -a -i -c -E "unhandled|nested exception|page fault on" "$OUT/journal-$TAG.log" 2>/dev/null); EXC=${EXC:-0}
ERR=$(grep -a -c -E "^[0-9a-f]{4}:err:" "$OUT/journal-$TAG.log" 2>/dev/null); ERR=${ERR:-0}

REM=
if [ "$DEMARRE" = - ]; then STATUT=pas-demarre; REM="voir play-$TAG.txt"
elif [ "$VIVANT" != oui ] && [ $k -lt 30 ] && [ "$EXC" = 0 ]; then
   # parti seul en moins de 30 s sans exception au journal (Dead Cells A le 22/10 : « 6 s de jeu ») : relance par
   # le client, ou fermeture ; a distinguer d'une mort par plantage
   STATUT=sorti; REM="parti seul apres ~$k s, aucune exception ; voir journal-$TAG.log"
elif [ "$VIVANT" != oui ]; then STATUT=mort
else STATUT=ok; fi
[ -n "$VERROU" ] && { STATUT=invalide; REM="ecran verrouille pendant la mesure"; }
case $ARRET in oui) ;; *) STATUT=arret-impossible ;; esac
ligne "$STATUT" "$DEMARRE" "$VIVANT" "$ARRET" "$PLATEAU" "$MEDIANE" "$NR" "$EXC" "$ERR" "$REM"
[ "$ARRET" = oui ] || exit 4
exit 0
