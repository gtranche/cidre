#!/bin/sh
# Les sauvegardes des jeux Windows lances par Cidre.
#
# Steam d'abord, quand il peut (tests/lier_saves_steam.sh, d'apres la fiche du
# jeu) : le client Steam de macOS synchronise lui-meme ce que le jeu ecrit par
# l'API Remote Storage (par le pont) et les dossiers Auto-Cloud que le jeu
# declare pour macOS (le dossier du prefixe y est lie). Cidre ne copie alors
# rien.
# Le reste -- Auto-Cloud declare pour Windows seulement : le client macOS ne
# sait pas resoudre une racine Windows -- est copie par Cidre vers un dossier
# de ce Mac : ~/Library/Application Support/Cidre/saves par defaut, ou celui
# que choisit `cidre saves dossier <chemin>` (iCloud Drive, par exemple), ou
# CIDRE_SAVES_DIR. Mode DOSSIER : tout le dossier du jeu sauf le superflu.
# JAMAIS destructif : copie horodatee en .history/ avant toute ecriture. Non
# bloquant.
# STEAM D'ABORD : ce que Steam Cloud synchronise a toujours la priorite. La
# copie de Cidre (sur ce Mac ou dans iCloud) n'est jamais restauree dans le
# stockage de l'API de Steam ni dans un dossier lie a celui que Steam
# synchronise -- y compris quand le jeu retombe en copie Cidre alors que le
# lien est deja pose (fiche absente du cache, CIDRE_SAVES_STEAM=0).
#
#   sync_saves_steam.sh <id> <restore|backup>
#   sync_saves_steam.sh <id> etat        ou en est la synchro, en JSON
#        "synchro" dit QUI synchronise, a valeurs stables (c'est ce qu'affiche
#        Verger) : "steam_api" (le jeu ecrit par l'API Remote Storage, par le
#        pont : Steam s'en charge), "steam_macos" (dossier lie a celui que le jeu
#        declare pour macOS : le client Steam s'en charge), "copie" (Cidre copie
#        vers le dossier "copie"), "aucune" (dossier inconnu : rien n'est
#        synchronise) ; "synchro_detail" le dit en une phrase. "copie" non vide
#        avec "steam_api" : Cidre copie EN PLUS le dossier local "dossier".
#        "reprise" : ce que `cidre import` a ramene de la bouteille d'ou vient
#        le jeu (tests/reprendre_saves_bouteille.sh : "etat", "fichiers",
#        "depuis", "vers", "message"...), ou null.
#   sync_saves_steam.sh - dossier        le dossier des copies
#
# Ou sont les sauvegardes d'un jeu : outil-steam/saves.conf (livre), surcharge
# par ~/Library/Application Support/Cidre/saves.conf (`cidre saves set`).
set -u
APPID=${1:-}; SENS=${2:-}
[ -n "$APPID" ] && [ -n "$SENS" ] || exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
# un jeu Battle.net vit dans le prefixe de Battle.net (tests/battlenet.sh)
case $APPID in bnet-*) PFX=$(sh "$R/tests/battlenet.sh" prefixe) ;; esac
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
# Le dossier des copies : la variable, sinon le choix de l'utilisateur (`cidre
# saves dossier`), sinon un dossier de ce Mac. iCloud n'est plus le defaut.
DEST=${CIDRE_SAVES_DIR:-}
[ -n "$DEST" ] || DEST=$(head -1 "$CIDRE_DIR/saves.dossier" 2>/dev/null)
DEFAUT=non; [ -n "$DEST" ] || { DEST="$CIDRE_DIR/saves"; DEFAUT=oui; }
[ "$SENS" = dossier ] && { printf '%s\n' "$DEST"; exit 0; }
json() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
# ce que `cidre import` a ramene de la bouteille d'origine : un objet, ou null
reprise() {
   r=$(head -1 "$CIDRE_DIR/reprises.saves/$APPID.json" 2>/dev/null)
   case $r in '{'*'}') printf '%s' "$r" ;; *) printf null ;; esac
}

# --- Steam synchronise-t-il ce jeu lui-meme ? ---------------------------------
STEAM_MODE=$(sh "$R/tests/lier_saves_steam.sh" "$APPID" mode 2>/dev/null || true)
if [ "$STEAM_MODE" = lien ] && [ "$SENS" != etat ]; then
   # Le lien se pose (ou se verifie) avant chaque lancement et apres : s'il ne
   # peut pas l'etre, la copie Cidre reprend la main.
   sh "$R/tests/lier_saves_steam.sh" "$APPID" lier || STEAM_MODE=
fi
# Par l'API, Steam ne synchronise que ce que le jeu lui confie : un dossier de
# sauvegardes locales designe par saves.conf (Vermintide 2 : tout est local en
# Modded Realm) reste copie par Cidre, en plus. Sans ligne, on ne devine rien.
LIGNE=$(cat "$CIDRE_DIR/saves.conf" "$R/outil-steam/saves.conf" 2>/dev/null \
        | awk -F'\t' -v a="$APPID" '$1==a {print $2; exit}')
STEAM_ET_COPIE=
if [ "$STEAM_MODE" = api ] && [ -n "$LIGNE" ]; then
   STEAM_ET_COPIE=api; STEAM_MODE=
   [ "$SENS" = restore ] && echo "    saves: Steam Cloud pour ce que le jeu ecrit par l'API ; copie Cidre du dossier $LIGNE"
fi
if [ -n "$STEAM_MODE" ]; then
   case $SENS in
      restore)
         [ $STEAM_MODE = api ] && echo "    saves: Steam Cloud (le jeu ecrit par l'API Remote Storage, le client Steam synchronise)" \
                               || echo "    saves: Steam Cloud (dossier lie a celui que le jeu declare pour macOS)" ;;
      backup)
         sh "$R/tests/lier_saves_steam.sh" "$APPID" envoi "${CIDRE_SAVES_DEPUIS:-}" ;;
      etat)
         d=
         if [ $STEAM_MODE = lien ]; then
            d=$(sh "$R/tests/lier_saves_steam.sh" "$APPID" dossiers 2>/dev/null | head -1 | cut -f2)
            lie=true; sh "$R/tests/lier_saves_steam.sh" "$APPID" dossiers 2>/dev/null | while IFS="$(printf '\t')" read -r a b; do
               [ -L "$a" ] && [ "$(readlink "$a")" = "$b" ] || exit 1; done || lie=false
         else
            d=$(ls -d "$HOME/Library/Application Support/Steam/userdata/"*"/$APPID/remote" 2>/dev/null | head -1); lie=null
         fi
         set -- 0 0 0
         [ -n "$d" ] && [ -d "$d" ] && set -- $(find "$d" -type f 2>/dev/null | while IFS= read -r f; do stat -f '%m %z' "$f"; done \
            | awk '{ n++; o += $2; if ($1 > m) m = $1 } END { printf "%d %d %d\n", n, o, m }')
         printf '{"id":"%s","configure":true,"etat":"steam","steam":"%s","lie":%s,"dossier":%s,"copie":"","icloud":false,' \
            "$APPID" "$STEAM_MODE" "$lie" "$(json "$d")"
         printf '"local":{"fichiers":%s,"octets":%s,"modifie":%s},"sauvegarde":{"fichiers":0,"octets":0,"modifie":0},' "$1" "$2" "$3"
         if [ $STEAM_MODE = api ]; then sy=steam_api; sd="Steam Cloud : le jeu écrit par l'API de Steam, le client Steam synchronise"
         elif [ $lie = true ]; then sy=steam_macos; sd="Steam Cloud : dossier lié à celui que le jeu déclare pour macOS, le client Steam synchronise"
         else sy=steam_macos; sd="Steam Cloud : le dossier sera lié au prochain lancement à celui que le jeu déclare pour macOS"; fi
         printf '"a_sauvegarder":0,"a_restaurer":0,"historique":%s,"synchro":"%s","synchro_detail":%s,"reprise":%s}\n' \
            "$(ls "$DEST/$APPID/.history" 2>/dev/null | wc -l | tr -d ' ')" "$sy" "$(json "$sd")" "$(reprise)" ;;
   esac
   exit 0
fi
JUNK='/cache/|/logs/|/crash|dumps/|image_cache/|/shader|PopsFeed|PopsMods|EarlyCrashReports|/Temp/|\.log$'
MAXSZ=104857600   # 100 Mo : au-dela ce n'est pas une sauvegarde

# La ligne du jeu : celle de l'utilisateur passe avant celle qu'on livre.
reldir=$LIGNE
non_configure() {
   [ "$SENS" = etat ] && printf '{"id":"%s","configure":false,"synchro":"aucune","synchro_detail":%s,"reprise":%s}\n' "$APPID" \
      "$(json "Dossier de sauvegarde inconnu : rien n'est synchronisé (cidre saves set pour le désigner)")" "$(reprise)"
   exit 0
}
# Aucune ligne : on essaie de deviner (la fiche de la base de profils ; apres
# une partie, CIDRE_SAVES_DEPUIS = date de lancement en secondes, les dossiers
# que les moteurs connus viennent d'ecrire). Trouve : memorise dans le
# saves.conf de l'utilisateur (`cidre saves unset` l'oublie), pour que Verger
# n'ait pas a demander.
if [ -z "$reldir" ]; then
   reldir=$(sh "$R/tests/deviner_saves.sh" "$APPID" ${CIDRE_SAVES_DEPUIS:+"$CIDRE_SAVES_DEPUIS"} 2>/dev/null || true)
   if [ -n "$reldir" ]; then
      mkdir -p "$CIDRE_DIR"; touch "$CIDRE_DIR/saves.conf"
      awk -F'\t' -v i="$APPID" '$1!=i' "$CIDRE_DIR/saves.conf" >"$CIDRE_DIR/saves.conf.tmp"
      printf '%s\t%s\n' "$APPID" "$reldir" >>"$CIDRE_DIR/saves.conf.tmp"
      mv "$CIDRE_DIR/saves.conf.tmp" "$CIDRE_DIR/saves.conf"
      [ "$SENS" = etat ] || echo "    sauvegardes : dossier trouve tout seul : $reldir (cidre saves unset $APPID pour l'oublier)"
   fi
fi
[ -n "$reldir" ] || non_configure

# Le dossier des sauvegardes : sous le dossier utilisateur du prefixe Wine, ou
# (`jeu:`) dans le dossier du jeu lui-meme -- certains jeux y rangent leurs saves.
case $reldir in
   jeu:*)
      racine=$(sh "$R/cidre" chemin "$APPID" 2>/dev/null)
      [ -n "$racine" ] || non_configure
      SRC="$racine/${reldir#jeu:}" ;;
   *)
      UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
      [ -n "$UH" ] || non_configure
      SRC="$(dirname "$UH")/$reldir" ;;
esac
BAK="$DEST/$APPID"

# liste des fichiers "save" sous un dossier (exclut le superflu et les gros)
lister() { # <racine>
   find -H "$1" -type f 2>/dev/null | grep -avE "$JUNK" | while IFS= read -r f; do
      sz=$(wc -c <"$f" 2>/dev/null || echo 0)
      [ "$sz" -le "$MAXSZ" ] && printf '%s\n' "$f"
   done
}
copie() { # <src> <dst> : archive l'ancien dst s'il differe, puis copie
   [ -f "$1" ] || return 0
   if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
      h="$3/$(dirname "${2#$4/}")"; mkdir -p "$h" 2>/dev/null && cp -p "$2" "$h/" 2>/dev/null
   fi
   mkdir -p "$(dirname "$2")" 2>/dev/null && cp -p "$1" "$2" 2>/dev/null
}

# Le defaut etait iCloud Drive (CidreSaves) jusqu'a la v1.5.8 : ce qui s'y
# trouve pour ce jeu est repris une fois dans le nouveau dossier. Rien n'est
# retire d'iCloud.
if [ $DEFAUT = oui ] && [ -z "$(ls "$BAK" 2>/dev/null)" ] && [ -d "$ICLOUD/CidreSaves/$APPID" ] && [ "$SENS" != etat ]; then
   mkdir -p "$BAK" && cp -Rp "$ICLOUD/CidreSaves/$APPID/." "$BAK/" 2>/dev/null \
      && echo "    saves: copies reprises d'iCloud Drive dans $BAK (celles d'iCloud restent en place)"
fi

TS=$(date '+%Y%m%d-%H%M%S')
case "$SENS" in
   backup)
      [ -d "$SRC" ] || exit 0
      lister "$SRC" | while IFS= read -r f; do
         copie "$f" "$BAK/${f#$SRC/}" "$BAK/.history/cloud-$TS" "$BAK"
      done
      echo "    saves: backup $APPID -> $BAK"
      [ -z "$STEAM_ET_COPIE" ] || sh "$R/tests/lier_saves_steam.sh" "$APPID" envoi "${CIDRE_SAVES_DEPUIS:-}" ;;
   restore)
      [ -d "$BAK" ] || exit 0
      # Steam d'abord : un dossier du prefixe qui est un lien pose par
      # lier_saves_steam.sh (lui, ou un de ses parents ; pas les dossiers de
      # premier niveau, Documents ou Bureau, que Wine lie au Mac) est celui que
      # Steam synchronise. La copie de Cidre n'y remplace rien.
      case $reldir in jeu:*) ;; *)
         p=$SRC; base=$(dirname "$UH")
         while [ "$p" != / ] && [ "$p" != "$base" ] && [ "$(dirname "$p")" != "$base" ]; do
            if [ -L "$p" ]; then
               echo "    saves: $SRC est lie a un dossier que Steam Cloud synchronise : la copie de Cidre n'y est pas restauree (Steam a la priorite)"
               exit 0
            fi
            p=$(dirname "$p")
         done ;;
      esac
      find "$BAK" -type f 2>/dev/null | grep -av "/.history/" | while IFS= read -r dst; do
         rel=${dst#$BAK/}; loc="$SRC/$rel"
         if [ ! -f "$loc" ] || [ "$dst" -nt "$loc" ]; then
            copie "$dst" "$loc" "$BAK/.history/local-$TS" "$SRC"
            echo "    saves: restore $rel"
         fi
      done ;;
   etat)
      # Compare les deux cotes, fichier par fichier. Un fichier absent de la
      # copie, ou different et plus recent en local, est « a sauvegarder » ;
      # absent en local, ou different et plus recent dans la copie, « a restaurer ».
      T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
      : >"$T/local"; : >"$T/copie"
      [ -d "$SRC" ] && lister "$SRC" >"$T/local"
      [ -d "$BAK" ] && find "$BAK" -type f 2>/dev/null | grep -av "/.history/" >"$T/copie"
      nl=0; ol=0; ml=0; nc=0; oc=0; mc=0; as=0; ar=0
      while IFS= read -r f; do
         set -- $(stat -f '%m %z' "$f" 2>/dev/null); [ $# -eq 2 ] || continue
         nl=$((nl + 1)); ol=$((ol + $2)); [ "$1" -gt "$ml" ] && ml=$1
         b="$BAK/${f#$SRC/}"
         if [ ! -f "$b" ]; then as=$((as + 1))
         elif ! cmp -s "$f" "$b"; then
            if [ "$(stat -f %m "$b")" -gt "$1" ]; then ar=$((ar + 1)); else as=$((as + 1)); fi
         fi
      done <"$T/local"
      while IFS= read -r b; do
         set -- $(stat -f '%m %z' "$b" 2>/dev/null); [ $# -eq 2 ] || continue
         nc=$((nc + 1)); oc=$((oc + $2)); [ "$1" -gt "$mc" ] && mc=$1
         [ -f "$SRC/${b#$BAK/}" ] || ar=$((ar + 1))
      done <"$T/copie"
      if   [ $nl -eq 0 ] && [ $nc -eq 0 ]; then e=vide
      elif [ $nc -eq 0 ]; then e=jamais_sauvegarde
      elif [ $as -gt 0 ] && [ $ar -gt 0 ]; then e=divergent
      elif [ $as -gt 0 ]; then e=a_sauvegarder
      elif [ $ar -gt 0 ]; then e=a_restaurer
      else e=a_jour; fi
      h=$(ls "$BAK/.history" 2>/dev/null | wc -l | tr -d ' ')
      # la copie part-elle vraiment sur iCloud ?
      ic=false; case $DEST in "$ICLOUD"/*) [ -d "$ICLOUD" ] && ic=true ;; esac
      printf '{"id":"%s","configure":true,"etat":"%s","steam":"%s","dossier":%s,"copie":%s,"icloud":%s,' \
         "$APPID" "$e" "$STEAM_ET_COPIE" "$(json "$SRC")" "$(json "$BAK")" "$ic"
      printf '"local":{"fichiers":%s,"octets":%s,"modifie":%s},"sauvegarde":{"fichiers":%s,"octets":%s,"modifie":%s},' \
         "$nl" "$ol" "$ml" "$nc" "$oc" "$mc"
      [ $ic = true ] && ou="dans iCloud Drive" || ou="dans un dossier de ce Mac"
      if [ -n "$STEAM_ET_COPIE" ]; then sy=steam_api; sd="Steam Cloud pour ce que le jeu écrit par l'API de Steam ; Cidre copie en plus son dossier local $ou"
      else sy=copie; sd="Copie Cidre $ou (Steam Cloud ne sait pas synchroniser ce jeu sur macOS)"; fi
      printf '"a_sauvegarder":%s,"a_restaurer":%s,"historique":%s,"synchro":"%s","synchro_detail":%s,"reprise":%s}\n' "$as" "$ar" "$h" "$sy" "$(json "$sd")" "$(reprise)" ;;
esac
exit 0
