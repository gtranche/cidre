#!/bin/sh
# Teste la base de profils par jeu (profils/README.md) :
#   1. migration : chaque [<appid>] de l'ancien outil-steam/profils.toml
#      (tests/fixtures/profils_ancien.toml) a sa fiche, et `profil_cidre.sh`
#      rend les memes valeurs ; l'index est a jour ;
#   2. priorite : profil utilisateur > fiche de la base > [defaut] utilisateur
#      > [defaut] livre ; cache telecharge > copie livree ;
#   3. reglages du jeu (reglages_jeu.sh) sur un INI CRLF factice : valeurs
#      posees, autres lignes intactes, sauvegarde .avant-cidre, idempotence,
#      cle manquante ajoutee dans sa section, fichier absent = on reessaiera ;
#      puis une sauvegarde Unreal factice (format gvas : entiers remplaces sur
#      place), un chemin a `*` (un dossier par compte), et une ruche de
#      registre factice (formats registre et playerprefs) ;
#   4. le marqueur reglages_jeu_appliques dans le profil utilisateur ;
#   5. `fiche_profil.sh maj` contre une copie locale (file://), et sans reseau ;
#   6. variantes par machine (blocs [[machine]], tests/machine.sh) : conditions,
#      fusion dans [cidre] et [[reglages_jeu]], priorite, application a l'INI,
#      fiche d'Expedition 33 sur un M1 Max et sur un iMac M4 ;
#   6c. compatibilite par famille de Mac ([[compat.machines]]) : faits famille_gpu,
#      generation, gamme, macos ; [compat] remplace par l'entree qui vaut ici et
#      parle de la voie de la fiche ; options par famille ; Expedition 33 ;
#   6b. arguments du jeu (option arguments) : decoupage, doublons, fiche, `cidre set` ;
#   7. sh -n sur les scripts de la chaine.
# Tout se passe dans un dossier temporaire : ni le profil utilisateur, ni le
# prefixe, ni le cache reels ne sont touches.
#   sh tests/tester_profils.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-profils.XXXXXX")
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
# un environnement isole : pas de profil utilisateur, cache vide, sauf dit autrement
export CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/cache" CIDRE_DIR="$T/cidre"
# la machine aussi est imposee (celle de reference, un M1 Max) : les fiches a
# variantes par machine rendent la meme chose partout ou le test tourne
M1MAX="coeurs_gpu=24 memoire_go=32 ecran_largeur=1728 ecran_hauteur=1117 famille_gpu=7 generation=1 gamme=max macos=26"
IMAC_M4="coeurs_gpu=10 memoire_go=24 ecran_largeur=2240 ecran_hauteur=1260 famille_gpu=9 generation=4 gamme=base macos=27"
export CIDRE_MACHINE="$M1MAX"
mkdir -p "$CIDRE_PROFILS_BASE"
resoudre() { sh "$R/tests/profil_cidre.sh" "$@"; }
valeur() { resoudre "$1" | sed -n "s/^$2=//p" | head -1; }

echo "== 1. migration de l'ancien profils.toml vers profils/<appid>.toml"
ANCIEN=$R/tests/fixtures/profils_ancien.toml
for id in $(sed -n 's/^\[\([0-9][0-9]*\)\]$/\1/p' "$ANCIEN"); do
   [ -f "$R/profils/$id.toml" ] && ok "fiche profils/$id.toml presente" || { echec "fiche profils/$id.toml absente"; continue; }
   # chaque cle de l'ancienne section, resolue par la chaine : meme valeur
   awk -v id="$id" '
      /^\[/ { dedans = ($0 == "[" id "]"); next }
      dedans && /^[a-z_]+[ \t]*=/ { print }' "$ANCIEN" |
   while IFS= read -r ligne; do
      cle=${ligne%%=*}; cle=$(printf '%s' "$cle" | tr -d ' \t')
      att=${ligne#*=}; att=$(printf "%s" "$att" | sed "s/^[[:space:]]*//; s/[[:space:]]*$//; s/^\"//; s/\"$//")
      obt=$(valeur "$id" "$cle")
      [ "$att" = "$obt" ] && echo "ok	$id : $cle = $att" || echo "KO	$id : $cle attendu $att, obtenu $obt"
   done >"$T/res"
   # (les compteurs sont dans ce shell : on relit le resultat hors du tube)
   while IFS="	" read -r etat msg; do [ "$etat" = ok ] && ok "$msg" || echec "$msg"; done <"$T/res"
done
# [defaut] est reste dans outil-steam/profils.toml, sans section par jeu
verif "profils.toml : plus de section [<appid>]" "" "$(grep -c '^\[[0-9]' "$R/outil-steam/profils.toml" | grep -vx 0)"
verif "profils.toml : [defaut] toujours la" "[defaut]" "$(grep -x '\[defaut\]' "$R/outil-steam/profils.toml")"
# l'index correspond aux fiches
if sh "$R/tests/fiche_profil.sh" generer-index | cmp -s - "$R/profils/index.toml"; then ok "profils/index.toml a jour"
else echec "profils/index.toml n'est pas a jour (sh tests/fiche_profil.sh generer-index > profils/index.toml)"; fi
# la fiche d'Expedition 33 : la resolution dans l'INI (partie commune), la qualite
# dans la sauvegarde de reglages du jeu (bloc [[machine]] vrai partout), le temoin
E33() { sh "$R/tests/fiche_profil.sh" reglages 1903340; }
verif "1903340 : entree 1 = CurrentSelectedUpscalerQualityMode dans sa section INI" "/Script/SandFall.ConfigurableGameUserSettings 0" "$(E33 | awk -F"\t" '$1==1 && $2=="section"{print $3}') $(E33 | awk -F"\t" '$1==1 && $3=="CurrentSelectedUpscalerQualityMode"{print $4}')"
verif "1903340 : aucun sg.* vise dans l INI (le jeu les recopie de sa sauvegarde)" "" "$(E33 | grep 'sg\.')"
verif "1903340 : entree 2 = la sauvegarde de reglages, format gvas, chemin a *" "gvas AppData/Local/Sandfall/Saved/SaveGames/*/SharedGameUserSettings.sav" "$(E33 | awk -F"\t" '$1==2 && $2=="format"{print $3}') $(E33 | awk -F"\t" '$1==2 && $2=="fichier"{print $3}')"
verif "1903340 : qualite Moyen (ShadowQuality, OverallScalabilityLevel)" "1 1" "$(E33 | awk -F"\t" '$1==2 && $3=="ShadowQuality"{print $4}') $(E33 | awk -F"\t" '$1==2 && $3=="OverallScalabilityLevel"{print $4}')"
verif "1903340 : 12 valeurs de reglages (le mode d upscaler + 11 de qualite)" "12" "$(E33 | grep -c "	valeur	")"
verif "1903340 : memes reglages sur l iMac M4 (mesure du 2026-10-12 : Moyen 50 % y est aussi le meilleur)" "$(E33)" "$(CIDRE_MACHINE="$IMAC_M4" sh "$R/tests/fiche_profil.sh" reglages 1903340)"
verif "1903340 : pas de MetalFX sur l iMac M4 (7 ms de plus)" "false" "$(CIDRE_MACHINE="$IMAC_M4" sh "$R/tests/profil_cidre.sh" 1903340 | sed -n 's/^metalfx=//p')"
verif "1903340 : un runtime d avant les blocs [[machine]] ne voit que l entree INI" "reglages_jeu.1" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/1903340.toml" | cut -f1 | grep '^reglages_jeu' | grep -v temoin | sed 's/\.valeurs$//' | sort -u | tr '\n' ' ' | sed 's/ $//')"
verif "1903340 : temoin = UserConfigHardwareProfile" "UserConfigHardwareProfile" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/1903340.toml" | awk -F'\t' '$1=="reglages_jeu_temoin" && $2=="cle"{print $4}')"
verif "1903340 : rapport de l iMac M4" "35" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/1903340.toml" | awk -F'\t' '$1=="rapports.1" && $2=="fps_jeu"{print $4}')"
verif "1903340 : compat fps_menu" "130" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/1903340.toml" | awk -F'\t' '$1=="compat"&&$2=="fps_menu"{print $4}')"
verif "1903340 : json rapports = 1" "1" "$(sh "$R/tests/fiche_profil.sh" json 1903340 | sed -n 's/.*"rapports":\([0-9]*\)}$/\1/p')"

echo "== 2. priorite des couches"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[jeu]
appid = 999
nom = "Jeu de test"
[cidre]
tso = false
hud = true
fils_compilation = 3
[compat]
etat = "bronze"
source = "cidre-test"
[[rapports]]
date = "2026-10-01"
etat = "bronze"
[[rapports]]
date = "2026-10-02"
etat = "argent"
notes = "guillemets \" et antislash \\ dans une note"
FICHE
cat >"$CIDRE_PROFILS" <<'PERSO'
[defaut]
vsync = false

[999]
hud = false
PERSO
verif "fiche > [defaut] livre (tso)" "false" "$(valeur 999 tso)"
verif "utilisateur > fiche (hud)" "false" "$(valeur 999 hud)"
verif "[defaut] utilisateur > [defaut] livre (vsync)" "false" "$(valeur 999 vsync)"
verif "[defaut] livre quand rien d'autre (async)" "false" "$(valeur 999 async)"
verif "fiche : entier (fils_compilation)" "3" "$(valeur 999 fils_compilation)"
verif "fiche : etat/source rendus a plat" "bronze cidre-test" "$(valeur 999 etat) $(valeur 999 source)"
verif "perso : seules les cles utilisateur du jeu" '{"hud":false}' "$(resoudre 999 perso)"
verif "json : rapports comptes" "2" "$(sh "$R/tests/fiche_profil.sh" json 999 | sed -n 's/.*"rapports":\([0-9]*\)}$/\1/p')"
verif "json : jeu.nom" '"nom":"Jeu de test"' "$(sh "$R/tests/fiche_profil.sh" json 999 | grep -o '"nom":"Jeu de test"')"
verif "jeu sans fiche : [defaut] seul" "true" "$(valeur 998 tso)"
verif "jeu sans fiche : json null" "null" "$(sh "$R/tests/fiche_profil.sh" json 998)"
# cache vide : la copie livree sert
verif "copie livree en repli (1903340 garde_index)" "false" "$(valeur 1903340 garde_index)"
# cache present : il prime
printf '[cidre]\ngarde_index = true\n' >"$CIDRE_PROFILS_BASE/1903340.toml"
verif "cache > copie livree (1903340 garde_index)" "true" "$(valeur 1903340 garde_index)"
rm -f "$CIDRE_PROFILS_BASE/1903340.toml"
# table en ligne, chaine avec guillemets echappes
printf '[reglages_jeu]\nfichier = "x.ini"\nvaleurs = { "a.b" = "1", c = 2, "d" = "deux \\"mots\\"" }\n' >"$CIDRE_PROFILS_BASE/997.toml"
verif "table en ligne : 3 valeurs" "3" "$(sh "$R/tests/fiche_profil.sh" reglages 997 | grep -c "	valeur	")"
verif "table en ligne : cle nue" "2" "$(sh "$R/tests/fiche_profil.sh" reglages 997 | awk -F"\t" "\$3==\"c\"{print \$4}")"
verif "table en ligne : guillemets echappes" 'deux "mots"' "$(sh "$R/tests/fiche_profil.sh" reglages 997 | awk -F"\t" "\$3==\"d\"{print \$4}")"
verif "id de jeu douteux refuse" "" "$(sh "$R/tests/fiche_profil.sh" chemin '../profils/1903340')"

echo "== 3. reglages du jeu sur un INI CRLF factice"
export WINEPREFIX="$T/pfx"
U="$WINEPREFIX/drive_c/users/testeur"; mkdir -p "$U/AppData/Local/Jeu/Config"
INI="$U/AppData/Local/Jeu/Config/GameUserSettings.ini"
printf '[ScalabilityGroups]\r\nsg.ResolutionQuality=100\r\nsg.ShadowQuality=3\r\nsg.TextureQuality=3\r\n\r\n[/Script/Engine.GameUserSettings]\r\nbUseVSync=False\r\nsg.ShadowQuality=9\r\nFullscreenMode = 1\r\nTitre="Un titre"\r\n' >"$INI"
cp "$INI" "$T/ini-origine"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
format = "ini"
section = "ScalabilityGroups"
[reglages_jeu.valeurs]
"sg.ResolutionQuality" = "66"
"sg.ShadowQuality" = "1"
"sg.FoliageQuality" = "1"
FICHE
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "application : code 0" "0" "$rc"
verif "application : journal" "poses" "$(printf '%s' "$sortie" | grep -o poses)"
verif "sauvegarde .avant-cidre = origine" "" "$(cmp "$INI.avant-cidre" "$T/ini-origine" 2>&1)"
verif "valeur changee (ResolutionQuality)" "sg.ResolutionQuality=66" "$(tr -d '\r' <"$INI" | grep '^sg.ResolutionQuality=')"
verif "valeur changee (ShadowQuality, section visee seulement)" "sg.ShadowQuality=1 sg.ShadowQuality=9" "$(tr -d '\r' <"$INI" | grep '^sg.ShadowQuality=' | tr '\n' ' ' | sed 's/ $//')"
verif "cle manquante ajoutee dans sa section, avant la ligne vide" "sg.TextureQuality=3 sg.FoliageQuality=1  [/Script/Engine.GameUserSettings]" "$(tr -d '\r' <"$INI" | sed -n '4,7p' | tr '\n' ' ' | sed 's/ $//')"
verif "toutes les lignes en CRLF" "$(wc -l <"$INI" | tr -d ' ')" "$(grep -c "$(printf '\r')\$" "$INI")"
tr -d "\r" <"$INI" | grep -v "^sg\." >"$T/a"; tr -d "\r" <"$T/ini-origine" | grep -v "^sg\." >"$T/b"
verif "autres lignes intactes" "" "$(diff "$T/a" "$T/b" 2>&1)"
verif "taille : 10 lignes + 1 ajoutee" "11" "$(wc -l <"$INI" | tr -d ' ')"
cp "$INI" "$T/ini-apres"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "idempotence : code 0" "0" "$rc"
verif "idempotence : « deja en place »" "deja en place" "$(printf '%s' "$sortie" | grep -o 'deja en place')"
verif "idempotence : fichier inchange" "" "$(cmp "$INI" "$T/ini-apres" 2>&1)"
verif "idempotence : sauvegarde inchangee" "" "$(cmp "$INI.avant-cidre" "$T/ini-origine" 2>&1)"
# l'utilisateur rechange une valeur : la relance la repose (c'est le marqueur du lanceur qui l'en empeche)
# sans section : la cle est cherchee partout, une cle absente n'est pas ajoutee ; l'espacement et les guillemets sont gardes
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
valeurs = { "FullscreenMode" = "2", "Titre" = "Autre", "Absente" = "x" }
FICHE
sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; rc=$?
verif "sans section : code 0" "0" "$rc"
verif "sans section : espacement garde" "FullscreenMode = 2" "$(tr -d '\r' <"$INI" | grep '^FullscreenMode')"
verif "sans section : guillemets gardes" 'Titre="Autre"' "$(tr -d '\r' <"$INI" | grep '^Titre')"
verif "sans section : cle absente non ajoutee" "" "$(grep -c Absente "$INI" | grep -vx 0)"
verif "sauvegarde toujours l'origine" "" "$(cmp "$INI.avant-cidre" "$T/ini-origine" 2>&1)"
# section absente du fichier : creee a la fin
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"\nsection = "Nouvelle"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
sh "$R/tests/reglages_jeu.sh" 999 >/dev/null
verif "section absente creee a la fin" "[Nouvelle] k=v" "$(tr -d '\r' <"$INI" | tail -2 | tr '\n' ' ' | sed 's/ $//')"
verif "section creee : CRLF partout" "$(wc -l <"$INI" | tr -d ' ')" "$(grep -c "$(printf '\r')\$" "$INI")"
# fichier du jeu absent : code 3, pas de sauvegarde
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/Absent.ini"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "fichier absent : code 3" "3" "$rc"
verif "fichier absent : rien cree" "" "$(ls "$U/AppData/Local/Jeu/Config/" | grep Absent)"
verif "jeu sans reglages : code 3" "3" "$(sh "$R/tests/reglages_jeu.sh" 998 >/dev/null; echo $?)"
verif "chemin hors du dossier utilisateur refuse" "1" "$(printf '[reglages_jeu]\nfichier = "../../windows/x.ini"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"; sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?)"

# plusieurs sections visees ([[reglages_jeu]]) : chaque entree a son tour, une seule sauvegarde
cp "$T/ini-origine" "$INI"; rm -f "$INI.avant-cidre"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[[reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
section = "ScalabilityGroups"
[reglages_jeu.valeurs]
"sg.ShadowQuality" = "1"
[[reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
section = "/Script/Engine.GameUserSettings"
valeurs = { "CurrentSelectedUpscalerQualityMode" = "0", "sg.ShadowQuality" = "2" }
[[reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/Absent.ini"
valeurs = { "k" = "v" }
FICHE
verif "multi : json = 3 entrees" "3" "$(sh "$R/tests/fiche_profil.sh" json 999 | grep -o '"section":' | wc -l | tr -d ' ')"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "multi : un fichier absent -> code 3 (on reessaiera), les autres posees" "3" "$rc"
verif "multi : deux lignes « poses »" "2" "$(printf '%s\n' "$sortie" | grep -c poses)"
verif "multi : section 1 posee" "sg.ShadowQuality=1 sg.ShadowQuality=2" "$(tr -d '\r' <"$INI" | grep '^sg.ShadowQuality=' | tr '\n' ' ' | sed 's/ $//')"
verif "multi : cle ajoutee dans la 2e section" "CurrentSelectedUpscalerQualityMode=0" "$(tr -d '\r' <"$INI" | grep '^CurrentSelected')"
verif "multi : une seule sauvegarde = origine" "" "$(cmp "$INI.avant-cidre" "$T/ini-origine" 2>&1)"
verif "multi : CRLF partout" "$(wc -l <"$INI" | tr -d ' ')" "$(grep -c "$(printf '\r')\$" "$INI")"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999)
verif "multi : relance = deja en place x2" "2" "$(printf '%s\n' "$sortie" | grep -c 'deja en place')"

# format gvas : une sauvegarde Unreal factice, deux comptes (chemin a `*`)
gvas_prop() { # <nom> <entier 0-255> : une IntProperty comme Unreal 5 l ecrit
   printf "\\$(printf '%03o' $((${#1} + 1)))\\0\\0\\0%s\\0\\014\\0\\0\\0IntProperty\\0\\0\\0\\0\\0\\004\\0\\0\\0\\0\\$(printf '%03o' "$2")\\0\\0\\0" "$1"
}
gvas_lire() { # <fichier> <nom> : les valeurs (octet de poids faible) de la propriete, dans l ordre
   od -An -v -tx1 "$1" | tr -d ' \n' | awk -v m="$(printf '%s' "$2" | od -An -v -tx1 | tr -d ' \n')000c000000496e7450726f706572747900000000000400000000" '
      { d = 1; while ((i = index(substr($0, d), m)) > 0) { p = d + i - 1; printf "%d ", ("0x" substr($0, p + length(m), 2)) + 0; d = p + 1 } }' | sed 's/ $//'
}
SG="$U/AppData/Local/Jeu/Saved/SaveGames"; mkdir -p "$SG/111" "$SG/222"
{ printf 'GVAS\002\0\0\0entete'; gvas_prop OverallScalabilityLevel 1; gvas_prop ShadowQuality 1; printf 'entre deux'; gvas_prop TextureQuality 3; gvas_prop Double 5; gvas_prop Double 6; printf 'fin'; } >"$SG/111/Reglages.sav"
cp "$SG/111/Reglages.sav" "$SG/222/Reglages.sav"; cp "$SG/111/Reglages.sav" "$T/sav-origine"
verif "gvas : la sauvegarde factice se relit" "1 3 5 6" "$(gvas_lire "$SG/111/Reglages.sav" ShadowQuality) $(gvas_lire "$SG/111/Reglages.sav" TextureQuality) $(gvas_lire "$SG/111/Reglages.sav" Double)"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu/Saved/SaveGames/*/Reglages.sav"
format = "gvas"
[reglages_jeu.valeurs]
"ShadowQuality" = "0"
"TextureQuality" = "2"
"OverallScalabilityLevel" = "1"
"Absente" = "1"
"Double" = "9"
"Quality" = "7"
"Texte" = "bas"
FICHE
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "gvas : code 0, un « poses » par compte" "0 2" "$rc $(printf '%s\n' "$sortie" | grep -c poses)"
verif "gvas : entiers remplaces (compte 1)" "0 2 1" "$(gvas_lire "$SG/111/Reglages.sav" ShadowQuality) $(gvas_lire "$SG/111/Reglages.sav" TextureQuality) $(gvas_lire "$SG/111/Reglages.sav" OverallScalabilityLevel)"
verif "gvas : entiers remplaces (compte 2)" "0 2" "$(gvas_lire "$SG/222/Reglages.sav" ShadowQuality) $(gvas_lire "$SG/222/Reglages.sav" TextureQuality)"
verif "gvas : taille inchangee" "$(wc -c <"$T/sav-origine" | tr -d ' ')" "$(wc -c <"$SG/111/Reglages.sav" | tr -d ' ')"
verif "gvas : 2 octets changes, pas un de plus" "2" "$(cmp -l "$SG/111/Reglages.sav" "$T/sav-origine" | wc -l | tr -d ' ')"
verif "gvas : sauvegarde .avant-cidre = origine" "" "$(cmp "$SG/111/Reglages.sav.avant-cidre" "$T/sav-origine" 2>&1)"
verif "gvas : propriete absente laissee, dite" "2" "$(printf '%s\n' "$sortie" | grep -c 'Absente trouvee 0 fois')"
verif "gvas : propriete en double laissee" "5 6" "$(gvas_lire "$SG/111/Reglages.sav" Double)"
verif "gvas : un nom partiel ne touche rien (Quality)" "2" "$(printf '%s\n' "$sortie" | grep -c 'Quality trouvee 0 fois')"
verif "gvas : valeur non entiere laissee, dite" "2" "$(printf '%s\n' "$sortie" | grep -c "Texte = « bas » n'est pas un entier")"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "gvas : relance = code 0, deja en place x2, fichier inchange" "0 2 0" "$rc $(printf '%s\n' "$sortie" | grep -c 'deja en place') $(printf '%s\n' "$sortie" | grep -c poses)"
printf 'pas une sauvegarde' >"$SG/222/Reglages.sav"
verif "gvas : un fichier qui n est pas GVAS -> code 1, pas touche" "1 pas une sauvegarde" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?) $(cat "$SG/222/Reglages.sav")"
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Saved/SaveGames/*/Absent.sav"\nformat = "gvas"\nvaleurs = { "k" = "1" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "chemin a * sans aucun fichier : code 3" "3" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?)"
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/*.ini"\nsection = "ScalabilityGroups"\nvaleurs = { "sg.ShadowQuality" = "2" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "chemin a * au format ini : pose dans le fichier trouve" "0 sg.ShadowQuality=2" "$rc $(tr -d '\r' <"$INI" | grep -m1 '^sg.ShadowQuality=')"
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"\nformat = "yaml"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "format inconnu : code 3" "3" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?)"

# formats registre et playerprefs : le registre du prefixe (user.reg), ici une
# ruche factice au format de Wine, avec une valeur binaire sur deux lignes
REG="$WINEPREFIX/user.reg"
export CIDRE_SERVEUR_WINE=non
cat >"$REG" <<'FIN'
WINE REGISTRY Version 2
;; All keys relative to REGISTRY\\User\\S-1-5-21-0-0-0-1000

#arch=win64

[Software\\Editeur\\Jeu] 1791905543
#time=1dd5b280b278856
"FovSetting_h2102208684"=hex(4):00,00,00,20,48,a2,51,40
"PUNCloudBestRegion_h3469667079"=hex:65,75,3b,32,30,3b,61,73,69,61,2c,61,75,2c,\
  65,75,2c,68,6b,2c,6a,70,2c,73,61,2c,75,73,2c,75,73,73,63,2c,75,73,77,00
"Screenmanager Resolution Width_h182942802"=dword:000006c0
"UnitySelectMonitor_h17969598"=dword:00000000

[Software\\Editeur\\Jeu\\Sous-cle] 1791905543
"LodQuality_h4281427567"=hex:48,69,67,68,00

[Software\\Wine] 1790333337
"Version"="win10"
FIN
cp "$REG" "$T/reg-origine"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FIN'
[reglages_jeu]
fichier = "user.reg"
format = "playerprefs"
section = "Software\\Editeur\\Jeu"
valeurs = { "LodQuality" = "Low", "PUNCloudBestRegion" = "eu", "Screenmanager Resolution Width" = 1280, "Decalage" = -1, "Echelle" = 0.5, "Accentué" = "x" }
FIN
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
reg_cle() { CLE="[$1] " awk 'index($0, ENVIRON["CLE"]) == 1 { d = 1; next } d && /^\[/ { exit } d' "$REG"; }
verif "playerprefs : code 0, pose" "0 1" "$rc $(printf '%s\n' "$sortie" | grep -c 'poses dans user.reg \[Software.Editeur.Jeu\]')"
verif "playerprefs : chaine ajoutee, nom suffixe du hachage d Unity, binaire a zero final" '"LodQuality_h4281427567"=hex:4c,6f,77,00' "$(reg_cle 'Software\\Editeur\\Jeu' | grep '^"LodQuality')"
verif "playerprefs : chaine sur deux lignes remplacee en entier" '"PUNCloudBestRegion_h3469667079"=hex:65,75,00|0' "$(reg_cle 'Software\\Editeur\\Jeu' | grep '^"PUNCloud')|$(grep -c '^  65,75' "$REG")"
verif "playerprefs : entier en dword, negatif en complement a deux" '"Screenmanager Resolution Width_h182942802"=dword:00000500 "Decalage_h3221923689"=dword:ffffffff' "$(reg_cle 'Software\\Editeur\\Jeu' | grep '^"Screenmanager Resolution Width') $(reg_cle 'Software\\Editeur\\Jeu' | grep '^"Decalage')"
verif "playerprefs : nombre decimal et caracteres non ASCII laisses, dits" "1 1 0" "$(printf '%s\n' "$sortie" | grep -c 'Echelle = 0.5 : les nombres decimaux') $(printf '%s\n' "$sortie" | grep -c 'ASCII imprimables') $(grep -c 'Echelle\|Accentu' "$REG")"
verif "playerprefs : les autres valeurs de la cle et les autres cles intactes" "$(grep -v 'PUNCloud\|^  65,75\|Resolution Width' "$T/reg-origine")" "$(grep -v 'PUNCloud\|Resolution Width\|^"LodQuality_h4281427567"=hex:4c\|Decalage' "$REG")"
verif "playerprefs : la sous-cle garde sa valeur de meme nom" '"LodQuality_h4281427567"=hex:48,69,67,68,00' "$(reg_cle 'Software\\Editeur\\Jeu\\Sous-cle')"
verif "playerprefs : copie d origine de la ruche" "" "$(cmp "$REG.avant-cidre" "$T/reg-origine" 2>&1)"
cp "$REG" "$T/reg-pose"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "playerprefs : relance = deja en place, ruche inchangee" "0 1 " "$rc $(printf '%s\n' "$sortie" | grep -c 'deja en place') $(cmp "$REG" "$T/reg-pose" 2>&1)"
cp "$T/reg-origine" "$REG"
verif "registre : prefixe tenu par un wineserver -> code 3, ruche pas touchee" "3 " "$(CIDRE_SERVEUR_WINE=oui sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?) $(cmp "$REG" "$T/reg-origine" 2>&1)"
# cle absente (le jeu n a jamais tourne) : creee a la fin ; format registre = noms tels quels, chaines REG_SZ
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FIN'
[[reglages_jeu]]
fichier = "user.reg"
format = "registre"
section = "Software\\Editeur\\Neuf"
valeurs = { "Dossier" = "C:\\jeu \"x\"", "Niveau" = 3 }
[[reglages_jeu]]
fichier = "user.reg"
format = "registre"
section = "software\\wine"
valeurs = { "version" = "win11" }
FIN
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "registre : cle absente creee, chaine echappee et dword" '0 "Dossier"="C:\\jeu \"x\"" "Niveau"=dword:00000003' "$rc $(reg_cle 'Software\\Editeur\\Neuf' | tr '\n' ' ' | sed 's/ *$//')"
verif "registre : cle et nom retrouves sans egard a la casse, valeur remplacee" '"version"="win11"' "$(reg_cle 'Software\\Wine')"
verif "registre : une seule cle creee" "4" "$(grep -c '^\[' "$REG")"
printf '[reglages_jeu]\nfichier = "system.reg"\nformat = "registre"\nsection = "Software\\\\X"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "registre : une autre ruche que user.reg refusee" "1" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?)"
printf '[reglages_jeu]\nfichier = "user.reg"\nformat = "registre"\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "registre : sans cle (section) -> code 1" "1" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?)"
unset CIDRE_SERVEUR_WINE

echo "== 4. marqueur reglages_jeu_appliques"
verif "avant : pas de marqueur" "" "$(valeur 999 reglages_jeu_appliques)"
sh "$R/tests/profil_cidre.sh" 999 set reglages_jeu_appliques true
verif "apres : marqueur a true" "true" "$(valeur 999 reglages_jeu_appliques)"
verif "marqueur : les autres reglages du jeu restent" "false" "$(valeur 999 hud)"
sh "$R/tests/profil_cidre.sh" 999 unset reglages_jeu_appliques
verif "unset : marqueur retire" "" "$(valeur 999 reglages_jeu_appliques)"
# le temoin : le jeu a refait sa detection du materiel pendant la partie -> marqueur retire
printf '[ScalabilityGroups]\r\nsg.ShadowQuality=1\r\n\r\n[/Script/Jeu.Reglages]\r\nProfilMateriel=CarteA\r\nAutre=1\r\n' >"$INI"
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
valeurs = { "sg.ShadowQuality" = "1" }
[reglages_jeu_temoin]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
cle = "ProfilMateriel"
FICHE
verif "temoin : valeur lue" "CarteA" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin)"
verif "temoin : la table n est pas prise pour des reglages" "1" "$(sh "$R/tests/fiche_profil.sh" reglages 999 | cut -f1 | sort -u | wc -l | tr -d ' ')"
verif "temoin : fiche sans temoin -> vide" "" "$(sh "$R/tests/reglages_jeu.sh" 996 temoin)"
verif "temoin : jeu sans fiche -> vide" "" "$(sh "$R/tests/reglages_jeu.sh" 998 temoin)"
sh "$R/tests/profil_cidre.sh" 999 set reglages_jeu_appliques true
verif "temoin inchange : rien dit, marqueur garde" " true" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-change CarteA) $(valeur 999 reglages_jeu_appliques)"
verif "temoin inconnu avant (premier lancement) : marqueur garde" " true" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-change '') $(valeur 999 reglages_jeu_appliques)"
printf '[ScalabilityGroups]\r\nsg.ShadowQuality=0\r\n\r\n[/Script/Jeu.Reglages]\r\nProfilMateriel=CarteB\r\nAutre=1\r\n' >"$INI"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999 temoin-change CarteA)
verif "temoin change : dit au journal" "CarteA -> CarteB" "$(printf '%s' "$sortie" | grep -o 'CarteA -> CarteB')"
verif "temoin change : marqueur retire" "" "$(valeur 999 reglages_jeu_appliques)"
verif "temoin change : les autres reglages utilisateur du jeu restent" "false" "$(valeur 999 hud)"
verif "temoin change sans marqueur : rien a retirer, rien dit" "" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-change CarteA)"
verif "lancement suivant : reglages reposes (code 0)" "0 sg.ShadowQuality=1" "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?) $(tr -d '\r' <"$INI" | grep '^sg.ShadowQuality=')"
rm -f "$INI"
verif "temoin : fichier absent -> vide, pas d erreur" " 0" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin) $?"

echo "== 5. mise a jour du cache (file://) et hors reseau"
rm -rf "$CIDRE_PROFILS_BASE"; mkdir -p "$CIDRE_PROFILS_BASE"
printf '[cidre]\ntso = false\n' >"$CIDRE_PROFILS_BASE/424242.toml"   # une fiche qui n'est plus dans l'index
sortie=$(CIDRE_PROFILS_URL="file://$R/profils/" sh "$R/tests/fiche_profil.sh" maj json); rc=$?
verif "maj : code 0" "0" "$rc"
n=$(ls "$R"/profils/[0-9]*.toml | wc -l | tr -d ' ')
verif "maj : $n fiches recues" "\"fiches\":$n" "$(printf '%s' "$sortie" | grep -o '"fiches":[0-9]*')"
verif "maj : index en cache" "" "$(cmp "$CIDRE_PROFILS_BASE/index.toml" "$R/profils/index.toml" 2>&1)"
verif "maj : fiche en cache identique" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"
verif "maj : horodatage pose" "20" "$(cut -c1-2 "$CIDRE_PROFILS_BASE/horodatage")"
verif "maj : fiche sortie de l'index retiree" "" "$(ls "$CIDRE_PROFILS_BASE" | grep 424242)"
verif "index : origine cache" "cache" "$(sh "$R/tests/fiche_profil.sh" index | awk -F'\t' '$1==1903340{print $5}')"
# seconde mise a jour : tout est deja en cache avec la bonne empreinte, rien n'est retelecharge
sortie=$(CIDRE_PROFILS_URL="file://$R/profils/" sh "$R/tests/fiche_profil.sh" maj json)
verif "maj incrementale : 0 fiche retelechargee" "\"fiches\":0" "$(printf '%s' "$sortie" | grep -o '"fiches":[0-9]*')"
verif "maj incrementale : $n fiches gardees" "\"gardees\":$n" "$(printf '%s' "$sortie" | grep -o '"gardees":[0-9]*')"
# une fiche modifiee localement (empreinte differente) est reprise
printf '[cidre]\ntso = false\n' >"$CIDRE_PROFILS_BASE/1903340.toml"
sortie=$(CIDRE_PROFILS_URL="file://$R/profils/" sh "$R/tests/fiche_profil.sh" maj json)
verif "maj incrementale : 1 fiche changee retelechargee" "\"fiches\":1" "$(printf '%s' "$sortie" | grep -o '"fiches":[0-9]*')"
verif "maj incrementale : fiche reprise identique" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"
sortie=$(CIDRE_PROFILS_URL="file://$T/nulle-part/" sh "$R/tests/fiche_profil.sh" maj json 2>/dev/null); rc=$?
verif "hors reseau : code 1" "1" "$rc"
verif "hors reseau : json ok=false" '{"ok":false' "$(printf '%s' "$sortie" | cut -c1-11)"
verif "hors reseau : cache intact" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"

echo "== 6. variantes par machine"
M="$R/tests/machine.sh"; FP="$R/tests/fiche_profil.sh"
si() { sh "$M" si "$1" >/dev/null 2>&1; echo $?; }
# les faits : imposes par CIDRE_MACHINE, sinon lus sur la machine
verif "machine : fait impose" "coeurs_gpu=24" "$(sh "$M" coeurs_gpu)"
verif "machine : plusieurs faits, dans l ordre demande" "ecran_largeur=1728 memoire_go=32" "$(sh "$M" ecran_largeur memoire_go | tr '\n' ' ' | sed 's/ $//')"
verif "machine : json" '"coeurs_gpu":24,"memoire_go":32,"ecran_largeur":1728,"ecran_hauteur":1117}' "$(sh "$M" json | sed 's/^{"puce":"[^"]*","generation":1,"gamme":"max","famille_gpu":7,//; s/,"macos":26,"macos_version":"[^"]*"}$/}/')"
verif "machine : json des seuls faits demandes" '{"famille_gpu":7,"gamme":"max"}' "$(sh "$M" json famille_gpu gamme)"
reel=$(CIDRE_MACHINE= sh "$M" coeurs_gpu memoire_go | tr '\n' ' ')
case $reel in "coeurs_gpu="[1-9]*" memoire_go="[1-9]*) ok "machine : faits reels lus ($reel)" ;; *) echec "machine : faits reels illisibles ($reel)" ;; esac
verif "machine : puce reelle lue" "Apple" "$(CIDRE_MACHINE= sh "$M" puce | sed -n 's/^puce=\(Apple\).*/\1/p')"
# la famille Metal, la generation et la gamme de la puce, macOS : lus pour de vrai
reel=$(CIDRE_MACHINE= sh "$M" famille_gpu generation gamme macos | tr '\n' ' ')
case $reel in "famille_gpu="[7-9]" generation="[1-9]*" gamme="[a-z]*" macos="[2-9][0-9]" "|"famille_gpu="[1-9][0-9]" generation="[1-9]*" gamme="[a-z]*" macos="[2-9][0-9]" ") ok "machine : famille, generation, gamme, macOS reels lus ($reel)" ;; *) echec "machine : famille, generation, gamme ou macOS illisible ($reel)" ;; esac
# la famille par Metal et par la generation de l AGX (repli) disent la meme chose
mkdir -p "$T/sans-osascript"; printf '#!/bin/sh\nexit 1\n' >"$T/sans-osascript/osascript"; chmod +x "$T/sans-osascript/osascript"
verif "machine : famille_gpu, repli ioreg = Metal" "$(CIDRE_MACHINE= sh "$M" famille_gpu)" "$(CIDRE_MACHINE= PATH="$T/sans-osascript:$PATH" sh "$M" famille_gpu)"
# generation et gamme d apres le nom de la puce (un sysctl factice)
mkdir -p "$T/autre-puce"; printf '#!/bin/sh\necho "$P"\n' >"$T/autre-puce/sysctl"; chmod +x "$T/autre-puce/sysctl"
for p in "Apple M3 Pro:3 pro" "Apple M2 Ultra:2 ultra" "Apple M4:4 base" "Apple M1 Max:1 max"; do
   verif "machine : ${p%%:*} -> generation et gamme" "${p#*:}" "$(CIDRE_MACHINE= P="${p%%:*}" PATH="$T/autre-puce:$PATH" sh "$M" generation gamme | sed 's/^[a-z]*=//' | tr '\n' ' ' | sed 's/ $//')"
done
# les conditions
verif "si : <= faux" "1" "$(si 'coeurs_gpu <= 10')"
verif "si : > vrai" "0" "$(si 'coeurs_gpu > 10')"
verif "si : == vrai" "0" "$(si 'memoire_go == 32')"
verif "si : != faux" "1" "$(si 'memoire_go != 32')"
verif "si : >= et < vrais" "0" "$(si 'ecran_largeur >= 1728 et ecran_hauteur < 1200')"
verif "si : un terme faux suffit" "1" "$(si 'coeurs_gpu > 10 et ecran_largeur >= 1920')"
verif "si : fait inconnu = pas vraie (2)" "2" "$(si 'coeurs_cpu > 2')"
verif "si : operateur inconnu = pas vraie (2)" "2" "$(si 'coeurs_gpu = 24')"
verif "si : nombre attendu (2)" "2" "$(si 'coeurs_gpu <= dix')"
verif "si : la puce ne se compare pas (2)" "2" "$(si 'puce == 4')"
verif "si : famille_gpu >= 8 faux sur M1" "1" "$(si 'famille_gpu >= 8')"
verif "si : famille_gpu == 7 et macos >= 26" "0" "$(si 'famille_gpu == 7 et macos >= 26')"
verif "si : gamme == max" "0" "$(si 'gamme == max')"
verif "si : gamme != max faux" "1" "$(si 'gamme != max')"
verif "si : gamme ne s ordonne pas (2)" "2" "$(si 'gamme >= pro')"
verif "si : gamme attend un mot (2)" "2" "$(si 'gamme == 3')"
verif "si : macos_version ne se compare pas (2)" "2" "$(si 'macos_version == 26')"
verif "si : famille illisible = fausse (1)" "1" "$(CIDRE_MACHINE='famille_gpu=' sh "$M" si 'famille_gpu >= 8' >/dev/null 2>&1; echo $?)"
verif "si : condition vide (2)" "2" "$(si '')"
verif "si : fait illisible sur la machine = fausse (1)" "1" "$(CIDRE_MACHINE='coeurs_gpu=' sh "$M" si 'coeurs_gpu <= 10' >/dev/null 2>&1; echo $?)"
verif "syntaxe : bien formee, vraie ou non" "0" "$(sh "$M" syntaxe 'coeurs_gpu <= 10 et ecran_largeur >= 1920'; echo $?)"
verif "syntaxe : mal formee" "2" "$(sh "$M" syntaxe 'coeurs_gpu <= 10 ou ecran_largeur >= 1920'; echo $?)"
# une fiche a deux blocs : petite carte graphique, beaucoup de memoire
cat >"$CIDRE_PROFILS_BASE/996.toml" <<'FICHE'
[jeu]
appid = 996
nom = "Jeu a variantes"
[cidre]
d3d11 = "dxmt"
vsync = false
[[reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
section = "ScalabilityGroups"
[reglages_jeu.valeurs]
"sg.ShadowQuality" = "1"
"sg.TextureQuality" = "1"
[[reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
section = "/Script/Engine.GameUserSettings"
valeurs = { "Mode" = "0" }
[[machine]]
si = "coeurs_gpu <= 10 et ecran_largeur >= 1920"
[machine.cidre]
metalfx = true
vsync = true
[[machine.reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/GameUserSettings.ini"
section = "ScalabilityGroups"
[machine.reglages_jeu.valeurs]
"sg.ShadowQuality" = "0"
"sg.FoliageQuality" = "0"
[[machine.reglages_jeu]]
fichier = "AppData/Local/Jeu/Config/Autre.ini"
valeurs = { "X" = "1" }
[[machine]]
si = "memoire_go >= 64"
[machine.cidre]
fils_compilation = 12
vsync = false
[[machine]]
si = "coeurs_gpu <= dix"
[machine.cidre]
hud = true
[compat]
etat = "argent"
source = "cidre-test"
FICHE
regl() { sh "$FP" reglages 996 | awk -F'\t' -v n="$1" -v c="$2" '$1 == n && $2 == "valeur" && $3 == c { print $4 }'; }
# l analyseur : tout ce qui est sous [[machine]] reste sous machine.N (un runtime
# d avant le mecanisme ne lit que cidre et reglages_jeu.N : il ignore les blocs)
verif "toml : [machine.cidre] -> machine.N.cidre" "true" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/996.toml" | awk -F'\t' '$1 == "machine.1.cidre" && $2 == "metalfx" { print $4 }')"
verif "toml : [[machine.reglages_jeu]] -> machine.N.reglages_jeu.M" "AppData/Local/Jeu/Config/Autre.ini" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/996.toml" | awk -F'\t' '$1 == "machine.1.reglages_jeu.2" && $2 == "fichier" { print $4 }')"
verif "toml : [machine.reglages_jeu.valeurs] -> machine.N.reglages_jeu.M.valeurs" "0" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/996.toml" | awk -F'\t' '$1 == "machine.1.reglages_jeu.1.valeurs" && $2 == "sg.FoliageQuality" { print $4 }')"
verif "toml : la partie commune garde ses 2 entrees de reglages" "reglages_jeu.1 reglages_jeu.2" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/996.toml" | cut -f1 | grep '^reglages_jeu\.[0-9]*$' | awk '!v[$0]++' | tr '\n' ' ' | sed 's/ $//')"
verif "toml : le bloc suivant repart de machine.2" "12" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/996.toml" | awk -F'\t' '$1 == "machine.2.cidre" && $2 == "fils_compilation" { print $4 }')"
# machine de reference : aucun bloc ne s applique, la partie commune seule
verif "M1 Max : aucune variante" "" "$(sh "$FP" variantes 996)"
verif "M1 Max : [cidre] commun (vsync)" "false" "$(valeur 996 vsync)"
verif "M1 Max : pas d option de variante (metalfx = defaut livre)" "$(valeur 998 metalfx)" "$(valeur 996 metalfx)"
verif "M1 Max : 3 valeurs de reglages, 2 entrees" "3 2" "$(sh "$FP" reglages 996 | grep -c '	valeur	') $(sh "$FP" reglages 996 | cut -f1 | sort -u | wc -l | tr -d ' ')"
verif "M1 Max : sg.ShadowQuality commun" "1" "$(regl 1 sg.ShadowQuality)"
verif "M1 Max : json variantes vide" '"variantes":[]' "$(sh "$FP" json 996 | grep -o '"variantes":\[[^]]*\]')"
# petite carte graphique sur grand ecran : le 1er bloc se fond dans la partie commune
export CIDRE_MACHINE="$IMAC_M4"
verif "iMac M4 : variante appliquee" "coeurs_gpu <= 10 et ecran_largeur >= 1920" "$(sh "$FP" variantes 996)"
verif "iMac M4 : option ajoutee (metalfx)" "true" "$(valeur 996 metalfx)"
verif "iMac M4 : option remplacee (vsync)" "true" "$(valeur 996 vsync)"
verif "iMac M4 : option commune gardee (d3d11)" "dxmt" "$(valeur 996 d3d11)"
verif "iMac M4 : etat/source toujours rendus" "argent cidre-test" "$(valeur 996 etat) $(valeur 996 source)"
verif "iMac M4 : meme fichier et meme section = une seule entree" "3" "$(sh "$FP" reglages 996 | cut -f1 | sort -u | wc -l | tr -d ' ')"
verif "iMac M4 : valeur remplacee (sg.ShadowQuality)" "0" "$(regl 1 sg.ShadowQuality)"
verif "iMac M4 : valeur commune gardee (sg.TextureQuality)" "1" "$(regl 1 sg.TextureQuality)"
verif "iMac M4 : valeur ajoutee (sg.FoliageQuality)" "0" "$(regl 1 sg.FoliageQuality)"
verif "iMac M4 : 2e entree commune intacte" "0" "$(regl 2 Mode)"
verif "iMac M4 : entree de plus (autre fichier)" "AppData/Local/Jeu/Config/Autre.ini" "$(sh "$FP" reglages 996 | awk -F'\t' '$1 == 3 && $2 == "fichier" { print $3 }')"
verif "iMac M4 : json cidre fondu, sans doublon" '"cidre":{"d3d11":"dxmt","vsync":true,"metalfx":true}' "$(sh "$FP" json 996 | grep -o '"cidre":{[^}]*}')"
verif "iMac M4 : json variantes" '"variantes":["coeurs_gpu <= 10 et ecran_largeur >= 1920"]' "$(sh "$FP" json 996 | grep -o '"variantes":\[[^]]*\]')"
verif "iMac M4 : json reglages fondus" '"valeurs":{"sg.ShadowQuality":"0","sg.TextureQuality":"1","sg.FoliageQuality":"0"}' "$(sh "$FP" json 996 | grep -o '"valeurs":{[^}]*}' | head -1)"
verif "iMac M4 : condition mal formee = bloc ignore (hud = defaut livre)" "$(valeur 998 hud)" "$(valeur 996 hud)"
# l utilisateur garde la main sur une option de variante
printf '[996]\nmetalfx = false\n' >"$CIDRE_PROFILS"
verif "utilisateur > variante de la fiche (metalfx)" "false" "$(valeur 996 metalfx)"
: >"$CIDRE_PROFILS"
# deux blocs vrais : dans l ordre de la fiche, le dernier gagne
export CIDRE_MACHINE="coeurs_gpu=8 memoire_go=64 ecran_largeur=2560 ecran_hauteur=1440"
verif "deux blocs : les deux conditions" "2" "$(sh "$FP" variantes 996 | wc -l | tr -d ' ')"
verif "deux blocs : le dernier gagne (vsync)" "false" "$(valeur 996 vsync)"
verif "deux blocs : chacun apporte sa cle" "true 12" "$(valeur 996 metalfx) $(valeur 996 fils_compilation)"
# petit ecran : le terme sur l ecran ecarte le bloc
export CIDRE_MACHINE="coeurs_gpu=10 memoire_go=16 ecran_largeur=1470 ecran_hauteur=956"
verif "petite carte, petit ecran : aucune variante" "" "$(sh "$FP" variantes 996)"
verif "petite carte, petit ecran : reglages communs" "1" "$(regl 1 sg.ShadowQuality)"
# application a l INI : la variante sur l iMac M4, la partie commune sur le M1 Max
printf '[ScalabilityGroups]\r\nsg.ShadowQuality=3\r\nsg.TextureQuality=3\r\n\r\n[/Script/Engine.GameUserSettings]\r\nMode=2\r\n' >"$INI"
rm -f "$INI.avant-cidre" "$U/AppData/Local/Jeu/Config/Autre.ini"
export CIDRE_MACHINE="$IMAC_M4"
sortie=$(sh "$R/tests/reglages_jeu.sh" 996); rc=$?
verif "INI iMac M4 : un fichier de la variante absent -> code 3, le reste pose" "3 2" "$rc $(printf '%s\n' "$sortie" | grep -c poses)"
verif "INI iMac M4 : valeurs de la variante" "sg.ShadowQuality=0 sg.TextureQuality=1 sg.FoliageQuality=0 Mode=0" "$(tr -d '\r' <"$INI" | grep = | tr '\n' ' ' | sed 's/ $//')"
printf 'X=0\r\n' >"$U/AppData/Local/Jeu/Config/Autre.ini"
sortie=$(sh "$R/tests/reglages_jeu.sh" 996); rc=$?
verif "INI iMac M4 : relance = code 0, 2 deja en place + 1 pose" "0 2 1" "$rc $(printf '%s\n' "$sortie" | grep -c 'deja en place') $(printf '%s\n' "$sortie" | grep -c poses)"
verif "INI iMac M4 : une ecriture par fichier et par section (pas de va-et-vient)" "" "$(sh "$R/tests/reglages_jeu.sh" 996 | grep poses)"
export CIDRE_MACHINE="$M1MAX"
sh "$R/tests/reglages_jeu.sh" 996 >/dev/null
verif "INI M1 Max : valeurs communes ; la cle propre a la variante n est pas touchee" "sg.ShadowQuality=1 sg.TextureQuality=1 sg.FoliageQuality=0 Mode=0" "$(tr -d '\r' <"$INI" | grep = | tr '\n' ' ' | sed 's/ $//')"
# les fiches livrees : chaque bloc [[machine]] a une condition bien formee
n=0
for f in $(grep -l '^\[\[machine\]\]' "$R"/profils/*.toml 2>/dev/null); do
   a=$(basename "$f" .toml); n=$((n + 1))
   sh "$FP" toml "$f" | awk -F'\t' '$1 ~ /^machine\.[0-9]+$/ && !vu[$1]++ { b++ } $1 ~ /^machine\.[0-9]+$/ && $2 == "si" { s++; print $4 } END { if (b != s) print "?" }' >"$T/si"
   while IFS= read -r c; do
      sh "$M" syntaxe "$c" && ok "profils/$a.toml : si « $c » bien formee" || echec "profils/$a.toml : bloc [[machine]] sans condition ou condition mal formee (« $c »)"
   done <"$T/si"
done
[ $n -gt 0 ] && ok "$n fiche(s) livree(s) a variantes par machine" || echec "aucune fiche livree n a de bloc [[machine]] (Expedition 33 en porte un)"

echo "== 6c. compatibilite par famille de Mac ([[compat.machines]])"
cat >"$CIDRE_PROFILS_BASE/995.toml" <<'FICHE'
[jeu]
appid = 995
nom = "Jeu par famille"
[cidre]
d3d11 = "dxmt"
[compat]
etat = "argent"
source = "cidre-test"
machine = "M1 Max 32 Go"
voie = "dxmt"
fps_jeu = 40
[[compat.machines]]
nom = "M1"
si = "famille_gpu <= 7"
voie = "d3d12"
etat = "ko"
options = "dx12=true sm66=true"
[[compat.machines]]
nom = "M2+"
si = "famille_gpu >= 8"
voie = "dxmt"
etat = "or"
fps_jeu = 60
[[compat.machines]]
nom = "M2+"
si = "famille_gpu >= 8"
voie = "d3d12"
etat = "bronze"
[[compat.machines]]
nom = "Ultra"
si = "gamme == ultra"
etat = "or"
notes = "toutes voies"
[compat.crossover]
source = "crossover"
FICHE
# la meme, qui passe en D3D12 (dx12, sm66) sur les familles qui le permettent
sed 's/^appid = 995$/appid = 994/' "$CIDRE_PROFILS_BASE/995.toml" >"$CIDRE_PROFILS_BASE/994.toml"
printf '[[machine]]\nsi = "famille_gpu >= 8"\n[machine.cidre]\ndx12 = true\nsm66 = true\n' >>"$CIDRE_PROFILS_BASE/994.toml"
CJ() { sh "$FP" json "$1" | grep -o "\"$2\":{[^}]*}"; }
CM() { sh "$FP" compat "$1" | awk -F'\t' -v c="$2" '$1 == c { print $2 }'; }
APP() { sh "$FP" compat "$1" | awk -F'\t' '$1 == "machines" { printf "%s%s", s, $5; s = " " }'; }
verif "toml : [[compat.machines]] -> compat.machines.N" "bronze" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/995.toml" | awk -F'\t' '$1 == "compat.machines.3" && $2 == "etat" { print $4 }')"
verif "toml : [compat.crossover] apres les entrees reste une sous-table" "crossover" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/995.toml" | awk -F'\t' '$1 == "compat.crossover" { print $4 }')"
verif "un runtime d avant ne lit que [compat] (cle compat a plat)" "argent" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/995.toml" | awk -F'\t' '$1 == "compat" && $2 == "etat" { print $4 }')"
# M1 Max : l entree M1 s applique, mais parle du D3D12 ; la fiche est en DXMT
export CIDRE_MACHINE="$M1MAX"
verif "M1 : entrees qui s appliquent" "true false false false" "$(APP 995)"
verif "M1 : [compat] de reference" "argent  40" "$(CM 995 etat) $(CM 995 pour) $(CM 995 fps_jeu)"
verif "M1 : etat rendu a plat" "argent" "$(valeur 995 etat)"
# M4 : l entree M2+ en DXMT remplace [compat] tout entier
export CIDRE_MACHINE="$IMAC_M4"
verif "M4 : entrees qui s appliquent" "false true true false" "$(APP 995)"
verif "M4 : compat = l entree M2+ DXMT" '"compat":{"pour":"M2+","voie":"dxmt","etat":"or","fps_jeu":60}' "$(CJ 995 compat)"
verif "M4 : etat rendu a plat (profil_cidre.sh)" "or" "$(valeur 995 etat)"
verif "M4 : compat_reference = [compat] ecrit" '"compat_reference":{"etat":"argent","source":"cidre-test","machine":"M1 Max 32 Go","voie":"dxmt","fps_jeu":40}' "$(CJ 995 compat_reference)"
verif "M4 : json, 4 entrees par famille avec applique" "4 2" "$(sh "$FP" json 995 | grep -o '"applique":[a-z]*' | wc -l | tr -d ' ') $(sh "$FP" json 995 | grep -o '"applique":true' | wc -l | tr -d ' ')"
verif "M4 : options d une entree rendues dans compat_machines" '"options":"dx12=true sm66=true"' "$(sh "$FP" json 995 | grep -o '"options":"[^"]*"')"
verif "M4 : l index garde l etat de reference" "argent" "$(sh "$FP" toml "$CIDRE_PROFILS_BASE/995.toml" | awk -F'\t' '$1 == "compat" && $2 == "etat" { print $4 }')"
# une entree sans voie vaut pour toutes ; la derniere qui vaut gagne
export CIDRE_MACHINE="famille_gpu=8 gamme=ultra"
verif "M2 Ultra : l entree sans voie, la derniere, gagne" "or Ultra dxmt toutes voies" "$(CM 995 etat) $(CM 995 pour) $(CM 995 voie) $(CM 995 notes)"
# famille illisible : aucune entree, [compat] seul
export CIDRE_MACHINE="famille_gpu= gamme="
verif "famille illisible : [compat] de reference" "argent false false false false" "$(CM 995 etat) $(APP 995)"
# options par famille : dx12 et sm66 sur M2+ seulement ; la voie suit, et avec elle la compat
export CIDRE_MACHINE="$IMAC_M4"
verif "M4 : dx12 et sm66 poses par le bloc famille_gpu >= 8" "true true" "$(valeur 994 dx12) $(valeur 994 sm66)"
verif "M4 : voie d3d12, compat = l entree M2+ D3D12" "bronze d3d12 M2+" "$(CM 994 etat) $(CM 994 voie) $(CM 994 pour)"
export CIDRE_MACHINE="$M1MAX"
verif "M1 : ni dx12 ni sm66 (defauts livres)" "$(valeur 998 dx12) $(valeur 998 sm66)" "$(valeur 994 dx12) $(valeur 994 sm66)"
verif "M1 : compat de reference" "argent dxmt" "$(CM 994 etat) $(CM 994 voie)"
rm -f "$CIDRE_PROFILS_BASE/995.toml" "$CIDRE_PROFILS_BASE/994.toml"
# Expedition 33 : D3D12 ko sur M1, DXMT argent et D3D12 bronze sur M2+ ; la fiche reste en DXMT
verif "1903340 : 3 entrees par famille" "3" "$(sh "$FP" json 1903340 | grep -o '"applique":' | wc -l | tr -d ' ')"
verif "1903340 M1 : compat de reference, D3D12 ko pour ce Mac" "argent M1 Max 32 Go|M1 d3d12 ko true" "$(CM 1903340 etat) $(CM 1903340 machine)|$(sh "$FP" compat 1903340 | awk -F'\t' '$1 == "machines" && $5 == "true" { print $2, $3, $4, $5 }')"
verif "1903340 M4 : compat = M2 et suivants en DXMT" "argent M2 et suivants dxmt 35" "$(CIDRE_MACHINE="$IMAC_M4" sh "$FP" compat 1903340 | awk -F'\t' '$1 == "etat" || $1 == "pour" || $1 == "voie" || $1 == "fps_jeu" { v[$1] = $2 } END { print v["etat"], v["pour"], v["voie"], v["fps_jeu"] }')"
verif "1903340 M4 : D3D12 bronze, pas active par la fiche" "bronze false" "$(CIDRE_MACHINE="$IMAC_M4" sh "$FP" compat 1903340 | awk -F'\t' '$1 == "machines" && $3 == "d3d12" && $5 == "true" { print $4 }') $(CIDRE_MACHINE="$IMAC_M4" sh "$R/tests/profil_cidre.sh" 1903340 | sed -n 's/^dx12=//p')"
# les fiches livrees : chaque entree a un nom, une condition bien formee, un etat et une voie connus
n=0
for f in $(grep -l '^\[\[compat\.machines\]\]' "$R"/profils/*.toml 2>/dev/null); do
   a=$(basename "$f" .toml)
   sh "$FP" toml "$f" | awk -F'\t' '$1 ~ /^compat\.machines\.[0-9]+$/ { if (!($1 in vu)) { vu[$1] = 1; o[++n] = $1 } v[$1, $2] = $4 } END { for (k = 1; k <= n; k++) print v[o[k], "nom"] "\t" v[o[k], "si"] "\t" v[o[k], "etat"] "\t" v[o[k], "voie"] }' >"$T/cm"
   while IFS="	" read -r nom c e v; do
      n=$((n + 1))
      { [ -n "$nom" ] && sh "$M" syntaxe "$c" && case $e in or|argent|bronze|ko|non-teste) true ;; *) false ;; esac && case $v in ''|dxmt|dxvk|d3d12|wined3d|natif) true ;; *) false ;; esac; } \
         && ok "profils/$a.toml : entree « $nom » ($c, $v : $e) bien formee" || echec "profils/$a.toml : entree par famille mal formee (« $nom » « $c » « $e » « $v »)"
   done <"$T/cm"
done
[ $n -gt 0 ] && ok "$n entree(s) par famille dans les fiches livrees" || echec "aucune fiche livree n a d entree [[compat.machines]] (Expedition 33 en porte)"
export CIDRE_MACHINE="$M1MAX"

echo "== 6b. arguments du jeu (option arguments, tests/arguments_jeu.sh)"
AJ() { sh "$R/tests/arguments_jeu.sh" "$@" | tr '\n' ' ' | sed 's/ $//'; }
verif "arguments : decoupes aux espaces" "-force-gfx-direct -window-mode borderless" "$(AJ '  -force-gfx-direct   -window-mode borderless ' jeu.exe)"
verif "arguments : option deja presente sautee avec sa valeur" "-force-gfx-direct" "$(AJ '-force-gfx-direct -window-mode borderless' jeu.exe -window-mode windowed)"
verif "arguments : pas de doublon" "" "$(AJ '-force-gfx-direct' jeu.exe -force-gfx-direct)"
verif "arguments : aucune expansion de motif" "-x*" "$(AJ '-x*' jeu.exe)"
verif "arguments : chaine vide" "" "$(AJ '' jeu.exe)"
printf '[jeu]\nappid = 996\n[cidre]\narguments = "-force-gfx-direct -popupwindow"\n' >"$CIDRE_PROFILS_BASE/996.toml"
verif "arguments : lus dans la fiche" "-force-gfx-direct -popupwindow" "$(valeur 996 arguments)"
verif "arguments : json de la fiche" '"arguments":"-force-gfx-direct -popupwindow"' "$(resoudre 996 json | grep -o '"arguments":"[^"]*"')"
rm -f "$CIDRE_PROFILS_BASE/996.toml"
cp "$CIDRE_PROFILS" "$T/perso.avant-arguments"
sh "$R/cidre" set defaut arguments "-a -b" >/dev/null 2>&1
verif "cidre set defaut arguments" "-a -b" "$(valeur 998 arguments)"
sh "$R/cidre" set defaut arguments 'a"b' >/dev/null 2>&1; rc=$?
verif "cidre set arguments : guillemet refuse" "2" "$rc"
cp "$T/perso.avant-arguments" "$CIDRE_PROFILS"
grep -q 'ARGJ=${CIDRE_ARGUMENTS:-$(profil arguments)}' "$R/tests/lancer_depuis_steam.sh" && ok "lanceur : option arguments lue" || echec "lanceur : option arguments non lue"

echo "== 7. syntaxe"
for s in cidre tests/profil_cidre.sh tests/fiche_profil.sh tests/reglages_jeu.sh tests/machine.sh tests/lancer_depuis_steam.sh tests/arguments_jeu.sh tests/empaqueter_runtime.sh tests/tester_profils.sh; do
   sh -n "$R/$s" 2>/dev/null && ok "sh -n $s" || echec "sh -n $s"
done

# Les scripts qui attendent la fin d'un jeu sont entierement entre accolades et
# se ferment par `exit` : le shell les lit en entier avant de commencer. Sinon,
# un fichier modifie pendant la partie est repris au milieu d'une autre
# commande (2026-10-13 : `cidre play` a fini dans la desinstallation).
enveloppe() { # <script> : 1re commande `{`, puis ... `exit`, `}` en dernier
   awk 'NR == 1 && /^#!/ { next } /^[ \t]*(#|$)/ { next }
        !debut { debut = $0 } { avant = dernier; dernier = $0 }
        END { exit !(debut == "{" && dernier == "}" && avant ~ /^exit( |$)/) }' "$1"
}
for s in cidre tests/lancer_depuis_steam.sh tests/etape2_pile_arm64ec.sh; do
   enveloppe "$R/$s" && ok "lu en entier avant d'executer : $s" || echec "$s n'est pas enveloppe dans { ... exit; } : une modification pendant un jeu peut executer n'importe quoi"
done
printf '#!/bin/sh\nset -u\necho a\nexit 0\n' >"$T/nu.sh"; printf '#!/bin/sh\n# x\n{\nset -u\necho a\nexit $?\n}\n' >"$T/enveloppe.sh"
enveloppe "$T/nu.sh" && echec "la verification laisse passer un script nu" || ok "la verification refuse un script nu"
enveloppe "$T/enveloppe.sh" && ok "la verification accepte un script enveloppe" || echec "la verification refuse un script enveloppe"
# ... et l'enveloppe protege bien : un script allonge pendant qu'il attend ne
# reprend pas au milieu de ce qu'on y a ajoute.
printf '#!/bin/sh\n{\nsleep 1\nexit 0\n}\n' >"$T/attend.sh"
sh "$T/attend.sh" >"$T/attend.sortie" 2>&1 & pid=$!
printf 'echo AJOUT-EXECUTE\n' >>"$T/attend.sh"; wait $pid
verif "script enveloppe allonge pendant qu'il attend : rien d'ajoute n'est execute" "" "$(cat "$T/attend.sortie")"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
