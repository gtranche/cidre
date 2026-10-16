#!/bin/sh
# Teste la langue des jeux, sans jeu, sans reseau et sans Wine :
#   1. tests/langue_cidre.sh : la langue du Mac (CIDRE_LANGUE_MAC) ou du profil
#      -> code Cidre, locale de Wine, nom Steam ; « auto » = Mac, sinon anglais ;
#   2. tests/depots_langue.awk : les depots de langue qui manquent a une
#      installation (DLC, depots d'une autre appli, sans manifeste, autre os : non) ;
#   3. `cidre dl` et la mise a jour demandent a SteamCMD la langue du jeu
#      (app_update -language) ; un jeu a jour installe dans une autre langue
#      recoit avant le lancement les depots qui lui manquent, et eux seuls ; un
#      depot que SteamCMD ne donne pas n'est pas redemande pour le meme build ;
#   4. tests/langue_jeu.sh : en « auto », la langue posee une fois par langue
#      du Mac dans le fichier du jeu (outil-steam/langues.conf), puis laissee au
#      jeu ; un code du profil, lui, est repose a chaque fois ;
#   5. le lanceur donne la locale au seul Wine (CIDRE_LOCALE, etape2), syntaxe.
# Rien n'est lu ni ecrit hors d'un dossier temporaire (HOME et CIDRE_DIR a part).
#   sh tests/tester_langue.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
C="$R/cidre"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-langue.XXXXXX")
T=$(cd "$T" && pwd -P)
F="$T/faux"
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

echo "== 1. langue_cidre.sh"
lc() { CIDRE_LANGUE_MAC=$1 sh "$R/tests/langue_cidre.sh" "$2" | sed -nE 's/^(code|locale|steam|origine)=//p' | tr '\n' ' ' | sed 's/ $//'; }
verif "Mac fr-FR, auto" "fr fr_FR.UTF-8 french mac" "$(lc fr-FR auto)"
verif "Mac fr-CA, auto : la region du Mac" "fr fr_CA.UTF-8 french mac" "$(lc fr-CA auto)"
verif "Mac en-GB" "en en_GB.UTF-8 english mac" "$(lc en-GB auto)"
verif "Mac de (sans region)" "de de_DE.UTF-8 german mac" "$(lc de auto)"
verif "Mac zh-Hans-CN" "zh zh_CN.UTF-8 schinese mac" "$(lc zh-Hans-CN auto)"
verif "Mac zh-Hant-TW" "zh zh_TW.UTF-8 tchinese mac" "$(lc zh-Hant-TW auto)"
verif "Mac pt-PT" "pt pt_PT.UTF-8 portuguese mac" "$(lc pt-PT auto)"
verif "Mac pt-BR" "pt pt_BR.UTF-8 brazilian mac" "$(lc pt-BR auto)"
verif "Mac es-419 : espagnol d'Amerique latine" "es es_MX.UTF-8 latam mac" "$(lc es-419 auto)"
verif "Mac ko-KR : koreana pour Steam" "ko ko_KR.UTF-8 koreana mac" "$(lc ko-KR auto)"
verif "Mac en langue inconnue : anglais" "en en_US.UTF-8 english mac" "$(lc xx-YY auto)"
verif "langue du Mac illisible : anglais" "en en_US.UTF-8 english mac" "$(lc '' auto)"
verif "profil de sur un Mac francais : le profil l'emporte" "de de_DE.UTF-8 german profil" "$(lc fr-FR de)"
verif "profil fr sur un Mac fr-CA : la region du Mac" "fr fr_CA.UTF-8 french profil" "$(lc fr-CA fr)"
verif "profil en sur un Mac francais" "en en_US.UTF-8 english profil" "$(lc fr-FR en)"
verif "code inconnu : comme auto" "fr fr_FR.UTF-8 french mac" "$(lc fr-FR klingon)"
verif "sans argument : auto" "fr fr_FR.UTF-8 french mac" "$(CIDRE_LANGUE_MAC=fr-FR sh "$R/tests/langue_cidre.sh" | sed -nE 's/^(code|locale|steam|origine)=//p' | tr '\n' ' ' | sed 's/ $//')"
mac=$(unset CIDRE_LANGUE_MAC; sh "$R/tests/langue_cidre.sh" auto | sed -n 's/^mac=//p')
[ -n "$mac" ] && ok "la langue de ce Mac se lit ($mac)" || echec "la langue de ce Mac ne se lit pas (defaults read -g AppleLanguages)"

echo "== 2. depots_langue.awk"
mkdir -p "$F/publie" "$F/bin" "$T/home"
# la fiche publique d'un jeu a depots de langue, telle que l'ecrit app_info_print
fiche() { # <appid> <build>
   printf 'AppID : %s, change number : 1/1, last change : Tue Oct 13 12:00:00 2026\n"%s"\n{\n\t"common"\n\t{\n\t\t"name"\t\t"Jeu %s"\n\t}\n\t"depots"\n\t{\n' "$1" "$1" "$1"
   for d in 1:: 2:french: 3:german: 4:french:dlc 5:french:autre 6:french:sans 7:french:macos; do
      n=${d%%:*}; r=${d#*:}; l=${r%%:*}; x=${r#*:}
      printf '\t\t"%s%s"\n\t\t{\n' "$1" "$n"
      if [ -n "$l" ] || [ "$x" = macos ]; then
         printf '\t\t\t"config"\n\t\t\t{\n'
         [ -z "$l" ] || printf '\t\t\t\t"language"\t\t"%s"\n' "$l"
         [ "$x" != macos ] || printf '\t\t\t\t"oslist"\t\t"macos"\n'
         printf '\t\t\t}\n'
      fi
      [ "$x" != dlc ] || printf '\t\t\t"dlcappid"\t\t"%s"\n' "${1}9"
      [ "$x" != autre ] || printf '\t\t\t"depotfromapp"\t\t"228980"\n'
      [ "$x" = sans ] || printf '\t\t\t"manifests"\n\t\t\t{\n\t\t\t\t"public"\n\t\t\t\t{\n\t\t\t\t\t"gid"\t\t"42%s"\n\t\t\t\t\t"size"\t\t"1000"\n\t\t\t\t}\n\t\t\t}\n' "$n"
      printf '\t\t}\n'
   done
   printf '\t\t"branches"\n\t\t{\n\t\t\t"public"\n\t\t\t{\n\t\t\t\t"buildid"\t\t"%s"\n\t\t\t}\n\t\t}\n\t}\n}\n' "$2"
}
# un appmanifest dont InstalledDepots porte ces depots
manifeste() { # <fichier> <appid> <build> <depots...>
   mf=$1; ma=$2; mb=$3; shift 3
   { printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Jeu %s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"1000"\n\t"buildid"\t\t"%s"\n\t"InstalledDepots"\n\t{\n' "$ma" "$ma" "$mb"
     for d in "$@"; do printf '\t\t"%s"\n\t\t{\n\t\t\t"manifest"\t\t"42"\n\t\t\t"size"\t\t"1000"\n\t\t}\n' "$d"; done
     printf '\t}\n\t"UserConfig"\n\t{\n\t}\n}\n'
   } | sed 's/$/\r/' >"$mf"   # (fins de ligne CR LF : le parseur les tolere)
}
{ fiche 9100 100; fiche 9200 100; } >"$T/appinfo.txt"
manque() { awk -v appid="$1" -v langue="$2" ${3:+-v os=$3} -f "$R/tests/depots_langue.awk" "$T/acf" "$T/appinfo.txt" | sort | tr '\n' ' ' | sed 's/ $//'; }
manifeste "$T/acf" 9100 100 91001
verif "installe sans langue : le depot francais manque" "91002" "$(manque 9100 french)"
verif "allemand : son depot" "91003" "$(manque 9100 german)"
verif "anglais (pas de depot de langue) : rien" "" "$(manque 9100 english)"
verif "macos : le depot macOS en plus" "91002 91007" "$(manque 9100 french macos)"
manifeste "$T/acf" 9100 100 91001 91002
verif "depot francais installe : rien" "" "$(manque 9100 french)"
verif "la fiche d'un autre jeu n'est pas lue" "92002" "$(manque 9200 french)"
verif "jeu absent de la fiche : rien" "" "$(manque 9300 french)"

echo "== 3. cidre dl, mise a jour avant lancement"
if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1; fi
[ -x "$R/build/cidre-outil" ] || { echo "cidre-outil introuvable et impossible a construire : suite non jouee" >&2; exit 1; }
export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/profils-base"
export CIDRE_STEAMCMD="$F/steamcmd.sh" CIDRE_LANCEUR="$F/lanceur.sh" CIDRE_STEAM_USER=essai
export CIDRE_MAJ_BUDGET=5 CIDRE_LANGUE_MAC=fr-FR
export CIDRE_PROTONDB_URL="file://$T/nulle-part/"
unset CIDRE_LANGUE CIDRE_MAJ_AVANT_LANCEMENT CIDRE_MAJ_TTL CIDRE_MAJ_LIBRE_MIN CIDRE_ESSAI_LIBRE_KO CIDRE_MAJ_VALIDER 2>/dev/null
printf '#!/bin/sh\nexit 0\n' >"$F/bin/open"; chmod +x "$F/bin/open"
export PATH="$F/bin:$PATH"
G="$CIDRE_DIR/games"; mkdir -p "$G"
printf '%s\n' "#!/bin/sh" "echo \"\$(basename \"\$1\") appid=\${SteamAppId:-}\" >>\"$F/lances\"" >"$F/lanceur.sh"
# Le faux SteamCMD : sans compte, la fiche ci-dessus ; avec compte, app_update
# installe le depot sans langue et celui de la langue demandee (-language),
# sauf si le fichier `sans_langue` existe (Steam ne le donne pas).
cat >"$F/steamcmd.sh" <<STEAMCMD
#!/bin/sh
F="$F"
R="$R"
STEAMCMD
cat >>"$F/steamcmd.sh" <<'STEAMCMD'
echo "$*" >>"$F/appels"
anonyme=non; dest=; app=; infos=; avant=; langue=english
for a in "$@"; do
   case $avant in
      +force_install_dir) dest=$a ;;
      +app_update) app=$a ;;
      +app_info_print) infos="$infos $a" ;;
      +login) [ "$a" = anonymous ] && anonyme=oui ;;
      -language) langue=$a ;;
   esac
   avant=$a
done
. "$F/fiche.sh"
if [ $anonyme = oui ]; then
   echo "Connecting anonymously to Steam Public...OK"
   for i in $infos; do [ -f "$F/publie/$i" ] && fiche "$i" "$(cat "$F/publie/$i")"; done
   exit 0
fi
echo "Logging in user 'essai' to Steam Public...OK"
[ -n "$app" ] || exit 0
mkdir -p "$dest/steamapps"; printf 'MZ\n' >"$dest/Jeu.exe"
d="${app}1"
if [ ! -f "$F/sans_langue" ]; then
   case $langue in french) d="$d ${app}2" ;; german) d="$d ${app}3" ;; esac
fi
manifeste "$dest/steamapps/appmanifest_$app.acf" "$app" "$(cat "$F/publie/$app")" $d
echo "Success! App '$app' fully installed."
exit 0
STEAMCMD
{ echo "manifeste() {"; sed -n '/^manifeste() {/,/^}/p' "$0" | sed '1d'; echo "fiche() {"; sed -n '/^fiche() {/,/^}/p' "$0" | sed '1d'; } >"$F/fiche.sh"
chmod +x "$F/steamcmd.sh" "$F/lanceur.sh"
appels() { grep -c -e "$1" "$F/appels" 2>/dev/null; }
raz() { : >"$F/appels"; : >"$F/lances"; rm -f "$F/sans_langue"; }
installes() { awk -F'"' '/"InstalledDepots"/ { d = 1; next } d && /^\t\t"/ { print $2 } d && /^\t}/ { d = 0 }' "$G/$1/steamapps/appmanifest_$1.acf" | tr '\n' ' ' | sed 's/ $//'; }
echo 100 >"$F/publie/9100"; echo 100 >"$F/publie/9200"
raz

sortie=$(sh "$C" dl 9100 </dev/null 2>&1); rc=$?
verif "cidre dl : code 0" "0" "$rc"
contient "cidre dl : la langue est annoncee" "langue  : french" "$sortie"
contient "cidre dl : SteamCMD recoit la langue du Mac" "+app_update 9100 -language french validate +quit" "$(grep app_update "$F/appels")"
verif "cidre dl : depots sans langue et francais" "91001 91002" "$(installes 9100)"

# un jeu telecharge avant ce correctif : en anglais, a jour
raz; mkdir -p "$G/9200/steamapps"; printf 'MZ\n' >"$G/9200/Jeu.exe"
manifeste "$G/9200/steamapps/appmanifest_9200.acf" 9200 100 92001
sortie=$(sh "$C" play 9200 2>&1); rc=$?
verif "jeu en anglais : lance (code 0)" "0" "$rc"
contient "jeu en anglais : les fichiers de langue sont annonces" "Fichiers de langue a ajouter (french : depot 92002)" "$sortie"
contient "jeu en anglais : sans validate, en francais" "+app_update 9200 -language french +quit" "$(grep app_update "$F/appels")"
verif "jeu en anglais : le depot francais est ajoute" "92001 92002" "$(installes 9200)"
contient "jeu en anglais : c'est dit" "Fichiers de langue ajoutes (french)." "$sortie"
verif "jeu en anglais : puis lance" "Jeu.exe appid=9200" "$(tail -1 "$F/lances")"
raz
sh "$C" play 9200 >/dev/null 2>&1
verif "lancement suivant : aucun telechargement" "0" "$(appels app_update)"

# le profil demande l'allemand ; Steam ne le donne pas
raz; sh "$C" set 9200 langue de >/dev/null 2>&1; : >"$F/sans_langue"
sortie=$(sh "$C" play 9200 2>&1); rc=$?
verif "allemand refuse : lance quand meme (code 0)" "0" "$rc"
contient "allemand : SteamCMD recoit la langue du profil" "+app_update 9200 -language german +quit" "$(grep app_update "$F/appels")"
contient "allemand refuse : c'est dit" "SteamCMD n'a pas installe le depot 92003" "$sortie"
raz; : >"$F/sans_langue"
sh "$C" play 9200 >/dev/null 2>&1
verif "allemand refuse : pas redemande pour le meme build" "0" "$(appels app_update)"
raz; echo 101 >"$F/publie/9200"; rm -f "$CIDRE_DIR/cache/appinfo.txt"
sortie=$(sh "$C" play 9200 2>&1)
contient "build suivant : la mise a jour demande l'allemand" "+app_update 9200 -language german +quit" "$(grep app_update "$F/appels")"
verif "build suivant : depot allemand installe avec" "92001 92003" "$(installes 9200)"
raz; sh "$C" set 9200 langue auto >/dev/null 2>&1
sortie=$(CIDRE_MAJ_AVANT_LANCEMENT=0 sh "$C" play 9200 2>&1)
verif "maj_avant_lancement coupee : rien d'ajoute" "0" "$(appels app_update)"

echo "== 4. langue_jeu.sh"
export WINEPREFIX="$T/pfx" CIDRE_LANGUES="$T/langues.conf" CIDRE_LANGUE_ETAT="$T/etat-langue"
printf '# essai\n9300\tAppData/Roaming/Jeu/reglages.txt\tlangue\ten=english fr=francais de=deutsch\n' >"$CIDRE_LANGUES"
U="$WINEPREFIX/drive_c/users/essai"; mkdir -p "$U/AppData/Roaming/Jeu"
printf 'volume = 3\nlangue = "english"\n' >"$U/AppData/Roaming/Jeu/reglages.txt"
lj() { sh "$R/tests/langue_jeu.sh" "$@"; }
val() { sed -n 's/^langue = //p' "$U/AppData/Roaming/Jeu/reglages.txt"; }
lj 9300 fr une-fois >/dev/null
verif "auto : la langue du Mac est posee" '"francais"' "$(val)"
verif "auto : notee" "fr" "$(cat "$CIDRE_LANGUE_ETAT/9300" 2>/dev/null)"
sed -i '' 's/^langue = .*/langue = "english"/' "$U/AppData/Roaming/Jeu/reglages.txt"
sortie=$(lj 9300 fr une-fois)
verif "auto : le choix fait dans le jeu est garde" '"english"' "$(val)"
contient "auto : c'est dit" "deja posee une fois" "$sortie"
lj 9300 de une-fois >/dev/null
verif "auto, le Mac change de langue : posee a nouveau" '"deutsch"' "$(val)"
sed -i '' 's/^langue = .*/langue = "english"/' "$U/AppData/Roaming/Jeu/reglages.txt"
lj 9300 fr >/dev/null
verif "profil : posee a chaque lancement" '"francais"' "$(val)"
rm -rf "$CIDRE_LANGUE_ETAT"; rm "$U/AppData/Roaming/Jeu/reglages.txt"
lj 9300 fr une-fois >/dev/null
verif "auto, fichier absent : rien de note (posee au lancement suivant)" "" "$(cat "$CIDRE_LANGUE_ETAT/9300" 2>/dev/null)"
verif "jeu hors de la table : rien" "" "$(lj 9301 fr une-fois)"
unset WINEPREFIX CIDRE_LANGUES CIDRE_LANGUE_ETAT

echo "== 5. lanceur, syntaxe"
grep -q 'export CIDRE_LOCALE=' "$R/tests/lancer_depuis_steam.sh" && ok "lanceur : la locale va a CIDRE_LOCALE" || echec "lanceur : CIDRE_LOCALE non posee"
grep -q 'export LC_ALL=\|export LANG=' "$R/tests/lancer_depuis_steam.sh" && echec "lanceur : LC_ALL/LANG exportes pour tout le script (printf du shell sous fr_FR)" || ok "lanceur : le script reste en locale C"
awk '/CIDRE_LOCALE/ { l = NR } /^exec "\$WINE" "\$@"/ { e = NR } END { exit !(l && e && l < e) }' "$R/tests/etape2_pile_arm64ec.sh" \
   && ok "etape2 : LC_ALL/LANG de CIDRE_LOCALE avant Wine" || echec "etape2 : CIDRE_LOCALE pas appliquee avant Wine"
grep -q 'langue_cidre.sh' "$R/tests/empaqueter_runtime.sh" && ok "runtime : langue_cidre.sh livre" || echec "runtime : langue_cidre.sh non livre"
grep -q 'depots_langue.awk' "$R/tests/empaqueter_runtime.sh" && ok "runtime : depots_langue.awk livre" || echec "runtime : depots_langue.awk non livre"
for s in cidre tests/langue_cidre.sh tests/langue_jeu.sh tests/lancer_depuis_steam.sh tests/etape2_pile_arm64ec.sh tests/tester_langue.sh; do
   sh -n "$R/$s" && ok "syntaxe : $s" || echec "syntaxe : $s"
done

echo
[ $ko -eq 0 ] && echo "langue : $nb verifications, toutes bonnes" || echo "langue : $ko sur $nb en echec"
[ $ko -eq 0 ]
