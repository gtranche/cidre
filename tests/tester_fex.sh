#!/bin/sh
# Reglages de FEX repris de Proton ARM64 (`fex_cache_disque`, `fex_x87_reduit`,
# `fex_maxinst`, `fex_multiblock`).
#
#   tester_fex.sh          le profil livre, `cidre set` et le bloc du lanceur
#                          (sans Wine : le bloc est extrait du lanceur et
#                          execute avec un profil et un environnement donnes)
#
# L'effet en jeu se mesure ailleurs (etude-proton.md, §9.3).
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester_fex.XXXXXX")
trap 'rm -rf "$T"' EXIT
ECHECS=0
ok()  { echo "ok    $1"; }
ko()  { echo "ECHEC $1"; ECHECS=$((ECHECS + 1)); }
vaut() { [ "$2" = "$3" ] && ok "$1" || ko "$1 : « $2 » au lieu de « $3 »"; }

# --- profil livre et cidre set ---
export CIDRE_PROFILS="$T/profils.toml"
def() { sh "$R/tests/profil_cidre.sh" defaut | sed -n "s/^$1=//p"; }
vaut "fex_cache_disque : defaut livre (coupe)" "$(def fex_cache_disque)" false
vaut "fex_x87_reduit : defaut livre (coupe)" "$(def fex_x87_reduit)" false
vaut "fex_maxinst : defaut livre (celui de FEX)" "$(def fex_maxinst)" 0
vaut "fex_multiblock : defaut livre (celui de FEX)" "$(def fex_multiblock)" true
for essai in "fex_cache_disque false" "fex_x87_reduit true" "fex_x87_reduit auto" "fex_maxinst 0" "fex_maxinst 5000" "fex_multiblock false" "fex_multiblock true"; do
   set -- $essai
   sh "$R/cidre" set defaut "$1" "$2" >/dev/null 2>&1 && ok "cidre set defaut $essai" || ko "cidre set defaut $essai refuse"
done
vaut "fex_x87_reduit auto relu" "$(sh "$R/tests/profil_cidre.sh" 0 | sed -n 's/^fex_x87_reduit=//p')" auto
for essai in "fex_x87_reduit 32" "fex_maxinst -1" "fex_maxinst 99999" "fex_cache_disque 1" "fex_multiblock 0"; do
   set -- $essai
   sh "$R/cidre" set defaut "$1" "$2" >/dev/null 2>&1 && ko "cidre set accepte $essai" || ok "cidre set refuse $essai"
done
unset CIDRE_PROFILS

# --- le bloc du lanceur, tel quel ---
L=$R/tests/lancer_depuis_steam.sh
FEX=$(awk '/^# --- reglages FEX : debut ---/,/^# --- reglages FEX : fin ---/' "$L")
[ -n "$FEX" ] || ko "bloc FEX introuvable dans le lanceur"
# Un exe PE32 (i386) et un PE32+ (x86-64) minimaux : MZ, e_lfanew = 64, puis
# « PE\0\0 » et le champ Machine.
pe() { # <fichier> <machine en hexa, petit-boutiste : 4c01 ou 6486>
   { printf 'MZ'; head -c 58 /dev/zero; printf '\100\000\000\000'; printf 'PE\000\000'
     printf "$(echo "$2" | sed 's/\(..\)/\\x\1/g')"; head -c 64 /dev/zero; } >"$1"
}
pe "$T/jeu32.exe" 4c01
pe "$T/jeu64.exe" 6486
# est_pe32, recopie du lanceur (sa definition, entre accolades)
EST_PE32=$(awk '/^est_pe32\(\) \{/,/^\}/' "$L")
[ -n "$EST_PE32" ] || ko "est_pe32 introuvable dans le lanceur"
lanceur() { # <bloc> <profil cle=valeur;...> <exe> [VAR=valeur...] ; rend les variables posees
   bloc=$1; profil_essai=$2; exe=$3; shift 3
   env -u FEX_DISKCACHE -u FEX_X87REDUCEDPRECISION -u FEX_MAXINST -u FEX_MULTIBLOCK \
       -u CIDRE_FEX_CACHE_DISQUE -u CIDRE_FEX_X87_REDUIT -u CIDRE_FEX_MAXINST -u CIDRE_FEX_MULTIBLOCK \
       "$@" PROFIL_ESSAI="$profil_essai" DOSSIER="$T" PROG="$exe" sh -c '
      set -e
      profil() { printf "%s\n" "$PROFIL_ESSAI" | tr ";" "\n" | sed -n "s/^$1=//p" | head -1; }
      opt() { eval "v=\${$2:-}"
         case $v in 1) echo true; return ;; 0) echo false; return ;; "") ;; *) echo "$v"; return ;; esac
         profil "$1"; }
      '"$EST_PE32"'
      '"$bloc"'
      echo "cache=${FEX_DISKCACHE-} x87=${FEX_X87REDUCEDPRECISION-} maxinst=${FEX_MAXINST-} multiblock=${FEX_MULTIBLOCK-}"'
}
F0="fex_cache_disque=false;fex_x87_reduit=false;fex_maxinst=0"
vaut "fex : defauts livres, jeu 32 bits : rien" "$(lanceur "$FEX" "$F0" jeu32.exe)" "cache= x87= maxinst= multiblock="
vaut "fex : defauts livres, CIDRE_FEX_CACHE_DISQUE=1" "$(lanceur "$FEX" "$F0" jeu64.exe CIDRE_FEX_CACHE_DISQUE=1)" "cache=1 x87= maxinst= multiblock="
F="fex_cache_disque=true;fex_x87_reduit=auto;fex_maxinst=500"
vaut "fex : reglages de Proton, jeu 64 bits" "$(lanceur "$FEX" "$F" jeu64.exe)" "cache=1 x87= maxinst=500 multiblock="
vaut "fex : reglages de Proton, jeu 32 bits" "$(lanceur "$FEX" "$F" jeu32.exe)" "cache=1 x87=1 maxinst=500 multiblock="
vaut "fex : x87 true, jeu 64 bits" "$(lanceur "$FEX" "fex_x87_reduit=true" jeu64.exe)" "cache= x87=1 maxinst= multiblock="
vaut "fex : x87 false, jeu 32 bits" "$(lanceur "$FEX" "fex_x87_reduit=false" jeu32.exe)" "cache= x87= maxinst= multiblock="
vaut "fex : maxinst 0 = defaut de FEX" "$(lanceur "$FEX" "fex_maxinst=0" jeu64.exe)" "cache= x87= maxinst= multiblock="
vaut "fex : maxinst invalide ignore" "$(lanceur "$FEX" "fex_maxinst=abc" jeu64.exe)" "cache= x87= maxinst= multiblock="
vaut "fex : exe absent, auto = rien" "$(lanceur "$FEX" "$F" absent.exe)" "cache=1 x87= maxinst=500 multiblock="
vaut "fex : CIDRE_FEX_CACHE_DISQUE=0" "$(lanceur "$FEX" "$F" jeu64.exe CIDRE_FEX_CACHE_DISQUE=0)" "cache= x87= maxinst=500 multiblock="
vaut "fex : CIDRE_FEX_X87_REDUIT=0 sur un 32 bits" "$(lanceur "$FEX" "$F" jeu32.exe CIDRE_FEX_X87_REDUIT=0)" "cache=1 x87= maxinst=500 multiblock="
vaut "fex : CIDRE_FEX_MAXINST=0 devant le profil" "$(lanceur "$FEX" "$F" jeu64.exe CIDRE_FEX_MAXINST=0)" "cache=1 x87= maxinst= multiblock="
vaut "fex : CIDRE_FEX_MAXINST=2000" "$(lanceur "$FEX" "$F" jeu64.exe CIDRE_FEX_MAXINST=2000)" "cache=1 x87= maxinst=2000 multiblock="
vaut "fex : variables FEX_* explicites gardees" \
   "$(lanceur "$FEX" "$F" jeu32.exe FEX_DISKCACHE=0 FEX_X87REDUCEDPRECISION=0 FEX_MAXINST=5000)" "cache=0 x87=0 maxinst=5000 multiblock="
vaut "fex : multiblock true = defaut de FEX" "$(lanceur "$FEX" "fex_multiblock=true" jeu64.exe)" "cache= x87= maxinst= multiblock="
B="fex_maxinst=500;fex_multiblock=false"
vaut "fex : fiche D2R (maxinst 500, multiblock false)" "$(lanceur "$FEX" "$B" jeu64.exe)" "cache= x87= maxinst=500 multiblock=0"
vaut "fex : CIDRE_FEX_MULTIBLOCK=1 devant le profil" "$(lanceur "$FEX" "$B" jeu64.exe CIDRE_FEX_MULTIBLOCK=1)" "cache= x87= maxinst=500 multiblock="
vaut "fex : CIDRE_FEX_MULTIBLOCK=0" "$(lanceur "$FEX" "fex_multiblock=true" jeu64.exe CIDRE_FEX_MULTIBLOCK=0)" "cache= x87= maxinst= multiblock=0"
vaut "fex : FEX_MULTIBLOCK explicite garde" "$(lanceur "$FEX" "$B" jeu64.exe FEX_MULTIBLOCK=1)" "cache= x87= maxinst=500 multiblock=1"

[ $ECHECS = 0 ] && echo "tout est bon" || echo "$ECHECS echec(s)"
exit $((ECHECS > 0))
