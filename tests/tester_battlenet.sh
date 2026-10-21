#!/bin/sh
# Teste les jeux Battle.net de Cidre (tests/battlenet.sh, `cidre list/info/play/
# rm` sur un id bnet-*) sur un prefixe fabrique : registre avec les cles
# Uninstall de l'Agent, client et jeux factices. Rien n'est lance, ni Wine ni
# Battle.net ; le dossier de Cidre de l'utilisateur n'est pas touche.
#   sh tests/tester_battlenet.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
B="$R/tests/battlenet.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-battlenet.XXXXXX")
trap 'rm -rf "$T"' EXIT
# (chemin reel : cidre compare les chemins des disques a /Volumes resolu)
T=$(cd "$T" && pwd -P)
export CIDRE_DIR="$T/cidre" CIDRE_SAVES_DIR="$T/copies" CIDRE_VOLUMES="$T/Volumes"
mkdir -p "$CIDRE_DIR" "$CIDRE_VOLUMES"
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
absent() { # <libelle> <motif> <texte>
   case $3 in *"$2"*) echec "$1 : « $2 » present dans « $3 »" ;; *) ok "$1" ;; esac
}

# --- le prefixe fabrique -----------------------------------------------------
P="$T/pfx-battlenet"; export CIDRE_BNET_PREFIXE="$P"
PF="$P/drive_c/Program Files (x86)"
mkdir -p "$PF/Battle.net" "$PF/Diablo II Resurrected" "$PF/Truc" "$P/dosdevices" "$T/disque-d/Jeux/Diablo IV" \
   "$P/drive_c/users/joueur/AppData/Roaming/Battle.net" "$P/drive_c/users/joueur/Saved Games/Diablo II Resurrected"
ln -s "$T/disque-d" "$P/dosdevices/d:"
printf 'MZ' >"$PF/Battle.net/Battle.net.exe"
printf 'MZ' >"$PF/Diablo II Resurrected/D2R.exe"
dd if=/dev/zero of="$PF/Diablo II Resurrected/data.casc" bs=1024 count=64 2>/dev/null
printf 'MZ' >"$PF/Truc/Truc.exe"
printf 'MZ' >"$T/disque-d/Jeux/Diablo IV/Diablo IV.exe"
printf 'perso' >"$P/drive_c/users/joueur/Saved Games/Diablo II Resurrected/Lucas.d2s"
U='\\"C:\\\\ProgramData\\\\Battle.net\\\\Agent\\\\Blizzard Uninstaller.exe\\" --lang=frFR'
cat >"$P/system.reg" <<EOF
WINE REGISTRY Version 2

[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Steam] 1792100000
"DisplayName"="Steam"
"InstallLocation"="C:\\\\Program Files (x86)\\\\Steam"
"Publisher"="Valve Corporation"
"UninstallString"="C:\\\\Program Files (x86)\\\\Steam\\\\uninstall.exe"

[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Battle.net] 1792338696
"DisplayIcon"="C:\\\\Program Files (x86)\\\\Battle.net\\\\Battle.net.exe"
"DisplayName"="Battle.net"
"InstallLocation"="C:\\\\Program Files (x86)\\\\Battle.net"
"Publisher"="Blizzard Entertainment"
"UninstallString"="$U --uid=battle.net --displayname=\\"Battle.net\\""

[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Diablo II Resurrected] 1792404867
"DisplayIcon"="C:\\\\Program Files (x86)\\\\Diablo II Resurrected\\\\D2R.exe"
"DisplayName"="Diablo II Resurrected"
"InstallLocation"="C:\\\\Program Files (x86)\\\\Diablo II Resurrected"
"Publisher"="Blizzard Entertainment"
"UninstallString"="$U --uid=osi --displayname=\\"Diablo II Resurrected\\""

[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Diablo IV] 1792404900
"DisplayName"="Diablo IV"
"InstallLocation"="D:\\\\Jeux\\\\Diablo IV\\\\"
"Publisher"="Blizzard Entertainment"
"UninstallString"="$U --uid=fenris --displayname=\\"Diablo IV\\""

[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Truc] 1792404950
"DisplayIcon"="C:\\\\Program Files (x86)\\\\Truc\\\\Truc.exe"
"DisplayName"="Truc de Blizzard"
"InstallLocation"="C:\\\\Program Files (x86)\\\\Truc"
"Publisher"="Blizzard Entertainment"
"UninstallString"="$U --uid=truc --displayname=\\"Truc\\""

[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Diablo II Resurrected] 1792404867
"InstallLocation"="C:\\\\Program Files (x86)\\\\Diablo II Resurrected"
"UninstallString"="$U --uid=osi"
EOF
CFG="$P/drive_c/users/joueur/AppData/Roaming/Battle.net/Battle.net.config"
printf '{\n    "Client": {\n        "GameLaunchWindowBehavior": "2",\n        "AutoLogin": "true"\n    }\n}\n' >"$CFG"
champ() { sh "$B" jeux | awk -F'\t' -v i="$1" -v n="$2" '$1 == i { print $n }'; }

echo "== battlenet.sh jeux : les cles Uninstall de l'Agent"
verif "ids (ni le client, ni Steam, sans doublon)" "bnet-osi bnet-fen bnet-truc" "$(sh "$B" jeux | cut -f1 | paste -sd ' ' -)"
verif "nom de la table" "Diablo II: Resurrected" "$(champ bnet-osi 2)"
verif "dossier C:" "$PF/Diablo II Resurrected" "$(champ bnet-osi 3)"
verif "code" "OSI" "$(champ bnet-osi 4)"
verif "uid" "osi" "$(champ bnet-osi 5)"
verif "executable de la table" "$PF/Diablo II Resurrected/D2R.exe" "$(champ bnet-osi 6)"
verif "taille (octets, par 1 Kio)" 1 "$([ "$(champ bnet-osi 7)" -ge 65536 ] && echo 1)"
verif "dossier D: (dosdevices, sans barre finale)" "$P/dosdevices/d:/Jeux/Diablo IV" "$(champ bnet-fen 3)"
verif "D4 : code Fen" "Fen" "$(champ bnet-fen 4)"
verif "uid inconnu : nom du registre" "Truc de Blizzard" "$(champ bnet-truc 2)"
verif "uid inconnu : pas de code" "" "$(champ bnet-truc 4)"
verif "uid inconnu : executable de DisplayIcon" "$PF/Truc/Truc.exe" "$(champ bnet-truc 6)"
verif "sans prefixe : aucun jeu" "" "$(CIDRE_BNET_PREFIXE="$T/rien" sh "$B" jeux)"

echo "== prefixe et etat"
verif "prefixe : CIDRE_BNET_PREFIXE" "$P" "$(sh "$B" prefixe)"
printf '%s\n' "$T/ailleurs" >"$CIDRE_DIR/battlenet.prefixe"
verif "prefixe : battlenet.prefixe" "$T/ailleurs" "$(CIDRE_BNET_PREFIXE= sh "$B" prefixe)"
rm -f "$CIDRE_DIR/battlenet.prefixe"
verif "prefixe : defaut" "$R/wine/pfx-battlenet" "$(CIDRE_BNET_PREFIXE= sh "$B" prefixe)"
CIDRE_BNET_PREFIXE= sh "$B" prefixe "$T/rien" >/dev/null 2>&1; verif "prefixe <chemin> : dossier absent refuse" 1 $?
mkdir -p "$T/vide"; CIDRE_BNET_PREFIXE= sh "$B" prefixe "$T/vide" >/dev/null 2>&1; verif "prefixe <chemin> : sans client refuse" 1 $?
CIDRE_BNET_PREFIXE= sh "$R/cidre" battlenet prefixe "$P" >/dev/null
verif "prefixe <chemin> : retenu" "$P" "$(CIDRE_BNET_PREFIXE= sh "$B" prefixe)"
CIDRE_BNET_PREFIXE= sh "$B" prefixe defaut >/dev/null
verif "prefixe defaut : oublie" "$R/wine/pfx-battlenet" "$(CIDRE_BNET_PREFIXE= sh "$B" prefixe)"
e=$(sh "$B" etat --json)
contient "etat : installe" '"installe":true' "$e"
contient "etat : ferme" '"ouvert":false,"pour":null,"jeu":null' "$e"
contient "etat : trois jeux" '"jeux":3' "$e"
contient "etat sans client" '"installe":false' "$(CIDRE_BNET_PREFIXE="$T/rien" sh "$B" etat --json)"
verif "pids : serveur arrete, rien" "" "$(sh "$B" pids)"

echo "== preparer et jouer, client ferme"
r=$(sh "$B" preparer bnet-osi); rc=$?
verif "preparer : code 0" 0 "$rc"
contient "preparer : GameLaunchWindowBehavior remis" "2 -> 0" "$r"
contient "Battle.net.config : 0" '"GameLaunchWindowBehavior": "0"' "$(cat "$CFG")"
contient "Battle.net.config : le reste garde" '"AutoLogin": "true"' "$(cat "$CFG")"
verif "preparer : rien la seconde fois" "" "$(sh "$B" preparer bnet-osi)"
# la cle Run du client : wineboot ouvrirait le client hors du jeu
printf 'WINE REGISTRY Version 2\n\n[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run] 1792338725\n"Battle.net"="\\"C:\\\\Program Files (x86)\\\\Battle.net\\\\Battle.net.exe\\" --autostarted"\n"Autre"="autre.exe"\n' >"$P/user.reg"
r=$(sh "$B" preparer bnet-osi)
contient "preparer : demarrage automatique retire" "demarrage automatique du client retire" "$r"
absent "user.reg : plus de Battle.net sous Run" '"Battle.net"=' "$(cat "$P/user.reg")"
contient "user.reg : les autres valeurs gardees" '"Autre"="autre.exe"' "$(cat "$P/user.reg")"
verif "preparer : rien a retirer ensuite" "" "$(sh "$B" preparer bnet-osi)"
sh "$B" jouer bnet-truc >/dev/null; verif "jouer sans code : 2" 2 $?
CIDRE_BNET_PREFIXE="$T/rien" sh "$B" preparer bnet-osi >/dev/null 2>&1; verif "preparer sans client : 5" 5 $?
verif "arreter sans client ouvert" "Battle.net n'etait pas ouvert." "$(sh "$B" arreter)"

# Facultatif (CIDRE_ESSAI_PROCESSUS=1), et seulement sur une machine ou rien ne
# tourne sous Wine : les faux processus portent des noms Windows et un faux
# wineserver, que les manches d'autres sessions pourraient voir ou arreter.
if [ "${CIDRE_ESSAI_PROCESSUS:-}" != 1 ]; then
   echo "== jouer : client et jeu factices -- saute (CIDRE_ESSAI_PROCESSUS=1 pour l'essayer)"
elif pgrep -x wineserver >/dev/null 2>&1 || ps -axo comm= | grep -qi '\.exe'; then
   echo "== jouer : client et jeu factices -- saute : un wineserver ou un programme Windows tourne deja"
else
echo "== jouer : client et jeu factices (processus nommes comme sous Wine, serveur du prefixe simule)"
# un jeu d'essai, au nom que rien d'autre ne porte
mkdir -p "$PF/Essai" && printf 'MZ' >"$PF/Essai/CidreEssai.exe"
{ cat "$R/outil-steam/battlenet.conf"; printf 'essai\tESSAI\tCidreEssai.exe\tEssai Cidre\n'; } >"$T/battlenet.conf"
printf '\n[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\Essai] 1\n"InstallLocation"="C:\\\\Program Files (x86)\\\\Essai"\n"UninstallString"="%s --uid=essai"\n' "$U" >>"$P/system.reg"
export CIDRE_BNET_TABLE="$T/battlenet.conf"
# Un « wineserver » (pgrep -x) et la socket du serveur du prefixe ; le client et
# le jeu sont des `sleep` qui portent le nom Windows de leur executable et
# tiennent un fichier du dossier du serveur, comme les processus de Wine.
SRV=/tmp/.wine-$(id -u)/server-$(stat -f '%Xd-%Xi' "$P")
mkdir -p "$T/bin" "$SRV" && cp /bin/sleep "$T/bin/wineserver" && touch "$SRV/lock"
# (une copie de /bin/sleep sans signature est tuee par macOS au lancement : la re-signer)
codesign -f -s - "$T/bin/wineserver" 2>/dev/null
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$SRV/socket"
"$T/bin/wineserver" 300 & FAUX_SERVEUR=$!
# (les faux processus par leur pid : leur ligne de commande ne dit pas $T)
faux_arreter() { kill $(cat "$T/client.pid" "$T/jeux.pid" 2>/dev/null) 2>/dev/null; rm -f "$T/client.pid" "$T/jeux.pid"; }
trap 'faux_arreter; kill $FAUX_SERVEUR 2>/dev/null; rm -rf "$SRV" "$T"' EXIT
cat >"$T/etape2.sh" <<'FIN'
#!/bin/sh
# etape2_pile_arm64ec.sh factice : note ses arguments, ouvre le « client » s'il ne
# l'est pas -- avec, comme sous Wine, le start.exe qui l'ouvre et l'Agent (chemin a
# barres obliques), qui ne sont pas des jeux -- puis lance le « jeu » une seconde
# plus tard (CIDRE_ESSAI_JEU s) -- ou rien (CIDRE_ESSAI_JEU=0).
printf '%s|' "$@" >>"$CIDRE_ESSAI/args"; echo >>"$CIDRE_ESSAI/args"
if ! kill -0 "$(cat "$CIDRE_ESSAI/client.pid" 2>/dev/null)" 2>/dev/null; then
   /bin/bash -c 'exec -a "C:\Program Files (x86)\Battle.net\Battle.net.exe" /bin/sleep '"${CIDRE_ESSAI_CLIENT:-120}"' 3<"$0/lock"' "$CIDRE_ESSAI_SRV" &
   echo $! >"$CIDRE_ESSAI/client.pid"
   /bin/bash -c 'exec -a "start.exe" /bin/sleep '"${CIDRE_ESSAI_CLIENT:-120}"' 3<"$0/lock"' "$CIDRE_ESSAI_SRV" &
   echo $! >>"$CIDRE_ESSAI/jeux.pid"
   /bin/bash -c 'exec -a "C:/ProgramData/Battle.net/Agent/Agent.9824/Agent.exe" /bin/sleep '"${CIDRE_ESSAI_CLIENT:-120}"' 3<"$0/lock"' "$CIDRE_ESSAI_SRV" &
   echo $! >>"$CIDRE_ESSAI/jeux.pid"
fi
[ "${CIDRE_ESSAI_JEU:-8}" = 0 ] && exit 0
sleep 1
/bin/bash -c 'exec -a "C:\Program Files (x86)\Essai\CidreEssai.exe" /bin/sleep '"${CIDRE_ESSAI_JEU:-8}"' 3<"$0/lock"' "$CIDRE_ESSAI_SRV" &
echo $! >>"$CIDRE_ESSAI/jeux.pid"
FIN
export CIDRE_BNET_ETAPE2="$T/etape2.sh" CIDRE_ESSAI="$T" CIDRE_ESSAI_SRV="$SRV"
J="$T/journal.log"
sh "$B" jouer bnet-essai >"$J" 2>&1; rc=$?
verif "jouer : code 0" 0 "$rc"
contient "jouer : client ouvert" "ouverture du client" "$(cat "$J")"
contient "jouer : jeu vu" "CidreEssai.exe demarre apres" "$(cat "$J")"
contient "jouer : jeu sorti, client garde" "CidreEssai.exe sorti apres" "$(cat "$J")"
verif "jouer : arguments du client" 'C:\Program Files (x86)\Battle.net\Battle.net.exe|--in-process-gpu|--exec=launch ESSAI|' "$(head -1 "$T/args")"
verif "marque : pour" "pour=bnet-essai" "$(head -1 "$P/.cidre-client")"
e=$(sh "$B" etat --json)
contient "etat : client ouvert pour le jeu" '"ouvert":true,"pour":"bnet-essai","jeu":null' "$e"
contient "pids : le client" " $(cat "$T/client.pid") " " $(sh "$B" pids | tr '\n' ' ') "
verif "pids : client, start.exe et Agent" 3 "$(sh "$B" pids | wc -l | tr -d ' ')"
contient "jouer : start.exe et l'Agent ne sont pas le jeu" "CidreEssai.exe demarre apres" "$(grep demarre "$J")"
verif "preparer : meme jeu, client garde" "    battlenet : client deja ouvert pour ce jeu" "$(sh "$B" preparer bnet-essai)"
sh "$B" jouer bnet-essai >"$J" 2>&1; rc=$?
verif "jouer 2 : code 0" 0 "$rc"
contient "jouer 2 : client garde, lancement demande" "client deja ouvert pour ce jeu, lancement de ESSAI demande" "$(cat "$J")"
verif "jouer 2 : un seul client" 1 "$(sh "$B" etat | grep -c 'ouvert')"
# un jeu en cours : ni preparer, ni arreter
CIDRE_ESSAI_JEU=20 sh "$T/etape2.sh" x; sleep 2
sh "$B" preparer bnet-fen >/dev/null; verif "preparer pendant un jeu : 4" 4 $?
sh "$B" arreter >/dev/null 2>&1; verif "arreter pendant un jeu : 4" 4 $?
contient "etat : en jeu (sans pid, sans start.exe ni Agent)" '"jeu":"CidreEssai.exe"' "$(sh "$B" etat --json)"
faux_arreter; rm -f "$P/.cidre-client"; sleep 1
# un client qui se ferme sans lancer le jeu
CIDRE_ESSAI_JEU=0 CIDRE_ESSAI_CLIENT=3 sh "$B" jouer bnet-essai >"$J" 2>&1; rc=$?
verif "client ferme avant le jeu : 6" 6 "$rc"
contient "client ferme avant le jeu : message" "s'est ferme avant CidreEssai.exe" "$(cat "$J")"
unset CIDRE_BNET_TABLE CIDRE_BNET_ETAPE2
fi

echo "== cidre list / info : la source battlenet"
C="$R/cidre"
l=$(sh "$C" list --json)
contient "list : bnet-osi" '{"id":"bnet-osi","appid":null,"nom":"Diablo II: Resurrected","plateforme":"windows","lancement":"cidre","source":"battlenet","installe":true,"wrapper":null' "$l"
contient "list : en ligne" '"emplacement":null,"en_ligne":true' "$(printf '%s\n' "$l" | grep '"bnet-osi"')"
contient "list : bnet-fen (disque D:)" '"id":"bnet-fen"' "$l"
# le contrat des jeux Steam : les memes lignes, qu'il y ait des jeux Battle.net ou non
norm() { grep -v '"bnet-' | sed 's/},$/}/'; }
# (avec le dossier de Cidre de l'utilisateur, lu seulement : ses jeux Cidre)
sans=$(CIDRE_DIR= CIDRE_BNET_PREFIXE="$T/rien" sh "$C" list --json | norm)
verif "list : jeux Steam inchanges" "$sans" "$(CIDRE_DIR= sh "$C" list --json | norm)"
contient "list : des jeux Steam ou Cidre" '"appid":' "$sans"
i=$(sh "$C" info bnet-osi --json)
contient "info : source" '"source":"battlenet"' "$i"
contient "info : fiche livree" '"lanceur":"battlenet"' "$i"
contient "info : options de la fiche" '"knowndlls":"d3d12 d3d12core"' "$i"
contient "info : sauvegardes connues" '"sauvegardes":true' "$i"
contient "list texte" "Cidre (Battle.net)" "$(sh "$C" list)"
contient "info fen : fiche D4" '"exe":"Diablo IV.exe"' "$(sh "$C" info bnet-fen --json)"
sh "$C" info bnet-inconnu >/dev/null 2>&1; verif "info : id inconnu" 1 $?

echo "== cidre rm / play"
r=$(sh "$C" rm bnet-osi 2>&1); rc=$?
verif "rm : refuse" 1 "$rc"
contient "rm : par le client" "depuis le client" "$r"
[ -f "$PF/Diablo II Resurrected/D2R.exe" ] && ok "rm : jeu intact" || echec "rm : jeu efface"
r=$(sh "$C" play bnet-truc 2>&1); rc=$?
verif "play sans code : 1" 1 "$rc"
contient "play sans code : message" "code de lancement" "$r"

echo "== disque debranche"
mkdir -p "$T/Volumes/SSK/Jeux/D2R"
rm -rf "$PF/Diablo II Resurrected"; ln -s "$T/Volumes/SSK/Jeux/D2R" "$PF/Diablo II Resurrected"
printf 'MZ' >"$T/Volumes/SSK/Jeux/D2R/D2R.exe"
contient "branche : en ligne" '"en_ligne":true' "$(sh "$C" list --json | grep '"bnet-osi"')"
rm -rf "$T/Volumes/SSK"
l=$(sh "$C" list --json | grep '"bnet-osi"')
contient "debranche : en ligne false" '"en_ligne":false' "$l"
contient "debranche : toujours windows" '"plateforme":"windows"' "$l"
r=$(sh "$C" play bnet-osi --json 2>/dev/null); rc=$?
verif "play debranche : code 8" 8 "$rc"
contient "play debranche : evenement" '"code":"hors_ligne"' "$r"
contient "play debranche : le disque" "SSK" "$r"

echo "== sauvegardes dans le prefixe Battle.net"
s=$(WINEPREFIX="$T/autre-prefixe" sh "$R/tests/sync_saves_steam.sh" bnet-osi etat)
contient "saves : ligne livree" '"configure":true' "$s"
contient "saves : un fichier dans le prefixe Battle.net" '"local":{"fichiers":1' "$s"
WINEPREFIX="$T/autre-prefixe" sh "$R/tests/sync_saves_steam.sh" bnet-osi backup >/dev/null 2>&1
[ -f "$T/copies/bnet-osi/Lucas.d2s" ] && ok "saves : copie faite" || echec "saves : copie absente ($(find "$T/copies" -type f | head -3))"

echo "== livraison"
grep -q 'battlenet.sh' "$R/tests/empaqueter_runtime.sh" && ok "empaqueter : battlenet.sh" || echec "empaqueter : battlenet.sh absent"
grep -q 'battlenet.conf' "$R/tests/empaqueter_runtime.sh" && ok "empaqueter : battlenet.conf" || echec "empaqueter : battlenet.conf absent"
verif "enveloppe : derniere ligne" "}" "$(tail -1 "$B")"

echo "$nb verifications, $ko echec(s)"
[ $ko -eq 0 ]
