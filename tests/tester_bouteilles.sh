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
#   6. les sauvegardes a la reprise (tests/reprendre_saves_bouteille.sh, par
#      `cidre import`) : absentes cote Cidre, plus anciennes, plus recentes,
#      absentes de la bouteille, introuvables puis designees (--dossier), jeu
#      que Steam Cloud synchronise -- Steam d'abord : API, dossier macOS lie
#      qui a deja une sauvegarde (meme plus ancienne : gardee), dossier vide
#      (comble), fichiers connus dans le nuage (rien copie), --forcer --,
#      sauvegardes dans le dossier du jeu, rattrapage d'une reprise ancienne
#      (--saves), refus ;
#   7. `cidre import --move` sur une bouteille en cours d'usage : refuse, rien
#      ne bouge ;
#   8. sh -n sur les scripts, et l'aide de `cidre`.
# Tout se passe dans un dossier temporaire, avec un HOME et un prefixe Wine a
# part : ni les vraies bouteilles, ni le dossier Cidre, ni son disque C:, ni le
# client Steam ne sont lus ou touches. Les fiches de la base de profils sont
# coupees (CIDRE_FICHE_*) : chaque cas dit ce que sa fiche declare.
#   sh tests/tester_bouteilles.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
D="$R/tests/trouver_jeux_bouteilles.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-bouteilles.XXXXXX")
T=$(cd "$T" && pwd -P)   # le detecteur rend des chemins physiques (/private/var/...)
VOL=
FAUX=   # les faux processus du cas « bouteille en usage »
trap '[ -z "$FAUX" ] || kill $FAUX 2>/dev/null; [ -z "$VOL" ] || hdiutil detach -quiet -force "$VOL" 2>/dev/null; rm -rf "$T"' EXIT
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
# le disque C: de Cidre : un faux prefixe, jamais wine/pfx-arm64ec
export WINEPREFIX="$T/pfx"; UC="$WINEPREFIX/drive_c/users/joueur"; mkdir -p "$UC/AppData"
export CIDRE_FICHE_STEAM_CLOUD=- CIDRE_FICHE_SAUVEGARDES=- CIDRE_FICHE_DOSSIERS_STEAM=- CIDRE_MAISON="$T/maison"
unset CIDRE_PREFIXE_UTIL CIDRE_JEU_DOSSIER CIDRE_SAVES_DIR CIDRE_SAVES_STEAM CIDRE_PS CIDRE_LSOF
# jamais de vraie seance Steam (tests/seance_steam_cloud.sh) : le client de ce Mac est peut-etre ouvert
export CIDRE_SEANCE_STEAM=0
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
# (la forme qu'ecrit Whisky 2.3.5 : releve sur des bouteilles creees par son outil)
cat >"$W1/Metadata.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>dxvkConfig</key>
	<dict><key>dxvk</key><false/><key>dxvkAsync</key><true/><key>dxvkHud</key><dict><key>off</key><dict/></dict></dict>
	<key>fileVersion</key>
	<dict><key>build</key><string></string><key>major</key><integer>1</integer><key>minor</key><integer>0</integer><key>patch</key><integer>0</integer><key>preRelease</key><string></string></dict>
	<key>info</key>
	<dict><key>blocklist</key><array/><key>name</key><string>Ma Bouteille « été » &amp; co</string><key>pins</key><array/></dict>
	<key>metalConfig</key>
	<dict><key>dxrEnabled</key><false/><key>metalHud</key><false/><key>metalTrace</key><false/></dict>
	<key>wineConfig</key>
	<dict><key>avxEnabled</key><false/><key>enhancedSync</key><dict><key>msync</key><dict/></dict><key>windowsVersion</key><string>win10</string></dict>
</dict>
</plist>
FIN
W2="$T/Ailleurs/Bouteille Externe"
jeu "$W2/$STEAM" 889 "Whisky Ailleurs" "Ailleurs" 4 5
plutil -create xml1 "$T/Whisky/BottleVM.plist"
plutil -insert paths -array "$T/Whisky/BottleVM.plist"; plutil -insert paths.0 -dictionary "$T/Whisky/BottleVM.plist"
plutil -insert paths.0.relative -string "file://$(printf '%s' "$W2" | sed 's/ /%20/g')/" "$T/Whisky/BottleVM.plist"
# (son registre note aussi les bouteilles du dossier Bottles, sans barre finale)
plutil -insert paths.1 -dictionary "$T/Whisky/BottleVM.plist"
plutil -insert paths.1.relative -string "file://$W1" "$T/Whisky/BottleVM.plist"
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
verif "Whisky : nom de la bouteille lu dans Metadata.plist (accents, guillemets, esperluette)" "whisky${TAB}Ma Bouteille « été » & co" "$(champs 888 | cut -f3,4)"
verif "Whisky : bouteille du dossier Bottles aussi notee au registre : une seule fois" "1" "$(champs 888 | wc -l | tr -d ' ')"
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
verif "--bouteilles : les bouteilles elles-memes, une fois chacune" \
   "crossover${TAB}Mes Jeux Steam${TAB}$CX2|crossover${TAB}Steam${TAB}$CX|heroic${TAB}default${TAB}$H1|heroic${TAB}perso${TAB}$H2|whisky${TAB}Bouteille Externe${TAB}$W2|whisky${TAB}Ma Bouteille « été » & co${TAB}$W1" \
   "$(sh "$D" --bouteilles | sort | tr '\n' '|' | sed 's/|$//')"
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
contient "compte rendu : sauvegardes ramenees (dossier Unity au nom du jeu)" "sauvegardes : 1 fichier(s) ramene(s) de la bouteille" "$sortie"
contient "compte rendu : d'ou" "de   : $CX/drive_c/users/crossover/AppData/LocalLow/LandCrab/PEAK" "$sortie"
contient "compte rendu : vers ou" "vers : $UC/AppData/LocalLow/LandCrab/PEAK" "$sortie"
verif "la sauvegarde est sur le disque C: de Cidre" "sauvegarde" "$(cat "$UC/AppData/LocalLow/LandCrab/PEAK/slot.peak" 2>/dev/null)"
verif "sa date est celle de la bouteille" "$(stat -f %m "$CX/drive_c/users/crossover/AppData/LocalLow/LandCrab/PEAK/slot.peak")" "$(stat -f %m "$UC/AppData/LocalLow/LandCrab/PEAK/slot.peak" 2>/dev/null)"
verif "le dossier trouve est note dans saves.conf" "3527290${TAB}AppData/LocalLow/LandCrab/PEAK" "$(cat "$CIDRE_DIR/saves.conf" 2>/dev/null)"
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
printf '%s' "$sortie" | plutil -convert json -o /dev/null - 2>/dev/null && ok "--json : JSON valide" || echec "--json : JSON invalide : $sortie"
contient "--json : reprise_sauvegardes, rien de trouve dans la bouteille" '"reprise_sauvegardes":{"appid":777,"etat":"introuvable","fichiers":0,' "$sortie"
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

echo "== 6. les sauvegardes a la reprise"
valide() { printf '%s' "$2" | plutil -convert json -o /dev/null - 2>/dev/null && ok "$1" || echec "$1 : JSON invalide : $2"; }
# un champ (chaine ou nombre) d'une sortie JSON ; a cle repetee, le dernier
cs() { printf '%s' "$2" | sed -n 's/.*"'"$1"'":"\{0,1\}\([^",}]*\).*/\1/p'; }
ES="$T/Essais/Bottles"; B="$ES/Jeux"; BS="$B/$STEAM"; BU="$B/drive_c/users/crossover"
export CIDRE_BOUTEILLES_CROSSOVER="$ES" CIDRE_BOUTEILLES_WHISKY= CIDRE_WHISKY_REGISTRE= CIDRE_BOUTEILLES_HEROIC= CIDRE_HEROIC_CONFIG=
mkdir -p "$BU/AppData/LocalLow" "$BU/AppData/Roaming" "$BU/AppData/Local" "$BU/Documents" "$B/drive_c/users/Public/AppData/Roaming"
date_bouteille() { touch -t 202606010000 "$@"; }   # les sauvegardes de la bouteille datent de juin 2026
# 2001 : un jeu Unity, dont le dossier de sauvegarde porte le nom du produit
# (app.info), pas celui du jeu ; a cote, le dossier plus recent d'un autre jeu
jeu "$BS" 2001 "Un Jeu Unity" "JeuUnity" 4 5 "" Lanceur.exe
mkdir -p "$BS/common/JeuUnity/Lanceur_Data"; printf 'Petit Studio\r\nMon Produit\r\n' >"$BS/common/JeuUnity/Lanceur_Data/app.info"
S1="$BU/AppData/LocalLow/Petit Studio/Mon Produit"; mkdir -p "$S1/slots"
echo un >"$S1/slots/1.sav"; echo deux >"$S1/slots/2.sav"; echo profil >"$S1/profil.json"; echo journal >"$S1/Player.log"
mkdir -p "$BU/AppData/LocalLow/Petit Studio/Autre Jeu"; echo autre >"$BU/AppData/LocalLow/Petit Studio/Autre Jeu/save.dat"
touch -t 202801010000 "$BU/AppData/LocalLow/Petit Studio/Autre Jeu/save.dat"
# 2002 : la fiche dit ou ; cote Cidre, un fichier plus ancien, un plus recent, un identique, un absent
jeu "$BS" 2002 "Jeu Deux" "JeuDeux" 4 5
S2="$BU/AppData/Roaming/Studio2/Jeu2"; C2="$UC/AppData/Roaming/Studio2/Jeu2"; mkdir -p "$S2" "$C2"
for f in a b c d; do echo "bouteille $f" >"$S2/$f.sav"; done; date_bouteille "$S2"/*.sav
echo "cidre ancien" >"$C2/a.sav"; touch -t 202501010000 "$C2/a.sav"
echo "cidre recent" >"$C2/b.sav"; touch -t 202801010000 "$C2/b.sav"
cp -p "$S2/c.sav" "$C2/c.sav"; echo "propre a cidre" >"$C2/e.sav"
# 2003 : saves.conf dit ou, la bouteille n'a rien ; 2004 : personne ne sait ou
jeu "$BS" 2003 "Jeu Trois" "JeuTrois" 4 5
jeu "$BS" 2004 "Jeu Quatre" "JeuQuatre" 4 5
S4="$BU/AppData/Roaming/Bizarre Nom"; mkdir -p "$S4"; echo x >"$S4/partie.bin"
# 2005 : Steam Cloud par l'API (stockage du client Steam de la bouteille), et un dossier local
jeu "$BS" 2005 "Jeu Cinq" "JeuCinq" 4 5
REM="$B/drive_c/Program Files (x86)/Steam/userdata/123456/2005/remote"; mkdir -p "$REM"; echo nuage >"$REM/user_0.dat"
S5="$BU/AppData/Roaming/Jeu Cinq"; mkdir -p "$S5"; echo "local" >"$S5/local.sav"
# 2006 : Steam Cloud par un dossier macOS lie, qui a deja une sauvegarde -- plus
# ANCIENNE que celle de la bouteille : Steam a la priorite quand meme
jeu "$BS" 2006 "Jeu Six" "JeuSix" 4 5
S6="$BU/AppData/LocalLow/Dev6/Jeu6"; MAC="$T/maison/Library/Application Support/Dev6.Jeu6"; mkdir -p "$S6" "$MAC"
echo "windows" >"$S6/win.sav"; echo "windows recent" >"$S6/commun.sav"; date_bouteille "$S6"/*.sav
echo "mac ancien" >"$MAC/commun.sav"; touch -t 202501010000 "$MAC/commun.sav"
lien() { printf 'steam-lien\tAppData/LocalLow/Dev%s/Jeu%s => Library/Application Support/Dev%s.Jeu%s' "$1" "$1" "$1" "$1"; }
LIEN=$(lien 6)
# 2014 : dossier macOS lie vide, et le client Steam n'a jamais synchronise le jeu ;
# 2015 : vide, mais le client connait des fichiers du nuage pour macOS ;
# 2016 : vide, le client ne connait qu'un fichier declare pour Windows (comme PEAK)
UD="$HOME/Library/Application Support/Steam/userdata/4242"
cache_steam() { # <appid> <fichier> <taille> <platformstosync2>
   mkdir -p "$UD/$1"
   printf '"%s"\n{\n\t"ChangeNumber"\t\t"3"\n\t"ostype"\t\t"-102"\n\t"%s"\n\t{\n\t\t"root"\t\t"12"\n\t\t"size"\t\t"%s"\n\t\t"localtime"\t\t"0"\n\t\t"time"\t\t"%s"\n\t\t"remotetime"\t\t"%s"\n\t\t"sha"\t\t"%s"\n\t\t"syncstate"\t\t"2"\n\t\t"persiststate"\t\t"0"\n\t\t"platformstosync2"\t\t"%s"\n\t}\n}\n' \
      "$1" "$2" "$3" "$([ "$3" -gt 0 ] && echo 1791067661 || echo 0)" "$([ "$3" -gt 0 ] && echo 1791067661 || echo 0)" \
      "$([ "$3" -gt 0 ] && echo 425f5cba8cfeb4a6143972c5766c2d4dbea3d7f9 || echo 0000000000000000000000000000000000000000)" "$4" >"$UD/$1/remotecache.vdf"
}
for n in 14 15 16 17; do
   jeu "$BS" 20$n "Jeu $n" "Jeu$n" 4 5
   mkdir -p "$BU/AppData/LocalLow/Dev$n/Jeu$n"; echo "bouteille $n" >"$BU/AppData/LocalLow/Dev$n/Jeu$n/partie.sav"
done
cache_steam 2015 "Dev15/Jeu15/partie.sav" 4096 -1
cache_steam 2016 "Dev16/Jeu16/partie.sav" 0 1
# 2007 : repris par un Cidre d'avant (le jeu, pas ses sauvegardes) ; 2008 : pas encore de disque C:
jeu "$BS" 2007 "Jeu Sept" "JeuSept" 4 5
S7="$BU/Documents/My Games/Jeu Sept"; mkdir -p "$S7"; echo partie >"$S7/partie.sav"; date_bouteille "$S7/partie.sav"
jeu "$BS" 2008 "Jeu Huit" "JeuHuit" 4 5
S8="$BU/AppData/Roaming/Jeu Huit"; mkdir -p "$S8"; echo huit >"$S8/h.sav"
# 2009 : les sauvegardes sont dans le dossier du jeu
jeu "$BS" 2009 "Jeu Neuf" "JeuNeuf" 4 5
mkdir -p "$BS/common/JeuNeuf/save"; echo neuf >"$BS/common/JeuNeuf/save/slot.sav"
ESSAIS_AVANT=$(cliche "$ES")

echo "  -- absentes cote Cidre (--json)"
sortie=$(sh "$R/cidre" import 2001 --json 2>"$T/err"); verif "jeu Unity : repris" "0" "$?"
valide "--json : JSON valide" "$sortie"
verif "--json : toujours la fiche du jeu, sur une ligne" '{"id":"2001","appid":2001,"nom":"Un Jeu Unity" 1' "$(printf '%s' "$sortie" | cut -d, -f1-3) $(printf '%s\n' "$sortie" | wc -l | tr -d ' ')"
verif "reprise_sauvegardes : etat, fichiers, origine, bouteille, synchro" "copie 3 crossover Jeux copie" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs origine "$sortie") $(cs bouteille "$sortie") $(cs synchro "$sortie")"
verif "reprise_sauvegardes : d'ou" "$S1" "$(cs depuis "$sortie")"
verif "reprise_sauvegardes : vers ou" "$UC/AppData/LocalLow/Petit Studio/Mon Produit" "$(cs vers "$sortie")"
verif "reprise_sauvegardes : le dossier, au nom du produit Unity" "AppData/LocalLow/Petit Studio/Mon Produit" "$(cs dossier "$sortie")"
contient "reprise_sauvegardes : une phrase" '"message":"3 fichier(s) de sauvegarde ramené(s) de la bouteille « Jeux » (CrossOver)"' "$sortie"
verif "les trois fichiers sont la, sous-dossier compris" "deux profil" "$(cat "$UC/AppData/LocalLow/Petit Studio/Mon Produit/slots/2.sav" "$UC/AppData/LocalLow/Petit Studio/Mon Produit/profil.json" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
[ ! -e "$UC/AppData/LocalLow/Petit Studio/Mon Produit/Player.log" ] && ok "le journal du jeu n'est pas repris" || echec "Player.log a ete copie"
[ ! -e "$UC/AppData/LocalLow/Petit Studio/Autre Jeu" ] && ok "le dossier plus recent d'un autre jeu n'est pas pris" || echec "le dossier d'un autre jeu a ete copie"
contient "--json : le compte rendu va a l'erreur" "sauvegardes : 3 fichier(s) ramene(s) de la bouteille" "$(cat "$T/err")"
e=$(sh "$R/cidre" saves 2001 --json)
valide "cidre saves --json : JSON valide" "$e"
contient "cidre saves --json : \"reprise\" dit ce qui a ete ramene" '"reprise":{"appid":2001,"etat":"copie","fichiers":3,"remplaces":0,"gardes":0,"identiques":0,' "$e"
contient "cidre saves --json : d'ou, vers ou" "\"origine\":\"crossover\",\"bouteille\":\"Jeux\",\"depuis\":\"$S1\",\"vers\":\"$UC/AppData/LocalLow/Petit Studio/Mon Produit\"" "$e"
verif "cidre saves --json : le dossier est connu, 3 fichiers sur ce Mac" 'true "fichiers":3' "$(cs configure "$e" | head -1) $(printf '%s' "$e" | sed -n 's/.*"local":{\("fichiers":[0-9]*\).*/\1/p')"

echo "  -- plus anciennes, plus recentes, identiques cote Cidre"
sortie=$(CIDRE_FICHE_SAUVEGARDES='AppData/Roaming/Studio2/Jeu2' sh "$R/cidre" import 2002 2>&1); verif "repris" "0" "$?"
contient "compte rendu : deux fichiers ramenes" "sauvegardes : 2 fichier(s) ramene(s) de la bouteille" "$sortie"
contient "compte rendu : un remplace, l'ancien garde" "1 remplace(s) par une version plus recente de la bouteille ; l'ancienne est gardee : $CIDRE_DIR/saves/2002/.history/avant-reprise-" "$sortie"
contient "compte rendu : un plus recent ici, garde" "1 plus recent(s) cote Cidre : garde(s) tel(s) quel(s)" "$sortie"
verif "fichier absent cote Cidre : copie" "bouteille d" "$(cat "$C2/d.sav" 2>/dev/null)"
verif "fichier plus ancien cote Cidre : remplace" "bouteille a" "$(cat "$C2/a.sav")"
verif "fichier plus recent cote Cidre : jamais ecrase" "cidre recent" "$(cat "$C2/b.sav")"
verif "fichier propre a Cidre : intact" "propre a cidre" "$(cat "$C2/e.sav")"
H2=$(ls -d "$CIDRE_DIR/saves/2002/.history/avant-reprise-"* 2>/dev/null | head -1)
verif "l'ancienne version remplacee est gardee" "cidre ancien" "$(cat "$H2/0/a.sav" 2>/dev/null)"
verif "seul le fichier remplace est dans la copie de precaution" "a.sav" "$(ls "$H2/0" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
verif "son emplacement d'origine est note" "$C2" "$(cat "$H2/0.origine" 2>/dev/null)"
contient "le compte est garde : ecrits, remplaces, gardes, identiques" '"etat":"copie","fichiers":2,"remplaces":1,"gardes":1,"identiques":1,' "$(cat "$CIDRE_DIR/reprises.saves/2002.json" 2>/dev/null)"
verif "le dossier que dit la fiche est note dans saves.conf" "AppData/Roaming/Studio2/Jeu2" "$(awk -F'\t' '$1 == 2002 { print $2 }' "$CIDRE_DIR/saves.conf")"

echo "  -- absentes de la bouteille, introuvables, designees"
printf '2003\tAppData/Roaming/Rien Ici\n' >>"$CIDRE_DIR/saves.conf"
sortie=$(sh "$R/cidre" import 2003 --json 2>"$T/err"); verif "sans sauvegarde dans la bouteille : le jeu est repris" "0" "$?"
verif "etat absentes, rien d'ecrit" "absentes 0" "$(cs etat "$sortie") $(cs fichiers "$sortie")"
contient "on dit ou elles auraient ete" "sauvegardes : aucune dans la bouteille (dossier attendu : AppData/Roaming/Rien Ici)" "$(cat "$T/err")"
sortie=$(sh "$R/cidre" import 2004 2>&1); verif "dossier inconnu : le jeu est repris" "0" "$?"
contient "dossier inconnu : on le dit" "sauvegardes : non trouvees dans la bouteille" "$sortie"
contient "dossier inconnu : et comment le designer" "cidre import 2004 --saves --dossier <dossier sous $BU>" "$sortie"
[ ! -e "$UC/AppData/Roaming/Bizarre Nom" ] && ok "dossier inconnu : rien n'est copie au hasard" || echec "un dossier sans rapport a ete copie"
contient "dossier inconnu : note comme tel" '"etat":"introuvable"' "$(cat "$CIDRE_DIR/reprises.saves/2004.json" 2>/dev/null)"
sortie=$(sh "$R/cidre" import 2004 --saves --dossier "$S4" --json 2>/dev/null); verif "--dossier : ramene" "0" "$?"
verif "--dossier : etat, fichiers, dossier" "copie 1 AppData/Roaming/Bizarre Nom" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs dossier "$sortie")"
verif "--dossier : le fichier est la" "x" "$(cat "$UC/AppData/Roaming/Bizarre Nom/partie.bin" 2>/dev/null)"
verif "--dossier : note dans saves.conf" "AppData/Roaming/Bizarre Nom" "$(awk -F'\t' '$1 == 2004 { print $2 }' "$CIDRE_DIR/saves.conf")"
sortie=$(sh "$R/cidre" import 2004 --saves --dossier "$T/home" 2>&1); verif "--dossier hors de la bouteille : refuse" "1" "$?"
contient "--dossier hors de la bouteille : dit pourquoi" "ce dossier n'est pas sur le disque C: de la bouteille « Jeux » (CrossOver)" "$sortie"
sh "$R/cidre" import 2004 --saves --dossier "$T/nulle-part" >/dev/null 2>&1; verif "--dossier inexistant : refuse" "1" "$?"
sh "$R/cidre" import 2004 --saves --move >/dev/null 2>&1; verif "--saves avec --move : usage" "2" "$?"

echo "  -- Steam Cloud synchronise deja le jeu"
sortie=$(CIDRE_FICHE_STEAM_CLOUD=steam-api sh "$R/cidre" import 2005 --json 2>"$T/err"); verif "API de Steam : le jeu est repris" "0" "$?"
verif "API de Steam : etat steam, rien de copie" "steam steam_api 0" "$(cs etat "$sortie") $(cs synchro "$sortie") $(cs fichiers "$sortie")"
[ ! -e "$UC/AppData/Roaming/Jeu Cinq" ] && ok "API de Steam : rien n'est ecrit sur le disque C: de Cidre" || echec "API de Steam : un dossier a ete copie"
contient "API de Steam : on le dit" "sauvegardes : Steam Cloud synchronise deja ce jeu (il ecrit par l'API de Steam) : rien n'est copie" "$(cat "$T/err")"
contient "API de Steam : ce que la bouteille garde, et ou" "(la bouteille en garde 1 fichier(s), intacts : $REM)" "$(cat "$T/err")"
sortie=$(CIDRE_FICHE_STEAM_CLOUD=steam-api sh "$R/cidre" import 2005 --saves --forcer --json 2>"$T/err")
verif "API de Steam, --forcer : toujours rien (le stockage de Steam n'est pas a Cidre)" "steam 0 1" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(grep -c "forcer n'y change rien" "$T/err")"
[ ! -e "$UC/AppData/Roaming/Jeu Cinq" ] && ok "API de Steam, --forcer : rien d'ecrit" || echec "API de Steam, --forcer : un dossier a ete copie"
printf '2005\tAppData/Roaming/Jeu Cinq\n' >>"$CIDRE_DIR/saves.conf"
sortie=$(CIDRE_FICHE_STEAM_CLOUD=steam-api sh "$R/cidre" import 2005 --saves --json 2>/dev/null)
verif "API de Steam + dossier local de saves.conf : celui-la est ramene" "copie steam_api 1" "$(cs etat "$sortie") $(cs synchro "$sortie") $(cs fichiers "$sortie")"
echo "  -- Steam d'abord : dossier macOS lie"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$LIEN" sh "$R/cidre" import 2006 --json 2>"$T/err"); verif "Steam a deja une sauvegarde : le jeu est repris" "0" "$?"
verif "Steam a deja une sauvegarde : etat, synchro, ecrits, gardes (bouteille), cote Steam" "steam_prioritaire steam_macos 0 2 1 false" \
   "$(cs etat "$sortie") $(cs synchro "$sortie") $(cs fichiers "$sortie") $(cs gardes "$sortie") $(cs steam_fichiers "$sortie") $(cs steam_distants "$sortie")"
verif "Steam a deja une sauvegarde : d'ou, et le dossier que Steam synchronise" "$S6 $MAC" "$(cs depuis "$sortie") $(cs vers "$sortie")"
verif "Steam a deja une sauvegarde : le lien est pose" "$MAC" "$(readlink "$UC/AppData/LocalLow/Dev6/Jeu6")"
verif "le fichier de Steam, meme plus ancien que celui de la bouteille, n'est pas remplace" "mac ancien" "$(cat "$MAC/commun.sav")"
[ ! -e "$MAC/win.sav" ] && ok "rien n'est copie, pas meme le fichier que Steam n'a pas" || echec "un fichier de la bouteille a ete ajoute au dossier de Steam"
contient "on dit que Steam a la priorite" "sauvegardes : Steam Cloud a deja des sauvegardes de ce jeu : elles ont la priorite, rien n'est copie de la bouteille" "$(cat "$T/err")"
contient "on dit ce que Steam a, et ou" "Steam     : 1 fichier(s) dans $MAC" "$(cat "$T/err")"
contient "on dit ce que la bouteille garde, et ou" "bouteille : 2 fichier(s), intacts : $S6" "$(cat "$T/err")"
contient "on dit comment passer outre" "cidre import 2006 --saves --forcer" "$(cat "$T/err")"
contient "cidre saves --json : la reprise dit que Steam a eu la priorite" '"reprise":{"appid":2006,"etat":"steam_prioritaire","fichiers":0,' "$(CIDRE_FICHE_STEAM_CLOUD="$LIEN" sh "$R/cidre" saves 2006 --json)"
sh "$R/cidre" import 2006 --forcer >/dev/null 2>&1; verif "--forcer sans --saves : usage (jamais a la reprise)" "2" "$?"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$(lien 14)" sh "$R/cidre" import 2014 --json 2>"$T/err")
verif "dossier de Steam vide : comble par la bouteille" "copie steam_macos 1 0 bouteille 14" "$(cs etat "$sortie") $(cs synchro "$sortie") $(cs fichiers "$sortie") $(cs steam_fichiers "$sortie") $(cat "$T/maison/Library/Application Support/Dev14.Jeu14/partie.sav" 2>/dev/null)"
verif "jamais synchronise par le client de ce Mac : conflit possible, dit" "true 1" "$(cs conflit_possible "$sortie") $(grep -c 'Steam signalera un conflit' "$T/err")"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$(lien 15)" sh "$R/cidre" import 2015 --json 2>"$T/err")
verif "dossier vide mais fichiers connus dans le nuage : Steam d'abord, rien n'est copie" "steam_prioritaire 0 1 true" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs steam_fichiers "$sortie") $(cs steam_distants "$sortie")"
[ -z "$(ls -A "$T/maison/Library/Application Support/Dev15.Jeu15" 2>/dev/null)" ] && ok "fichiers connus dans le nuage : le dossier de Steam reste vide" || echec "fichiers connus dans le nuage : un fichier a ete copie"
contient "fichiers connus dans le nuage : on le dit" "Steam     : 1 fichier(s) dans le nuage, que le client Steam connait (pas encore sur ce Mac)" "$(cat "$T/err")"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$(lien 16)" sh "$R/cidre" import 2016 --json 2>"$T/err")
verif "le nuage n'a qu'un fichier declare pour Windows : comble, sans conflit possible" "copie 1 false bouteille 16" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs conflit_possible "$sortie") $(cat "$T/maison/Library/Application Support/Dev16.Jeu16/partie.sav" 2>/dev/null)"
# 2017 : dossier lie vide, rien de connu du nuage. Un jeu Auto-Cloud n'a JAMAIS
# de seance Steam (elle pourrait faire retirer du nuage des fichiers que ce Mac
# n'a pas, cf. tests/seance_steam_cloud.sh) : le faux client n'est pas appele,
# le dossier est comble et le conflit possible annonce.
mkdir -p "$HOME/Library/Application Support/Steam/logs" "$HOME/Library/Application Support/Steam/Steam.AppBundle"
printf '[2026-10-14 09:00:00] [Logged On, 0,0,0,0] etat\n' >"$HOME/Library/Application Support/Steam/logs/connection_log.txt"
cat >"$T/outil-seance" <<'FIN'
#!/bin/sh
echo "$*" >>"$HOME/appels-seance"
J="$HOME/Library/Application Support/Steam/logs/cloud_log.txt"; h=$(date '+%Y-%m-%d %H:%M:%S')
printf '[%s] [AppID %s] Starting sync (up,AC Exit,)\n[%s] [AppID %s] Download OK for file Dev17/Jeu17/partie.sav\n' "$h" "$2" "$h" "$2" >>"$J"
mkdir -p "$HOME/Library/Application Support/Steam/userdata/4242/$2"
printf '"%s"\n{\n\t"Dev17/Jeu17/partie.sav"\n\t{\n\t\t"size"\t\t"9"\n\t\t"remotetime"\t\t"1791067661"\n\t\t"platformstosync2"\t\t"-1"\n\t}\n}\n' "$2" >"$HOME/Library/Application Support/Steam/userdata/4242/$2/remotecache.vdf"
printf '[%s] [AppID %s] YldWriteCacheDirectoryToFile - saved\n' "$h" "$2" >>"$J"
printf 'nuage_compte=1\nnuage_jeu=1\netat=ok\n'
FIN
chmod +x "$T/outil-seance"
sortie=$(CIDRE_SEANCE_STEAM=1 CIDRE_OUTIL="$T/outil-seance" CIDRE_STEAM_TOURNE=true CIDRE_FICHE_STEAM_CLOUD="$(lien 17)" sh "$R/cidre" import 2017 --json 2>"$T/err")
verif "dossier lie : aucune seance, meme client ouvert et seance permise" "" "$(cat "$HOME/appels-seance" 2>/dev/null)"
verif "dossier lie sans seance : comble, conflit possible annonce" "copie 1 true" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs conflit_possible "$sortie")"

echo "  -- sauvegardes dans le dossier du jeu"
sortie=$(CIDRE_FICHE_SAUVEGARDES='jeu:save' sh "$R/cidre" import 2009 --json 2>"$T/err")
verif "etat avec_le_jeu" "avec_le_jeu 0" "$(cs etat "$sortie") $(cs fichiers "$sortie")"
verif "elles sont venues avec le clone" "neuf" "$(cat "$G/2009/save/slot.sav" 2>/dev/null)"
contient "on le dit" "ce jeu les range dans son propre dossier (save) : elles sont venues avec lui" "$(cat "$T/err")"
echo "  -- Steam d'abord : forcer, a la demande"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$LIEN" sh "$R/cidre" import 2006 --saves --forcer --json 2>"$T/err"); verif "--saves --forcer : fait" "0" "$?"
verif "--forcer : etat, ecrits, remplaces, force" "copie 2 1 true" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs remplaces "$sortie") $(cs force "$sortie")"
verif "--forcer : les fichiers de la bouteille sont dans le dossier de Steam" "windows recent windows" "$(cat "$MAC/commun.sav") $(cat "$MAC/win.sav" 2>/dev/null)"
verif "--forcer : la version de Steam remplacee est gardee" "mac ancien" "$(cat "$(cs historique "$sortie")/0/commun.sav" 2>/dev/null)"
contient "--forcer : on le dit" "par-dessus le dossier que Steam Cloud synchronise (--forcer)" "$(cat "$T/err")"
sortie=$(CIDRE_FICHE_STEAM_CLOUD="$(lien 15)" sh "$R/cidre" import 2015 --saves --json 2>/dev/null)
verif "rattrapage sans --forcer : Steam garde la priorite" "steam_prioritaire 0" "$(cs etat "$sortie") $(cs fichiers "$sortie")"
verif "aucune bouteille n'a ete modifiee par ces reprises" "$ESSAIS_AVANT" "$(cliche "$ES")"

echo "  -- rattrapage d'une reprise ancienne (cidre import <appid> --saves)"
# ce que faisait `cidre import` avant de savoir les ramener : le jeu et reprises.conf, pas les sauvegardes
sh "$R/tests/reprendre_jeu_bouteille.sh" 2007 >/dev/null 2>&1; verif "reprise a l'ancienne" "0" "$?"
C7="$UC/Documents/My Games/Jeu Sept"
[ -d "$G/2007" ] && [ ! -e "$C7" ] && ok "reprise ancienne : le jeu, sans ses sauvegardes" || echec "reprise ancienne : etat inattendu"
contient "cidre saves --json : aucune reprise de sauvegardes notee" '"reprise":null' "$(sh "$R/cidre" saves 2007 --json)"
sortie=$(sh "$R/cidre" import 2007 --saves 2>&1); verif "rattrapage : fait" "0" "$?"
contient "rattrapage : compte rendu" "sauvegardes : 1 fichier(s) ramene(s) de la bouteille" "$sortie"
verif "rattrapage : la sauvegarde est la (dossier trouve a son nom)" "partie" "$(cat "$C7/partie.sav" 2>/dev/null)"
e=$(sh "$R/cidre" saves 2007 --json)
contient "cidre saves --json : la reprise" "\"reprise\":{\"appid\":2007,\"etat\":\"copie\",\"fichiers\":1," "$e"
contient "cidre saves --json : d'ou, vers ou" "\"depuis\":\"$S7\",\"vers\":\"$C7\"" "$e"
sortie=$(sh "$R/cidre" import 2007 --saves --json 2>/dev/null)
verif "rattrapage rejoue : rien a ramener" "a_jour 0 1" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs identiques "$sortie")"
verif "--saves --json : l'objet seul, valide" "1" "$(printf '%s\n' "$sortie" | grep -c '^{"appid":2007,"etat":"a_jour"')"
valide "--saves --json : JSON valide" "$sortie"
# on a rejoue dans la bouteille depuis : sa sauvegarde est plus recente
echo "partie suivante" >"$S7/partie.sav"; touch -t 202701010000 "$S7/partie.sav"
sortie=$(sh "$R/cidre" import 2007 --saves --json 2>/dev/null)
verif "rejoue dans la bouteille : remplace" "copie 1 1" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs remplaces "$sortie")"
verif "rejoue dans la bouteille : la nouvelle version" "partie suivante" "$(cat "$C7/partie.sav")"
verif "rejoue dans la bouteille : l'ancienne est gardee" "partie" "$(cat "$(cs historique "$sortie")/0/partie.sav" 2>/dev/null)"
# on a joue sous Cidre depuis : la sienne est plus recente
echo "jouee ici" >"$C7/partie.sav"; touch -t 202801010000 "$C7/partie.sav"
sortie=$(sh "$R/cidre" import 2007 --saves --json 2>/dev/null)
verif "joue sous Cidre depuis : rien n'est ecrase" "a_jour 0 1 jouee ici" "$(cs etat "$sortie") $(cs fichiers "$sortie") $(cs gardes "$sortie") $(cat "$C7/partie.sav")"
sortie=$(sh "$R/cidre" import 31337 --saves 2>&1); verif "jeu absent du dossier Cidre : refuse" "1" "$?"
contient "jeu absent : dit quoi faire" "31337 n'est pas dans le dossier Cidre" "$sortie"
sortie=$(sh "$R/cidre" import 444 --saves 2>&1); verif "jeu qui ne vient pas d'une bouteille : refuse" "1" "$?"
contient "jeu qui ne vient pas d'une bouteille : dit quoi faire" "444 n'a pas ete repris d'une bouteille : nommer celle qui a ses sauvegardes" "$sortie"
sortie=$(sh "$R/cidre" import 444 crossover:Jeux --saves --json 2>/dev/null); verif "bouteille nommee : regardee" "0" "$?"
verif "bouteille nommee, jeu sans nom connu : rien n'est pris au hasard" "introuvable Jeux" "$(cs etat "$sortie") $(cs bouteille "$sortie")"
sh "$R/cidre" import 444 "Bouteille Inconnue" --saves >/dev/null 2>&1; verif "bouteille inconnue : refuse" "1" "$?"
mv "$B" "$B.partie"
sortie=$(sh "$R/cidre" import 2007 --saves --json 2>"$T/err"); verif "bouteille disparue : refuse" "1" "$?"
verif "bouteille disparue : --json le dit" "erreur bouteille_absente" "$(cs etat "$sortie") $(cs raison "$sortie")"
contient "bouteille disparue : message" "la bouteille « Jeux » (CrossOver) n'est plus la : $B" "$(cat "$T/err")"
mv "$B.partie" "$B"
sortie=$(WINEPREFIX="$T/nulle-part" sh "$R/cidre" import 2008 --json 2>"$T/err"); verif "disque C: de Cidre absent : le jeu est repris quand meme" "0" "$?"
verif "disque C: absent : --json le dit" "erreur prefixe_absent" "$(cs etat "$sortie") $(cs raison "$sortie")"
valide "disque C: absent : JSON valide" "$sortie"
contient "disque C: absent : dit quoi faire ensuite" "ensuite : cidre import 2008 --saves" "$(cat "$T/err")"
[ -f "$G/2008/Jeu.exe" ] && [ ! -e "$CIDRE_DIR/reprises.saves/2008.json" ] && ok "disque C: absent : jeu la, rien de note" || echec "disque C: absent : etat inattendu"
sh "$R/cidre" import 2008 --saves >/dev/null 2>&1
verif "disque C: cree depuis : le rattrapage ramene" "huit" "$(cat "$UC/AppData/Roaming/Jeu Huit/h.sav" 2>/dev/null)"

echo "== 7. cidre import --move : bouteille en cours d'usage"
OB="$ES/Occupee"; OBS="$OB/$STEAM"; OB2="$ES/Occupee 2"
for a in 2010 2011 2012 2013; do jeu "$OBS" $a "Jeu $a" "Jeu$a" 4 5; done
mkdir -p "$OB/drive_c/users/crossover" "$OB2/drive_c"
CLE=$(stat -f 'server-%Xd-%Xi' "$OB" | tr 'A-F' 'a-f'); CLE2=$(stat -f 'server-%Xd-%Xi' "$OB2" | tr 'A-F' 'a-f')
OCC_AVANT=$(cliche "$OB")
refuse() { # <libelle> <raison attendue> : --move de 2010 doit etre refuse, sans rien bouger
   verif "$1 : refuse" "1" "$rc"
   contient "$1 : dit que la bouteille tourne" "deplacement refuse : la bouteille « Occupee » (CrossOver) est en cours d'usage" "$sortie"
   contient "$1 : dit ce qui tourne" "  - $2" "$sortie"
   contient "$1 : dit quoi fermer" "Ferme le client Steam de cette bouteille et les jeux qui y tournent, puis quitte CrossOver, et relance : cidre import 2010 --move" "$sortie"
   [ ! -e "$G/2010" ] && [ -z "$(ls -A "$G" | grep reprise)" ] && ok "$1 : rien dans le dossier Cidre" || echec "$1 : le dossier Cidre a change"
   verif "$1 : la bouteille n'a pas bouge" "$OCC_AVANT" "$(cliche "$OB")"
}
# ce que rendent lsof et ps, releve sur de vrais processus
printf 'p4242\nfcwd\nn/private/tmp/.wine-501/%s\n' "$CLE" >"$T/lsof-ici"
printf 'p4343\nfcwd\nn/private/tmp/.wine-501/%s\np4344\nfcwd\nn/private/tmp/.wine-501/server-1000011-abc\n' "$CLE2" >"$T/lsof-ailleurs"
printf '  777 C:\\Program Files (x86)\\Steam\\steam.exe -silent WINEPREFIX=%s CX_BOTTLE=Occupee PATH=/usr/bin\n' "$OB" >"$T/ps-steam"
printf '  778 Z:\\jeu\\Jeu.exe LANG=fr_FR.UTF-8 WINEPREFIX=%s\n' "$OB" >"$T/ps-jeu"
printf '  779 C:\\Program Files (x86)\\Steam\\steam.exe WINEPREFIX=%s CX_BOTTLE=Occupee 2\n  780 wineserver WINEPREFIX=%s/sous A=1\n' "$OB2" "$OB" >"$T/ps-ailleurs"
sortie=$(CIDRE_LSOF="cat $T/lsof-ici" CIDRE_PS=true sh "$R/cidre" import 2010 --move 2>&1); rc=$?
refuse "wineserver de la bouteille" "son wineserver tourne (processus 4242)"
sortie=$(CIDRE_LSOF=true CIDRE_PS="cat $T/ps-steam" sh "$R/cidre" import 2010 --move 2>&1); rc=$?
refuse "client Steam de la bouteille" "son client Steam est ouvert (processus 777)"
sortie=$(CIDRE_LSOF=true CIDRE_PS="cat $T/ps-jeu" sh "$R/cidre" import 2010 --move 2>&1); rc=$?
refuse "jeu qui tourne dans la bouteille" "un programme Windows y tourne (processus 778)"
sortie=$(CIDRE_LSOF="cat $T/lsof-ici" CIDRE_PS="cat $T/ps-steam" sh "$R/cidre" import 2010 --move --json 2>&1 >/dev/null); rc=$?
refuse "--json, les deux a la fois" "son client Steam est ouvert (processus 777)"
verif "les deux raisons sont dites" "2" "$(printf '%s\n' "$sortie" | grep -c '^  - ')"
sortie=$(CIDRE_LSOF="cat $T/lsof-ici" CIDRE_PS="cat $T/ps-steam" sh "$R/cidre" import 2013 2>&1); verif "sans --move, une bouteille en usage se clone" "0" "$?"
contient "sans --move : clone" "mode        : clone APFS" "$sortie"
sortie=$(CIDRE_LSOF="cat $T/lsof-ailleurs" CIDRE_PS="cat $T/ps-ailleurs" sh "$R/cidre" import 2011 --move 2>&1); verif "une autre bouteille en usage (meme debut de nom) ne bloque pas" "0" "$?"
[ -f "$G/2011/Jeu.exe" ] && [ ! -e "$OBS/common/Jeu2011" ] && ok "autre bouteille en usage : deplace" || echec "autre bouteille en usage : 2011 pas deplace"
# avec de vrais processus : un faux wineserver dans le dossier de ce prefixe,
# puis un faux client Steam lance avec WINEPREFIX = la bouteille
OCC_AVANT=$(cliche "$OB")
mkdir -p "$T/bin" "$T/tmp-wine/$CLE"
printf '#include <unistd.h>\nint main(void) { sleep(120); return 0; }\n' >"$T/dort.c"
if cc -o "$T/bin/wineserver" "$T/dort.c" 2>/dev/null && cp "$T/bin/wineserver" "$T/bin/steam.exe"; then
   vu() { i=0; while [ $i -lt 20 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }
   (cd "$T/tmp-wine/$CLE" && exec "$T/bin/wineserver") & FAUX=$!
   vu sh -c "lsof -a -c wineserver -d cwd -Fpn | grep -q '$CLE'"
   sortie=$(sh "$R/cidre" import 2010 --move 2>&1); rc=$?
   refuse "vrai processus wineserver" "son wineserver tourne (processus $FAUX)"
   kill $FAUX; wait $FAUX 2>/dev/null; FAUX=
   WINEPREFIX="$OB" "$T/bin/steam.exe" & FAUX=$!
   vu sh -c "ps -axwwE -o pid=,command= | grep -q 'WINEPREFIX=$OB'"
   sortie=$(sh "$R/cidre" import 2010 --move 2>&1); rc=$?
   refuse "vrai processus lance dans la bouteille" "son client Steam est ouvert (processus $FAUX)"
   kill $FAUX; wait $FAUX 2>/dev/null; FAUX=
else
   echo "  (pas de compilateur : cas « vrais processus » non verifies)"
fi
sortie=$(sh "$R/cidre" import 2010 --move 2>&1); verif "bouteille liberee : deplace" "0" "$?"
[ -f "$G/2010/Jeu.exe" ] && [ ! -e "$OBS/common/Jeu2010" ] && [ ! -e "$OBS/appmanifest_2010.acf" ] && ok "bouteille liberee : le jeu l'a quittee" || echec "bouteille liberee : 2010 pas deplace"
contient "--move : les sauvegardes sont cherchees ensuite, dans la bouteille" "sauvegardes : non trouvees dans la bouteille" "$sortie"

echo "== 8. syntaxe"
for f in cidre tests/trouver_jeux_bouteilles.sh tests/reprendre_jeu_bouteille.sh tests/reprendre_saves_bouteille.sh tests/deviner_saves.sh tests/sync_saves_steam.sh tests/tester_bouteilles.sh; do
   sh -n "$R/$f" 2>/dev/null && ok "sh -n $f" || echec "sh -n $f"
done

# (l'aide est un here-document : un accent grave s'y executerait)
verif "cidre help : rien sur la sortie d'erreur" "" "$(sh "$R/cidre" help 2>&1 >/dev/null)"
verif "cidre help : import, import --saves et bottles documentes" "3" "$(sh "$R/cidre" help 2>/dev/null | grep -c -e '^  cidre import <appid>' -e '^  cidre bottles ')"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
