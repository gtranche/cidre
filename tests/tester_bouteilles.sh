#!/bin/sh
# Teste la reprise des jeux Steam Windows deja installes par CrossOver, Whisky
# ou Heroic, sur des bouteilles fabriquees :
#   1. tests/trouver_jeux_bouteilles.sh : les trois sources, les bouteilles
#      rangees ailleurs (registre de Whisky, configuration de Heroic), une
#      bibliotheque Steam sur un autre lecteur, les manifestes complets,
#      incomplets, sans dossier, trop legers, le jeu deja dans Cidre, les noms
#      a espaces et a guillemets, le jeu present dans deux bouteilles, --json ;
#   2. `cidre import` : un faux PEAK repris d'une fausse bouteille CrossOver --
#      forme de games/<appid>, manifeste, clone (inodes distincts, bouteille
#      intacte au fichier pres), `cidre list`, reprises.conf, les refus ;
#   3. `cidre import --move` : le jeu et son manifeste quittent la bouteille,
#      le reste n'y bouge pas ;
#   4. entre deux volumes (une image disque montee le temps du test) : copie
#      ordinaire annoncee, refus quand la place manque, --move ;
#   5. `cidre-outil bibliotheque --bouteilles` : "source":"bouteille" dans
#      `cidre library --json` (noms lus dans le cache du client Steam, s'il est la) ;
#   6. sh -n sur les scripts, et l'aide de `cidre`.
# Tout se passe dans un dossier temporaire, avec un HOME a part : ni les vraies
# bouteilles, ni le dossier Cidre, ni le client Steam ne sont lus ou touches.
#   sh tests/tester_bouteilles.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
D="$R/tests/trouver_jeux_bouteilles.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-bouteilles.XXXXXX")
T=$(cd "$T" && pwd -P)   # le detecteur rend des chemins physiques (/private/var/...)
VOL=
trap '[ -z "$VOL" ] || hdiutil detach -quiet -force "$VOL" 2>/dev/null; rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
VRAI_HOME=$HOME
export HOME="$T/home" CIDRE_DIR="$T/cidre"
export CIDRE_BOUTEILLES_CROSSOVER="$T/CrossOver/Bottles" CIDRE_BOUTEILLES_WHISKY="$T/Whisky/Bottles"
export CIDRE_WHISKY_REGISTRE="$T/Whisky/BottleVM.plist"
export CIDRE_BOUTEILLES_HEROIC="$T/Heroic/Prefixes" CIDRE_HEROIC_CONFIG="$T/heroic"
mkdir -p "$HOME" "$CIDRE_DIR/games"
TAB=$(printf '\t')
STEAM="drive_c/Program Files (x86)/Steam/steamapps"
octets() { find "$1" -type f -exec stat -f %z {} + | awk '{ t += $1 } END { print t + 0 }'; }
# Un jeu dans une bibliotheque Steam : son manifeste (comme l'ecrit le client
# Windows, fins de ligne CRLF comprises) et, sauf `-`, son dossier.
jeu() { # <steamapps> <appid> <nom> <installdir|-> <StateFlags> <build> [taille declaree] [exe]
   lib=$1; appid=$2; nomj=$3; rep=$4; etat=$5; build=$6; exe=${8:-Jeu.exe}
   mkdir -p "$lib/common"
   if [ "$rep" != - ]; then
      mkdir -p "$lib/common/$rep/Donnees"
      [ "$exe" = - ] || printf 'MZ\220\000faux programme Windows %s\n' "$appid" >"$lib/common/$rep/$exe"
      printf 'MZ\220\000' >"$lib/common/$rep/UnityCrashHandler64.exe" 2>/dev/null
      [ "$exe" = - ] && rm -f "$lib/common/$rep/UnityCrashHandler64.exe"
      dd if=/dev/urandom of="$lib/common/$rep/Donnees/niveau 1.bin" bs=1k count=40 2>/dev/null
   fi
   taille=${7:-$( [ "$rep" = - ] && echo 1000 || octets "$lib/common/$rep" )}
   printf '"AppState"\r\n{\r\n\t"appid"\t\t"%s"\r\n\t"Universe"\t\t"1"\r\n\t"LauncherPath"\t\t"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe"\r\n\t"name"\t\t"%s"\r\n\t"StateFlags"\t\t"%s"\r\n\t"installdir"\t\t"%s"\r\n\t"LastPlayed"\t\t"1790000000"\r\n\t"SizeOnDisk"\t\t"%s"\r\n\t"buildid"\t\t"%s"\r\n\t"InstalledDepots"\r\n\t{\r\n\t\t"%s1"\r\n\t\t{\r\n\t\t\t"manifest"\t\t"42"\r\n\t\t\t"size"\t\t"7"\r\n\t\t}\r\n\t}\r\n\t"UserConfig"\r\n\t{\r\n\t\t"name"\t\t"pas le nom du jeu"\r\n\t}\r\n}\r\n' \
      "$appid" "$nomj" "$etat" "$([ "$rep" = - ] && echo Absent || echo "$rep")" "$taille" "$build" "$appid" >"$lib/appmanifest_$appid.acf"
}
# l'etat d'un dossier, fichier par fichier : inode, taille, date, nom
cliche() { (cd "$1" && find . -exec stat -f '%i %z %m %N' {} + | sort); }
ligne() { sh "$D" "$@" | awk -F'\t' -v a="$APPID" '$1 == a' ; }
champs() { APPID=$1; shift; ligne "$@"; }

# --- les bouteilles ---------------------------------------------------------
CX="$T/CrossOver/Bottles/Steam"; CXS="$CX/$STEAM"
mkdir -p "$CX/drive_c/users/crossover/AppData/LocalLow/LandCrab/PEAK"
echo sauvegarde >"$CX/drive_c/users/crossover/AppData/LocalLow/LandCrab/PEAK/slot.peak"
jeu "$CXS" 3527290 PEAK PEAK 4 25667990 "" PEAK.exe
dd if=/dev/zero of="$CXS/common/PEAK/Donnees/gros.bin" bs=1m count=48 2>/dev/null   # de quoi voir un clone
jeu "$CXS" 3527290 PEAK PEAK 4 25667990 "$(octets "$CXS/common/PEAK")" PEAK.exe
PEAK_OCTETS=$(octets "$CXS/common/PEAK")
jeu "$CXS" 111 "Demi Jeu" "Demi Jeu" 1026 5
jeu "$CXS" 222 "Sans Dossier" - 4 5
jeu "$CXS" 333 "Trop Leger" "Trop Leger" 4 5 52428800
jeu "$CXS" 444 "Deja La" "Deja La" 4 5
mkdir -p "$CIDRE_DIR/games/444"
jeu "$CXS" 555 "En Retard" "En Retard" 6 20
jeu "$CXS" 228980 "Steamworks Common Redistributables" "Steamworks Shared" 4 5
jeu "$CXS" 1001 "Sans Exe" "Sans Exe" 4 5 "" -
jeu "$CXS" 1002 'Jeu \"Guillemets\" & Co' "Guillemets" 4 5
# une bouteille au nom a espaces, et une bibliotheque Steam sur son lecteur D:
CX2="$T/CrossOver/Bottles/Mes Jeux Steam"
jeu "$CX2/$STEAM" 666 "Jeu Avec Espaces" "Jeu Avec Espaces" 4 5
mkdir -p "$CX2/dosdevices" "$T/Disque D/SteamLibrary"
ln -s ../drive_c "$CX2/dosdevices/c:"; ln -s "$T/Disque D" "$CX2/dosdevices/d:"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"D:\\\\SteamLibrary"\n\t}\n}\n' >"$CX2/$STEAM/libraryfolders.vdf"
jeu "$T/Disque D/SteamLibrary/steamapps" 777 "Sur Le Disque D" "SurD" 4 5
mkdir -p "$T/CrossOver/Bottles/Pas une bouteille"
# Whisky : un dossier par UUID, le nom dans Metadata.plist ; une bouteille
# rangee ailleurs, connue par le registre
W1="$T/Whisky/Bottles/6F9619FF-8B86-D011-B42D-00C04FC964FF"
jeu "$W1/$STEAM" 888 "Chez Whisky" "ChezWhisky" 4 5
plutil -create xml1 "$W1/Metadata.plist"
plutil -insert info -dictionary "$W1/Metadata.plist"; plutil -insert info.name -string "Ma Bouteille" "$W1/Metadata.plist"
W2="$T/Ailleurs/Bouteille Externe"
jeu "$W2/$STEAM" 889 "Whisky Ailleurs" "Ailleurs" 4 5
plutil -create xml1 "$T/Whisky/BottleVM.plist"
plutil -insert paths -array "$T/Whisky/BottleVM.plist"; plutil -insert paths.0 -dictionary "$T/Whisky/BottleVM.plist"
plutil -insert paths.0.relative -string "file://$(printf '%s' "$W2" | sed 's/ /%20/g')/" "$T/Whisky/BottleVM.plist"
# Heroic : le dossier Prefixes, et un prefixe que nomme la configuration d'un jeu
H1="$T/Heroic/Prefixes/default"
jeu "$H1/$STEAM" 999 "Chez Heroic" "ChezHeroic" 4 5
jeu "$H1/$STEAM" 998 "Reste Chez Heroic" "Reste" 4 5
jeu "$H1/$STEAM" 555 "En Retard" "En Retard" 4 10
jeu "$H1/$STEAM" 3527290 PEAK PEAK 4 100 "" PEAK.exe
H2="$T/Prefixes Heroic/perso"
jeu "$H2/$STEAM" 1000 "Heroic Perso" "Perso" 4 5
mkdir -p "$T/heroic/GamesConfig"
printf '{\n  "abc": {\n    "winePrefix": "%s",\n    "wineVersion": {}\n  }\n}\n' "$H2" >"$T/heroic/GamesConfig/abc.json"
printf '{"defaultSettings": {"defaultWinePrefix": "%s"}}\n' "$H1" >"$T/heroic/config.json"
AVANT=$(cliche "$T/CrossOver"; cliche "$T/Whisky"; cliche "$T/Heroic"; cliche "$T/Ailleurs"; cliche "$T/Disque D"; cliche "$T/Prefixes Heroic")

echo "== 1. detection"
verif "PEAK dans la bouteille CrossOver : appid, nom, source, bouteille, chemin, build, taille" \
   "3527290${TAB}PEAK${TAB}crossover${TAB}Steam${TAB}$CXS/common/PEAK${TAB}25667990${TAB}$PEAK_OCTETS" "$(champs 3527290 | head -1)"
verif "jeu dans deux bouteilles : le build le plus recent d'abord" "crossover heroic" "$(champs 3527290 | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
verif "installation incomplete (StateFlags 1026) ecartee" "" "$(champs 111)"
verif "manifeste sans dossier ecarte" "" "$(champs 222)"
verif "dossier trop leger pour son manifeste ecarte" "" "$(champs 333)"
verif "--rapide ne pese pas les dossiers" "333" "$(champs 333 --rapide | cut -f1)"
verif "jeu deja dans le dossier Cidre ecarte" "" "$(champs 444)"
verif "Steamworks Common Redistributables ecarte" "" "$(champs 228980)"
verif "StateFlags 6 (mise a jour en attente) retenu" "crossover heroic" "$(champs 555 | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
verif "nom a guillemets" 'Jeu "Guillemets" & Co' "$(champs 1002 | cut -f2)"
verif "le nom vient du premier niveau du manifeste" "Jeu Avec Espaces" "$(champs 666 | cut -f2)"
verif "bouteille et chemin a espaces" "Mes Jeux Steam${TAB}$CX2/$STEAM/common/Jeu Avec Espaces" "$(champs 666 | cut -f4,5)"
verif "bibliotheque Steam sur le lecteur D: de la bouteille" "Mes Jeux Steam${TAB}$T/Disque D/SteamLibrary/steamapps/common/SurD" "$(champs 777 | cut -f4,5)"
verif "Whisky : nom de la bouteille lu dans Metadata.plist" "whisky${TAB}Ma Bouteille" "$(champs 888 | cut -f3,4)"
verif "Whisky : bouteille rangee ailleurs (registre, URL a %20)" "whisky${TAB}Bouteille Externe" "$(champs 889 | cut -f3,4)"
verif "Heroic : dossier Prefixes" "heroic${TAB}default" "$(champs 999 | cut -f3,4)"
verif "Heroic : prefixe nomme par la configuration d'un jeu" "heroic${TAB}perso" "$(champs 1000 | cut -f3,4)"
verif "un prefixe connu par deux chemins ne compte qu'une fois" "1" "$(champs 999 | wc -l | tr -d ' ')"
verif "sept colonnes" "7" "$(sh "$D" | awk -F'\t' '{ print NF }' | sort -u)"
verif "--complet : StateFlags, racine, manifeste" "4${TAB}$CX${TAB}$CXS/appmanifest_3527290.acf" "$(champs 3527290 --complet | head -1 | cut -f8-10)"
verif "tous les jeux retenus" "555 555 666 777 888 889 998 999 1000 1001 1002 3527290 3527290" "$(sh "$D" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
sh "$D" --json >"$T/liste.json"
plutil -convert xml1 -o /dev/null "$T/liste.json" 2>/dev/null && ok "--json : JSON valide" || echec "--json : JSON invalide"
contient "--json : champs du jeu" "{\"appid\":3527290,\"nom\":\"PEAK\",\"source\":\"crossover\",\"bouteille\":\"Steam\",\"chemin\":\"$CXS/common/PEAK\",\"buildid\":25667990,\"taille\":$PEAK_OCTETS,\"maj_en_attente\":false}" "$(cat "$T/liste.json")"
contient "--json : guillemets echappes" '"nom":"Jeu \"Guillemets\" & Co"' "$(cat "$T/liste.json")"
contient "--json : mise a jour en attente" '"bouteille":"Steam","chemin":"'"$CXS"'/common/En Retard","buildid":20,"taille":'"$(octets "$CXS/common/En Retard")"',"maj_en_attente":true' "$(cat "$T/liste.json")"
raisons=$(sh "$D" --verbeux 2>&1 >/dev/null)
contient "--verbeux : installation incomplete" "ignore : 111 Demi Jeu (crossover : Steam), installation incomplete (StateFlags 1026)" "$raisons"
contient "--verbeux : dossier absent" "ignore : 222 Sans Dossier (crossover : Steam), dossier absent" "$raisons"
contient "--verbeux : dossier incomplet" "ignore : 333 Trop Leger (crossover : Steam), dossier incomplet (0 Mo sur 50 attendus)" "$raisons"
contient "--verbeux : deja dans Cidre" "ignore : 444 Deja La (crossover : Steam), deja dans le dossier Cidre" "$raisons"
verif "aucune source : liste vide" "[]" "$(CIDRE_BOUTEILLES_CROSSOVER= CIDRE_BOUTEILLES_WHISKY= CIDRE_WHISKY_REGISTRE= CIDRE_BOUTEILLES_HEROIC= CIDRE_HEROIC_CONFIG= sh "$D" --json)"
verif "\`cidre bottles\` : un jeu par ligne" "13" "$(sh "$R/cidre" bottles | tail -n +2 | wc -l | tr -d ' ')"
verif "la detection n'ecrit rien dans les bouteilles" "$AVANT" "$(cliche "$T/CrossOver"; cliche "$T/Whisky"; cliche "$T/Heroic"; cliche "$T/Ailleurs"; cliche "$T/Disque D"; cliche "$T/Prefixes Heroic")"

echo "== 2. cidre import : un faux PEAK repris d'une fausse bouteille CrossOver"
G="$CIDRE_DIR/games"
libre_avant=$(df -Pk "$G" | awk 'NR == 2 { print $4 }')
sortie=$(sh "$R/cidre" import 3527290 2>&1); rc=$?
libre_apres=$(df -Pk "$G" | awk 'NR == 2 { print $4 }')
verif "code de retour" "0" "$rc"
contient "compte rendu : source et bouteille" "repris : PEAK (3527290), depuis crossover « Steam »" "$sortie"
contient "compte rendu : clone APFS" "mode        : clone APFS" "$sortie"
contient "compte rendu : executable verifie apres coup" "executable  : PEAK.exe" "$sortie"
contient "compte rendu : ou sont restees les sauvegardes" "sauvegardes : restees dans la bouteille, sous $CX/drive_c/users/crossover" "$sortie"
[ -f "$G/3527290/PEAK.exe" ] && [ -f "$G/3527290/Donnees/niveau 1.bin" ] && ok "les fichiers du jeu a la racine de games/3527290" || echec "games/3527290 n'a pas la forme attendue : $(ls "$G/3527290" 2>&1)"
M="$G/3527290/steamapps/appmanifest_3527290.acf"
verif "manifeste : nom" "PEAK" "$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$M" | head -1)"
verif "manifeste : StateFlags, build, taille" "4 25667990 $PEAK_OCTETS" "$(for c in StateFlags buildid SizeOnDisk; do sed -n 's/.*"'$c'"[[:space:]]*"\(.*\)".*/\1/p' "$M" | head -1; done | tr '\n' ' ' | sed 's/ $//')"
verif "manifeste : sans le chemin du client de la bouteille" "0" "$(grep -c LauncherPath "$M")"
verif "manifeste : depots conserves" "1" "$(grep -c '"35272901"' "$M")"
verif "contenu identique a celui de la bouteille" "" "$(diff -r "$CXS/common/PEAK" "$G/3527290" 2>&1 | grep -v '^Only in .*: steamapps$')"
i1=$(stat -f %i "$CXS/common/PEAK/PEAK.exe"); i2=$(stat -f %i "$G/3527290/PEAK.exe")
[ -n "$i1" ] && [ -n "$i2" ] && [ "$i1" != "$i2" ] && ok "clone : inodes distincts ($i1, $i2)" || echec "clone : inodes $i1 et $i2"
verif "clone : un seul lien par fichier (pas de lien physique)" "1 1" "$(stat -f %l "$CXS/common/PEAK/Donnees/gros.bin" "$G/3527290/Donnees/gros.bin" | tr '\n' ' ' | sed 's/ $//')"
# 48 Mo clones : la place libre ne bouge pas (au bruit du disque pres)
pris=$(( (libre_avant - libre_apres) / 1024 ))
[ "$pris" -lt 24 ] && ok "clone : pas de place prise ($pris Mo pour un jeu de $(( PEAK_OCTETS / 1048576 )) Mo)" || echec "clone : $pris Mo pris pour un jeu de $(( PEAK_OCTETS / 1048576 )) Mo (copie ordinaire ?)"
verif "la bouteille est intacte, au fichier pres" "$AVANT" "$(cliche "$T/CrossOver"; cliche "$T/Whisky"; cliche "$T/Heroic"; cliche "$T/Ailleurs"; cliche "$T/Disque D"; cliche "$T/Prefixes Heroic")"
echo "ecrit par Cidre" >>"$G/3527290/PEAK.exe"
verif "ecrire dans la copie ne touche pas la bouteille" "$AVANT" "$(cliche "$T/CrossOver"; cliche "$T/Whisky"; cliche "$T/Heroic"; cliche "$T/Ailleurs"; cliche "$T/Disque D"; cliche "$T/Prefixes Heroic")"
fiche=$(sh "$R/cidre" list --json | grep '"id":"3527290"')
contient "cidre list --json : un jeu Cidre, installe" "{\"id\":\"3527290\",\"appid\":3527290,\"nom\":\"PEAK\",\"plateforme\":\"windows\",\"lancement\":\"cidre\",\"source\":\"cidre\",\"installe\":true,\"wrapper\":null,\"chemin\":\"$G/3527290\",\"taille\":$PEAK_OCTETS,\"dernier_lancement\":1790000000}" "$fiche"
verif "cidre info : source" "source      : cidre" "$(sh "$R/cidre" info 3527290 2>/dev/null | grep '^source')"
verif "repris : plus propose, dans aucune bouteille" "" "$(champs 3527290)"
verif "reprises.conf : appid, source, bouteille, racine, mode" "3527290${TAB}crossover${TAB}Steam${TAB}$CX${TAB}clone" "$(cut -f1-5 "$CIDRE_DIR/reprises.conf")"
sortie=$(sh "$R/cidre" import 3527290 2>&1); verif "deja repris : refuse" "1" "$?"
contient "deja repris : le dit" "3527290 est deja dans le dossier Cidre" "$sortie"
sortie=$(sh "$R/cidre" import 111 2>&1); verif "installation incomplete : refuse" "1" "$?"
contient "installation incomplete : dit pourquoi" "installation incomplete (StateFlags 1026)" "$sortie"
[ ! -e "$G/111" ] && ok "installation incomplete : rien de cree" || echec "games/111 existe"
sortie=$(sh "$R/cidre" import 1001 2>&1); verif "jeu sans .exe : refuse" "1" "$?"
[ ! -e "$G/1001" ] && ok "jeu sans .exe : rien de cree" || echec "games/1001 existe"
sh "$R/cidre" import 31337 >/dev/null 2>&1; verif "appid inconnu : refuse" "1" "$?"
sh "$R/cidre" import >/dev/null 2>&1; verif "sans appid : usage" "2" "$?"
sh "$R/cidre" import ../444 >/dev/null 2>&1; verif "appid qui n'en est pas un : usage" "2" "$?"
verif "aucun dossier de travail laisse" "" "$(ls -A "$G" | grep reprise)"
sortie=$(sh "$R/cidre" import 666 2>&1); verif "bouteille et jeu a espaces : repris" "0" "$?"
[ -f "$G/666/Donnees/niveau 1.bin" ] && ok "bouteille et jeu a espaces : fichiers la" || echec "games/666 incomplet"
sh "$R/cidre" import 555 heroic:default >/dev/null 2>&1; verif "bouteille choisie (source:nom)" "0" "$?"
verif "bouteille choisie : c'est son build" "10" "$(sed -n 's/.*"buildid"[[:space:]]*"\(.*\)".*/\1/p' "$G/555/steamapps/appmanifest_555.acf" | head -1)"
verif "StateFlags 6 dans la bouteille CrossOver : toujours la" "6" "$(sed -n 's/.*"StateFlags"[[:space:]]*"\([0-9]*\)".*/\1/p' "$CXS/appmanifest_555.acf")"
sh "$R/cidre" import 777 "Bouteille Inconnue" >/dev/null 2>&1; verif "bouteille inconnue : refuse" "1" "$?"
sortie=$(sh "$R/cidre" import 777 --json 2>/dev/null); verif "--json : repris" "0" "$?"
verif "--json : la sortie est la fiche du jeu" "{\"id\":\"777\",\"appid\":777,\"nom\":\"Sur Le Disque D\",\"plateforme\":\"windows\",\"lancement\":\"cidre\",\"source\":\"cidre\",\"installe\":true" "$(printf '%s' "$sortie" | cut -d, -f1-7)"
verif "--json : une seule ligne" "1" "$(printf '%s\n' "$sortie" | wc -l | tr -d ' ')"
verif "sans --move, aucune bouteille n'a bouge" "$AVANT" "$(cliche "$T/CrossOver"; cliche "$T/Whisky"; cliche "$T/Heroic"; cliche "$T/Ailleurs"; cliche "$T/Disque D"; cliche "$T/Prefixes Heroic")"

echo "== 3. cidre import --move"
H1S="$H1/$STEAM"
inode=$(stat -f %i "$H1S/common/ChezHeroic/Jeu.exe")
RESTE=$(cliche "$H1S/common/Reste"; cat "$H1S/appmanifest_998.acf")
sortie=$(sh "$R/cidre" import 999 --move 2>&1); verif "code de retour" "0" "$?"
contient "compte rendu : deplace" "mode        : deplace" "$sortie"
[ ! -e "$H1S/common/ChezHeroic" ] && [ ! -e "$H1S/appmanifest_999.acf" ] && ok "le jeu et son manifeste ont quitte la bouteille" || echec "la bouteille a encore le jeu 999"
verif "deplace, pas copie : meme inode" "$inode" "$(stat -f %i "$G/999/Jeu.exe")"
verif "manifeste dans le dossier Cidre" "Chez Heroic" "$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$G/999/steamapps/appmanifest_999.acf" | head -1)"
verif "le reste de la bouteille n'a pas bouge" "$RESTE" "$(cliche "$H1S/common/Reste"; cat "$H1S/appmanifest_998.acf")"
verif "reprises.conf : mode deplace" "deplace" "$(awk -F'\t' '$1 == 999 { print $5 }' "$CIDRE_DIR/reprises.conf")"
sh "$R/cidre" import --deplacer 998 >/dev/null 2>&1; verif "--deplacer, option avant l'appid" "0" "$?"
[ -f "$G/998/Jeu.exe" ] && [ ! -e "$H1S/common/Reste" ] && ok "--deplacer : deplace" || echec "--deplacer : 998 pas deplace"

echo "== 4. entre deux volumes"
if hdiutil create -quiet -size 40m -fs HFS+ -volname CidreEssai "$T/vol.dmg" 2>/dev/null &&
   mkdir "$T/vol" && hdiutil attach -quiet -nobrowse -mountpoint "$T/vol" "$T/vol.dmg" 2>/dev/null; then
   VOL="$T/vol"
   EXT="$VOL/Bouteilles/Externe"
   jeu "$EXT/$STEAM" 1200 "Sur Un Autre Disque" "AutreDisque" 4 5
   jeu "$EXT/$STEAM" 1400 "A Deplacer" "ADeplacer" 4 5
   export CIDRE_BOUTEILLES_CROSSOVER="$T/CrossOver/Bottles:$VOL/Bouteilles"
   verif "deux dossiers de bouteilles (liste a deux-points)" "crossover${TAB}Externe" "$(champs 1200 | cut -f3,4)"
   EXT_AVANT=$(cliche "$EXT")
   sortie=$(sh "$R/cidre" import 1200 2>&1); verif "autre volume : repris" "0" "$?"
   contient "autre volume : copie annoncee" "attention : pas de clone possible (autre volume, ou volume non APFS) : copie de" "$sortie"
   contient "autre volume : mode copie" "mode        : copie" "$sortie"
   verif "autre volume : contenu identique" "" "$(diff -r "$EXT/$STEAM/common/AutreDisque" "$G/1200" 2>&1 | grep -v '^Only in .*: steamapps$')"
   verif "autre volume : la bouteille est intacte" "$EXT_AVANT" "$(cliche "$EXT")"
   sh "$R/cidre" import 1400 --move >/dev/null 2>&1; verif "autre volume, --move : repris" "0" "$?"
   [ -f "$G/1400/Jeu.exe" ] && [ ! -e "$EXT/$STEAM/common/ADeplacer" ] && [ ! -e "$EXT/$STEAM/appmanifest_1400.acf" ] &&
      ok "autre volume, --move : copie puis efface de la bouteille" || echec "autre volume, --move : 1400 mal deplace"
   # la place manque : le dossier Cidre sur le petit volume, un jeu de 48 Mo a y copier
   H1P="$H1S/common/PEAK"
   dd if=/dev/zero of="$H1P/gros.bin" bs=1m count=48 2>/dev/null
   sed -i '' 's/\("SizeOnDisk"[[:space:]]*\)"[0-9]*"/\1"1000"/' "$H1S/appmanifest_3527290.acf"
   sortie=$(CIDRE_DIR="$VOL/cidre" sh "$R/cidre" import 3527290 2>&1); verif "place insuffisante : refuse" "1" "$?"
   contient "place insuffisante : le dit" "place insuffisante sur le volume du dossier Cidre" "$sortie"
   verif "place insuffisante : rien de cree" "" "$(ls -A "$VOL/cidre/games" 2>/dev/null)"
   [ -f "$H1P/gros.bin" ] && ok "place insuffisante : la bouteille est intacte" || echec "place insuffisante : la bouteille a perdu des fichiers"
else
   echo "  (image disque impossible a creer ou a monter : cas « autre volume » non verifies)"
fi

echo "== 5. cidre library : les jeux des bouteilles, a reprendre"
if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1; fi
if [ -x "$R/build/cidre-outil" ] && [ -f "$VRAI_HOME/Library/Application Support/Steam/appcache/appinfo.vdf" ]; then
   # (le cache du client Steam, le vrai, lu sans rien y ecrire : il donne les noms)
   printf 'License packageID 1:\n - State   : Active\n - Apps    : 400, 620,  (2 in total)\n' >"$T/licences.txt"
   printf '620\tPortal 2\tcrossover\tMes "Jeux"\t/b/common/Portal 2\t7\t1000\n620\tPortal 2\theroic\tdefault\t/h/Portal 2\t6\t1000\n400\tPortal\twhisky\tW\t/w/Portal\t3\t900\n424242424\tJeu Du Manifeste\theroic\tdefault\t/h/Jeu\t5\t77\n' >"$T/b.tsv"
   bib=$(HOME=$VRAI_HOME "$R/build/cidre-outil" bibliotheque --bouteilles "$T/b.tsv" "$T/licences.txt" 400)
   printf '%s' "$bib" | plutil -convert xml1 -o /dev/null - 2>/dev/null && ok "JSON valide" || echec "JSON invalide : $bib"
   contient "jeu d'une bouteille : source, origine, bouteille, chemin (la premiere ligne)" '{"appid": 620, "nom": "Portal 2", "plateformes": ["windows", "macos", "linux"], "installe": false, "source": "bouteille", "origine": "crossover", "bouteille": "Mes \"Jeux\"", "chemin": "/b/common/Portal 2", "buildid": 7, "taille": 1000}' "$(printf '%s' "$bib" | sed 's/"plateformes": \[[^]]*\]/"plateformes": ["windows", "macos", "linux"]/g')"
   contient "jeu deja installe : pas de source" '"installe": true}' "$(printf '%s' "$bib" | tr '{' '\n' | grep '"appid": 400,')"
   contient "jeu hors des licences : montre, au nom de son manifeste" '{"appid": 424242424, "nom": "Jeu Du Manifeste", "plateformes": ["windows"], "installe": false, "source": "bouteille", "origine": "heroic", "bouteille": "default", "chemin": "/h/Jeu", "buildid": 5, "taille": 77}' "$bib"
   verif "sans --bouteilles : rien ne change" "0" "$(HOME=$VRAI_HOME "$R/build/cidre-outil" bibliotheque "$T/licences.txt" 400 | grep -c bouteille)"
   contient "texte : a reprendre" "a reprendre (crossover : Mes \"Jeux\")" "$(HOME=$VRAI_HOME "$R/build/cidre-outil" bibliotheque --texte --bouteilles - "$T/licences.txt" 400 <"$T/b.tsv")"
else
   echo "  (cidre-outil ou cache du client Steam absent : non verifie)"
fi

echo "== 6. syntaxe"
for f in cidre tests/trouver_jeux_bouteilles.sh tests/reprendre_jeu_bouteille.sh tests/tester_bouteilles.sh; do
   sh -n "$R/$f" 2>/dev/null && ok "sh -n $f" || echec "sh -n $f"
done

# (l'aide est un here-document : un accent grave s'y executerait)
verif "cidre help : rien sur la sortie d'erreur" "" "$(sh "$R/cidre" help 2>&1 >/dev/null)"
verif "cidre help : import et bottles documentes" "2" "$(sh "$R/cidre" help 2>/dev/null | grep -c -e '^  cidre import <appid>' -e '^  cidre bottles ')"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
