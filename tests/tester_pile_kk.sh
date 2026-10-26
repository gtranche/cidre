#!/bin/sh
# Options de KosmicKrisp posees par le lanceur (lancer_depuis_steam.sh) : pile du
# 26/10 en dx12 (pile_kk), demi-precision avec sm66, options de fiche
# (calcul_avant_passe, compile_differee, code_kk), vsync = false -> CIDRE_WSI_VSYNC=0.
# Les blocs sont extraits du lanceur et joues avec un profil d'essai.
#   sh tests/tester_pile_kk.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
L=$R/tests/lancer_depuis_steam.sh
ECHECS=0; N=0
vaut() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "KO    $1 : attendu « $3 », obtenu « $2 »"; ECHECS=$((ECHECS + 1)); fi; }
FN=$(awk '/^KK_OPTIONS=$/,/^}$/' "$L")
PILE=$(awk '/^if \[ "\$\(opt dx12 CIDRE_DX12\)" = true \] && \[ "\$\(opt pile_kk CIDRE_PILE_KK\)" != false \]; then$/,/^done$/' "$L")
DEMI=$(grep 'kk_defaut CIDRE_DEMI_PRECISION' "$L")
VSYNC=$(grep 'export CIDRE_WSI_VSYNC=' "$L")
[ -n "$FN" ] && [ -n "$PILE" ] && [ -n "$DEMI" ] && [ -n "$VSYNC" ] || { echo "KO    blocs introuvables dans le lanceur"; exit 1; }
# jouer <profil (cle=valeur;...)> <famille_gpu> [VAR=valeur ...] : rend KK_OPTIONS
jouer() {
   p=$1; f=$2; shift 2
   env -i PATH="$PATH" HOME="$HOME" R="$R" PROFIL_ESSAI="$p" FAMILLE_GPU="$f" "$@" sh -c '
      profil() { printf "%s\n" "$PROFIL_ESSAI" | tr ";" "\n" | sed -n "s/^$1=//p" | head -1; }
      opt() { eval "v=\${$2:-}"
         case $v in 1) echo true; return ;; 0) echo false; return ;; "") ;; *) echo "$v"; return ;; esac
         profil "$1"; }
      '"$FN"'
      [ "$(opt sm66 CIDRE_SM66)" = true ] && { '"$DEMI"'; }
      '"$PILE"'
      echo "$KK_OPTIONS"' 2>&1
}
vaut "sans dx12 : rien" "$(jouer "" 9)" ""
vaut "dx12, M4 : pile + compression" "$(jouer "dx12=true" 9)" "VISIB=2 RESOLVE_GROUPE=4 FILES=4 AIR_DIRECT=1 TEX_COMPRESSION=3"
vaut "dx12, M1 : pile sans compression" "$(jouer "dx12=true" 7)" "VISIB=2 RESOLVE_GROUPE=4 FILES=4 AIR_DIRECT=1"
vaut "pile_kk = false" "$(jouer "dx12=true;pile_kk=false" 9)" ""
vaut "CIDRE_PILE_KK=0" "$(jouer "dx12=true" 9 CIDRE_PILE_KK=0)" ""
vaut "CIDRE_AIR_DIRECT=0 retire l AIR direct" "$(jouer "dx12=true" 7 CIDRE_AIR_DIRECT=0)" "VISIB=2 RESOLVE_GROUPE=4 FILES=4"
vaut "valeur explicite gardee" "$(jouer "dx12=true" 7 CIDRE_FILES=2)" "VISIB=2 RESOLVE_GROUPE=4 FILES=2 AIR_DIRECT=1"
vaut "sm66 : demi-precision" "$(jouer "dx12=true;sm66=true" 7)" "DEMI_PRECISION=1 VISIB=2 RESOLVE_GROUPE=4 FILES=4 AIR_DIRECT=1"
vaut "sm66, demi_precision = false" "$(jouer "dx12=true;sm66=true;demi_precision=false" 7)" "VISIB=2 RESOLVE_GROUPE=4 FILES=4 AIR_DIRECT=1"
vaut "fiche ER (M1)" "$(jouer 'dx12=true;calcul_avant_passe=true;compile_differee=true;code_kk="lectures_cachees ssbo_sans_bornes"' 7)" \
   "VISIB=2 RESOLVE_GROUPE=4 FILES=4 AIR_DIRECT=1 CALCUL_AVANT_PASSE=1 COMPILE_DIFFEREE=1 LECTURES_CACHEES=1 SSBO_SANS_BORNES=1"
vaut "code_kk : option inconnue ignoree" "$(jouer 'code_kk="deroulers"' 7)" "code_kk : option inconnue ignoree : deroulers"
vaut "CIDRE_SSBO_SANS_BORNES=0 devant la fiche" "$(jouer 'code_kk="ssbo_sans_bornes"' 7 CIDRE_SSBO_SANS_BORNES=0)" ""
vaut "vsync = false -> CIDRE_WSI_VSYNC=0" "$(env -u CIDRE_WSI_VSYNC sh -c "$VSYNC; echo \$CIDRE_WSI_VSYNC")" "0"
vaut "options de cidre set" "$(grep -c 'pile_kk|calcul_avant_passe|compile_differee|demi_precision)' "$R/cidre")" "1"
vaut "defauts de profils.toml" "$(grep -cE '^(pile_kk|demi_precision|calcul_avant_passe|compile_differee|code_kk) =' "$R/outil-steam/profils.toml")" "5"
vaut "syntaxe du lanceur" "$(sh -n "$L" && echo bonne)" "bonne"
echo "$N verifications, $ECHECS en echec"
exit $((ECHECS > 0))
