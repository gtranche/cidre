#!/bin/sh
# Deplace un jeu Cidre d'un emplacement a un autre : c'est `cidre move`, qui
# l'appelle apres avoir verifie le jeu et resolu les emplacements (cidre :
# en-tete « Emplacements »). Jamais de perte : l'original n'est supprime
# qu'une fois la copie entiere et verifiee.
#   1. refus si le jeu tourne (temoin de `cidre play`, ou un processus qui a
#      son dossier dans sa ligne de commande, chemin Unix ou Windows Z:\...),
#      si un autre deplacement du meme jeu tourne, ou si la place manque sur la
#      cible (arrondie a la taille de bloc du volume : un petit fichier occupe
#      un bloc entier, 128 Kio sur un gros disque exFAT) ;
#   2. copie dans un dossier cache de la cible (.cidre-deplacement-<appid>,
#      ignore par `cidre`), par rsync : une copie interrompue (Ctrl-C, disque
#      debranche, Mac eteint) reprend la ou elle en etait au `cidre move`
#      suivant ; avancement d'apres la place prise sur la cible ;
#   3. verification : memes fichiers, memes tailles, memes liens (et, avec
#      --verifier-contenu, memes octets) ;
#   4. bascule : le dossier cache prend le nom du jeu (renommage, instantane),
#      puis l'original est renomme en dossier cache et efface.
# Meme volume (deux emplacements sur un meme disque) : un simple renommage.
# Rien d'autre ne bouge : sauvegardes (prefixe, dossiers macOS, liens Steam
# Cloud), prefixe Wine, options et etat des mises a jour sont ranges par appid,
# pas par chemin. Un lien symbolique du jeu qui visait son propre dossier par
# un chemin absolu est refait vers le nouveau.
# exFAT : pas de droits Unix (rsync ne les impose pas), et macOS y range les
# attributs etendus dans des fichiers ._xxx, qu'on ne copie pas et qu'on
# retire apres coup (dot_clean -m) : un jeu qui chercherait *.pak y verrait
# sinon des ._xxx.pak illisibles.
#
# Usage (par `cidre move`) : deplacer_jeu.sh <appid> <dossier du jeu> <chemin de l'emplacement cible>
# Environnement : CIDRE_DIR, DEPL_DE et DEPL_VERS (ids des emplacements, pour
# l'etat), DEPL_NOM (nom du jeu), DEPL_VOLUME (nom de la cible pour le joueur),
# DEPL_JSON=oui (evenements JSON sur la sortie standard, un par ligne, le
# reste a l'erreur), DEPL_VERIFIER=oui (comparer aussi les octets).
# Etat : $CIDRE_DIR/deplacements/<appid> (cle=valeur : etat en_cours,
# interrompu ou echoue, phase, de, vers, source, cible, pid, raison, message) et
# <appid>.avancement (pourcentage, octets, total) ; effaces une fois le jeu
# deplace.
# Codes : 0 deplace ; 1 echec (rien de perdu) ; 4 jeu en cours d'usage, ou
# deja en cours de deplacement ; 5 place insuffisante ; 8 un des disques a ete
# debranche ; 130 interrompu.
#
# Tout le corps est entre accolades, ferme par `exit` : le shell le lit en
# entier avant d'executer quoi que ce soit (un deplacement dure ; une mise a
# jour du runtime pendant ce temps ne le reprend pas au milieu).
{
set -u
APPID=${1:-}; SRC=${2:-}; CIBLE=${3:-}
case $APPID in ''|*[!0-9]*) echo "usage: deplacer_jeu.sh <appid> <dossier du jeu> <emplacement cible>" >&2; exit 2 ;; esac
[ -n "$SRC" ] && [ -n "$CIBLE" ] || { echo "usage: deplacer_jeu.sh <appid> <dossier du jeu> <emplacement cible>" >&2; exit 2; }
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
D="$CIDRE_DIR/deplacements"
JSON=${DEPL_JSON:-non}; VERIFIER=${DEPL_VERIFIER:-non}
NOM=${DEPL_NOM:-$APPID}; VOL=${DEPL_VOLUME:-$CIBLE}
DE=${DEPL_DE:-}; VERS=${DEPL_VERS:-}
SRCLIB=$(dirname "$SRC")
DEST="$CIBLE/$APPID"
TMP="$CIBLE/.cidre-deplacement-$APPID"
ERR="$D/$APPID.erreurs"
PHASE=preparation; DEBUT=$(date +%s)

js() { printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\n\r' '   ')"; }
dire() { if [ "$JSON" = oui ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
evenement() { [ "$JSON" != oui ] || printf '%s\n' "$1"; }
etat() { # <etat> [raison] [message]
   mkdir -p "$D" &&
   printf 'etat=%s\nphase=%s\nde=%s\nvers=%s\nsource=%s\ncible=%s\npid=%s\nraison=%s\nmessage=%s\ndate=%s\n' \
      "$1" "$PHASE" "$DE" "$VERS" "$SRC" "$CIBLE" "$$" "${2:-}" "$(printf '%s' "${3:-}" | tr '\n' ' ')" "$(date +%s)" >"$D/$APPID.tmp.$$" &&
   mv "$D/$APPID.tmp.$$" "$D/$APPID"
}
phase() { PHASE=$1; etat en_cours; evenement "{\"evenement\":\"deplacement\",\"etat\":\"en_cours\",\"phase\":\"$1\"}"; }
# (la preparation n'ecrit pas d'etat : un refus a ce stade ne laisse rien, et
# l'etat d'un deplacement inacheve reste celui qu'il etait ; le verrou dit
# qu'un deplacement tourne)
# Un echec : l'etat le garde (Verger le montre, `cidre move` le reprend), le
# message va au joueur, en derniere ligne.
echouer() { # <code> <raison> <message>
   PHASE=${PHASE:-preparation}
   etat echoue "$2" "$3"
   rm -f "$D/$APPID.avancement"
   evenement "{\"evenement\":\"deplacement\",\"etat\":\"echoue\",\"raison\":\"$2\",\"message\":$(js "$3")}"
   echo "$3" >&2
   liberer; exit "$1"
}
# refus avant d'avoir rien commence : pas d'etat garde
refuser() { # <code> <raison> <message>
   evenement "{\"evenement\":\"deplacement\",\"etat\":\"refuse\",\"raison\":\"$2\",\"message\":$(js "$3")}"
   echo "$3" >&2
   liberer; exit "$1"
}
# Efface un dossier. Sur exFAT (macOS 26), un nom accentue que lit `rm -rf`
# (decompose, NFD) ne s'efface pas : le volume ne l'efface que sous sa forme
# composee (NFC). Une seconde passe, entree par entree, sous cette forme.
effacer() { # <dossier>
   rm -rf "${1:?}" 2>/dev/null
   [ -e "$1" ] || [ -L "$1" ] || return 0
   find "$1" -depth 2>/dev/null | /usr/bin/iconv -f UTF-8-MAC -t UTF-8 2>/dev/null | while IFS= read -r ef_f; do
      if [ -d "$ef_f" ] && [ ! -L "$ef_f" ]; then rmdir "$ef_f" 2>/dev/null; else rm -f "$ef_f" 2>/dev/null; fi
   done
   rm -rf "${1:?}" 2>/dev/null
   [ ! -e "$1" ]
}
go() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f Go", k / 1048576; else printf "%d Mo", k / 1024 }'; }

# --- un deplacement de ce jeu a la fois -------------------------------------
VERROU="$D/$APPID.verrou"
liberer() { rm -rf "${VERROU:?}" 2>/dev/null; }
mkdir -p "$D" || exit 1
if ! mkdir "$VERROU" 2>/dev/null; then
   v=$(cat "$VERROU/pid" 2>/dev/null)
   if [ -n "$v" ] && kill -0 "$v" 2>/dev/null; then
      evenement "{\"evenement\":\"deplacement\",\"etat\":\"refuse\",\"raison\":\"en_cours\",\"message\":$(js "Ce jeu est deja en cours de deplacement (processus $v).")}"
      echo "Ce jeu est deja en cours de deplacement (processus $v)." >&2; exit 4
   fi
   rm -rf "${VERROU:?}"; mkdir "$VERROU" || exit 1
fi
echo $$ >"$VERROU/pid"

# --- le jeu tourne-t-il ? ---------------------------------------------------
[ -d "$SRC" ] || refuser 8 debranche "Le dossier du jeu est introuvable : $SRC"
[ -d "$CIBLE" ] || refuser 8 debranche "L'emplacement cible est introuvable : $CIBLE"
t="$CIDRE_DIR/en-cours/$APPID"
if [ -f "$t" ] && kill -0 "$(cat "$t" 2>/dev/null)" 2>/dev/null; then
   refuser 4 en_jeu "$NOM est en cours de partie : quitte-le, puis deplace-le."
fi
# La liste des processus est prise d'abord, seule : un grep qui tournerait en
# meme temps porterait le chemin du jeu dans sa propre ligne de commande.
ps_l=$(ps -axww -o pid=,command= 2>/dev/null)
z=$(printf 'Z:%s' "$SRC" | tr / '\\')
if printf '%s\n' "$ps_l" | grep -v 'deplacer_jeu\.sh' | grep -F -i -e "$SRC/" -e "$z\\" >/dev/null; then
   refuser 4 en_jeu "Un programme utilise encore le dossier de $NOM (le jeu, ou Wine) : quitte-le (\`cidre stop\` au besoin), puis recommence."
fi

# --- les restes d'une suppression interrompue ---------------------------------
for r in "$SRCLIB"/.cidre-supprime-"$APPID".* "$CIBLE"/.cidre-supprime-"$APPID".*; do
   [ -d "$r" ] || continue
   p=${r##*.}; case $p in ''|*[!0-9]*) ;; *) kill -0 "$p" 2>/dev/null && continue ;; esac
   effacer "$r"
done

# Le systeme de fichiers d'un dossier (apfs, exfat, msdos, hfs, smbfs...).
fs_de() {
   fd_m=$(df -P "$1" 2>/dev/null | awk 'NR == 2 { for (i = 1; i <= 5; i++) $i = ""; sub(/^ +/, ""); print }')
   mount | M=" on $fd_m (" awk 'index($0, ENVIRON["M"]) { s = substr($0, index($0, ENVIRON["M"]) + length(ENVIRON["M"])); sub(/[,)].*/, "", s); print s; exit }'
}
FS=$(fs_de "$CIBLE")
# Retire les ._xxx (attributs etendus que macOS range a cote de chaque fichier
# sur exFAT). dot_clean -m n'y arrive pas pour un nom accentue : find le rend
# decompose (NFD), et le volume ne retrouve le ._xxx que sous sa forme
# composee ; on essaie les deux.
sans_point_souligne() { # <dossier>
   find "$1" -name '._*' -type f 2>/dev/null | while IFS= read -r ps_f; do
      rm -f "$ps_f" 2>/dev/null
      [ -e "$ps_f" ] && rm -f "$(printf '%s' "$ps_f" | /usr/bin/iconv -f UTF-8-MAC -t UTF-8 2>/dev/null)" 2>/dev/null
   done
}
# La liste de ce que contient un dossier, pour comparer : fichiers (taille),
# liens (cible), dossiers ; sans les ._xxx d'exFAT. Les noms en forme composee
# (NFC) : exFAT rend « É » decompose (E + accent), APFS tel qu'il a ete ecrit.
lister() {
   (cd "$1" && find . ! -name '._*' \( -type f -exec stat -f 'f %z %N' {} + -o -type l -exec stat -f 'l %Y %N' {} + -o -type d -exec stat -f 'd - %N' {} + \)) 2>/dev/null |
      /usr/bin/iconv -f UTF-8-MAC -t UTF-8 2>/dev/null | LC_ALL=C sort
}

# --- meme volume : un renommage ---------------------------------------------
if [ "$(stat -f %d "$SRC")" = "$(stat -f %d "$CIBLE")" ]; then
   [ -e "$DEST" ] && refuser 1 existe "$DEST existe deja : rien n'est deplace."
   PHASE=bascule; etat en_cours
   mv "$SRC" "$DEST" || echouer 1 copie "Le renommage de $SRC en $DEST a echoue."
   rm -f "$D/$APPID" "$D/$APPID.avancement" "$ERR"
   evenement "{\"evenement\":\"deplacement\",\"etat\":\"fait\",\"emplacement\":$(js "$VERS"),\"chemin\":$(js "$DEST"),\"octets\":null,\"duree\":0}"
   dire "deplace : $NOM -> $DEST (meme volume : renomme)"
   liberer; exit 0
fi

# --- un exemplaire est deja a destination -------------------------------------
# (copie faite a la main, ou deplacement arrete juste apres la bascule) : le
# meme que l'original, on finit le deplacement ; un autre, on n'y touche pas.
DEJA=non
if [ -e "$DEST" ]; then
   if [ "$(lister "$SRC")" = "$(lister "$DEST")" ]; then DEJA=oui
   else refuser 1 existe "Un autre exemplaire de $NOM est deja dans « $VOL » ($DEST), different de celui-ci : supprime-le ou renomme-le, puis recommence."; fi
fi

trap 'interrompre' INT TERM HUP
tuer_arbre() { for ta_c in $(pgrep -P "$1" 2>/dev/null); do tuer_arbre "$ta_c"; done; kill -TERM "$1" 2>/dev/null; }
interrompre() {
   trap - INT TERM HUP
   for c in $(pgrep -P $$ 2>/dev/null); do tuer_arbre "$c"; done
   etat interrompu interrompu "Deplacement interrompu : rien n'est perdu, l'original est intact. Relance-le pour le reprendre ou il en etait."
   rm -f "$D/$APPID.avancement"
   evenement "{\"evenement\":\"deplacement\",\"etat\":\"interrompu\",\"raison\":\"interrompu\",\"message\":$(js "Deplacement interrompu : l'original est intact.")}"
   liberer; exit 130
}

if [ $DEJA = non ]; then
   PHASE=preparation
   evenement '{"evenement":"deplacement","etat":"en_cours","phase":"preparation"}'
   # --- la place -----------------------------------------------------------
   # Un fichier occupe des blocs entiers ; sur exFAT, chaque fichier a en plus
   # un temps son ._xxx (un bloc) et chaque dossier un bloc.
   bloc=$(diskutil info -plist "$CIBLE" 2>/dev/null | plutil -extract VolumeAllocationBlockSize raw - 2>/dev/null)
   case $bloc in ''|*[!0-9]*) bloc=4096 ;; esac
   [ "$bloc" -ge 512 ] || bloc=4096
   en_plus=0; case $FS in exfat|msdos|smbfs) en_plus=1 ;; esac
   set -- $( (cd "$SRC" && { find . -type f ! -name '._*' -exec stat -f 'f %z' {} +; find . -type d -exec stat -f 'd 0' {} +; }) 2>/dev/null |
      awk -v b="$bloc" -v e="$en_plus" '
         $1 == "f" { n++; o += $2; k += int(($2 + b - 1) / b) * b + e * b }
         $1 == "d" { k += b }
         END { printf "%d %.0f %.0f\n", n, o, k / 1024 }')
   NB=${1:-0}; TOTAL=${2:-0}; BESOIN=${3:-0}
   DEJA_KO=0; [ -d "$TMP" ] && DEJA_KO=$(du -sk "$TMP" 2>/dev/null | cut -f1)
   LIBRE0=$(df -Pk "$CIBLE" 2>/dev/null | awk 'NR == 2 { print $4 }')
   MARGE=${CIDRE_DEPL_MARGE_KO:-262144}
   RESTE=$((BESOIN - DEJA_KO)); [ $RESTE -gt 0 ] || RESTE=0
   if [ $((RESTE + MARGE)) -gt "${LIBRE0:-0}" ]; then
      m="Place insuffisante sur « $VOL » : il faut $(go $((RESTE + MARGE))) pour $NOM, il y en a $(go "${LIBRE0:-0}") de libres."
      [ -d "$TMP" ] && echouer 5 place "$m Le debut de copie y reste, pour reprendre plus tard ; \`cidre move $APPID --annuler\` l'efface."
      refuser 5 place "$m"
   fi
   # --- les liens symboliques : la cible sait-elle en garder ? --------------
   nl=$(find "$SRC" -type l 2>/dev/null | head -1)
   if [ -n "$nl" ]; then
      mkdir -p "$TMP" 2>/dev/null
      if ! ln -s . "$TMP/.cidre-essai-lien.$$" 2>/dev/null; then
         rmdir "$TMP" 2>/dev/null
         refuser 1 liens "« $VOL » ($FS) ne sait pas garder les liens symboliques, et $NOM en a (${nl#"$SRC"/}) : choisis un emplacement APFS ou Mac OS etendu."
      fi
      rm -f "$TMP/.cidre-essai-lien.$$"
   fi

   # --- la copie -------------------------------------------------------------
   PHASE=copie; etat en_cours
   evenement "{\"evenement\":\"deplacement\",\"etat\":\"en_cours\",\"phase\":\"copie\",\"avancement\":0,\"octets\":0,\"total\":$TOTAL}"
   dire "copie de $NOM vers « $VOL » : $(go "$BESOIN")${DEJA_KO:+ (reprise : $(go "$DEJA_KO") deja copies)}"
   mkdir -p "$TMP" || echouer 1 copie "Impossible de creer $TMP."
   # L'avancement, d'apres la place prise sur la cible (une lecture de df :
   # rien a parcourir) ; le pourcentage ne touche 100 qu'a la fin.
   (
      n=0
      while sleep 1; do
         l=$(df -Pk "$CIBLE" 2>/dev/null | awk 'NR == 2 { print $4 }')
         [ -n "$l" ] || exit 0
         f=$((DEJA_KO + LIBRE0 - l)); [ $f -ge 0 ] || f=0
         [ "$BESOIN" -gt 0 ] && p=$(awk -v f="$f" -v b="$BESOIN" 'BEGIN { p = 100 * f / b; if (p > 99.9) p = 99.9; printf "%.1f", p }') || p=0
         o=$(awk -v p="$p" -v t="$TOTAL" 'BEGIN { printf "%.0f", p * t / 100 }')
         printf '%s %s %s\n' "$p" "$o" "$TOTAL" >"$D/$APPID.avancement.tmp" && mv "$D/$APPID.avancement.tmp" "$D/$APPID.avancement"
         evenement "{\"evenement\":\"deplacement\",\"etat\":\"en_cours\",\"phase\":\"copie\",\"avancement\":$p,\"octets\":$o,\"total\":$TOTAL}"
         n=$((n + 1)); [ "$JSON" = oui ] || [ $((n % 5)) -ne 0 ] || echo "  copie : $p %"
      done
   ) &
   SUIVI=$!
   # -rlpt : fichiers, liens tels quels, droits, dates (exFAT n'a pas de droits :
   # rsync passe outre) ; --modify-window : exFAT date a 10 ms pres, et la
   # reprise compare taille + date ; --delete : les restes d'une copie coupee
   # (fichiers temporaires de rsync) ; sans les ._xxx d'exFAT.
   rsync -rlptW --modify-window=1 --delete --exclude='._*' "$SRC/" "$TMP/" >/dev/null 2>"$ERR" &
   wait $!; rc=$?
   kill "$SUIVI" 2>/dev/null; wait "$SUIVI" 2>/dev/null
   if [ $rc -ne 0 ]; then
      [ -d "$CIBLE" ] || echouer 8 debranche "« $VOL » a ete debranche pendant la copie : l'original est intact. Rebranche-le et relance le deplacement : il reprendra ou il en etait."
      [ -d "$SRC" ] || echouer 8 debranche "Le disque de $NOM a ete debranche pendant la copie : rebranche-le et relance le deplacement, il reprendra ou il en etait."
      if grep -qi 'no space left\|disk full' "$ERR" 2>/dev/null; then
         echouer 5 place "Place insuffisante sur « $VOL » : la copie s'est arretee. Libere de la place et relance le deplacement (il reprendra), ou \`cidre move $APPID --annuler\`."
      fi
      e=$(grep -v '^$' "$ERR" 2>/dev/null | tail -1)
      echouer 1 copie "La copie a echoue${e:+ ($e)} : l'original est intact. Relance le deplacement pour la reprendre."
   fi

   # --- la verification ------------------------------------------------------
   phase verification
   a=$(lister "$SRC"); b=$(lister "$TMP")
   if [ "$a" != "$b" ]; then
      n=$(printf '%s\n%s\n' "$a" "$b" | LC_ALL=C sort | uniq -u | wc -l | tr -d ' ')
      printf '%s\n' "$a" >"$D/$APPID.liste-source"; printf '%s\n' "$b" >"$D/$APPID.liste-copie"
      echouer 1 verification "La copie ne correspond pas a l'original ($n lignes differentes, voir $D/$APPID.liste-*) : rien n'est supprime. Relance le deplacement pour la reprendre."
   fi
   if [ "$VERIFIER" = oui ]; then
      faux=$( (cd "$SRC" && find . -type f ! -name '._*') | while IFS= read -r f; do cmp -s "$SRC/$f" "$TMP/$f" || echo "$f"; done | head -5)
      [ -z "$faux" ] || echouer 1 verification "La copie differe de l'original (contenu) : $(printf '%s' "$faux" | tr '\n' ' ')- rien n'est supprime. Relance le deplacement."
   fi
   rm -f "$D/$APPID.liste-source" "$D/$APPID.liste-copie"
   # les liens qui visaient le dossier du jeu lui-meme, par un chemin absolu
   (cd "$TMP" && find . -type l) 2>/dev/null | while IFS= read -r l; do
      c=$(readlink "$TMP/$l")
      case $c in "$SRC"/*) ln -sfn "$DEST/${c#"$SRC"/}" "$TMP/$l" ;; esac
   done

   # les ._xxx que macOS a poses en route (exFAT, FAT, partage reseau)
   case $FS in exfat|msdos|smbfs|webdav) sans_point_souligne "$TMP" ;; esac

   # --- la bascule -------------------------------------------------------------
   PHASE=bascule; etat en_cours
   mv "$TMP" "$DEST" || echouer 1 copie "Impossible de renommer $TMP en $DEST : l'original est intact."
   rm -f "$CIBLE/._$APPID" "$CIBLE/._.cidre-deplacement-$APPID" 2>/dev/null
fi
[ $DEJA = oui ] && [ -d "$TMP" ] && effacer "$TMP"

# --- l'original s'en va -------------------------------------------------------
PHASE=suppression; etat en_cours
evenement '{"evenement":"deplacement","etat":"en_cours","phase":"suppression"}'
if [ -f "$SRC/steamapps/appmanifest_$APPID.acf" ] && [ ! -f "$DEST/steamapps/appmanifest_$APPID.acf" ]; then
   echouer 1 verification "Le manifeste du jeu manque a destination ($DEST) : l'original est garde."
fi
POUBELLE="$SRCLIB/.cidre-supprime-$APPID.$$"
if mv "$SRC" "$POUBELLE" 2>/dev/null; then
   effacer "$POUBELLE" || dire "attention : $POUBELLE n'a pas pu etre efface entierement (dossier cache, ignore par Cidre) : retire-le a la main."
else
   echouer 1 suppression "$NOM est copie dans « $VOL » ($DEST), mais l'original n'a pas pu etre retire ($SRC) : retire-le a la main."
fi
rm -f "$D/$APPID" "$D/$APPID.avancement" "$ERR"
fin=$(date +%s)
evenement "{\"evenement\":\"deplacement\",\"etat\":\"fait\",\"emplacement\":$(js "$VERS"),\"chemin\":$(js "$DEST"),\"octets\":${TOTAL:-null},\"duree\":$((fin - DEBUT))}"
dire "deplace : $NOM -> $DEST ($((fin - DEBUT)) s). Sauvegardes, prefixe et options n'ont pas bouge."
liberer
exit 0
}
