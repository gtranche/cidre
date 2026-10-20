#!/bin/sh
# DLL systeme que le jeu qu'on lance doit prendre dans system32, meme s'il en
# livre une copie dans son dossier (option knowndlls de son profil, noms sans
# .dll separes par des espaces : knowndlls = "d3d12 d3d12core"). Appele par
# lancer_depuis_steam.sh avant de demarrer Wine, et par `cidre set` pour valider.
#
#   knowndlls.sh valider <liste>    la liste sous sa forme canonique ; code 1 et un message si un nom est refuse
#   knowndlls.sh poser [<liste>]    regle le prefixe ($WINEPREFIX) pour le lancement qui suit ; sans liste : rien
#                                   de Cidre ne reste
#
# Windows charge une DLL nommee dans HKLM\System\CurrentControlSet\Control\
# Session Manager\KnownDLLs depuis system32, avant le dossier de l'application ;
# Wine aussi. Cas de Diablo II Resurrected : son dossier contient le d3d12.dll
# de Microsoft pour Windows 7 (D3D12On7). Sous Windows 10, le D3D12 du systeme
# passe devant ; sous Wine, sans cette cle, D3D12On7 se chargeait d'abord, ou
# bien (d3d12=b) le d3d12 builtin de Wine prenait sa place et retombait en
# D3D11, que D2R n'a pas : pointeur nul dans un rappel de fenetre, plus rien a
# l'ecran (manches L2/V2 du 2026-10-20). Avec d3d12 et d3d12core ici, c'est
# vkd3d-proton (system32) qui se charge.
#
# Tous les jeux partagent un prefixe : comme la version de Windows
# (version_windows.sh), la cle est reglee a CHAQUE lancement, pour le jeu qu'on
# lance. Cidre retient dans $WINEPREFIX/.cidre-knowndlls les valeurs qu'il a
# ajoutees lui-meme ; un jeu sans l'option les retire, et seulement elles (les
# KnownDLLs de wine.inf ne sont jamais touchees, une valeur deja la n'est ni
# reecrite ni comptee comme la sienne). Ecrit sans demarrer Wine, par
# l'ecriture de registre de reglages_jeu.sh (le prefixe ne doit etre tenu par
# aucun wineserver).
#
# Codes de retour de `poser` : 0 = regle (ou rien a faire) ; 3 = le prefixe est
# tenu par un wineserver, ou n'existe pas encore : rien n'est ecrit ; 1 = erreur.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
# (CurrentControlSet est un lien vers ControlSet001 : la ruche ne connait que lui)
CLE='System\ControlSet001\Control\Session Manager\KnownDLLs'
MARQUE=$PFX/.cidre-knowndlls

# Les noms de la liste, en minuscules, sans .dll, un par ligne et sans doublon ;
# code 1 si un nom n'est pas fait de lettres, chiffres et soulignes.
noms() {
   l=
   for n in $(printf '%s' "$1" | tr ',;' '  '); do
      n=$(printf '%s' "$n" | tr 'A-Z' 'a-z'); n=${n%.dll}
      case $n in ''|*[!a-z0-9_]*) echo "knowndlls : « $n » refuse (un nom de DLL sans chemin, ex. d3d12)" >&2; return 1 ;; esac
      case " $l " in *" $n "*) ;; *) l="$l $n" ;; esac
   done
   for n in $l; do echo "$n"; done
}
# Les valeurs de la cle, `nom TAB donnee` (nom en minuscules, donnee sans guillemets).
presentes() {
   [ -f "$PFX/system.reg" ] || return 0
   CLEB=$(printf '%s' "$CLE" | sed 's/\\/\\\\/g') LC_ALL=C awk '
      BEGIN { cle = "[" tolower(ENVIRON["CLEB"]) "]" }
      /^\[/ { if (dedans) exit; k = tolower($0); sub(/\][^\]]*$/, "]", k); dedans = (k == cle); next }
      dedans && /^"/ { n = $0; sub(/^"/, "", n); d = n; sub(/".*$/, "", n); sub(/^[^"]*"=/, "", d); gsub(/^"|"$/, "", d); print tolower(n) "\t" d }' "$PFX/system.reg"
}
ecrire() { WINEPREFIX=$PFX sh "$R/tests/reglages_jeu.sh" - ruche system.reg "$CLE" >/dev/null; }

case ${1:-} in
   valider)
      l=$(noms "${2:-}") || exit 1
      printf '%s\n' "$l" | paste -sd ' ' - ;;
   poser)
      voulues=$(noms "${2:-}") || { echo "    knowndlls : liste « ${2:-} » refusee, rien n'est pose"; voulues=; }
      [ -f "$PFX/system.reg" ] || { [ -z "$voulues" ] || echo "    knowndlls : le prefixe n'existe pas encore, $(printf '%s\n' "$voulues" | paste -sd ' ' -) sera pose au prochain lancement"; exit 3; }
      a_nous=$(cat "$MARQUE" 2>/dev/null)
      P=$(presentes)
      retirer=; ajouter=
      for n in $a_nous; do
         printf '%s\n' "$voulues" | grep -qx "$n" && continue
         # retiree seulement si elle est encore telle que Cidre l'a posee
         printf '%s\n' "$P" | grep -qx "$n	$n.dll" && retirer="$retirer $n"
      done
      for n in $voulues; do
         printf '%s\n' "$P" | cut -f1 | grep -qx "$n" || ajouter="$ajouter $n"
      done
      if [ -n "$retirer$ajouter" ]; then
         { for n in $retirer; do printf '%s\t\n' "$n"; done
           for n in $ajouter; do printf '%s\t"%s.dll"\n' "$n" "$n"; done; } | ecrire; rc=$?
         if [ $rc -ne 0 ]; then
            [ $rc -eq 3 ] && echo "    knowndlls : le prefixe est en cours d'usage (un autre jeu tourne), registre laisse" \
                          || echo "    knowndlls : echec de l'ecriture du registre du prefixe"
            exit $rc
         fi
      fi
      # ce qui est a Cidre desormais : ce qu'il avait et qui reste voulu, plus ce qu'il vient d'ajouter
      garde=$(for n in $a_nous; do printf '%s\n' "$voulues" | grep -qx "$n" && echo "$n"; done; for n in $ajouter; do echo "$n"; done)
      if [ -n "$garde" ]; then printf '%s\n' "$garde" | awk '!vu[$0]++' >"$MARQUE"; else rm -f "$MARQUE"; fi
      [ -z "$retirer" ] || echo "    knowndlls :$retirer retire(s) (pose(s) pour un autre jeu)"
      [ -z "$voulues" ] || echo "    knowndlls : $(printf '%s\n' "$voulues" | paste -sd ' ' -) pris dans system32 pour ce jeu (option knowndlls)" ;;
   *) echo "usage : knowndlls.sh valider <liste> | poser [<liste>]" >&2; exit 2 ;;
esac
