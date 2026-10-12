#!/bin/sh
# Le client Steam de macOS, celui que le pont lsteamclient interroge : il doit
# tourner ET etre connecte avant qu'un jeu Steam demarre. Lance par le bouton
# « Jouer » de Steam il tourne par construction ; par `cidre play` (Verger, un
# jeu telecharge hors du client) rien ne le garantissait. Ferme, un jeu protege
# par le DRM de Steam (SteamStub) ne trouve personne derriere le pont : il
# demande steam://run/<appid> au systeme et sort aussitot, sans une ligne au
# journal. Mesure sur Expedition 33 le 2026-10-12 (M4, macOS 27, Mac rallume et
# Steam pas rouvert) : code de sortie 53 trois fois de suite client ferme ; le
# meme lancement passe le DRM et demarre le jeu une fois le client ouvert.
#
#   client_steam_natif.sh              son etat, en un mot : « connecte »,
#                                      « ouvert » (il tourne, pas connecte),
#                                      « ferme », ou « absent » (pas installe)
#   client_steam_natif.sh assurer [s]  l'ouvre s'il est ferme, sans lui donner
#                                      le premier plan, et attend sa connexion
#                                      [s] secondes au plus (90 par defaut)
#
# assurer ecrit ce qu'il a fait (rien s'il n'y avait rien a faire) et rend
# 0 = connecte (ou ouvert en mode hors ligne, choisi dans Steam : rien a
# attendre), 1 = ouvert mais pas connecte a temps (fenetre de connexion, mise a
# jour du client), 2 = pas de client Steam sur ce Mac, ou impossible a ouvrir.
# Il ne bloque jamais un lancement : a l'appelant de continuer.
#
# La connexion se lit dans logs/connection_log.txt du client : chaque ligne
# d'etat y porte « [Logged On, ...] », « [Connecting, ...] », « [Logged Off,
# ...] », et la derniere fait foi. Quand c'est nous qui venons de l'ouvrir, on
# ne lit que ce qu'il a ecrit depuis : apres un arret brutal (Mac eteint), la
# derniere ligne de la session precedente dit encore « Logged On ».
#
# Pour les essais (tests/tester_client_steam.sh) : CIDRE_STEAM_DIR (le dossier
# du client), CIDRE_STEAM_APP (son application), CIDRE_STEAM_TOURNE et
# CIDRE_STEAM_OUVRIR (les commandes qui disent s'il tourne et qui l'ouvrent).
set -u
STEAM=${CIDRE_STEAM_DIR:-$HOME/Library/Application Support/Steam}
JC="$STEAM/logs/connection_log.txt"

tourne() {
   if [ -n "${CIDRE_STEAM_TOURNE:-}" ]; then sh -c "$CIDRE_STEAM_TOURNE" >/dev/null 2>&1
   else pgrep -x steam_osx >/dev/null 2>&1; fi
}
installe() { [ -d "$STEAM/Steam.AppBundle" ] || [ -d "${CIDRE_STEAM_APP:-/Applications/Steam.app}" ]; }
ouvrir() {
   if [ -n "${CIDRE_STEAM_OUVRIR:-}" ]; then sh -c "$CIDRE_STEAM_OUVRIR" >/dev/null 2>&1
   else open -g -b com.valvesoftware.steam 2>/dev/null || open -g -a Steam 2>/dev/null; fi
}
lignes() { n=$(wc -l 2>/dev/null <"$JC") || n=0; echo $((${n:-0})); }
# le dernier etat ecrit a partir de la ligne <n> du journal de connexion
dernier_etat() {
   tail -n "+$1" "$JC" 2>/dev/null | LC_ALL=C awk '
      match($0, /^\[[^]]*\] \[[A-Za-z ]+,/) { e = substr($0, RSTART, RLENGTH - 1); sub(/^\[[^]]*\] \[/, "", e) }
      END { print e }'
}
connecte() { [ "$(dernier_etat "$1")" = "Logged On" ]; }
hors_ligne() { LC_ALL=C grep -q '"WantsOfflineMode"[[:space:]]*"1"' "$STEAM/config/loginusers.vdf" 2>/dev/null; }
etat() {
   if tourne; then connecte "$(( $(lignes) > 400 ? $(lignes) - 400 : 1 ))" && echo connecte || echo ouvert
   elif installe; then echo ferme
   else echo absent; fi
}

case ${1:-etat} in
   etat) etat ;;
   assurer)
      ATTENTE=${2:-90}
      case $ATTENTE in ''|*[!0-9]*) echo "usage : client_steam_natif.sh [assurer [secondes]]" >&2; exit 64 ;; esac
      case $(etat) in
         connecte) exit 0 ;;
         absent)
            echo "    client Steam : pas installe sur ce Mac -- un jeu Steam ne trouvera personne derriere le pont (installer Steam, s'y connecter, relancer)"
            exit 2 ;;
         ouvert)
            # Le mode hors ligne est un choix (Steam > Passer hors ligne) : le
            # client repond avec ce qu'il a en cache, il n'y a rien a attendre.
            hors_ligne && exit 0
            # Il tourne deja : on ne lui laisse qu'un court delai (il vient
            # peut-etre d'etre ouvert), pas l'attente d'un demarrage complet.
            depuis=$(( $(lignes) > 400 ? $(lignes) - 400 : 1 )); base=$((depuis - 1)); [ "$ATTENTE" -gt 15 ] && ATTENTE=15
            quoi="deja ouvert" ;;
         ferme)
            base=$(lignes); depuis=$((base + 1))
            ouvrir || { echo "    client Steam : ferme, et il n'a pas pu etre ouvert -- l'ouvrir a la main, puis relancer"; exit 2; }
            quoi="etait ferme, ouvert par Cidre" ;;
      esac
      i=0
      while [ "$i" -lt "$ATTENTE" ]; do
         # un journal qui a tourne (connection_log.previous.txt) repart de zero
         [ "$(lignes)" -lt "$base" ] && { base=0; depuis=1; }
         if tourne && connecte "$depuis"; then
            echo "    client Steam : $quoi, connecte apres $i s"
            exit 0
         fi
         sleep 1; i=$((i + 1))
      done
      echo "    client Steam : $quoi, mais pas connecte apres $ATTENTE s -- un jeu protege par Steam se fermera aussitot (se connecter dans Steam, puis relancer)"
      exit 1 ;;
   *) echo "usage : client_steam_natif.sh [assurer [secondes]]" >&2; exit 64 ;;
esac
