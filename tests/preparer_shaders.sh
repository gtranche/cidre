#!/bin/sh
# Preparation des shaders avant le lancement d'un jeu D3D12/Vulkan sous
# KosmicKrisp : l'equivalent de « Traitement des shaders Vulkan » de Steam
# (rejeu Fossilize), avec un bouton Passer. Conception : PREPARATION_SHADERS.md.
#
# Pendant les parties, KosmicKrisp garde, dans le cache de pipelines du jeu
# (MESA_KK_PIPELINE_CACHE = <CIDRE_DIR>/vkd3d-cache/<id>) :
#   - base-pipelines/ (0444, option compilation_kk base_pipelines) : chaque
#     pipeline froid cree par le jeu, SPIR-V et etat, a la Fossilize ;
#   - liste-chaude-kk.bin (0441, option compilation_kk fond) : la cle de chaque
#     nuanceur effectivement LIE par le jeu.
# Avant le lancement, ce script recompile hors du processus du jeu, en
# parallele, les pipelines de la base que le jeu a LIES lors d'une partie
# precedente (liste chaude) et qui ne sont pas encore faits pour l'identite
# courante : cle de code de KosmicKrisp (KK_CODEGEN), famille de GPU (apple7 =
# M1, apple8 = M2 et suivants), build de macOS (son compilateur Metal). Le rejeu
# est celui de KosmicKrisp (0444/0472 : cache disque Mesa, reserve d'AIR,
# archive Metal), lance par build/prepa-shaders sur une base filtree.
# Jamais les pipelines crees mais jamais lies : 0492 (tous les froids compiles
# en fond pendant la partie) a ete nuisible sur Diablo IV (4 691 compiles pour 1
# servi, saccades x7) ; ici, rien pendant la partie, et seulement l'utile.
#
# Les cles faites pour une identite sont dans <cache>/rejoues-prep-<identite>.bin
# (journal que KosmicKrisp ecrit lot par lot, CIDRE_REJEU_JOURNAL) ; le lanceur y
# ajoute, a la sortie du jeu, les cles liees pendant la partie (`noter`) : le jeu
# les a compilees lui-meme sous cette identite.
#
# usage :
#   preparer_shaders.sh etat <id> [--json]      inactive | chaude | a_preparer (+ raison, a_faire, connus)
#   preparer_shaders.sh preparer <id> [--json]  prepare ce qui manque ; rien (et aucun evenement) si tout est chaud
#                       --json : {"evenement":"preparation","etat":"debut"|"en_cours","fait","total"} puis
#                       {"evenement":"preparation","etat":"finie"|"passee"|"echouee","fait","total","echecs","duree"}
#   preparer_shaders.sh passer <id>             la preparation en cours s'arrete, le jeu part (le reste se compile en jeu)
#   preparer_shaders.sh debut <id>              (lanceur, au lancement) la taille de la liste chaude
#   preparer_shaders.sh noter <id> <debut>      (lanceur, a la sortie) pipelines lies pendant la partie -> faits
# Options : preparation_shaders = false (fiche, profils.toml) ou CIDRE_PREPARATION_SHADERS=0 la coupent
# (=1 l'impose) ; CIDRE_PREPARATION_FILS (fils de compilation, defaut : tous les coeurs).
# Essais : CIDRE_DIR, CIDRE_KK_DYLIB (le pilote), CIDRE_PRECOMPIL_FAMILLE, CIDRE_PREPARATION_MACOS (build),
# CIDRE_PREPARATION_OUTIL (build/prepa-shaders). Teste par tests/tester_preparation_shaders.sh.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
ACTION=${1:-}; ID=${2:-}; JSON=non
for a in "$@"; do [ "$a" = --json ] && JSON=oui; done
[ -n "$ACTION" ] && [ -n "$ID" ] || { sed -n '/^# usage/,/^# Essais/p' "$0" >&2; exit 2; }
case $ID in *[!A-Za-z0-9_-]*) echo "id invalide : $ID" >&2; exit 2 ;; esac

CACHE=${MESA_KK_PIPELINE_CACHE:-$CIDRE_DIR/vkd3d-cache/$ID}
case ${CIDRE_BASE_PIPELINES:-} in /*) BASE=$CIDRE_BASE_PIPELINES ;; *) BASE=$CACHE/base-pipelines ;; esac
case ${CIDRE_LISTE_CHAUDE:-} in /*) LISTE=$CIDRE_LISTE_CHAUDE ;; *) LISTE=$CACHE/liste-chaude-kk.bin ;; esac
PREP=$CACHE/preparation
OUTIL=${CIDRE_PREPARATION_OUTIL:-$R/build/prepa-shaders}

dire() { if [ "$JSON" = oui ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
evenement() { [ "$JSON" != oui ] || printf '{"evenement":"preparation",%s}\n' "$1"; }
taille() { stat -f %z "$1" 2>/dev/null || echo 0; }

active() {
   case ${CIDRE_PREPARATION_SHADERS:-} in 0) return 1 ;; 1) return 0 ;; esac
   p=$(sh "$R/tests/profil_cidre.sh" "$ID" 2>/dev/null || true)
   [ "$(printf '%s\n' "$p" | sed -n 's/^preparation_shaders=//p' | head -1)" != false ] || return 1
   [ "$(printf '%s\n' "$p" | sed -n 's/^cache_pipelines=//p' | head -1)" != false ] || return 1
   case ${CIDRE_PIPELINE_CACHE:-} in 0) return 1 ;; esac
   return 0
}

# Le pilote que le jeu chargera : celui de l'ICD que pose etape2_pile_arm64ec.sh.
dylib() {
   [ -n "${CIDRE_KK_DYLIB:-}" ] && { echo "$CIDRE_KK_DYLIB"; return; }
   icd="$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
   d=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$icd" 2>/dev/null | head -1)
   echo "${d:-$R/prefix/lib/libvulkan_kosmickrisp.dylib}"
}

# L'outil natif : livre dans build/ par tests/empaqueter_runtime.sh ; dans un
# arbre de developpement, construit a la demande (quelques dixiemes de seconde).
outil() {
   s="$R/tests/prepa_shaders.c"
   if [ -x "$OUTIL" ] && { [ ! -f "$s" ] || [ ! "$s" -nt "$OUTIL" ]; }; then return 0; fi
   [ -f "$s" ] && command -v cc >/dev/null 2>&1 || { [ -x "$OUTIL" ]; return; }
   mkdir -p "$(dirname "$OUTIL")"
   cc -arch arm64 -mmacosx-version-min=13.0 -O1 -I"$R/prefix/include" -o "$OUTIL.neuf" "$s" 2>/dev/null &&
      mv "$OUTIL.neuf" "$OUTIL"
   [ -x "$OUTIL" ]
}

# L'identite des pipelines compiles : cle de code KK, famille de GPU, build de
# macOS. Gardee dans <prep>/identite tant que le pilote, la machine et macOS ne
# changent pas (lire la cle dans la dylib coute ~50 ms). Rend aussi REJEU=oui si
# le pilote sait rejouer une base dans un journal nomme (0444 + 0472).
identite() {
   DYLIB=$(dylib)
   [ -f "$DYLIB" ] || return 1
   B=${CIDRE_PREPARATION_MACOS:-$(sw_vers -buildVersion 2>/dev/null || echo inconnu)}
   empreinte="$DYLIB $(stat -f '%z %m' "$DYLIB") $(sysctl -n hw.model 2>/dev/null) $B ${CIDRE_PRECOMPIL_FAMILLE:-}"
   if [ "$(sed -n 1p "$PREP/identite" 2>/dev/null)" = "$empreinte" ]; then
      IDENT=$(sed -n 2p "$PREP/identite"); REJEU=$(sed -n 3p "$PREP/identite")
   else
      K=$(CIDRE_KK_DYLIB=$DYLIB sh "$R/tests/precompil_kk.sh" kk 2>/dev/null)
      F=$(sh "$R/tests/precompil_kk.sh" famille 2>/dev/null)
      case $K in ''|inconnu|*[!A-Za-z0-9.-]*) return 1 ;; esac
      IDENT="$K-${F:-inconnu}-$B"
      if LC_ALL=C grep -q 'CIDRE_REJEU_JOURNAL' "$DYLIB" 2>/dev/null; then REJEU=oui; else REJEU=non; fi
      mkdir -p "$PREP" && printf '%s\n%s\n%s\n' "$empreinte" "$IDENT" "$REJEU" >"$PREP/identite.$$" &&
         mv "$PREP/identite.$$" "$PREP/identite"
   fi
   JOURNAL_NOM="rejoues-prep-$IDENT.bin"; JOURNAL="$CACHE/$JOURNAL_NOM"
   ECHECS="$PREP/echecs-$IDENT.bin"
}

# Ce qui est a faire. ETAT = inactive (RAISON) | chaude | a_preparer ; A_FAIRE, CONNUS.
evaluer() {
   ETAT=inactive; RAISON=; A_FAIRE=0; CONNUS=0
   # (d'abord les fichiers : un jeu sans base ne coute que deux stat)
   [ -f "$BASE/pipelines.bin" ] && [ -f "$BASE/nuanceurs.bin" ] && [ -f "$BASE/fonctions.bin" ] &&
      [ -f "$BASE/env.txt" ] || { RAISON=sans_base; return; }
   [ -s "$LISTE" ] || { RAISON=sans_liste; return; }
   active || { RAISON=option; return; }
   identite || { RAISON=pilote; return; }
   [ "$REJEU" = oui ] || { RAISON=pilote; return; }
   if [ -f "$CIDRE_DIR/en-cours/$ID" ] && kill -0 "$(cat "$CIDRE_DIR/en-cours/$ID" 2>/dev/null)" 2>/dev/null; then
      RAISON=en_cours; return
   fi
   # Cache disque des nuanceurs vide (0430) : ce qui a ete fait est perdu.
   if [ -f "$JOURNAL" ] && grep -q '^CIDRE_CACHE_DISQUE=[^0]' "$BASE/env.txt" 2>/dev/null && [ ! -d "$CACHE/mesa" ]; then
      mv "$JOURNAL" "$JOURNAL.perime" 2>/dev/null; rm -f "$PREP/chaud" "$ECHECS"
   fi
   # Premiere rencontre (une fois par jeu) : si ses shaders sont deja en cache
   # (etat_shaders.sh : meme macOS, meme Mac, meme Cidre qu'a la derniere partie,
   # assez de jeu), la liste chaude actuelle a ete compilee sous cette identite :
   # on l'adopte au lieu de tout recompiler. Sinon (jamais joue ainsi, macOS ou
   # Cidre changes), tout ce qui a ete lie est a preparer.
   if [ ! -f "$PREP/adoption" ]; then
      e=$(sh "$R/tests/etat_shaders.sh" etat "$ID" 2>/dev/null | sed -n 's/^etat=//p')
      if [ "$e" = en_cache ] && outil && "$OUTIL" noter "$BASE/pipelines.bin" "$LISTE" 0 "$JOURNAL" >/dev/null 2>&1; then
         r=adoptee
      else
         r="non adoptee (${e:-inconnu})"
      fi
      mkdir -p "$PREP" && echo "$IDENT $r $(date +%s)" >"$PREP/adoption"
   fi
   # Cout nul si tout est chaud : rien n'a bouge depuis la derniere evaluation.
   tampon="$IDENT $(taille "$LISTE") $(taille "$BASE/pipelines.bin") $(taille "$JOURNAL") $(taille "$ECHECS")"
   if [ "$(cat "$PREP/chaud" 2>/dev/null)" = "$tampon" ]; then ETAT=chaude; return; fi
   outil || { RAISON=outil; return; }
   c=$("$OUTIL" compter "$BASE/pipelines.bin" "$LISTE" "$JOURNAL" "$ECHECS" 2>/dev/null) || { RAISON=illisible; return; }
   A_FAIRE=${c% *}; CONNUS=${c#* }
   if [ "$A_FAIRE" = 0 ]; then
      ETAT=chaude
      mkdir -p "$PREP" && printf '%s\n' "$tampon" >"$PREP/chaud"
   else
      ETAT=a_preparer
   fi
}

# Environnement du rejeu : celui de la derniere partie (<base>/env.txt, ecrit
# par KosmicKrisp : la cle du cache disque contient ses options), sans les
# dossiers ni ce qui ne vaut qu'en jeu ; les dossiers de ce lancement.
environnement() { # <fichier de sortie>
   grep -E '^(CIDRE|MESA)_[A-Za-z0-9_]*=' "$BASE/env.txt" |
      grep -v -E '^(MESA_KK_PIPELINE_CACHE|MESA_KK_AIR_LOCAL|MESA_KK_PRECOMPIL|MESA_KK_RECOLTE|MESA_SHADER_CACHE_DIR|CIDRE_BASE_PIPELINES|CIDRE_LISTE_CHAUDE|CIDRE_COMPILE_FOND|CIDRE_FOND_[A-Z_]*|CIDRE_REJEU[A-Z_]*|CIDRE_BANC_[A-Z_]*|CIDRE_COMPILE_DIFFEREE)=' >"$1"
}

preparer() {
   evaluer
   [ "$ETAT" = a_preparer ] || return 0
   mkdir -p "$PREP"
   if ! mkdir "$PREP/verrou" 2>/dev/null; then
      # une autre preparation de ce jeu tourne (ou un reste : son processus est mort)
      if kill -0 "$(cat "$PREP/verrou/pid" 2>/dev/null)" 2>/dev/null; then dire "preparation des shaders de $ID : deja en cours"; return 0; fi
      rm -rf "$PREP/verrou"; mkdir "$PREP/verrou" 2>/dev/null || return 0
   fi
   echo $$ >"$PREP/verrou/pid"
   rm -f "$PREP/passer"
   W="$PREP/travail.$$"
   PID=
   nettoyer() { [ -z "$PID" ] || kill "$PID" 2>/dev/null; rm -rf "$W" "$PREP/verrou"; }
   trap 'nettoyer' EXIT
   INTERROMPU=
   trap 'INTERROMPU=passer' INT
   trap 'INTERROMPU=fin' TERM HUP
   rm -rf "$W"; mkdir -p "$W"
   N=$("$OUTIL" filtrer "$BASE/pipelines.bin" "$LISTE" "$W/pipelines.bin" "$JOURNAL" "$ECHECS" 2>/dev/null) || N=0
   [ "$N" -gt 0 ] 2>/dev/null && [ -z "$INTERROMPU" ] || return 0
   ln -s "$BASE/nuanceurs.bin" "$W/nuanceurs.bin"; ln -s "$BASE/fonctions.bin" "$W/fonctions.bin"
   environnement "$W/env"
   AIR=$(CIDRE_DIR=$CIDRE_DIR sh "$R/tests/precompil_kk.sh" air_local "$ID" 2>/dev/null || true)
   PRECOMPIL=$(CIDRE_DIR=$CIDRE_DIR sh "$R/tests/precompil_kk.sh" dossier "$ID" 2>/dev/null || true)
   FILS=${CIDRE_PREPARATION_FILS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}
   case $FILS in ''|*[!0-9]*|0) FILS=8 ;; esac; [ "$FILS" -le 64 ] || FILS=64
   # Lots : l'avancement se lit dans le journal, ecrit apres l'archive de chaque
   # lot ; une dizaine de lots (et d'archives), entre 50 et 1 000 pipelines.
   LOT=$(( (N + 9) / 10 )); [ $LOT -ge 50 ] || LOT=50; [ $LOT -le 1000 ] || LOT=1000
   J0=$(taille "$JOURNAL"); T0=$(date +%s)
   JRN="$PREP/journal.txt"
   { echo "== $(date '+%F %T') preparation de $ID : $N pipelines, identite $IDENT, $FILS fils, lots de $LOT"
     echo "   pilote $DYLIB ; base $BASE ; liste $LISTE"; } >>"$JRN"
   dire "Preparation des shaders : $N pipelines a compiler pour ce Mac ($( [ "$JSON" = oui ] && echo "Passer : cidre preparation $ID passer" || echo "Ctrl-C : passer, le reste se compilera en jeu"))"
   evenement "\"etat\":\"debut\",\"fait\":0,\"total\":$N"
   (
      for v in $(env | sed -n -E 's/^((CIDRE|MESA)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
      while IFS= read -r l; do export "$l"; done <"$W/env"
      export CIDRE_REJEU="$W" CIDRE_REJEU_JOURNAL="$JOURNAL_NOM" CIDRE_REJEU_LOT="$LOT" \
             CIDRE_COMPILE_DIFFEREE="$FILS" CIDRE_REJEU_QOS_HAUTE=1 MESA_KK_COMPILE_STATS=1 \
             MESA_KK_PIPELINE_CACHE="$CACHE"
      [ -z "$AIR" ] || export MESA_KK_AIR_LOCAL="$AIR"
      [ -z "$PRECOMPIL" ] || export MESA_KK_PRECOMPIL="$PRECOMPIL"
      export DYLD_FALLBACK_LIBRARY_PATH="$R/wine/vklib-arm64:$R/libs:$R/prefix/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
      exec "$OUTIL" rejouer "$DYLIB"
   ) >>"$JRN" 2>&1 </dev/null &
   PID=$!
   PARENT=$PPID; FAIT=0; DIT=0
   while kill -0 "$PID" 2>/dev/null; do
      [ -z "$INTERROMPU" ] || break
      [ ! -f "$PREP/passer" ] || { INTERROMPU=passer; break; }
      # `cidre play` arrete (Verger a annule) : rien ne doit lui survivre
      kill -0 "$PARENT" 2>/dev/null || { INTERROMPU=fin; break; }
      f=$(( ($(taille "$JOURNAL") - J0) / 32 ))
      if [ "$f" != "$FAIT" ]; then
         FAIT=$f; [ $FAIT -le $N ] || FAIT=$N
         evenement "\"etat\":\"en_cours\",\"fait\":$FAIT,\"total\":$N"
         if [ "$JSON" != oui ] && [ $(( FAIT * 10 / N )) -gt $DIT ]; then DIT=$(( FAIT * 10 / N )); echo "  $FAIT / $N"; fi
      fi
      sleep 0.5
   done
   if [ -n "$INTERROMPU" ]; then
      kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=
   else
      wait "$PID"; RC=$?; PID=
   fi
   FAIT=$(( ($(taille "$JOURNAL") - J0) / 32 )); [ $FAIT -le $N ] || FAIT=$N
   D=$(( $(date +%s) - T0 ))
   fin=$(grep 'kk: rejeu fini' "$JRN" 2>/dev/null | tail -1)
   if [ -n "$INTERROMPU" ]; then
      echo "   interrompue ($INTERROMPU) apres $D s : $FAIT / $N" >>"$JRN"
      dire "Preparation des shaders passee : $FAIT / $N faits, le reste se compilera en jeu"
      evenement "\"etat\":\"passee\",\"fait\":$FAIT,\"total\":$N,\"echecs\":0,\"duree\":$D"
      [ "$INTERROMPU" = passer ] || exit 1
      return 0
   fi
   if [ "${RC:-1}" != 0 ] || [ -z "$fin" ]; then
      echo "   echec (code ${RC:-?}) apres $D s : $FAIT / $N" >>"$JRN"
      dire "Preparation des shaders : echec (journal : $JRN), le jeu compilera lui-meme"
      evenement "\"etat\":\"echouee\",\"fait\":$FAIT,\"total\":$N,\"echecs\":0,\"duree\":$D"
      return 0
   fi
   # Rejeu complet : ce qui n'est pas au journal a echoue (ou est illisible :
   # base d'un autre Mesa). Note, pour ne pas le retenter a chaque lancement.
   "$OUTIL" cles "$W/pipelines.bin" >"$W/cles" 2>/dev/null &&
      E=$("$OUTIL" ajouter "$W/cles" 0 "$ECHECS" "$JOURNAL" 2>/dev/null) || E=0
   echo "   finie en $D s : $FAIT / $N, $E en echec ; $fin" >>"$JRN"
   dire "Preparation des shaders finie en $D s ($FAIT / $N${E:+, $E en echec})"
   evenement "\"etat\":\"finie\",\"fait\":$FAIT,\"total\":$N,\"echecs\":${E:-0},\"duree\":$D"
   rm -f "$PREP/chaud"
}

case $ACTION in
   etat)
      evaluer
      if [ "$JSON" = oui ]; then
         r=null; [ -z "$RAISON" ] || r="\"$RAISON\""
         printf '{"etat":"%s","raison":%s,"a_faire":%s,"connus":%s,"identite":%s}\n' "$ETAT" "$r" "$A_FAIRE" "$CONNUS" \
            "$( [ -n "${IDENT:-}" ] && printf '"%s"' "$IDENT" || echo null)"
      else
         echo "etat=$ETAT"; echo "raison=$RAISON"; echo "a_faire=$A_FAIRE"; echo "connus=$CONNUS"; echo "identite=${IDENT:-}"
      fi ;;
   preparer) preparer ;;
   passer)
      [ -d "$PREP/verrou" ] || exit 0
      : >"$PREP/passer" ;;
   debut)
      taille "$LISTE" ;;
   noter)
      DEB=${3:-}
      case $DEB in ''|*[!0-9]*) exit 2 ;; esac
      active || exit 0
      [ -s "$LISTE" ] && [ "$(taille "$LISTE")" -gt "$DEB" ] || exit 0
      identite && [ "$REJEU" = oui ] && outil || exit 0
      [ -f "$BASE/pipelines.bin" ] || exit 0
      n=$("$OUTIL" noter "$BASE/pipelines.bin" "$LISTE" "$DEB" "$JOURNAL" 2>/dev/null) || exit 0
      echo "preparation des shaders : $n pipelines lies pendant la partie, notes faits ($IDENT)" ;;
   *) sed -n '/^# usage/,/^# Essais/p' "$0" >&2; exit 2 ;;
esac
