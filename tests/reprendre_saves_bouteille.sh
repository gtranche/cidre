#!/bin/sh
# Ramene les sauvegardes d'un jeu repris d'une bouteille CrossOver, Whisky ou
# Heroic (`cidre import`) : le jeu a ete clone dans le dossier Cidre, ses
# sauvegardes sont restees dans le prefixe de la bouteille. C'est la fin de
# `cidre import <appid>`, et `cidre import <appid> --saves` pour un jeu repris
# avant que Cidre sache le faire (ou rejoue depuis dans la bouteille).
#
#   reprendre_saves_bouteille.sh <appid> [<bouteille>] [--dossier <chemin>] [--json]
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
# Quand Steam Cloud synchronise deja le jeu (tests/lier_saves_steam.sh) :
#   - par l'API de Steam (synchro = "steam-api") : rien n'est copie. Ces
#     sauvegardes sont dans le stockage du client Steam (userdata/.../remote),
#     que seul le client doit ecrire : y deposer des fichiers a sa place
#     contredirait ce qu'il sait du nuage. On dit combien la bouteille en garde,
#     et ou. Exception : le dossier LOCAL que designe saves.conf (Vermintide 2)
#     n'est pas confie a Steam ; il est repris comme les autres.
#   - par un dossier macOS lie (synchro = "steam-lien") : les fichiers sont
#     copies DANS ce dossier macOS (le lien est pose d'abord, comme au premier
#     lancement), avec la meme regle. Le client Steam de macOS ne descend pas
#     les fichiers d'un jeu qu'il ne lance pas lui-meme, et un jeu qui declare
#     ses fichiers par systeme (PEAK) ne partage pas ceux de Windows avec le
#     Mac : sans cette copie, le jeu demarrerait sans sauvegarde. Steam les
#     enverra a la sortie du jeu, comme toute partie jouee ici.
# Un jeu qui range ses sauvegardes dans son propre dossier (`jeu:...`) les a
# emportees avec lui : rien a faire.
#
# Sortie : un compte rendu ; avec --json, un objet sur la sortie standard (le
# compte rendu va a la sortie d'erreur) :
#   {"appid":N,"etat":E,"fichiers":N,"remplaces":N,"gardes":N,"identiques":N,
#    "octets":N,"origine":"crossover","bouteille":"Steam","depuis":"...",
#    "vers":"...","dossier":"AppData/...","synchro":S,"historique":"...",
#    "date":N,"message":"une phrase"}
#   etat : copie (des fichiers ont ete ramenes : "fichiers", dont "remplaces"),
#          a_jour (rien a ramener : "identiques", ou plus recents ici : "gardes"),
#          steam (Steam Cloud s'en charge par son API : rien n'est copie),
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
usage() { echo "usage: cidre import <appid> [<bouteille>] --saves [--dossier <dossier de la bouteille>]" >&2; exit 2; }
APPID=; QUI=; DOSSIER=; JSON=non
while [ $# -gt 0 ]; do
   case $1 in
      --json) JSON=oui ;;
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
rendre() {
   obj=$(printf '{"appid":%s,"etat":"%s","fichiers":%s,"remplaces":%s,"gardes":%s,"identiques":%s,"octets":%s,"origine":%s,"bouteille":%s,"depuis":%s,"vers":%s,"dossier":%s,"synchro":"%s","historique":%s,"date":%s,"message":%s}' \
      "$APPID" "$ETAT" $((NF + NR)) "$NR" "$NG" "$NI" "$OCT" "$(js "$SOURCE")" "$(js "$BOUTEILLE")" "$(js "$DEPUIS")" "$(js "$VERS")" \
      "$(js "$REL")" "$SYNCHRO" "$(js "$HIST")" "$(date +%s)" "$(js "$MESSAGE")")
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
copier() { # <dossier de la bouteille> <dossier cote Cidre>
   src=$1; dst=$2
   # (le tri porte sur le chemin sous le dossier, barre en tete : `/cache/x`)
   ( cd "$src" && find . -type f ) 2>/dev/null | sed 's|^\.||' | grep -avE "$JUNK" | sed 's|^/||' >"$LISTE"
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
      elif [ "$1" -gt "$(stat -f %m "$d")" ]; then
         # celui de la bouteille est plus recent : l'ancien est garde, puis remplace
         mkdir -p "$h/$(dirname "$f")" && cp -p "$d" "$h/$f" || { dire "    saves: copie de precaution impossible, $f laisse tel quel"; NG=$((NG + 1)); continue; }
         [ -f "$h.origine" ] || printf '%s\n' "$dst" >"$h.origine"
         cp -p "$s" "$d" || { dire "    saves: copie impossible : $d"; continue; }
         NR=$((NR + 1)); OCT=$((OCT + $2)); HIST=$(dirname "$h")
      else NG=$((NG + 1)); fi
   done <"$LISTE"
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
   MESSAGE="Steam Cloud synchronise déjà ce jeu : rien n'a été copié de $QUI_DIT"
   if [ "$n" -gt 0 ]; then
      dire "                (la bouteille en garde $n fichier(s), intacts : $DEPUIS)"
      MESSAGE="$MESSAGE, qui garde ses $n fichier(s)"
   fi
   rendre
fi

# --- 2. Steam Cloud par un dossier macOS lie : on copie dans ce dossier ------
if [ "$STEAM_MODE" = lien ]; then
   [ -n "$UTILC" ] && [ -d "$UTILC" ] || sans_prefixe
   # le lien se pose comme au premier lancement ; s'il ne peut pas l'etre, la
   # copie Cidre prend la main, ici comme dans sync_saves_steam.sh
   if l=$(CIDRE_PREFIXE_UTIL="$UTILC" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/lier_saves_steam.sh" "$APPID" lier 2>&1); then
      [ -z "$l" ] || dire "$l"
      SYNCHRO=steam_macos; attendu=
      CIDRE_PREFIXE_UTIL="$UTILC" CIDRE_JEU_DOSSIER="$JEUX/$APPID" sh "$R/tests/lier_saves_steam.sh" "$APPID" dossiers >"$LISTE.l" 2>/dev/null
      while IFS="$TAB" read -r w m; do
         case $w in "$UTILC"/?*) rel=${w#"$UTILC"/} ;; *) continue ;; esac
         [ -n "$attendu" ] || attendu=$rel
         u=$(qui_a "$rel"); [ -n "$u" ] || continue
         [ -n "$DEPUIS" ] || { DEPUIS="$u/$rel"; VERS=$m; REL=$rel; }
         copier "$u/$rel" "$w"
      done <"$LISTE.l"
      rm -f "$LISTE.l"
      [ -n "$REL" ] || REL=$attendu
      if [ $((NF + NR)) -gt 0 ]; then
         ETAT=copie
         dire "  sauvegardes : $((NF + NR)) fichier(s) ramene(s) de la bouteille, dans le dossier que Steam Cloud synchronise"
         MESSAGE="$((NF + NR)) fichier(s) de sauvegarde ramené(s) de $QUI_DIT dans le dossier que Steam Cloud synchronise"
      elif [ $((NI + NG)) -gt 0 ]; then
         ETAT=a_jour
         dire "  sauvegardes : rien a ramener de la bouteille : celles du dossier que Steam Cloud synchronise sont identiques ou plus recentes"
         MESSAGE="Rien à ramener de $QUI_DIT : les sauvegardes du dossier que Steam Cloud synchronise sont identiques ou plus récentes"
      else
         ETAT=absentes
         dire "  sauvegardes : aucune dans la bouteille (dossier attendu : ${REL:-?}) ; Steam Cloud synchronise ce jeu"
         MESSAGE="Aucune sauvegarde de ce jeu dans $QUI_DIT"
      fi
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
         if [ -z "$BU" ] || [ ! -d "$BU/$REL" ]; then
            ETAT=absentes
            dire "  sauvegardes : aucune dans la bouteille (dossier attendu : $REL)"
            MESSAGE="Aucune sauvegarde de ce jeu dans $QUI_DIT"
         else
            DEPUIS="$BU/$REL"
            copier "$DEPUIS" "$VERS"
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
if [ -n "$DEPUIS" ] && [ "$ETAT" != absentes ]; then
   dire "                de   : $DEPUIS"
   dire "                vers : $VERS"
fi
[ "$NR" -eq 0 ] || { dire "                $NR remplace(s) par une version plus recente de la bouteille ; l'ancienne est gardee : $HIST"
                     MESSAGE="$MESSAGE ; $NR remplacé(s), l'ancienne version est gardée"; }
[ "$NG" -eq 0 ] || { dire "                $NG plus recent(s) cote Cidre : garde(s) tel(s) quel(s)"
                     [ "$ETAT" != copie ] || MESSAGE="$MESSAGE ; $NG plus récent(s) ici, gardé(s)"; }
[ "$SYNCHRO" != steam_api ] || [ "$ETAT" = steam ] ||
   dire "                (Steam Cloud synchronise par ailleurs ce que le jeu ecrit par l'API de Steam)"
rendre
