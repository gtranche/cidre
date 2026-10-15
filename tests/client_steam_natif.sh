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
# On ne le quitte donc jamais, meme quand il gene : on le met en arriere-plan.
#
#   client_steam_natif.sh              son etat, en un mot : « connecte »,
#                                      « ouvert » (il tourne, pas connecte),
#                                      « ferme », ou « absent » (pas installe)
#   client_steam_natif.sh assurer [s]  l'ouvre s'il est ferme, sans fenetre ni
#                                      premier plan (-silent), attend sa
#                                      connexion [s] secondes au plus (90 par
#                                      defaut), puis masque sa fenetre s'il en
#                                      montre une ; s'il tournait deja, dit s'il
#                                      mange le processeur
#   client_steam_natif.sh cpu          ce qu'il prend du processeur en continu,
#                                      en % (1re ligne) ; au-dela du seuil,
#                                      l'avertissement en 2e ligne, code 0 ;
#                                      code 1 en dessous, 2 s'il ne tourne pas
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
# Arriere-plan. Ouvert par nous, il part avec -silent (ni fenetre ni premier
# plan ; /Applications/Steam.app et steam_osx connaissent tous deux l'option).
# Deja ouvert avec sa fenetre, on masque l'application (comme Cmd-H) par
# NSRunningApplication.hide, depuis osascript en JavaScript : ni evenement Apple
# ni autorisation d'Accessibilite ou d'Automatisation, et la fenetre de la
# bibliotheque -- qui appartient au processus « Steam Helper » -- part avec
# (verifie sur le Mac de dev le 2026-10-15). Seulement une fois connecte : pas
# connecte, la fenetre est souvent celle ou l'on se connecte. Masque, il ne
# dessine plus rien ; un clic sur son icone le rend.
# CIDRE_STEAM_LAISSER_FENETRE=1 : ne pas masquer.
#
# Processeur. Le 2026-10-15 sur le M4, steam_osx tournait a 100 % depuis deux
# jours, sans jeu, et prenait sa part aux mesures. S'il tournait avant nous (pas
# juste ouvert : un demarrage mange du processeur par nature), on regarde son
# %cpu ; au-dela de CIDRE_STEAM_CPU_SEUIL (80 par defaut), on le confirme par
# son temps processeur sur 5 s (CIDRE_STEAM_CPU_FENETRE) et on le dit. On ne le
# tue pas. Un pic passager existe : ouvrir sa bibliotheque l'a tenu a 100 %
# pendant une minute environ sur le Mac de dev ; 5 s ne l'ecartent pas tout a
# fait, d'ou un avertissement et rien de plus. CIDRE_STEAM_CPU=<n> : la mesure deja faite (`cidre play --json`).
#
# Pour les essais (tests/tester_client_steam.sh) : CIDRE_STEAM_DIR (le dossier
# du client), CIDRE_STEAM_APP (son application), CIDRE_STEAM_TOURNE,
# CIDRE_STEAM_OUVRIR et CIDRE_STEAM_MASQUER (les commandes qui disent s'il
# tourne, qui l'ouvrent, et qui masquent sa fenetre), CIDRE_STEAM_PID (le
# processus dont on mesure le processeur) et CIDRE_STEAM_CPU_AGE_MIN (l'age, en
# secondes, en dessous duquel on ne le mesure pas ; 120 par defaut).
set -u
STEAM=${CIDRE_STEAM_DIR:-$HOME/Library/Application Support/Steam}
JC="$STEAM/logs/connection_log.txt"
SEUIL=${CIDRE_STEAM_CPU_SEUIL:-80}
FENETRE=${CIDRE_STEAM_CPU_FENETRE:-5}
AGE_MIN=${CIDRE_STEAM_CPU_AGE_MIN:-120}

tourne() {
   if [ -n "${CIDRE_STEAM_TOURNE:-}" ]; then sh -c "$CIDRE_STEAM_TOURNE" >/dev/null 2>&1
   else pgrep -x steam_osx >/dev/null 2>&1; fi
}
installe() { [ -d "$STEAM/Steam.AppBundle" ] || [ -d "${CIDRE_STEAM_APP:-/Applications/Steam.app}" ]; }
ouvrir() {
   if [ -n "${CIDRE_STEAM_OUVRIR:-}" ]; then sh -c "$CIDRE_STEAM_OUVRIR" >/dev/null 2>&1
   else open -g -b com.valvesoftware.steam --args -silent 2>/dev/null || open -g -a Steam --args -silent 2>/dev/null; fi
}
# Masque l'application si une de ses fenetres est a l'ecran ; ecrit ce qui
# s'est passe : masque, sans_fenetre (rien a l'ecran, ou deja masque), absent,
# echec.
masquer() {
   if [ -n "${CIDRE_STEAM_MASQUER:-}" ]; then sh -c "$CIDRE_STEAM_MASQUER" 2>/dev/null; return; fi
   osascript -l JavaScript -e '
      ObjC.import("AppKit"); ObjC.import("CoreGraphics");
      var W = $.NSRunningApplication, ID = "com.valvesoftware.steam";
      function applis() { return W.runningApplicationsWithBundleIdentifier(ID).js; }
      // une fenetre de Steam a l ecran ? (celle de la bibliotheque est au
      // processus « Steam Helper », com.valvesoftware.steam.helper)
      function visible() {
         var pids = {};
         applis().concat(W.runningApplicationsWithBundleIdentifier(ID + ".helper").js)
            .forEach(function (a) { pids[a.processIdentifier] = 1; });
         var l = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(
            $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0))) || [];
         return l.some(function (w) { var b = w.kCGWindowBounds;
            return pids[w.kCGWindowOwnerPID] && w.kCGWindowLayer == 0 && b.Width > 100 && b.Height > 100; });
      }
      var r;
      if (!applis().length) r = "absent";
      else if (!visible()) r = "sans_fenetre";
      else {
         // hide rend NON meme quand la demande aboutit, et « hidden » reste en
         // cache sans boucle d evenements : on relit les fenetres a l ecran
         applis().forEach(function (a) { a.hide; });
         for (var i = 0; i < 40 && visible(); i++) delay(0.05);
         r = visible() ? "echec" : "masque";
      }
      r' 2>/dev/null || echo echec
}
arriere_plan() {
   [ "${CIDRE_STEAM_LAISSER_FENETRE:-}" = 1 ] && return 0
   case $(masquer) in
      masque) echo "    client Steam : fenetre masquee (il reste ouvert et connecte ; un clic sur son icone la rend)" ;;
      echec)  echo "    client Steam : sa fenetre n'a pas pu etre masquee (Cmd-H dans Steam pour la cacher)" ;;
   esac
}

# Le processeur que prend steam_osx, en % d'un coeur : le %cpu de ps (sur
# macOS, quasi instantane : il retombe a 0 en une seconde), puis, s'il depasse
# le seuil, son temps processeur sur FENETRE secondes, pour ne pas compter un
# pic. Rend 1 s'il ne tourne pas ; 0 % s'il vient de demarrer.
# une duree de ps (etime, time : [j-][[h:]m:]s[.cc]) en centiemes de seconde
centiemes() { awk -v t="$1" 'BEGIN { j = 0; k = index(t, "-"); if (k) { j = substr(t, 1, k - 1); t = substr(t, k + 1) }
   n = split(t, c, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + c[i]; printf "%d\n", (j * 86400 + s) * 100 + 0.5 }'; }
cpu_continu() {
   case ${CIDRE_STEAM_CPU:-} in ''|*[!0-9]*) ;; *) echo "$CIDRE_STEAM_CPU"; return 0 ;; esac
   # celui de CE dossier Steam : une suite d'essais (HOME factice) ne mesure
   # pas le vrai client
   pid=${CIDRE_STEAM_PID:-$(ps -axo pid=,comm= 2>/dev/null | awk -v d="$STEAM/" 'index($0, d) && /\/steam_osx$/ { print $1; exit }')}
   [ -n "$pid" ] || return 1
   age=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
   [ -n "$age" ] || return 1
   [ "$(centiemes "$age")" -ge $((AGE_MIN * 100)) ] || { echo 0; return 0; }
   inst=$(ps -o %cpu= -p "$pid" 2>/dev/null | awk '{ printf "%d\n", $1 }')
   [ "${inst:-0}" -ge "$SEUIL" ] || { echo "${inst:-0}"; return 0; }
   t0=$(ps -o time= -p "$pid" 2>/dev/null | tr -d ' ')
   sleep "$FENETRE"
   t1=$(ps -o time= -p "$pid" 2>/dev/null | tr -d ' ')
   [ -n "$t0" ] && [ -n "$t1" ] || return 1
   echo $(( ($(centiemes "$t1") - $(centiemes "$t0")) / FENETRE ))
}
message_cpu() { # <%>
   echo "client Steam : steam_osx prend $1 % du processeur en continu (mesure sur $FENETRE s avant le lancement, sans jeu) -- autant de moins pour le jeu ; le quitter et le rouvrir quand aucun jeu ne tourne (Cidre ne le ferme pas : un jeu protege par Steam se fermerait avec lui)"
}
# assurer : l'avertissement, s'il y a lieu, a la sortie du lanceur
diagnostic_cpu() {
   p=$(cpu_continu) || return 0
   [ "$p" -ge "$SEUIL" ] && echo "    $(message_cpu "$p")"
   return 0
}

lignes() { n=$(wc -l 2>/dev/null <"$JC") || n=0; echo $((${n:-0})); }
# le dernier etat ecrit a partir de la ligne <n> du journal de connexion. Les
# lignes du compte 0 ([U:1:0]) ne comptent pas : le client en ecrit avant de
# connaitre son compte, et le pont steamclient de Wine en ajoute dans le meme
# journal pendant qu'un jeu tourne (« [Logged Off, 0, 0] [U:1:0]
# CCMInterface::SetSteamID », 2026-10-15) ; le client, lui, connecte ou non,
# ecrit sous le compte de l'utilisateur.
dernier_etat() {
   tail -n "+$1" "$JC" 2>/dev/null | LC_ALL=C awk '
      / \[U:1:0\] / { next }
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
   cpu)
      for v in "$SEUIL" "$FENETRE" "$AGE_MIN"; do
         case $v in ''|*[!0-9]*) echo "CIDRE_STEAM_CPU_* : entier attendu" >&2; exit 64 ;; esac
      done
      [ "$FENETRE" -ge 1 ] || FENETRE=1
      p=$(cpu_continu) || exit 2
      echo "$p"
      [ "$p" -ge "$SEUIL" ] || exit 1
      message_cpu "$p" ;;
   assurer)
      ATTENTE=${2:-90}
      case $ATTENTE in ''|*[!0-9]*) echo "usage : client_steam_natif.sh [assurer [secondes] | cpu]" >&2; exit 64 ;; esac
      case $SEUIL$FENETRE$AGE_MIN in ''|*[!0-9]*) SEUIL=80 FENETRE=5 AGE_MIN=120 ;; esac
      [ "$FENETRE" -ge 1 ] || FENETRE=1
      case $(etat) in
         connecte) diagnostic_cpu; arriere_plan; exit 0 ;;
         absent)
            echo "    client Steam : pas installe sur ce Mac -- un jeu Steam ne trouvera personne derriere le pont (installer Steam, s'y connecter, relancer)"
            exit 2 ;;
         ouvert)
            diagnostic_cpu
            # Le mode hors ligne est un choix (Steam > Passer hors ligne) : le
            # client repond avec ce qu'il a en cache, il n'y a rien a attendre.
            hors_ligne && { arriere_plan; exit 0; }
            # Il tourne deja : on ne lui laisse qu'un court delai (il vient
            # peut-etre d'etre ouvert), pas l'attente d'un demarrage complet.
            depuis=$(( $(lignes) > 400 ? $(lignes) - 400 : 1 )); base=$((depuis - 1)); [ "$ATTENTE" -gt 15 ] && ATTENTE=15
            quoi="deja ouvert" ;;
         ferme)
            base=$(lignes); depuis=$((base + 1))
            ouvrir || { echo "    client Steam : ferme, et il n'a pas pu etre ouvert -- l'ouvrir a la main, puis relancer"; exit 2; }
            quoi="etait ferme, ouvert par Cidre en arriere-plan" ;;
      esac
      i=0
      while [ "$i" -lt "$ATTENTE" ]; do
         # un journal qui a tourne (connection_log.previous.txt) repart de zero
         [ "$(lignes)" -lt "$base" ] && { base=0; depuis=1; }
         if tourne && connecte "$depuis"; then
            echo "    client Steam : $quoi, connecte apres $i s"
            arriere_plan
            exit 0
         fi
         sleep 1; i=$((i + 1))
      done
      echo "    client Steam : $quoi, mais pas connecte apres $ATTENTE s -- un jeu protege par Steam se fermera aussitot (se connecter dans Steam, puis relancer)"
      exit 1 ;;
   *) echo "usage : client_steam_natif.sh [assurer [secondes] | cpu]" >&2; exit 64 ;;
esac
