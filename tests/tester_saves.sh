#!/bin/sh
# Teste tests/deviner_saves.sh sur un faux prefixe et un faux dossier de jeu :
# la fiche quand elle designe un dossier qui existe, l'heuristique par moteur
# apres une partie, et les cas ou il faut se taire. Puis « Steam d'abord » :
# tests/lier_saves_steam.sh (lien du dossier du prefixe vers le dossier macOS
# que le jeu declare a Steam Cloud, sans rien perdre) et le dossier des copies
# de tests/sync_saves_steam.sh. Enfin les sauvegardes d'un jeu repris d'une
# bouteille (tests/reprendre_saves_bouteille.sh) : plus anciennes, plus recentes,
# absentes, jeu que Steam synchronise ; et la seance Steam qui fait descendre le
# nuage avant un lancement (tests/seance_steam_cloud.sh, avec un faux client).
# Rien n'est lance, rien de reel n'est touche.
#   sh tests/tester_saves.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S="$R/tests/deviner_saves.sh"
# jamais de vraie seance Steam pendant les essais (tests/seance_steam_cloud.sh)
export CIDRE_SEANCE_STEAM=0
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

# ------------------------------------------------------------------------------
# Les sauvegardes d'un jeu repris d'une bouteille CrossOver, Whisky ou Heroic :
# tests/reprendre_saves_bouteille.sh, sur une bouteille fabriquee (le parcours
# par `cidre import` est dans tests/tester_bouteilles.sh).
echo "== bouteille : les dossiers des moteurs, au nom du jeu seulement"
U2="$T/autre-prefixe/users/crossover"
mkdir -p "$U2/AppData/LocalLow/Dev/Jeu A" "$U2/AppData/LocalLow/Dev/Jeu B" "$U2/AppData/Local/Projet/Saved/SaveGames"
echo a >"$U2/AppData/LocalLow/Dev/Jeu A/s.sav"; vieux "$U2/AppData/LocalLow/Dev/Jeu A/s.sav"
echo b >"$U2/AppData/LocalLow/Dev/Jeu B/s.sav"
echo p >"$U2/AppData/Local/Projet/Saved/SaveGames/p.sav"; vieux "$U2/AppData/Local/Projet/Saved/SaveGames/p.sav"
nomme() { CIDRE_PREFIXE_UTIL="$U2" CIDRE_JEU_DOSSIER=/nonexistent CIDRE_DEVINER_NOMS="$1" CIDRE_FICHE_SAUVEGARDES=- CIDRE_FICHE_DOSSIERS_STEAM=- sh "$S" 1 1 2>/dev/null; }
verif "sans nom : le plus recent, quel que soit le jeu" "AppData/LocalLow/Dev/Jeu B" "$(nomme '')"
verif "au nom du jeu : son dossier, meme plus ancien" "AppData/LocalLow/Dev/Jeu A" "$(nomme 'Jeu A')"
verif "casse et ponctuation ignorees" "AppData/LocalLow/Dev/Jeu A" "$(nomme 'JEU-a!')"
verif "plusieurs noms (un par ligne) : projet Unreal" "AppData/Local/Projet/Saved/SaveGames" "$(nomme "$(printf 'Un Titre\nProjet')")"
verif "aucun dossier a ce nom : rien" "" "$(nomme 'Jeu C')"
verif "un nom de dossier generique ne designe rien" "" "$(nomme "$(printf 'Saved\nLocalLow\nSaveGames')")"
verif "un nom trop court ne designe rien" "" "$(nomme 'B')"

echo "== bouteille : ramener les sauvegardes sans rien perdre"
RS="$R/tests/reprendre_saves_bouteille.sh"
export CIDRE_BOUTEILLES_CROSSOVER= CIDRE_BOUTEILLES_WHISKY= CIDRE_WHISKY_REGISTRE= CIDRE_BOUTEILLES_HEROIC= CIDRE_HEROIC_CONFIG=
BT="$T/bouteille"; BU="$BT/drive_c/users/crossover"; mkdir -p "$BU/AppData/Roaming" "$BT/drive_c/users/steamuser/AppData/Roaming" "$BT/drive_c/users/Public"
repris() { # <appid> <nom> : un jeu du dossier Cidre, note comme repris de la bouteille
   mkdir -p "$C/games/$1/steamapps"
   printf '"AppState"\r\n{\r\n\t"appid"\t\t"%s"\r\n\t"name"\t\t"%s"\r\n\t"installdir"\t\t"Rep%s"\r\n}\r\n' "$1" "$2" "$1" >"$C/games/$1/steamapps/appmanifest_$1.acf"
   printf '%s\tcrossover\tEssai\t%s\tclone\t0\n' "$1" "$BT" >>"$C/reprises.conf"
}
# avec la fiche Steam Cloud $FICHE (aucune par defaut) ; le compte rendu dans rs.err
ramener() { CIDRE_FICHE_STEAM_CLOUD="${FICHE:--}" CIDRE_FICHE_SAUVEGARDES=- CIDRE_FICHE_DOSSIERS_STEAM=- sh "$RS" "$@" --json 2>"$T/rs.err"; }
cj() { printf '%s' "$2" | sed -n 's/.*"'"$1"'":"\{0,1\}\([^",}]*\).*/\1/p'; }
cliche() { (cd "$1" && find . -exec stat -f '%i %z %m %N' {} + | sort); }
rm -f "$C/saves.conf"
# 9101 : cote Cidre, un fichier plus ancien, un plus recent, un identique, un absent ; du superflu
repris 9101 "Jeu 91"
S91="$BU/AppData/Roaming/Jeu91"; C91="$U/AppData/Roaming/Jeu91"; mkdir -p "$S91/cache" "$S91/sous" "$C91"
for f in a b c; do echo "bouteille $f" >"$S91/$f.sav"; done; echo "bouteille d" >"$S91/sous/d.sav"
echo journal >"$S91/jeu.log"; echo cache >"$S91/cache/x.bin"; mkfile -n 101m "$S91/enorme.bin"
touch -t 202606010000 "$S91"/*.sav "$S91/sous/d.sav"
echo "cidre ancien" >"$C91/a.sav"; touch -t 202501010000 "$C91/a.sav"
echo "cidre recent" >"$C91/b.sav"; touch -t 202801010000 "$C91/b.sav"
cp -p "$S91/c.sav" "$C91/c.sav"
printf '9101\tAppData/Roaming/Jeu91\n' >>"$C/saves.conf"
# 9102 : rien dans la bouteille ; 9105 : chez un autre utilisateur de la bouteille
repris 9102 "Jeu 92"; printf '9102\tAppData/Roaming/Jeu92\n' >>"$C/saves.conf"
repris 9105 "Jeu 95"; mkdir -p "$BT/drive_c/users/steamuser/AppData/Roaming/Jeu 95"; echo cinq >"$BT/drive_c/users/steamuser/AppData/Roaming/Jeu 95/s.sav"
# 9103 : Steam Cloud par l'API ; 9104 : par un dossier macOS lie
repris 9103 "Jeu 93"; mkdir -p "$BU/AppData/Roaming/Jeu 93"; echo trois >"$BU/AppData/Roaming/Jeu 93/s.sav"
repris 9104 "Jeu 94"; S94="$BU/AppData/LocalLow/Dev94/Jeu94"; M94="$M/Library/Application Support/Dev94.Jeu94"; mkdir -p "$S94"
echo quatre >"$S94/q.sav"
F94="steam-lien${TABU}AppData/LocalLow/Dev94/Jeu94 => Library/Application Support/Dev94.Jeu94"
# 9106 : Documents de la bouteille et de Cidre sont le meme dossier du Mac
repris 9106 "Vieux"; ln -s "$U/Documents" "$BU/Documents"; printf '9106\tDocuments/My Games/Vieux\n' >>"$C/saves.conf"
# 1562430 : le dossier que dit le saves.conf livre
repris 1562430 "DREDGE"; mkdir -p "$BU/AppData/LocalLow/Black Salt Games/DREDGE/saves"; echo dredge >"$BU/AppData/LocalLow/Black Salt Games/DREDGE/saves/slot0.bin"
BT_AVANT=$(cliche "$BT"); DOC_AVANT=$(cliche "$U/Documents")

o=$(ramener 9101); verif "code de retour" "0" "$?"
printf '%s' "$o" | plutil -convert json -o /dev/null - 2>/dev/null && ok "JSON valide" || echec "JSON invalide : $o"
verif "etat, ecrits, remplaces, gardes, identiques" "copie 2 1 1 1" "$(cj etat "$o") $(cj fichiers "$o") $(cj remplaces "$o") $(cj gardes "$o") $(cj identiques "$o")"
verif "origine, bouteille, synchro, dossier" "crossover Essai copie AppData/Roaming/Jeu91" "$(cj origine "$o") $(cj bouteille "$o") $(cj synchro "$o") $(cj dossier "$o")"
verif "d'ou, vers ou" "$S91 $C91" "$(cj depuis "$o") $(cj vers "$o")"
verif "plus ancien cote Cidre : remplace par celui de la bouteille" "bouteille a" "$(cat "$C91/a.sav")"
verif "plus recent cote Cidre : jamais ecrase" "cidre recent" "$(cat "$C91/b.sav")"
verif "absent cote Cidre : copie, sous-dossier compris" "bouteille d" "$(cat "$C91/sous/d.sav" 2>/dev/null)"
verif "la date de la bouteille est gardee" "$(stat -f %m "$S91/sous/d.sav")" "$(stat -f %m "$C91/sous/d.sav" 2>/dev/null)"
verif "le superflu n'est pas repris (journal, cache, plus de 100 Mo)" "" "$(ls "$C91/jeu.log" "$C91/cache" "$C91/enorme.bin" 2>/dev/null)"
H91=$(cj historique "$o")
verif "copie de ce qui est remplace, et de cela seulement" "cidre ancien|a.sav" "$(cat "$H91/0/a.sav" 2>/dev/null)|$(ls "$H91/0" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
verif "la copie de precaution est dans l'historique du jeu" "$C/saves/9101/.history" "$(dirname "$H91")"
o=$(ramener 9101)
verif "second passage : rien a ramener, rien de plus dans l'historique" "a_jour 0 1" "$(cj etat "$o") $(cj fichiers "$o") $(ls "$C/saves/9101/.history" | wc -l | tr -d ' ')"
o=$(ramener 9102)
verif "rien dans la bouteille : absentes" "absentes 0" "$(cj etat "$o") $(cj fichiers "$o")"
o=$(ramener 9105)
verif "chez un autre utilisateur de la bouteille (dossier au nom du jeu)" "copie 1 $BT/drive_c/users/steamuser/AppData/Roaming/Jeu 95" "$(cj etat "$o") $(cj fichiers "$o") $(cj depuis "$o")"
verif "le dossier devine est note dans saves.conf" "AppData/Roaming/Jeu 95" "$(awk -F'\t' '$1 == 9105 { print $2 }' "$C/saves.conf")"
o=$(FICHE=steam-api ramener 9103)
verif "Steam Cloud par l'API : rien n'est copie" "steam steam_api 0" "$(cj etat "$o") $(cj synchro "$o") $(cj fichiers "$o")"
[ ! -e "$U/AppData/Roaming/Jeu 93" ] && ok "Steam Cloud par l'API : rien d'ecrit cote Cidre" || echec "Steam Cloud par l'API : un dossier a ete copie"
verif "Steam Cloud par l'API : on le dit" "1" "$(grep -c 'Steam Cloud synchronise deja ce jeu' "$T/rs.err")"
o=$(CIDRE_SAVES_STEAM=0 FICHE=steam-api ramener 9103)
verif "CIDRE_SAVES_STEAM=0 : comme un jeu sans Steam Cloud" "copie copie 1" "$(cj etat "$o") $(cj synchro "$o") $(cj fichiers "$o")"
o=$(FICHE="$F94" ramener 9104)
verif "dossier macOS lie : copie dans ce dossier" "copie steam_macos 1 $M94" "$(cj etat "$o") $(cj synchro "$o") $(cj fichiers "$o") $(cj vers "$o")"
verif "dossier macOS lie : le lien est pose, le fichier y est" "$M94 quatre" "$(readlink "$U/AppData/LocalLow/Dev94/Jeu94") $(cat "$M94/q.sav" 2>/dev/null)"
verif "dossier macOS lie : rien n'est note dans saves.conf" "" "$(awk -F'\t' '$1 == 9104' "$C/saves.conf")"
o=$(ramener 9106)
verif "meme dossier des deux cotes (Documents du Mac) : rien a faire" "a_jour 0 1" "$(cj etat "$o") $(cj fichiers "$o") $(cj identiques "$o")"
verif "meme dossier des deux cotes : intact" "$DOC_AVANT" "$(cliche "$U/Documents")"
o=$(ramener 1562430)
verif "le dossier du saves.conf livre" "copie 1 AppData/LocalLow/Black Salt Games/DREDGE" "$(cj etat "$o") $(cj fichiers "$o") $(cj dossier "$o")"
verif "la bouteille n'a pas ete touchee" "$BT_AVANT" "$(cliche "$BT")"

echo "== Steam d'abord : la bouteille ne fait que combler"
# le stockage du client Steam (userdata), fabrique : ce qu'il sait du nuage
export CIDRE_STEAM_USERDATA="$T/userdata"
cache_steam() { # <appid> <fichier> <taille> <platformstosync2>
   mkdir -p "$CIDRE_STEAM_USERDATA/77/$1"
   printf '"%s"\n{\n\t"ChangeNumber"\t\t"3"\n\t"%s"\n\t{\n\t\t"root"\t\t"12"\n\t\t"size"\t\t"%s"\n\t\t"remotetime"\t\t"%s"\n\t\t"sha"\t\t"0000000000000000000000000000000000000000"\n\t\t"syncstate"\t\t"2"\n\t\t"platformstosync2"\t\t"%s"\n\t}\n}\n' \
      "$1" "$2" "$3" "$([ "$3" -gt 0 ] && echo 1791067661 || echo 0)" "$4" >"$CIDRE_STEAM_USERDATA/77/$1/remotecache.vdf"
}
lie() { # <n> : jeu 91<n>, sa fiche a dossier macOS lie, une sauvegarde dans la bouteille
   repris 91$1 "Jeu 1$1"; mkdir -p "$BU/AppData/LocalLow/D$1/J$1"
   echo "bouteille $1" >"$BU/AppData/LocalLow/D$1/J$1/commun.sav"; echo "en plus $1" >"$BU/AppData/LocalLow/D$1/J$1/autre.sav"
   touch -t 202606010000 "$BU/AppData/LocalLow/D$1/J$1"/*.sav
}
fl() { printf 'steam-lien\tAppData/LocalLow/D%s/J%s => Library/Application Support/D%s.J%s' "$1" "$1" "$1" "$1"; }
ml() { printf '%s' "$M/Library/Application Support/D$1.J$1"; }
for n in 07 08 09 10 11 12; do lie $n; done
repris 9113 "Jeu 113"; mkdir -p "$BU/AppData/Roaming/Jeu 113"; echo api >"$BU/AppData/Roaming/Jeu 113/s.sav"
BT_AVANT=$(cliche "$BT")
# 9107 : Steam a deja un fichier, PLUS ANCIEN que celui de la bouteille
mkdir -p "$(ml 07)"; echo "steam ancien" >"$(ml 07)/commun.sav"; touch -t 202501010000 "$(ml 07)/commun.sav"
o=$(FICHE="$(fl 07)" ramener 9107); verif "Steam a un fichier plus ancien : code de retour" "0" "$?"
verif "Steam a un fichier plus ancien : Steam d'abord" "steam_prioritaire steam_macos 0 0 2 1 false false" \
   "$(cj etat "$o") $(cj synchro "$o") $(cj fichiers "$o") $(cj remplaces "$o") $(cj gardes "$o") $(cj steam_fichiers "$o") $(cj steam_distants "$o") $(cj force "$o")"
verif "le fichier de Steam n'est pas remplace, meme plus ancien" "steam ancien" "$(cat "$(ml 07)/commun.sav")"
verif "rien n'est ajoute non plus au dossier de Steam" "commun.sav" "$(ls "$(ml 07)" | tr '\n' ' ' | sed 's/ $//')"
verif "on dit la priorite, ce que la bouteille garde, et comment passer outre" "1 1 1" \
   "$(grep -c 'elles ont la priorite, rien n.est copie de la bouteille' "$T/rs.err") $(grep -c "bouteille : 2 fichier(s), intacts : $BU/AppData/LocalLow/D07/J07" "$T/rs.err") $(grep -c 'cidre import 9107 --saves --forcer' "$T/rs.err")"
verif "aucune copie de precaution : rien n'a ete remplace" "" "$(ls -d "$C/saves/9107/.history/avant-reprise-"* 2>/dev/null)"
# 9108 : le dossier de Steam est vide, le client n'a jamais synchronise ce jeu
o=$(FICHE="$(fl 08)" ramener 9108)
verif "dossier de Steam vide : comble" "copie 2 0 true bouteille 08" "$(cj etat "$o") $(cj fichiers "$o") $(cj steam_fichiers "$o") $(cj conflit_possible "$o") $(cat "$(ml 08)/commun.sav" 2>/dev/null)"
verif "jamais synchronise ici : le conflit possible est dit" "1" "$(grep -c 'Steam signalera un conflit' "$T/rs.err")"
o=$(FICHE="$(fl 08)" ramener 9108)
verif "second passage : Steam a maintenant ces fichiers, plus rien n'est touche" "steam_prioritaire 0" "$(cj etat "$o") $(cj fichiers "$o")"
# 9109 : dossier vide, mais le client connait un fichier du nuage pour macOS
cache_steam 9109 "D09/J09/commun.sav" 4096 -1
o=$(FICHE="$(fl 09)" ramener 9109)
verif "fichiers connus dans le nuage : rien n'est copie" "steam_prioritaire 0 1 true" "$(cj etat "$o") $(cj fichiers "$o") $(cj steam_fichiers "$o") $(cj steam_distants "$o")"
verif "fichiers connus dans le nuage : le dossier de Steam reste vide" "" "$(ls -A "$(ml 09)" 2>/dev/null)"
# 9110 : le client ne connait qu'un fichier declare pour Windows (jamais descendu sur Mac), ou un fichier efface
cache_steam 9110 "D10/J10/commun.sav" 4096 1
o=$(FICHE="$(fl 10)" ramener 9110)
verif "nuage : fichier pour Windows seulement -> comble, sans conflit possible" "copie 2 false" "$(cj etat "$o") $(cj fichiers "$o") $(cj conflit_possible "$o")"
cache_steam 9111 "D11/J11/commun.sav" 0 -1
o=$(FICHE="$(fl 11)" ramener 9111)
verif "nuage : entree vide (taille 0, jamais envoyee) -> comble" "copie 2 false" "$(cj etat "$o") $(cj fichiers "$o") $(cj conflit_possible "$o")"
# forcer, a la demande : la bouteille passe par-dessus, la version de Steam est gardee
o=$(FICHE="$(fl 07)" ramener 9107 --forcer)
verif "--forcer : etat, ecrits, remplaces, force" "copie 2 1 true" "$(cj etat "$o") $(cj fichiers "$o") $(cj remplaces "$o") $(cj force "$o")"
verif "--forcer : le fichier de la bouteille remplace celui de Steam" "bouteille 07" "$(cat "$(ml 07)/commun.sav")"
verif "--forcer : la version de Steam est gardee dans l'historique" "steam ancien" "$(cat "$(cj historique "$o")/0/commun.sav" 2>/dev/null)"
o=$(FICHE="$(fl 09)" ramener 9109 --forcer)
verif "--forcer malgre des fichiers connus dans le nuage : copie" "copie 2" "$(cj etat "$o") $(cj fichiers "$o")"
o=$(FICHE=steam-api ramener 9113 --forcer)
verif "--forcer sur un jeu a API de Steam : toujours rien" "steam 0 0" "$(cj etat "$o") $(cj fichiers "$o") $(ls "$U/AppData/Roaming/Jeu 113" 2>/dev/null | wc -l | tr -d ' ')"
# 9112 : le lien est deja pose, mais la fiche ne le dit plus (cache de fiches perime,
# CIDRE_SAVES_STEAM=0) : le dossier reste celui que Steam synchronise
mkdir -p "$(ml 12)" "$U/AppData/LocalLow/D12"; echo "steam 12" >"$(ml 12)/commun.sav"; touch -t 202501010000 "$(ml 12)/commun.sav"
ln -s "$(ml 12)" "$U/AppData/LocalLow/D12/J12"; printf '9112\tAppData/LocalLow/D12/J12\n' >>"$C/saves.conf"
o=$(ramener 9112)
verif "lien deja pose, fiche muette : Steam d'abord quand meme" "steam_prioritaire steam_macos 0 steam 12" "$(cj etat "$o") $(cj synchro "$o") $(cj fichiers "$o") $(cat "$(ml 12)/commun.sav")"
verif "la bouteille n'a pas ete touchee" "$BT_AVANT" "$(cliche "$BT")"

echo "== Steam d'abord : la copie de Cidre n'est jamais restauree dans un dossier que Steam synchronise"
# la copie de Cidre (ou d'iCloud) a un fichier plus recent, et un que Steam n'a pas
mkdir -p "$C/saves/9112"; echo "copie cidre recente" >"$C/saves/9112/commun.sav"; touch -t 202901010000 "$C/saves/9112/commun.sav"; echo "en plus" >"$C/saves/9112/copie.sav"
s=$(CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 9112 restore 2>&1)
verif "lien pose, jeu retombe en copie Cidre : restore ne remplace rien" "steam 12" "$(cat "$(ml 12)/commun.sav")"
verif "restore n'ajoute rien non plus" "commun.sav" "$(ls "$(ml 12)" | tr '\n' ' ' | sed 's/ $//')"
verif "restore le dit" "1" "$(printf '%s\n' "$s" | grep -c "la copie de Cidre n'y est pas restauree (Steam a la priorite)")"
s=$(CIDRE_SAVES_STEAM=0 CIDRE_FICHE_STEAM_CLOUD="$(fl 12)" sh "$Y" 9112 restore 2>&1)
verif "CIDRE_SAVES_STEAM=0 : pareil" "steam 12" "$(cat "$(ml 12)/commun.sav")"
CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 9112 backup >/dev/null 2>&1
verif "backup, lui, lit le dossier de Steam sans y ecrire" "steam 12 copie cidre recente" "$(cat "$(ml 12)/commun.sav") $(cat "$C/saves/9112/.history"/*/commun.sav 2>/dev/null)"
s=$(CIDRE_FICHE_STEAM_CLOUD="$(fl 12)" sh "$Y" 9112 restore 2>&1)
verif "fiche a dossier lie : restore ne copie rien (Steam Cloud)" "steam 12 0" "$(cat "$(ml 12)/commun.sav") $(printf '%s\n' "$s" | grep -c 'restore ')"
# un dossier ordinaire (pas un lien) reste restaure comme avant
mkdir -p "$C/saves/9105"; echo "copie plus recente" >"$C/saves/9105/s.sav"; touch -t 203001010000 "$C/saves/9105/s.sav"
CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 9105 restore >/dev/null 2>&1
verif "jeu sans Steam Cloud : la copie de Cidre plus recente est toujours restauree" "copie plus recente" "$(cat "$U/AppData/Roaming/Jeu 95/s.sav")"
unset CIDRE_STEAM_USERDATA


echo "== seance Steam avant le lancement : faire descendre le nuage (tests/seance_steam_cloud.sh)"
SC="$R/tests/seance_steam_cloud.sh"
FS="$T/faux-steam"; mkdir -p "$FS/logs" "$FS/Steam.AppBundle"
JC="$FS/logs/cloud_log.txt"; : >"$JC"
# un faux cidre-outil : il ajoute au journal du client ce que dit FAUX_JOURNAL,
# et rend FAUX_SORTIE / FAUX_RC ; chaque appel est note
cat >"$T/outil-faux" <<'FIN'
#!/bin/sh
echo "$*" >>"$FAUX_APPELS"
[ -z "${FAUX_JOURNAL:-}" ] || printf '%b' "$FAUX_JOURNAL" >>"$CIDRE_CLOUD_LOG"
printf '%b' "${FAUX_SORTIE:-nuage_compte=1\nnuage_jeu=1\netat=ok\n}"
exit ${FAUX_RC:-0}
FIN
chmod +x "$T/outil-faux"
export FAUX_APPELS="$T/appels"
connexion() { printf '[2026-10-14 09:00:00] [%s, 0,0,0,0] etat\n' "$1" >>"$FS/logs/connection_log.txt"; }
seance() { # <fiche> [env...] : la sortie du script ; les appels de l'outil dans $FAUX_APPELS
   : >"$FAUX_APPELS"
   CIDRE_STEAM_DIR="$FS" CIDRE_CLOUD_LOG="$JC" CIDRE_OUTIL="$T/outil-faux" CIDRE_STEAM_TOURNE="${TOURNE:-true}" \
   CIDRE_FICHE_STEAM_CLOUD="$1" CIDRE_SEANCE_ATTENTE="${ATT:-3}" CIDRE_SEANCE_STEAM="${SEANCE:-1}" sh "$SC" 77 2>&1
}
appels() { wc -l <"$FAUX_APPELS" | tr -d ' '; }
h=$(date '+%Y-%m-%d %H:%M:%S')
connexion "Logged On"
verif "jeu Windows seulement : rien, pas de seance" "|0" "$(seance copie)|$(appels)"
verif "CIDRE_SEANCE_STEAM=0 : rien" "|0" "$(SEANCE=0 seance steam-api)|$(appels)"
verif "client ferme : dit, pas de seance, pas d'ouverture" "1|0" "$(TOURNE=false seance steam-api | grep -c 'client Steam ferme')|$(appels)"
connexion "Logged Off"
verif "client hors ligne : dit, pas de seance" "1|0" "$(seance steam-api | grep -c 'hors ligne, nuage non verifie')|$(appels)"
connexion "Logged On"
o=$(FAUX_JOURNAL="[$h] [AppID 77] Starting sync (up,AC Exit,)\n[$h] [AppID 77] Download OK for file user_0.dat\n[$h] [AppID 77] Download OK for file opts.json\n[$h] [AppID 77] YldWriteCacheDirectoryToFile - saved\n" seance steam-api)
verif "le nuage descend : seance au nom du jeu, fichiers comptes" "seance 77|1" "$(cat "$FAUX_APPELS")|$(printf '%s\n' "$o" | grep -c '2 fichier(s) descendu(s) du nuage, 0 envoye(s), avant le lancement')"
o=$(FAUX_JOURNAL="[$h] [AppID 77] Starting sync (up,AC Exit,)\n[$h] [AppID 77] Currently already synced to global change number '9', should be nothing to download\n[$h] [AppID 77] YldWriteCacheDirectoryToFile - saved\n" seance steam-api)
verif "deja a jour" "1" "$(printf '%s\n' "$o" | grep -c 'a jour avec le nuage')"
# Garde : jamais de seance pour un jeu Auto-Cloud. La synchro de sortie qu'elle
# declenche retire du nuage les fichiers que remotecache.vdf croit sur ce Mac et
# que les regles n'y trouvent pas (Blasphemous, 2026-10-14 10:32).
verif "garde : dossier lie (Auto-Cloud) -> pas de seance, rien a dire" "|0" "$(seance "$PEAK")|$(appels)"
mkdir -p "$FS/userdata/42/77"
printf '"77"\n{\n\t"ChangeNumber"\t\t"3"\n\t"user_0.dat"\n\t{\n\t\t"root"\t\t"0"\n\t\t"size"\t\t"9"\n\t}\n}\n' >"$FS/userdata/42/77/remotecache.vdf"
o=$(FAUX_JOURNAL="[$h] [AppID 77] Starting sync (up,AC Exit,)\n[$h] [AppID 77] YldWriteCacheDirectoryToFile - saved\n" seance steam-api)
verif "garde : API, le client ne connait que des fichiers de l'API -> seance" "1|1" "$(appels)|$(printf '%s\n' "$o" | grep -c 'a jour avec le nuage')"
printf '"77"\n{\n\t"user_0.dat"\n\t{\n\t\t"root"\t\t"0"\n\t}\n\t"Studio/Jeu/Savegames/slot.sav"\n\t{\n\t\t"root"\t\t"7"\n\t\t"size"\t\t"0"\n\t}\n}\n' >"$FS/userdata/42/77/remotecache.vdf"
o=$(seance steam-api)
verif "garde : API, mais le client connait un fichier Auto-Cloud (racine 7) -> pas de seance, dit" "0|1" "$(appels)|$(printf '%s\n' "$o" | grep -c 'aussi des fichiers Auto-Cloud, pas de seance')"
rm -f "$FS/userdata/42/77/remotecache.vdf"
o=$(FAUX_JOURNAL="[$h] [AppID 77] Starting sync (up,AC Exit,)\n[$h] [AppID 77] Failed sync for 'up,AC Exit,' [login=false][offlineMode=true]\n" seance steam-api)
verif "synchro refusee par le client : le jeu part quand meme" "1" "$(printf '%s\n' "$o" | grep -c 'synchro impossible')"
o=$(FAUX_JOURNAL="[$h] [AppID 77] Starting sync (up,AC Exit,)\n[$h] [AppID 77] Conflict detected for file x\n[$h] [AppID 77] YldWriteCacheDirectoryToFile - saved\n" seance steam-api)
verif "conflit : on dit d'ouvrir Steam" "1" "$(printf '%s\n' "$o" | grep -c 'signale un conflit')"
# une synchro finie AVANT la seance (deja au journal) ne compte pas
t=$(date +%s); o=$(ATT=1 seance steam-api); d=$(( $(date +%s) - t ))
verif "rien de neuf au journal : attente bornee, le jeu part" "1" "$(printf '%s\n' "$o" | grep -c 'synchro pas finie apres')"
[ $d -le 4 ] && ok "attente bornee ($d s pour 1 s demandee)" || echec "attente de $d s pour 1 s demandee"
o=$(FAUX_JOURNAL="[$h] [AppID 78] Starting sync (up,AC Exit,)\n[$h] [AppID 78] YldWriteCacheDirectoryToFile - saved\n" ATT=1 seance steam-api)
verif "la synchro d'un autre jeu ne compte pas" "1" "$(printf '%s\n' "$o" | grep -c 'synchro pas finie')"
o=$(FAUX_SORTIE='etat=seance_refusee\ninit=2\ndetail=No subscription\n' FAUX_RC=4 seance steam-api)
verif "seance refusee (jeu non possede...) : dit pourquoi" "1" "$(printf '%s\n' "$o" | grep -c 'a refuse la seance (No subscription)')"
o=$(FAUX_SORTIE='nuage_compte=1\nnuage_jeu=0\netat=ok\n' seance steam-api)
verif "Steam Cloud coupe pour ce jeu : dit, sans attendre" "1" "$(printf '%s\n' "$o" | grep -c 'Steam Cloud est coupe pour ce jeu')"
verif "toujours 0" "0" "$(FAUX_RC=4 seance steam-api >/dev/null; echo $?)"
if [ -x "$R/build/cidre-outil" ]; then
   verif "cidre-outil seance : appid invalide" "2" "$("$R/build/cidre-outil" seance 7x >/dev/null 2>&1; echo $?)"
   o=$(CIDRE_STEAM_API=/nonexistent "$R/build/cidre-outil" seance 7); rc=$?
   verif "cidre-outil seance : sans bibliotheque, client tenu pour ferme" "etat=bibliotheque_absente 3" "$o $rc"
fi

echo "== bouteille : ce qu'en dit l'etat des sauvegardes"
e=$(CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 9101 etat)
printf '%s' "$e" | plutil -convert json -o /dev/null - 2>/dev/null && ok "etat : JSON valide" || echec "etat : JSON invalide : $e"
verif "copie Cidre : \"reprise\" porte le dernier passage" '"reprise":{"appid":9101,"etat":"a_jour","fichiers":0,' "$(printf '%s' "$e" | grep -o '"reprise":{"appid":9101,"etat":"a_jour","fichiers":0,')"
verif "copie Cidre : le reste de l'etat est la" "jamais_sauvegarde copie" "$(cj etat "$(printf '%s' "$e" | sed 's/,"reprise":.*//')") $(cj synchro "$(printf '%s' "$e" | sed 's/,"reprise":.*//')")"
e=$(CIDRE_FICHE_STEAM_CLOUD="$F94" sh "$Y" 9104 etat)
verif "Steam Cloud : \"reprise\" aussi" "1" "$(printf '%s' "$e" | grep -c '"synchro":"steam_macos".*"reprise":{"appid":9104,"etat":"copie","fichiers":1,')"
verif "jeu qui ne vient pas d'une bouteille : null" "1" "$(CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 7 etat | grep -c '"reprise":null}$')"
verif "dossier inconnu : null aussi" "1" "$(CIDRE_FICHE_STEAM_CLOUD=- sh "$Y" 424242 etat | grep -c '"configure":false.*"reprise":null}$')"
verif "refus : jeu absent du dossier Cidre" "1 erreur jeu_absent" "$(o=$(ramener 31337); echo "$? $(cj etat "$o") $(cj raison "$o")")"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
