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
# Tout le corps est entre accolades, ferme par `exit` : le shell lit ainsi le
# fichier ENTIER avant d'executer quoi que ce soit, et n'y revient jamais. Sans
# cela, il lit au fil de l'execution : un fichier modifie pendant qu'un jeu
# tourne (mise a jour, edition) est repris a l'ancien decalage, au milieu d'une
# autre commande -- le 2026-10-13, `cidre play` a ainsi fini dans la
# desinstallation et efface le jeu. tests/tester_profils.sh verifie l'enveloppe.
{
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

# Prefixe a jour du runtime : un runtime pose sans `cidre setup` (reconstruction
# de Wine sur la machine de dev) peut apporter une DLL que le prefixe n'a jamais
# inscrite -- winegstreamer le 2026-10-16 : toute video .mp4 de Media Foundation
# echouait et Sherlock Holmes Chapter One ne quittait plus son ecran de
# chargement. Rien a faire (quelques ms) tant que la liste des DLL n'a pas bouge.
sh "$R/tests/prefixe_a_jour.sh"

# Profil du jeu : options de lancement par appid, en donnees. Reglages generaux
# livres dans outil-steam/profils.toml ([defaut]), fiche du jeu dans la base de
# profils (profils/<appid>.toml, [cidre]), surcharges par l'utilisateur (ou
# Verger) dans ~/Library/Application Support/Cidre/profils.toml.
# cf. tests/profil_cidre.sh et profils/README.md.
# Un jeu hors Steam n'a pas d'appid : `cidre play` donne son id dans CIDRE_JEU.
JEU=${CIDRE_JEU:-${SteamAppId:-}}
PROFIL=$(sh "$R/tests/profil_cidre.sh" "$JEU" 2>/dev/null || true)
# Une option : l'environnement explicite garde la main (0/1 pour un booleen,
# la valeur telle quelle pour une option a choix, ex. CIDRE_D3D11=dxmt), sinon
# le profil.
profil() { printf '%s\n' "$PROFIL" | sed -n "s/^$1=//p" | head -1; }
opt() { # <cle du profil> <variable d'environnement>
   eval "v=\${$2:-}"
   case $v in 1) echo true; return ;; 0) echo false; return ;; '') ;; *) echo "$v"; return ;; esac
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

# Langue du jeu. langue = "auto" (defaut) : la langue de macOS, sinon l'anglais ;
# un code a deux lettres (ou CIDRE_LANGUE=fr) l'impose (tests/langue_cidre.sh).
# Un jeu choisit sa langue par l'une de trois voies :
#   - la locale Windows : Wine la tire de LC_ALL / LANG. On ne la laisse pas a
#     l'environnement -- Verger herite LANG=C.UTF-8 et Steam lance ses jeux sous
#     LC_ALL=en_US.UTF-8 : Wine annoncait en-US a tous les jeux (Sherlock Holmes
#     Chapter One en anglais). CIDRE_LOCALE la donne au seul Wine
#     (etape2_pile_arm64ec.sh) : ce script et ses outils restent en locale C
#     (sous fr_FR, le printf du shell refuse « 1.5 ») ;
#   - un fichier de reglages propre au jeu : table outil-steam/langues.conf,
#     ecrit plus bas, juste avant le lancement ;
#   - l'API Steam (GetCurrentGameLanguage) : le pont relaie la langue que le
#     client Steam donne au jeu, comme Steam sous Windows ; elle se change dans Steam.
# Le choix fait dans le jeu reste le sien : il l'enregistre dans ses reglages,
# qu'il relit avant la locale.
LANGUE=${CIDRE_LANGUE:-$(profil langue)}
case $LANGUE in fr|en|de|es|it|pt|ru|pl|ja|ko|zh) ;; *) LANGUE=auto ;; esac
LANGUES=$(sh "$R/tests/langue_cidre.sh" "$LANGUE" 2>/dev/null || true)
langue() { printf '%s\n' "$LANGUES" | sed -n "s/^$1=//p" | head -1; }
LANGUE_CODE=$(langue code)
[ -z "$(langue locale)" ] || export CIDRE_LOCALE="$(langue locale)"

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
   # CIDRE_VKD3D_DIR=<dossier> (essais) : un vkd3d-proton construit a part (ses
   # d3d12.dll et d3d12core.dll), pris avant celui du runtime pour ce lancement --
   # par exemple un build -Denable_profiling=true pour VKD3D_TIMESTAMP_PROFILE (temps
   # GPU par PSO). Le lancement suivant sans la variable remet celui du runtime.
   for d in d3d12core d3d12; do
      for cand in ${CIDRE_VKD3D_DIR:+"$CIDRE_VKD3D_DIR/$d.dll"} "$R/vkd3d/$d.dll" "$R/build/vkd3d-winarm64ec/libs/$d/$d.dll"; do
         [ -f "$cand" ] || continue
         cmp -s "$cand" "$P12/$d.dll" || cp "$cand" "$P12/$d.dll"
         break
      done
   done
   export CIDRE_D3D12=n
   # Annonce opt-in des capacites FL 12.x a KosmicKrisp (sparse/tiled tier 2, ROV,
   # conservative raster) pour que vkd3d-proton atteigne le Feature Level 12.1.
   # Best-effort : si le jeu cree vraiment une ressource tiled, ca peut echouer.
   # Sans custom_border en D3D12 : l'emulation des couleurs de bord ajoute a CHAQUE
   # lecture de texture une seconde lecture conditionnelle (banc : x1,5 sur un filtre
   # de 32 lectures ; Little Nightmares 12 -> 16 fps). vkd3d-proton s'en passe : les
   # bords standard restent exacts, un bord arbitraire devient noir transparent.
   export MESA_KK_EXPERIMENTAL="${MESA_KK_EXPERIMENTAL:-image_view_min_lod},fl12"
   # KosmicKrisp 0135 (min/max a zero signe teste en entier, exact) et 0136 (lecture
   # de texture d'un descripteur nul sans branche : Metal rend 0) : les branchements
   # par lecture empechent Metal de lancer les lectures en parallele. Banc : filtre de
   # 32 lectures 2,48 -> 0,78 ms. =0 retire la variable (le pilote ne regarde que sa
   # presence).
   case ${CIDRE_MINMAX_ZERO_ENTIER:-1} in
      0) unset CIDRE_MINMAX_ZERO_ENTIER ;;
      *) export CIDRE_MINMAX_ZERO_ENTIER=1 ;;
   esac
   case ${CIDRE_TEXTURES_NULLES_SANS_BRANCHE:-1} in
      0) unset CIDRE_TEXTURES_NULLES_SANS_BRANCHE ;;
      *) export CIDRE_TEXTURES_NULLES_SANS_BRANCHE=1 ;;
   esac
   # Shader Model 6.6 (Unreal 5 en D3D12, sm66 = true) : vkd3d-proton annonce SM 6.2+
   # malgre des denormaux fp32 non reglables (0142), KosmicKrisp les derivees dans les
   # nuanceurs de calcul (0143) et, sur M2 et suivants seulement (detection a
   # l'execution), les atomiques 64 bits min/max de Metal (0144). Sur M1, SM 6.5 sans
   # atomiques 64 bits : Unreal 5 y garde son repli.
   if [ "$(opt sm66 CIDRE_SM66)" = true ]; then
      export CIDRE_VKD3D_DENORMAUX_LIBRES=1 CIDRE_DERIVEES_CALCUL=1 CIDRE_ATOMIQUES_64=1
   fi
fi

# Overrides DLL propres au jeu (base de compat, cf. profils.toml). Format Wine
# "a,b=n;c=b" (n=natif, b=builtin, =disable). etape2 les AJOUTE aux overrides par
# defaut (dxgi/d3d11/d3d12). De quoi forcer une audio, une d3dx ou une dll moteur
# par jeu, a la facon des recettes CrossOver, sans toucher au code.
DLLOV=${CIDRE_DLL_OVERRIDES:-$(profil dll_overrides)}
[ -n "$DLLOV" ] && export CIDRE_DLL_OVERRIDES="$DLLOV"

# Relachement cible des barrieres de cloture d'encodeur KosmicKrisp vers les
# vraies stages (au lieu de ALL->ALL) : laisse les passes GPU se recouvrir, gain
# en scene chargee (GPU-bound). Valide sur VT2. Un environnement explicite
# (y compris CIDRE_NARROW_BARRIERS=global pour le mode debug) garde la main.
# En vrai D3D12 (dx12), le mode « sur » (correctif 0125) : le relachement
# ignore l'etage VERTEX du cote consommateur, or vkd3d-proton le demande pour
# NON_PIXEL_SHADER_RESOURCE (lecture d'une cible rendue au sommet). Banc
# tests/bench_barriere_vertex.c, 2026-10-14 : mode cible 597 fautes sur 600
# quand la barriere demande VERTEX|FRAGMENT ou ALL_COMMANDS, mode « sur » 0 ;
# meme gain (-9 % de temps mur, bench_barriere_chaine.c) quand elle ne demande
# que FRAGMENT. Le mode cible reste celui de DXVK (VT2, valide en jeu).
if [ -z "${CIDRE_NARROW_BARRIERS:-}" ] && [ "$(profil narrow_barriers)" = true ]; then
   if [ "$(opt dx12 CIDRE_DX12)" = true ]; then
      export CIDRE_NARROW_BARRIERS=sur
   else
      export CIDRE_NARROW_BARRIERS=1
   fi
fi
# Garde d'index de KosmicKrisp (ses contournements 12 et 13) : faute de pouvoir
# se fier a Metal pour les lectures hors limites d'un tampon d'index, le pilote
# « deroule » chaque dessin indexe indirect par une passe de calcul -- ce qui
# coupe la passe de rendu en cours, a chaque dessin. Un moteur qui dessine tout
# en indirect (Unreal Engine 5) s'y effondre : Clair Obscur: Expedition 33
# passait de 0,6 a 15 images par seconde en la coupant. Sans elle, un dessin
# qui lirait au-dela de son tampon d'index n'a plus de filet : a n'oter que
# pour un jeu ou cela a ete essaye. Un environnement explicite garde la main.
if [ -z "${MESA_KK_DISABLE_WORKAROUNDS:-}" ] && [ "$(profil garde_index)" = false ]; then
   export MESA_KK_DISABLE_WORKAROUNDS=12,13
fi
# Pipelines Metal compiles hors du verrou du device (correctif 0130) : KosmicKrisp
# compile le pipeline Metal au premier dessin, et le faisait sous un verrou global ;
# les fils qui enregistrent en parallele (Job.Worker d'Unity en D3D12) s'y
# attendaient tous. PEAK en D3D12, meme parcours, 2026-10-14 : trous de plus de
# 250 ms 3,0 -> 0,9 par minute ; banc tests/bench_variantes_paralleles.c, 8 fils :
# 466 -> 102 ms, un fil neutre. Pour tous les jeux ; CIDRE_COMPILE_HORS_VERROU=0
# revient a l'ancien comportement (le pilote ne regarde que la presence de la
# variable : on la retire).
case ${CIDRE_COMPILE_HORS_VERROU:-1} in
   0) unset CIDRE_COMPILE_HORS_VERROU ;;
   *) export CIDRE_COMPILE_HORS_VERROU=1 ;;
esac
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

# Plein ecran exclusif sans changement de mode. Un jeu qui demande un mode
# d'ecran (ChangeDisplaySettings, DXGI SetFullscreenState) le voit applique,
# mais l'ecran reste a sa resolution : win32u emule le mode (EmulateModeset de
# Wine, pose ici par CIDRE_EMULATE_MODESET), la fenetre couvre l'ecran et
# l'image est mise a l'echelle et centree, comme en fenetre plein ecran. Le
# vrai changement de mode passait par le filtre de l'ecran (image floue) et
# par un mode sans Retina. Avec plein_ecran, le bureau presente au jeu est
# l'espace plein ecran lui-meme (sous la barre de menus d'un ecran a encoche).
# mode_emule = false rend l'ancien comportement a un jeu qui l'exigerait.
if [ -z "${CIDRE_EMULATE_MODESET:-}" ] && [ "$(opt mode_emule CIDRE_MODE_EMULE)" = true ]; then
   export CIDRE_EMULATE_MODESET=1
fi
# En mode emule, l'EDID vu par le jeu annonce la taille de l'espace (winemac,
# 0141) et non la definition native de la dalle : un jeu qui rend a la
# definition « native » du moniteur (Unreal) rendait sinon 4 fois plus de
# pixels qu'il n'en montre (Little Nightmares 12 -> 75 fps a 1728x1084).
# retina = true garde l'EDID de la dalle, pour qui veut ce rendu en 2x.
[ "$(opt retina CIDRE_RETINA)" = true ] && export CIDRE_RETINA=1

# Touches a leur place pour un clavier non QWERTY (winemac, 0151). Un jeu qui
# lit les codes virtuels (VK_W...) attend ses touches aux positions QWERTY ;
# Wine, comme Windows, les distribue selon les caracteres, et un joueur en
# AZERTY reassignait A/Q, Z/W, M... dans chaque jeu. clavier = "positions" :
# chaque touche de caracteres prend le code virtuel de sa position QWERTY (la
# touche Z de l'AZERTY est le W du jeu, la touche M son « ; », la touche 1 son
# 1). "systeme" (defaut) : le comportement de Wine. Le texte tape (discussion,
# noms) reste celui de la disposition macOS. Un jeu deja reassigne a la main
# est a remettre a ses touches par defaut. CIDRE_CLAVIER=positions pour un essai.
case $(opt clavier CIDRE_CLAVIER) in
   positions|true) export CIDRE_CLAVIER=positions ;;
   *)              unset CIDRE_CLAVIER ;;
esac

JOURNAL=${PROTON_OUVERT_JOURNAL:-$R/build/logs/steam-${JEU:-inconnu}.log}
mkdir -p "$(dirname "$JOURNAL")"
# Un journal detaille peut peser lourd : au-dela de 30 Mo, on repart d'un
# fichier neuf en gardant le precedent a cote.
if [ "$(stat -f %z "$JOURNAL" 2>/dev/null || echo 0)" -gt 30000000 ]; then mv -f "$JOURNAL" "$JOURNAL.precedent"; fi

[ $# -ge 1 ] || { echo "usage : a mettre dans les options de lancement Steam, suivi de %command%" >&2; exit 2; }

# Steam donne un chemin POSIX ; la pile veut un chemin vu de Windows. Tout ce
# qui est hors du disque C: du prefixe est accessible par Z:.
EXE=$1; shift
case $EXE in
   /*) DOSSIER=$(dirname "$EXE"); PROG=$(basename "$EXE") ;;
   *)  DOSSIER=$(pwd);            PROG=$EXE ;;
esac

DEBUT_EPOCH=$(date +%s)
{
   echo "=== $(date '+%F %T')  appid=${SteamAppId:-?}  jeu=$PROG"
   echo "    dossier : $DOSSIER"
   echo "    args    : $*"
   echo "    profil  : $(echo $PROFIL)"
   # Une fiche peut porter des variantes par machine (blocs [[machine]] de
   # profils/README.md, deja fondus dans le profil ci-dessus) : dire lesquelles jouent.
   VARIANTES=$(sh "$R/tests/fiche_profil.sh" variantes "$JEU" 2>/dev/null | tr '\n' ';' | sed 's/;$//; s/;/ ; /g')
   [ -z "$VARIANTES" ] || echo "    fiche   : variante pour cette machine (si $VARIANTES)"
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

# Version de Windows vue par le jeu : windows_version = "win7", "winxp"... quand
# il l'exige (CIDRE_WINDOWS_VERSION=win7 pour un essai) ; win10 sans l'option.
# Les jeux partagent le prefixe : elle est donc reglee a CHAQUE lancement, pour
# le jeu qu'on lance -- la valeur HKCU\Software\Wine\Version, que Wine lit avant
# la version du prefixe et que tous les processus du jeu voient (son lanceur,
# ce qu'il demarre). Sans l'option elle est retiree : un jeu ne laisse rien au
# suivant, et une version restee collee au prefixe (winecfg -v) est remise a
# Windows 10. Ecrit dans le registre sans demarrer Wine, donc ICI, avant le
# client de service : un wineserver en vie recrirait le registre a sa sortie.
# Une valeur inconnue est dite, et le jeu part en win10. Jamais bloquant.
# Cf. tests/version_windows.sh.
WINVER=${CIDRE_WINDOWS_VERSION:-$(profil windows_version)}
sh "$R/tests/version_windows.sh" poser "$WINVER" 2>&1 | tee -a "$JOURNAL" || true

# Rendu Direct3D 11 : d3d11 = "dxmt" (defaut depuis la 1.5.8) ou "dxvk" (CIDRE_D3D11=dxvk, repli).
# DXVK est un natif pose en system32 (dxgi,d3d11=n, cf. etape2). DXMT (D3D11 ->
# Metal en un saut, x3 a x4 mesure sur Expedition 33) est bati comme des
# builtins Wine : ses d3d11/dxgi/d3d10core/winemetal.dll vont dans
# lib/wine/aarch64-windows, son unixlib winemetal.so dans aarch64-unix, et ils
# se chargent avec =b -- ajoute apres le =n d'etape2, il gagne. Les builtins
# Wine d'origine sont sauvegardes avant d'etre remplaces, et remis des qu'un
# jeu se lance en dxvk : l'etat pose suit toujours l'option du jeu qu'on lance,
# meme quand deux jeux s'enchainent avec des options differentes. Les binaires
# viennent du runtime livre ($R/dxmt) ; sur la machine de dev, a defaut, de
# src/dxmt/build. Remplacement par mv, jamais cp par-dessus : ecraser une
# bibliotheque encore mappee par un jeu en cours tue ce jeu.
# Un jeu 32 bits (PE32 i386 : Dead Cells) ne charge rien de aarch64-windows : il
# lui faut la variante i386 de DXMT ($R/dxmt/i386, quatre DLL, la meme
# winemetal.so servant les deux largeurs par ses thunks wow64), posee dans
# lib/wine/i386-windows. Sans elle, le =b l'envoie sur le d3d11 builtin de Wine
# (wined3d), qui rend DXGI_ERROR_UNSUPPORTED a la creation du device -- le
# « DXError 887A0004 » du 2026-10-13 (tests/sonde_heaps.sh) ; un runtime sans
# DXMT i386 lance donc un jeu 32 bits en dxvk d'emblee.
# CIDRE_DXMT_DIR=<dossier> (essais) : un DXMT a la forme de $R/dxmt (cinq
# fichiers, plus i386/), pris avant le runtime livre pour ce lancement.
D3D11=$(opt d3d11 CIDRE_D3D11)
case $D3D11 in dxmt) ;; *) D3D11=dxvk ;; esac
# En vrai D3D12 (dx12), le DXGI est celui de DXVK, compagnon de vkd3d-proton
# (comme sous Proton) : celui de DXMT annonce 0 octet de memoire partagee, et
# Unity, qui voit un adaptateur « integre » en D3D12, refusait le D3D12 de PEAK
# (« Graphics Memory Less Than 3600 », manche du 2026-10-14 ; avec le DXGI de
# DXVK le filtre passe). Le D3D11 eventuel du jeu suit donc DXVK. Un
# CIDRE_D3D11=dxmt explicite garde la main (essais).
if [ "$D3D11" = dxmt ] && [ "$(opt dx12 CIDRE_DX12)" = true ] && [ -z "${CIDRE_D3D11:-}" ]; then
   D3D11=dxvk
   echo "    d3d11 : dxvk (dx12 : DXGI de DXVK pour vkd3d-proton)" >>"$JOURNAL"
fi
# Options DXMT propres au jeu (fiche ou profil : dxmt_config = "d3d11.cle=valeur;..."),
# placees devant DXMT_CONFIG de l'environnement, qui garde donc le dernier mot.
DXMTCFG=$(opt dxmt_config CIDRE_DXMT_CONFIG)
# async = true vaut aussi pour DXMT (d3d11.asyncPipelines) : un dessin dont le
# pipeline compile encore est saute au lieu de geler l'image (objet absent
# quelques images, premier lancement surtout). Une valeur dans dxmt_config ou
# DXMT_CONFIG garde la main.
if [ "$D3D11" = dxmt ] && [ "$(opt async CIDRE_ASYNC)" = true ]; then
   case ";$DXMTCFG;${DXMT_CONFIG:-};" in
      *asyncPipelines*) ;;
      *) DXMTCFG="d3d11.asyncPipelines=True${DXMTCFG:+;$DXMTCFG}" ;;
   esac
fi
if [ "$D3D11" = dxmt ] && [ -n "$DXMTCFG" ]; then
   export DXMT_CONFIG="$DXMTCFG;${DXMT_CONFIG:-}"
   echo "    d3d11 : options DXMT du profil : $DXMTCFG" >>"$JOURNAL"
fi
WINDLL=$R/wine/wine11-arm64/lib/wine/aarch64-windows
WINUNIX=$R/wine/wine11-arm64/lib/wine/aarch64-unix
WINDLL32=$R/wine/wine11-arm64/lib/wine/i386-windows
SYS32=$WINEPREFIX/drive_c/windows/system32
SYSWOW=$WINEPREFIX/drive_c/windows/syswow64
BUILTINS_WINE=$R/wine/.wine-builtin-backup
DXMT_DLLS="d3d11 dxgi d3d10core"
# Un builtin Wine ne contient pas la chaine « dxmt » ; ceux de DXMT, si. (grep
# plutot que strings : sur un Mac sans outils de developpement, strings n'est
# qu'un relais qui propose de les installer.)
est_dxmt() { LC_ALL=C grep -q -a dxmt "$1" 2>/dev/null; }
poser() { # <source> <destination> : copie seulement si different, remplacement atomique
   cmp -s "$1" "$2" && return 0
   cp -p "$1" "$2.cidre-tmp" && mv -f "$2.cidre-tmp" "$2"
}
source_dxmt() { # <fichier> : le runtime livre d'abord, le build de dev a defaut
   case $1 in
      d3d10core.dll) dev=d3d10/$1 ;; winemetal.so) dev=winemetal/unix/$1 ;;
      winemetal.dll) dev=winemetal/$1 ;; *) dev=${1%.dll}/$1 ;;
   esac
   for cand in ${CIDRE_DXMT_DIR:+"$CIDRE_DXMT_DIR/$1"} "$R/dxmt/$1" "$R/src/dxmt/build/src/$dev"; do
      [ -f "$cand" ] && { echo "$cand"; return 0; }
   done
   return 1
}
source_dxmt32() { # <fichier> : la variante i386, memes sources
   case $1 in
      d3d10core.dll) dev=d3d10/$1 ;; winemetal.dll) dev=winemetal/$1 ;; *) dev=${1%.dll}/$1 ;;
   esac
   for cand in ${CIDRE_DXMT_DIR:+"$CIDRE_DXMT_DIR/i386/$1"} "$R/dxmt/i386/$1" "$R/src/dxmt/build-i386/src/$dev"; do
      [ -f "$cand" ] && { echo "$cand"; return 0; }
   done
   return 1
}
est_pe32() { # <exe> : champ Machine de l'en-tete PE = 0x014c (i386)
   pe=$(od -An -t u4 -j 60 -N 4 "$1" 2>/dev/null | tr -d ' ')
   case $pe in ''|*[!0-9]*) return 1 ;; esac
   [ "$(od -An -t x2 -j $((pe + 4)) -N 2 "$1" 2>/dev/null | tr -d ' ')" = 014c ]
}
retirer_dxmt32() { # <raison> : remet les builtins i386 de Wine si DXMT i386 est pose
   for d in $DXMT_DLLS; do
      [ -f "$WINDLL32/$d.dll" ] && est_dxmt "$WINDLL32/$d.dll" || continue
      if [ -f "$BUILTINS_WINE/i386/$d.dll" ]; then
         poser "$BUILTINS_WINE/i386/$d.dll" "$WINDLL32/$d.dll"
         echo "    d3d11 : $1 -> builtin Wine i386 $d.dll remis (DXMT etait pose)" >>"$JOURNAL"
      else
         echo "    d3d11 : $d.dll i386 est celui de DXMT et le builtin Wine n'a pas de sauvegarde : reinstaller le runtime (cidre setup)" >>"$JOURNAL"
      fi
   done
   rm -f "$WINDLL32/winemetal.dll" "$SYSWOW/winemetal.dll"
}
DXMT32=
if [ -d "$WINDLL32" ]; then
   DXMT32=1
   for f in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do
      source_dxmt32 "$f" >/dev/null || { DXMT32=; break; }
   done
fi
if [ "$D3D11" = dxmt ] && [ -z "$DXMT32" ] && est_pe32 "$DOSSIER/$PROG"; then
   echo "    d3d11 : jeu 32 bits et pas de DXMT i386 dans ce runtime (ni $R/dxmt/i386 ni src/dxmt/build-i386) : on reste en dxvk" >>"$JOURNAL"
   D3D11=dxvk
fi
if [ "$D3D11" = dxmt ]; then
   for f in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll winemetal.so; do
      source_dxmt "$f" >/dev/null || {
         echo "    d3d11 : dxmt demande mais $f introuvable (ni $R/dxmt ni src/dxmt/build) : on reste en dxvk" >>"$JOURNAL"
         D3D11=dxvk; break
      }
   done
fi
if [ "$D3D11" = dxmt ]; then
   for d in $DXMT_DLLS; do
      if [ -f "$WINDLL/$d.dll" ] && ! est_dxmt "$WINDLL/$d.dll"; then
         mkdir -p "$BUILTINS_WINE"
         cp -p "$WINDLL/$d.dll" "$BUILTINS_WINE/$d.dll"
      fi
      poser "$(source_dxmt $d.dll)" "$WINDLL/$d.dll"
   done
   poser "$(source_dxmt winemetal.dll)" "$WINDLL/winemetal.dll"
   poser "$(source_dxmt winemetal.so)"  "$WINUNIX/winemetal.so"
   # une copie en system32 pour que le chargeur resolve l'import de d3d11.dll
   [ -d "$SYS32" ] && poser "$(source_dxmt winemetal.dll)" "$SYS32/winemetal.dll"
   # la variante i386, pour un jeu (ou un lanceur de jeu) 32 bits : memes gestes,
   # builtins i386 de Wine gardes a part, winemetal.dll i386 aussi en syswow64
   if [ -n "$DXMT32" ]; then
      for d in $DXMT_DLLS; do
         if [ -f "$WINDLL32/$d.dll" ] && ! est_dxmt "$WINDLL32/$d.dll"; then
            mkdir -p "$BUILTINS_WINE/i386"
            cp -p "$WINDLL32/$d.dll" "$BUILTINS_WINE/i386/$d.dll"
         fi
         poser "$(source_dxmt32 $d.dll)" "$WINDLL32/$d.dll"
      done
      poser "$(source_dxmt32 winemetal.dll)" "$WINDLL32/winemetal.dll"
      [ -d "$SYSWOW" ] && poser "$(source_dxmt32 winemetal.dll)" "$SYSWOW/winemetal.dll"
   else
      # pas de variante i386 dans ce DXMT : celle d'un autre (essai, runtime
      # precedent) ne doit pas rester a cote d'une winemetal.so qui n'est pas la sienne
      retirer_dxmt32 "dxmt sans i386"
   fi
   DXMT_OV="dxgi,d3d11,d3d10core,winemetal=b"
   case ";${CIDRE_DLL_OVERRIDES:-};" in
      *";$DXMT_OV;"*) : ;;
      *) export CIDRE_DLL_OVERRIDES="${CIDRE_DLL_OVERRIDES:+$CIDRE_DLL_OVERRIDES;}$DXMT_OV" ;;
   esac
   echo "    d3d11 : dxmt pose depuis $(dirname "$(source_dxmt d3d11.dll)")${DXMT32:+, i386 compris} (builtins Wine gardes dans $BUILTINS_WINE)" >>"$JOURNAL"
   # L'overlay Steam (gameoverlayrenderer.dylib) accroche presentDrawable: ; avec
   # DXMT la premiere image s'affiche puis plus rien n'avance (verifie sur
   # Expedition 33 le 2026-10-11). On le coupe pour ce lancement, quoi que dise
   # l'option overlay.
   if [ -n "$OVERLAY" ]; then
      OVERLAY=
      echo "    d3d11 : dxmt -> overlay Steam coupe pour ce lancement (sa bibliotheque fige la presentation DXMT)" >>"$JOURNAL"
   fi
   # metalfx = true : MetalFX spatial x2 sur la sortie (drawable aux pixels physiques
   # au lieu de l'agrandissement CoreAnimation). Sans bordure seulement : le plein
   # ecran exclusif change le mode d'affichage et donne un ecran noir.
   if [ "$(opt metalfx CIDRE_METALFX)" = true ]; then
      export DXMT_METALFX_SPATIAL_SWAPCHAIN=1
      echo "    d3d11 : dxmt -> MetalFX spatial x2 sur la sortie" >>"$JOURNAL"
   fi
   if [ "$(opt journal_detaille CIDRE_JOURNAL_DETAILLE)" = true ]; then
      export DXMT_LOG_LEVEL=${DXMT_LOG_LEVEL:-info} DXMT_LOG_PATH="${DXMT_LOG_PATH:-$(dirname "$JOURNAL")/dxmt}"
      mkdir -p "$DXMT_LOG_PATH"
   fi
else
   # dxvk : si DXMT est encore pose par un lancement precedent, on remet les
   # builtins Wine et on retire winemetal. Sinon rien a faire.
   for d in $DXMT_DLLS; do
      [ -f "$WINDLL/$d.dll" ] && est_dxmt "$WINDLL/$d.dll" || continue
      if [ -f "$BUILTINS_WINE/$d.dll" ]; then
         poser "$BUILTINS_WINE/$d.dll" "$WINDLL/$d.dll"
         echo "    d3d11 : dxvk -> builtin Wine $d.dll remis (DXMT etait pose)" >>"$JOURNAL"
      else
         echo "    d3d11 : $d.dll est celui de DXMT et le builtin Wine n'a pas de sauvegarde : reinstaller le runtime (cidre setup)" >>"$JOURNAL"
      fi
   done
   retirer_dxmt32 dxvk
   rm -f "$WINDLL/winemetal.dll" "$WINUNIX/winemetal.so" "$SYS32/winemetal.dll"
fi

# Journal detaille : par defaut on fait taire Wine (WINEDEBUG=-all), ce qui rend
# muet aussi un Wine qui ne demarre pas. journal_detaille = true lui laisse ses
# messages d'erreur, pour le client de service comme pour le jeu.
JOURNAL_WINE=-all
if [ "$(opt journal_detaille CIDRE_JOURNAL_DETAILLE)" = true ]; then
   JOURNAL_WINE=err+all,fixme-all
   # Pour le jeu, les exceptions en plus (+seh) : la premiere dit pourquoi il
   # tombe, quand la derniere ligne d'erreur n'en montre que la consequence.
   # `cidre log` n'en rend que le debut.
   [ -n "${WINEDEBUG:-}" ] || export WINEDEBUG=$JOURNAL_WINE,+seh
   echo "    journal detaille : WINEDEBUG=$WINEDEBUG" >>"$JOURNAL"
fi

# Le client Steam de macOS : c'est lui qui repond derriere le pont, et rien ne
# dit qu'il tourne quand le jeu est lance par `cidre play` (Verger) plutot que
# par le bouton de Steam. Ferme, un jeu protege par le DRM de Steam demande
# steam://run/<appid> et sort aussitot (Expedition 33 : code 53, sans une ligne
# au journal). On l'ouvre donc (en arriere-plan, sans fenetre) et on attend
# qu'il soit connecte ; deja ouvert, on masque sa fenetre et on dit s'il mange
# le processeur -- jamais on ne le quitte. Ce qu'on a fait va au journal et a la
# sortie (le journal de lancement de Verger). Jamais bloquant : sans client, le
# jeu est lance quand meme, la trace dit pourquoi il tombera.
# CIDRE_SANS_STEAM=1 : on ne touche pas au client. Cf.
# tests/client_steam_natif.sh.
if [ -n "${SteamAppId:-}" ] && [ "${CIDRE_SANS_STEAM:-}" != 1 ]; then
   sh "$R/tests/client_steam_natif.sh" assurer 2>&1 | tee -a "$JOURNAL" || true
elif [ "${CIDRE_SANS_STEAM:-}" != 1 ]; then
   # Jeu hors Steam : le client ne lui sert a rien, mais s'il tourne et mange
   # le processeur, il le prend au jeu aussi.
   sh "$R/tests/client_steam_natif.sh" cpu 2>/dev/null | sed -n '2s/^/    /p' | tee -a "$JOURNAL" || true
fi

# Le client de service : un seul a la fois, reutilise s'il tourne deja.
if ! pgrep -f 'c:\\faux_steam.exe' >/dev/null 2>&1; then
   WINEDEBUG=$JOURNAL_WINE CIDRE_OVERLAY_DYLIB= sh "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >>"$JOURNAL" 2>&1 &
   # On attend SA ligne « inscrit » : celle d'un lancement precedent est deja
   # dans le journal, on ne compte que ce qui s'y ajoute.
   # (`|| true` : grep rend 1 quand il compte zero, et ce script est en `set -e`)
   inscrits() { grep -c "inscrit" "$JOURNAL" 2>/dev/null || true; }
   avant=$(inscrits); avant=${avant:-0}
   i=0
   while [ $i -lt 60 ]; do
      n=$(inscrits); [ "${n:-0}" -gt "$avant" ] && break
      sleep 1; i=$((i + 1))
   done
   # Sans lui, le jeu ne trouvera pas Steam ; et s'il n'a pas demarre, le jeu ne
   # demarrera sans doute pas non plus. Le dire, plutot que se taire.
   [ $i -lt 60 ] || echo "    client de service : pas demarre apres 60 s -- Wine ne repond pas ? (\`cidre doctor\` le dira)" >>"$JOURNAL"
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
#   arguments : options de ligne de commande du jeu, depuis sa fiche (ex.
#     "-force-gfx-direct" : PEAK en vrai D3D12 rend alors en 2 listes de commandes
#     par image au lieu de ~120, 32 -> 45 images/s au meme endroit, 2026-10-14).
#     Un environnement explicite (CIDRE_ARGUMENTS) garde la main ; une option deja
#     presente sur la ligne de commande n'est pas doublee (tests/arguments_jeu.sh).
ARGJ=${CIDRE_ARGUMENTS:-$(profil arguments)}
if [ -n "$ARGJ" ]; then
   AJOUTS=$(sh "$R/tests/arguments_jeu.sh" "$ARGJ" "$@")
   while IFS= read -r a; do
      [ -n "$a" ] && set -- "$@" "$a"
   done <<FIN_ARGUMENTS
$AJOUTS
FIN_ARGUMENTS
   echo "    profil : arguments du jeu : $ARGJ" >>"$JOURNAL"
fi

# Sauvegardes. Steam d'abord : si le jeu ecrit par l'API Remote Storage, ou
# declare a Steam Cloud un dossier pour macOS (le dossier du prefixe y est lie
# ici, avant le lancement), le client Steam de macOS synchronise lui-meme et
# Cidre ne copie rien. Sinon (Auto-Cloud declare pour Windows seulement : le
# client macOS ne resout pas ces racines), restauration depuis le dossier des
# copies de Cidre de ce qui y est plus recent. Non destructif, non bloquant.
# cf. tests/sync_saves_steam.sh, tests/lier_saves_steam.sh.
# Un jeu lance par `cidre play` (CIDRE_SEANCE=1), et non par le bouton de Steam :
# le client ne synchronise pas son nuage au lancement, seulement a la sortie.
# Une seance Steam au nom du jeu, ouverte puis fermee, declenche cette synchro
# (qui descend le nuage) et on attend sa fin : le jeu trouve des le premier
# lancement une sauvegarde faite ailleurs. ~1 s quand tout est a jour ; rien si
# le client est ferme ou hors ligne. cf. tests/seance_steam_cloud.sh.
if [ -n "$JEU" ] && [ "${CIDRE_SEANCE:-}" = 1 ] && [ "${CIDRE_SANS_STEAM:-}" != 1 ]; then
   sh "$R/tests/seance_steam_cloud.sh" "$JEU" 2>&1 | tee -a "$JOURNAL" || true
fi
# Et avant tout : la fin de la partie ne doit pas faire retirer du nuage des
# sauvegardes que ce Mac a perdues. La synchro de sortie du client, sans trace
# du lancement, retire du nuage tout fichier qu'il croit synchronise ici et que
# ses regles n'y trouvent plus. Une copie identique gardee par Cidre est remise
# en place ; sinon le jeu ne part pas (code 7), sauf accord explicite
# (`cidre play <id> --accord-nuage`). cf. tests/garde_nuage_steam.sh.
if [ -n "$JEU" ] && [ "${CIDRE_SEANCE:-}" = 1 ]; then
   g=$(sh "$R/tests/garde_nuage_steam.sh" "$JEU" ${CIDRE_ACCORD_NUAGE:+--accord} 2>&1) && gr=0 || gr=$?
   [ -z "$g" ] || printf '%s\n' "$g" | tee -a "$JOURNAL"
   [ $gr -eq 0 ] || exit 7
fi
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

# Reglages du jeu lui-meme ([reglages_jeu] de sa fiche dans la base de profils,
# cf. profils/README.md) : un jeu qui n'est jouable qu'avec ses propres options
# baissees (Expedition 33 : prereglage Moyen + resolution 66 %, x2,5). Poses une
# fois, apres la restauration des sauvegardes (qui peut ramener ce fichier
# de la copie) : des qu'ils sont ecrits -- ou deja en place -- on le note dans le
# profil utilisateur (reglages_jeu_appliques = true) et on n'y touche plus,
# l'utilisateur est libre de regler son jeu. Si le fichier n'existe pas encore
# (premier lancement), on reessaie la fois suivante. Jamais bloquant.
# Une entree qui porte un `id` (ajoutee a la fiche apres coup : la resolution
# redetectee une fois, 0141) atteint aussi un jeu deja marque : les `id` poses
# sont gardes dans reglages_jeu_ids, et une entree a `id` nouveau est posee une
# fois, sans reposer les autres.
# Le temoin de la fiche depend aussi de l'API graphique (Expedition 33 : la carte
# vue n'est pas la meme en DXMT, en DXVK et en D3D12) : celui que le jeu a ecrit
# lors d'une partie dans cette voie est garde dans le profil, et remis avant le
# jeu quand une partie dans une autre voie l'a change -- sinon le jeu refait sa
# detection une minute apres le lancement et la partie se joue a ses reglages.
VOIE_TEMOIN=$D3D11
[ "$(opt dx12 CIDRE_DX12)" = true ] && VOIE_TEMOIN=d3d12
[ -z "$JEU" ] || sh "$R/tests/reglages_jeu.sh" "$JEU" temoin-remettre "$VOIE_TEMOIN" >>"$JOURNAL" 2>&1 || true
if [ -n "$JEU" ]; then
   IDS_FICHE=$(sh "$R/tests/fiche_profil.sh" reglages "$JEU" 2>/dev/null | awk -F'\t' '$2 == "id" && !vu[$3]++ { printf "%s%s", (n++ ? "," : ""), $3 }')
   if [ "$(profil reglages_jeu_appliques)" != true ]; then
      sh "$R/tests/reglages_jeu.sh" "$JEU" >>"$JOURNAL" 2>&1 && RCR=0 || RCR=$?
      if [ "$RCR" -eq 0 ]; then
         sh "$R/tests/profil_cidre.sh" "$JEU" set reglages_jeu_appliques true >>"$JOURNAL" 2>&1 \
            && echo "    reglages du jeu : notes comme appliques (cidre unset $JEU reglages_jeu_appliques pour les reposer)" >>"$JOURNAL" || true
         [ -z "$IDS_FICHE" ] || sh "$R/tests/profil_cidre.sh" "$JEU" set reglages_jeu_ids "\"$IDS_FICHE\"" >>"$JOURNAL" 2>&1 || true
      fi
   elif [ -n "$IDS_FICHE" ]; then
      IDS_FAITS=$(profil reglages_jeu_ids)
      NOUVEAUX=$(awk -v f="$IDS_FICHE" -v d="$IDS_FAITS" 'BEGIN { n = split(f, a, ","); for (i = 1; i <= n; i++) if (index("," d ",", "," a[i] ",") == 0) print a[i] }')
      if [ -n "$NOUVEAUX" ]; then
         sh "$R/tests/reglages_jeu.sh" "$JEU" nouvelles "$IDS_FAITS" >>"$JOURNAL" 2>&1 && RCR=0 || RCR=$?
         if [ "$RCR" -eq 0 ]; then
            sh "$R/tests/profil_cidre.sh" "$JEU" set reglages_jeu_ids "\"$IDS_FICHE\"" >>"$JOURNAL" 2>&1 \
               && echo "    reglages du jeu : nouvelles entrees de la fiche posees ($(echo $NOUVEAUX))" >>"$JOURNAL" || true
         fi
      fi
   fi
fi
# Le temoin de la fiche ([reglages_jeu_temoin]) : releve avant le jeu, compare a
# la sortie. S'il a change, le jeu a refait sa detection du materiel et repris
# ses propres reglages : on les reposera au lancement suivant (cf. reglages_jeu.sh).
TEMOIN=
[ -z "$JEU" ] || TEMOIN=$(sh "$R/tests/reglages_jeu.sh" "$JEU" temoin 2>/dev/null || true)

cd "$DOSSIER"
# Langue dans le fichier de reglages du jeu (outil-steam/langues.conf). Apres la
# restauration des sauvegardes, qui peut ramener ce meme fichier de la copie.
# En « auto », une fois par langue du Mac : la langue choisie ensuite dans le
# jeu n'est plus touchee.
echo "    langue  : $LANGUE_CODE ($([ "$LANGUE" = auto ] && echo "langue du Mac : $(langue mac)" || echo "profil")) -> locale ${CIDRE_LOCALE:-?}, Steam : langue du client" >>"$JOURNAL"
if [ -n "$LANGUE_CODE" ]; then
   if [ "$LANGUE" = auto ]; then sh "$R/tests/langue_jeu.sh" "$JEU" "$LANGUE_CODE" une-fois >>"$JOURNAL" 2>&1 || true
   else sh "$R/tests/langue_jeu.sh" "$JEU" "$LANGUE_CODE" >>"$JOURNAL" 2>&1 || true; fi
fi
# On ne fait PLUS exec : on attend la fin du jeu pour sauvegarder apres coup.
# `&& ... ||` : ce script est en `set -e`, et un jeu qui sort sur un code d'erreur
# (un plantage, un arret force) l'arretait ici meme, AVANT la sauvegarde ci-dessous.
[ -z "$JEU" ] || echo "    shaders : $(sh "$R/tests/etat_shaders.sh" etat "$JEU" "$VOIE_TEMOIN" 2>/dev/null | sed -n 's/^etat=//p')" >>"$JOURNAL"
CIDRE_OVERLAY_DYLIB=$OVERLAY sh "$R/tests/etape2_pile_arm64ec.sh" "$PROG" "$@" >>"$JOURNAL" 2>&1 && RC=0 || RC=$?
[ -z "$JEU" ] || sh "$R/tests/reglages_jeu.sh" "$JEU" temoin-change "$TEMOIN" "$VOIE_TEMOIN" >>"$JOURNAL" 2>&1 || true
# Ce que le jeu a eu le temps de compiler : la voie, la duree de la partie, le
# macOS et le Cidre du moment (tests/etat_shaders.sh), pour annoncer au
# prochain lancement s'il faudra encore compiler (`cidre play --json`, Verger).
[ -z "$JEU" ] || sh "$R/tests/etat_shaders.sh" noter "$JEU" "$VOIE_TEMOIN" "$DEBUT_EPOCH" >>"$JOURNAL" 2>&1 || true
# Sorti sur une erreur : le code seul n'aide personne. tests/expliquer_sortie.sh
# lit le journal de ce lancement, reconnait les signatures connues (client Steam
# ferme, pas d'affichage, DLL manquante, prefixe abime, plantage...) et ecrit
# « cause probable » et « a faire », au journal et sur la sortie (Verger les
# affiche a la place du code).
# Un jeu lance en DXMT qui l'a refuse au demarrage (DXGI_ERROR_UNSUPPORTED) :
# tests/repli_dxmt.sh enregistre d3d11 = dxvk pour ce jeu, et on l'explique
# meme si le jeu est sorti sur 0 (fenetre d'erreur fermee par le joueur).
REPLI=
if [ -n "$JEU" ] && [ "$D3D11" = dxmt ]; then
   REPLI=$(sh "$R/tests/repli_dxmt.sh" "$JEU" "$JOURNAL" 2>/dev/null || true)
   [ -z "$REPLI" ] || echo "$REPLI" | tee -a "$JOURNAL"
fi
if [ $RC -ne 0 ] || [ -n "$REPLI" ]; then
   [ $RC -eq 0 ] || echo "    le jeu s'est termine sur le code $RC" | tee -a "$JOURNAL"
   [ "${CIDRE_SANS_STEAM:-}" != 1 ] || export CIDRE_CLIENT_STEAM_ETAT=inconnu
   CIDRE_JEU="$JEU" sh "$R/tests/expliquer_sortie.sh" "$RC" "$JOURNAL" 2>/dev/null | tee -a "$JOURNAL" || true
fi

# Apres la sortie du jeu (meme en cas de crash : l'etat tel quel) : copie vers
# le dossier de Cidre, ou, si Steam synchronise ce jeu, ce que son client dit
# avoir envoye. Non bloquant.
if [ -n "$JEU" ]; then
   CIDRE_SAVES_DEPUIS=$DEBUT_EPOCH sh "$R/tests/sync_saves_steam.sh" "$JEU" backup >>"$JOURNAL" 2>&1 || true
fi
exit $RC
}
