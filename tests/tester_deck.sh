#!/bin/sh
# Mode Deck simule (`deck`, CIDRE_DECK, wine11 0160) : un jeu « Verifie Steam
# Deck » prend seul sa configuration Deck quand le pont Steam repond oui a
# IsSteamRunningOnSteamDeck.
#
#   tester_deck.sh         le profil livre, `cidre set` et le bloc du lanceur
#                          (sans Wine : le bloc est extrait du lanceur et
#                          execute avec un profil et un environnement donnes)
#
# L'effet en jeu se mesure ailleurs (etude-proton.md, §9.1, manche C : la ligne
# « lsteamclient : mode Deck simule » sur la sortie du jeu dit qu'il a pose la
# question).
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester_deck.XXXXXX")
trap 'rm -rf "$T"' EXIT
ECHECS=0
ok()  { echo "ok    $1"; }
ko()  { echo "ECHEC $1"; ECHECS=$((ECHECS + 1)); }
vaut() { [ "$2" = "$3" ] && ok "$1" || ko "$1 : « $2 » au lieu de « $3 »"; }

# --- profil livre et cidre set ---
export CIDRE_PROFILS="$T/profils.toml"
vaut "defaut livre" "$(sh "$R/tests/profil_cidre.sh" defaut | sed -n 's/^deck=//p')" false
sh "$R/cidre" set defaut deck true >/dev/null 2>&1 && ok "cidre set defaut deck true" || ko "cidre set defaut deck true refuse"
vaut "defaut utilisateur" "$(sh "$R/tests/profil_cidre.sh" 0 | sed -n 's/^deck=//p')" true
sh "$R/cidre" set defaut deck oui >/dev/null 2>&1 && ko "cidre set accepte deck oui" || ok "cidre set refuse deck oui"
unset CIDRE_PROFILS

# --- le bloc du lanceur, tel quel ---
BLOC=$(awk '/^case \$\(opt deck CIDRE_DECK\) in/,/^esac/' "$R/tests/lancer_depuis_steam.sh")
[ -n "$BLOC" ] || ko "bloc deck introuvable dans le lanceur"
lanceur() { # <valeur du profil> [CIDRE_DECK] [dx12 du profil]
   env -u CIDRE_DECK -u CIDRE_DX12 ${2:+CIDRE_DECK=$2} PROFIL_ESSAI="$1" PROFIL_DX12="${3:-false}" sh -c '
      profil() { case $1 in deck) echo "$PROFIL_ESSAI" ;; dx12) echo "$PROFIL_DX12" ;; esac; }
      opt() { eval "v=\${$2:-}"
         case $v in 1) echo true; return ;; 0) echo false; return ;; "") ;; *) echo "$v"; return ;; esac
         profil "$1"; }
      '"$BLOC"'
      echo "${CIDRE_DECK-(absent)}${DECK_COUPE:+ coupe=$DECK_COUPE}"'
}
vaut "profil true" "$(lanceur true)" 1
vaut "profil false" "$(lanceur false)" "(absent)"
vaut "sans profil" "$(lanceur '')" "(absent)"
vaut "CIDRE_DECK=1 devant le profil" "$(lanceur false 1)" 1
vaut "CIDRE_DECK=0 devant le profil" "$(lanceur true 0)" "(absent)"
vaut "profil true, dx12 : coupe" "$(lanceur true '' true)" "(absent) coupe=d3d12"
vaut "profil false, dx12 : rien" "$(lanceur false '' true)" "(absent)"
vaut "CIDRE_DECK=1 explicite, dx12 : garde la main" "$(lanceur false 1 true)" 1

# --- la fiche d'Expedition 33 : deck sur M1 seulement ---
valeur() { CIDRE_PROFILS=$T/vide.toml CIDRE_PROFILS_BASE=/nonexistent CIDRE_MACHINE="$1" sh "$R/tests/profil_cidre.sh" 1903340 | sed -n 's/^deck=//p'; }
vaut "1903340 : deck sur M1 (famille 7)" "$(valeur 'famille_gpu=7 coeurs_gpu=24')" true
vaut "1903340 : pas de deck sur M4 (famille 9)" "$(valeur 'famille_gpu=9 coeurs_gpu=10')" false

# --- le pont Steam : la reponse n'est donnee qu'a la bonne question ---
P=$(ls "$R"/0160-wine11-lsteamclient-mode-deck-simule.patch 2>/dev/null)
[ -n "$P" ] || ko "correctif 0160 absent"
[ -z "$P" ] || {
   grep -q 'emplacement != 34 || strcmp( version, "SteamUtils010" )' "$P" && ok "0160 : SteamUtils010 emplacement 34 seulement" \
      || ko "0160 : la garde SteamUtils010/34 a change"
   [ "$(grep -c '^+        if (deck_simule( objet->nom, emplacement, &neutre )) return neutre;' "$P")" = 2 ] \
      && ok "0160 : relais 64 et 32 bits" || ko "0160 : deck_simule absent d'un relais"
}
. "$R/tests/series.sh"
serie_wine11 | grep -q '0160-wine11-' && ok "0160 dans serie_wine11" || ko "0160 absent de serie_wine11"

[ $ECHECS = 0 ] && echo "tout est bon" || echo "$ECHECS echec(s)"
exit $((ECHECS > 0))
