#!/bin/sh
# Ramene les sauvegardes d'un jeu repris d'une bouteille CrossOver, Whisky ou
# Heroic (`cidre import`) : le jeu a ete clone dans le dossier Cidre, ses
# sauvegardes sont restees dans le prefixe de la bouteille. C'est la fin de
# `cidre import <appid>`, et `cidre import <appid> --saves` pour un jeu repris
# avant que Cidre sache le faire (ou rejoue depuis dans la bouteille).
#
#   reprendre_saves_bouteille.sh <appid> [<bouteille>] [--dossier <chemin>] [--forcer] [--json]
#
# La bouteille est celle que note reprises.conf (ecrit par `cidre import`), ou
# celle qu'on nomme : son nom, source:nom (crossover:Steam), ou sa racine --
# pour un jeu telecharge par `cidre dl` dont les sauvegardes sont dans une
# bouteille. Elle n'est que LUE : rien n'y est ecrit, deplace ni efface.
#
# Ou sont les sauvegardes dans la bouteille, dans l'ordre :
#   1. --dossier <chemin> : un dossier du disque C: de la bouteille
#      (drive_c/users/<nom>/...), que l'utilisateur designe ;
#   2. saves.conf (celui de l'utilisateur, puis celui qu'on livre) ;
#   3. tests/deviner_saves.sh, lance sur le dossier utilisateur de la
#      bouteille : la fiche du jeu ([compat.steam_cloud] dossier_windows, puis
#      [compat.pcgamingwiki] sauvegardes), puis les dossiers des moteurs connus
#      -- ceux-la seulement s'ils portent un nom du jeu (son nom, son dossier,
#      son executable, son projet Unity ou Unreal) : une bouteille sert a
#      plusieurs jeux, « le plus recent » serait souvent celui d'un autre.
#
# Ou elles vont : au meme endroit sous le dossier utilisateur du prefixe de
# Cidre, la ou le jeu les cherchera. Fichier par fichier, comme `cidre sync
# restore` : un fichier absent cote Cidre est copie ; un fichier different et
# plus ancien cote Cidre est remplace, APRES copie de l'ancien dans
# <copies>/<appid>/.history/avant-reprise-<date>/ ; un fichier plus recent (ou
# du meme instant) cote Cidre est garde tel quel. Le superflu (journaux, caches,
# fichiers de plus de 100 Mo) n'est pas repris.
#
# STEAM D'ABORD. Ce que Steam Cloud synchronise a toujours la priorite : un
# fichier que Steam detient n'est jamais remplace par celui d'une bouteille,
# meme plus ancien. La bouteille ne fait que COMBLER un dossier que Steam a
# vide. (tests/lier_saves_steam.sh dit comment Steam synchronise le jeu.)
#   - par l'API de Steam (synchro = "steam-api") : rien n'est copie, jamais.
#     Ces sauvegardes sont dans le stockage du client Steam
#     (userdata/.../remote), que seul le client doit ecrire. On dit combien la
#     bouteille en garde, et ou. Exception : le dossier LOCAL que designe
#     saves.conf (Vermintide 2) n'est pas confie a Steam ; il suit la regle
#     ordinaire (le plus recent gagne, l'ancien est garde).
#   - par un dossier macOS lie (synchro = "steam-lien", ou tout dossier du
#     prefixe qui est deja un lien pose par lier_saves_steam.sh) :
#       . Steam a des sauvegardes de ce jeu -- le dossier lie en contient, ou
#         le client Steam de ce Mac en connait dans le nuage pour macOS
#         (userdata/<compte>/<appid>/remotecache.vdf) : RIEN n'est copie, pas
#         meme les fichiers que Steam n'a pas. Etat "steam_prioritaire" ; on
#         dit combien la bouteille en garde, ou, et la commande pour passer
#         outre ;
#       . Steam n'en a aucune : la bouteille comble le dossier (le lien est
#         pose d'abord, comme au premier lancement), pour que le jeu ne
#         demarre pas a vide ; Steam les enverra a la sortie du jeu. Si le
#         client Steam n'a encore jamais synchronise ce jeu sur ce Mac (pas de
#         remotecache.vdf), on ne peut pas savoir ce que garde le nuage : on
#         previent qu'un conflit Steam Cloud est possible ("conflit_possible").
#   --forcer : le joueur veut les sauvegardes de la bouteille. Elles sont
#     copiees par-dessus celles du dossier, Steam ou non, quelle que soit leur
#     date ; chaque fichier remplace est d'abord garde dans l'historique.
#     Jamais par defaut, et sans effet sur le stockage de l'API de Steam.
# Un jeu qui range ses sauvegardes dans son propre dossier (`jeu:...`) les a
# emportees avec lui : rien a faire.
#
# Sortie : un compte rendu ; avec --json, un objet sur la sortie standard (le
# compte rendu va a la sortie d'erreur) :
#   {"appid":N,"etat":E,"fichiers":N,"remplaces":N,"gardes":N,"identiques":N,
#    "octets":N,"origine":"crossover","bouteille":"Steam","depuis":"...",
#    "vers":"...","dossier":"AppData/...","synchro":S,"historique":"...",
#    "steam_fichiers":N,"steam_distants":B,"conflit_possible":B,"force":B,
#    "date":N,"message":"une phrase"}
#   etat : copie (des fichiers ont ete ramenes : "fichiers", dont "remplaces"),
#          a_jour (rien a ramener : "identiques", ou plus recents ici : "gardes"),
#          steam (Steam Cloud s'en charge par son API : rien n'est copie),
#          steam_prioritaire (le dossier que Steam synchronise a deja des
#            sauvegardes : rien n'est copie ; "steam_fichiers" = combien Steam
#            en a, "steam_distants" = vrai s'il ne les a que dans le nuage,
#            "gardes" = combien la bouteille en garde),
#          avec_le_jeu (elles sont dans le dossier du jeu, venues avec lui),
#          absentes (on sait ou elles seraient : la bouteille n'en a pas),
#          introuvable (on ne sait pas ou ce jeu les range)
#   synchro : steam_api | steam_macos | copie | aucune (comme `cidre saves --json`)
# Cet objet est garde dans <Cidre>/reprises.saves/<appid>.json : `cidre saves
# <id> --json` le rend sous "reprise".
# Un refus -- jeu absent du dossier Cidre, aucune bouteille connue, bouteille
# disparue, disque C: de Cidre pas encore cree -- rend 1 et, avec --json,
# {"appid":N,"etat":"erreur","raison":R,"message":"..."} ; rien n'est garde.
# Codes de retour : 0 fait (quel que soit l'etat), 1 refuse, 2 usage.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
JEUX="$CIDRE_DIR/games"
TAB=$(printf '\t')
usage() { echo "usage: cidre import <appid> [<bouteille>] --saves [--dossier <dossier de la bouteille>] [--forcer]" >&2; exit 2; }
APPID=; QUI=; DOSSIER=; JSON=non; FORCER=non
while [ $# -gt 0 ]; do
   case $1 in
      --json) JSON=oui ;;
      --forcer|--force) FORCER=oui ;;
      --dossier) [ $# -ge 2 ] || usage; DOSSIER=$2; shift ;;
      -*) usage ;;
      *) if [ -z "$APPID" ]; then APPID=$1; elif [ -z "$QUI" ]; then QUI=$1; else usage; fi ;;
   esac
   shift
done
case $APPID in ''|*[!0-9]*) usage ;; esac

js() { printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\n\r' '   ')"; }
# le compte rendu : sur la sortie standard, ou sur l'erreur quand la sortie est du JSON
dire() { if [ "$JSON" = oui ]; then printf '%s\n' "$1" >&2; else printf '%s\n' "$1"; fi; }
refus() { # <raison> <message>
   echo "$2" >&2
   [ "$JSON" = oui ] && printf '{"appid":%s,"etat":"erreur","raison":"%s","message":%s}\n' "$APPID" "$1" "$(js "$2")"
   exit 1
}
physique() { (cd "$1" 2>/dev/null && pwd -P); }
outil() { case $1 in crossover) echo CrossOver ;; whisky) echo Whisky ;; heroic) echo Heroic ;; *) echo "$1" ;; esac; }

[ -d "$JEUX/$APPID" ] || refus jeu_absent "$APPID n'est pas dans le dossier Cidre : le reprendre d'abord (cidre import $APPID)"

# --- la bouteille -----------------------------------------------------------
SOURCE=; BOUTEILLE=; RACINE=
if [ -n "$QUI" ]; then
   l=$(sh "$R/tests/trouver_jeux_bouteilles.sh" --bouteilles | awk -F'\t' -v q="$QUI" '$2 == q || $1 ":" $2 == q || $3 == q { print; exit }')
   [ -n "$l" ] || refus sans_bouteille "bouteille introuvable : $QUI"
else
   l=$(awk -F'\t' -v a="$APPID" '$1 == a { print $2 "\t" $3 "\t" $4; exit }' "$CIDRE_DIR/reprises.conf" 2>/dev/null)
   [ -n "$l" ] || refus sans_reprise "$APPID n'a pas ete repris d'une bouteille : nommer celle qui a ses sauvegardes (cidre import $APPID <bouteille> --saves ; cidre bottles les montre)"
fi
SOURCE=$(printf '%s\n' "$l" | cut -f1); BOUTEILLE=$(printf '%s\n' "$l" | cut -f2); RACINE=$(printf '%s\n' "$l" | cut -f3)
[ -d "$RACINE/drive_c" ] ||
   refus bouteille_absente "la bouteille « $BOUTEILLE » ($(outil "$SOURCE")) n'est plus la : $RACINE (supprimee, ou sur un disque debranche)"
# les dossiers utilisateur de la bouteille (`crossover` pour CrossOver et
# Whisky, le nom de session ou `steamuser` pour Heroic)
utilisateurs() {
   for u in "$RACINE/drive_c/users"/*/; do
      u=${u%/}; [ "$(basename "$u")" = Public ] && continue
      [ -d "$u" ] && printf '%s\n' "$u"
   done
}
# le premier d'entre eux qui a ce dossier
qui_a() { # <relatif>
   utilisateurs | while IFS= read -r u; do [ -d "$u/$1" ] && { printf '%s\n' "$u"; break; }; done
}

# --- le prefixe de Cidre ----------------------------------------------------
UTILC=${CIDRE_PREFIXE_UTIL:-}
if [ -z "$UTILC" ]; then
   a=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
   [ -n "$a" ] && UTILC=$(dirname "$a")
fi
sans_prefixe() { refus prefixe_absent "le disque C: de Cidre n'existe pas encore (cidre setup) : les sauvegardes de $APPID sont restees dans la bouteille ; ensuite : cidre import $APPID --saves"; }

# --- ce que le jeu s'appelle : pour l'heuristique des moteurs ---------------
noms() {
   m="$JEUX/$APPID/steamapps/appmanifest_$APPID.acf"
   for c in name installdir; do
      tr -d '\r' <"$m" 2>/dev/null | sed -n 's/^[[:space:]]*"'$c'"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' | head -1
   done
   for e in "$JEUX/$APPID"/*.exe; do
      [ -f "$e" ] || continue
      case $(basename "$e") in UnityCrashHandler*|unins*|UnrealCEFSubProcess*|CrashReport*) continue ;; esac
      basename "$e" .exe
   done
   # Unity : <jeu>_Data/app.info = l'editeur, puis le produit (LocalLow/<editeur>/<produit>)
   for a in "$JEUX/$APPID"/*_Data/app.info; do [ -f "$a" ] && tr -d '\r' <"$a" | sed -n 2p; done
   # Unreal : le projet est le dossier qui porte Binaries/Win64 (Local/<projet>/Saved/SaveGames)
   for b in "$JEUX/$APPID"/*/Binaries/Win64; do
      [ -d "$b" ] || continue
      p=$(basename "$(dirname "$(dirname "$b")")"); [ "$p" = Engine ] || printf '%s\n' "$p"
   done
}

# --- l'etat, et comment on le rend ------------------------------------------
ETAT=; NF=0; NR=0; NG=0; NI=0; OCT=0; DEPUIS=; VERS=; REL=; SYNCHRO=aucune; HIST=; MESSAGE=
NSTEAM=0; ND=0; DISTANTS=false; CONFLIT=false
rendre() {
   [ $FORCER = oui ] && force=true || force=false
   obj=$(printf '{"appid":%s,"etat":"%s","fichiers":%s,"remplaces":%s,"gardes":%s,"identiques":%s,"octets":%s,"origine":%s,"bouteille":%s,"depuis":%s,"vers":%s,"dossier":%s,"synchro":"%s","historique":%s,"steam_fichiers":%s,"steam_distants":%s,"conflit_possible":%s,"force":%s,"date":%s,"message":%s}' \
      "$APPID" "$ETAT" $((NF + NR)) "$NR" "$NG" "$NI" "$OCT" "$(js "$SOURCE")" "$(js "$BOUTEILLE")" "$(js "$DEPUIS")" "$(js "$VERS")" \
      "$(js "$REL")" "$SYNCHRO" "$(js "$HIST")" "$NSTEAM" "$DISTANTS" "$CONFLIT" "$force" "$(date +%s)" "$(js "$MESSAGE")")
   mkdir -p "$CIDRE_DIR/reprises.saves" && printf '%s\n' "$obj" >"$CIDRE_DIR/reprises.saves/$APPID.json"
   [ "$JSON" = oui ] && printf '%s\n' "$obj"
   exit 0
}
QUI_DIT="la bouteille « $BOUTEILLE » ($(outil "$SOURCE"))"

# --- copier un dossier de la bouteille vers Cidre, sans rien perdre ---------
# (le meme tri que tests/sync_saves_steam.sh)
JUNK='/cache/|/logs/|/crash|dumps/|image_cache/|/shader|PopsFeed|PopsMods|EarlyCrashReports|/Temp/|\.log$'
MAXSZ=104857600
TS=$(date '+%Y%m%d-%H%M%S')
COPIES=$(sh "$R/tests/sync_saves_steam.sh" - dossier)
LISTE=$(mktemp "${TMPDIR:-/tmp}/reprise-saves.XXXXXX") || exit 1
trap 'rm -f "$LISTE" "$LISTE.l"' EXIT
NPAIRE=0
# les fichiers de sauvegarde d'un dossier (chemins sous le dossier, sans le superflu)
# (le tri porte sur le chemin, barre en tete : `/cache/x`)
lister() { ( cd "$1" 2>/dev/null && find . -type f ) 2>/dev/null | sed 's|^\.||' | grep -avE "$JUNK" | sed 's|^/||'; }
compter() { lister "$1" | wc -l | tr -d ' '; }
# <regle> : `date` -- le plus recent gagne (un fichier plus recent cote Cidre
# est garde) ; `combler` -- seuls les fichiers absents sont copies, aucun n'est
# remplace ; `forcer` -- celui de la bouteille gagne toujours. Un fichier
# remplace est d'abord copie dans l'historique du jeu.
copier() { # <dossier de la bouteille> <dossier cote Cidre> <regle>
   src=$1; dst=$2; regle=$3
   lister "$src" >"$LISTE"
   h="$COPIES/$APPID/.history/avant-reprise-$TS/$NPAIRE"; NPAIRE=$((NPAIRE + 1))
   while IFS= read -r f; do
      s="$src/$f"; d="$dst/$f"
      set -- $(stat -f '%m %z' "$s" 2>/dev/null); [ $# -eq 2 ] || continue
      [ "$2" -le "$MAXSZ" ] || continue
      if [ ! -e "$d" ] && [ ! -L "$d" ]; then
         mkdir -p "$(dirname "$d")" && cp -p "$s" "$d" || { dire "    saves: copie impossible : $d"; continue; }
         NF=$((NF + 1)); OCT=$((OCT + $2))
      elif [ ! -f "$d" ]; then NG=$((NG + 1))   # autre chose qu'un fichier a cette place : on n'y touche pas
      elif cmp -s "$s" "$d"; then NI=$((NI + 1))
      elif [ $regle = forcer ] || { [ $regle = date ] && [ "$1" -gt "$(stat -f %m "$d")" ]; }; then
         # celui de la bouteille l'emporte : l'ancien est garde, puis remplace
         mkdir -p "$h/$(dirname "$f")" && cp -p "$d" "$h/$f" || { dire "    saves: copie de precaution impossible, $f laisse tel quel"; NG=$((NG + 1)); continue; }
         [ -f "$h.origine" ] || printf '%s\n' "$dst" >"$h.origine"
         cp -p "$s" "$d" || { dire "    saves: copie impossible : $d"; continue; }
         NR=$((NR + 1)); OCT=$((OCT + $2)); HIST=$(dirname "$h")
      else NG=$((NG + 1)); fi
   done <"$LISTE"
}

# --- Steam d'abord ------------------------------------------------------------
# Un dossier du prefixe que Steam synchronise : le lien pose par
# lier_saves_steam.sh -- le dossier lui-meme, ou un de ses parents. Pas les
# dossiers de premier niveau (Documents, Bureau...), que Wine lie au Mac.
lie_a_steam() { # <dossier sous $UTILC>
   p=$1
   while [ "$p" != / ] && [ "$p" != "$UTILC" ] && [ "$(dirname "$p")" != "$UTILC" ]; do
      [ -L "$p" ] && return 0
      p=$(dirname "$p")
   done
   return 1
}
# Ce que le client Steam de ce Mac sait du nuage pour ce jeu : son
# remotecache.vdf, ecrit a chaque synchronisation. CONNU = il existe (le client
# a deja synchronise ce jeu ici) ; ND = les fichiers qu'il y note pour macOS
# (platformstosync2 : -1 = tous les systemes, bit 2 = macOS ; un fichier que le
# jeu ne declare que pour Windows ne descendra jamais sur ce Mac : pas compte).
USERDATA=${CIDRE_STEAM_USERDATA:-$HOME/Library/Application Support/Steam/userdata}
distants() {
   CONNU=non; ND=0
   for c in "$USERDATA"/*/"$APPID"/remotecache.vdf; do
      [ -f "$c" ] || continue
      CONNU=oui
      n=$(LC_ALL=C awk '
         /^[ \t]*\{/ { prof++; if (prof == 2) { taille = 0; rt = 0; sha = ""; p = -1 } next }
         /^[ \t]*\}/ { if (prof == 2 && (p < 0 || int(p / 2) % 2 == 1) && (taille > 0 || rt > 0 || sha ~ /[1-9a-f]/)) nb++; prof--; next }
         prof == 2 { split($0, q, "\""); if (q[2] == "size") taille = q[4] + 0; else if (q[2] == "remotetime") rt = q[4] + 0
                     else if (q[2] == "sha") sha = q[4]; else if (q[2] == "platformstosync2") p = q[4] + 0 }
         END { print nb + 0 }' "$c")
      ND=$((ND + n))
   done
}
# La reprise vers un dossier que Steam synchronise. <fichier> : une ligne
# `dossier de la bouteille (ou -) <TAB> dossier du prefixe (le lien)` par
# dossier (les colonnes suivantes ne sont pas lues).
# Pose ETAT et le compte rendu.
steam_dabord() {
   NSTEAM=0; nbout=0
   while IFS="$TAB" read -r s d reste; do
      NSTEAM=$((NSTEAM + $(compter "$d")))
      [ "$s" = - ] || nbout=$((nbout + $(compter "$s")))
   done <"$1"
   distants
   if [ $nbout -eq 0 ]; then
      ETAT=absentes
      dire "  sauvegardes : aucune dans la bouteille (dossier attendu : ${REL:-?}) ; Steam Cloud synchronise ce jeu"
      MESSAGE="Aucune sauvegarde de ce jeu dans $QUI_DIT"
      return
   fi
   if [ $FORCER = non ] && [ $((NSTEAM + ND)) -gt 0 ]; then
      ETAT=steam_prioritaire; NG=$nbout
      dire "  sauvegardes : Steam Cloud a deja des sauvegardes de ce jeu : elles ont la priorite, rien n'est copie de la bouteille"
      if [ $NSTEAM -gt 0 ]; then dire "                Steam     : $NSTEAM fichier(s) dans $VERS"
      else
         DISTANTS=true; NSTEAM=$ND
         dire "                Steam     : $ND fichier(s) dans le nuage, que le client Steam connait (pas encore sur ce Mac)"
      fi
      dire "                bouteille : $nbout fichier(s), intacts : $DEPUIS"
      dire "                pour les copier quand meme par-dessus celles de Steam (les versions remplacees sont gardees) :"
      dire "                cidre import $APPID --saves --forcer"
      MESSAGE="Steam Cloud a déjà des sauvegardes de ce jeu : elles ont la priorité, rien n'a été copié de $QUI_DIT, qui garde ses $nbout fichier(s)"
      return
   fi
   regle=combler; [ $FORCER = oui ] && regle=forcer
   while IFS="$TAB" read -r s d reste; do [ "$s" = - ] || copier "$s" "$d" $regle; done <"$1"
   if [ $((NF + NR)) -gt 0 ]; then
      ETAT=copie
      if [ $FORCER = oui ]; then
         dire "  sauvegardes : $((NF + NR)) fichier(s) ramene(s) de la bouteille par-dessus le dossier que Steam Cloud synchronise (--forcer)"
         MESSAGE="$((NF + NR)) fichier(s) de sauvegarde ramené(s) de $QUI_DIT par-dessus le dossier que Steam Cloud synchronise (forcé)"
      else
         dire "  sauvegardes : $((NF + NR)) fichier(s) ramene(s) de la bouteille, dans le dossier que Steam Cloud synchronise"
         dire "                (Steam n'y avait aucune sauvegarde de ce jeu)"
         MESSAGE="$((NF + NR)) fichier(s) de sauvegarde ramené(s) de $QUI_DIT dans le dossier que Steam Cloud synchronise, qui était vide"
         if [ $CONNU = non ]; then
            CONFLIT=true
            MESSAGE="$MESSAGE ; si Steam Cloud en garde d'autres, faites ailleurs, Steam demandera laquelle garder"
         fi
      fi
   else
      ETAT=a_jour
      dire "  sauvegardes : rien a ramener de la bouteille : celles du dossier que Steam Cloud synchronise sont identiques"
      MESSAGE="Rien à ramener de $QUI_DIT : les sauvegardes du dossier que Steam Cloud synchronise sont identiques"
   fi
}

# --- 1. ou sont-elles ? ------------------------------------------------------
LIGNE=$(cat "$CIDRE_DIR/saves.conf" "$R/outil-steam/saves.conf" 2>/dev/null | awk -F'\t' -v a="$APPID" '$1 == a { print $2; exit }')
STEAM_MODE=
[ -n "$DOSSIER" ] || STEAM_MODE=$(CIDRE_PREFIXE_UTIL="$UTILC" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/lier_saves_steam.sh" "$APPID" mode 2>/dev/null || true)
BU=; MEMORISER=non
if [ -n "$DOSSIER" ]; then
   # le dossier que designe l'utilisateur : il doit etre sur le disque C: de la bouteille
   [ -d "$DOSSIER" ] || refus dossier_absent "dossier introuvable : $DOSSIER"
   case $DOSSIER in /*) ;; *) DOSSIER="$(pwd)/$DOSSIER" ;; esac
   d1=${DOSSIER%/}; d2=$(physique "$DOSSIER")
   utilisateurs >"$LISTE"
   while IFS= read -r u; do
      for forme in "$u" "$(physique "$u")"; do
         for d in "$d1" "$d2"; do
            case $d in "$forme"/?*) BU=$u; REL=${d#"$forme"/} ;; esac
         done
      done
      [ -z "$BU" ] || break
   done <"$LISTE"
   [ -n "$BU" ] || refus dossier_hors_bouteille "ce dossier n'est pas sur le disque C: de $QUI_DIT : il doit etre sous $RACINE/drive_c/users/<nom>/"
   MEMORISER=oui
elif [ "$STEAM_MODE" = api ] && [ -z "$LIGNE" ]; then
   # Steam Cloud par l'API : le stockage du client Steam, on n'y ecrit pas
   ETAT=steam; SYNCHRO=steam_api
   n=0
   for rem in "$RACINE/drive_c/Program Files (x86)/Steam/userdata"/*/"$APPID"/remote "$RACINE/drive_c/Program Files/Steam/userdata"/*/"$APPID"/remote; do
      [ -d "$rem" ] || continue
      n=$(find "$rem" -type f 2>/dev/null | wc -l | tr -d ' '); DEPUIS=$rem; break
   done
   dire "  sauvegardes : Steam Cloud synchronise deja ce jeu (il ecrit par l'API de Steam) : rien n'est copie,"
   dire "                le client Steam les fournit au jeu"
   [ $FORCER = non ] || dire "                (--forcer n'y change rien : ce stockage est celui du client Steam, Cidre n'y ecrit pas)"
   MESSAGE="Steam Cloud synchronise déjà ce jeu : rien n'a été copié de $QUI_DIT"
   if [ "$n" -gt 0 ]; then
      dire "                (la bouteille en garde $n fichier(s), intacts : $DEPUIS)"
      MESSAGE="$MESSAGE, qui garde ses $n fichier(s)"
   fi
   rendre
fi

# --- 2. Steam Cloud par un dossier macOS lie : Steam d'abord ------------------
if [ "$STEAM_MODE" = lien ]; then
   [ -n "$UTILC" ] && [ -d "$UTILC" ] || sans_prefixe
   # le lien se pose comme au premier lancement ; s'il ne peut pas l'etre, la
   # copie Cidre prend la main, ici comme dans sync_saves_steam.sh
   if l=$(CIDRE_PREFIXE_UTIL="$UTILC" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/lier_saves_steam.sh" "$APPID" lier 2>&1); then
      [ -z "$l" ] || dire "$l"
      SYNCHRO=steam_macos; attendu=; vers1=
      CIDRE_PREFIXE_UTIL="$UTILC" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/lier_saves_steam.sh" "$APPID" dossiers 2>/dev/null |
         while IFS="$TAB" read -r w m; do
            case $w in "$UTILC"/?*) rel=${w#"$UTILC"/} ;; *) continue ;; esac
            u=$(qui_a "$rel"); [ -n "$u" ] && s="$u/$rel" || s=-
            printf '%s\t%s\t%s\t%s\n' "$s" "$w" "$rel" "$m"
         done >"$LISTE.l"
      # (ce qu'on montre : la premiere paire que la bouteille a ; sinon la premiere)
      while IFS="$TAB" read -r s w rel m; do
         [ -n "$attendu" ] || { attendu=$rel; vers1=$m; }
         [ "$s" = - ] || [ -n "$DEPUIS" ] || { DEPUIS=$s; VERS=$m; REL=$rel; }
      done <"$LISTE.l"
      [ -n "$REL" ] || { REL=$attendu; VERS=$vers1; }
      steam_dabord "$LISTE.l"
      rm -f "$LISTE.l"
   else
      [ -z "$l" ] || dire "$l"
      STEAM_MODE=
   fi
fi

# --- 3. le reste : au meme endroit dans le prefixe de Cidre ------------------
if [ -z "$ETAT" ]; then
   [ "$STEAM_MODE" = api ] && SYNCHRO=steam_api || SYNCHRO=copie
   [ -n "$REL" ] || REL=$LIGNE
   if [ -z "$REL" ]; then
      # la fiche d'abord (elle peut designer le dossier du jeu) ; puis les
      # dossiers des moteurs, hors du dossier du jeu, et au nom du jeu seulement
      # (aucun nom connu : `-` ne designe aucun dossier, rien n'est pris au hasard)
      NOMS=$(noms); [ -n "$NOMS" ] || NOMS=-
      utilisateurs >"$LISTE"
      while IFS= read -r u; do
         REL=$(CIDRE_PREFIXE_UTIL="$u" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/deviner_saves.sh" "$APPID" 2>/dev/null) ||
            REL=$(CIDRE_PREFIXE_UTIL="$u" CIDRE_JEU_DOSSIER=/nonexistent CIDRE_DEVINER_NOMS="$NOMS" sh "$R/tests/deviner_saves.sh" "$APPID" 1 2>/dev/null) || REL=
         [ -z "$REL" ] || { BU=$u; MEMORISER=oui; break; }
      done <"$LISTE"
   fi
   case $REL in
      '')
         ETAT=introuvable; SYNCHRO=aucune
         u=$(utilisateurs | head -1)
         dire "  sauvegardes : non trouvees dans la bouteille : ni la fiche du jeu ni les dossiers habituels des moteurs ne"
         dire "                disent ou ce jeu les range (si c'est dans son propre dossier, elles sont venues avec lui)."
         dire "                Si tu sais ou elles sont : cidre import $APPID --saves --dossier <dossier sous ${u:-$RACINE/drive_c/users}>"
         MESSAGE="Sauvegardes non trouvées dans $QUI_DIT : Cidre ne sait pas où ce jeu les range" ;;
      jeu:*)
         ETAT=avec_le_jeu; VERS="$JEUX/$APPID/${REL#jeu:}"
         dire "  sauvegardes : ce jeu les range dans son propre dossier (${REL#jeu:}) : elles sont venues avec lui"
         MESSAGE="Ce jeu range ses sauvegardes dans son propre dossier : elles sont venues avec lui" ;;
      *)
         [ -n "$UTILC" ] && [ -d "$UTILC" ] || sans_prefixe
         [ -n "$BU" ] || BU=$(qui_a "$REL")
         VERS="$UTILC/$REL"
         if [ -n "$BU" ] && [ -d "$BU/$REL" ] && lie_a_steam "$VERS"; then
            # ce dossier du prefixe est deja un lien vers un dossier que Steam
            # synchronise (pose a un lancement precedent) : Steam d'abord, ici aussi
            DEPUIS="$BU/$REL"; SYNCHRO=steam_macos
            printf '%s\t%s\n' "$DEPUIS" "$VERS" >"$LISTE.l"
            VERS=$(physique "$VERS" || printf '%s' "$VERS")
            steam_dabord "$LISTE.l"
            rm -f "$LISTE.l"
         elif [ -z "$BU" ] || [ ! -d "$BU/$REL" ]; then
            ETAT=absentes
            dire "  sauvegardes : aucune dans la bouteille (dossier attendu : $REL)"
            MESSAGE="Aucune sauvegarde de ce jeu dans $QUI_DIT"
         else
            DEPUIS="$BU/$REL"
            regle=date; [ $FORCER = oui ] && regle=forcer
            copier "$DEPUIS" "$VERS" $regle
            if [ $((NF + NR)) -gt 0 ]; then
               ETAT=copie
               dire "  sauvegardes : $((NF + NR)) fichier(s) ramene(s) de la bouteille"
               MESSAGE="$((NF + NR)) fichier(s) de sauvegarde ramené(s) de $QUI_DIT"
            elif [ $((NI + NG)) -gt 0 ]; then
               ETAT=a_jour
               dire "  sauvegardes : rien a ramener de la bouteille : celles de Cidre sont identiques ou plus recentes"
               MESSAGE="Rien à ramener de $QUI_DIT : les sauvegardes de Cidre sont identiques ou plus récentes"
            else
               ETAT=absentes
               dire "  sauvegardes : aucune dans la bouteille (dossier vide : $DEPUIS)"
               MESSAGE="Aucune sauvegarde de ce jeu dans $QUI_DIT"
            fi
            # le dossier trouve est note, comme apres une partie : `cidre saves`
            # et la copie de Cidre sauront ou regarder
            if [ $MEMORISER = oui ] && [ "$ETAT" != absentes ]; then
               touch "$CIDRE_DIR/saves.conf"
               awk -F'\t' -v i="$APPID" '$1 != i' "$CIDRE_DIR/saves.conf" >"$CIDRE_DIR/saves.conf.tmp"
               printf '%s\t%s\n' "$APPID" "$REL" >>"$CIDRE_DIR/saves.conf.tmp"
               mv "$CIDRE_DIR/saves.conf.tmp" "$CIDRE_DIR/saves.conf"
            fi
         fi ;;
   esac
fi

# --- le detail ---------------------------------------------------------------
if [ -n "$DEPUIS" ] && [ "$ETAT" != absentes ] && [ "$ETAT" != steam_prioritaire ]; then
   dire "                de   : $DEPUIS"
   dire "                vers : $VERS"
fi
if [ "$NR" -gt 0 ]; then
   [ $FORCER = oui ] && comment="par la version de la bouteille" || comment="par une version plus recente de la bouteille"
   dire "                $NR remplace(s) $comment ; l'ancienne est gardee : $HIST"
   MESSAGE="$MESSAGE ; $NR remplacé(s), l'ancienne version est gardée"
fi
if [ "$NG" -gt 0 ] && [ "$ETAT" != steam_prioritaire ]; then
   [ "$SYNCHRO" = steam_macos ] && dire "                $NG deja la cote Steam : garde(s) tel(s) quel(s)" ||
      dire "                $NG plus recent(s) cote Cidre : garde(s) tel(s) quel(s)"
   [ "$ETAT" != copie ] || MESSAGE="$MESSAGE ; $NG plus récent(s) ici, gardé(s)"
fi
if [ $CONFLIT = true ]; then
   dire "                attention : le client Steam de ce Mac n'a encore jamais synchronise ce jeu ; Cidre ne peut pas savoir"
   dire "                si Steam Cloud en garde des sauvegardes faites ailleurs. S'il en a, Steam signalera un conflit a la"
   dire "                sortie du jeu : choisis alors dans Steam la version a garder."
fi
[ "$SYNCHRO" != steam_api ] || [ "$ETAT" = steam ] ||
   dire "                (Steam Cloud synchronise par ailleurs ce que le jeu ecrit par l'API de Steam)"
rendre
