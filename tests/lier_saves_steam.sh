#!/bin/sh
# Faire synchroniser les sauvegardes par Steam lui-meme, quand il le peut.
#
# Le client Steam de macOS synchronise deja, a la sortie d'un jeu lance par
# Cidre (« AutoCloud on exit » dans son cloud_log.txt), tout ce qu'il sait
# trouver :
#   - les fichiers que le jeu ecrit par l'API Remote Storage : ils passent par
#     le pont et arrivent dans userdata/<compte>/<appid>/remote du client ;
#   - les fichiers Auto-Cloud dont le jeu declare un dossier POUR macOS.
# Il ne sait pas resoudre une racine Windows (WinAppDataLocal...) : pour un jeu
# Auto-Cloud, il faut donc que les fichiers du jeu Windows soient LA ou le
# client les cherche. C'est le lien : le dossier de sauvegarde du prefixe Wine
# devient un lien symbolique vers le dossier macOS que le jeu declare a Steam.
# La fiche du jeu ([compat.steam_cloud], relevee par l'importeur) dit lequel.
#
#   lier_saves_steam.sh <appid> mode       `api`, `lien`, ou rien (Steam ne peut pas : copie Cidre)
#   lier_saves_steam.sh <appid> lier       pose les liens ; 0 si tous sont en place
#   lier_saves_steam.sh <appid> dossiers   les liens resolus : `dossier du prefixe <TAB> dossier macOS`
#   lier_saves_steam.sh <appid> envoi <depuis>   ce que le client a envoye depuis (secondes epoch)
#
# Jamais destructif : le dossier d'origine du prefixe est DEPLACE, entier, dans
# <Cidre>/saves/<appid>/.history/avant-lien-<date>/ ; ses fichiers sont copies
# dans le dossier macOS sans rien y ecraser (un fichier deja present cote macOS
# reste : c'est celui que Steam synchronise ; l'autre est dans la copie datee).
#
# CIDRE_SAVES_STEAM=0 : ne rien confier a Steam (copie Cidre comme avant).
# Pour les essais : CIDRE_FICHE_STEAM_CLOUD (`synchro<TAB>liens`, `-` pour
# aucune fiche), CIDRE_PREFIXE_UTIL, CIDRE_JEU_DOSSIER, CIDRE_MAISON (dossier
# personnel), CIDRE_STEAMID (identifiant 64 bits du compte), CIDRE_CLOUD_LOG.
set -u
APPID=${1:?usage: lier_saves_steam.sh <appid> mode|lier|dossiers|envoi}
CMD=${2:-mode}
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
MAISON=${CIDRE_MAISON:-$HOME}
STEAM="$HOME/Library/Application Support/Steam"
TAB=$(printf '\t')

[ "${CIDRE_SAVES_STEAM:-1}" = 0 ] && exit 1

# --- la fiche : synchro et liens ---------------------------------------------
if [ -n "${CIDRE_FICHE_STEAM_CLOUD:-}" ]; then
   [ "$CIDRE_FICHE_STEAM_CLOUD" = - ] && exit 1
   SYNCHRO=${CIDRE_FICHE_STEAM_CLOUD%%"$TAB"*}
   LIENS=${CIDRE_FICHE_STEAM_CLOUD#*"$TAB"}; [ "$LIENS" = "$CIDRE_FICHE_STEAM_CLOUD" ] && LIENS=
else
   f=$(sh "$R/tests/fiche_profil.sh" chemin "$APPID" 2>/dev/null) || exit 1
   [ -n "$f" ] || exit 1
   plat=$(sh "$R/tests/fiche_profil.sh" toml "$f" 2>/dev/null | awk -F'\t' '$1 == "compat.steam_cloud"')
   SYNCHRO=$(printf '%s\n' "$plat" | awk -F'\t' '$2 == "synchro" { print $4; exit }')
   LIENS=$(printf '%s\n' "$plat" | awk -F'\t' '$2 == "liens" { print $4; exit }')
fi
case $SYNCHRO in
   steam-api)  MODE=api ;;
   steam-lien) MODE=lien; [ -n "$LIENS" ] || exit 1 ;;
   *) exit 1 ;;
esac

# --- le compte : {64BitSteamID} et {Steam3AccountID} dans les chemins ---------
steamid() {
   [ -n "${CIDRE_STEAMID:-}" ] && { echo "$CIDRE_STEAMID"; return; }
   # le bloc du compte marque MostRecent, sinon le premier
   LC_ALL=C awk '
      /^[ \t]*"7656[0-9]+"[ \t\r]*$/ { gsub(/[^0-9]/, ""); id = $0; if (premier == "") premier = id }
      /"MostRecent"[ \t]*"1"/ && id != "" { print id; trouve = 1; exit }
      END { if (!trouve && premier != "") print premier }' "$STEAM/config/loginusers.vdf" 2>/dev/null
}
# Les liens resolus, un par ligne : `dossier du prefixe <TAB> dossier macOS`.
# Rend 1 si un chemin ne peut pas etre resolu (compte inconnu, dossier du
# prefixe ou du jeu introuvable) : dans le doute, pas de lien.
resoudre() {
   UTIL=${CIDRE_PREFIXE_UTIL:-}
   if [ -z "$UTIL" ]; then
      a=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
      [ -n "$a" ] && UTIL=$(dirname "$a")
   fi
   JEUDIR=${CIDRE_JEU_DOSSIER:-}
   SID=
   case $LIENS in *"{"*) SID=$(steamid); [ -n "$SID" ] || return 1 ;; esac
   printf '%s\n' "$LIENS" | awk -v sid="$SID" '
      # identifiant 64 bits = 76561197960265728 + numero de compte (sans les trois
      # premiers chiffres, le calcul tient dans un flottant)
      BEGIN { compte = ""; if (sid != "") compte = sprintf("%d", substr(sid, 4) - 61197960265728) }
      { n = split($0, l, / ; /)
        for (i = 1; i <= n; i++) {
           p = index(l[i], " => "); if (!p) { faux = 1; continue }
           w = substr(l[i], 1, p - 1); m = substr(l[i], p + 4)
           gsub(/\{64BitSteamID\}/, sid, w); gsub(/\{64BitSteamID\}/, sid, m)
           gsub(/\{Steam3AccountID\}/, compte, w); gsub(/\{Steam3AccountID\}/, compte, m)
           if (w ~ /[{}]/ || m ~ /[{}]/ || w == "" || m == "" || w ~ /(^|\/)\.\.(\/|$)/ || m ~ /(^|\/)\.\.(\/|$)/) faux = 1
           sortie = sortie w "\t" m "\n"
        } }
      # tout ou rien : un seul lien illisible, et on ne lie rien
      END { if (!faux) printf "%s", sortie }' | while IFS="$TAB" read -r w m; do
      case $w in
         jeu:*)
            [ -n "$JEUDIR" ] || JEUDIR=$(sh "$R/cidre" chemin "$APPID" 2>/dev/null || true)
            [ -n "$JEUDIR" ] && [ -d "$JEUDIR" ] || exit 1
            printf '%s\t%s\n' "$JEUDIR/${w#jeu:}" "$MAISON/$m" ;;
         *)
            [ -n "$UTIL" ] && [ -d "$UTIL" ] || exit 1
            printf '%s\t%s\n' "$UTIL/$w" "$MAISON/$m" ;;
      esac
   done
}

# Un lien : <dossier du prefixe> -> <dossier macOS>. 0 s'il est en place.
lier_un() { # <src> <dst>
   src=$1; dst=$2
   if [ -L "$src" ]; then
      [ "$(readlink "$src")" = "$dst" ] && return 0
      echo "    saves: $src est deja un lien vers autre chose ($(readlink "$src")) : laisse tel quel"
      return 1
   fi
   hist="$CIDRE_DIR/saves/$APPID/.history/avant-lien-$TS"
   n=0; while [ -e "$hist/$n" ] || [ -e "$hist/$n.macos" ]; do n=$((n + 1)); done
   # Le dossier macOS a deja des fichiers (ceux du jeu natif, ou descendus du
   # nuage) : le jeu Windows va ecrire au meme endroit. On en garde une copie
   # datee avant le premier lien.
   if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
      mkdir -p "$hist" && cp -Rp "$dst" "$hist/$n.macos" || { echo "    saves: copie de precaution de $dst impossible : pas de lien"; return 1; }
      echo "    saves: copie de precaution du dossier macOS dans $hist/$n.macos"
   fi
   mkdir -p "$dst" || return 1
   if [ -e "$src" ]; then
      [ -d "$src" ] || { echo "    saves: $src n'est pas un dossier : pas de lien"; return 1; }
      # Les fichiers du prefixe rejoignent le dossier macOS, sans rien y ecraser.
      garde=0
      liste=$(mktemp "${TMPDIR:-/tmp}/cidre-lien.XXXXXX") || return 1
      ( cd "$src" && find . -type f ) >"$liste" 2>/dev/null
      while IFS= read -r rel; do
         rel=${rel#./}
         if [ -e "$dst/$rel" ]; then
            cmp -s "$src/$rel" "$dst/$rel" || { garde=$((garde + 1)); echo "    saves: $rel existe deja cote macOS et differe : celui de macOS reste"; }
         else
            mkdir -p "$(dirname "$dst/$rel")" && cp -p "$src/$rel" "$dst/$rel" || { rm -f "$liste"; return 1; }
         fi
      done <"$liste"
      rm -f "$liste"
      # Le dossier d'origine n'est pas efface : il est range, entier, a cote des
      # copies de precaution de Cidre.
      mkdir -p "$hist" && mv "$src" "$hist/$n" || { echo "    saves: impossible de ranger $src : pas de lien"; return 1; }
      printf '%s\n' "$src" >"$hist/$n.origine"
      echo "    saves: dossier d'origine range dans $hist/$n"
      [ $garde -eq 0 ] || echo "    saves: $garde fichier(s) du prefixe non repris (la version macOS a ete gardee) : ils sont dans $hist/$n"
   else
      mkdir -p "$(dirname "$src")" || return 1
   fi
   ln -s "$dst" "$src" || return 1
   echo "    saves: $src -> $dst (Steam Cloud synchronise ce dossier)"
}

TS=$(date '+%Y%m%d-%H%M%S')
case $CMD in
   mode)
      # `lien` seulement si les chemins se resolvent : sinon la copie Cidre sert.
      if [ $MODE = lien ]; then l=$(resoudre) && [ -n "$l" ] || exit 1; fi
      echo $MODE ;;
   dossiers)
      [ $MODE = lien ] || exit 0
      resoudre ;;
   lier)
      [ $MODE = lien ] || exit 0
      l=$(resoudre) && [ -n "$l" ] || { echo "    saves: liens Steam Cloud non resolus (compte Steam ou dossier introuvable)"; exit 1; }
      rc=0
      printf '%s\n' "$l" | { while IFS="$TAB" read -r s d; do lier_un "$s" "$d" || rc=1; done; exit $rc; } ;;
   envoi)
      # Ce que dit le journal du client depuis le lancement : la synchro de
      # sortie de CE jeu, et ce qu'elle a envoye. On lui laisse quelques
      # secondes pour finir ; sans client ou sans journal, on ne dit rien.
      DEPUIS=${3:-}; case $DEPUIS in ''|*[!0-9]*) exit 0 ;; esac
      J=${CIDRE_CLOUD_LOG:-$STEAM/logs/cloud_log.txt}
      [ -r "$J" ] || exit 0
      d=$(date -r "$DEPUIS" '+%Y-%m-%d %H:%M:%S')
      lire() {
         LC_ALL=C awk -v d="[$d]" -v a="[AppID $APPID]" '
            index($0, a) && substr($0, 1, 21) >= d {
               if ($0 ~ /Starting sync \(up/) { sync++; fini = 0 }
               if ($0 ~ /Upload OK for file/) ok++
               if ($0 ~ /Upload complete/) fini = 1
               if ($0 ~ /Unable to resolve path|failed to resolve path/) irresolu++
               if ($0 ~ /[Cc]onflict/) conflit++
            }
            END { printf "%d %d %d %d %d\n", sync, fini, ok, irresolu, conflit }' "$J"
      }
      i=0
      while :; do
         set -- $(lire)
         { [ "$1" -gt 0 ] && [ "$2" -eq 1 ]; } || [ $i -ge ${CIDRE_ENVOI_ATTENTE:-8} ] && break
         i=$((i + 1)); sleep 1
      done
      if [ "$1" -eq 0 ]; then echo "    saves: Steam Cloud : le client Steam n'a pas synchronise a la sortie (est-il ouvert et connecte ?)"
      elif [ "$5" -gt 0 ]; then echo "    saves: Steam Cloud : le client signale un conflit (ouvrir Steam pour choisir la version)"
      elif [ "$3" -gt 0 ]; then echo "    saves: Steam Cloud : $3 fichier(s) envoye(s) par le client Steam"
      else echo "    saves: Steam Cloud : rien de neuf a envoyer"; fi ;;
   *) echo "usage: lier_saves_steam.sh <appid> mode|lier|dossiers|envoi" >&2; exit 2 ;;
esac
