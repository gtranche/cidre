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
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
if ! pgrep -f '[v]ermintide2.exe' >/dev/null 2>&1; then
   pkill -9 -f '[c]:\\faux_steam.exe' 2>/dev/null || true
   # Le wineserver de CE prefixe, et lui seul : « wineserver -k » le retrouve
   # par le verrou du prefixe, lui demande de s'arreter (il emporte ses
   # processus) et ne le tue qu'au bout de 10 s. Pas de pkill sur la ligne de
   # commande : Wine lance son serveur par .../lib/wine/../../bin/wineserver,
   # que le motif 'wine11-arm64/bin/wineserver' n'a jamais attrape, et un motif
   # plus large tuerait aussi le serveur d'un autre prefixe.
   "$R/wine/wine11-arm64/bin/wineserver" -k 2>/dev/null || true
   sleep 1
fi

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

# Cache de pipelines Metal (KosmicKrisp) : les shaders compiles (MSL -> binaire
# Metal) sont ranges par jeu dans une archive MTL4 et relus au lancement suivant,
# pour ne compiler qu'une fois. Active par defaut des qu'on a un identifiant de
# jeu ; CIDRE_PIPELINE_CACHE=0 (ou cache_pipelines=0 dans le profil) le coupe.
if [ -n "$JEU" ] && [ "$(opt cache_pipelines CIDRE_PIPELINE_CACHE)" != false ]; then
   export MESA_KK_PIPELINE_CACHE="${MESA_KK_PIPELINE_CACHE:-$HOME/Library/Application Support/Cidre/vkd3d-cache/$JEU}"
fi

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

# Overlay Steam (Maj+Tab, amis, succes, notifications en jeu). Steam l'affiche
# dans un jeu Mac natif en injectant gameoverlayrenderer.dylib dans le processus ;
# il ne le fait pas pour nous (les variables DYLD_* ne survivent pas a /bin/sh).
# overlay = true (defaut ; CIDRE_OVERLAY=0 pour s'en passer) injecte la meme
# bibliotheque dans le Wine du jeu -- de lui seul, pas du faux client -- et fait
# presenter KosmicKrisp par le chemin Metal qu'elle sait accrocher (cf.
# etape2_pile_arm64ec.sh, NOTES §312). Sans effet pour un jeu hors Steam (pas
# d'appid : l'overlay n'aurait rien a quoi se rattacher) ou sans client Steam.
OVERLAY=
if [ "$(opt overlay CIDRE_OVERLAY)" = true ] && [ -n "${SteamAppId:-}" ]; then
   OVERLAY="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/gameoverlayrenderer.dylib"
   [ -f "$OVERLAY" ] || OVERLAY=
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

# Renderer D3D12. Defaut : d3d12 builtin de Wine (etape2 : CIDRE_D3D12=b), qui
# retombe proprement en D3D11/DXVK si le jeu exige une interface D3D12 recente
# (cas PEAK : il exige le Feature Level 12.1, non supporte par KosmicKrisp -> DX11).
# dx12 = true (ou CIDRE_DX12=1) : installe vkd3d-proton arm64ec en system32 et
# force le natif (=n) pour du vrai D3D12 (FL 12.0). FL 12.1 (conservative raster,
# absente de Metal) reste hors de portee -- chantier KosmicKrisp.
if [ "$(opt dx12 CIDRE_DX12)" = true ]; then
   P12="$WINEPREFIX/drive_c/windows/system32"
   for d in d3d12core d3d12; do
      for cand in "$R/vkd3d/$d.dll" "$R/build/vkd3d-winarm64ec/libs/$d/$d.dll"; do
         [ -f "$cand" ] || continue
         cmp -s "$cand" "$P12/$d.dll" || cp "$cand" "$P12/$d.dll"
         break
      done
   done
   export CIDRE_D3D12=n
   # Annonce opt-in des capacites FL 12.x a KosmicKrisp (sparse/tiled tier 2, ROV,
   # conservative raster) pour que vkd3d-proton atteigne le Feature Level 12.1.
   # Best-effort : si le jeu cree vraiment une ressource tiled, ca peut echouer.
   export MESA_KK_EXPERIMENTAL="${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod},fl12"
fi

# Relachement cible des barrieres de cloture d'encodeur KosmicKrisp vers les
# vraies stages (au lieu de ALL->ALL) : laisse les passes GPU se recouvrir, gain
# en scene chargee (GPU-bound). Valide sur VT2. Un environnement explicite
# (y compris CIDRE_NARROW_BARRIERS=global pour le mode debug) garde la main.
if [ -z "${CIDRE_NARROW_BARRIERS:-}" ] && [ "$(profil narrow_barriers)" = true ]; then
   export CIDRE_NARROW_BARRIERS=1
fi
FILS=${CIDRE_FILS_COMPILATION:-$(profil fils_compilation)}
case $FILS in ''|0|*[!0-9]*) : ;; *) dxvk_config "dxvk.numCompilerThreads=$FILS" ;; esac

# LuaJIT veut la fenetre basse 64 bits (sinon plantage au boot, ex. Vermintide 2).
[ "$(opt luajit CIDRE_LUAJIT)" = true ] && export PROTON_OUVERT_LUAJIT=1

# Vrai plein ecran macOS (Space) automatique. winemac.drv promeut la fenetre de
# jeu qui couvre l'ecran vers un Space natif (equivalent Ctrl+Cmd+F) : couvre
# l'encoche du MacBook, laisse macOS scaler une resolution de jeu plus basse pour
# remplir l'ecran, et met l'app au premier plan en plein ecran -- condition du
# Game Mode. Generique tous jeux ; plein_ecran = false pour un jeu recalcitrant.
[ "$(opt plein_ecran CIDRE_PLEIN_ECRAN)" = true ] && export CIDRE_FULLSCREEN_SPACE=1

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
   WINEDEBUG=-all CIDRE_OVERLAY_DYLIB= sh "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >>"$JOURNAL" 2>&1 &
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
if [ -n "$JEU" ]; then
   sh "$R/tests/sync_saves_steam.sh" "$JEU" restore >>"$JOURNAL" 2>&1 || true
fi

# macOS Game Mode : priorise CPU/GPU pour le jeu, reduit la latence manette/audio.
# Il s'active deja seul quand une app categorie « jeu » (nos cles Info.plist
# embarquees dans le binaire Wine) est au premier plan en vrai plein ecran -- d'ou
# le Space automatique ci-dessus. gamemode = true le FORCE en plus via
# gamepolicyctl (sans sudo) et le rend a « auto » a la sortie (trap), pour ne pas
# laisser le reglage colle apres le jeu. Si gamepolicyctl est absent, on ne force
# rien : l'activation automatique en plein ecran suffit.
# gamepolicyctl n'est PAS dans le PATH ni livre avec les Command Line Tools : il
# n'existe que sous Xcode.app (.../Developer/usr/bin). On le cherche donc la, en
# plus du PATH et du developer dir actif.
GAMEPOLICYCTL=$(command -v gamepolicyctl 2>/dev/null || true)
if [ -z "$GAMEPOLICYCTL" ]; then
   for c in "$(xcode-select -p 2>/dev/null)/usr/bin/gamepolicyctl" \
            /Applications/Xcode*.app/Contents/Developer/usr/bin/gamepolicyctl; do
      [ -x "$c" ] && GAMEPOLICYCTL=$c && break
   done
fi
if [ "$(opt gamemode CIDRE_GAME_MODE)" = true ] && [ -n "$GAMEPOLICYCTL" ]; then
   if "$GAMEPOLICYCTL" game-mode set on >>"$JOURNAL" 2>&1; then
      echo "    game mode : force on (rendu a auto a la sortie)" >>"$JOURNAL"
      trap '"$GAMEPOLICYCTL" game-mode set auto >>"$JOURNAL" 2>&1 || true' EXIT INT TERM
   else
      echo "    game mode : gamepolicyctl a echoue, on laisse l'auto" >>"$JOURNAL"
   fi
fi

cd "$DOSSIER"
# Langue dans le fichier de reglages du jeu (outil-steam/langues.conf). Apres la
# restauration des sauvegardes, qui peut ramener ce meme fichier d'iCloud.
[ "$LANGUE" = auto ] || sh "$R/tests/langue_jeu.sh" "$JEU" "$LANGUE" >>"$JOURNAL" 2>&1 || true
# On ne fait PLUS exec : on attend la fin du jeu pour sauvegarder apres coup.
CIDRE_OVERLAY_DYLIB=$OVERLAY sh "$R/tests/etape2_pile_arm64ec.sh" "$PROG" "$@" >>"$JOURNAL" 2>&1
RC=$?

# Sauvegarde vers le dossier synchronise apres la sortie du jeu (meme en cas de
# crash : on sauve l'etat tel quel). Non bloquant.
if [ -n "$JEU" ]; then
   sh "$R/tests/sync_saves_steam.sh" "$JEU" backup >>"$JOURNAL" 2>&1 || true
fi
exit $RC
