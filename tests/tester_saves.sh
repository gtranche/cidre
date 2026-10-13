#!/bin/sh
# Teste tests/deviner_saves.sh sur un faux prefixe et un faux dossier de jeu :
# la fiche quand elle designe un dossier qui existe, l'heuristique par moteur
# apres une partie, et les cas ou il faut se taire. Puis « Steam d'abord » :
# tests/lier_saves_steam.sh (lien du dossier du prefixe vers le dossier macOS
# que le jeu declare a Steam Cloud, sans rien perdre) et le dossier des copies
# de tests/sync_saves_steam.sh. Rien n'est lance, rien de reel n'est touche.
#   sh tests/tester_saves.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S="$R/tests/deviner_saves.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-saves.XXXXXX")
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
U="$T/users/joueur"; J="$T/jeu"
mkdir -p "$U/AppData/Local" "$U/AppData/LocalLow" "$U/AppData/Roaming" "$U/Documents" "$J"
export CIDRE_PREFIXE_UTIL="$U" CIDRE_JEU_DOSSIER="$J"
deviner() { # <fiche> [depuis]
   CIDRE_FICHE_SAUVEGARDES="$1" sh "$S" 1 ${2:+"$2"} 2>/dev/null
}
vieux() { touch -t 202601010000 "$1"; }   # un fichier d'avant la partie

echo "== fiche : dossier utilisateur qui existe"
mkdir -p "$U/AppData/Roaming/Studio/Jeu/saves"; vieux "$U/AppData/Roaming/Studio/Jeu/saves/a.sav"
verif "AppData/Roaming/..." "AppData/Roaming/Studio/Jeu/saves" "$(deviner 'AppData/Roaming/Studio/Jeu/saves/')"
verif "antislashs Windows" "AppData/Roaming/Studio/Jeu/saves" "$(deviner 'AppData\Roaming\Studio\Jeu\saves')"
verif "motif de fichiers tronque a son dossier" "AppData/Roaming/Studio/Jeu/saves" "$(deviner 'AppData/Roaming/Studio/Jeu/saves/*.sav')"
verif "plusieurs emplacements : le premier" "AppData/Roaming/Studio/Jeu/saves" "$(deviner 'AppData/Roaming/Studio/Jeu/saves/ ; steam:userdata/<uid>/1/remote/')"

echo "== fiche : dans le jeu"
mkdir -p "$J/profiles"; vieux "$J/profiles/p.dat"
verif "jeu:dossier" "jeu:profiles" "$(deviner 'jeu:profiles')"
verif "jeu:motif" "jeu:profiles" "$(deviner 'jeu:profiles/*.dat')"

echo "== fiche : pas un dossier, ou dossier absent"
verif "steam: ignore" "" "$(deviner 'steam:userdata/<uid>/1/remote/')"
verif "registre: ignore" "" "$(deviner 'registre:HKEY_CURRENT_USER/Software/X')"
verif "prose ignoree" "" "$(deviner 'No save data created')"
verif "dossier absent : on ne devine pas" "" "$(deviner 'AppData/Local/Inconnu/Saved/SaveGames')"
verif "aucune fiche" "" "$(deviner -)"

echo "== apres une partie : moteurs connus"
depuis=$(( $(date +%s) - 600 ))
mkdir -p "$U/AppData/Local/Sandfall/Saved/SaveGames/765" "$U/AppData/Local/Sandfall/Saved/Logs"
touch "$U/AppData/Local/Sandfall/Saved/SaveGames/765/slot1.sav"; touch "$U/AppData/Local/Sandfall/Saved/Logs/x.log"
verif "Unreal : AppData/Local/X/Saved/SaveGames" "AppData/Local/Sandfall/Saved/SaveGames" "$(deviner - $depuis)"
verif "sans « depuis », pas d'heuristique" "" "$(deviner -)"
mkdir -p "$U/AppData/LocalLow/Dev/Unity Jeu"; touch "$U/AppData/LocalLow/Dev/Unity Jeu/save.json"
verif "deux candidats : le plus recent" "AppData/LocalLow/Dev/Unity Jeu" "$(deviner - $depuis)"
echo "== apres une partie : les vieux dossiers ne comptent pas"
rm -rf "$U/AppData/LocalLow/Dev" "$U/AppData/Local/Sandfall"
mkdir -p "$U/Documents/My Games/Vieux"; vieux "$U/Documents/My Games/Vieux/s.sav"
verif "rien de modifie depuis la partie" "" "$(deviner - $depuis)"
echo "== apres une partie : dans le jeu"
mkdir -p "$J/save"; touch "$J/save/slot.sav"
verif "jeu:save" "jeu:save" "$(deviner - $depuis)"
echo "== la fiche passe avant l'heuristique"
verif "fiche d'abord" "jeu:profiles" "$(deviner 'jeu:profiles' $depuis)"

echo "== la fiche Steam Cloud (dossier_windows) passe avant PCGamingWiki"
mkdir -p "$U/AppData/Local/Studio/Saved/SaveGames"; vieux "$U/AppData/Local/Studio/Saved/SaveGames/a.sav"
verif "le premier dossier declare qui existe" "AppData/Local/Studio/Saved/SaveGames" \
   "$(CIDRE_FICHE_DOSSIERS_STEAM='AppData/Local/Absent ; AppData/Local/Studio/Saved/SaveGames' deviner 'jeu:profiles')"
verif "aucun n'existe : PCGamingWiki" "jeu:profiles" "$(CIDRE_FICHE_DOSSIERS_STEAM='AppData/Local/Absent' deviner 'jeu:profiles')"

# ------------------------------------------------------------------------------
# Steam d'abord : tests/lier_saves_steam.sh (liens vers le dossier macOS declare)
# et ce qu'en fait tests/sync_saves_steam.sh. Faux prefixe, faux dossier
# personnel, faux journal du client.
L="$R/tests/lier_saves_steam.sh"; Y="$R/tests/sync_saves_steam.sh"
M="$T/maison"; C="$T/cidre"; mkdir -p "$M" "$C"
export CIDRE_MAISON="$M" CIDRE_DIR="$C" CIDRE_STEAMID=76561198043440982
TABU=$(printf '\t')
lier() { CIDRE_FICHE_STEAM_CLOUD="$1" sh "$L" 7 "${2:-mode}" ${3:+"$3"} 2>&1; }
PEAK="steam-lien${TABU}AppData/LocalLow/LandCrab/PEAK => Library/Application Support/unity.LandCrab.PEAK"

echo "== Steam : le mode d'apres la fiche"
verif "API Remote Storage" "api" "$(lier steam-api)"
verif "dossier macOS declare : lien" "lien" "$(lier "$PEAK")"
verif "Windows seulement : pas Steam" "" "$(lier copie)"
verif "aucune fiche" "" "$(lier -)"
verif "lien sans liens : pas Steam" "" "$(lier steam-lien)"
verif "CIDRE_SAVES_STEAM=0 : pas Steam" "" "$(CIDRE_SAVES_STEAM=0 lier steam-api)"
verif "chemin qui remonte (..) refuse" "" "$(lier "steam-lien${TABU}AppData/../../x => Library/y")"
verif "variable inconnue refusee" "" "$(lier "steam-lien${TABU}AppData/Local/{Autre} => Library/y")"
verif "compte inconnu : pas de lien" "" "$(CIDRE_STEAMID= HOME="$T/sans-steam" lier "steam-lien${TABU}AppData/Local/X/{64BitSteamID} => Library/X/{64BitSteamID}")"
verif "variables du compte resolues" "$U/AppData/Local/X/76561198043440982/83175254${TABU}$M/Library/X/83175254" \
   "$(lier "steam-lien${TABU}AppData/Local/X/{64BitSteamID}/{Steam3AccountID} => Library/X/{Steam3AccountID}" dossiers)"

echo "== Steam : poser le lien, sans rien perdre"
W="$U/AppData/LocalLow/LandCrab/PEAK"; MAC="$M/Library/Application Support/unity.LandCrab.PEAK"
mkdir -p "$W/sous" "$MAC"
echo windows >"$W/quicksave.peak"; echo seul >"$W/sous/b.peak"; echo journal >"$W/Player.log"
echo macos >"$MAC/quicksave.peak"; echo natif >"$MAC/natif.peak"
sortie=$(lier "$PEAK" lier); rc=$?
verif "lier rend 0" "0" "$rc"
verif "le dossier du prefixe est un lien vers le dossier macOS" "$MAC" "$(readlink "$W")"
verif "fichier absent cote macOS : repris" "seul" "$(cat "$MAC/sous/b.peak")"
verif "fichier deja la cote macOS : jamais ecrase" "macos" "$(cat "$MAC/quicksave.peak")"
verif "le fichier propre a macOS reste" "natif" "$(cat "$MAC/natif.peak")"
H=$(ls -d "$C/saves/7/.history/avant-lien-"* 2>/dev/null | head -1)
verif "dossier d'origine range entier" "windows" "$(cat "$H/0/quicksave.peak" 2>/dev/null)"
verif "son emplacement d'origine est note" "$W" "$(cat "$H/0.origine" 2>/dev/null)"
verif "copie de precaution du dossier macOS d'avant" "macos" "$(cat "$H/0.macos/quicksave.peak" 2>/dev/null)"
verif "le fichier non repris est signale" "1" "$(printf '%s\n' "$sortie" | grep -c 'differe')"
verif "a travers le lien, le jeu voit le dossier macOS" "natif" "$(cat "$W/natif.peak")"
lier "$PEAK" lier >/dev/null; rc=$?
verif "second passage : rien a faire, 0" "0" "$rc"
verif "second passage : pas de nouvelle copie" "1" "$(ls -d "$C/saves/7/.history/avant-lien-"* | wc -l | tr -d ' ')"
rm "$W"; ln -s "$T/ailleurs" "$W"
lier "$PEAK" lier >/dev/null; rc=$?
verif "lien vers autre chose : laisse, 1" "1 $T/ailleurs" "$rc $(readlink "$W")"
rm "$W"
lier "$PEAK" lier >/dev/null
verif "dossier absent du prefixe : lien cree" "$MAC" "$(readlink "$W")"

echo "== Steam : ce que rend la synchro"
synchro() { CIDRE_FICHE_STEAM_CLOUD="$1" sh "$Y" 7 "$2" 2>&1; }
e=$(synchro "$PEAK" etat)
verif "etat : steam, lien en place" '"etat":"steam","steam":"lien","lie":true' "$(printf '%s' "$e" | sed -n 's/.*\("etat":"steam","steam":"lien","lie":true\).*/\1/p')"
verif "etat : le dossier est celui de macOS" "1" "$(printf '%s' "$e" | grep -c "\"dossier\":\"$MAC\"")"
verif "etat : fichiers comptes" '"fichiers":4' "$(printf '%s' "$e" | sed -n 's/.*"local":{\("fichiers":[0-9]*\).*/\1/p')"
verif "API : etat steam, sans lien" '"steam":"api","lie":null' "$(synchro steam-api etat | sed -n 's/.*\("steam":"api","lie":null\).*/\1/p')"
champ() { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p'; }
verif "synchro : steam_macos (lien)" "steam_macos" "$(printf '%s' "$e" | champ synchro)"
verif "synchro_detail : une phrase" "1" "$(printf '%s' "$e" | champ synchro_detail | grep -c 'Steam Cloud : dossier lié')"
verif "synchro : steam_api" "steam_api" "$(synchro steam-api etat | champ synchro)"
verif "synchro : aucune (dossier inconnu), configure reste faux" 'false aucune' \
   "$(synchro copie etat | sed -n 's/.*"configure":\(false\).*/\1/p') $(synchro copie etat | champ synchro)"
verif "restore : Cidre ne copie rien" "0" "$(synchro "$PEAK" restore | grep -c 'restore ')"
synchro "$PEAK" restore >/dev/null
verif "aucune copie Cidre creee" "" "$(ls "$C/saves/7" 2>/dev/null | grep -v '^\.history$')"

# API + dossier local designe par saves.conf : la copie Cidre continue, en plus
printf '7\tAppData/Roaming/Studio/Jeu/saves\n' >"$C/saves.conf"
mkdir -p "$T/pfx/drive_c"; ln -s "$T/users" "$T/pfx/drive_c/users"; export WINEPREFIX="$T/pfx"
e=$(synchro steam-api etat)
verif "API + ligne saves.conf : etat de la copie, steam=api" '"etat":"jamais_sauvegarde","steam":"api"' \
   "$(printf '%s' "$e" | sed -n 's/.*\("etat":"jamais_sauvegarde","steam":"api"\).*/\1/p')"
verif "API + ligne : synchro steam_api, et le dossier de la copie est donne" "steam_api $C/saves/7" "$(printf '%s' "$e" | champ synchro) $(printf '%s' "$e" | champ copie)"
verif "Windows seulement + ligne : synchro copie" "copie" "$(synchro copie etat | champ synchro)"
synchro steam-api backup >/dev/null
verif "API + ligne saves.conf : le dossier local est copie" "1" "$(ls "$C/saves/7/a.sav" 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$C/saves/7/a.sav" "$C/saves.conf"
synchro steam-api backup >/dev/null
verif "API sans ligne : rien n'est copie, rien n'est devine" "0" "$(ls "$C/saves/7/a.sav" "$C/saves.conf" 2>/dev/null | wc -l | tr -d ' ')"

echo "== Steam : le compte rendu d'envoi, lu dans le journal du client"
J="$T/cloud_log.txt"; export CIDRE_CLOUD_LOG="$J" CIDRE_ENVOI_ATTENTE=0
avant=$(date -v-1H '+%Y-%m-%d %H:%M:%S'); apres=$(date -v+1M '+%Y-%m-%d %H:%M:%S'); debut=$(date +%s)
cat >"$J" <<FIN
[$avant] [AppID 7] Starting sync (up,AC Exit,)
[$avant] [AppID 7] Upload OK for file vieux.peak
[$avant] [AppID 7] Upload complete, result OK
[$apres] [AppID 70] Starting sync (up,AC Exit,)
[$apres] [AppID 70] Upload OK for file autre-jeu.peak
FIN
verif "pas de synchro depuis le lancement : dit" "1" "$(lier "$PEAK" envoi $debut | grep -c "n'a pas synchronise")"
cat >>"$J" <<FIN
[$apres] [AppID 7] Starting sync (up,AC Exit,)
[$apres] [AppID 7] Need to upload file unity.LandCrab.PEAK/quicksave.peak
[$apres] [AppID 7] Upload OK for file unity.LandCrab.PEAK/quicksave.peak
[$apres] [AppID 7] Upload OK for file unity.LandCrab.PEAK/sous/b.peak
[$apres] [AppID 7] Upload complete, result OK
FIN
verif "deux fichiers envoyes" "1" "$(lier "$PEAK" envoi $debut | grep -c '2 fichier(s) envoye(s)')"
verif "backup : rend le compte rendu du client" "1" "$(CIDRE_SAVES_DEPUIS=$debut synchro "$PEAK" backup | grep -c '2 fichier(s) envoye(s)')"
cat >"$J" <<FIN
[$apres] [AppID 7] Starting sync (up,AC Exit,)
[$apres] [AppID 7] Upload complete in build list
FIN
verif "rien de neuf" "1" "$(lier "$PEAK" envoi $debut | grep -c 'rien de neuf')"

echo "== copie Cidre : le dossier par defaut est sur ce Mac, iCloud au choix"
dossier() { sh "$Y" - dossier; }
verif "defaut : <Cidre>/saves" "$C/saves" "$(dossier)"
echo "$T/choisi" >"$C/saves.dossier"
verif "choix de l'utilisateur (saves.dossier)" "$T/choisi" "$(dossier)"
verif "CIDRE_SAVES_DIR passe avant" "$T/env" "$(CIDRE_SAVES_DIR="$T/env" dossier)"
rm "$C/saves.dossier"
# un jeu Windows seulement : la copie va dans le dossier par defaut, et ce qui
# etait dans iCloud Drive (ancien defaut) y est repris une fois
FH="$T/foyer"; IC="$FH/Library/Mobile Documents/com~apple~CloudDocs/CidreSaves/7"
mkdir -p "$IC" "$FH/Library/Application Support"; echo ancien >"$IC/vieux.sav"
printf '7\tAppData/Roaming/Studio/Jeu/saves\n' >"$C/saves.conf"
s=$(HOME="$FH" CIDRE_FICHE_STEAM_CLOUD=copie sh "$Y" 7 backup 2>&1)
verif "copie dans le dossier par defaut" "1" "$(ls "$C/saves/7/a.sav" 2>/dev/null | wc -l | tr -d ' ')"
verif "copies d'iCloud reprises une fois" "ancien" "$(cat "$C/saves/7/vieux.sav" 2>/dev/null)"
verif "rien n'est retire d'iCloud" "ancien" "$(cat "$IC/vieux.sav")"
verif "le journal ne parle plus d'iCloud" "0" "$(printf '%s\n' "$s" | grep -c -- '-> iCloud')"
verif "etat : pas dans iCloud" '"icloud":false' "$(HOME="$FH" CIDRE_FICHE_STEAM_CLOUD=copie sh "$Y" 7 etat | sed -n 's/.*\("icloud":false\).*/\1/p')"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
