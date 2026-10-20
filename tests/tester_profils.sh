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
#   5b. `maj` par l'archive de la base (file://) : echange du cache, archive refusee
#      (chemin douteux, fiche manquante) -> fiches une a une ; fiche provisoire
#      d'un jeu sans fiche (ProtonDB et magasin Steam factices, file://) ;
#   6. variantes par machine (blocs [[machine]], tests/machine.sh) : conditions,
#      fusion dans [cidre] et [[reglages_jeu]], priorite, application a l'INI,
#      fiche d'Expedition 33 sur un M1 Max et sur un iMac M4 ;
#   6c. compatibilite par famille de Mac ([[compat.machines]]) : faits famille_gpu,
#      generation, gamme, macos ; [compat] remplace par l'entree qui vaut ici et
#      parle de la voie de la fiche ; options par famille ; Expedition 33 ;
#   6b. arguments du jeu (option arguments) : decoupage, doublons, fiche, `cidre set` ;
#       d3d9, dlss et generation_images (metalfx ou non) : valeurs, fiche, `cidre set`, lus par le lanceur ;
#       sortie_normale (tests/sortie_normale.sh) : codes, duree minimale, fiche de Fahrenheit ;
#       exe_sans_anticheat : exe de Steam remplace (faux ELDEN RING), absent, coupe, introuvable, chemin ;
#       knowndlls (tests/knowndlls.sh) : fiche de D2R, validation, pose et retrait dans une ruche factice ;
#   6d. version macOS 32 bits seulement : binaire installe (faux Mach-O), fiche,
#      cache du client Steam ; list/play/dl/install la traitent en jeu Windows ;
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
# ni archive de la base, ni fiches provisoires reelles (5b les essaie en file://)
export CIDRE_PROFILS_ARCHIVE= CIDRE_PROFILS_PROVISOIRES="$T/provisoires"
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
verif "1903340 : iMac M4 = les memes reglages, plus une entree a part (sortie 1920x1080, mesure du 2026-10-15)" "$(E33)" "$(CIDRE_MACHINE="$IMAC_M4" sh "$R/tests/fiche_profil.sh" reglages 1903340 | awk -F"\t" '$1 != 3')"
E33M4() { CIDRE_MACHINE="$IMAC_M4" sh "$R/tests/fiche_profil.sh" reglages 1903340; }
verif "1903340 : iMac M4, entree 3 a id, meme section INI que l entree 1" "sortie-imac-1920x1080 /Script/SandFall.ConfigurableGameUserSettings 1920 1080 0" "$(E33M4 | awk -F"\t" '$1==3 && $2=="id"{print $3}') $(E33M4 | awk -F"\t" '$1==3 && $2=="section"{print $3}') $(E33M4 | awk -F"\t" '$1==3 && $3=="ResolutionSizeX"{print $4}') $(E33M4 | awk -F"\t" '$1==3 && $3=="LastUserConfirmedResolutionSizeY"{print $4}') $(E33M4 | awk -F"\t" '$1==3 && $3=="FullscreenMode"{print $4}')"
verif "1903340 : pas de sortie 1920x1080 sur un autre ecran (MacBook Air M4, 10 coeurs)" "" "$(CIDRE_MACHINE="coeurs_gpu=10 ecran_largeur=1470 ecran_hauteur=956" sh "$R/tests/fiche_profil.sh" reglages 1903340 | grep ResolutionSize)"
verif "1903340 : pas de sortie 1920x1080 sur le M1 Max" "" "$(CIDRE_MACHINE="coeurs_gpu=24 ecran_largeur=1728 ecran_hauteur=1117" sh "$R/tests/fiche_profil.sh" reglages 1903340 | grep ResolutionSize)"
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
tso_sans = "UnityPlayer.dll GameAssembly.dll;1522d00-15246a0"
tso_msvc = true
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
verif "fiche : liste en chaine (tso_sans)" "UnityPlayer.dll GameAssembly.dll;1522d00-15246a0" "$(valeur 999 tso_sans)"
verif "fiche : tso_msvc" "true" "$(valeur 999 tso_msvc)"
verif "[defaut] livre : tso_msvc false" "false" "$(valeur 998 tso_msvc)"
# la conversion du lanceur vers FEX_EXTENDEDVOLATILEMETADATA (meme commande que lancer_depuis_steam.sh)
verif "tso_sans -> syntaxe de FEX" "UnityPlayer.dll:GameAssembly.dll;1522d00-15246a0" \
   "$(printf '%s' "$(valeur 999 tso_sans)" | tr -d '"' | tr -s ' \t' '::' | sed 's/^://; s/:$//')"
verif "fiche : etat/source rendus a plat" "bronze cidre-test" "$(valeur 999 etat) $(valeur 999 source)"
verif "perso : seules les cles utilisateur du jeu" '{"hud":false}' "$(resoudre 999 perso)"
verif "json : rapports comptes" "2" "$(sh "$R/tests/fiche_profil.sh" json 999 | sed -n 's/.*"rapports":\([0-9]*\)}$/\1/p')"
verif "json : jeu.nom" '"nom":"Jeu de test"' "$(sh "$R/tests/fiche_profil.sh" json 999 | grep -o '"nom":"Jeu de test"')"
verif "jeu sans fiche : [defaut] seul" "true" "$(valeur 998 tso)"
verif "jeu sans fiche : json null" "null" "$(sh "$R/tests/fiche_profil.sh" json 998)"
# cache vide : la copie livree sert
verif "copie livree en repli (1903340 garde_index)" "false" "$(valeur 1903340 garde_index)"
# cache present : il prime, sauf copie livree plus recente que lui (index-depot.toml
# de l archive, sinon l horodatage de la derniere mise a jour)
printf '[cidre]\ngarde_index = true\n' >"$CIDRE_PROFILS_BASE/1903340.toml"
E=$(md5 -q "$R/profils/1903340.toml" 2>/dev/null || md5sum "$R/profils/1903340.toml" | cut -c1-32)
depot() { printf '[1903340]\nempreinte = "%s"\nanciennes = "%s"\n\n[1]\nempreinte = "%s"\n' "$1" "$2" "$E" >"$CIDRE_PROFILS_BASE/index-depot.toml"; }
depot "$E" ""
verif "cache > copie livree dont il part (empreinte)" "true" "$(valeur 1903340 garde_index)"
depot 0123456789abcdef0123456789abcdef "aaaa $E bbbb"
verif "cache > copie livree plus ancienne (anciennes)" "true" "$(valeur 1903340 garde_index)"
depot 0123456789abcdef0123456789abcdef "aaaa bbbb"
verif "copie livree inconnue de l archive > cache" "false" "$(valeur 1903340 garde_index)"
verif "copie livree plus recente : json origine livree" '"origine":"livree"' "$(sh "$R/tests/fiche_profil.sh" json 1903340 | grep -o '"origine":"[a-z]*"')"
verif "copie livree plus recente : chemin" "$R/profils/1903340.toml" "$(sh "$R/tests/fiche_profil.sh" chemin 1903340)"
printf '[1]\nempreinte = "%s"\nanciennes = ""\n' "$E" >"$CIDRE_PROFILS_BASE/index-depot.toml"
verif "fiche absente d index-depot (ecrite depuis) : copie livree > cache" "false" "$(valeur 1903340 garde_index)"
rm -f "$CIDRE_PROFILS_BASE/index-depot.toml"
touch -t 209901010000 "$CIDRE_PROFILS_BASE/horodatage"
verif "sans index-depot, maj apres la copie livree : cache > copie livree" "true" "$(valeur 1903340 garde_index)"
touch -t 200001010000 "$CIDRE_PROFILS_BASE/horodatage"
verif "sans index-depot, copie livree plus recente que la maj : elle sert" "false" "$(valeur 1903340 garde_index)"
rm -f "$CIDRE_PROFILS_BASE/horodatage"
verif "sans index-depot ni horodatage : copie livree" "false" "$(valeur 1903340 garde_index)"
verif "jeu du seul cache : le cache sert" "true" "$(printf '[cidre]\ngarde_index = true\n' >"$CIDRE_PROFILS_BASE/424243.toml"; valeur 424243 garde_index)"
rm -f "$CIDRE_PROFILS_BASE/1903340.toml" "$CIDRE_PROFILS_BASE/424243.toml"
# api_disponibles (importe de PCGamingWiki) = "d3d12" seulement : dx12 par defaut,
# sauf choix explicite de la fiche ou de l utilisateur (dx12, d3d11 pour ce jeu,
# api autre que d3d12). Exp33 partait en D3D12 au lieu de DXMT (2026-10-16).
api12() { printf '[jeu]\n%bapi_disponibles = "d3d12"\n[jeu.sources]\napi_disponibles = "pcgamingwiki 2026-10-15"\n[cidre]\n%b' "$1" "$2" >"$CIDRE_PROFILS_BASE/424244.toml"; valeur 424244 dx12; }
verif "api_disponibles d3d12 sans choix : dx12" "true" "$(api12 '' '')"
verif "api_disponibles d3d12 + [jeu] api importee d3d12 : dx12" "true" "$(api12 'api = "d3d12"\n' '')"
verif "api_disponibles d3d12 + [cidre] d3d11 = dxmt : pas de dx12" "false" "$(api12 '' 'd3d11 = "dxmt"\n')"
verif "api_disponibles d3d12 + [cidre] d3d11 = dxvk : pas de dx12" "false" "$(api12 '' 'd3d11 = "dxvk"\n')"
verif "api_disponibles d3d12 + [jeu] api = d3d11 : pas de dx12" "false" "$(api12 'api = "d3d11"\n' '')"
verif "api_disponibles d3d12 + [jeu] api = vulkan : pas de dx12" "false" "$(api12 'api = "vulkan"\n' '')"
verif "api_disponibles d3d12 + [cidre] dx12 = false : pas de dx12" "false" "$(api12 '' 'dx12 = false\n')"
verif "api_disponibles d3d12 + api = d3d11 + dx12 = true : dx12" "true" "$(api12 'api = "d3d11"\n' 'dx12 = true\n')"
printf '[defaut]\nd3d11 = "dxvk"\n' >"$CIDRE_PROFILS"
verif "d3d11 du [defaut] utilisateur : pas un choix pour ce jeu, dx12" "true" "$(api12 '' '')"
printf '[424244]\nd3d11 = "dxmt"\n' >"$CIDRE_PROFILS"
verif "d3d11 pose par l utilisateur sur ce jeu : pas de dx12" "false" "$(api12 '' '')"
printf '[424244]\ndx12 = true\n' >"$CIDRE_PROFILS"
verif "dx12 pose par l utilisateur > d3d11 de la fiche" "true" "$(api12 '' 'd3d11 = "dxmt"\n')"
rm -f "$CIDRE_PROFILS" "$CIDRE_PROFILS_BASE/424244.toml"
# la copie enrichie d Exp33 (fiche du depot + [jeu] api_disponibles = "d3d12"),
# reconnue par index-depot.toml : elle sert, et reste en DXMT
{ sed '/^lanceur = /a\
api_disponibles = "d3d12"\
[jeu.sources]\
api_disponibles = "pcgamingwiki 2026-10-15"
' "$R/profils/1903340.toml"; } >"$CIDRE_PROFILS_BASE/1903340.toml"
depot "$E" ""
verif "1903340 copie enrichie (api_disponibles d3d12) : DXMT, pas de dx12" "enrichie dxmt false" \
   "$(grep -q '^api_disponibles = "d3d12"' "$(sh "$R/tests/fiche_profil.sh" chemin 1903340)" && echo enrichie) $(valeur 1903340 d3d11) $(valeur 1903340 dx12)"
rm -f "$CIDRE_PROFILS_BASE/1903340.toml" "$CIDRE_PROFILS_BASE/index-depot.toml"
# index_depot.py (workflow de l archive) sur un petit depot git : version courante
# et versions passees de chaque fiche ; refuse un clone superficiel
if command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
   G="$T/depot-git"; mkdir -p "$G/profils"
   git -C "$G" init -q && git -C "$G" config user.email t@t && git -C "$G" config user.name t
   printf '[cidre]\ndx12 = true\n' >"$G/profils/5.toml"; git -C "$G" add -A && git -C "$G" commit -qm 1
   v1=$(md5 -q "$G/profils/5.toml" 2>/dev/null || md5sum "$G/profils/5.toml" | cut -c1-32)
   printf '[cidre]\ndx12 = false\n' >"$G/profils/5.toml"; printf '[jeu]\n' >"$G/profils/6.toml"; printf '#\n' >"$G/profils/index.toml"
   git -C "$G" add -A && git -C "$G" commit -qm 2
   v2=$(md5 -q "$G/profils/5.toml" 2>/dev/null || md5sum "$G/profils/5.toml" | cut -c1-32)
   python3 -I "$R/tests/outils/index_depot.py" "$G/profils" >"$T/index-depot.toml"; rc=$?
   verif "index_depot.py : code 0, sections des fiches seules" "0 [5] [6]" "$rc $(grep '^\[' "$T/index-depot.toml" | tr '\n' ' ' | sed 's/ $//')"
   verif "index_depot.py : empreinte = version courante, anciennes = la precedente" "$v2 $v1" "$(sh "$R/tests/fiche_profil.sh" toml "$T/index-depot.toml" | awk -F'\t' '$1 == "5" { printf "%s%s", (n++ ? " " : ""), $4 }')"
   git clone -q --depth 1 "file://$G" "$T/superficiel" 2>/dev/null
   verif "index_depot.py : clone superficiel refuse" "1" "$(python3 -I "$R/tests/outils/index_depot.py" "$T/superficiel/profils" 2>/dev/null >/dev/null; echo $?)"
else
   echo "  (git ou python3 absent : index_depot.py non essaye)"
fi
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
# creer = true : l Engine.ini d Unreal, que le jeu n ecrit pas, cree avec sa section
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/Engine.ini"\nsection = "SystemSettings"\ncreer = true\nvaleurs = { "r.Lumen.ScreenProbeGather.DownsampleFactor" = "32", "r.Lumen.Reflections.Allow" = "0" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "creer : code 0" "0" "$rc"
verif "creer : journal" "cree" "$(printf '%s' "$sortie" | grep -o 'cree (absent' | cut -c1-4)"
verif "creer : section et cles" "[SystemSettings] r.Lumen.ScreenProbeGather.DownsampleFactor=32 r.Lumen.Reflections.Allow=0" "$(tr -d '\r' <"$U/AppData/Local/Jeu/Config/Engine.ini" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')"
verif "creer : sauvegarde vide (absent avant)" "0" "$(wc -c <"$U/AppData/Local/Jeu/Config/Engine.ini.avant-cidre" | tr -d ' ')"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "creer : relance deja en place" "0 deja en place" "$rc $(printf '%s' "$sortie" | grep -o 'deja en place')"
# fichier deja la : les autres cles et sections restent
printf '[Core.Log]\r\nLogX=Verbose\r\n' >"$U/AppData/Local/Jeu/Config/Engine.ini"; rm -f "$U/AppData/Local/Jeu/Config/Engine.ini.avant-cidre"
sh "$R/tests/reglages_jeu.sh" 999 >/dev/null
verif "creer, fichier existant : autres cles gardees" "[Core.Log] LogX=Verbose [SystemSettings] r.Lumen.ScreenProbeGather.DownsampleFactor=32 r.Lumen.Reflections.Allow=0" "$(tr -d '\r' <"$U/AppData/Local/Jeu/Config/Engine.ini" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')"
rm -f "$U/AppData/Local/Jeu/Config/Engine.ini" "$U/AppData/Local/Jeu/Config/Engine.ini.avant-cidre"
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Absent/Engine.ini"\nsection = "SystemSettings"\ncreer = true\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "creer, dossier absent : code 3, rien cree" "3 " "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?) $(ls "$U/AppData/Local/Jeu" | grep Absent)"
printf '[reglages_jeu]\nfichier = "AppData/Local/Jeu/Config/Engine.ini"\ncreer = true\nvaleurs = { "k" = "v" }\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "creer sans section : code 1, rien cree" "1 " "$(sh "$R/tests/reglages_jeu.sh" 999 >/dev/null; echo $?) $(ls "$U/AppData/Local/Jeu/Config/" | grep Engine)"
printf '[[machine]]\nsi = "coeurs_gpu >= 1"\n[[machine.reglages_jeu]]\nfichier = "AppData/Local/Jeu/Config/Engine.ini"\nsection = "SystemSettings"\ncreer = true\n[machine.reglages_jeu.valeurs]\n"k" = "v"\n' >"$CIDRE_PROFILS_BASE/999.toml"
verif "creer : garde a la fusion d un bloc [[machine]]" "true" "$(sh "$R/tests/fiche_profil.sh" reglages 999 | awk -F'\t' '$2 == "creer" { print $3 }')"
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
# une propriete absente (Unreal n ecrit pas une valeur par defaut : Expedition 33
# en Bas) : avec `section`, ajoutee a la fin de la structure, taille corrigee
gvas_struct() { # <nom> <contenu deja ecrit dans le fichier $1.contenu> : une StructProperty 5.4 (type SF_X de /Script/Jeu)
   t=$(wc -c <"$2" | tr -d ' ')
   printf "\\$(printf '%03o' $((${#1} + 1)))\\0\\0\\0%s\\0\\017\\0\\0\\0StructProperty\\0\\001\\0\\0\\0\\005\\0\\0\\0SF_X\\0\\001\\0\\0\\0\\014\\0\\0\\0/Script/Jeu\\0\\0\\0\\0\\0\\$(printf '%03o' $((t % 256)))\\$(printf '%03o' $((t / 256)))\\0\\0\\0" "$1"
   cat "$2"
}
{ printf '\006\0\0\0Autre\0'; printf '\005\0\0\0None\0'; } >"$T/autre.contenu"
{ gvas_prop ShadowQuality 2; printf '\005\0\0\0None\0'; } >"$T/moteur.contenu"
{ printf 'GVAS\003\0\0\0entete'; gvas_struct Autre "$T/autre.contenu"; gvas_struct Moteur "$T/moteur.contenu"; printf '\005\0\0\0None\0\0\0\0\0'; } >"$SG/111/Reglages.sav"
rm -f "$SG/111/Reglages.sav.avant-cidre" "$SG/222/Reglages.sav"
taille_avant=$(wc -c <"$SG/111/Reglages.sav" | tr -d ' ')
cat >"$CIDRE_PROFILS_BASE/999.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu/Saved/SaveGames/*/Reglages.sav"
format = "gvas"
section = "Moteur"
[reglages_jeu.valeurs]
"ShadowQuality" = "1"
"OverallScalabilityLevel" = "1"
"TextureQuality" = "300"
FICHE
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "gvas + section : code 0, deux ajoutees, une remplacee" "0 1 1" "$rc $(printf '%s\n' "$sortie" | grep -c 'ajoutees a Moteur.*: OverallScalabilityLevel TextureQuality$') $(gvas_lire "$SG/111/Reglages.sav" ShadowQuality)"
verif "gvas + section : valeurs relues (300 = 44 + 256)" "1 44" "$(gvas_lire "$SG/111/Reglages.sav" OverallScalabilityLevel) $(gvas_lire "$SG/111/Reglages.sav" TextureQuality)"
verif "gvas + section : taille = avant + 57 + 48 (deux en-tetes)" "$((taille_avant + 105))" "$(wc -c <"$SG/111/Reglages.sav" | tr -d ' ')"
hexs=$(od -An -v -tx1 "$SG/111/Reglages.sav" | tr -d ' \n')
verif "gvas + section : taille de la structure corrigee (56 -> 161)" "a1000000" "$(printf '%s' "$hexs" | awk -v m="$(printf '/Script/Jeu' | od -An -v -tx1 | tr -d ' \n')0000000000" '{ n = 0; d = 1; while ((i = index(substr($0, d), m)) > 0) { p = d + i - 1; n++; d = p + 1 } print substr($0, p + length(m), 8) }')"
verif "gvas + section : la structure finit par None, le fichier aussi" "1 1" "$(printf '%s' "$hexs" | grep -c '2c010000050000004e6f6e650005000000') $(printf '%s' "$hexs" | grep -c '050000004e6f6e650000000000$')"
verif "gvas + section : l autre structure intacte" "1" "$(printf '%s' "$hexs" | grep -c '06000000417574726500050000004e6f6e6500')"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "gvas + section : relance = deja en place, rien d ajoute" "0 1 0" "$rc $(printf '%s\n' "$sortie" | grep -c 'deja en place') $(printf '%s\n' "$sortie" | grep -c ajoutees)"
sed -i '' 's/^section = "Moteur"/section = "Absente"/' "$CIDRE_PROFILS_BASE/999.toml"
cp "$SG/111/Reglages.sav.avant-cidre" "$SG/111/Reglages.sav"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999); rc=$?
verif "gvas + section introuvable : laissees, dit, code 0" "0 1 1" "$rc $(printf '%s\n' "$sortie" | grep -c 'pas ajoutees (Absente : structure trouvee 0 fois)') $(gvas_lire "$SG/111/Reglages.sav" ShadowQuality)"
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

# une sauvegarde Unreal 4 ou chaque reglage est une entree « Graphics_X » suivie
# d un champ « Value » (Sherlock Holmes Chapter One) : cle « Parent.Champ »
gvas4_entree() { # <parent> <entier 0-255> : la chaine Parent, puis IntProperty Value (en-tete Unreal 4)
   printf "\\$(printf '%03o' $((${#1} + 1)))\\0\\0\\0%s\\0\\006\\0\\0\\0Value\\0\\014\\0\\0\\0IntProperty\\0\\004\\0\\0\\0\\0\\0\\0\\0\\0\\$(printf '%03o' "$2")\\0\\0\\0" "$1"
}
gvas4_lire() { # <fichier> <parent> : les valeurs (octet de poids faible) du champ Value qui suit Parent
   od -An -v -tx1 "$1" | tr -d ' \n' | awk -v m="$(printf '%s' "$2" | od -An -v -tx1 | tr -d ' \n')000600000056616c7565000c000000496e7450726f7065727479000400000000000000" '
      { d = 1; while ((i = index(substr($0, d), m)) > 0) { p = d + i - 1; printf "%d ", ("0x" substr($0, p + length(m) + 2, 2)) + 0; d = p + 1 } }' | sed 's/ $//'
}
SG4="$U/AppData/Local/Jeu4/Saved/SaveGames"; mkdir -p "$SG4"
{ printf 'GVAS\002\0\0\0entete'; gvas4_entree Graphics_VerticalSync 1; gvas4_entree Graphics_ResolutionQuality 100; printf 'None'; gvas4_entree Graphics_Double 5; gvas4_entree Graphics_Double 6; printf 'fin'; } >"$SG4/Settings.sav"
cp "$SG4/Settings.sav" "$T/sav4-origine"
verif "gvas UE4 : la sauvegarde factice se relit" "1 100 5 6" "$(gvas4_lire "$SG4/Settings.sav" Graphics_VerticalSync) $(gvas4_lire "$SG4/Settings.sav" Graphics_ResolutionQuality) $(gvas4_lire "$SG4/Settings.sav" Graphics_Double)"
cat >"$CIDRE_PROFILS_BASE/993.toml" <<'FICHE'
[reglages_jeu]
fichier = "AppData/Local/Jeu4/Saved/SaveGames/Settings.sav"
format = "gvas"
[reglages_jeu.valeurs]
"Graphics_VerticalSync.Value" = "0"
"Graphics_Double.Value" = "7"
"Graphics_Absent.Value" = "1"
"Value" = "9"
FICHE
sortie=$(sh "$R/tests/reglages_jeu.sh" 993); rc=$?
verif "gvas UE4 : code 0, poses" "0 1" "$rc $(printf '%s\n' "$sortie" | grep -c poses)"
verif "gvas UE4 : Parent.Champ pose, voisin intact" "0 100" "$(gvas4_lire "$SG4/Settings.sav" Graphics_VerticalSync) $(gvas4_lire "$SG4/Settings.sav" Graphics_ResolutionQuality)"
verif "gvas UE4 : 1 octet change, taille inchangee" "1 $(wc -c <"$T/sav4-origine" | tr -d ' ')" "$(cmp -l "$SG4/Settings.sav" "$T/sav4-origine" | wc -l | tr -d ' ') $(wc -c <"$SG4/Settings.sav" | tr -d ' ')"
verif "gvas UE4 : parent en double laisse, dit" "5 6 1" "$(gvas4_lire "$SG4/Settings.sav" Graphics_Double) $(printf '%s\n' "$sortie" | grep -c 'Graphics_Double.Value trouvee 2 fois')"
verif "gvas UE4 : parent absent laisse, dit (pas d ajout)" "1" "$(printf '%s\n' "$sortie" | grep -c 'Graphics_Absent.Value trouvee 0 fois')"
verif "gvas UE4 : « Value » seul, ambigu, laisse" "1" "$(printf '%s\n' "$sortie" | grep -c 'entiere Value trouvee 4 fois')"
sortie=$(sh "$R/tests/reglages_jeu.sh" 993); rc=$?
verif "gvas UE4 : relance = deja en place" "0 1" "$rc $(printf '%s\n' "$sortie" | grep -c 'deja en place')"

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
# le temoin par voie graphique : garde a la sortie, remis avant une partie dans la meme voie
sh "$R/tests/reglages_jeu.sh" 999 temoin-change CarteB dxmt >/dev/null
verif "voie : temoin garde a la sortie (dxmt)" "CarteB" "$(valeur 999 reglages_jeu_temoin_dxmt)"
sed -i '' 's/ProfilMateriel=CarteB/ProfilMateriel=CarteD3D12/' "$INI"
sh "$R/tests/reglages_jeu.sh" 999 temoin-change CarteB d3d12 >/dev/null
verif "voie : une partie D3D12 garde sa propre valeur, sans toucher a dxmt" "CarteD3D12 CarteB" "$(valeur 999 reglages_jeu_temoin_d3d12) $(valeur 999 reglages_jeu_temoin_dxmt)"
sortie=$(sh "$R/tests/reglages_jeu.sh" 999 temoin-remettre dxmt)
verif "voie : remis avant une partie DXMT, dit au journal" "CarteD3D12 -> CarteB ProfilMateriel=CarteB" "$(printf '%s' "$sortie" | grep -o 'CarteD3D12 -> CarteB') $(tr -d '\r' <"$INI" | grep '^ProfilMateriel=')"
verif "voie : CRLF et autres lignes gardes" "6 6 Autre=1" "$(wc -l <"$INI" | tr -d ' ') $(grep -c "$(printf '\r')\$" "$INI") $(tr -d '\r' <"$INI" | grep '^Autre=')"
verif "voie : deja la valeur -> rien dit" "" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-remettre dxmt)"
verif "voie inconnue (jamais jouee) : rien" "" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-remettre dxvk)$(tr -d '\r' <"$INI" | grep -c '^ProfilMateriel=CarteB$' | sed 's/^1$//')"
verif "voie : nom de voie douteux refuse" "" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin-remettre '../x')"
rm -f "$INI"
verif "temoin : fichier absent -> vide, pas d erreur" " 0" "$(sh "$R/tests/reglages_jeu.sh" 999 temoin) $?"

echo "== 5. mise a jour du cache (file://) et hors reseau"
rm -rf "$CIDRE_PROFILS_BASE"; mkdir -p "$CIDRE_PROFILS_BASE"
printf '[cidre]\ntso = false\n' >"$CIDRE_PROFILS_BASE/424242.toml"   # une fiche qui n'est plus dans l'index
sortie=$(CIDRE_PROFILS_URL="file://$R/profils/" sh "$R/tests/fiche_profil.sh" maj json); rc=$?
verif "maj : code 0" "0" "$rc"
# toutes les fiches, Steam ou non (bnet-osi) : le nom que l'archive publiee retient
n=$(ls "$R/profils" | grep -E '^[A-Za-z0-9_-]+\.toml$' | grep -vc '^index\.toml$')
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

echo "== 5b. archive de la base, fiche provisoire"
FP="$R/tests/fiche_profil.sh"
mkdir -p "$T/arch"
( cd "$R/profils" && ls | grep -E '^[A-Za-z0-9_-]+\.toml$' | COPYFILE_DISABLE=1 tar -czf "$T/arch/base.tar.gz" -T - )   # comme .github/workflows/profils.yml
rm -rf "$CIDRE_PROFILS_BASE"
sortie=$(CIDRE_PROFILS_ARCHIVE="file://$T/arch/base.tar.gz" sh "$FP" maj json); rc=$?
verif "archive : code 0" "0" "$rc"
verif "archive : mode et total" "\"mode\":\"archive\",\"fiches\":$n,\"gardees\":0,\"total\":$n" "$(printf '%s' "$sortie" | grep -o '"mode":"archive","fiches":[0-9]*,"gardees":[0-9]*,"total":[0-9]*')"
verif "archive : index en cache" "" "$(cmp "$CIDRE_PROFILS_BASE/index.toml" "$R/profils/index.toml" 2>&1)"
verif "archive : fiche en cache identique" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"
verif "archive : horodatage pose" "20" "$(cut -c1-2 "$CIDRE_PROFILS_BASE/horodatage")"
verif "archive : pas de dossier de travail laisse" "" "$(ls "$(dirname "$CIDRE_PROFILS_BASE")" | grep -e '\.nouveau\.' -e '\.ancien\.')"
sortie=$(CIDRE_PROFILS_ARCHIVE="file://$T/arch/base.tar.gz" sh "$FP" maj json)
verif "json : origine d'une fiche du cache, puis de la copie livree" '"origine":"cache" "origine":"livree"' "$(sh "$FP" json 1903340 | grep -o '"origine":"[a-z]*"') $(CIDRE_PROFILS_BASE="$T/vide" sh "$FP" json 1903340 | grep -o '"origine":"[a-z]*"')"
verif "archive : seconde maj, rien de change" "\"fiches\":0,\"gardees\":$n" "$(printf '%s' "$sortie" | grep -o '"fiches":[0-9]*,"gardees":[0-9]*')"
# une archive douteuse est refusee : on passe aux fiches une a une (ici, la copie du depot)
mkdir -p "$T/douteuse/sous" && cp "$R/profils/index.toml" "$T/douteuse/" && cp "$R/profils/1903340.toml" "$T/douteuse/sous/"
( cd "$T/douteuse" && tar -czf "$T/arch/douteuse.tar.gz" index.toml sous/1903340.toml )
printf '[cidre]\ntso = false\n' >"$CIDRE_PROFILS_BASE/1903340.toml"
# (un petit depot d une fiche, pour ne pas reprendre toute la base une a une)
mkdir -p "$T/petit" && cp "$R/profils/1903340.toml" "$T/petit/" && sh "$FP" generer-index "$T/petit" >"$T/petit/index.toml"
sortie=$(CIDRE_PROFILS_ARCHIVE="file://$T/arch/douteuse.tar.gz" CIDRE_PROFILS_URL="file://$T/petit/" sh "$FP" maj json 2>"$T/err"); rc=$?
verif "archive a sous-dossier : refusee, fiches une a une (code 0)" "0 1" "$rc $(grep -c 'archive refusee' "$T/err")"
verif "archive a sous-dossier : la fiche changee est reprise" "" "$(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"
( cd "$R/profils" && tar -czf "$T/arch/incomplete.tar.gz" index.toml 1903340.toml )
sortie=$(CIDRE_PROFILS_ARCHIVE="file://$T/arch/incomplete.tar.gz" CIDRE_PROFILS_URL="file://$T/nulle-part/" sh "$FP" maj json 2>"$T/err"); rc=$?
verif "archive sans les fiches de son index : refusee, cache intact" "1 1 " "$rc $(grep -c 'archive incomplete' "$T/err") $(cmp "$CIDRE_PROFILS_BASE/1903340.toml" "$R/profils/1903340.toml" 2>&1)"
# fiche provisoire : un jeu installe sans fiche
mkdir -p "$T/pdb"
printf '{\n  "bestReportedTier": "platinum",\n  "confidence": "good",\n  "score": 0.666,\n  "tier": "gold",\n  "total": 42,\n  "trendingTier": "silver"\n}\n' >"$T/pdb/777001.json"
printf '{"response":{"store_items":[{"item_type":0,"id":777001,"success":1,"visible":true,"name":"Jeu \\"Essai\\" \\u2122 \\\\ fin","appid":777001,"type":0,"platforms":{"windows":true,"vr_support":{},"steam_deck_compat_category":3},"best_purchase_option":{"purchase_option_name":"Autre nom"}}]}}' >"$T/magasin.json"
prov() { CIDRE_PROTONDB_URL="file://$T/pdb/" CIDRE_STEAM_MAGASIN_URL="file://$T/magasin.json" sh "$FP" provisoire "$@"; }
verif "provisoire : ecrite" "$CIDRE_PROFILS_PROVISOIRES/777001.toml" "$(prov 777001)"
verif "provisoire : chemin" "$CIDRE_PROFILS_PROVISOIRES/777001.toml" "$(sh "$FP" chemin 777001)"
j=$(sh "$FP" json 777001)
verif "provisoire : json jeu" '"jeu":{"appid":777001,"nom":"Jeu \"Essai\"  \\ fin","plateformes_steam":"windows","provisoire":true}' "$(printf '%s' "$j" | grep -o '"jeu":{[^}]*}')"
verif "provisoire : json protondb" '"protondb":{"palier":"gold","tendance":"silver","meilleur_palier":"platinum","confiance":"good","rapports":42,"score":67,"source":"protondb"' "$(printf '%s' "$j" | grep -o '"protondb":{[^}]*"source":"protondb"')"
verif "provisoire : json origine, compat non teste" '"etat":"non-teste" "origine":"provisoire"' "$(printf '%s' "$j" | grep -o '"etat":"non-teste"' | head -1) $(printf '%s' "$j" | grep -o '"origine":"[a-z]*"')"
verif "provisoire : TOML relu par l'analyseur" "gold" "$(sh "$FP" toml "$CIDRE_PROFILS_PROVISOIRES/777001.toml" | awk -F'\t' '$1 == "compat.protondb" && $2 == "palier" { print $4 }')"
verif "provisoire : plat (options) sans surprise" 'etat = "non-teste"' "$(sh "$FP" plat 777001)"
verif "provisoire : jeu deja dans la base, rien d ecrit" "0 " "$(prov 1903340 >/dev/null; echo $?) $(ls "$CIDRE_PROFILS_PROVISOIRES" | grep 1903340)"
verif "provisoire : jeu inconnu de ProtonDB, code 3, rien d ecrit" "3 " "$(prov 777002 2>/dev/null; echo $?) $(ls "$CIDRE_PROFILS_PROVISOIRES" | grep 777002)"
verif "provisoire : magasin muet, fiche quand meme (sans nom)" "0 " "$(CIDRE_PROTONDB_URL="file://$T/pdb/" CIDRE_STEAM_MAGASIN_URL="file://$T/nulle-part.json" sh "$FP" provisoire 777003 >/dev/null 2>&1; cp "$T/pdb/777001.json" "$T/pdb/777003.json"; CIDRE_PROTONDB_URL="file://$T/pdb/" CIDRE_STEAM_MAGASIN_URL="file://$T/nulle-part.json" sh "$FP" provisoire 777003 >/dev/null; echo $?) $(sh "$FP" json 777003 | grep -o '"nom":"[^"]*"')"
verif "provisoire : appid douteux refuse" "2" "$(prov '../x' 2>/dev/null; echo $?)"
cp "$R/profils/1903340.toml" "$CIDRE_PROFILS_PROVISOIRES/1903340.toml"
CIDRE_PROFILS_ARCHIVE="file://$T/arch/base.tar.gz" sh "$FP" maj >/dev/null
verif "archive : une provisoire que la base couvre s'en va, les autres restent" "777001.toml 777003.toml" "$(ls "$CIDRE_PROFILS_PROVISOIRES" | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$CIDRE_PROFILS_PROVISOIRES"

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
verif "1903340 M4 : compat = M2 et suivants en DXMT" "argent M2 et suivants dxmt 40" "$(CIDRE_MACHINE="$IMAC_M4" sh "$FP" compat 1903340 | awk -F'\t' '$1 == "etat" || $1 == "pour" || $1 == "voie" || $1 == "fps_jeu" { v[$1] = $2 } END { print v["etat"], v["pour"], v["voie"], v["fps_jeu"] }')"
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
# exe_sans_anticheat : le bloc du lanceur joue sur un faux ELDEN RING (chemin a
# espaces) ; l'exe de Steam remplace par celui de la fiche, aucun fichier touche
verif "fiche 1245620 : exe_sans_anticheat" "eldenring.exe" "$(valeur 1245620 exe_sans_anticheat)"
N=$T/sans-ac; JD="$N/Jeux Cidre/ELDEN RING/Game"; mkdir -p "$JD"
printf 'MZ' >"$JD/start_protected_game.exe"; printf 'MZ' >"$JD/eldenring.exe"
awk '/^# --- exe sans anticheat : debut ---$/ { p = 1 } p { print } /^# --- exe sans anticheat : fin ---$/ { p = 0 }' "$R/tests/lancer_depuis_steam.sh" >"$N/bloc.sh"
cat >"$N/jouer.sh" <<'EOS'
set -e
R=$1; DOSSIER=$2; PROG=start_protected_game.exe; JOURNAL=$R/journal; PROFIL=$3
profil() { printf '%s\n' "$PROFIL" | sed -n "s/^$1=//p" | head -1; }
opt() { eval "v=\${$2:-}"; case $v in 1) echo true; return ;; 0) echo false; return ;; '') ;; *) echo "$v"; return ;; esac; profil "$1"; }
. "$R/bloc.sh"
echo "$PROG"
EOS
avant=$(ls -l "$JD" | md5 -q 2>/dev/null || ls -l "$JD" | md5sum)
verif "exe_sans_anticheat : pose -> exe remplace" "eldenring.exe" "$(sh "$N/jouer.sh" "$N" "$JD" 'exe_sans_anticheat=eldenring.exe')"
verif "exe_sans_anticheat : remplacement note au journal" "1" "$(grep -c 'sans anticheat : start_protected_game.exe remplace par eldenring.exe' "$N/journal")"
verif "exe_sans_anticheat : absent -> inchange" "start_protected_game.exe" "$(sh "$N/jouer.sh" "$N" "$JD" 'eac_untrusted=false')"
verif "exe_sans_anticheat : CIDRE_EXE_SANS_ANTICHEAT=0 coupe la fiche" "start_protected_game.exe" "$(CIDRE_EXE_SANS_ANTICHEAT=0 sh "$N/jouer.sh" "$N" "$JD" 'exe_sans_anticheat=eldenring.exe')"
verif "exe_sans_anticheat : CIDRE_EXE_SANS_ANTICHEAT nomme l'exe" "eldenring.exe" "$(CIDRE_EXE_SANS_ANTICHEAT=eldenring.exe sh "$N/jouer.sh" "$N" "$JD" '')"
verif "exe_sans_anticheat : exe introuvable -> inchange, note" "start_protected_game.exe 1" "$(sh "$N/jouer.sh" "$N" "$JD" 'exe_sans_anticheat=absent.exe') $(grep -c 'absent.exe introuvable' "$N/journal")"
verif "exe_sans_anticheat : chemin refuse" "start_protected_game.exe" "$(sh "$N/jouer.sh" "$N" "$JD" 'exe_sans_anticheat=../eldenring.exe')"
verif "exe_sans_anticheat : fichiers du jeu intacts" "$avant" "$(ls -l "$JD" | md5 -q 2>/dev/null || ls -l "$JD" | md5sum)"
# knowndlls : fiche de D2R, validation, et pose dans une ruche factice au format
# de Wine (KnownDLLs de wine.inf) : ajout, idempotence, retrait des seules
# valeurs de Cidre, prefixe occupe
verif "fiche bnet-osi : dx12" "true" "$(valeur bnet-osi dx12)"
verif "fiche bnet-osi : knowndlls" "d3d12 d3d12core" "$(valeur bnet-osi knowndlls)"
verif "knowndlls valider : forme canonique" "d3d12 d3d12core" "$(sh "$R/tests/knowndlls.sh" valider 'D3D12.dll,d3d12core d3d12')"
verif "knowndlls valider : chemin refuse" "1" "$(sh "$R/tests/knowndlls.sh" valider '../d3d12' 2>/dev/null; echo $?)"
K=$T/pfx-knowndlls; mkdir -p "$K"
cat >"$K/system.reg" <<'EOR'
WINE REGISTRY Version 2
;; All keys relative to \\Machine

[System\\ControlSet001\\Control\\Session Manager\\KnownDLLs] 1790333337
#time=1dd4cdb776491c2
"_xtajit"="xtajit.dll"
"gdi32"="gdi32.dll"
"kernel32"="kernel32.dll"

[System\\ControlSet001\\Control\\Session Manager\\Memory Management] 1790333337
"PagingFiles"="pagefile.sys"
EOR
cp "$K/system.reg" "$T/knowndlls-origine"
kd() { WINEPREFIX=$K CIDRE_SERVEUR_WINE=non sh "$R/tests/knowndlls.sh" poser "$@" >/dev/null 2>&1; echo $?; }
kv() { awk '/^\[/ { d = index($0, "KnownDLLs]") > 0; next } d && /^"/ { printf "%s ", $0 }' "$K/system.reg"; }
verif "knowndlls : pose d3d12 d3d12core" "0 \"_xtajit\"=\"xtajit.dll\" \"gdi32\"=\"gdi32.dll\" \"kernel32\"=\"kernel32.dll\" \"d3d12\"=\"d3d12.dll\" \"d3d12core\"=\"d3d12core.dll\" " "$(kd 'd3d12 d3d12core') $(kv)"
verif "knowndlls : marque de Cidre" "d3d12 d3d12core" "$(paste -sd ' ' - <"$K/.cidre-knowndlls")"
cp "$K/system.reg" "$T/knowndlls-pose"
verif "knowndlls : relance = ruche inchangee" "0 " "$(kd 'd3d12 d3d12core') $(cmp "$K/system.reg" "$T/knowndlls-pose" 2>&1)"
verif "knowndlls : une valeur de Wine demandee n'est pas prise pour celle de Cidre" "0 d3d12" "$(kd 'd3d12 gdi32') $(paste -sd ' ' - <"$K/.cidre-knowndlls")"
cp "$K/system.reg" "$T/knowndlls-occupe"
verif "knowndlls : prefixe tenu par un wineserver -> code 3, ruche pas touchee" "3 " "$(WINEPREFIX=$K CIDRE_SERVEUR_WINE=oui sh "$R/tests/knowndlls.sh" poser >/dev/null 2>&1; echo $?) $(cmp "$K/system.reg" "$T/knowndlls-occupe" 2>&1)"
verif "knowndlls : jeu sans l'option -> celles de Cidre retirees, celles de Wine gardees" "0 \"_xtajit\"=\"xtajit.dll\" \"gdi32\"=\"gdi32.dll\" \"kernel32\"=\"kernel32.dll\"  absente" "$(kd) $(kv) $([ -f "$K/.cidre-knowndlls" ] && echo presente || echo absente)"
verif "knowndlls : ruche revenue a l'origine (hors horodatage)" "" "$(grep -v '^#time' "$K/system.reg" | diff - "$T/knowndlls-origine" | grep -v '#time' | grep '^[<>]')"
verif "knowndlls : prefixe absent -> code 3" "3" "$(WINEPREFIX=$T/pas-de-prefixe sh "$R/tests/knowndlls.sh" poser d3d12 >/dev/null 2>&1; echo $?)"
grep -q 'KDLL=$(opt knowndlls CIDRE_KNOWNDLLS)' "$R/tests/lancer_depuis_steam.sh" && ok "lanceur : option knowndlls lue" || echec "lanceur : option knowndlls non lue"
verif "knowndlls.sh est livre avec le runtime" "1" "$(grep -c ' knowndlls\.sh ' "$R/tests/empaqueter_runtime.sh")"
# posee avant le premier processus Wine du lancement (le client de service), comme la version de Windows
kl=$(grep -n 'knowndlls.sh" poser' "$R/tests/lancer_depuis_steam.sh" | head -1 | cut -d: -f1)
kw=$(grep -n "etape2_pile_arm64ec.sh\" 'c:.faux_steam.exe'" "$R/tests/lancer_depuis_steam.sh" | head -1 | cut -d: -f1)
[ -n "$kl" ] && [ -n "$kw" ] && [ "$kl" -lt "$kw" ] && ok "lanceur : knowndlls posees avant le premier processus Wine" || echec "lanceur : knowndlls.sh ($kl) doit preceder le client de service ($kw)"
cp "$CIDRE_PROFILS" "$T/perso.avant-knowndlls" 2>/dev/null || : >"$T/perso.avant-knowndlls"
sh "$R/cidre" set defaut knowndlls 'D3D12 d3d12core.dll' >/dev/null 2>&1
verif "cidre set knowndlls : forme canonique ecrite" "d3d12 d3d12core" "$(valeur 1245620 knowndlls)"
sh "$R/cidre" set defaut knowndlls '../x' >/dev/null 2>&1; rc=$?
verif "cidre set knowndlls : chemin refuse" "2" "$rc"
cp "$T/perso.avant-knowndlls" "$CIDRE_PROFILS"
# d3d9 : dxvk ou wined3d, rien d'autre ; le lanceur la lit et pose le =n/=b
cp "$CIDRE_PROFILS" "$T/perso.avant-d3d9"
sh "$R/cidre" set defaut d3d9 wined3d >/dev/null 2>&1
verif "cidre set defaut d3d9 wined3d" "wined3d" "$(valeur 998 d3d9)"
sh "$R/cidre" set defaut d3d9 opengl >/dev/null 2>&1; rc=$?
verif "cidre set d3d9 : valeur inconnue refusee" "2" "$rc"
cp "$T/perso.avant-d3d9" "$CIDRE_PROFILS"
grep -q 'D3D9=$(opt d3d9 CIDRE_D3D9)' "$R/tests/lancer_depuis_steam.sh" && grep -q 'D3D9_OV="d3d9=n"' "$R/tests/lancer_depuis_steam.sh" \
   && ok "lanceur : option d3d9 lue" || echec "lanceur : option d3d9 non lue"
# sortie_normale : un code que la fiche dit normal, apres assez de jeu, n'est
# pas une erreur (Fahrenheit sort sur 1 a chaque fermeture, 2026-10-19)
SN="$R/tests/sortie_normale.sh"
verif "fiche 312840 : sortie_normale = 1" "1" "$(valeur 312840 sortie_normale)"
sh "$SN" 1 600 '"1"' >/dev/null; verif "sortie_normale : code 1 apres 600 s = normal" "0" "$?"
verif "sortie_normale : la ligne du journal" "    le jeu s'est ferme sur le code 1 apres 600 s : fin normale pour ce jeu (fiche : sortie_normale = \"1\", des 60 s de jeu)" "$(sh "$SN" 1 600 '"1"')"
sh "$SN" 1 20 '"1"' >/dev/null; verif "sortie_normale : code 1 apres 20 s = erreur (plantage au demarrage)" "1" "$?"
sh "$SN" 1 20 '"1"' 10 >/dev/null; verif "sortie_normale : sortie_normale_apres = 10" "0" "$?"
sh "$SN" 3221225477 600 '"1"' >/dev/null; verif "sortie_normale : autre code = erreur" "1" "$?"
sh "$SN" 7 600 '"1 7"' >/dev/null; verif "sortie_normale : liste de codes" "0" "$?"
sh "$SN" 1 600 '' >/dev/null; verif "sortie_normale : sans option = erreur" "1" "$?"
verif "sortie_normale : sans option, rien d'ecrit" "" "$(sh "$SN" 1 600 '')"
verif "sortie_normale : jeu sans option (998)" "" "$(valeur 998 sortie_normale)"
grep -q 'NORMALE=$(sh "$R/tests/sortie_normale.sh" "$RC" "$(( $(date +%s) - DEBUT_EPOCH ))" "$(opt sortie_normale CIDRE_SORTIE_NORMALE)" "$(profil sortie_normale_apres)"' "$R/tests/lancer_depuis_steam.sh" \
   && ok "lanceur : option sortie_normale lue" || echec "lanceur : option sortie_normale non lue"
grep -q 'sortie_normale.sh' "$R/tests/empaqueter_runtime.sh" && ok "runtime : sortie_normale.sh livre" || echec "runtime : sortie_normale.sh non livre"

# dlss : metalfx ou non ; "non" livre par defaut ; la fiche le porte ; le lanceur
# pose les extensions NVIDIA de DXMT et DXMT_ENABLE_NVEXT seulement avec metalfx
verif "dlss : non par defaut" "non" "$(valeur 998 dlss)"
printf '[jeu]\nappid = 996\n[cidre]\ndlss = "metalfx"\n' >"$CIDRE_PROFILS_BASE/996.toml"
verif "dlss : lu dans la fiche" "metalfx" "$(valeur 996 dlss)"
rm -f "$CIDRE_PROFILS_BASE/996.toml"
cp "$CIDRE_PROFILS" "$T/perso.avant-dlss"
sh "$R/cidre" set defaut dlss metalfx >/dev/null 2>&1
verif "cidre set defaut dlss metalfx" "metalfx" "$(valeur 998 dlss)"
sh "$R/cidre" set defaut dlss fsr >/dev/null 2>&1; rc=$?
verif "cidre set dlss : valeur inconnue refusee" "2" "$rc"
cp "$T/perso.avant-dlss" "$CIDRE_PROFILS"
grep -q 'DLSS=$(opt dlss CIDRE_DLSS)' "$R/tests/lancer_depuis_steam.sh" && grep -q 'export DXMT_ENABLE_NVEXT=1' "$R/tests/lancer_depuis_steam.sh" \
   && grep -q 'NVEXT_OV="nvapi64,nvngx=b"' "$R/tests/lancer_depuis_steam.sh" \
   && ok "lanceur : option dlss lue (NVEXT, nvapi64/nvngx en builtin)" || echec "lanceur : option dlss non lue"
verif "generation_images : non par defaut" "non" "$(valeur 998 generation_images)"
cp "$CIDRE_PROFILS" "$T/perso.avant-fg"
sh "$R/cidre" set defaut generation_images metalfx >/dev/null 2>&1
verif "cidre set defaut generation_images metalfx" "metalfx" "$(valeur 998 generation_images)"
sh "$R/cidre" set defaut generation_images oui >/dev/null 2>&1; rc=$?
verif "cidre set generation_images : valeur inconnue refusee" "2" "$rc"
cp "$T/perso.avant-fg" "$CIDRE_PROFILS"
grep -q 'opt generation_images CIDRE_GENERATION_IMAGES)" = metalfx' "$R/tests/lancer_depuis_steam.sh" && ! grep -q 'export CIDRE_DXMT_FG=1' "$R/tests/lancer_depuis_steam.sh" \
   && ok "lanceur : generation_images lue et refusee (jamais CIDRE_DXMT_FG=1)" || echec "lanceur : generation_images encore activable"
# le bloc DLSS du lanceur, joue a part sur un faux jeu dont le chemin a des espaces
# (« SSK SSD » : le 2026-10-18 un chemin decoupe faisait mourir le lanceur avant Wine)
N=$T/nvext; JD="$N/Jeux Cidre/1903340"; mkdir -p "$JD/Sandfall/Binaries/Win64" "$JD/Sandfall/Plugins/NVIDIA/DLSS" "$N/dxmt/nvext" "$N/windll" "$N/sys32" "$N/tests"
cp "$R/tests/machine.sh" "$N/tests/machine.sh"
printf 'MZ' >"$JD/Sandfall/Binaries/Win64/SandFall-Win64-Shipping.exe"; printf 'MZ' >"$JD/Expedition33_Steam.exe"
printf 'signe' >"$JD/Sandfall/Plugins/NVIDIA/DLSS/nvngx_dlss.dll"
printf 'nvapi' >"$N/dxmt/nvext/nvapi64.dll"; printf 'nvngx' >"$N/dxmt/nvext/nvngx.dll"
awk '/^DLSS=\$\(opt dlss CIDRE_DLSS\)$/ { p = 1 } /^# Rendu Direct3D 9/ { p = 0 } p' "$R/tests/lancer_depuis_steam.sh" >"$N/bloc.sh"
cat >"$N/jouer.sh" <<'EOS'
set -e
R=$1; DOSSIER=$2; PROG=Expedition33_Steam.exe; D3D11=dxmt; JOURNAL=$R/journal
WINDLL=$R/windll; SYS32=$R/sys32; CIDRE_DXMT_DIR=$R/dxmt; mkdir -p "$R/wine"
opt() { eval "v=\${$2:-}"; echo "$v"; }
est_pe32() { return 1; }
poser() { cmp -s "$1" "$2" && return 0; cp -p "$1" "$2.cidre-tmp" && mv -f "$2.cidre-tmp" "$2"; }
. "$R/bloc.sh"
echo "fg ${CIDRE_DXMT_FG:-0}"
echo "fin ${DXMT_ENABLE_NVEXT:-0}"
EOS
# garde du 2026-10-20 : DLSS seulement si famille_gpu >= 9, sans cle de contournement
M1F="famille_gpu=7"; M2F="famille_gpu=8"; M4F="famille_gpu=9"
fin=$(CIDRE_MACHINE=$M1F CIDRE_DLSS=metalfx sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : refuse sur M1 (famille 7)" "fin 0 absent" "$fin $([ -e "$N/sys32/nvngx.dll" ] && echo pose || echo absent)"
verif "dlss : refus note au journal avec la famille" "1" "$(grep -c 'dlss : metalfx refuse sur famille_gpu 7' "$N/journal")"
fin=$(CIDRE_MACHINE=$M1F CIDRE_DLSS=metalfx CIDRE_DLSS_ESSAI=1 sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : refuse sur M1 meme avec CIDRE_DLSS_ESSAI=1" "fin 0 absent" "$fin $([ -e "$N/sys32/nvngx.dll" ] && echo pose || echo absent)"
fin=$(CIDRE_MACHINE=$M2F CIDRE_DLSS=metalfx sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : refuse sur famille 8 (non mesuree)" "fin 0" "$fin"
fin=$(CIDRE_MACHINE=famille_gpu=x CIDRE_DLSS=metalfx sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : refuse si la famille est illisible" "fin 0 1" "$fin $(grep -c 'famille_gpu illisible' "$N/journal")"
fin=$(CIDRE_MACHINE=$M4F CIDRE_DLSS=metalfx sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : accepte sur M4 (famille 9), bloc au bout sur un chemin a espaces" "fin 1" "$fin"
verif "dlss : leurre signe a cote de l'exe et en system32" "signe signe signe" "$(cat "$JD/nvngx.dll" "$JD/Sandfall/Binaries/Win64/nvngx.dll" "$N/sys32/nvngx.dll" 2>/dev/null | tr '\n' ' ' | sed 's/signe/signe /g; s/  */ /g; s/ $//')"
fin=$(CIDRE_MACHINE=$M4F sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -1)
verif "dlss : retire au lancement suivant sans dlss" "fin 0 absent absent absent" "$fin $([ -e "$JD/nvngx.dll" ] && echo la || echo absent) $([ -e "$N/sys32/nvngx.dll" ] && echo la || echo absent) $([ -e "$N/windll/nvngx.dll" ] && echo la || echo absent)"
# generation d'images : fermee partout (2026-10-20), meme sur M4 avec dlss, et un CIDRE_DXMT_FG herite est retire
sortie=$(CIDRE_MACHINE=$M4F CIDRE_DLSS=metalfx CIDRE_GENERATION_IMAGES=metalfx CIDRE_DXMT_FG=1 sh "$N/jouer.sh" "$N" "$JD" 2>&1 | tail -2 | tr '\n' ' ')
verif "generation_images : refusee sur M4 avec dlss, CIDRE_DXMT_FG herite retire, note au journal" "fg 0 fin 1 oui" "$sortie$(grep -q 'generation_images : metalfx refuse' "$N/journal" && echo oui || echo non)"
n=$(grep -l '^generation_images *= *"metalfx"' "$R"/profils/*.toml 2>/dev/null | wc -l | tr -d ' ')
verif "generation_images : aucune fiche ne l'active" "0" "$n"
grep -q 'nvngx/nvngx.dll' "$R/tests/construire_dxmt.sh" && grep -q 'enable_nvngx=true' "$R/tests/construire_dxmt.sh" \
   && ok "construire_dxmt : nvapi64/nvngx construits et poses dans dxmt/nvext" || echec "construire_dxmt : extensions NVIDIA absentes"

echo "== 6d. version macOS 32 bits seulement (traitee en jeu Windows)"
# Un faux client Steam : Fahrenheit (312840) installe en version macOS. Ses
# executables sont de faux Mach-O (l'en-tete suffit a `file`) : i386 seul, puis
# x86_64. Un faux `open` : si la garde manquait, rien ne partirait pour de vrai.
H=$T/home32; SAF="$H/Library/Application Support/Steam/steamapps"; APPF="$SAF/common/Fahrenheit/Fahrenheit.app"
mkdir -p "$APPF/Contents/MacOS" "$T/bin32"
printf '"AppState"\n{\n\t"appid"\t\t"312840"\n\t"name"\t\t"Fahrenheit: Indigo Prophecy Remastered"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Fahrenheit"\n}\n' >"$SAF/appmanifest_312840.acf"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Fahrenheit</string></dict></plist>\n' >"$APPF/Contents/Info.plist"
macho() { # <fichier> <32|64>
   if [ "$2" = 32 ]; then printf '\316\372\355\376\007\000\000\000\003\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' >"$1"
   else printf '\317\372\355\376\007\000\000\001\003\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' >"$1"; fi
}
printf '#!/bin/sh\necho "open $*" >>"%s/open.txt"\n' "$T" >"$T/bin32/open"; chmod +x "$T/bin32/open"
cidre32() { HOME=$H PATH="$T/bin32:$PATH" CIDRE_DIR="$T/cidre32" sh "$R/cidre" "$@"; }
champ_json() { sed -n "s/.*\"$1\":\\([a-z]*\\).*/\\1/p"; }
macho "$APPF/Contents/MacOS/Fahrenheit" 32
verif "binaire i386 : Mach-O 32 bits pour file" "oui" "$(file -b "$APPF/Contents/MacOS/Fahrenheit" | grep -q 'Mach-O executable i386' && echo oui)"
l=$(cidre32 list --json)
verif "list --json : mac_32bits true" "true" "$(printf '%s' "$l" | champ_json mac_32bits)"
verif "list --json : lance par Cidre, pas en natif" "cidre" "$(printf '%s' "$l" | sed -n 's/.*"lancement":"\([a-z]*\)".*/\1/p')"
verif "list --json : la plateforme installee reste macos" "macos" "$(printf '%s' "$l" | sed -n 's/.*"plateforme":"\([a-z]*\)".*/\1/p')"
verif "list : texte" "oui" "$(cidre32 list | grep -q 'Mac 32 bits : cidre dl 312840' && echo oui)"
p=$(cidre32 play 312840 --json 2>"$T/play32.err"); rc=$?
verif "play : refuse, code 9" "9" "$rc"
verif "play --json : evenement mac_32bits" "mac_32bits" "$(printf '%s' "$p" | sed -n 's/.*"code":"\([a-z_0-9]*\)".*/\1/p')"
verif "play : dit quoi faire" "oui" "$(grep -q 'cidre dl 312840' "$T/play32.err" && echo oui)"
verif "play : Steam n'est pas appele" "" "$(cat "$T/open.txt" 2>/dev/null)"
cidre32 dl 312840 macos >/dev/null 2>&1; verif "dl macos : refuse (code 9)" "9" "$?"
cidre32 install 312840 macos >/dev/null 2>&1; verif "install macos : refuse (code 9)" "9" "$?"
# le binaire installe prime sur la fiche (profils/312840.toml dit mac_32bits = true)
verif "la fiche livree de Fahrenheit dit mac_32bits" "true" "$(sh "$R/tests/fiche_profil.sh" toml "$R/profils/312840.toml" | awk -F'\t' '$1 == "jeu" && $2 == "mac_32bits" { print $4 }')"
macho "$APPF/Contents/MacOS/Fahrenheit" 64
l=$(cidre32 list --json)
verif "binaire x86_64 installe : mac_32bits false (le binaire prime)" "false" "$(printf '%s' "$l" | champ_json mac_32bits)"
verif "binaire x86_64 installe : natif" "natif" "$(printf '%s' "$l" | sed -n 's/.*"lancement":"\([a-z]*\)".*/\1/p')"
# un .app sans Mach-O (script) : on ne sait pas, la fiche tranche
printf '#!/bin/sh\n' >"$APPF/Contents/MacOS/Fahrenheit"
verif "sans Mach-O : la fiche tranche" "true" "$(cidre32 list --json | champ_json mac_32bits)"
rm -f "$APPF/Contents/MacOS/Fahrenheit"
# un jeu Windows : null
mkdir -p "$SAF/common/Fahrenheit-win"; : >"$SAF/common/Fahrenheit-win/Jeu.exe"
sed 's/"Fahrenheit"$/"Fahrenheit-win"/' "$SAF/appmanifest_312840.acf" >"$SAF/m.acf" && mv "$SAF/m.acf" "$SAF/appmanifest_312840.acf"
verif "jeu Windows : mac_32bits null" "null" "$(cidre32 list --json | sed -n 's/.*"mac_32bits":\([a-z]*\).*/\1/p')"
# le cache du client Steam (cidre-outil plateformes), quand il est la : Steam
# ne declare pas de version macOS 64 bits pour Fahrenheit, Portal 2 ; il en
# declare une pour Surviving Mars
AI="$HOME/Library/Application Support/Steam/appcache/appinfo.vdf"
if [ -x "$R/build/cidre-outil" ] && [ ! "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ] && [ -f "$AI" ] &&
   [ "$("$R/build/cidre-outil" plateformes "$AI" 312840 464920 620 | wc -l | tr -d ' ')" = 3 ]; then
   pf=$("$R/build/cidre-outil" plateformes "$AI" 312840 464920 620)
   verif "cache du client : Fahrenheit en 32 bits" "oui" "$(printf '%s\n' "$pf" | awk -F'\t' '$1 == 312840 { print $4 }')"
   verif "cache du client : Portal 2 en 32 bits" "oui" "$(printf '%s\n' "$pf" | awk -F'\t' '$1 == 620 { print $4 }')"
   verif "cache du client : Surviving Mars en 64 bits (macos64)" "non" "$(printf '%s\n' "$pf" | awk -F'\t' '$1 == 464920 { print $4 }')"
   printf 'License packageID 1:\n - Apps    : 312840, 464920, (2 in total)\n' >"$T/licences32.txt"
   b=$(HOME=$HOME "$R/build/cidre-outil" bibliotheque "$T/licences32.txt")
   verif "library : mac_32bits sur Fahrenheit seulement" "1" "$(printf '%s' "$b" | grep -o '"mac_32bits": true' | wc -l | tr -d ' ')"
   b=$(HOME=$HOME "$R/build/cidre-outil" bibliotheque --mac64 312840, --mac32 464920, "$T/licences32.txt")
   verif "library : --mac64 (fiche) leve Fahrenheit, --mac32 marque Surviving Mars" "464920" "$(printf '%s' "$b" | tr '}' '\n' | grep '"mac_32bits": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p')"
else
   echo "  (cidre-outil ou cache du client Steam absent : plateformes non verifiees)"
fi

echo "== 7. syntaxe"
for s in cidre tests/cidre_install.sh tests/profil_cidre.sh tests/fiche_profil.sh tests/reglages_jeu.sh tests/machine.sh tests/lancer_depuis_steam.sh tests/arguments_jeu.sh tests/empaqueter_runtime.sh tests/tester_profils.sh tests/prefixe_a_jour.sh tests/fin_de_partie.sh tests/sortie_normale.sh tests/knowndlls.sh; do
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
for s in cidre tests/lancer_depuis_steam.sh tests/etape2_pile_arm64ec.sh tests/prefixe_a_jour.sh tests/fin_de_partie.sh; do
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

# Fin de partie (2026-10-18) : aucun descripteur de l'appelant au-dela de 2 ne
# passe a Wine (faux_steam et le wineserver le tiendraient apres le jeu : un
# `cidre play | tail` ne finissait plus), et le lanceur arrete le client de
# service apres le jeu.
grep -q '^exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-$' "$R/tests/lancer_depuis_steam.sh" && ok "lanceur : fd 3-9 de l'appelant fermes" || echec "lanceur : fd 3-9 de l'appelant herites par Wine"
grep -q '^exec "$WINE" "$@" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-$' "$R/tests/etape2_pile_arm64ec.sh" && ok "etape2 : fd 3-9 fermes avant Wine" || echec "etape2 : fd 3-9 herites par Wine"
grep -q 'sh "$R/tests/fin_de_partie.sh"' "$R/tests/lancer_depuis_steam.sh" && ok "lanceur : client de service arrete apres le jeu" || echec "lanceur : fin_de_partie.sh non appele"
# le mecanisme lui-meme : un fils en arriere-plan qui garde le fd 3 d'un tube
# retient son lecteur ; ferme, le lecteur finit avec le script
duree_tube() { # <commande sh> : secondes d'attente du lecteur d'un tube pose en fd 3
   { sh -c "$1"; } 3>&1 >/dev/null 2>&1 | { t0=$(date +%s); cat >/dev/null; echo $(( $(date +%s) - t0 )); }
}
[ "$(duree_tube 'sleep 2 &')" -ge 1 ] && ok "fd 3 herite : le lecteur du tube attend le fils (le defaut corrige)" || echec "fd 3 herite : le lecteur n'attend pas, le test ne prouve rien"
verif "fd 3 ferme : le tube se termine avec le script, pas avec son fils" "0" "$(duree_tube 'exec 3>&-; sleep 2 &')"
# sans serveur Wine pour ce prefixe : rien a faire, tout de suite, sans bruit
mkdir -p "$T/pfx-vide"
verif "fin_de_partie : prefixe sans serveur, rien a faire" "0:" "$(WINEPREFIX=$T/pfx-vide sh "$R/tests/fin_de_partie.sh" 2>&1; echo "$?:")"

# Extensions ARM donnees a FEX (2026-10-18) : eteintes par defaut ; avec
# CIDRE_FEX_EXTENSIONS=1, seulement celles que ce Mac annonce par sysctl,
# jamais LSE (plus lent sur M1) ni AFP (non mesure).
attendu=enablecrypto
for e in FEAT_LRCPC:enablelrcpc FEAT_LRCPC2:enablelrcpc2 FEAT_FlagM2:enableflagm2; do
   [ "$(sysctl -n "hw.optional.arm.${e%%:*}" 2>/dev/null)" = 1 ] && attendu=$attendu,${e#*:}
done
verif "extensions FEX : celles du Mac (CIDRE_FEX_EXTENSIONS=1)" "$attendu" "$(CIDRE_FEX_EXTENSIONS=1 sh "$R/tests/extensions_fex.sh")"
verif "extensions FEX : par defaut, enablecrypto seul" "enablecrypto" "$(sh "$R/tests/extensions_fex.sh")"
grep -q 'FEX_HOSTFEATURES:-$(sh "$R/tests/extensions_fex.sh")' "$R/tests/etape2_pile_arm64ec.sh" && ok "etape2 : extensions FEX du Mac" || echec "etape2 : FEX_HOSTFEATURES sans extensions_fex.sh"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
