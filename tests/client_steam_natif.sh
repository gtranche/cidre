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
#   client_steam_natif.sh discret <etat> <pid>
#                                      le client en arriere-plan tant que <pid>
#                                      (le lanceur) vit ; cf. « Pendant la
#                                      partie » plus bas
#   client_steam_natif.sh rendre <etat>
#                                      sa priorite rendue, et ce qu'il a pris
#                                      du processeur pendant la partie
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
      // hide rend NON meme quand la demande aboutit, et « hidden » reste en
      // cache sans boucle d evenements : on relit les fenetres a l ecran.
      // Deja masque (un Cmd-H, ou nous au lancement precedent), hide ne fait
      // rien -- or Steam rouvre la bibliotheque a la sortie d un jeu sans
      // quitter cet etat : ses fenetres sont la, l appli « masquee » (M1, le
      // 2026-10-17 : 15 echecs sur 15 lancements). On la rend, puis on la
      // masque. Masquer « Steam Helper » lui-meme ne sert a rien : appli sans
      // icone (accessory), hide n y fait rien.
      function masquer(rendre) {
         applis().forEach(function (a) { if (rendre) { a.unhide; delay(0.3); } a.hide; });
         for (var i = 0; i < 40 && visible(); i++) delay(0.05);
         return !visible();
      }
      var r;
      if (!applis().length) r = "absent";
      else if (!visible()) r = "sans_fenetre";
      else {
         var deja = applis().some(function (a) { return a.hidden; });
         r = masquer(deja) || masquer(true) ? "masque" : "echec";
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
# Lance par le bouton « Jouer » de Steam (le lanceur passe
# CIDRE_STEAM_PAR_LE_CLIENT=1), le client est en train de lancer le jeu quand on
# le mesure : il peut prendre tout un coeur par nature (M1, le 2026-10-17 :
# 99 % a 11:19:13, LN lance par le bouton ; rien aux deux lancements suivants,
# 0,4 % au repos). Cette mesure ne dit rien de son regime continu : celle de la
# partie (rendre) le dit a la sortie.
diagnostic_cpu() {
   [ "${CIDRE_STEAM_PAR_LE_CLIENT:-}" = 1 ] && return 0
   p=$(cpu_continu) || return 0
   [ "$p" -ge "$SEUIL" ] && echo "    $(message_cpu "$p")"
   return 0
}

# Pendant la partie : le client en arriere-plan (taskpolicy -b, comme un
# processus de fond de macOS : coeurs d'efficacite, entrees-sorties freinees),
# rendu a la sortie (-B). Le meme utilisateur, sans sudo ; on ne le tue pas, on
# ne le ralentit que pendant le jeu. Bride : steam_osx et ses « Steam Helper »
# (CEF : bibliotheque, magasin). Laisses a pleine vitesse : ipcserver (il
# n'est pas l'enfant de steam_osx, rien n'en herite) et gameoverlayui, l'overlay
# du jeu -- steam_osx le lance au demarrage du jeu, il naitrait bride (un enfant
# herite du bridage de son parent ; pas ceux deja lances, le jeu lance par le
# bouton de Steam n'est donc pas touche) : la veille le rend toutes les
# PERIODE secondes. CIDRE_STEAM_ARRIERE_PLAN=0 : ne pas brider.
#   discret <etat> <pid>  veille tant que <pid> (le lanceur) vit ; note dans
#                         <etat> le temps processeur du client au depart
#   rendre <etat>         arrete la veille, rend la priorite, et ecrit ce que
#                         le client a pris du processeur pendant la partie
PERIODE=${CIDRE_STEAM_PERIODE:-5}
# les processus du client de CE dossier : « <pid> <role> », role = client,
# aide, overlay
processus() {
   ps -axo pid=,comm= 2>/dev/null | awk -v d="$STEAM/" '
      !index($0, d) { next }
      /\/steam_osx$/ { print $1, "client"; next }
      /\/gameoverlayui$/ { print $1, "overlay"; next }
      /\/Steam Helper[^\/]*$/ { print $1, "aide" }'
}
temps_cpu() { # <pids...> : somme des temps processeur, en centiemes
   s=0
   for p in "$@"; do
      t=$(ps -o time= -p "$p" 2>/dev/null | tr -d ' ')
      [ -n "$t" ] && s=$((s + $(centiemes "$t")))
   done
   echo "$s"
}
brider() { taskpolicy -b -p "$1" >/dev/null 2>&1; }
debrider() { taskpolicy -B -p "$1" >/dev/null 2>&1; }
veille() { # <etat> <pid du lanceur>
   brides= vus=
   rendre_tout() { for p in $brides; do debrider "$p"; done; exit 0; }
   trap rendre_tout TERM INT HUP
   while kill -0 "$2" 2>/dev/null; do
      processus >"$1.liste"
      while read -r p role; do
         case $role in
            overlay) case " $vus " in *" $p "*) ;; *) debrider "$p"; vus="$vus $p" ;; esac ;;
            *) case " $brides " in *" $p "*) ;; *) brider "$p" && brides="$brides $p" ;; esac ;;
         esac
      done <"$1.liste"
      # une boucle interruptible : TERM n'attend pas la fin d'un sleep
      sleep "$PERIODE" & wait $! 2>/dev/null
   done
   rendre_tout
}
discret() { # <etat> <pid du lanceur>
   [ "${CIDRE_STEAM_ARRIERE_PLAN:-1}" = 0 ] && return 0
   command -v taskpolicy >/dev/null 2>&1 || return 0
   l=$(processus)
   c=$(printf '%s\n' "$l" | awk '$2 == "client" { print $1; exit }')
   [ -n "$c" ] || return 0
   n=$(printf '%s\n' "$l" | awk '$2 == "aide"' | wc -l | tr -d ' ')
   # depart : date, pid du client, son temps processeur, celui de ses aides
   echo "$(date +%s) $c $(temps_cpu "$c") $(temps_cpu $(printf '%s\n' "$l" | awk '$2 == "aide" { print $1 }'))" >"$1"
   veille "$1" "$2" >/dev/null 2>&1 </dev/null &
   echo $! >"$1.veille"
   echo "    client Steam : en arriere-plan pendant la partie (steam_osx et $n Steam Helper, priorite basse ; l'overlay et ipcserver gardent la leur), rendu a la sortie"
}
rendre() { # <etat>
   [ -f "$1" ] || return 0
   v=$(cat "$1.veille" 2>/dev/null)
   if [ -n "$v" ] && kill -0 "$v" 2>/dev/null; then
      kill "$v" 2>/dev/null
      i=0; while kill -0 "$v" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
   fi
   # et sans compter sur la veille (tuee net, elle n'a rien rendu)
   processus | while read -r p role; do [ "$role" = overlay ] || debrider "$p"; done
   read -r t0 c c0 a0 <"$1"
   d=$(( $(date +%s) - t0 ))
   if [ "$d" -ge "${CIDRE_STEAM_DUREE_MIN:-10}" ] && [ "$d" -gt 0 ] && kill -0 "$c" 2>/dev/null; then
      c1=$(temps_cpu "$c")
      a1=$(temps_cpu $(processus | awk '$2 == "aide" { print $1 }'))
      pc=$(( (c1 - c0) / d )); pa=$(( (a1 - a0) / d ))
      [ "$pa" -ge 0 ] || pa=0   # une aide sortie pendant la partie emporte son temps
      echo "    client Steam : pendant la partie ($d s), steam_osx a pris $pc % d'un coeur en moyenne, ses Steam Helper $pa % ; priorite rendue"
   else
      echo "    client Steam : priorite rendue"
   fi
   rm -f "$1" "$1.veille" "$1.liste"
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
   discret)
      [ $# -ge 3 ] || { echo "usage : client_steam_natif.sh discret <etat> <pid>" >&2; exit 64; }
      case $PERIODE in ''|*[!0-9]*|0) PERIODE=5 ;; esac
      discret "$2" "$3" ;;
   rendre)
      [ $# -ge 2 ] || { echo "usage : client_steam_natif.sh rendre <etat>" >&2; exit 64; }
      rendre "$2" ;;
   *) echo "usage : client_steam_natif.sh [assurer [secondes] | cpu | discret <etat> <pid> | rendre <etat>]" >&2; exit 64 ;;
esac
