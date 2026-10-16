#!/bin/sh
# Touches aux positions QWERTY pour un clavier AZERTY (option `clavier`,
# CIDRE_CLAVIER, winemac wine11 0151).
#
#   tester_clavier.sh          le profil, `cidre set` et le lanceur (sans Wine)
#   tester_clavier.sh sonde    en plus, tests/sonde_clavier.c sous Wine, dans un
#                              prefixe clone, sans CIDRE_CLAVIER puis avec
#                              CIDRE_CLAVIER=positions
#
# Pour la sonde : PFX_ESSAI = prefixe clone (cp -c -R wine/pfx-arm64ec <scratch>/pfx),
# jamais wine/pfx-arm64ec ; WINE_ESSAI = racine du runtime (defaut
# wine/wine11-arm64) ; SONDE = sonde_clavier.exe (construite sinon a cote de
# PFX_ESSAI). Refuse de partir si un jeu tourne. Ce que la sonde doit voir
# depend de la disposition macOS active : en AZERTY, VK_W passe de la position
# Z a la position W, VK_M de la position M a la position ; ; en QWERTY US,
# rien ne change.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester_clavier.XXXXXX")
trap 'rm -rf "$T"' EXIT
ECHECS=0
ok()  { echo "ok    $1"; }
ko()  { echo "ECHEC $1"; ECHECS=$((ECHECS + 1)); }
vaut() { [ "$2" = "$3" ] && ok "$1" || ko "$1 : « $2 » au lieu de « $3 »"; }

# --- profil et cidre set ---
export CIDRE_PROFILS="$T/profils.toml"
vaut "defaut livre" "$(sh "$R/tests/profil_cidre.sh" defaut | sed -n 's/^clavier=//p')" systeme
sh "$R/cidre" set defaut clavier positions >/dev/null 2>&1 && ok "cidre set defaut clavier positions" \
   || ko "cidre set defaut clavier positions refuse"
vaut "defaut utilisateur" "$(sh "$R/tests/profil_cidre.sh" 0 | sed -n 's/^clavier=//p')" positions
sh "$R/cidre" set defaut clavier azerty >/dev/null 2>&1 && ko "cidre set accepte clavier azerty" \
   || ok "cidre set refuse une valeur inconnue"
sh "$R/cidre" set defaut clavier systeme >/dev/null 2>&1
vaut "systeme pose" "$(sh "$R/tests/profil_cidre.sh" 0 | sed -n 's/^clavier=//p')" systeme
unset CIDRE_PROFILS

# --- le lanceur : l'option devient CIDRE_CLAVIER (le bloc tel qu'il est dans
# le lanceur, execute avec un profil et un environnement donnes) ---
BLOC=$(awk '/^case \$\(opt clavier CIDRE_CLAVIER\) in/,/^esac/' "$R/tests/lancer_depuis_steam.sh")
[ -n "$BLOC" ] || ko "bloc clavier introuvable dans le lanceur"
lanceur() { # <valeur du profil> [CIDRE_CLAVIER]
   env -u CIDRE_CLAVIER ${2:+CIDRE_CLAVIER=$2} PROFIL_ESSAI="$1" sh -c '
      profil() { [ "$1" = clavier ] && echo "$PROFIL_ESSAI"; }
      opt() { eval "v=\${$2:-}"
         case $v in 1) echo true; return ;; 0) echo false; return ;; "") ;; *) echo "$v"; return ;; esac
         profil "$1"; }
      '"$BLOC"'
      echo "${CIDRE_CLAVIER-(absent)}"'
}
vaut "profil positions" "$(lanceur positions)" positions
vaut "profil inconnu" "$(lanceur qwerty)" "(absent)"
vaut "profil systeme" "$(lanceur systeme)" "(absent)"
vaut "sans profil" "$(lanceur '')" "(absent)"
vaut "CIDRE_CLAVIER=positions devant le profil" "$(lanceur systeme positions)" positions
vaut "CIDRE_CLAVIER=0 devant le profil" "$(lanceur positions 0)" "(absent)"

[ "${1:-}" = sonde ] || { [ $ECHECS = 0 ] && echo "tout est bon" || echo "$ECHECS echec(s)"; exit $((ECHECS > 0)); }

# --- la sonde sous Wine ---
WINE_ESSAI=${WINE_ESSAI:-$R/wine/wine11-arm64}
PFX=${PFX_ESSAI:?PFX_ESSAI = un prefixe clone, jamais wine/pfx-arm64ec}
case $(cd "$PFX" && pwd) in "$R/wine/pfx-arm64ec") echo "PFX_ESSAI ne doit pas etre wine/pfx-arm64ec" >&2; exit 2 ;; esac
if pgrep -f '[l]ancer_depuis_steam.sh' >/dev/null 2>&1; then
   echo "un jeu tourne : pas de sonde (a relancer apres la partie)" >&2; exit 3
fi
SONDE=${SONDE:-$PFX/drive_c/sonde_clavier.exe}
if [ ! -f "$SONDE" ]; then
   "$R/toolchain/llvm-mingw/bin/x86_64-w64-mingw32-gcc" -O1 -o "$SONDE" "$R/tests/sonde_clavier.c" -luser32 \
      || { echo "sonde introuvable et non construite" >&2; exit 2; }
fi
sonde() { # <CIDRE_CLAVIER ou vide> <sortie>
   env -u CIDRE_CLAVIER ${1:+CIDRE_CLAVIER=$1} WINEPREFIX="$PFX" WINEDEBUG=-all \
      "$WINE_ESSAI/bin/wine" "$SONDE" >"$2.crlf" 2>"$2.err"
   r=$?; tr -d '\r' <"$2.crlf" >"$2"; return $r   # la console Wine ecrit en CRLF
}
sonde ""        "$T/base"      || ko "sonde sans CIDRE_CLAVIER"
sonde positions "$T/positions" || ko "sonde en positions"
WINEPREFIX="$PFX" "$WINE_ESSAI/bin/wineserver" -k 2>/dev/null || true
for m in base positions; do cp "$T/$m" "${SORTIES:-$T}/sonde-$m.txt" 2>/dev/null || true; done

# colonne <n> de la ligne du code de balayage <scan>
col() { awk -v s="$2" -v c="$3" '$1 == s { print $c; exit }' "$T/$1"; }
# lignes de la table : scan qwerty vk vk->car texte nom
table() { awk '$1 ~ /^0x[0-9a-f][0-9a-f]$/' "$T/$1"; }
[ "$(table base | wc -l)" -ge 40 ] && ok "sonde : table complete" || { ko "sonde : table vide"; cat "$T/base.err" | tail -5; }

# Disposition macOS : WASD deja en place (QWERTY, QWERTZ) ou non (AZERTY...).
EN_PLACE=oui
for p in "0x11 0x57" "0x1e 0x41" "0x1f 0x53" "0x20 0x44"; do
   set -- $p; [ "$(col base "$1" 3)" = "$2" ] || EN_PLACE=non
done
echo "      disposition : WASD en place = $EN_PLACE ; $(grep 'disposition annoncee' "$T/base")"

# Le texte tape et le nom des touches ne changent dans aucun mode.
for m in positions; do
   vaut "$m : texte tape inchange" "$(table $m | awk '{print $1, $5}')" "$(table base | awk '{print $1, $5}')"
   vaut "$m : noms des touches inchanges" "$(table $m | awk '{print $1, $6}')" "$(table base | awk '{print $1, $6}')"
done

# Code virtuel US attendu a chaque position
vk_us() { case $1 in
   [A-Z0-9]) printf '0x%02x' "'$1" ;;
   -) echo 0xbd ;; =) echo 0xbb ;; '[') echo 0xdb ;; ']') echo 0xdd ;; ';') echo 0xba ;;
   "'") echo 0xde ;; '\') echo 0xdc ;; ,) echo 0xbc ;; .) echo 0xbe ;; /) echo 0xbf ;;
   *) echo ? ;; esac; }

# Toutes les touches de caracteres (hors <> et `, traitees a part par winemac)
# a leur position QWERTY : code virtuel et caractere de MapVirtualKey.
BAD=$(table positions | while read -r s q vk car reste; do
   if [ "$s" = 0x56 ] || [ "$s" = 0x29 ]; then continue; fi
   [ "$vk" = "$(vk_us "$q")" ] && [ "$car" = "$q" ] || echo "$s:$q:$vk:$car"
done)
vaut "positions : le bloc principal aux positions QWERTY (VK et VK_TO_CHAR)" "$BAD" ""
grep -q 'WASD : .*VK_W a la position W (0x11) VK_A a la position A (0x1e) VK_S a la position S (0x1f) VK_D a la position D (0x20)' \
   "$T/positions" && ok "positions : WASD aux positions WASD" || ko "positions : $(grep '^WASD' "$T/positions")"
grep -q 'cidre: clavier aux positions QWERTY' "$T/positions.err" && ok "positions : annonce au journal" \
   || ko "positions : pas de ligne « cidre: clavier » sur la sortie d'erreur"
if [ "$(table base | awk '{print $1, $3}')" = "$(table positions | awk '{print $1, $3}')" ] &&
   grep -q 'nom 00000409' "$T/base"; then
   vaut "QWERTY US : disposition inchangee" "$(grep 'disposition annoncee' "$T/positions")" \
      "$(grep 'disposition annoncee' "$T/base")"
else
   grep -q 'HKL 0409.*nom 00000409' "$T/positions" && ok "positions : disposition US annoncee" \
      || ko "positions : $(grep 'disposition annoncee' "$T/positions")"
fi
if [ $EN_PLACE = non ] && [ "$(col base 0x10 4)" = A ] && [ "$(col base 0x2c 4)" = W ]; then
   # AZERTY : A/Q et Z/W echangees, M a la position ; (ce que demandait le joueur)
   for p in "0x10 0x41 0x51" "0x1e 0x51 0x41" "0x11 0x5a 0x57" "0x2c 0x57 0x5a" "0x27 0x4d 0xba" "0x32 0xbc 0x4d"; do
      set -- $p
      vaut "AZERTY : $1 passe de $2 a $3" "$(col base $1 3) $(col positions $1 3)" "$2 $3"
   done
   vaut "AZERTY : la touche 1 s'appelle 1 (et non &)" "$(col base 0x02 4) $(col positions 0x02 4)" "& 1"
fi

[ $ECHECS = 0 ] && echo "tout est bon" || echo "$ECHECS echec(s)"
exit $((ECHECS > 0))
