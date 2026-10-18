#!/bin/sh
# Apres la sortie du jeu : arreter le client de service (c:\faux_steam.exe) du
# prefixe, et avec lui le wineserver et ses services, des que plus rien du jeu
# n'y tourne.
#
#   fin_de_partie.sh        (WINEPREFIX, sinon wine/pfx-arm64ec)
#
# faux_steam n'est la que pour le jeu (lancer_depuis_steam.sh), et le lancement
# suivant le tue de toute facon (hygiene). Laisse en vie, il garde le wineserver
# et ses services (services.exe, plugplay.exe, svchost.exe...) des heures, et
# avec eux tout descripteur herite de l'appelant. Le 2026-10-18 (Demonologist,
# M1), deux parties de suite ont ainsi laisse `cidre play ... 2>&1 | tail` en
# attente apres « Quitter » : il a fallu un `cidre stop`.
#
# Prudence (feedback « trois constats ») : on ne conclut qu'apres 3 releves
# consecutifs, a 2 s d'intervalle, sans autre processus Windows dans le prefixe
# que faux_steam et ceux de C:\windows\ (services de Wine). Un jeu dont le
# lanceur sort en laissant tourner le vrai jeu, un gestionnaire de plantage qui
# s'attarde : on attend au plus ~24 s, puis on laisse tout en place. On ne tue
# jamais un processus du jeu : seulement faux_steam, puis `wineserver -k` si le
# serveur ne part pas seul.
# Les processus du prefixe sont ceux qui ont un fichier ouvert dans le dossier du
# serveur Wine de CE prefixe (/tmp/.wine-<uid>/server-<dev>-<inode>, que lsof
# montre sous /private/tmp) : un autre prefixe, un autre runtime (Whisky,
# CrossOver) n'y sont pas.
# CIDRE_FIN_RELEVES / CIDRE_FIN_PAUSE : nombre maximal de releves et pause (essais).
# Tout le corps est entre accolades, ferme par `exit` (cf. lancer_depuis_steam.sh).
{
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
WS=$R/wine/wine11-arm64/bin/wineserver
SRV=/tmp/.wine-$(id -u)/server-$(stat -f '%Xd-%Xi' "$PFX" 2>/dev/null)
MAX=${CIDRE_FIN_RELEVES:-12}
PAUSE=${CIDRE_FIN_PAUSE:-2}

serveur_vivant() { [ -S "$SRV/socket" ] && pgrep -x wineserver >/dev/null 2>&1; }

# « pid<TAB>nom » de chaque processus Windows du prefixe (wineserver exclu : son
# nom n'a pas de .exe).
processus() {
   c=$(ps -axo pid=,comm= 2>/dev/null | awk 'tolower($0) ~ /\.exe/ { print $1 }' | paste -sd, -)
   [ -n "$c" ] || return 0
   for p in $(lsof -a -p "$c" -Fpn 2>/dev/null | awk -v s="/.wine-$(id -u)/${SRV##*/}/" '/^p/ { p = substr($0, 2) } /^n/ && index($0, s) && !vu[p]++ { print p }'); do
      printf '%s\t%s\n' "$p" "$(ps -o comm= -p "$p" 2>/dev/null)"
   done
}
# ce qui n'est ni faux_steam ni un service de Wine
autres() { processus | awk -F'\t' '{ n = tolower($2) } n !~ /faux_steam\.exe/ && n !~ /^c:\\windows\\/ { print $2 }'; }

serveur_vivant || exit 0
vides=0; i=0; reste=
while [ $i -lt "$MAX" ]; do
   reste=$(autres)
   if [ -z "$reste" ]; then vides=$((vides + 1)); [ $vides -ge 3 ] && break
   else vides=0; fi
   i=$((i + 1)); sleep "$PAUSE"
done
if [ $vides -lt 3 ]; then
   echo "    fin de partie : encore dans le prefixe : $(printf '%s\n' "$reste" | sed 's/.*\\//' | sort -u | paste -sd ' ' -) -- client de service garde"
   exit 0
fi
fs=$(processus | awk -F'\t' 'tolower($2) ~ /faux_steam\.exe/ { print $1 }')
[ -z "$fs" ] || kill $fs 2>/dev/null || true
# Sans processus d'utilisateur, le wineserver arrete ses services et sort de
# lui-meme en quelques secondes ; sinon, comme l'hygiene du lanceur.
j=0
while serveur_vivant && [ $j -lt 10 ]; do sleep 1; j=$((j + 1)); done
if serveur_vivant; then
   WINEPREFIX=$PFX "$WS" -k 2>/dev/null || true
   echo "    fin de partie : client de service arrete${fs:+ ($fs)}, wineserver arrete (-k)"
else
   echo "    fin de partie : client de service arrete${fs:+ ($fs)}, wineserver sorti en ${j} s"
fi
exit 0
}
