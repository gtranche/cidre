#!/bin/sh
# Teste tests/client_steam_natif.sh contre un faux client Steam : un dossier
# temporaire avec son journal de connexion, un temoin « il tourne », et une
# commande d'ouverture qui ecrit dans ce journal ce que le vrai client y ecrit
# (releve sur le M4 le 2026-10-12). Ni le vrai client ni son dossier ne sont
# touches, et rien n'est lance.
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
contient "il dit qu'il l'a ouvert" "etait ferme, ouvert par Cidre, connecte apres" "$sortie"
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

echo "== 10. usage et syntaxe"
sh "$S" assurer abc >/dev/null 2>&1; verif "delai non numerique refuse" "64" "$?"
sh "$S" autre >/dev/null 2>&1; verif "verbe inconnu refuse" "64" "$?"
for s in tests/client_steam_natif.sh tests/lancer_depuis_steam.sh tests/diagnostic_cidre.sh tests/empaqueter_runtime.sh tests/tester_client_steam.sh; do
   sh -n "$R/$s" 2>/dev/null && ok "sh -n $s" || echec "sh -n $s"
done
grep -q "client_steam_natif.sh" "$R/tests/empaqueter_runtime.sh" && ok "livre dans le runtime (empaqueter_runtime.sh)" || echec "client_steam_natif.sh n'est pas dans empaqueter_runtime.sh"
grep -q 'client_steam_natif.sh" assurer' "$R/tests/lancer_depuis_steam.sh" && ok "appele par le lanceur" || echec "le lanceur n'appelle pas client_steam_natif.sh"

echo
echo "$nb verifications, $ko en echec"
[ "$ko" -eq 0 ]
