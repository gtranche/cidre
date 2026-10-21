#!/bin/sh
# nuit.sh [--sec] [--sans-jeux] [--sans-temoins] [--jeux nom,nom] : banc de non-regression A/B du M1, sans intervention.
#   A = runtime installe (~/Dev/proton-ouvert, la derniere release posee) ; B = A + la livraison candidate dont le
#   liste.tsv est nomme dans $BANC/candidat (une ligne : chemin du liste.tsv ; absent = contre-epreuve A/A).
#   Temoins hors jeu (temoins.tsv) puis jeux au menu (jeux.tsv), chacun en A puis en B, sur des arbres fantomes
#   (monter.sh) ; rapport dans $BANC/nuits/<date>/rapport.md, une ligne dans $BANC/synthese.txt (la derniere = la
#   nuit passee) et $BANC/derniere.txt.
#   --sec : monte les arbres, construit les temoins et dit ce qu'il ferait ; ni Wine, ni jeu.
# Refuse (et le dit dans la synthese) si un jeu, un wineserver ou Wine tourne, si l'ecran est verrouille ou la
# session hors console, ou si le verrou du M1 (verrou_m1.sh) est tenu. Garde l'ecran allume (caffeinate) et rend le
# verrou en sortant. Ne touche jamais l'installe ; jamais de pkill sur un jeu (cidre stop).
# Le script se copie d'abord dans le dossier de la nuit et s'execute de la copie : une edition du depot pendant la
# nuit ne le touche pas.
set -u
H=$(cd "$(dirname "$0")" && pwd)
. "$H/commun.sh"
if [ -z "${CIDRE_BANC_NUIT:-}" ]; then
   NUIT=$BANC/nuits/$(date +%Y-%m-%d_%H%M)
   [ -e "$NUIT" ] && NUIT=$NUIT-$$
   mkdir -p "$NUIT/banc"
   cp -p "$H"/*.sh "$H"/*.tsv "$H"/*.py "$NUIT/banc/"
   CIDRE_BANC_NUIT=$NUIT exec sh "$NUIT/banc/nuit.sh" "$@"
fi
NUIT=$CIDRE_BANC_NUIT
SEC=; SANS_JEUX=; SANS_TEMOINS=; FILTRE=
while [ $# -gt 0 ]; do
   case $1 in
      --sec) SEC=1 ;; --sans-jeux) SANS_JEUX=1 ;; --sans-temoins) SANS_TEMOINS=1 ;;
      --jeux) FILTRE=",${2:?noms},"; shift ;;
      *) echo "option inconnue : $1" >&2; exit 2 ;;
   esac
   shift
done
exec >> "$NUIT/nuit.log" 2>&1
echo "### banc nocturne $(date '+%Y-%m-%d %H:%M:%S') pid $$${SEC:+ (a sec)}"
RES=$NUIT/resultats.tsv; : > "$RES"
[ -n "$SEC" ] && : > "$NUIT/a-sec"
QUI=banc-nocturne
CAF=

finir() {
   [ -n "$CAF" ] && kill "$CAF" 2>/dev/null
   sh "$H/verrou_m1.sh" rendre "$QUI" 2>/dev/null
   for T in A B; do [ -f "$BANC/arbres/$T/.banc-arbre" ] && cp -p "$BANC/arbres/$T/.banc-arbre" "$NUIT/$T.banc-arbre"; done
   python3 -I "$H/rapport.py" "$NUIT" "$H/jeux.tsv" > /dev/null
   if [ -z "$SEC" ]; then   # une nuit a sec ne remplace pas la derniere vraie
      cat "$NUIT/synthese.txt" >> "$BANC/synthese.txt"
      cp "$NUIT/synthese.txt" "$BANC/derniere.txt"
      ln -sfn "$NUIT" "$BANC/derniere"
   fi
   echo "### fin $(date '+%H:%M:%S') : $(cat "$NUIT/synthese.txt")"
}
refuser() { trap - EXIT; echo "$*" > "$NUIT/refus.txt"; echo "REFUS : $*"; finir; exit 0; }
garde() { if [ -n "$SEC" ]; then echo "(a sec) garde : $*"; else refuser "$*"; fi; }

# 1. gardes
r=$(deja_occupe); [ -z "$r" ] || garde "$r"
if ecran_verrouille; then garde "ecran verrouille : une mesure ecran verrouille ne vaut rien"; fi
if hors_console; then garde "session hors console"; fi
if [ -n "$SEC" ]; then
   echo "(a sec) verrou du M1 : $(sh "$H/verrou_m1.sh" etat | tr '\n' ' ')"
else
   v=$(CIDRE_VERROU_PID=$$ sh "$H/verrou_m1.sh" prendre "$QUI" 150 "banc nocturne $NUIT" 2>&1) ||
      refuser "verrou du M1 tenu : $(echo "$v" | tr '\n' ' ' | tr -s ' ')"
   trap 'finir' EXIT
   trap 'echo "interrompu"; exit 1' INT TERM HUP
   # ecran allume, pas de veille, pas d'economiseur : sans quoi la session se verrouille pendant la mesure
   caffeinate -dimsu -w $$ & CAF=$!
fi

# 2. arbres
CAND=
[ -f "$BANC/candidat" ] && CAND=$(sed -n '1{s/[[:space:]]*$//;p;}' "$BANC/candidat")
[ -z "$CAND" ] || [ -f "$CAND" ] || refuser "liste candidate introuvable : $CAND"
sh "$H/monter.sh" "$BANC/arbres/A" || refuser "arbre A non monte"
sh "$H/monter.sh" "$BANC/arbres/B" $CAND || refuser "arbre B non monte (liste $CAND)"
echo "A : $(tr '\n' ' ' < "$BANC/arbres/A/.banc-arbre")"
echo "B : $(tr '\n' ' ' < "$BANC/arbres/B/.banc-arbre")"

# 3. temoins hors jeu
if [ -z "$SANS_TEMOINS" ]; then
   n=$(sh "$H/temoins.sh" construire "$NUIT/exe")
   echo "temoins construits : $n"
   for T in A B; do
      if [ -n "$SEC" ]; then echo "(a sec) temoins.sh passer $BANC/arbres/$T $T"; continue; fi
      ecran_verrouille && refuser "ecran verrouille avant les temoins $T"
      sh "$H/temoins.sh" passer "$BANC/arbres/$T" "$T" "$NUIT/exe" "$NUIT" >> "$RES"
      [ $? = 3 ] && refuser "M1 occupe avant les temoins $T : $(tail -1 "$RES" | cut -f6)"
   done
fi

# 4. jeux au menu, A puis B pour chacun
if [ -z "$SANS_JEUX" ]; then
   grep -v '^#' "$H/jeux.tsv" | while IFS="$TAB" read -r nom id exe sec seuil requis; do
      [ -n "$nom" ] || continue
      case $FILTRE in ''|*",$nom,"*) ;; *) continue ;; esac
      if [ "$requis" != - ] && [ ! -d "$requis" ]; then
         for T in A B; do printf 'jeu\t%s\t%s\tabsent\t-\t-\t-\t-\t-\t-\t-\t-\t%s non monte\n' "$nom" "$T" "$requis" >> "$RES"; done
         continue
      fi
      for T in A B; do
         if [ -n "$SEC" ]; then echo "(a sec) manche_jeu.sh $BANC/arbres/$T $T $nom $id $exe $sec"; continue; fi
         sh "$H/manche_jeu.sh" "$BANC/arbres/$T" "$T" "$nom" "$id" "$exe" "$sec" "$NUIT" >> "$RES"
         rc=$?
         echo "$(date +%T) $(tail -1 "$RES" | tr '\t' ' ')"
         # 4 : le jeu ou wineserver ne s'arrete pas ; 3 : quelqu'un d'autre a pris le M1 -> on s'arrete la
         [ $rc = 4 ] && { echo "arret impossible : fin de la serie" > "$NUIT/arret-serie"; exit 0; }
         [ $rc = 3 ] && { echo "M1 occupe en cours de nuit : fin de la serie" > "$NUIT/arret-serie"; exit 0; }
      done
   done
   [ -f "$NUIT/arret-serie" ] && cat "$NUIT/arret-serie"
fi
[ -n "$SEC" ] && { echo "a sec : rien n'a ete lance"; finir; }
exit 0
