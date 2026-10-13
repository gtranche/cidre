#!/bin/sh
# Teste l'option windows_version (tests/version_windows.sh) sur un prefixe
# fabrique : deux ruches au format de Wine, aucun Wine lance.
#   1. les valeurs admises, leur forme canonique, une valeur inconnue ;
#   2. un jeu sans l'option sur un prefixe neuf : rien n'est touche ;
#   3. un jeu avec l'option : la valeur est posee, le reste de la ruche intact ;
#   4. deux jeux a la suite : le second, sans l'option, tourne en win10 ;
#   5. une valeur inconnue : dite, et le jeu part en win10 ;
#   6. une version restee collee au prefixe par `winecfg -v` (les lanceurs
#      d'avant) : reconnue et remise, a l'octet pres ; un Windows 9x aussi ;
#      la version par defaut d'un autre Wine n'est pas prise pour une collee ;
#   7. le prefixe tenu par un wineserver, ou pas encore cree : rien n'est ecrit ;
#   8. la chaine entiere : fiche de la base, profil utilisateur, `cidre set` et
#      `cidre unset` ;
#   9. le lanceur : il appelle version_windows.sh une fois le journal ouvert et
#      avant de demarrer Wine, et n'ecrit jamais dans un journal pas encore nomme.
# Tout se passe dans un dossier temporaire.
#   sh tests/tester_version_windows.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
VW="$R/tests/version_windows.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-version.XXXXXX")
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
export WINEPREFIX="$T/pfx" CIDRE_SERVEUR_WINE=non
export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/base"
mkdir -p "$WINEPREFIX" "$HOME" "$CIDRE_DIR/games" "$CIDRE_PROFILS_BASE"
U="$WINEPREFIX/user.reg"; S="$WINEPREFIX/system.reg"

# Les deux ruches d'un prefixe neuf (Wine 11) : seulement les cles qui comptent
# ici, et de quoi voir que les voisines ne bougent pas. `ruches <version>` les
# remet a neuf ; avec une version, system.reg est celui que `winecfg -v
# <version>` laisse.
ruches() {
   cat >"$U" <<'FIN'
WINE REGISTRY Version 2
;; All keys relative to REGISTRY\\User\\S-1-5-21-0-0-0-1000

#arch=win64

[Software\\Editeur\\Jeu] 1791905543
#time=1dd5b280b278856
"Version"="1.2"
"Binaire"=hex:65,75,3b,32,30,3b,61,73,69,61,2c,61,75,2c,\
  65,75,2c,68,6b,00

[Software\\Wine\\AppDefaults] 1790330887
#time=1dd4cd5c3035b32

[Software\\Wine\\AppDefaults\\vieux.exe] 1790330887
#time=1dd4cd5c3035b32
"Version"="winxp"

[Software\\Wine\\DllOverrides] 1790330887
#time=1dd4cd5c3035b32
"*dxgi"="native"
FIN
   nt='"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CurrentType"="Multiprocessor Free"
"CurrentVersion"="6.3"
"DigitalProductId"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00
"EditionId"="Professional"
"ProductId"="12345-oem-0000001-54321"
"ProductName"="Windows 10 Pro"
"SystemRoot"="C:\\windows"
"UBR"=dword:000016a4'
   type=WinNT; sp=00000000; w9=
   case ${1:-} in
      win7) nt='"CSDVersion"="Service Pack 1"
"CurrentBuild"="7601"
"CurrentBuildNumber"="7601"
"CurrentMajorVersionNumber"=dword:00000006
"CurrentMinorVersionNumber"=dword:00000001
"CurrentType"="Multiprocessor Free"
"CurrentVersion"="6.1"
"DigitalProductId"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00
"EditionId"="Professional"
"ProductId"="12345-oem-0000001-54321"
"ProductName"="Microsoft Windows 7"
"SystemRoot"="C:\\windows"'
         sp=00000100 ;;
      win98) nt='"CurrentType"="Multiprocessor Free"
"DigitalProductId"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00
"EditionId"="Professional"
"ProductId"="12345-oem-0000001-54321"
"SystemRoot"="C:\\windows"'
         w9='"ProductName"="Microsoft Windows 98"
"SubVersionNumber"=" A "
"VersionNumber"="4.10.2222"
' ;;
      autre-wine) nt=$(printf '%s\n' "$nt" | sed 's/19045/26100/; s/Windows 10 Pro/Windows 11 Pro/') ;;
   esac
   {
      printf 'WINE REGISTRY Version 2\n;; All keys relative to REGISTRY\\\\Machine\n\n#arch=win64\n\n'
      printf '[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion] 1790350687\n#time=1dd4d03dc9fe816\n"ProductId"="12345-oem-0000001-54321"\n"ProgramFilesDir"="C:\\\\Program Files"\n%s\n' "$w9"
      printf '[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion] 1791915063\n#time=1dd5b3e357d629a\n%s\n\n' "$nt"
      printf '[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts] 1791915063\n"Arial (TrueType)"="arial.ttf"\n\n'
      printf '[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion] 1790593512\n#time=1dd4f393be237ac\n"ProductId"="12345-oem-0000001-54321"\n%s\n' "$w9"
      printf '[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows NT\\\\CurrentVersion] 1790593512\n#time=1dd4f393be32ce8\n%s\n\n' "$nt"
      printf '[System\\\\ControlSet001\\\\Control\\\\ProductOptions] 1790330898\n#time=1dd4cd5c9bc5866\n"ProductType"="%s"\n\n' "$type"
      printf '[System\\\\ControlSet001\\\\Control\\\\Session Manager\\\\Environment] 1790333337\n"NUMBER_OF_PROCESSORS"="10"\n"OS"="Windows_NT"\n\n'
      printf '[System\\\\ControlSet001\\\\Control\\\\Windows] 1790330898\n#time=1dd4cd5c9bc5956\n"CSDVersion"=dword:%s\n' "$sp"
   } >"$S"
   rm -f "$U.avant-cidre" "$S.avant-cidre"
}
ruches; cp "$U" "$T/user.neuf"; cp "$S" "$T/system.neuf"
poser() { sortie=$(sh "$VW" poser "$@" 2>&1); rc=$?; }
reg_cle() { CLE="[$2] " awk 'index($0, ENVIRON["CLE"]) == 1 { d = 1; next } d && /^\[/ { exit } d && !/^#time/' "$1"; }   # <ruche> <cle>
version() { reg_cle "$U" 'Software\\Wine' | sed -n 's/^"Version"="\(.*\)"$/\1/p'; }
intact() { # <libelle> : hors de la cle [Software\\Wine] (et des lignes vides de fin), user.reg est celui du prefixe neuf
   verif "$1" "" "$(CLE='[Software\\Wine] ' awk 'index($0, ENVIRON["CLE"]) == 1 { d = 1; next } d && /^\[/ { d = 0 } !d { l[++n] = $0 }
      END { while (n && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i] }' "$U" | diff - "$T/user.neuf" 2>&1)"
}

echo "== 1. valeurs admises"
verif "liste" "win11 win10 win81 win8 win7 vista winxp64 winxp win2k" "$(sh "$VW" liste | tr '\n' ' ' | sed 's/ $//')"
for v in $(sh "$VW" liste); do
   verif "valider $v" "$v 0" "$(sh "$VW" valider "$v" 2>&1) $?"
   # ... et c'est bien un nom que ntdll connait, quand ses sources sont la
   [ ! -f "$R/src/wine11/dlls/ntdll/version.c" ] || { grep -q "{ L\"$v\"," "$R/src/wine11/dlls/ntdll/version.c" && ok "$v : connu de ntdll" || echec "$v : inconnu de ntdll (version.c)"; }
done
verif "casse" "win7" "$(sh "$VW" valider Win7)"
verif "synonymes" "vista win2k win81" "$(sh "$VW" valider winvista) $(sh "$VW" valider win2000) $(sh "$VW" valider win8.1)"
for v in win95 win98 windows7 '' 'win7 vista' 'win7;x' '*' nt40; do
   sh "$VW" valider "$v" >/dev/null 2>&1 && echec "valider « $v » : accepte" || ok "valider « $v » : refuse"
done
contient "valider : le message cite les valeurs" "win11, win10, win81" "$(sh "$VW" valider win95 2>&1)"

echo "== 2. jeu sans l'option, prefixe neuf"
poser
verif "code 0, rien a dire" "0 " "$rc $sortie"
verif "user.reg pas touche" "" "$(cmp "$U" "$T/user.neuf" 2>&1)"
verif "system.reg pas touche" "" "$(cmp "$S" "$T/system.neuf" 2>&1)"
poser win10
verif "win10 demande = le defaut : rien n'est ecrit" "0  " "$rc $sortie $(cmp "$U" "$T/user.neuf" 2>&1)"

echo "== 3. jeu avec l'option"
poser win7
verif "win7 : code 0" "0" "$rc"
contient "win7 : dit au journal" "version de Windows : win7 pour ce jeu (option windows_version)" "$sortie"
verif "win7 : HKCU\\Software\\Wine\\Version" "win7" "$(version)"
intact "win7 : le reste de user.reg intact (cle de l'application, DllOverrides, valeur binaire)"
verif "win7 : la cle par application d'un autre programme reste" '"Version"="winxp"' "$(reg_cle "$U" 'Software\\Wine\\AppDefaults\\vieux.exe')"
verif "win7 : system.reg pas touche" "" "$(cmp "$S" "$T/system.neuf" 2>&1)"
verif "win7 : copie d'origine de la ruche" "" "$(cmp "$U.avant-cidre" "$T/user.neuf" 2>&1)"
cp "$U" "$T/user.win7"
poser win7
verif "relance du meme jeu : ruche inchangee, toujours dit" "0 1 " "$rc $(printf '%s\n' "$sortie" | grep -c 'win7 pour ce jeu') $(cmp "$U" "$T/user.win7" 2>&1)"
poser WinXP
verif "autre jeu, autre version (casse corrigee)" "0 winxp 1" "$rc $(version) $(reg_cle "$U" 'Software\\Wine' | grep -c .)"

echo "== 4. deux jeux a la suite"
poser win7; poser
verif "jeu sans l'option apres un jeu en win7 : valeur retiree" "0 " "$rc $(version)"
contient "... et dit" "win7 etait reste dans le prefixe (un autre jeu) : retire, ce jeu tourne en win10" "$sortie"
intact "... le reste de user.reg intact"
verif "... une seule cle [Software\\Wine], gardee vide" "1" "$(grep -c '^\[Software\\\\Wine\] ' "$U")"
poser
verif "troisieme lancement : plus rien a faire" "0 " "$rc $sortie"
poser vista; poser win81
verif "deux jeux a options differentes : la derniere seule" "win81 1" "$(version) $(reg_cle "$U" 'Software\\Wine' | grep -c .)"
poser

echo "== 5. valeur inconnue"
poser win7; poser win95
verif "win95 : code 0, le jeu part en win10 (la valeur du jeu d'avant est retiree)" "0 " "$rc $(version)"
contient "win95 : message" "windows_version = « win95 » n'est pas une valeur connue (win11, win10, win81, win8, win7, vista, winxp64, winxp, win2k) : le jeu est lance en win10" "$sortie"
ruches
poser 'n importe quoi'
verif "valeur farfelue sur un prefixe neuf : rien n'est ecrit" "0 " "$rc $(cmp "$U" "$T/user.neuf" 2>&1)$(cmp "$S" "$T/system.neuf" 2>&1)"

echo "== 6. version restee collee au prefixe (winecfg -v)"
ruches win7; cp "$S" "$T/system.win7"
poser
verif "win7 colle, jeu sans l'option : code 0" "0" "$rc"
contient "... reconnu et dit" "le prefixe etait regle sur Microsoft Windows 7 (build 7601) pour tous les jeux (winecfg -v) : remis a Windows 10" "$sortie"
verif "... system.reg redevenu celui d'un prefixe neuf, a l'octet pres" "" "$(cmp "$S" "$T/system.neuf" 2>&1)"
verif "... copie d'origine de system.reg" "" "$(cmp "$S.avant-cidre" "$T/system.win7" 2>&1)"
verif "... user.reg pas touche" "" "$(cmp "$U" "$T/user.neuf" 2>&1)"
poser
verif "... lancement suivant : rien a faire" "0  " "$rc $sortie $(cmp "$S" "$T/system.neuf" 2>&1)"
ruches win7
poser winxp
verif "win7 colle, jeu en winxp : prefixe remis ET option posee" "0 winxp  2" "$rc $(version) $(cmp "$S" "$T/system.neuf" 2>&1) $(printf '%s\n' "$sortie" | wc -l | tr -d ' ')"
ruches win98
poser
contient "win98 colle : reconnu" "le prefixe etait regle sur Microsoft Windows 98 (4.10.2222)" "$sortie"
for vue in 'Software' 'Software\\Wow6432Node'; do
   verif "win98 colle : valeurs NT revenues ($vue)" '"CurrentBuild"="19045" "CurrentVersion"="6.3" "ProductName"="Windows 10 Pro" "UBR"=dword:000016a4' \
      "$(reg_cle "$S" "$vue\\\\Microsoft\\\\Windows NT\\\\CurrentVersion" | grep '^"CurrentBuild"\|^"CurrentVersion"\|^"ProductName"\|^"UBR"' | sort | tr '\n' ' ' | sed 's/ $//')"
   verif "win98 colle : valeurs 9x retirees, voisines gardees ($vue)" '"ProductId"="12345-oem-0000001-54321"' "$(reg_cle "$S" "$vue\\\\Microsoft\\\\Windows\\\\CurrentVersion" | grep -v ProgramFilesDir | grep .)"
done
verif "win98 colle : la sous-cle voisine intacte" '"Arial (TrueType)"="arial.ttf"' "$(reg_cle "$S" 'Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts' | grep .)"
poser
verif "win98 colle : plus rien au lancement suivant" "0 " "$rc $sortie"
ruches autre-wine; cp "$S" "$T/system.autre"
poser
verif "version par defaut d'un autre Wine (build 26100, « Windows 11 Pro ») : pas une collee, pas touchee" "0  " "$rc $sortie $(cmp "$S" "$T/system.autre" 2>&1)"
ruches win7; sed 's/Microsoft Windows 7/Microsoft Windows 10/; s/7601/19045/g' "$S" >"$S.x" && mv "$S.x" "$S"; cp "$S" "$T/system.w10"
poser
verif "\`winecfg -v win10\` (meme build) : rien a remettre" "0  " "$rc $sortie $(cmp "$S" "$T/system.w10" 2>&1)"

echo "== 7. prefixe occupe, prefixe absent"
ruches win7; cp "$S" "$T/system.win7"
sortie=$(CIDRE_SERVEUR_WINE=oui sh "$VW" poser winxp 2>&1); rc=$?
verif "wineserver en vie : code 3, aucune ruche touchee" "3  " "$rc $(cmp "$U" "$T/user.neuf" 2>&1) $(cmp "$S" "$T/system.win7" 2>&1)"
contient "... et dit" "le prefixe est en cours d'usage (un autre jeu tourne), registre laisse" "$sortie"
ruches; poser win7
sortie=$(CIDRE_SERVEUR_WINE=oui sh "$VW" poser 2>&1); rc=$?
verif "wineserver en vie, jeu sans l'option : code 3, la valeur du jeu en cours reste" "3 win7" "$rc $(version)"
contient "... et dit laquelle" "elle reste win7 pour ce lancement" "$sortie"
sortie=$(WINEPREFIX="$T/absent" sh "$VW" poser win7 2>&1); rc=$?
verif "prefixe pas encore cree : code 3" "3" "$rc"
contient "... et dit" "le prefixe n'existe pas encore" "$sortie"
verif "prefixe pas encore cree, jeu sans l'option : code 3, rien a dire" "3" "$(WINEPREFIX="$T/absent" sh "$VW" poser 2>&1; echo $?)"
sh "$VW" >/dev/null 2>&1; verif "sans commande : usage" "2" "$?"

echo "== 8. de la fiche au prefixe ; cidre set / unset"
# ce que fait le lanceur : l'environnement d'abord, sinon le profil resolu du jeu
lancer() { # <id>
   WINVER=${CIDRE_WINDOWS_VERSION:-$(sh "$R/tests/profil_cidre.sh" "$1" | sed -n 's/^windows_version=//p' | head -1)}
   poser "$WINVER"
}
ruches
printf '[jeu]\nnom = "Vieux jeu"\n\n[cidre]\nwindows_version = "win7"\n' >"$CIDRE_PROFILS_BASE/111.toml"
mkdir -p "$CIDRE_DIR/games/111" "$CIDRE_DIR/games/222"
lancer 111; verif "fiche de la base (windows_version = \"win7\")" "win7" "$(version)"
lancer 222; verif "puis un jeu sans fiche : win10" "" "$(version)"
sh "$R/cidre" set 222 windows_version WinXP >/dev/null 2>&1
verif "cidre set : code 0, forme canonique entre guillemets" '0 windows_version = "winxp"' "$? $(grep windows_version "$CIDRE_PROFILS")"
lancer 222; verif "... applique au lancement" "winxp" "$(version)"
lancer 111; verif "... et l'autre jeu garde la sienne" "win7" "$(version)"
sh "$R/cidre" set 111 windows_version win10 >/dev/null 2>&1
lancer 111; verif "cidre set win10 par-dessus la fiche : le jeu revient en win10" "" "$(version)"
sortie=$(sh "$R/cidre" set 222 windows_version win95 2>&1); rc=$?
verif "cidre set, valeur inconnue : code 2, profil inchange" '2 windows_version = "winxp"' "$rc $(sed -n '/^\[222\]/,/^\[/p' "$CIDRE_PROFILS" | grep windows_version)"
contient "... et la liste des valeurs" "windows_version attend une de ces valeurs : win11, win10" "$sortie"
sh "$R/cidre" unset 222 windows_version >/dev/null 2>&1
verif "cidre unset : code 0, option retiree" "0 " "$? $(sed -n '/^\[222\]/,/^\[/p' "$CIDRE_PROFILS" | grep windows_version)"
lancer 222; verif "... le jeu revient en win10" "" "$(version)"
sh "$R/cidre" unset 111 windows_version >/dev/null 2>&1
lancer 111; verif "cidre unset sur le jeu a fiche : la fiche reprend la main" "win7" "$(version)"
export CIDRE_WINDOWS_VERSION=vista; lancer 111; unset CIDRE_WINDOWS_VERSION; verif "CIDRE_WINDOWS_VERSION passe devant le profil" "vista" "$(version)"
printf '[cidre]\nwindows_version = "windows 7"\n' >"$CIDRE_PROFILS_BASE/333.toml"
lancer 333
verif "fiche a valeur inconnue : win10" "0 " "$rc $(version)"
contient "... et dit" "« windows 7 » n'est pas une valeur connue" "$sortie"
intact "apres tout cela : le reste de user.reg intact"
verif "... et system.reg jamais touche" "" "$(cmp "$S" "$T/system.neuf" 2>&1)"

echo "== 9. le lanceur"
L="$R/tests/lancer_depuis_steam.sh"
ligne() { grep -n "$1" "$L" | head -1 | cut -d: -f1; }
j=$(ligne '^JOURNAL='); v=$(ligne 'version_windows.sh" poser'); w=$(ligne "etape2_pile_arm64ec.sh\" 'c:.faux_steam.exe'")
[ -n "$j" ] && [ -n "$v" ] && [ -n "$w" ] && [ "$j" -lt "$v" ] && [ "$v" -lt "$w" ] \
   && ok "version_windows.sh appele apres l'ouverture du journal et avant le premier processus Wine" \
   || echec "ordre attendu dans le lanceur : JOURNAL= ($j) < version_windows.sh ($v) < client de service ($w)"
verif "le lanceur lit l'option (environnement, puis profil)" "1" "$(grep -c '^WINVER=\${CIDRE_WINDOWS_VERSION:-\$(profil windows_version)}$' "$L")"
verif "le lanceur n'appelle plus winecfg" "0" "$(grep -v '^ *#' "$L" | grep -c winecfg)"
# la panne d'avant : `winecfg -v` redirige vers "$JOURNAL" avant que JOURNAL soit
# nomme -- la redirection echouait, la commande n'etait jamais lancee, sans un mot
verif "aucune ecriture dans le journal avant qu'il soit nomme" "" "$(awk -v j="$j" 'NR < j && !/^ *#/ && /\$JOURNAL/ { print NR ": " $0 }' "$L")"
verif "version_windows.sh est livre avec le runtime" "1" "$(grep -c ' version_windows\.sh ' "$R/tests/empaqueter_runtime.sh")"
for s in tests/version_windows.sh tests/reglages_jeu.sh tests/lancer_depuis_steam.sh tests/tester_version_windows.sh cidre; do
   sh -n "$R/$s" 2>/dev/null && ok "sh -n $s" || echec "sh -n $s"
done
contient "documente dans outil-steam/profils.toml" "windows_version  version de Windows que voit le jeu" "$(cat "$R/outil-steam/profils.toml")"
for v in $(sh "$VW" liste); do
   grep -q "^#.*[ ,]$v[, ]" "$R/outil-steam/profils.toml" && ok "profils.toml cite $v" || echec "profils.toml ne cite pas $v"
done

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
