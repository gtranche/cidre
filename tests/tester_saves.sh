#!/bin/sh
# Teste tests/deviner_saves.sh sur un faux prefixe et un faux dossier de jeu :
# la fiche quand elle designe un dossier qui existe, l'heuristique par moteur
# apres une partie, et les cas ou il faut se taire. Rien n'est lance.
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

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
