#!/bin/sh
# Faire descendre le nuage Steam d'un jeu AVANT de le lancer.
#
# Le client Steam de macOS ne synchronise Steam Cloud au lancement que pour les
# jeux qu'il lance lui-meme (« AC Launch,down ») ; un jeu lance par Cidre ne
# l'est qu'a la sortie (« up,AC Exit » : son journal dit « No launch record
# found »). Cette synchro de sortie compare aussi le nuage et descend ce qui y
# est plus recent. On la declenche donc avant le lancement par une seance
# Steam au nom du jeu, ouverte puis fermee sans le lancer (`cidre-outil
# seance`), et on attend sa fin dans le journal du client (logs/cloud_log.txt).
# Ensuite seulement le jeu part, ou une copie (Cidre, bouteille) comble un
# dossier que Steam aurait laisse vide -- et remotecache.vdf, que cette synchro
# ecrit, dit ce que garde le nuage.
#
#   seance_steam_cloud.sh <appid>
#
# Seulement pour un jeu que le client sait synchroniser sur macOS (fiche
# [compat.steam_cloud] : API de Steam, ou dossier declare pour macOS, cf.
# tests/lier_saves_steam.sh) ; un jeu Auto-Cloud « Windows seulement » n'y gagne
# rien, le client ne resout pas ses racines. Rien non plus si le client est
# ferme (on ne l'ouvre pas ici), hors ligne ou pas connecte : on le dit, et le
# jeu part avec ce qu'il y a sur ce Mac. Cout quand tout est a jour : de l'ordre
# de la seconde. Jamais bloquant, rend toujours 0 ; ecrit une ligne
# `    saves: ...` (rien quand le jeu n'est pas concerne).
#
# CIDRE_SEANCE_STEAM=0 : jamais de seance (les essais). CIDRE_SEANCE_ATTENTE :
# l'attente maximale de la synchro, en secondes (20). Pour les essais aussi :
# CIDRE_OUTIL (la commande `cidre-outil`), CIDRE_CLOUD_LOG, et ce que lisent
# tests/lier_saves_steam.sh et tests/client_steam_natif.sh.
set -u
APPID=${1:-}
case $APPID in ''|*[!0-9]*) exit 0 ;; esac
[ "${CIDRE_SEANCE_STEAM:-1}" = 0 ] && exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
STEAM=${CIDRE_STEAM_DIR:-$HOME/Library/Application Support/Steam}
J=${CIDRE_CLOUD_LOG:-$STEAM/logs/cloud_log.txt}
ATTENTE=${CIDRE_SEANCE_ATTENTE:-20}

# le client sait-il synchroniser ce jeu sur macOS ?
case $(sh "$R/tests/lier_saves_steam.sh" "$APPID" mode 2>/dev/null) in api|lien) ;; *) exit 0 ;; esac
case $(sh "$R/tests/client_steam_natif.sh" 2>/dev/null) in
   connecte) ;;
   ouvert) echo "    saves: Steam Cloud : client Steam hors ligne, nuage non verifie : le jeu part avec les sauvegardes de ce Mac"; exit 0 ;;
   *) echo "    saves: Steam Cloud : client Steam ferme, nuage non verifie"; exit 0 ;;
esac
OUTIL=${CIDRE_OUTIL:-$R/build/cidre-outil}
if [ -z "${CIDRE_OUTIL:-}" ] && [ -f "$R/tests/cidre_outil.c" ] && { [ ! -x "$OUTIL" ] || [ "$R/tests/cidre_outil.c" -nt "$OUTIL" ]; }; then
   sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1 || true
fi

n0=$(wc -l <"$J" 2>/dev/null | tr -d ' '); n0=${n0:-0}
t0=$(date +%s)
s=$("$OUTIL" seance "$APPID" 2>/dev/null); rc=$?
case $rc in
   0) ;;
   3) echo "    saves: Steam Cloud : client Steam ferme, nuage non verifie"; exit 0 ;;
   *) echo "    saves: Steam Cloud : le client a refuse la seance ($(printf '%s\n' "$s" | sed -n 's/^detail=//p' | head -1)) : nuage non verifie"; exit 0 ;;
esac
case $s in *nuage_compte=0*|*nuage_jeu=0*)
   echo "    saves: Steam Cloud est coupe pour ce jeu ou ce compte (reglages de Steam) : nuage non verifie"; exit 0 ;;
esac

# La synchro de sortie que la seance vient de declencher : on attend sa fin
# (« YldWriteCacheDirectoryToFile » ou « Failed sync » pour ce jeu), au plus
# ATTENTE secondes. Ce qu'elle a fait se lit dans les memes lignes.
lire() {
   tail -n "+$((n0 + 1))" "$J" 2>/dev/null | LC_ALL=C awk -v a="[AppID $APPID]" '
      index($0, a) {
         if ($0 ~ /Starting sync/) debut = 1
         if (!debut) next
         if ($0 ~ /Download OK for file/) desc++
         if ($0 ~ /Upload OK for file/) env++
         if ($0 ~ /Failed sync/) echec = 1
         if ($0 ~ /[Cc]onflict/) conflit = 1
         if ($0 ~ /YldWriteCacheDirectoryToFile/ || echec) fin = 1
      }
      END { printf "%d %d %d %d %d\n", fin, desc, env, echec, conflit }'
}
set -- 0 0 0 0 0
while :; do
   set -- $(lire)
   [ "$1" -eq 1 ] && break
   [ $(( $(date +%s) - t0 )) -ge "$ATTENTE" ] && break
   sleep 0.2
done
d=$(( $(date +%s) - t0 ))
if [ "$1" -ne 1 ]; then echo "    saves: Steam Cloud : synchro pas finie apres ${d} s : le jeu part quand meme"
elif [ "$4" -eq 1 ]; then echo "    saves: Steam Cloud : synchro impossible (client hors ligne ?) : le jeu part avec les sauvegardes de ce Mac"
elif [ "$5" -eq 1 ]; then echo "    saves: Steam Cloud : le client signale un conflit (ouvrir Steam pour choisir la version a garder)"
elif [ "$2" -gt 0 ] || [ "$3" -gt 0 ]; then
   echo "    saves: Steam Cloud : $2 fichier(s) descendu(s) du nuage, $3 envoye(s), avant le lancement (${d} s)"
else echo "    saves: Steam Cloud : a jour avec le nuage (${d} s)"; fi
exit 0
