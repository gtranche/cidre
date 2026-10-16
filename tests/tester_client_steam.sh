#!/bin/sh
# Teste tests/client_steam_natif.sh contre un faux client Steam : un dossier
# temporaire avec son journal de connexion, un temoin « il tourne », et une
# commande d'ouverture qui ecrit dans ce journal ce que le vrai client y ecrit
# (releve sur le M4 le 2026-10-12). Ni le vrai client ni son dossier ne sont
# touches, et rien n'est lance : le masquage de sa fenetre et la mesure de son
# processeur sont remplaces eux aussi (CIDRE_STEAM_MASQUER, CIDRE_STEAM_CPU) ;
# la mesure, elle, est essayee sur un processus du test (CIDRE_STEAM_PID).
#   sh tests/tester_client_steam.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S="$R/tests/client_steam_natif.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-client-steam.XXXXXX")
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}

export CIDRE_STEAM_DIR="$T/Steam" CIDRE_STEAM_APP="$T/nulle-part/Steam.app"
export CIDRE_STEAM_TOURNE="test -f '$T/tourne'"
# par defaut : pas de fenetre a masquer, un client qui ne mange rien
export CIDRE_STEAM_MASQUER="echo sans_fenetre" CIDRE_STEAM_CPU=0
unset CIDRE_STEAM_LAISSER_FENETRE CIDRE_STEAM_PID CIDRE_STEAM_CPU_SEUIL CIDRE_STEAM_CPU_FENETRE CIDRE_STEAM_CPU_AGE_MIN
JC="$CIDRE_STEAM_DIR/logs/connection_log.txt"
# ce que le client ecrit : un arret propre, puis un demarrage jusqu'a la connexion
arret() { echo "[2026-10-10 21:46:19] [Logged Off, 0, 0] [U:1:1] ConnectionDisconnected() not auto reconnecting due to user initiated logoff
[2026-10-10 21:46:20] [Logged Off, 0, 0] [U:1:1] Log session ended"; }
demarrage() { echo "[2026-10-12 13:00:35] Client version: 1788652215
[2026-10-12 13:00:35] [Logged Off, 0, 0] [U:1:0] CCMInterface::SetSteamID( [U:1:0] )
[2026-10-12 13:00:36] Connectivity test: result=Connected (since 0.0s ago), prev=Unknown, in progress=0
[2026-10-12 13:00:55] [Logged Off, 4, 0] [U:1:1] LogOn() called; not connected yet, scheduling connection."; }
connexion() { echo "[2026-10-12 13:01:02] [Connecting, 4, 0] [U:1:1] PingWebSocketCM() (ext1-par1.steamserver.net:443) starting...
[2026-10-12 13:01:03] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'
[2026-10-12 13:01:03] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
[2026-10-12 13:01:03] CClientJobGetClientUpdateHosts: cached copy new expiration: Wed Oct 14 20:33:54 2026"; }
remise() { # <installe oui|non> : un client ferme, journal d'une session passee
   rm -rf "$T/Steam" "$T/tourne"; mkdir -p "$CIDRE_STEAM_DIR/logs"
   [ "$1" = oui ] && mkdir -p "$CIDRE_STEAM_DIR/Steam.AppBundle"
   { demarrage; connexion; arret; } >"$JC"
}
# la commande d'ouverture du faux client, ecrite dans un script (elle part en fond)
ouvreur() { # <corps>
   printf '#!/bin/sh\nJC="%s"\nT="%s"\n%s\n' "$JC" "$T" "$1" >"$T/ouvrir.sh"
   export CIDRE_STEAM_OUVRIR="sh '$T/ouvrir.sh'"
}
DEM=$(demarrage); CON=$(connexion)

echo "== 1. l'etat, en un mot"
remise non; unset CIDRE_STEAM_OUVRIR
verif "ni dossier ni application : absent" "absent" "$(sh "$S")"
sortie=$(sh "$S" assurer 2); rc=$?
verif "absent : assurer rend 2" "2" "$rc"
contient "absent : il le dit" "pas installe" "$sortie"
remise oui
verif "installe, pas lance : ferme" "ferme" "$(sh "$S")"
touch "$T/tourne"
verif "lance, derniere ligne Logged Off : ouvert" "ouvert" "$(sh "$S")"
{ demarrage; connexion; } >>"$JC"
verif "lance, derniere ligne d'etat Logged On : connecte" "connecte" "$(sh "$S")"
echo "[2026-10-12 13:04:00] [Logged Off, 0, 0] [U:1:0] CCMInterface::SetSteamID( [U:1:0] )" >>"$JC"
verif "lance, puis une ligne du compte 0 (pont steamclient) : toujours connecte" "connecte" "$(sh "$S")"
echo "[2026-10-12 13:05:00] [Connecting, 4, 0] [U:1:1] reconnexion" >>"$JC"
verif "lance, en reconnexion : ouvert" "ouvert" "$(sh "$S")"

echo "== 2. deja connecte : rien a faire, rien d'ecrit"
remise oui; touch "$T/tourne"; { demarrage; connexion; } >>"$JC"
ouvreur 'touch "$T/ouvert-a-tort"'
sortie=$(sh "$S" assurer 5); rc=$?
verif "code 0" "0" "$rc"
verif "aucune ligne" "" "$sortie"
verif "pas rouvert" "" "$(ls "$T" | grep ouvert-a-tort)"

echo "== 3. ferme : ouvert, puis attendu jusqu'a sa connexion"
remise oui
ouvreur "touch \"\$T/tourne\"; ( sleep 2; cat >>\"\$JC\" <<'FIN'
$DEM
$CON
FIN
) >/dev/null 2>&1 &"
debut=$(date +%s); sortie=$(sh "$S" assurer 20); rc=$?; duree=$(( $(date +%s) - debut ))
verif "code 0" "0" "$rc"
contient "il dit qu'il l'a ouvert" "etait ferme, ouvert par Cidre en arriere-plan, connecte apres" "$sortie"
[ "$duree" -ge 2 ] && [ "$duree" -le 8 ] && ok "a attendu la connexion ($duree s), pas le delai entier" || echec "duree $duree s"
verif "etat ensuite : connecte" "connecte" "$(sh "$S")"

echo "== 4. ferme apres un arret brutal : le « Logged On » de la session passee ne compte pas"
remise oui; { demarrage; connexion; } >"$JC"       # derniere ligne d'etat : Logged On, client mort
verif "pas lance : ferme, quoi que dise le journal" "ferme" "$(sh "$S")"
ouvreur "touch \"\$T/tourne\"; ( sleep 3; cat >>\"\$JC\" <<'FIN'
$DEM
$CON
FIN
) >/dev/null 2>&1 &"
debut=$(date +%s); sortie=$(sh "$S" assurer 20); rc=$?; duree=$(( $(date +%s) - debut ))
verif "code 0" "0" "$rc"
[ "$duree" -ge 3 ] && ok "a attendu la nouvelle connexion ($duree s)" || echec "n'a pas attendu : $duree s (« $sortie »)"

echo "== 5. ferme, ouvert, jamais connecte (fenetre de connexion)"
remise oui
ouvreur "touch \"\$T/tourne\"; cat >>\"\$JC\" <<'FIN'
$DEM
FIN"
sortie=$(sh "$S" assurer 3); rc=$?
verif "code 1" "1" "$rc"
contient "il dit quoi faire" "pas connecte apres 3 s" "$sortie"

echo "== 6. deja ouvert mais pas connecte : attente courte"
remise oui; touch "$T/tourne"; ouvreur 'touch "$T/ouvert-a-tort"'
debut=$(date +%s); sortie=$(sh "$S" assurer 90); rc=$?; duree=$(( $(date +%s) - debut ))
verif "code 1" "1" "$rc"
contient "il le dit" "deja ouvert, mais pas connecte apres 15 s" "$sortie"
[ "$duree" -le 20 ] && ok "15 s au plus, pas 90 ($duree s)" || echec "duree $duree s"
verif "pas rouvert" "" "$(ls "$T" | grep ouvert-a-tort)"

echo "== 6 bis. deja ouvert en mode hors ligne voulu : ni attente ni reproche"
remise oui; touch "$T/tourne"; mkdir -p "$CIDRE_STEAM_DIR/config"
printf '"users"\n{\n\t"1"\n\t{\n\t\t"AccountName"\t\t"x"\n\t\t"WantsOfflineMode"\t\t"1"\n\t}\n}\n' >"$CIDRE_STEAM_DIR/config/loginusers.vdf"
debut=$(date +%s); sortie=$(sh "$S" assurer 90); rc=$?; duree=$(( $(date +%s) - debut ))
verif "code 0" "0" "$rc"
verif "aucune ligne" "" "$sortie"
[ "$duree" -le 2 ] && ok "sans attente ($duree s)" || echec "duree $duree s"

echo "== 7. l'ouverture echoue"
remise oui; ouvreur 'exit 1'
sortie=$(sh "$S" assurer 3); rc=$?
verif "code 2" "2" "$rc"
contient "il dit de l'ouvrir a la main" "a la main" "$sortie"

echo "== 8. le journal de connexion tourne pendant l'attente"
remise oui
ouvreur "touch \"\$T/tourne\"; ( sleep 2; mv \"\$JC\" \"\$JC.previous\"; cat >\"\$JC\" <<'FIN'
$CON
FIN
) >/dev/null 2>&1 &"
sortie=$(sh "$S" assurer 20); rc=$?
verif "code 0" "0" "$rc"

echo "== 9. pas de journal du tout (client jamais lance) : pas d'erreur, pas connecte"
remise oui; rm -f "$JC"; touch "$T/tourne"
verif "etat : ouvert" "ouvert" "$(sh "$S" 2>&1)"

# un masqueur qui laisse une trace, et rend <resultat>
masqueur() { export CIDRE_STEAM_MASQUER="touch '$T/masque-appele'; echo $1"; rm -f "$T/masque-appele"; }
masque_appele() { [ -f "$T/masque-appele" ] && echo oui || echo non; }

echo "== 11. ferme : ouvert avec -silent, sans premier plan (la vraie commande, open intercepte)"
remise oui; unset CIDRE_STEAM_OUVRIR
mkdir -p "$T/bin"
cat >"$T/bin/open" <<FIN
#!/bin/sh
echo "\$*" >>"$T/open.args"
touch "$T/tourne"; cat >>"$JC" <<'J'
$DEM
$CON
J
FIN
chmod +x "$T/bin/open"; rm -f "$T/open.args"
sortie=$(PATH="$T/bin:$PATH" sh "$S" assurer 10); rc=$?
verif "code 0" "0" "$rc"
verif "open -g -b com.valvesoftware.steam --args -silent" "-g -b com.valvesoftware.steam --args -silent" "$(cat "$T/open.args" 2>/dev/null)"
contient "il le dit" "ouvert par Cidre en arriere-plan, connecte apres" "$sortie"

echo "== 12. fenetre de Steam : masquee une fois connecte, jamais avant"
remise oui; touch "$T/tourne"; { demarrage; connexion; } >>"$JC"
masqueur masque; sortie=$(sh "$S" assurer 5); rc=$?
verif "connecte, fenetre visible : code 0" "0" "$rc"
verif "connecte : masqueur appele" "oui" "$(masque_appele)"
contient "il le dit, et qu'il reste ouvert" "fenetre masquee (il reste ouvert et connecte" "$sortie"
masqueur sans_fenetre; sortie=$(sh "$S" assurer 5)
verif "pas de fenetre a l'ecran : rien d'ecrit" "" "$sortie"
masqueur echec; sortie=$(sh "$S" assurer 5); rc=$?
verif "masquage impossible : code 0 quand meme" "0" "$rc"
contient "masquage impossible : il dit quoi faire" "Cmd-H" "$sortie"
masqueur masque; sortie=$(CIDRE_STEAM_LAISSER_FENETRE=1 sh "$S" assurer 5)
verif "CIDRE_STEAM_LAISSER_FENETRE=1 : masqueur pas appele" "non" "$(masque_appele)"
verif "CIDRE_STEAM_LAISSER_FENETRE=1 : rien d'ecrit" "" "$sortie"
remise oui; ouvreur "touch \"\$T/tourne\"; cat >>\"\$JC\" <<'FIN'
$DEM
$CON
FIN"
masqueur masque; sortie=$(sh "$S" assurer 10)
verif "ouvert par Cidre puis connecte : masqueur appele (au cas ou)" "oui" "$(masque_appele)"
remise oui; touch "$T/tourne"; masqueur masque
sortie=$(sh "$S" assurer 2)
verif "ouvert, pas connecte (fenetre de connexion) : pas masque" "non" "$(masque_appele)"
remise oui; touch "$T/tourne"; mkdir -p "$CIDRE_STEAM_DIR/config"; masqueur masque
printf '"users"\n{\n\t"1"\n\t{\n\t\t"WantsOfflineMode"\t\t"1"\n\t}\n}\n' >"$CIDRE_STEAM_DIR/config/loginusers.vdf"
sortie=$(sh "$S" assurer 5)
verif "hors ligne voulu : masque" "oui" "$(masque_appele)"
export CIDRE_STEAM_MASQUER="echo sans_fenetre"

echo "== 13. un client qui mange le processeur avant le lancement : dit, pas tue"
remise oui; touch "$T/tourne"; { demarrage; connexion; } >>"$JC"
sortie=$(CIDRE_STEAM_CPU=97 sh "$S" assurer 5); rc=$?
verif "connecte a 97 % : code 0" "0" "$rc"
contient "connecte a 97 % : il le dit" "steam_osx prend 97 % du processeur en continu" "$sortie"
contient "et qu'on ne le ferme pas" "Cidre ne le ferme pas" "$sortie"
verif "toujours la (temoin intact)" "connecte" "$(sh "$S")"
sortie=$(CIDRE_STEAM_CPU=40 sh "$S" assurer 5)
verif "connecte a 40 % : rien d'ecrit" "" "$sortie"
remise oui; touch "$T/tourne"
sortie=$(CIDRE_STEAM_CPU=97 sh "$S" assurer 1)
contient "deja ouvert, pas connecte, 97 % : dit aussi" "prend 97 %" "$sortie"
remise oui; ouvreur "touch \"\$T/tourne\"; cat >>\"\$JC\" <<'FIN'
$DEM
$CON
FIN"
sortie=$(CIDRE_STEAM_CPU=97 sh "$S" assurer 10)
case $sortie in *"prend 97"*) echec "ouvert par Cidre : un demarrage mange du processeur, pas d'avertissement attendu" ;; *) ok "ouvert par Cidre : pas d'avertissement (demarrage)" ;; esac
# la vraie mesure, sur des processus du test
unset CIDRE_STEAM_CPU
yes >/dev/null & glouton=$!
sleep 30 & dort=$!; sleep 1   # le %cpu de ps monte en une seconde
sortie=$(CIDRE_STEAM_PID=$glouton CIDRE_STEAM_CPU_AGE_MIN=0 CIDRE_STEAM_CPU_FENETRE=2 sh "$S" cpu); rc=$?
p=$(printf '%s\n' "$sortie" | sed -n 1p)
verif "cpu, processus a 100 % : code 0" "0" "$rc"
[ "${p:-0}" -ge 80 ] && [ "${p:-0}" -le 110 ] && ok "cpu, processus a 100 % : mesure $p %" || echec "cpu, processus a 100 % : mesure « $p »"
contient "cpu : l'avertissement en 2e ligne" "client Steam : steam_osx prend $p %" "$(printf '%s\n' "$sortie" | sed -n 2p)"
debut=$(date +%s); sortie=$(CIDRE_STEAM_PID=$glouton CIDRE_STEAM_CPU_FENETRE=2 sh "$S" cpu); rc=$?; duree=$(( $(date +%s) - debut ))
verif "cpu, processus de moins de 2 min : 0, pas mesure" "0 1" "$sortie $rc"
[ "$duree" -le 1 ] && ok "  sans attendre ($duree s)" || echec "  a attendu $duree s"
kill "$glouton" 2>/dev/null; wait "$glouton" 2>/dev/null
debut=$(date +%s); sortie=$(CIDRE_STEAM_PID=$dort CIDRE_STEAM_CPU_AGE_MIN=0 sh "$S" cpu); rc=$?; duree=$(( $(date +%s) - debut ))
verif "cpu, processus endormi : code 1" "1" "$rc"
[ "$(printf '%s\n' "$sortie" | wc -l | tr -d ' ')" = 1 ] && ok "cpu, processus endormi : une ligne, pas d'avertissement" || echec "cpu endormi : « $sortie »"
[ "$duree" -le 1 ] && ok "cpu, processus endormi : sans la fenetre de 5 s ($duree s)" || echec "cpu endormi : $duree s"
kill "$dort" 2>/dev/null; wait "$dort" 2>/dev/null
CIDRE_STEAM_PID=999999 sh "$S" cpu >/dev/null 2>&1; verif "cpu, rien ne tourne : code 2" "2" "$?"
sh "$S" cpu >/dev/null 2>&1; verif "cpu : le vrai steam_osx n'est pas pris pour celui du dossier d'essai (code 2)" "2" "$?"
CIDRE_STEAM_CPU=97 sh "$S" cpu >/dev/null 2>&1; verif "cpu, mesure fournie (CIDRE_STEAM_CPU) : reprise" "0" "$?"
export CIDRE_STEAM_CPU=0

echo "== 13 bis. cidre play --json : l'avertissement pour Verger, avant le lancement (faux lanceur, jeu hors Steam)"
mkdir -p "$T/cidre" "$T/home"; : >"$T/jeu.exe"
printf 'local-essai\tEssai\t%s\n' "$T/jeu.exe" >"$T/cidre/jeux-locaux.conf"
printf '#!/bin/sh\necho "lanceur CIDRE_STEAM_CPU=${CIDRE_STEAM_CPU:-vide}" >&2\n' >"$T/lanceur.sh"
jouer() { HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_LANCEUR="$T/lanceur.sh" sh "$R/cidre" play local-essai "$@" 2>"$T/play.err"; }
# (l'evenement « shaders » de tests/etat_shaders.sh passe avant les autres : on
# le verifie a part, puis on l'ecarte pour ne regarder que l'avertissement)
sans_shaders() { grep -v '^{"evenement":"shaders"'; }
sortie=$(CIDRE_STEAM_CPU=97 jouer --json)
verif "trois evenements : shaders, avertissement, lancement" "shaders avertissement lancement" "$(printf '%s\n' "$sortie" | sed 's/^{"evenement":"\([a-z]*\)".*/\1/' | tr '\n' ' ' | sed 's/ $//')"
contient "jeu jamais joue ici : premier lancement" '{"evenement":"shaders","etat":"premier_lancement"' "$sortie"
sortie=$(printf '%s\n' "$sortie" | sans_shaders)
verif "deux evenements, avertissement d'abord" "avertissement lancement" "$(printf '%s\n' "$sortie" | sed 's/^{"evenement":"\([a-z]*\)".*/\1/' | tr '\n' ' ' | sed 's/ $//')"
contient "code steam_cpu, cpu 97" '"code":"steam_cpu","cpu":97,"message":"client Steam : steam_osx prend 97 %' "$sortie"
if command -v python3 >/dev/null 2>&1; then
   printf '%s\n' "$sortie" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin]' 2>/dev/null && ok "JSON valide, ligne a ligne" || echec "JSON invalide : $sortie"
fi
contient "la mesure passe au lanceur" "lanceur CIDRE_STEAM_CPU=97" "$(cat "$T/play.err")"
verif "a 40 % : le seul lancement" '{"evenement":"lancement"}' "$(CIDRE_STEAM_CPU=40 jouer --json | sans_shaders)"
verif "CIDRE_SANS_STEAM=1 : rien" '{"evenement":"lancement"}' "$(CIDRE_STEAM_CPU=97 CIDRE_SANS_STEAM=1 jouer --json | sans_shaders)"
sortie=$(CIDRE_STEAM_CPU=97 jouer)
case $sortie in *steam_cpu*|*"prend 97"*) echec "sans --json, cidre ne dit rien (c'est au lanceur)" ;; *) ok "sans --json, cidre le laisse au lanceur" ;; esac
# la ligne du lanceur pour un jeu hors Steam : la 2e ligne de « cpu », indentee
verif "lanceur hors Steam : la ligne d'avertissement" "    client Steam : steam_osx prend 97 %" "$(CIDRE_STEAM_CPU=97 sh "$S" cpu 2>/dev/null | sed -n '2s/^/    /p' | cut -c1-39)"
verif "lanceur hors Steam, 40 % : rien" "" "$(CIDRE_STEAM_CPU=40 sh "$S" cpu 2>/dev/null | sed -n '2s/^/    /p')"

echo "== 14. usage et syntaxe"
sh "$S" assurer abc >/dev/null 2>&1; verif "delai non numerique refuse" "64" "$?"
sh "$S" autre >/dev/null 2>&1; verif "verbe inconnu refuse" "64" "$?"
for s in tests/client_steam_natif.sh tests/lancer_depuis_steam.sh tests/diagnostic_cidre.sh tests/empaqueter_runtime.sh tests/tester_client_steam.sh; do
   sh -n "$R/$s" 2>/dev/null && ok "sh -n $s" || echec "sh -n $s"
done
grep -q "client_steam_natif.sh" "$R/tests/empaqueter_runtime.sh" && ok "livre dans le runtime (empaqueter_runtime.sh)" || echec "client_steam_natif.sh n'est pas dans empaqueter_runtime.sh"
grep -q 'client_steam_natif.sh" assurer' "$R/tests/lancer_depuis_steam.sh" && ok "appele par le lanceur" || echec "le lanceur n'appelle pas client_steam_natif.sh"
grep -q 'client_steam_natif.sh" cpu' "$R/tests/lancer_depuis_steam.sh" && ok "le lanceur le mesure aussi pour un jeu hors Steam" || echec "lanceur : pas de mesure hors Steam"
grep -q '"evenement":"avertissement","code":"steam_cpu"' "$R/cidre" && ok "cidre play --json : evenement avertissement steam_cpu" || echec "cidre : pas d'evenement steam_cpu"
sh -n "$R/cidre" 2>/dev/null && ok "sh -n cidre" || echec "sh -n cidre"
# ni quitter le client, ni lui parler par AppleScript (autorisation d'Automatisation)
if grep -n -E 'pkill|killall|kill -|System Events|tell application|steam://exit|-shutdown' "$S" | grep -v '^[0-9]*:[[:space:]]*#' | grep -q .; then echec "client_steam_natif.sh quitte, tue ou scripte le client"; else ok "client_steam_natif.sh ne quitte ni ne scripte le client"; fi

echo
echo "$nb verifications, $ko en echec"
[ "$ko" -eq 0 ]
