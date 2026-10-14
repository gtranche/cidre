#!/bin/sh
# Teste la mise a jour d'un jeu avant son lancement (`cidre play`), sans jeu,
# sans reseau et sans Wine : un faux SteamCMD (fiche publique des jeux, mise a
# jour qui reussit, s'arrete a mi-parcours, manque de place, n'a pas de
# session...), un faux lanceur qui note ce qu'on lui fait lancer, de faux jeux
# dans un dossier Cidre temporaire.
#   1. un jeu a jour : lance sans rien demander a Steam tant que le cache vaut,
#      une seule demande sans compte quand il est perime ;
#   2. un build plus recent : mis a jour (sans `validate`), puis lance ; l'etat
#      et le cache suivent ; pas de seconde mise a jour au lancement suivant ;
#   3. passer outre : --sans-maj, l'option maj_avant_lancement (jeu, general),
#      CIDRE_MAJ_AVANT_LANCEMENT ;
#   4. la verification est impossible : hors ligne, Steam trop lent, SteamCMD
#      absent -- une ligne, et le jeu part dans sa version installee ;
#   5. la mise a jour echoue : session absente, coupure a mi-parcours, place
#      insuffisante (avant, et dite par SteamCMD), code 0 sur un echec -- le jeu
#      reste installe et lancable, `cidre list|info|updates --json` le disent ;
#   6. les cas tranches : jeu du client Steam (rien), jeu repris d'une
#      bouteille (comme un autre), branche beta (epingle), build installe en
#      avance sur la fiche (a jour), mise a jour sans effet (pas de boucle) ;
#   7. --json : les evenements de `cidre play`, un objet par ligne ;
#   8. deux commandes a la fois, et l'arret en cours de route (SIGTERM) ;
#   9. `cidre dl` : meme chemin, cache invalide apres coup ; `cidre rm` ;
#  10. le cache du client Steam (appcache/appinfo.vdf, fabrique ici) : lu par
#      `cidre-outil builds`, il dispense de SteamCMD tant qu'il est frais ;
#      `cidre updates --fond`, une seule demande a la fois (verrou), rien
#      laisse derriere une verification abandonnee ;
#  11. syntaxe, aide, documentation de l'option.
# Rien n'est lu ni ecrit hors d'un dossier temporaire (HOME et CIDRE_DIR a part).
#   sh tests/tester_maj_avant_lancement.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
VRAI_HOME=$HOME
C="$R/cidre"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-maj.XXXXXX")
T=$(cd "$T" && pwd -P)
F="$T/faux"
trap 'pkill -f "$F/steamcmd.sh" 2>/dev/null; rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
sans() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) echec "$1 : « $2 » present dans « $3 »" ;; *) ok "$1" ;; esac
}

if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1; fi
[ -x "$R/build/cidre-outil" ] || { echo "cidre-outil introuvable et impossible a construire : suite non jouee" >&2; exit 1; }

mkdir -p "$F/publie" "$F/bin" "$T/home"
export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/profils-base"
export CIDRE_STEAMCMD="$F/steamcmd.sh" CIDRE_LANCEUR="$F/lanceur.sh" CIDRE_STEAM_USER=essai
export CIDRE_MAJ_BUDGET=5
unset CIDRE_MAJ_AVANT_LANCEMENT CIDRE_MAJ_TTL CIDRE_MAJ_LIBRE_MIN CIDRE_ESSAI_LIBRE_KO CIDRE_MAJ_VALIDER 2>/dev/null
# `open` (le client Steam) : un faux, devant le vrai
printf '#!/bin/sh\necho "$*" >>"%s/ouvertures"\n' "$F" >"$F/bin/open"; chmod +x "$F/bin/open"
export PATH="$F/bin:$PATH"
G="$CIDRE_DIR/games"; M="$CIDRE_DIR/maj"; A="$CIDRE_DIR/cache/appinfo.txt"; TAB=$(printf '\t')
mkdir -p "$G"

# Le faux lanceur : note l'executable et la version du jeu qu'on lui confie.
cat >"$F/lanceur.sh" <<'LANCEUR'
#!/bin/sh
F=$(dirname "$0")
echo "$(basename "$1") $(cat "$(dirname "$1")/version.txt" 2>/dev/null) appid=${SteamAppId:-}" >>"$F/lances"
echo "sortie du lanceur"
LANCEUR

# Le faux SteamCMD. Sans compte (+login anonymous) : la fiche publique des jeux
# demandes, d'apres publie/<appid> ; fichiers `hors_ligne` et `lent` (secondes).
# Avec compte : +app_update, selon le fichier `mode` (ok par defaut).
cat >"$F/steamcmd.sh" <<'STEAMCMD'
#!/bin/sh
F=$(dirname "$0")
echo "$*" >>"$F/appels"
anonyme=non; dest=; app=; infos=; avant=
for a in "$@"; do
   case $avant in
      +force_install_dir) dest=$a ;;
      +app_update) app=$a ;;
      +app_info_print) infos="$infos $a" ;;
      +login) [ "$a" = anonymous ] && anonyme=oui ;;
   esac
   avant=$a
done
if [ $anonyme = oui ]; then
   [ -f "$F/lent" ] && sleep "$(cat "$F/lent")"
   [ -f "$F/hors_ligne" ] && { echo "Connecting anonymously to Steam Public...FAILED (No Connection)"; exit 5; }
   echo "Connecting anonymously to Steam Public...OK"
   for i in $infos; do
      [ -f "$F/publie/$i" ] || { echo "No app info for AppID $i found, requesting..."; continue; }
      printf 'AppID : %s, change number : 1/1, last change : Tue Oct 13 12:00:00 2026\n"%s"\n{\n\t"common"\n\t{\n\t\t"name"\t\t"Jeu %s"\n\t}\n\t"depots"\n\t{\n\t\t"1"\n\t\t{\n\t\t\t"manifests"\n\t\t\t{\n\t\t\t\t"public"\n\t\t\t\t{\n\t\t\t\t\t"gid"\t\t"42"\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t\t"branches"\n\t\t{\n\t\t\t"public"\n\t\t\t{\n\t\t\t\t"buildid"\t\t"%s"\n\t\t\t\t"timeupdated"\t\t"1791000000"\n\t\t\t}\n\t\t\t"experimental"\n\t\t\t{\n\t\t\t\t"buildid"\t\t"999999"\n\t\t\t}\n\t\t}\n\t}\n}\n' \
         "$i" "$i" "$i" "$(cat "$F/publie/$i")"
   done
   exit 0
fi
mode=$(cat "$F/mode" 2>/dev/null); mode=${mode:-ok}
if [ "$mode" = sans_session ]; then
   echo "Logging in user 'essai' to Steam Public..."
   echo "Cached credentials not found."
   printf 'password: '
   sleep 30; exit 5
fi
echo "Logging in user 'essai' to Steam Public...OK"
[ -n "$app" ] || exit 0
m="$dest/steamapps/appmanifest_$app.acf"
cible=$(cat "$F/publie/$app" 2>/dev/null); cible=${cible:-1}
ancien=$(sed -n 's/.*"buildid"[[:space:]]*"\(.*\)".*/\1/p' "$m" 2>/dev/null | head -1)
manifeste() { # <StateFlags> <buildid>
   mkdir -p "$dest/steamapps"
   printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Jeu %s"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"1000"\n\t"buildid"\t\t"%s"\n\t"TargetBuildID"\t\t"%s"\n}\n' "$app" "$app" "$1" "$2" "$cible" >"$m"
}
echo " Update state (0x5) verifying install, progress: 50.00 (500 / 1000)"
case $mode in
   ok)
      echo " Update state (0x61) downloading, progress: 37.93 (32564012 / 85850313)"
      echo " Update state (0x61) downloading, progress: 100.00 (85850313 / 85850313)"
      mkdir -p "$dest"; printf 'MZ build %s\n' "$cible" >"$dest/Jeu.exe"; echo "$cible" >"$dest/version.txt"
      manifeste 4 "$cible"
      echo "Success! App '$app' fully installed." ;;
   coupe|rc0)
      echo " Update state (0x61) downloading, progress: 40.00 (400 / 1000)"
      manifeste 1026 "${ancien:-0}"
      echo "Error! App '$app' state is 0x402 after update job."
      [ "$mode" = rc0 ] || exit 8 ;;
   disque)
      echo "Error! App '$app' state is 0x202 after update job."
      exit 8 ;;
   sans_effet)
      echo "Success! App '$app' already up to date." ;;
   long)
      echo " Update state (0x61) downloading, progress: 12.50 (125 / 1000)"
      sleep 60 ;;
esac
exit 0
STEAMCMD
chmod +x "$F/steamcmd.sh" "$F/lanceur.sh"

# Un jeu du dossier Cidre, tel que `cidre dl` le laisse.
jeu() { # <appid> <build> [StateFlags] [ligne de manifeste en plus]
   mkdir -p "$G/$1/steamapps"
   printf 'MZ build %s\n' "$2" >"$G/$1/Jeu.exe"; echo "$2" >"$G/$1/version.txt"
   printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Jeu %s"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"1000"\n\t"buildid"\t\t"%s"\n%s}\n' "$1" "$1" "${3:-4}" "$2" "${4:-}" >"$G/$1/steamapps/appmanifest_$1.acf"
}
publie() { echo "$2" >"$F/publie/$1"; }
appels() { grep -c -e "$1" "$F/appels" 2>/dev/null; }   # appels a SteamCMD dont les arguments portent ce motif
raz() { : >"$F/appels"; : >"$F/lances"; rm -f "$F/mode" "$F/hors_ligne" "$F/lent"; }
build() { sed -n 's/.*"buildid"[[:space:]]*"\(.*\)".*/\1/p' "$G/$1/steamapps/appmanifest_$1.acf" | head -1; }
lance() { tail -1 "$F/lances" 2>/dev/null; }
vieillir() { touch -t 202601010000 "$A"; }
etat() { sed -n "s/^$2=//p" "$M/$1" 2>/dev/null | head -1; }
champ_json() { printf '%s' "$1" | sed -nE 's/.*"'"$2"'": *("[^"]*"|[^,}]*).*/\1/p' | head -1; }
maj_de() { sh "$C" info "$1" --json | sed -n 's/.*"maj":\({[^}]*}\).*/\1/p'; }
raz

echo "== 1. un jeu a jour"
jeu 9001 100; publie 9001 100
sortie=$(sh "$C" play 9001 2>&1); rc=$?
verif "jamais verifie : lance (code 0)" "0" "$rc"
verif "jamais verifie : une demande a Steam, sans compte" "1" "$(appels 'login anonymous')"
verif "jamais verifie : aucun telechargement" "0" "$(appels app_update)"
verif "lance : l'executable, la version installee et l'appid" "Jeu.exe 100 appid=9001" "$(lance)"
contient "la sortie du lanceur passe" "sortie du lanceur" "$sortie"
raz
sortie=$(sh "$C" play 9001 2>&1)
verif "cache frais : aucun appel a SteamCMD" "0" "$(wc -l <"$F/appels" | tr -d ' ')"
verif "cache frais : lance" "Jeu.exe 100 appid=9001" "$(lance)"
sans "cache frais : rien a dire de la mise a jour" "ise a jour" "$sortie"
raz; vieillir
sh "$C" play 9001 >/dev/null 2>&1
verif "cache perime : une demande sans compte" "1" "$(appels 'login anonymous')"
verif "cache perime : pas de telechargement" "0" "$(appels app_update)"
verif "cache perime : lance" "Jeu.exe 100 appid=9001" "$(lance)"
[ -z "$(find "$A" -mmin +1)" ] && ok "cache perime : il est refait" || echec "cache perime : il n'a pas ete refait"

echo "== 2. un build plus recent"
raz; publie 9001 200; vieillir
sortie=$(sh "$C" play 9001 2>&1); rc=$?
verif "mis a jour puis lance (code 0)" "0" "$rc"
verif "le build installe est le nouveau" "200" "$(build 9001)"
verif "c'est la nouvelle version qui est lancee" "Jeu.exe 200 appid=9001" "$(lance)"
verif "un seul telechargement" "1" "$(appels 'app_update 9001')"
verif "sans validate : seul ce qui a change" "0" "$(appels 'app_update 9001 validate')"
contient "session du compte, dossier du jeu" "+force_install_dir $G/9001 +login essai +app_update 9001 +quit" "$(grep app_update "$F/appels")"
contient "annonce la mise a jour et la facon de passer outre" "Mise a jour avant le lancement : build 100 -> 200 (\`cidre play 9001 --sans-maj\` pour jouer sans attendre)." "$sortie"
contient "la sortie de SteamCMD est relayee" "downloading, progress: 37.93" "$sortie"
contient "dit que c'est fait" "Mise a jour faite : build 200." "$sortie"
verif "etat : faite, d'ou l'on vient et ou l'on va" "faite 100 200 200" "$(etat 9001 etat) $(etat 9001 build_avant) $(etat 9001 build_vise) $(etat 9001 build_apres)"
verif "aucun fichier de travail ne reste" "" "$(ls "$M" | grep -e avancement -e '\.rc$')"
raz
sh "$C" play 9001 >/dev/null 2>&1
verif "lancement suivant : aucun appel a SteamCMD" "0" "$(wc -l <"$F/appels" | tr -d ' ')"
verif "cidre updates : a jour" '"build_installe": 200, "build_disponible": 200, "a_jour": true, "source": "cidre", "etat":"a_jour"' "$(sh "$C" updates --json | sed 's/.*\("build_installe": 200[^}]*"etat":"[a-z_]*"\).*/\1/')"
# une mise a jour connue par un cache ancien reste vraie : pas de nouvelle question a Steam
raz; publie 9001 300; sh "$C" updates --refresh >/dev/null 2>&1; : >"$F/appels"; vieillir
sh "$C" play 9001 >/dev/null 2>&1
verif "mise a jour deja connue, cache ancien : pas de nouvelle demande sans compte" "0" "$(appels 'login anonymous')"
verif "mise a jour deja connue, cache ancien : faite" "300 Jeu.exe 300 appid=9001" "$(build 9001) $(lance)"

echo "== 3. passer outre"
raz; publie 9001 400; sh "$C" updates --refresh >/dev/null 2>&1; : >"$F/appels"
sortie=$(sh "$C" play 9001 --sans-maj 2>&1)
verif "--sans-maj : aucun appel a SteamCMD" "0" "$(wc -l <"$F/appels" | tr -d ' ')"
verif "--sans-maj : la version installee est lancee" "300 Jeu.exe 300 appid=9001" "$(build 9001) $(lance)"
contient "--sans-maj : la mise a jour connue est annoncee" "Mise a jour disponible (build 300 -> 400), laissee de cote : a ta demande (--sans-maj)." "$sortie"
raz; vieillir
sh "$C" play --sans-maj 9001 >/dev/null 2>&1
verif "--sans-maj, cache perime : toujours aucun appel" "0 Jeu.exe 300 appid=9001" "$(wc -l <"$F/appels" | tr -d ' ') $(lance)"
sh "$C" updates --refresh >/dev/null 2>&1
raz; sh "$C" set 9001 maj_avant_lancement false; verif "cidre set <id> maj_avant_lancement false : accepte" "0" "$?"
sortie=$(sh "$C" play 9001 2>&1)
verif "option coupee pour le jeu : aucun appel, version installee" "0 Jeu.exe 300 appid=9001" "$(wc -l <"$F/appels" | tr -d ' ') $(lance)"
contient "option coupee : la mise a jour est annoncee, et comment la reprendre" "laissee de cote : maj_avant_lancement = false (\`cidre set 9001 maj_avant_lancement true\` pour la reprendre)." "$sortie"
verif "option coupee : cidre info dit « ignoree », raison option" '"etat":"ignoree" "option" false' "$(m=$(maj_de 9001); echo "\"etat\":$(champ_json "$m" etat) $(champ_json "$m" raison) $(champ_json "$m" avant_lancement)")"
verif "option coupee : cidre updates l'annonce toujours" "1" "$(sh "$C" updates | grep -c '^9001 .*MISE A JOUR : build 300 -> 400 (laissee de cote : option)')"
raz; sortie=$(CIDRE_MAJ_AVANT_LANCEMENT=1 sh "$C" play 9001 2>&1)
verif "CIDRE_MAJ_AVANT_LANCEMENT=1 passe devant le profil" "400 Jeu.exe 400 appid=9001" "$(build 9001) $(lance)"
sh "$C" unset 9001 maj_avant_lancement
publie 9001 500; sh "$C" updates --refresh >/dev/null 2>&1
raz; sh "$C" set defaut maj_avant_lancement false
sh "$C" play 9001 >/dev/null 2>&1
verif "option coupee en general : version installee" "0 Jeu.exe 400 appid=9001" "$(wc -l <"$F/appels" | tr -d ' ') $(lance)"
sh "$C" set 9001 maj_avant_lancement true
raz; sh "$C" play 9001 >/dev/null 2>&1
verif "le reglage du jeu passe devant le general" "500 Jeu.exe 500 appid=9001" "$(build 9001) $(lance)"
sh "$C" unset defaut maj_avant_lancement; sh "$C" unset 9001 maj_avant_lancement
raz; publie 9001 600; sh "$C" updates --refresh >/dev/null 2>&1; : >"$F/appels"
CIDRE_MAJ_AVANT_LANCEMENT=0 sh "$C" play 9001 >/dev/null 2>&1
verif "CIDRE_MAJ_AVANT_LANCEMENT=0 : version installee" "0 Jeu.exe 500 appid=9001" "$(wc -l <"$F/appels" | tr -d ' ') $(lance)"
verif "option : true ou false, rien d'autre" "2" "$(sh "$C" set 9001 maj_avant_lancement peut-etre >/dev/null 2>&1; echo $?)"
verif "option livree : true" "true" "$(sh "$R/tests/profil_cidre.sh" 9001 | sed -n 's/^maj_avant_lancement=//p')"

echo "== 4. la verification est impossible"
jeu 9002 100; publie 9002 100; sh "$C" updates --refresh >/dev/null 2>&1
raz; publie 9002 200; vieillir; touch "$F/hors_ligne"
sortie=$(sh "$C" play 9002 2>&1); rc=$?
verif "hors ligne : lance quand meme (code 0)" "0 Jeu.exe 100 appid=9002" "$rc $(lance)"
contient "hors ligne : une ligne le dit" "Mise a jour non verifiee : Steam n'a pas repondu (hors ligne ?). Lancement de la version installee." "$sortie"
verif "hors ligne : une seule ligne sur la mise a jour" "1" "$(printf '%s\n' "$sortie" | grep -c 'ise a jour')"
verif "hors ligne : aucun telechargement tente" "0" "$(appels app_update)"
verif "hors ligne : cidre updates rend ce qu'il savait" '0 "a_jour": true' "$(s=$(sh "$C" updates --json 2>/dev/null); echo "$? $(printf '%s' "$s" | sed -n 's/.*"appid": 9002,[^}]*\("a_jour": [a-z]*\).*/\1/p')")"
contient "hors ligne : cidre updates previent sur l'erreur standard" "Steam n'a pas repondu (hors ligne ?) : etat lu le 2026-01-01" "$(sh "$C" updates --json 2>&1 >/dev/null)"
raz; vieillir; echo 4 >"$F/lent"
debut=$(date +%s); sortie=$(CIDRE_MAJ_BUDGET=1 sh "$C" play 9002 2>&1); rc=$?; duree=$(( $(date +%s) - debut ))
verif "Steam trop lent : lance quand meme" "0 Jeu.exe 100 appid=9002" "$rc $(lance)"
contient "Steam trop lent : une ligne le dit" "Mise a jour non verifiee : Steam met plus de 1 s a repondre ; sa reponse servira au prochain lancement. Lancement de la version installee." "$sortie"
[ "$duree" -le 3 ] && ok "Steam trop lent : le lancement n'attend pas ($duree s pour une reponse a 4 s)" || echec "Steam trop lent : le lancement a attendu $duree s"
i=0; while [ $i -lt 40 ] && [ -n "$(find "$A" -mmin +1)" ]; do sleep 0.25; i=$((i + 1)); done
[ -z "$(find "$A" -mmin +1)" ] && ok "Steam trop lent : la reponse arrive en fond et refait le cache" || echec "Steam trop lent : le cache n'a pas ete refait en fond"
rm -f "$F/lent"; raz
sh "$C" play 9002 >/dev/null 2>&1
verif "le lancement suivant s'en sert : mis a jour" "200 Jeu.exe 200 appid=9002" "$(build 9002) $(lance)"
raz; publie 9002 300; vieillir
sortie=$(CIDRE_STEAMCMD="$T/absent" sh "$C" play 9002 2>&1); rc=$?
verif "SteamCMD absent : lance quand meme" "0 Jeu.exe 200 appid=9002" "$rc $(lance)"
contient "SteamCMD absent : une ligne le dit" "Mise a jour non verifiee : SteamCMD est introuvable. Relance \`cidre setup\` pour le reinstaller. Lancement de la version installee." "$sortie"

echo "== 5. la mise a jour echoue"
jeu 9003 100; publie 9003 200; raz; sh "$C" updates --refresh >/dev/null 2>&1; : >"$F/appels"
echo sans_session >"$F/mode"
sortie=$(sh "$C" play 9003 2>&1); rc=$?
verif "session absente : lance quand meme la version installee" "0 100 Jeu.exe 100 appid=9003" "$rc $(build 9003) $(lance)"
contient "session absente : la cause et quoi faire" "Mise a jour impossible : la session Steam n'est pas memorisee. Connecte-toi (\`cidre login\`, ou « Connexion a Steam » dans Verger), puis relance le jeu. Lancement de la version installee (build 100)." "$sortie"
verif "session absente : etat echouee, raison session" "echouee session 100 200" "$(etat 9003 etat) $(etat 9003 raison) $(etat 9003 build_avant) $(etat 9003 build_vise)"
m=$(maj_de 9003)
verif "session absente : cidre info --json" '"echouee" "session" 100 200' "$(champ_json "$m" etat) $(champ_json "$m" raison) $(champ_json "$m" build_installe) $(champ_json "$m" build_disponible)"
contient "session absente : le message est dans le JSON" '"message":"Mise a jour impossible : la session Steam n' "$m"
sh "$C" info 9003 --json | plutil -convert json -o /dev/null - 2>/dev/null && ok "cidre info --json : JSON valide" || echec "cidre info --json : JSON invalide"

echo coupe >"$F/mode"; : >"$F/lances"
sortie=$(sh "$C" play 9003 2>&1); rc=$?
verif "coupure a mi-parcours : lance quand meme" "0 Jeu.exe 100 appid=9003" "$rc $(lance)"
verif "coupure : le manifeste dit « mise a jour en route » (StateFlags 1026)" "1" "$(grep -c '"StateFlags"[[:space:]]*"1026"' "$G/9003/steamapps/appmanifest_9003.acf")"
contient "coupure : la cause, l'erreur de SteamCMD, et la suite" "Mise a jour interrompue : la connexion a Steam a ete perdue (Error! App '9003' state is 0x402 after update job.). Elle reprendra ou elle en etait au prochain lancement. Lancement de la version installee (build 100)." "$sortie"
verif "coupure : etat echouee, raison reseau" "echouee reseau 100" "$(etat 9003 etat) $(etat 9003 raison) $(etat 9003 build_avant)"
contient "coupure : le jeu reste « installe » pour cidre list" '"id":"9003","appid":9003,"nom":"Jeu 9003","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true' "$(sh "$C" list --json)"
u=$(sh "$C" updates --json 2>/dev/null)
printf '%s' "$u" | plutil -convert json -o /dev/null - 2>/dev/null && ok "cidre updates --json : JSON valide" || echec "cidre updates --json : JSON invalide : $u"
u3=$(printf '%s' "$u" | tr '{' '\n' | grep '"appid": 9003,')
verif "coupure : cidre updates --json dit echouee, et pourquoi" 'false "echouee" "reseau"' "$(champ_json "$u3" a_jour) $(champ_json "$u3" etat) $(champ_json "$u3" raison)"
verif "coupure : cidre updates (texte)" "1" "$(sh "$C" updates 2>/dev/null | grep -c '^9003 .*MISE A JOUR : build 100 -> 200 (derniere tentative echouee : reseau)')"
# un premier telechargement inacheve, lui, n'est pas un jeu installe
jeu 9004 0 1026; rm -f "$G/9004/Jeu.exe"
contient "premier telechargement inacheve : pas installe" '"id":"9004","appid":9004,"nom":"Jeu 9004","plateforme":"inconnu","lancement":"cidre","source":"cidre","installe":false' "$(sh "$C" list --json)"
rm -rf "$G/9004"
echo ok >"$F/mode"; : >"$F/lances"; : >"$F/appels"
sh "$C" play 9003 >/dev/null 2>&1
verif "lancement suivant : la mise a jour est reprise, et passe" "200 Jeu.exe 200 appid=9003 faite" "$(build 9003) $(lance) $(etat 9003 etat)"

publie 9003 300; sh "$C" updates --refresh >/dev/null 2>&1; raz
sortie=$(CIDRE_ESSAI_LIBRE_KO=204800 sh "$C" play 9003 2>&1); rc=$?
verif "200 Mo libres : lance quand meme, sans rien telecharger" "0 0 Jeu.exe 200 appid=9003" "$rc $(appels app_update) $(lance)"
contient "200 Mo libres : la place, et quoi faire" "Mise a jour impossible : place insuffisante sur le disque des jeux (200 Mo libres, il en faut au moins 1024). Libere de la place, puis relance le jeu. Lancement de la version installee (build 200)." "$sortie"
verif "200 Mo libres : etat echouee, raison disque" "echouee disque" "$(etat 9003 etat) $(etat 9003 raison)"
verif "CIDRE_MAJ_LIBRE_MIN abaisse le seuil" "300" "$(CIDRE_ESSAI_LIBRE_KO=204800 CIDRE_MAJ_LIBRE_MIN=100 sh "$C" play 9003 >/dev/null 2>&1; build 9003)"
publie 9003 400; sh "$C" updates --refresh >/dev/null 2>&1; raz; echo disque >"$F/mode"
sortie=$(sh "$C" play 9003 2>&1)
verif "SteamCMD manque de place (0x202) : lance quand meme" "Jeu.exe 300 appid=9003 disque" "$(lance) $(etat 9003 raison)"
contient "SteamCMD manque de place : le dit" "Mise a jour impossible : place insuffisante sur le disque des jeux (Error! App '9003' state is 0x202 after update job.)." "$sortie"
raz; echo rc0 >"$F/mode"
sortie=$(sh "$C" play 9003 2>&1)
verif "SteamCMD rend 0 sur un echec : ce n'est pas pris pour une reussite" "300 echouee Jeu.exe 300 appid=9003" "$(build 9003) $(etat 9003 etat) $(lance)"
sans "SteamCMD rend 0 sur un echec : on ne dit pas « faite »" "Mise a jour faite" "$sortie"

echo "== 6. les cas tranches"
# un jeu du client Steam : Steam le met a jour lui-meme
S="$HOME/Library/Application Support/Steam/steamapps"; mkdir -p "$S/common/Natif/Natif.app"
printf '"AppState"\n{\n\t"appid"\t\t"9010"\n\t"name"\t\t"Natif"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Natif"\n\t"buildid"\t\t"100"\n}\n' >"$S/appmanifest_9010.acf"
publie 9010 200; raz; rm -f "$F/ouvertures"; sh "$C" updates --refresh >/dev/null 2>&1; : >"$F/appels"
sortie=$(sh "$C" play 9010 2>&1); rc=$?
verif "jeu du client Steam : confie a Steam, sans SteamCMD" "0 steam://run/9010 0" "$rc $(cat "$F/ouvertures" 2>/dev/null) $(wc -l <"$F/appels" | tr -d ' ')"
verif "jeu du client Steam : rien de lance par Cidre" "" "$(lance)"
u=$(sh "$C" updates --json | tr '{' '\n' | grep '"appid": 9010,')
verif "jeu du client Steam : cidre updates l'annonce, source steam" 'false "steam" "disponible"' "$(champ_json "$u" a_jour) $(champ_json "$u" source) $(champ_json "$u" etat)"
verif "jeu du client Steam : pas de « maj » dans cidre info" "null" "$(sh "$C" info 9010 --json | sed -n 's/.*"maj":\(null\).*/\1/p')"
# un jeu repris d'une bouteille : meme forme, donc meme mise a jour, sur place
jeu 9011 100; printf '9011\tcrossover\tSteam\t/b\tclone\t1790000000\n' >"$CIDRE_DIR/reprises.conf"
publie 9011 200; sh "$C" updates --refresh >/dev/null 2>&1; raz
sh "$C" play 9011 >/dev/null 2>&1
verif "jeu repris d'une bouteille : mis a jour sur place puis lance" "200 Jeu.exe 200 appid=9011" "$(build 9011) $(lance)"
# un jeu qui suit une branche beta : epingle
jeu 9012 100 4 "$(printf '\t"UserConfig"\n\t{\n\t\t"BetaKey"\t\t"experimental"\n\t}\n')"
publie 9012 200; sh "$C" updates --refresh >/dev/null 2>&1; raz
sortie=$(sh "$C" play 9012 2>&1)
verif "branche beta : jamais mis a jour au lancement" "0 100 Jeu.exe 100 appid=9012" "$(appels app_update) $(build 9012) $(lance)"
contient "branche beta : le dit" "laissee de cote : le jeu suit la branche « experimental »." "$sortie"
m=$(maj_de 9012); verif "branche beta : cidre info dit ignoree, raison branche" '"ignoree" "branche"' "$(champ_json "$m" etat) $(champ_json "$m" raison)"
# le build installe est en avance sur la fiche lue : la fiche est en retard, pas le jeu
jeu 9013 300; publie 9013 200; sh "$C" updates --refresh >/dev/null 2>&1; raz
sortie=$(sh "$C" play 9013 2>&1)
verif "build installe en avance : aucun telechargement" "0 Jeu.exe 300 appid=9013" "$(appels app_update) $(lance)"
u=$(sh "$C" updates --json | tr '{' '\n' | grep '"appid": 9013,')
verif "build installe en avance : a jour, pas « pas a jour »" 'true "a_jour"' "$(champ_json "$u" a_jour) $(champ_json "$u" etat)"
verif "build installe en avance : cidre updates (texte)" "1" "$(sh "$C" updates | grep -c '^9013 *a jour$')"
# Steam dit « deja a jour » alors que la fiche annonce plus recent : une tentative, pas une boucle
jeu 9014 100; publie 9014 200; sh "$C" updates --refresh >/dev/null 2>&1; raz; echo sans_effet >"$F/mode"
sh "$C" play 9014 >/dev/null 2>&1
verif "mise a jour sans effet : une tentative, puis lance" "1 Jeu.exe 100 appid=9014" "$(appels 'app_update 9014') $(lance)"
sortie=$(sh "$C" play 9014 2>&1)
verif "mise a jour sans effet : pas de seconde tentative" "1" "$(appels 'app_update 9014')"
contient "mise a jour sans effet : le dit" "laissee de cote : Steam ne la donne pas a ce compte (deja tentee, sans effet)." "$sortie"
raz; vieillir; sh "$C" play 9014 >/dev/null 2>&1
verif "mise a jour sans effet : redemande a Steam quand le cache a vieilli, sans retenter le meme build" "1 0" "$(appels 'login anonymous') $(appels app_update)"
publie 9014 300; vieillir; sh "$C" play 9014 >/dev/null 2>&1
verif "mise a jour sans effet : un build encore plus recent est retente" "300" "$(build 9014)"
# La passe A de l'essai reel (PEAK, 2026-10-14) : buildid abaisse a 25000000,
# SteamCMD repond « Success! App '3527290' already up to date. » sans recrire
# le manifeste. Ce n'est pas une mise a jour faite.
jeu 3527290 25000000; publie 3527290 25739797; sh "$C" updates --refresh >/dev/null 2>&1; raz; echo sans_effet >"$F/mode"
sortie=$(sh "$C" play 3527290 2>&1)
contient "passe A : SteamCMD dit exactement ce qu'il a dit" "Success! App '3527290' already up to date." "$sortie"
sans "passe A : pas de « Mise a jour faite »" "Mise a jour faite" "$sortie"
contient "passe A : le message juste" "Mise a jour sans effet : SteamCMD dit le jeu a jour mais le laisse au build 25000000 (publie : 25739797) ; elle ne sera pas retentee pour ce build. Lancement de la version installee." "$sortie"
verif "passe A : le jeu part dans sa version installee" "25000000 Jeu.exe 25000000 appid=3527290" "$(build 3527290) $(lance)"
verif "passe A : la tentative est notee (faite, vers 25739797, sans effet)" "faite 25000000 25739797 25000000" "$(etat 3527290 etat) $(etat 3527290 build_avant) $(etat 3527290 build_vise) $(etat 3527290 build_apres)"
m=$(maj_de 3527290); verif "passe A : cidre info dit ignoree, sans_effet" '"ignoree" "sans_effet"' "$(champ_json "$m" etat) $(champ_json "$m" raison)"
raz; sortie=$(sh "$C" play 3527290 2>&1)
verif "passe A, lancement suivant : pas de nouvelle tentative" "0 Jeu.exe 25000000 appid=3527290" "$(appels app_update) $(lance)"
contient "passe A, lancement suivant : le dit" "laissee de cote : Steam ne la donne pas a ce compte (deja tentee, sans effet)." "$sortie"
raz; vieillir; sh "$C" play 3527290 >/dev/null 2>&1
verif "passe A, cache vieilli : redemande a Steam, toujours pas de nouvelle tentative" "1 0" "$(appels 'login anonymous') $(appels app_update)"
raz; echo sans_effet >"$F/mode"; jeu 3527290 25000000; rm -f "$M/3527290"; sh "$C" play 3527290 --json >"$T/evts" 2>/dev/null
contient "passe A, --json : l'evenement dit ignoree, sans_effet" '{"evenement":"maj","etat":"ignoree","build_installe":25000000,"build_disponible":25739797,"raison":"sans_effet"' "$(cat "$T/evts")"
echo ok >"$F/mode"; sh "$C" rm 3527290 >/dev/null 2>&1

echo "== 7. --json : les evenements de cidre play"
jeu 9020 100; publie 9020 200; sh "$C" updates --refresh >/dev/null 2>&1; raz; vieillir
sh "$C" play 9020 --json >"$T/evts" 2>"$T/err"; rc=$?
verif "code 0" "0" "$rc"
verif "la sortie standard ne porte que des objets JSON, un par ligne" "0" "$(grep -vc '^{.*}$' "$T/evts")"
bon=oui; while IFS= read -r l; do printf '%s' "$l" | plutil -convert json -o /dev/null - 2>/dev/null || bon=non; done <"$T/evts"
verif "chaque ligne est du JSON valide" "oui" "$bon"
verif "l'ordre : verification, en cours, avancement, faite, lancement" "verification en_cours en_cours en_cours en_cours faite lancement" \
   "$(sed -n 's/.*"evenement":"lancement".*/lancement/p; s/.*"evenement":"maj","etat":"\([a-z_]*\)".*/\1/p' "$T/evts" | tr '\n' ' ' | sed 's/ $//')"
contient "avancement : pourcentage, octets, total, phase" '{"evenement":"maj","etat":"en_cours","avancement":37.93,"octets":32564012,"total":85850313,"phase":"downloading"}' "$(cat "$T/evts")"
contient "annonce : les deux builds" '{"evenement":"maj","etat":"en_cours","build_installe":100,"build_disponible":200,' "$(cat "$T/evts")"
contient "fin : le build installe" '{"evenement":"maj","etat":"faite","build_installe":200,' "$(cat "$T/evts")"
verif "le dernier evenement est le lancement" '{"evenement":"lancement"}' "$(tail -1 "$T/evts")"
contient "le lanceur ecrit a l'erreur, pas sur la sortie standard" "sortie du lanceur" "$(cat "$T/err")"
contient "la sortie de SteamCMD va a l'erreur" "downloading, progress: 37.93" "$(cat "$T/err")"
verif "le jeu mis a jour est lance" "Jeu.exe 200 appid=9020" "$(lance)"
publie 9020 300; sh "$C" updates --refresh >/dev/null 2>&1; raz; echo sans_session >"$F/mode"
sh "$C" play 9020 --json >"$T/evts" 2>/dev/null
contient "echec : etat, raison et message, puis lancement" '"etat":"echouee","build_installe":200,"build_disponible":300,"raison":"session","message":"Mise a jour impossible : la session Steam' "$(cat "$T/evts")"
verif "echec : le lancement suit" '{"evenement":"lancement"} Jeu.exe 200 appid=9020' "$(tail -1 "$T/evts") $(lance)"
raz; sh "$C" play 9020 --json --sans-maj >"$T/evts" 2>/dev/null
verif "--sans-maj : ignoree (raison demande), puis lancement" '"ignoree" "demande" {"evenement":"lancement"}' "$(l=$(head -1 "$T/evts"); echo "$(champ_json "$l" etat) $(champ_json "$l" raison) $(tail -1 "$T/evts")")"
raz; touch "$F/hors_ligne"; vieillir; publie 9001 600; jeu 9021 100; publie 9021 100
sh "$C" play 9021 --json >"$T/evts" 2>/dev/null
verif "hors ligne : inconnu (raison hors_ligne), puis lancement" 'verification "inconnu" "hors_ligne" {"evenement":"lancement"}' "$(l=$(sed -n 2p "$T/evts"); echo "$(sed -n '1s/.*"etat":"\([a-z]*\)".*/\1/p' "$T/evts") $(champ_json "$l" etat) $(champ_json "$l" raison) $(tail -1 "$T/evts")")"
rm -f "$F/hors_ligne"

echo "== 8. deux commandes a la fois, et l'arret en route"
jeu 9030 100; publie 9030 200; sh "$C" updates --refresh >/dev/null 2>&1; raz; echo long >"$F/mode"
sh "$C" play 9030 --json >"$T/evts" 2>"$T/err" & pid=$!
i=0; while [ $i -lt 80 ] && [ ! -s "$M/9030.avancement" ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$M/9030.avancement" ] && ok "telechargement en route : avancement note" || echec "telechargement en route : pas d'avancement apres 8 s"
m=$(maj_de 9030)
verif "pendant ce temps, cidre info : en cours, avec l'avancement" '"en_cours" 12.50 125 1000' "$(champ_json "$m" etat) $(champ_json "$m" avancement) $(champ_json "$m" octets) $(champ_json "$m" total)"
u=$(sh "$C" updates --json | tr '{' '\n' | grep '"appid": 9030,')
verif "pendant ce temps, cidre updates : en cours" '"en_cours" 12.50' "$(champ_json "$u" etat) $(champ_json "$u" avancement)"
sortie=$(sh "$C" play 9030 2>&1); rc=$?
verif "second cidre play pendant la mise a jour : refuse (code 4), rien de lance" "4 " "$rc $(lance)"
contient "second cidre play : dit pourquoi" "Une mise a jour de ce jeu est deja en cours (processus $pid) : attends sa fin, puis relance-le." "$sortie"
verif "cidre dl pendant la mise a jour : refuse (code 4)" "4" "$(sh "$C" dl 9030 >/dev/null 2>&1; echo $?)"
kill -TERM $pid; wait $pid; rc=$?
verif "SIGTERM pendant la mise a jour : cidre s'arrete (code 130)" "130" "$rc"
sleep 0.5
verif "SIGTERM : SteamCMD est arrete avec lui" "" "$(pgrep -f "$F/steamcmd.sh")"
verif "SIGTERM : le jeu n'est pas lance" "" "$(lance)"
verif "SIGTERM : etat echouee, raison interrompue" "echouee interrompue 100" "$(etat 9030 etat) $(etat 9030 raison) $(etat 9030 build_avant)"
verif "SIGTERM : pas d'evenement de lancement" "0" "$(grep -c '"evenement":"lancement"' "$T/evts")"
echo ok >"$F/mode"; sh "$C" play 9030 >/dev/null 2>&1
verif "apres l'arret : le lancement suivant reprend la mise a jour" "200 Jeu.exe 200 appid=9030" "$(build 9030) $(lance)"
# une commande tuee net laisse « en cours » avec un processus mort : ce n'est pas un verrou
printf 'etat=en_cours\npid=999999\nbuild_avant=200\nbuild_vise=300\n' >"$M/9030"; publie 9030 300; sh "$C" updates --refresh >/dev/null 2>&1; raz
m=$(maj_de 9030); verif "processus mort : vu comme une mise a jour interrompue" '"echouee" "interrompue"' "$(champ_json "$m" etat) $(champ_json "$m" raison)"
sh "$C" play 9030 >/dev/null 2>&1
verif "processus mort : le lancement suivant refait la mise a jour" "300 Jeu.exe 300 appid=9030" "$(build 9030) $(lance)"

echo "== 9. cidre dl et cidre rm"
jeu 9040 100; publie 9040 100; sh "$C" updates --refresh >/dev/null 2>&1; raz; publie 9040 200
sortie=$(sh "$C" dl 9040 </dev/null 2>&1); rc=$?
verif "cidre dl : mis a jour (code 0)" "0 200" "$rc $(build 9040)"
verif "cidre dl : avec validate (fichiers reverifies)" "1" "$(appels 'app_update 9040 validate')"
contient "cidre dl : la sortie de SteamCMD passe telle quelle (Verger y lit l'avancement)" " Update state (0x61) downloading, progress: 37.93 (32564012 / 85850313)" "$sortie"
[ ! -e "$A" ] && ok "cidre dl : le cache disait 100, il est jete" || echec "cidre dl : le cache en retard est reste"
verif "apres cidre dl : cidre updates redemande et dit a jour" '1 true "a_jour"' "$(u=$(sh "$C" updates --json | tr '{' '\n' | grep '"appid": 9040,'); echo "$(appels 'login anonymous') $(champ_json "$u" a_jour) $(champ_json "$u" etat)")"
raz; sh "$C" dl 9040 </dev/null >/dev/null 2>&1
[ -s "$A" ] && ok "cidre dl sans changement : le cache, juste, est garde" || echec "cidre dl sans changement : le cache a ete jete"
raz; publie 9041 100; sortie=$(sh "$C" dl 9041 </dev/null 2>&1)
verif "cidre dl d'un nouveau jeu : installe, etat faite" "100 faite" "$(build 9041) $(etat 9041 etat)"
verif "nouveau jeu : cidre updates le voit sans attendre la fin du cache" "1" "$(sh "$C" updates | grep -c '^9041 *a jour$')"
raz; echo sans_session >"$F/mode"
sortie=$(sh "$C" dl 9042 </dev/null 2>&1); rc=$?
verif "cidre dl sans session : code 3, pas de dossier vide, pas d'etat" "3  " "$rc $(ls "$G" | grep 9042) $(ls "$M" | grep 9042)"
contient "cidre dl sans session : le dit" "Session Steam non memorisee : connecte-toi (\`cidre login\`)." "$sortie"
raz; echo coupe >"$F/mode"; publie 9040 300; sh "$C" updates --refresh >/dev/null 2>&1
sortie=$(sh "$C" dl 9040 </dev/null 2>&1); rc=$?
verif "cidre dl qui echoue : son code, et le jeu reste installe" "8 true" "$rc $(sh "$C" list --json | sed -n 's/.*"id":"9040".*"installe":\([a-z]*\).*/\1/p')"
verif "cidre dl qui echoue : la derniere ligne dit la cause et quoi faire" "Mise a jour interrompue : la connexion a Steam a ete perdue (Error! App '9040' state is 0x402 after update job.). Elle reprendra ou elle en etait au prochain lancement." "$(printf '%s\n' "$sortie" | tail -1)"
sh "$C" rm 9040 >/dev/null 2>&1
verif "cidre rm : l'etat de mise a jour part avec le jeu" "" "$(ls "$M" | grep 9040)"

echo "== 10. le cache du client Steam"
# Un appinfo.vdf comme l'ecrit le client (format v28, cles en ligne) : pour
# chaque jeu, appinfo/depots/branches/public/buildid, en entier ou en chaine.
octets() { for o in "$@"; do printf "\\$(printf %03o "$o")"; done; }
le32() { octets $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)); }
fiche_client() { # <appid> <build> [chaine] : une entree, sur la sortie standard
   { octets 0; printf 'appinfo\000'
       octets 2; printf 'appid\000'; le32 "$1"
       octets 0; printf 'depots\000'
         octets 0; printf 'branches\000'
           octets 0; printf 'beta\000'; octets 2; printf 'buildid\000'; le32 999999; octets 8
           octets 0; printf 'public\000'
             if [ -n "${3:-}" ]; then octets 1; printf 'buildid\000%s\000' "$2"; else octets 2; printf 'buildid\000'; le32 "$2"; fi
           octets 8
         octets 8
       octets 8
     octets 8
     octets 8
   } >"$T/corps"
   le32 "$1"; le32 $((60 + $(wc -c <"$T/corps")))
   le32 2; le32 1791900000; octets 0 0 0 0 0 0 0 0
   i=0; while [ $i -lt 20 ]; do octets 0; i=$((i + 1)); done
   le32 42
   i=0; while [ $i -lt 20 ]; do octets 0; i=$((i + 1)); done
   cat "$T/corps"
}
CLIENT="$HOME/Library/Application Support/Steam/appcache/appinfo.vdf"
client() { # <appid>=<build>[:chaine] ... : le cache du client, frais
   mkdir -p "$(dirname "$CLIENT")"
   { le32 $((0x07564428)); le32 1
     for e in "$@"; do b=${e#*=}; case $b in *:chaine) fiche_client "${e%%=*}" "${b%:chaine}" chaine ;; *) fiche_client "${e%%=*}" "$b" ;; esac; done
     le32 0; } >"$CLIENT"
}
O="$R/build/cidre-outil"
client 9050=200 9051=300:chaine 9052=0
verif "cidre-outil builds : entier, chaine, la date ; jeu absent ou sans build : rien" "$(printf '9050\t200\t1791900000\n9051\t300\t1791900000')" "$("$O" builds "$CLIENT" 9050 9051 9052 9053)"
verif "cidre-outil builds : la branche publique, pas une autre" "" "$("$O" builds "$CLIENT" 9050 | grep 999999)"
printf 'pas un cache' >"$T/faux.vdf"
verif "cidre-outil builds : un fichier d'un autre format ne donne rien (code 1)" "1 " "$("$O" builds "$T/faux.vdf" 9050 2>/dev/null; echo "$? $("$O" builds "$T/faux.vdf" 9050 2>/dev/null)")"
head -c 120 "$CLIENT" >"$T/tronque.vdf"
verif "cidre-outil builds : un fichier tronque, code 1" "1" "$("$O" builds "$T/tronque.vdf" 9050 >/dev/null 2>&1; echo $?)"
if [ -s "$VRAI_HOME/Library/Application Support/Steam/appcache/appinfo.vdf" ]; then
   # le vrai cache du client de cette machine, lu sans rien y ecrire
   vrai=$("$O" builds "$VRAI_HOME/Library/Application Support/Steam/appcache/appinfo.vdf" 220 440 570 730 3527290 1903340); rc=$?
   verif "vrai cache du client : lu (code 0)" "0" "$rc"
   verif "vrai cache du client : des lignes « appid, build, date »" "0" "$(printf '%s\n' "$vrai" | grep -v '^$' | grep -cv "^[0-9]*$TAB[0-9]*$TAB[0-9]*$")"
else
   echo "  (pas de client Steam sur cette machine : vrai cache non lu)"
fi
# un jeu en retard que seul le client sait : pas de SteamCMD sans compte, mise a jour faite
jeu 9050 100; publie 9050 200; rm -f "$A"; raz
client 9050=200
sortie=$(sh "$C" play 9050 2>&1)
verif "client frais, cache absent : aucune demande sans compte" "0" "$(appels 'login anonymous')"
verif "client frais : la mise a jour est faite, puis le jeu lance" "200 Jeu.exe 200 appid=9050" "$(build 9050) $(lance)"
raz; sh "$C" play 9050 >/dev/null 2>&1
verif "client frais, jeu a jour : aucun appel a SteamCMD" "0 Jeu.exe 200 appid=9050" "$(wc -l <"$F/appels" | tr -d ' ') $(lance)"
# le client est plus en avance que le cache : le plus grand fait foi
publie 9050 200; sh "$C" updates --refresh >/dev/null 2>&1; client 9050=300; publie 9050 300; raz
sh "$C" play 9050 >/dev/null 2>&1
verif "le client en sait plus que le cache : son build fait foi" "0 300" "$(appels 'login anonymous') $(build 9050)"
# un client ancien ne dispense de rien... sauf s'il tourne et vient de relire
# ses fiches : il ne recrit son cache que quand l'une change
J="$HOME/Library/Application Support/Steam/logs/appinfo_log.txt"; mkdir -p "$(dirname "$J")"
raz; touch -t 202601010000 "$CLIENT"; vieillir
CIDRE_STEAM_TOURNE=false sh "$C" play 9050 >/dev/null 2>&1
verif "client ancien, cache ancien : une demande sans compte" "1" "$(appels 'login anonymous')"
raz; vieillir; echo "[2026-10-14 09:34:07] Apps changed: 1=2," >"$J"
CIDRE_STEAM_TOURNE=true sh "$C" play 9050 >/dev/null 2>&1
verif "cache du client ancien, mais client lance qui vient de relire : aucune demande" "0" "$(appels 'login anonymous')"
raz; vieillir
CIDRE_STEAM_TOURNE=false sh "$C" play 9050 >/dev/null 2>&1
verif "meme journal recent, client ferme : une demande sans compte" "1" "$(appels 'login anonymous')"
raz; vieillir; touch -t 202601010000 "$J"
CIDRE_STEAM_TOURNE=true sh "$C" play 9050 >/dev/null 2>&1
verif "client lance qui n'a pas relu depuis longtemps (hors ligne) : une demande sans compte" "1" "$(appels 'login anonymous')"
printf 'pas un cache' >"$CLIENT"; raz; vieillir; touch "$J"
CIDRE_STEAM_TOURNE=true sh "$C" play 9050 >/dev/null 2>&1
verif "client illisible : ignore, une demande sans compte, le jeu part" "1 Jeu.exe 300 appid=9050" "$(appels 'login anonymous') $(lance)"
# cidre updates : un client frais qui porte tous les jeux dispense de SteamCMD
raz; vieillir
ids=$(ls "$G" | grep -E '^[0-9]+$' | tr '\n' ' ')
# (et le jeu du client Steam de la partie 6)
set -- 9010=200; for i in $ids; do set -- "$@" "$i=$(build "$i")"; done
client "$@"; publie 9050 300
u=$(sh "$C" updates --json)
verif "cidre updates, client frais et complet : aucune demande sans compte" "0" "$(appels 'login anonymous')"
printf '%s' "$u" | plutil -convert json -o /dev/null - 2>/dev/null && ok "cidre updates --json : JSON valide" || echec "cidre updates --json : JSON invalide : $u"
verif "cidre updates : « verifie » est la date du cache du client" "$(stat -f %m "$CLIENT")" "$(champ_json "$(printf '%s' "$u" | tr '{' '\n' | grep '"appid": 9050,')" verifie)"
# --fond : la main revient tout de suite ; une seule demande a la fois
rm -f "$CLIENT"; raz; vieillir; echo 2 >"$F/lent"
debut=$(date +%s); sh "$C" updates --fond; rc=$?; duree=$(( $(date +%s) - debut ))
verif "--fond : code 0, sans attendre SteamCMD" "0 0" "$rc $duree"
sh "$C" updates --fond
i=0; while [ $i -lt 40 ] && [ -n "$(find "$A" -mmin +1)" ]; do sleep 0.25; i=$((i + 1)); done
[ -z "$(find "$A" -mmin +1)" ] && ok "--fond : le cache est refait en arriere-plan" || echec "--fond : le cache n'a pas ete refait"
sleep 1
verif "deux --fond coup sur coup : une seule demande a SteamCMD (verrou)" "1" "$(appels 'login anonymous')"
verif "le verrou est rendu" "" "$(ls -d "$A.verrou" 2>/dev/null)"
raz; sh "$C" updates --fond
verif "--fond, cache frais : rien n'est demande" "0" "$(sleep 1; appels 'login anonymous')"
# une verification abandonnee (trop lente) ne laisse rien derriere elle
raz; vieillir; echo 3 >"$F/lent"
CIDRE_MAJ_BUDGET=1 sh "$C" play 9050 >/dev/null 2>&1
sleep 4
verif "verification abandonnee : ni .rc ni .abandon laisses dans le cache" "" "$(ls "$(dirname "$A")" | grep -e '\.rc\.' -e abandon)"
rm -f "$F/lent"

echo "== 11. syntaxe, aide, documentation"
for f in cidre tests/tester_maj_avant_lancement.sh; do
   sh -n "$R/$f" 2>/dev/null && ok "sh -n $f" || echec "sh -n $f"
done
LC_ALL=C awk -v paires="1=5 2=7 3=9" -f "$R/tests/majs_steam.awk" "$A" >/dev/null 2>&1 && ok "majs_steam.awk s'execute" || echec "majs_steam.awk en erreur"
verif "cidre help : rien sur la sortie d'erreur" "" "$(sh "$C" help 2>&1 >/dev/null)"
verif "cidre help : --sans-maj documente" "1" "$(sh "$C" help 2>/dev/null | grep -c '^  cidre play <id> \[--sans-maj\]')"
verif "cidre help : --fond documente" "1" "$(sh "$C" help 2>/dev/null | grep -c '^  cidre updates .*\[--fond\]')"
verif "outil-steam/profils.toml : option documentee et livree" "2" "$(grep -c -e '^#   maj_avant_lancement ' -e '^maj_avant_lancement = true$' "$R/outil-steam/profils.toml")"
verif "profils/README.md : option documentee" "1" "$(grep -c '^### Mise à jour avant le lancement' "$R/profils/README.md")"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
