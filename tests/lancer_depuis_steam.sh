#!/bin/sh
# Faire fonctionner le bouton « Jouer » de Steam sur un jeu Windows.
#
# A poser dans les options de lancement du jeu, dans Steam :
#
#   /chemin/vers/cidre/tests/lancer_depuis_steam.sh %command%
#
# Steam remplace %command% par l'executable du jeu et ses arguments, et nous
# transmet son environnement : SteamAppId, SteamGameId, SteamOverlayGameId, et
# le chemin de son client. On ne simule rien et on ne contourne rien : on prend
# ce que Steam donne et on le presente a la pile, qui relaie vers le vrai
# client Steam de macOS par le pont lsteamclient.
#
# Le faux client n'est la que pour une chose : occuper ActiveProcess\pid dans le
# registre du prefixe, sans quoi SteamAPI_Init attend un client Windows qui
# n'existera jamais. C'est le vrai client natif qui repond derriere.
set -e
R=$(cd "$(dirname "$0")" && cd .. && pwd)

# Hygiene avant lancement : un faux_steam ou un wineserver laisses par une
# session precedente font planter le nouveau lancement des le demarrage
# (access violation precoce, « ca se lance et ca se ferme »). Si AUCUN jeu ne
# tourne mais que des restes trainent, on les retire. On ne touche a rien si un
# jeu est deja en cours.
if ! pgrep -f '[v]ermintide2.exe' >/dev/null 2>&1; then
   pkill -9 -f '[c]:\\faux_steam.exe' 2>/dev/null || true
   pkill -9 -f 'wine11-arm64/bin/wineserver' 2>/dev/null || true
   sleep 1
fi
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}

# Profil du jeu : options de lancement par appid, en donnees. Reglages livres
# dans outil-steam/profils.toml, surcharges par l'utilisateur (ou Verger) dans
# ~/Library/Application Support/Cidre/profils.toml. cf. tests/profil_cidre.sh.
# Un jeu hors Steam n'a pas d'appid : `cidre play` donne son id dans CIDRE_JEU.
JEU=${CIDRE_JEU:-${SteamAppId:-}}
PROFIL=$(sh "$R/tests/profil_cidre.sh" "$JEU" 2>/dev/null || true)
# Une option : l'environnement explicite (0/1) garde la main, sinon le profil.
profil() { printf '%s\n' "$PROFIL" | sed -n "s/^$1=//p" | head -1; }
opt() { # <cle du profil> <variable d'environnement>
   eval "v=\${$2:-}"
   case $v in 1) echo true; return ;; 0) echo false; return ;; esac
   profil "$1"
}
dxvk_config() { export DXVK_CONFIG="${DXVK_CONFIG:+$DXVK_CONFIG;}$1"; }

# Langue du jeu. langue = "auto" (defaut) ne force rien : Wine annonce la langue
# de macOS, le pont Steam relaie celle du client. Sinon un code a deux lettres
# (ou CIDRE_LANGUE=fr), applique par deux voies -- un jeu choisit sa langue par
# l'une ou l'autre :
#   - la locale Windows : Wine la tire de LC_ALL / LANG, poses ici ;
#   - un fichier de reglages propre au jeu : table outil-steam/langues.conf,
#     ecrit plus bas, juste avant le lancement.
# La troisieme voie, l'API Steam (GetCurrentGameLanguage), n'est pas forcee : le
# pont relaie la langue reglee dans Steam, qui se change dans Steam.
LANGUE=${CIDRE_LANGUE:-$(profil langue)}
case $LANGUE in
   fr) LOCALE=fr_FR ;; en) LOCALE=en_US ;; de) LOCALE=de_DE ;; es) LOCALE=es_ES ;;
   it) LOCALE=it_IT ;; pt) LOCALE=pt_BR ;; ru) LOCALE=ru_RU ;; pl) LOCALE=pl_PL ;;
   ja) LOCALE=ja_JP ;; ko) LOCALE=ko_KR ;; zh) LOCALE=zh_CN ;;
   *)  LANGUE=auto; LOCALE= ;;
esac
[ -n "$LOCALE" ] && export LC_ALL="$LOCALE.UTF-8" LANG="$LOCALE.UTF-8"

# Ordonnancement memoire FEX. L'emulation TSO (defaut, pour la correction) taxe
# chaque acces memoire sensible a l'ordre : mesure sur micro-banc = jusqu'a 3,7x
# sur du code a fort trafic memoire. tso = false (ou CIDRE_TSO=0) la desactive
# -> gros gain CPU, au prix d'un risque de course sur du code lock-free qui
# compte sur l'ordre fort du x86. Opt-in, par jeu. Defaut : inchange.
case $(opt tso CIDRE_TSO) in
   false) export FEX_TSOENABLED=0 ;;
   true)  [ -n "${CIDRE_TSO:-}" ] && export FEX_TSOENABLED=1 ;;
esac

# HUD fps/GPU a la demande : hud = true (ou CIDRE_HUD=1) -> compteur fps + charge
# GPU a l'ecran (pratique pour regler les options graphiques en voyant l'effet).
if [ "$(opt hud CIDRE_HUD)" = true ]; then
   [ -z "${DXVK_HUD:-}" ] && export DXVK_HUD=fps,gpuload,drawcalls,submissions,pipelines,frametimes
   export MTL_HUD_ENABLED=1   # HUD Metal d'Apple : GPU-ms reel par frame
fi

# Presentation / vsync. En FIFO strict (vsync on), une frame qui rate le vblank
# 60 Hz fait chuter a 40/30 (pas 59) -- mesure DREDGE : 40 fps vsync on vs 69 off.
# vsync = false (ou CIDRE_VSYNC=0) force syncInterval=0 cote DXVK (pas de
# penalite vblank ; tearing possible). On l'ajoute au DXVK_CONFIG sans ecraser
# l'existant.
if [ "$(opt vsync CIDRE_VSYNC)" = false ]; then
   case ";${DXVK_CONFIG:-};" in
      *syncInterval*) : ;;
      *) dxvk_config "dxgi.syncInterval=0;d3d11.syncInterval=0" ;;
   esac
fi

# DXVK async (build gplasync) : compile les pipelines en fond au lieu de bloquer
# le rendu -> tue le stutter de traversee. fils_compilation borne les fils
# compilateurs (0 = defaut DXVK, tous les coeurs).
[ "$(opt async CIDRE_ASYNC)" = true ] && export DXVK_ASYNC=1
FILS=${CIDRE_FILS_COMPILATION:-$(profil fils_compilation)}
case $FILS in ''|0|*[!0-9]*) : ;; *) dxvk_config "dxvk.numCompilerThreads=$FILS" ;; esac

# LuaJIT veut la fenetre basse 64 bits (sinon plantage au boot, ex. Vermintide 2).
[ "$(opt luajit CIDRE_LUAJIT)" = true ] && export PROTON_OUVERT_LUAJIT=1
JOURNAL=${PROTON_OUVERT_JOURNAL:-$R/build/logs/steam-${JEU:-inconnu}.log}
mkdir -p "$(dirname "$JOURNAL")"

[ $# -ge 1 ] || { echo "usage : a mettre dans les options de lancement Steam, suivi de %command%" >&2; exit 2; }

# Steam donne un chemin POSIX ; la pile veut un chemin vu de Windows. Tout ce
# qui est hors du disque C: du prefixe est accessible par Z:.
EXE=$1; shift
case $EXE in
   /*) DOSSIER=$(dirname "$EXE"); PROG=$(basename "$EXE") ;;
   *)  DOSSIER=$(pwd);            PROG=$EXE ;;
esac

{
   echo "=== $(date '+%F %T')  appid=${SteamAppId:-?}  jeu=$PROG"
   echo "    dossier : $DOSSIER"
   echo "    args    : $*"
   echo "    profil  : $(echo $PROFIL)"
} >>"$JOURNAL"

# Ce que Steam nous donne n'est pas forcement un binaire Windows : un jeu peut
# avoir une version macOS native, et l'option de lancement peut etre posee sur
# tous les jeux sans distinction. Si ce n'est pas un PE, on s'efface et on lance
# tel quel -- le script doit etre inoffensif la ou il n'a rien a faire.
if [ "$(head -c 2 "$DOSSIER/$PROG" 2>/dev/null)" != "MZ" ]; then
   echo "    pas un binaire Windows : lance tel quel, sans la pile" >>"$JOURNAL"
   cd "$DOSSIER"
   exec "./$PROG" "$@"
fi

# Le client de service : un seul a la fois, reutilise s'il tourne deja.
if ! pgrep -f 'c:\\faux_steam.exe' >/dev/null 2>&1; then
   WINEDEBUG=-all sh "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >>"$JOURNAL" 2>&1 &
   i=0
   while [ $i -lt 60 ] && ! grep -q "inscrit" "$JOURNAL" 2>/dev/null; do sleep 1; i=$((i + 1)); done
fi

# Certains jeux font lancer par Steam un « lanceur » que la pile ne sait pas
# faire tourner -- un binaire .NET, par exemple. outil-steam/jeux.conf note
# alors l'executable que ce lanceur aurait demarre. Une ligne de donnees, pas
# une exception dans le code.
TABLE=$R/outil-steam/jeux.conf
if [ -n "${SteamAppId:-}" ] && [ -f "$TABLE" ]; then
   CIBLE=$(awk -v a="$SteamAppId" '$1==a {print $2; exit}' "$TABLE")
   if [ -n "$CIBLE" ]; then
      RACINE=$DOSSIER
      # Le chemin de la table est relatif au dossier du jeu, pas a celui de
      # l'executable que Steam a nomme : on remonte jusqu'a le trouver.
      while [ ! -f "$RACINE/$CIBLE" ] && [ "$RACINE" != "/" ]; do RACINE=$(dirname "$RACINE"); done
      if [ -f "$RACINE/$CIBLE" ]; then
         echo "    table  : $PROG remplace par $CIBLE" >>"$JOURNAL"
         # Le repertoire courant reste la RACINE du jeu, pas celui de
         # l'executable : c'est la que vivent ses donnees. Le lancer depuis
         # binaries/ faisait echouer Vermintide 2 avant meme qu'il ouvre son
         # journal -- symptome trompeur, puisqu'il plante de toute facon plus
         # loin (§284).
         DOSSIER=$RACINE; PROG=$CIBLE
         set --
      else
         echo "    table  : $CIBLE introuvable, on garde $PROG" >>"$JOURNAL"
      fi
   fi
fi

# Arguments propres au profil. A poser APRES la table des lanceurs, qui remet les
# arguments a zero quand elle remplace l'executable.
#   eac_untrusted : EAC online est un mur -> realm « Modded » via -eac-untrusted
#     (voir NOTES EAC).
if [ "$(opt eac_untrusted CIDRE_EAC_UNTRUSTED)" = true ]; then
   set -- "$@" -eac-untrusted
   echo "    profil : +-eac-untrusted" >>"$JOURNAL"
fi

# Restauration des sauvegardes depuis le dossier synchronise (iCloud), si plus
# recentes (ex. jouees sur une autre machine). Non destructif, non bloquant.
# Steam Cloud ne peut pas le faire pour un jeu Windows sur macOS (roots non
# resolus) ; on replique sa logique. cf. tests/sync_saves_steam.sh.
if [ -n "${SteamAppId:-}" ]; then
   sh "$R/tests/sync_saves_steam.sh" "$SteamAppId" restore >>"$JOURNAL" 2>&1 || true
fi

cd "$DOSSIER"
# Langue dans le fichier de reglages du jeu (outil-steam/langues.conf). Apres la
# restauration des sauvegardes, qui peut ramener ce meme fichier d'iCloud.
[ "$LANGUE" = auto ] || sh "$R/tests/langue_jeu.sh" "$JEU" "$LANGUE" >>"$JOURNAL" 2>&1 || true
# On ne fait PLUS exec : on attend la fin du jeu pour sauvegarder apres coup.
sh "$R/tests/etape2_pile_arm64ec.sh" "$PROG" "$@" >>"$JOURNAL" 2>&1
RC=$?

# Sauvegarde vers le dossier synchronise apres la sortie du jeu (meme en cas de
# crash : on sauve l'etat tel quel). Non bloquant.
if [ -n "${SteamAppId:-}" ]; then
   sh "$R/tests/sync_saves_steam.sh" "$SteamAppId" backup >>"$JOURNAL" 2>&1 || true
fi
exit $RC
