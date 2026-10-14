#!/bin/sh
# Avant de lancer un jeu par Cidre : verifier que sa fin de partie ne fera pas
# RETIRER du nuage Steam des sauvegardes que ce Mac a perdues.
#
# A la sortie d'un jeu lance par Cidre, le client Steam de macOS fait sa synchro
# « up,AC Exit » sans trace du lancement (« No launch record found »). Ses
# regles Auto-Cloud y comparent les fichiers que remotecache.vdf dit presents
# sur ce Mac a ceux qu'elles y trouvent ; un fichier note synchronise et absent
# du disque est retire du nuage (« no longer matches any patterns (2). Removing
# from cloud »). Ne pas lier le dossier n'y change rien : le client surveille
# le dossier macOS du jeu de toute facon. Un fichier encore a descendre
# (syncstate 2) est epargne par le client lui-meme (« file has pending changes
# in cloud; ignoring forget », Blasphemous le 2026-10-14) ; le danger est un
# fichier SYNCHRONISE (syncstate 1), de notre plateforme, absent du disque.
#
#   garde_nuage_steam.sh <appid> [--accord]
#
# Pour chacun de ces fichiers :
#   - une copie identique (meme SHA-1 que celle que Steam a dans le nuage) est
#     dans l'historique ou la copie de Cidre (<copies>/<appid>/) : elle est
#     remise a sa place -- c'est exactement la version du nuage, rien ne
#     change la-haut ;
#   - sinon : on refuse le lancement (code 1) et on dit lesquels, ou ils sont
#     encore (le nuage), et comment passer outre. --accord (`cidre play <id>
#     --accord-nuage`) : on lance quand meme, en le disant -- le client les
#     retirera du nuage a la sortie.
# Rien a dire quand tout va bien. Les fichiers de l'API de Steam (racine 0)
# ne relevent d'aucune regle : non concernes.
#
# Pour les essais : CIDRE_STEAM_DIR (le dossier du client), CIDRE_MAISON (le
# dossier personnel ou sont les racines macOS), CIDRE_JEU_DOSSIER.
set -u
APPID=${1:-}; ACCORD=non; [ "${2:-}" = --accord ] && ACCORD=oui
case $APPID in ''|*[!0-9]*) exit 0 ;; esac
R=$(cd "$(dirname "$0")/.." && pwd)
STEAM=${CIDRE_STEAM_DIR:-$HOME/Library/Application Support/Steam}
MAISON=${CIDRE_MAISON:-$HOME}
TAB=$(printf '\t')
COPIES=$(sh "$R/tests/sync_saves_steam.sh" - dossier 2>/dev/null)
JEUDIR=${CIDRE_JEU_DOSSIER:-}
[ -n "$JEUDIR" ] || JEUDIR=$(sh "$R/cidre" chemin "$APPID" 2>/dev/null || true)

# Les fichiers a surveiller : racine autre que 0 (l'API), synchronises
# (syncstate 1), conserves (persiststate 0), de notre plateforme
# (platformstosync2 : -1 = toutes, sinon le bit 2 = macOS).
LISTE=$(mktemp "${TMPDIR:-/tmp}/garde-nuage.XXXXXX") || exit 0
trap 'rm -f "$LISTE" "$LISTE.m"' EXIT
for c in "$STEAM/userdata"/*/"$APPID"/remotecache.vdf; do
   [ -f "$c" ] || continue
   LC_ALL=C awk -F'"' '
      /^\t"/ && NF == 3 { nom = $2; r = ""; s = ""; p = "0"; pl = "-1"; sha = ""; next }
      $2 == "root" { r = $4 } $2 == "syncstate" { s = $4 } $2 == "persiststate" { p = $4 }
      $2 == "sha" { sha = $4 } $2 == "platformstosync2" { pl = $4 }
      /^\t\}/ { if (nom != "" && r != "" && r != "0" && s == "1" && p == "0" && (pl + 0 < 0 || int(pl / 2) % 2 == 1))
                   printf "%s\t%s\n", sha, nom
                nom = "" }' "$c"
done >"$LISTE"
[ -s "$LISTE" ] || exit 0

# Ou le client les cherche sur ce Mac : sous une racine macOS (le nom est
# relatif a la racine ; une racine Windows « surchargee » pour macOS garde le
# meme chemin relatif), ou dans le dossier du jeu.
present() { # <nom>
   for d in "$MAISON/Library/Application Support" "$MAISON" "$MAISON/Documents" "$MAISON/Library/Caches" "$MAISON/Library/Preferences" "${JEUDIR:-/nonexistent}"; do
      [ -e "$d/$1" ] && return 0
   done
   return 1
}
# Une copie identique a celle du nuage, dans ce que Cidre garde de ce jeu
copie_identique() { # <sha> <nom>
   [ -n "$COPIES" ] && [ -d "$COPIES/$APPID" ] || return 1
   b=$(basename "$2")
   find "$COPIES/$APPID" -type f -name "$b" 2>/dev/null | while IFS= read -r f; do
      [ "$(shasum -a 1 "$f" 2>/dev/null | cut -d' ' -f1)" = "$1" ] && { printf '%s\n' "$f"; break; }
   done
}
# La place ou le remettre : la racine macOS ou son dossier parent existe deja
# (sinon Application Support, la racine des sauvegardes macOS par defaut)
place() { # <nom>
   for d in "$MAISON/Library/Application Support" "$MAISON/Documents" "$MAISON"; do
      [ -d "$d/$(dirname "$1")" ] && { printf '%s\n' "$d/$1"; return; }
   done
   printf '%s\n' "$MAISON/Library/Application Support/$1"
}

remis=0; manquants=0
: >"$LISTE.m"
while IFS="$TAB" read -r sha nom; do
   present "$nom" && continue
   src=$(copie_identique "$sha" "$nom")
   if [ -n "$src" ]; then
      dst=$(place "$nom")
      if mkdir -p "$(dirname "$dst")" && cp -p "$src" "$dst"; then
         remis=$((remis + 1)); echo "    saves: Steam Cloud : $nom manquait sur ce Mac ; remis depuis la copie de Cidre (identique a celle du nuage)"
         continue
      fi
   fi
   manquants=$((manquants + 1)); printf '%s\n' "$nom" >>"$LISTE.m"
done <"$LISTE"
[ $manquants -eq 0 ] && exit 0

echo "    saves: Steam Cloud : $manquants sauvegarde(s) que Steam croit sur ce Mac n'y sont plus :"
sed 's/^/                 /' "$LISTE.m"
if [ $ACCORD = oui ]; then
   echo "    saves: lancement quand meme (--accord-nuage) : a la sortie du jeu, le client Steam les retirera du nuage"
   exit 0
fi
echo "    saves: a la sortie du jeu, le client Steam les retirerait du nuage : lancement arrete."
echo "           Elles y sont encore (page Steam Cloud du compte : store.steampowered.com/account/remotestorage) ;"
echo "           les remettre a leur place, ou lancer quand meme : cidre play $APPID --accord-nuage"
exit 1
