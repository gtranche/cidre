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
#   4. le marqueur reglages_jeu_appliques dans le profil utilisateur ;
#   5. `fiche_profil.sh maj` contre une copie locale (file://), et sans reseau ;
#   6. sh -n sur les scripts de la chaine.
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
# la fiche d'Expedition 33 porte les reglages du jeu et la compat du 2026-10-11
verif "1903340 : reglages_jeu sg.ResolutionQuality" "66" "$(sh "$R/tests/fiche_profil.sh" reglages 1903340 | awk -F'\t' '$2=="sg.ResolutionQuality"{print $3}')"
verif "1903340 : 12 valeurs de reglages" "12" "$(sh "$R/tests/fiche_profil.sh" reglages 1903340 | grep -c '^valeur	')"
verif "1903340 : compat fps_menu" "90" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/1903340.toml" | awk -F'\t' '$1=="compat"&&$2=="fps_menu"{print $4}')"
verif "1903340 : json rapports = 0" "0" "$(sh "$R/tests/fiche_profil.sh" json 1903340 | sed -n 's/.*"rapports":\([0-9]*\)}$/\1/p')"

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
verif "table en ligne : 3 valeurs" "3" "$(sh "$R/tests/fiche_profil.sh" reglages 997 | grep -c '^valeur	')"
verif "table en ligne : cle nue" "2" "$(sh "$R/tests/fiche_profil.sh" reglages 997 | awk -F'\t' '$2=="c"{print $3}')"
verif "table en ligne : guillemets echappes" 'deux "mots"' "$(sh "$R/tests/fiche_profil.sh" reglages 997 | awk -F'\t' '$2=="d"{print $3}')"
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

echo "== 4. marqueur reglages_jeu_appliques"
verif "avant : pas de marqueur" "" "$(valeur 999 reglages_jeu_appliques)"
sh "$R/tests/profil_cidre.sh" 999 set reglages_jeu_appliques true
verif "apres : marqueur a true" "true" "$(valeur 999 reglages_jeu_appliques)"
verif "marqueur : les autres reglages du jeu restent" "false" "$(valeur 999 hud)"
sh "$R/tests/profil_cidre.sh" 999 unset reglages_jeu_appliques
verif "unset : marqueur retire" "" "$(valeur 999 reglages_jeu_appliques)"

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
sortie=$(CIDRE_PROFILS_URL="file://$T/nulle-part/" sh "$R/tests/fiche_profil.sh" maj json 2>/dev/null); rc=$?
verif "hors reseau : code 1" "1" "$rc"
verif "hors reseau : json ok=false" '{"ok":false' "$(printf '%s' "$sortie" | cut -c1-11)"
verif "hors reseau : cache intact" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"

echo "== 6. syntaxe"
for s in cidre tests/profil_cidre.sh tests/fiche_profil.sh tests/reglages_jeu.sh tests/lancer_depuis_steam.sh tests/empaqueter_runtime.sh tests/tester_profils.sh; do
   sh -n "$R/$s" 2>/dev/null && ok "sh -n $s" || echec "sh -n $s"
done

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
