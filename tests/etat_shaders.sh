#!/bin/sh
# Les shaders d'un jeu sont-ils deja compiles sur ce Mac ? De quoi prevenir le
# joueur avant le lancement, et garder la trace de ce qui a ete fait.
#
# Au premier lancement d'un jeu, chaque shader est traduit (DXBC -> AIR par
# DXMT, DXIL -> SPIR-V -> MSL par vkd3d-proton et KosmicKrisp) puis compile par
# Metal pour la puce (service MTLCompilerService, tous les coeurs). Selon le
# jeu, cela fait des minutes d'ecran noir ou de textures manquantes. Tout
# reste ensuite en cache :
#   - DXMT : l'AIR dans $DARWIN_USER_CACHE_DIR/dxmt/<exe>/shaders_<metal>.db,
#     le binaire de Metal a cote (dxmt/<exe>/com.apple.metal) ;
#   - KosmicKrisp (D3D12, et D3D11 par DXVK) : les pipelines Metal dans
#     ~/Library/Application Support/Cidre/vkd3d-cache/<appid> ;
#   - vkd3d-proton : vkd3d-proton.cache dans le dossier de l'executable.
# Ces caches ne survivent pas a tout : le binaire Metal est a refaire apres une
# mise a jour de macOS (son compilateur change) ou sur un autre Mac, et les
# pipelines de KosmicKrisp apres une mise a jour de Cidre qui change le MSL
# produit. L'AIR de DXMT, lui, ne depend ni de la puce ni de macOS.
#
# On ne lit pas les caches eux-memes (DXMT les range par nom d'executable, que
# Cidre ne connait pas toujours d'avance) : le lanceur note, a la sortie du
# jeu, dans quelles conditions il a tourne, et combien de temps. Un jeu qui
# a tourne moins de SEUIL secondes en tout dans une voie n'a sans doute pas
# encore tout compile.
#
# Etat rendu :
#   premier_lancement  rien de note dans cette voie (ou trop peu de jeu)
#   cache_invalide     raison = macos | machine | cidre : a recompiler, en
#                      general plus vite qu'au premier lancement
#   en_cache           rien a annoncer
#
# usage :
#   etat_shaders.sh voie <id>                      dxmt | dxvk | d3d12
#   etat_shaders.sh etat <id> [<voie>]             lignes cle=valeur
#   etat_shaders.sh json <id> [<voie>]             un objet JSON
#   etat_shaders.sh message <id> [<voie>]          la phrase a dire, vide si rien
#   etat_shaders.sh noter <id> <voie> <debut>      a la sortie du jeu (lanceur)
# CIDRE_DIR : dossier d'etat de Cidre (defaut ~/Library/Application Support/Cidre).
set -u
R=$(cd "$(dirname "$0")" && cd .. && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
ETATS="$CIDRE_DIR/shaders"
SEUIL=${CIDRE_SHADERS_SEUIL:-120}

ACTION=${1:-}; ID=${2:-}
[ -n "$ACTION" ] && [ -n "$ID" ] || { sed -n '/^# usage/,/^# CIDRE_DIR/p' "$0" >&2; exit 2; }
case $ID in *[!A-Za-z0-9_-]*) echo "id invalide : $ID" >&2; exit 2 ;; esac

macos() { sw_vers -buildVersion 2>/dev/null || echo inconnu; }
machine() { sysctl -n hw.model 2>/dev/null || echo inconnu; }
runtime() { v=$(cat "$R/VERSION" 2>/dev/null); echo "${v:-dev}"; }

# La voie de rendu du prochain lancement, comme la choisit le lanceur : d3d12
# si l'option dx12 est posee, sinon d3d11 (dxmt, ou dxvk). L'environnement
# explicite garde la main, comme dans tests/lancer_depuis_steam.sh.
voie() {
   p=$(sh "$R/tests/profil_cidre.sh" "$ID" 2>/dev/null || true)
   val() { printf '%s\n' "$p" | sed -n "s/^$1=//p" | head -1; }
   case ${CIDRE_DX12:-} in 1) echo d3d12; return ;; 0) ;; *) [ "$(val dx12)" = true ] && { echo d3d12; return; } ;; esac
   d=${CIDRE_D3D11:-$(val d3d11)}
   case $d in dxmt) echo dxmt ;; *) echo dxvk ;; esac
}

VOIE=${3:-}
case $ACTION in noter) ;; *) [ -n "$VOIE" ] || VOIE=$(voie) ;; esac
case $VOIE in dxmt|dxvk|d3d12) ;; *) echo "voie inconnue : $VOIE" >&2; exit 2 ;; esac
F="$ETATS/$ID.$VOIE"
lu() { sed -n "s/^$1=//p" "$F" 2>/dev/null | head -1; }

# Rien de note (jeu joue avant que Cidre ne note ses parties) : les caches
# eux-memes. DXMT range le sien par nom d'executable : un .exe du dossier du
# jeu (CIDRE_CHEMIN_JEU, donne par `cidre`) qui a deja une base de plus de
# 1 Mo ; KosmicKrisp, par appid. On ne sait pas pour quel macOS ils ont ete
# faits : sans trace, on les croit bons.
amorce() {
   c=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)
   case $VOIE in
      dxmt)
         [ -n "$c" ] && [ -d "${CIDRE_CHEMIN_JEU:-}" ] || return 1
         find "$CIDRE_CHEMIN_JEU" -maxdepth 6 -iname '*.exe' 2>/dev/null | while IFS= read -r e; do
            find "${c%/}/dxmt/$(basename "$e")" -maxdepth 1 -name 'shaders_*.db' -size +2048 2>/dev/null
         done | grep -q . ;;
      *) find "$CIDRE_DIR/vkd3d-cache/$ID" -maxdepth 1 -name '*.mtl4archive' -size +2048 2>/dev/null | grep -q . ;;
   esac
}

etat() {
   ETAT=en_cache; RAISON=
   cumul=$(lu cumul)
   case $cumul in ''|*[!0-9]*) cumul=0 ;; esac
   if [ ! -f "$F" ]; then
      amorce || ETAT=premier_lancement
   elif [ "$cumul" -lt "$SEUIL" ]; then
      ETAT=premier_lancement
   elif [ "$(lu machine)" != "$(machine)" ]; then
      ETAT=cache_invalide; RAISON=machine
   elif [ "$(lu macos)" != "$(macos)" ]; then
      ETAT=cache_invalide; RAISON=macos
   elif [ "$VOIE" != dxmt ] && [ "$(lu runtime)" != "$(runtime)" ]; then
      # KosmicKrisp retrouve ses pipelines par leur MSL : un Cidre qui le
      # produit autrement les recompile. DXMT garde son AIR (cle : version
      # d'airconv et options) et Metal son binaire tant que macOS ne change pas.
      ETAT=cache_invalide; RAISON=cidre
   fi
}

message() {
   case $ETAT:$RAISON in
      premier_lancement:*) echo "Premier lancement : les shaders du jeu sont compiles pour ce Mac. Cela peut prendre quelques minutes, pendant lesquelles le jeu peut rester sur un ecran noir ou afficher des textures manquantes. Les lancements suivants reprennent le cache." ;;
      cache_invalide:macos) echo "macOS a ete mis a jour depuis la derniere partie : Metal recompile les shaders du jeu. Le lancement peut etre plus long que d'habitude, une fois." ;;
      cache_invalide:machine) echo "Premier lancement sur ce Mac : les shaders du jeu sont compiles pour sa puce. Cela peut prendre quelques minutes (ecran noir ou textures manquantes possibles)." ;;
      cache_invalide:cidre) echo "Cidre a ete mis a jour depuis la derniere partie : une partie des shaders du jeu peut etre recompilee. Le lancement peut etre plus long que d'habitude, une fois." ;;
   esac
}

json_ou_null() { case $1 in '') echo null ;; *[!0-9]*) printf '"%s"\n' "$1" ;; *) echo "$1" ;; esac; }
json_chaine() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

case $ACTION in
   voie) echo "$VOIE" ;;
   etat)
      etat
      echo "etat=$ETAT"; echo "raison=$RAISON"; echo "voie=$VOIE"
      echo "dernier=$(lu dernier)"; echo "macos=$(lu macos)" ;;
   message) etat; message ;;
   json)
      etat; m=$(message)
      printf '{"etat":"%s","raison":%s,"voie":"%s","dernier":%s,"cumul":%s,"macos":%s,"message":%s}\n' \
         "$ETAT" "$(json_ou_null "$RAISON")" "$VOIE" "$(json_ou_null "$(lu dernier)")" \
         "$(json_ou_null "$(lu cumul)")" "$(json_ou_null "$(lu macos)")" \
         "$([ -n "$m" ] && json_chaine "$m" || echo null)" ;;
   noter)
      DEBUT=${4:-}
      case $DEBUT in ''|*[!0-9]*) echo "usage : etat_shaders.sh noter <id> <voie> <debut_epoch>" >&2; exit 2 ;; esac
      FIN=$(date +%s); duree=$((FIN - DEBUT)); [ "$duree" -ge 0 ] || duree=0
      # Une autre machine, un autre macOS ou (hors DXMT) un autre Cidre : le
      # cache a ete refait pendant cette partie, le cumul repart d'elle.
      cumul=$(lu cumul); case $cumul in ''|*[!0-9]*) cumul=0 ;; esac
      premier=$(lu premier)
      if [ "$(lu machine)" != "$(machine)" ] || [ "$(lu macos)" != "$(macos)" ] \
         || { [ "$VOIE" != dxmt ] && [ "$(lu runtime)" != "$(runtime)" ]; }; then
         cumul=0
      fi
      mkdir -p "$ETATS"
      { echo "voie=$VOIE"
        echo "premier=${premier:-$DEBUT}"
        echo "dernier=$FIN"
        echo "cumul=$((cumul + duree))"
        echo "macos=$(macos)"
        echo "machine=$(machine)"
        echo "runtime=$(runtime)"
      } >"$F.tmp" && mv "$F.tmp" "$F"
      echo "    shaders : $VOIE, ${duree} s de jeu (en tout $((cumul + duree)) s sur macOS $(macos)) -> $F" ;;
   *) echo "action inconnue : $ACTION" >&2; exit 2 ;;
esac
