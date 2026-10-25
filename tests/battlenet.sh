#!/bin/sh
# Jeux Battle.net : le client de Blizzard, dans un prefixe a lui, lance les jeux
# (BATTLENET.md, section 3). Appele par `cidre` (list, info, play, stop,
# battlenet) et par lancer_depuis_steam.sh.
#
#   battlenet.sh prefixe [<chemin>|defaut]   le prefixe Battle.net (qu'il existe ou non) ; le
#                                     designer (un prefixe ou le client est deja installe)
#   battlenet.sh etat [--json]        client installe ? ouvert ? pour quel jeu ? un jeu en cours ?
#   battlenet.sh pids                 les processus que tient le wineserver du prefixe (cidre stop)
#   battlenet.sh jeux                 les jeux installes, un par ligne, TAB-separe : id, nom,
#                                     dossier, code, uid, executable (chemins POSIX), taille (octets)
#   battlenet.sh ouvrir [--json]      ouvre le client (connexion, telechargements, jeux), sans attendre ;
#                                     --json : {"evenement":"ouvert","deja":bool} ou {"evenement":"erreur",...}
#   battlenet.sh arreter [--force]    ferme le client, et le wineserver du prefixe avec lui ;
#                                     refuse (code 4) pendant un jeu, sauf --force (`cidre stop`)
#   battlenet.sh preparer <id> [args] lancer_depuis_steam.sh, avant de regler le prefixe pour ce jeu (et ses
#                                     arguments : AdditionalLaunchArguments de Battle.net.config)
#   battlenet.sh jouer <id> [args]    lancer_depuis_steam.sh, a la place de l'executable du jeu
#   battlenet.sh creer                cree le prefixe s'il manque (Wine neuf, runtime Visual C++, DXVK, FEX ;
#                                     sans le pont Steam), sinon le remet au runtime (cidre setup)
#   battlenet.sh installer [--json]   cree le prefixe, telecharge l'installeur officiel et le lance ; rend la
#                                     main quand le client est installe (l'utilisateur s'y connecte)
#
# Le prefixe : CIDRE_BNET_PREFIXE, sinon la premiere ligne de
# ~/Library/Application Support/Cidre/battlenet.prefixe, sinon wine/pfx-battlenet.
# A part du prefixe Steam : l'Agent et le client restent en arriere-plan et
# tiennent un wineserver, ils bloqueraient la fin des parties Steam et
# rejoindraient chaque jeu.
#
# Les jeux : les cles Uninstall que l'Agent ecrit dans le registre du prefixe
# (« --uid=osi » dans UninstallString, InstallLocation), traduites par
# outil-steam/battlenet.conf en id Cidre (bnet-<code>), code de lancement et
# executable. Le telechargement et les mises a jour restent au client.
#
# Le lancement passe par le client, connecte (session gardee par l'utilisateur) :
# `Battle.net.exe --exec="launch <code>"` (Lutris), qui donne au jeu le jeton de
# session et ses mises a jour. Le jeu est un processus fils du client : il herite
# de SON environnement (FEX, DXVK, vkd3d-proton, KosmicKrisp, DLL...), pas de
# celui de la commande --exec, qui ne fait que transmettre la demande au client
# deja ouvert. Le client est donc ouvert avec l'environnement que le lanceur a
# prepare pour le jeu, et rouvert quand un autre jeu, ou un autre reglage, le
# demande ; ouvert pour le meme jeu avec le meme environnement, il sert tel quel.
# Il est aussi ferme avant le reglage du prefixe pour un autre jeu (preparer) :
# la version de Windows et les KnownDLLs s'ecrivent sans wineserver.
# Le client en Qt logiciel (QT_QUICK_BACKEND=software QT_OPENGL=software) et son
# CEF en --in-process-gpu : la couche Metal de Qt couvre sinon la vue CEF
# (BATTLENET.md, section 4). CIDRE_BNET_ARGS_CLIENT remplace ces arguments.
# Battle.net.config : GameLaunchWindowBehavior = 2 ferme le client au lancement
# du jeu ; il est remis a 0 (client garde ouvert), client ferme.
#
# `jouer` attend le jeu (CIDRE_BNET_ATTENTE s, 900 par defaut : il faut parfois
# se connecter), puis sa fin : trois releves vides de suite, a 2 s (D2R se
# relance en un second processus). Le client reste ouvert apres le jeu. Codes :
# 0 = le jeu a tourne puis est sorti ; 1 = jamais vu ; 2 = jeu sans code de
# lancement ; 6 = le client s'est ferme avant le jeu. On ne tue jamais un jeu :
# seul `arreter --force` (cidre stop) arrete le wineserver pendant une partie.
# Tout le corps est entre accolades, ferme par `exit` (cf. lancer_depuis_steam.sh).
{
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
# (CIDRE_BNET_WINE : un autre Wine, pour les essais de creer/installer)
W=${CIDRE_BNET_WINE:-$R/wine/wine11-arm64}
# (CIDRE_BNET_TABLE : une autre table, pour les essais)
TABLE=${CIDRE_BNET_TABLE:-$R/outil-steam/battlenet.conf}

prefixe() {
   p=${CIDRE_BNET_PREFIXE:-}
   [ -n "$p" ] || p=$(head -1 "$CIDRE_DIR/battlenet.prefixe" 2>/dev/null)
   [ -n "$p" ] || p=$R/wine/pfx-battlenet
   printf '%s' "$p"
}
PFX=$(prefixe)
CLIENT_W='C:\Program Files (x86)\Battle.net\Battle.net.exe'
CLIENT="$PFX/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
CLIENT_ARGS=${CIDRE_BNET_ARGS_CLIENT:---in-process-gpu}
# pour quel jeu Cidre a ouvert le client, et l'empreinte de son environnement
MARQUE=$PFX/.cidre-client
# (CIDRE_BNET_JOURNAL_CLIENT : un autre journal, pour les essais -- le temoin ecrivait dans le vrai)
JOURNAL_CLIENT=${CIDRE_BNET_JOURNAL_CLIENT:-$R/build/logs/battlenet-client.log}
# (CIDRE_BNET_ETAPE2 : un autre lanceur de programme Windows, pour les essais)
ETAPE2=${CIDRE_BNET_ETAPE2:-$R/tests/etape2_pile_arm64ec.sh}
SRV=/tmp/.wine-$(id -u)/server-$(stat -f '%Xd-%Xi' "$PFX" 2>/dev/null)

serveur_vivant() { [ -S "$SRV/socket" ] && pgrep -x wineserver >/dev/null 2>&1; }
# « pid<TAB>nom » de chaque processus Windows du prefixe (cf. fin_de_partie.sh)
processus() {
   serveur_vivant || return 0
   c=$(ps -axo pid=,comm= 2>/dev/null | awk 'tolower($0) ~ /\.exe/ { print $1 }' | paste -sd, -)
   [ -n "$c" ] || return 0
   for p in $(lsof -a -p "$c" -Fpn 2>/dev/null | awk -v s="/.wine-$(id -u)/${SRV##*/}/" '/^p/ { p = substr($0, 2) } /^n/ && index($0, s) && !vu[p]++ { print p }'); do
      printf '%s\t%s\n' "$p" "$(ps -o comm= -p "$p" 2>/dev/null)"
   done
}
# le client et l'Agent (dossiers Battle.net de Program Files et ProgramData ; l'Agent
# s'ecrit C:/ProgramData/Battle.net/Agent/..., avec des barres obliques)
du_client() { processus | awk -F'\t' 'tolower($2) ~ /[\\\/]battle\.net[\\\/]/'; }
# ni le client, ni un service de Wine (ni start.exe, qui l'ouvre) : un jeu
des_jeux() { processus | awk -F'\t' '{ n = tolower($2) } n !~ /^c:\\windows\\/ && n !~ /[\\\/]battle\.net[\\\/]/ && n !~ /^start\.exe/'; }
# le pid de l'executable <nom> parmi les jeux
# (E devant awk, pas devant des_jeux : devant le premier membre du tube, awk ne la voyait pas,
# cherchait un nom vide et prenait le premier processus venu -- start.exe, manche du 21/10)
jeu_vu() { jv_e="\\$(printf '%s' "$1" | tr 'A-Z' 'a-z')"; des_jeux | E=$jv_e awk -F'\t' 'BEGIN { e = ENVIRON["E"] } { n = tolower($2) } substr(n, length(n) - length(e) + 1) == e { print $1; exit }'; }
noms() { cut -f2 | sed 's/.*[\\/]//' | sort -u | paste -sd ' ' -; }
marque() { sed -n "s/^$1=//p" "$MARQUE" 2>/dev/null | head -1; }
json() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
json_ou_null() { if [ -n "$1" ]; then json "$1"; else printf null; fi; }

jeux_registre() {
   [ -f "$PFX/system.reg" ] || return 0
   # (les cles Uninstall d'abord, par grep : awk sur toute la ruche prend 0,5 s)
   LC_ALL=C grep -i -A24 '^\[.*\\\\uninstall\\\\' "$PFX/system.reg" | LC_ALL=C awk -v table="$TABLE" -v pfx="$PFX" '
      BEGIN {
         while ((getline l < table) > 0) {
            if (l ~ /^#/ || l == "") continue
            split(l, c, "\t"); code[c[1]] = c[2]; exe[c[1]] = c[3]; nom[c[1]] = c[4]
         }
      }
      # C:/Program Files (x86)/Jeu -> <prefixe>/drive_c/Program Files (x86)/Jeu
      function posix(w,   l, r) {
         l = tolower(substr(w, 1, 1)); r = substr(w, 3); sub(/\/+$/, "", r)
         return pfx (l == "c" ? "/drive_c" : "/dosdevices/" l ":") r
      }
      function fin(   id, d, e) {
         if (u == "" || u == "battle.net" || loc == "") return
         id = "bnet-" (u in code ? tolower(code[u]) : u)
         if (vu[id]++) return
         d = posix(loc)
         e = (u in exe) ? d "/" exe[u] : (ic != "" ? posix(ic) : "")
         printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, (u in nom ? nom[u] : dn), d, (u in code ? code[u] : ""), u, e
      }
      /^\[/ { fin(); u = loc = dn = ic = ""; dedans = (tolower($0) ~ /\\\\uninstall\\\\/); next }
      dedans && /^"[^"]*"="/ {
         k = $0; sub(/^"/, "", k); sub(/".*$/, "", k)
         v = $0; sub(/^"[^"]*"="/, "", v); sub(/"$/, "", v)
         gsub(/\\\\/, "/", v); gsub(/\\"/, "\"", v)
         if (k == "UninstallString" && v ~ /Blizzard Uninstaller/ && match(v, /--uid=[^ "]+/)) u = tolower(substr(v, RSTART + 6, RLENGTH - 6))
         else if (k == "InstallLocation") loc = v
         else if (k == "DisplayName") dn = v
         else if (k == "DisplayIcon") ic = v
      }
      END { fin() }'
}
# ... et la place que chacun prend (octets ; quelques ms : peu de gros fichiers)
jeux() {
   # (pas de `read` en champs : IFS fond deux tabulations, et le code peut etre vide)
   jeux_registre | while IFS= read -r j_l; do
      j_t=$(du -sk "$(printf '%s' "$j_l" | cut -f3)/" 2>/dev/null | cut -f1)
      printf '%s\t%s\n' "$j_l" "$(( ${j_t:-0} * 1024 ))"
   done
}

# Battle.net.config : GameLaunchWindowBehavior 2 (quitter au lancement) -> 0
config_lancement() {
   cf=$(ls -d "$PFX/drive_c/users/"*/AppData/Roaming/Battle.net/Battle.net.config 2>/dev/null | head -1)
   [ -n "$cf" ] && grep -q '"GameLaunchWindowBehavior": *"2"' "$cf" 2>/dev/null || return 0
   sed 's/"GameLaunchWindowBehavior": *"2"/"GameLaunchWindowBehavior": "0"/' "$cf" >"$cf.cidre-neuf" && mv "$cf.cidre-neuf" "$cf" &&
      echo "    battlenet : GameLaunchWindowBehavior 2 -> 0 (le client reste ouvert pendant le jeu)"
}

# Les arguments du jeu (option `arguments` de sa fiche, ou CIDRE_ARGUMENTS, et ceux
# de `cidre play <id> -- ...`) : le client lance le jeu avec ses propres arguments,
# plus ceux de son reglage « Arguments de ligne de commande supplementaires »,
# AdditionalLaunchArguments du bloc Games.<uid> de Battle.net.config. Cidre y ajoute
# les siens, client ferme, et retient dans .cidre-bnet-args/<uid> ce qu'il a ajoute :
# la fois suivante il retire cela seul, et laisse ce que l'utilisateur y a mis a la
# main (une option deja la n'est pas doublee, tests/arguments_jeu.sh). Pas de
# guillemet ni de barre oblique inverse (la valeur est une chaine JSON) ; fin de
# ligne CRLF du fichier gardee.
bnet_config() { ls -d "$PFX/drive_c/users/"*/AppData/Roaming/Battle.net/Battle.net.config 2>/dev/null | head -1; }
# la valeur actuelle de AdditionalLaunchArguments pour <uid> (rien si absente)
args_actuels() { # <config> <uid>
   U=$2 awk 'BEGIN { u = "\"" ENVIRON["U"] "\": {" }
      { sub(/\r$/, "") }
      /^ *"Games": *\{/ { g = 1; next }
      g && index($0, u) { b = 1; next }
      b && /^ *}/ { exit }
      b && /"AdditionalLaunchArguments":/ { v = $0; sub(/^[^:]*: *"/, "", v); sub(/",? *$/, "", v); print v; exit }' "$1"
}
# pose <valeur> pour <uid> : remplace la ligne si le bloc du jeu l'a, sinon l'ajoute en
# tete du bloc ; code 1 si le bloc du jeu manque (jeu jamais vu par ce client). Deux
# lectures du fichier : la premiere dit si la cle est deja dans le bloc.
poser_args() { # <config> <uid> <valeur>
   U=$2 V=$3 awk 'BEGIN { u = "\"" ENVIRON["U"] "\": {"; v = ENVIRON["V"] }
      { cr = sub(/\r$/, ""); fin = cr ? "\r" : "" }
      /^ *"Games": *\{/ { g = 1 }
      FNR == NR { if (g && !vu && index($0, u)) { vu = 1; b = 1; next }
                  if (b && /^ *}/) b = 0
                  if (b && /"AdditionalLaunchArguments":/) a = 1
                  next }
      FNR == 1 { g = 0; b = 0 }
      g && !fait && index($0, u) && $0 !~ /\{ *}/ { print $0 fin; b = 1; ind = $0; sub(/[^ ].*$/, "", ind)
         if (!a) { print ind "    \"AdditionalLaunchArguments\": \"" v "\"," fin; fait = 1 }
         next }
      b && a && /"AdditionalLaunchArguments":/ { l = $0; sub(/"AdditionalLaunchArguments":.*$/, "", l)
         c = ($0 ~ /", *$/) ? "," : ""; print l "\"AdditionalLaunchArguments\": \"" v "\"" c fin; fait = 1; next }
      b && /^ *}/ { b = 0 }
      { print $0 fin }
      END { exit !fait }' "$1" "$1" >"$1.cidre-neuf" && mv "$1.cidre-neuf" "$1" || { rm -f "$1.cidre-neuf"; return 1; }
}
# les arguments que Cidre veut pour le jeu : ceux de la ligne de commande, puis ceux de la fiche qui n'y sont pas
args_voulus() { # <id> [arguments de la ligne de commande...]
   av_id=$1; shift
   av_f=${CIDRE_ARGUMENTS:-$(sh "$R/tests/profil_cidre.sh" "$av_id" 2>/dev/null | sed -n 's/^arguments=//p' | head -1)}
   av_n="$*"
   [ -z "$av_f" ] || av_n="$av_n $(sh "$R/tests/arguments_jeu.sh" "$av_f" "$@" | paste -sd ' ' -)"
   printf '%s' "$av_n" | awk '{ $1 = $1; print }'
}
regler_args() { # <id> [arguments de la ligne de commande...] : client ferme
   ra_id=$1; shift
   ra_cf=$(bnet_config); [ -n "$ra_cf" ] || return 0
   ra_uid=$(jeux_registre | awk -F'\t' -v i="$ra_id" '$1 == i { print $5; exit }'); [ -n "$ra_uid" ] || return 0
   ra_m=$PFX/.cidre-bnet-args/$ra_uid
   ra_neuf=$(args_voulus "$ra_id" "$@")
   case $ra_neuf in *'"'*|*'\'*) echo "    battlenet : arguments du jeu refuses (guillemet ou barre oblique inverse) : $ra_neuf"; return 0 ;; esac
   ra_cur=$(args_actuels "$ra_cf" "$ra_uid"); ra_old=$(cat "$ra_m" 2>/dev/null)
   # la part de l'utilisateur : la valeur, sans ce que Cidre y avait ajoute
   ra_user=$ra_cur
   if [ -n "$ra_old" ]; then
      case $ra_cur in "$ra_old") ra_user= ;; *" $ra_old") ra_user=${ra_cur%" $ra_old"} ;; esac
   fi
   # shellcheck disable=SC2086
   ra_add=$(sh "$R/tests/arguments_jeu.sh" "$ra_neuf" $ra_user | paste -sd ' ' -)
   ra_val=$(printf '%s %s' "$ra_user" "$ra_add" | awk '{ $1 = $1; print }')
   if [ "$ra_val" != "$ra_cur" ]; then
      if [ -z "$ra_cur" ] && ! grep -q '"AdditionalLaunchArguments":' "$ra_cf" && [ -z "$ra_val" ]; then :
      elif poser_args "$ra_cf" "$ra_uid" "$ra_val"; then
         echo "    battlenet : arguments du jeu pour $ra_uid : « $ra_val »${ra_user:+ (dont « $ra_user » pose a la main)}"
      else
         echo "    battlenet : $ra_uid absent de Battle.net.config, arguments du jeu non poses"; return 0
      fi
   fi
   mkdir -p "$PFX/.cidre-bnet-args"
   if [ -n "$ra_add" ]; then printf '%s\n' "$ra_add" >"$ra_m"; else rm -f "$ra_m"; fi
}

# La cle Run « Battle.net » (« Lancer Battle.net au demarrage » du client, qui la
# reecrit) : wineboot -u (prefixe_a_jour.sh) ouvrait alors le client, sans
# l'environnement du jeu, et `wineserver -w` l'attendait sans fin (manche du
# 21/10). Retiree, prefixe ferme, avant chaque ouverture.
sans_demarrage_auto() {
   awk 'tolower($0) ~ /^\[software\\\\microsoft\\\\windows\\\\currentversion\\\\run\]/ { d = 1; next } /^\[/ { d = 0 } d && /^"Battle\.net"=/ { t = 1 } END { exit !t }' "$PFX/user.reg" 2>/dev/null || return 0
   printf 'Battle.net\t\n' | WINEPREFIX=$PFX sh "$R/tests/reglages_jeu.sh" - ruche user.reg 'Software\Microsoft\Windows\CurrentVersion\Run' >/dev/null &&
      echo "    battlenet : demarrage automatique du client retire (wineboot l'ouvrait hors du jeu)"
}

# L'environnement qui passera au jeu (variables de la pile), en empreinte.
empreinte() {
   env | grep -E '^(FEX_|DXVK_|VKD3D_|MESA_|DXMT_|VK_|WINE|QT_|GST_|DYLD_|PROTON_OUVERT_|CIDRE_|LC_ALL=|LANG=)' \
       | grep -vE '^(CIDRE_STEAM_CPU|CIDRE_BNET_[A-Z_]*|CIDRE_ACCORD_NUAGE|WINEDEBUG)=' | LC_ALL=C sort | shasum | cut -c1-40
}

# Le client (ou l'installeur, aussi en Qt et CEF), en arriere-plan et detache :
# il survit a `cidre play`, qui attend le jeu.
lancer_client_prog() { # <journal> <programme Windows> [arguments]
   lc_j=$1; lc_p=$2; shift 2
   mkdir -p "$(dirname "$lc_j")"
   # (pas de « === » : `cidre log` prend la derniere ligne qui en commence une pour le debut du lancement)
   # (printf et non echo : le echo de sh lisait \t, \v... dans les chemins Windows)
   printf '    battlenet : %s %s %s\n' "$(date '+%F %T')" "$lc_p" "$*" >>"$lc_j"
   ( export WINEPREFIX="$PFX" QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-software} QT_OPENGL=${QT_OPENGL:-software}
     CIDRE_OVERLAY_DYLIB= nohup sh "$ETAPE2" "$lc_p" "$@" >>"$lc_j" 2>&1 </dev/null & )
}
lancer_client() { lc_1=$1; shift; lancer_client_prog "$lc_1" "$CLIENT_W" $CLIENT_ARGS "$@"; }

arreter_client() { # [raison]
   if serveur_vivant; then
      WINEPREFIX=$PFX "$W/bin/wineserver" -k 2>/dev/null
      i=0; while serveur_vivant && [ $i -lt 15 ]; do sleep 1; i=$((i + 1)); done
      serveur_vivant && WINEPREFIX=$PFX "$W/bin/wineserver" -k9 2>/dev/null
      echo "    battlenet : client ferme${1:+ ($1)}"
   fi
   rm -f "$MARQUE"
}

# --- Creation du prefixe, installation du client ---------------------------
INSTALLEUR_URL=${CIDRE_BNET_INSTALLEUR_URL:-https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe}
# La langue du Mac en locale Blizzard (frFR, enUS...) : une langue d'installeur
# differente de celle de la machine peut bloquer l'installation a 45 %.
locale_blizzard() {
   lb_l=$(sh "$R/tests/langue_cidre.sh" auto 2>/dev/null | sed -n 's/^locale=//p'); lb_l=${lb_l%%.*}
   lb_c=$(printf '%s' "$lb_l" | tr -d '_')
   case $lb_c in
      deDE|enUS|enGB|esES|esMX|frFR|itIT|jaJP|koKR|plPL|ptBR|ruRU|zhCN|zhTW) echo "$lb_c" ;;
      *) case ${lb_l%%_*} in
            de) echo deDE ;; es) echo esES ;; fr) echo frFR ;; it) echo itIT ;; ja) echo jaJP ;; ko) echo koKR ;;
            pl) echo plPL ;; pt) echo ptBR ;; ru) echo ruRU ;; zh) echo zhCN ;; *) echo enUS ;;
         esac ;;
   esac
}
# Un prefixe a lui, comme celui de Steam (configurer_cidre.sh, etapes 2 et 3),
# sans le pont Steam ni faux_steam. Deja la : remis au runtime (DLL de Wine,
# FEX), sauf si le client y tourne -- il le sera au prochain lancement.
creer() {
   if [ -f "$PFX/system.reg" ] && [ -d "$PFX/drive_c/windows/system32" ]; then
      if serveur_vivant; then echo "  prefixe Battle.net : en usage, remis au runtime au prochain lancement"; return 0; fi
      WINEPREFIX=$PFX sh "$R/tests/prefixe_a_jour.sh"
      WINE_ARM64=$W WINEPREFIX=$PFX sh "$R/tests/installer_fex.sh" >/dev/null 2>&1 || true
      echo "  prefixe Battle.net a jour ($PFX)"
      return 0
   fi
   mkdir -p "$PFX" || { echo "  prefixe Battle.net : impossible de creer $PFX" >&2; return 1; }
   echo "  prefixe Battle.net : creation dans $PFX (une minute)"
   ( export WINEPREFIX="$PFX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=d;mshtml=d"
     "$W/bin/wineboot" -u >/dev/null 2>&1 || true
     "$W/bin/wineserver" -w 2>/dev/null
     [ -d "$PFX/drive_c/windows/system32" ] || exit 1
     sh "$R/tests/prefixe_a_jour.sh" --marquer
     CIDRE_VC_WINE=$W/bin/wine sh "$R/tests/vcruntime_registre.sh" || true
     "$W/bin/wineserver" -w 2>/dev/null
     for d in d3d11 dxgi d3d10core d3d9 d3d8; do
        [ -f "$R/dxvk/async/$d.dll" ] && cp "$R/dxvk/async/$d.dll" "$PFX/drive_c/windows/system32/" 2>/dev/null || true
     done
     WINE_ARM64=$W sh "$R/tests/installer_fex.sh" >/dev/null 2>&1 || true ) \
      || { echo "  prefixe Battle.net : Wine n'a pas cree $PFX (cidre doctor)" >&2; return 1; }
   echo "  prefixe Battle.net cree"
}
# L'installeur officiel, ou CIDRE_BNET_INSTALLEUR (un fichier deja la, essais).
# Verifie : un executable Windows de plus de 1 Mo, signe au nom de Blizzard
# (le nom est cherche dans le bloc de signature : ce n'est pas une verification
# cryptographique de la signature, qu'un Mac sans outils ne sait pas faire ; le
# telechargement passe par HTTPS depuis downloader.battle.net).
installeur() {
   if [ -n "${CIDRE_BNET_INSTALLEUR:-}" ]; then printf '%s' "$CIDRE_BNET_INSTALLEUR"; return 0; fi
   i_f=$CIDRE_DIR/cache/Battle.net-Setup.exe
   mkdir -p "$CIDRE_DIR/cache" || return 1
   curl -fsSL --retry 2 --max-time 600 -o "$i_f.part" "$INSTALLEUR_URL" 2>/dev/null && mv "$i_f.part" "$i_f" || { rm -f "$i_f.part"; return 1; }
   printf '%s' "$i_f"
}
installeur_valide() {
   [ "$(head -c 2 "$1" 2>/dev/null)" = MZ ] && [ "$(wc -c <"$1" 2>/dev/null)" -gt 1000000 ] &&
      LC_ALL=C grep -aq 'Blizzard Entertainment' "$1"
}

absent() {
   [ -f "$CLIENT" ] && return 1
   echo "Battle.net n'est pas installe dans $PFX (client introuvable)." >&2
   return 0
}

case ${1:-} in
   prefixe)
      # avec un chemin : le prefixe ou le client est deja installe (retenu dans
      # battlenet.prefixe) ; « defaut » revient a wine/pfx-battlenet
      case ${2:-} in
         '') printf '%s\n' "$PFX" ;;
         defaut) rm -f "$CIDRE_DIR/battlenet.prefixe"; echo "prefixe Battle.net : $R/wine/pfx-battlenet" ;;
         *) np=$(cd "$2" 2>/dev/null && pwd -P) || { echo "dossier introuvable : $2" >&2; exit 1; }
            [ -f "$np/drive_c/Program Files (x86)/Battle.net/Battle.net.exe" ] && [ -f "$np/system.reg" ] \
               || { echo "$np n'est pas un prefixe Wine ou Battle.net est installe (Battle.net.exe introuvable)" >&2; exit 1; }
            mkdir -p "$CIDRE_DIR" && printf '%s\n' "$np" >"$CIDRE_DIR/battlenet.prefixe.tmp" && mv "$CIDRE_DIR/battlenet.prefixe.tmp" "$CIDRE_DIR/battlenet.prefixe"
            [ -z "${CIDRE_BNET_PREFIXE:-}" ] || echo "(CIDRE_BNET_PREFIXE est pose : il passe devant tant qu'il l'est)" >&2
            echo "prefixe Battle.net : $np" ;;
      esac ;;
   jeux) jeux ;;
   # les processus Windows que tient le serveur du prefixe (rien s'il ne tourne pas)
   pids) processus | cut -f1 ;;
   etat)
      [ -f "$CLIENT" ] && inst=true || inst=false
      dc=$(du_client); dj=$(des_jeux)
      [ -n "$dc" ] && ouv=true || ouv=false
      pour=; [ $ouv = false ] || pour=$(marque pour)
      jn=$(printf '%s' "$dj" | noms)
      if [ "${2:-}" = --json ]; then
         printf '{"prefixe":%s,"installe":%s,"ouvert":%s,"pour":%s,"jeu":%s,"jeux":%s}\n' "$(json "$PFX")" "$inst" "$ouv" \
            "$(json_ou_null "$pour")" "$(json_ou_null "$jn")" "$(jeux | wc -l | tr -d ' ')"
      else
         echo "prefixe : $PFX"
         echo "client  : $([ $inst = true ] && echo installe || echo absent)$([ $ouv = true ] && echo ", ouvert${pour:+ (pour $pour)}")"
         [ -z "$jn" ] || echo "en jeu  : $jn"
         jeux | awk -F'\t' '{ printf "jeu     : %s  %s%s\n", $1, $2, ($4 == "" ? " (code de lancement inconnu)" : "") }'
      fi ;;
   ouvrir)
      # --json (Verger) : une ligne d'evenement sur la sortie, les messages sur l'erreur
      J_=non; [ "${2:-}" = --json ] && J_=oui
      dire_() { if [ $J_ = oui ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
      if [ ! -f "$CLIENT" ]; then
         [ $J_ = non ] || printf '{"evenement":"erreur","code":"absent","message":%s}\n' "$(json "Battle.net n'est pas installe dans $PFX.")"
         absent; exit 5
      fi
      if [ -n "$(du_client)" ]; then
         [ $J_ = non ] || echo '{"evenement":"ouvert","deja":true}'
         dire_ "Battle.net est deja ouvert."; exit 0
      fi
      serveur_vivant || sans_demarrage_auto
      WINEPREFIX=$PFX sh "$R/tests/prefixe_a_jour.sh" >&2
      config_lancement >&2
      printf 'pour=client\n' >"$MARQUE"
      # Un jeu lance par « Jouer » du client herite de cet environnement, pas de sa
      # fiche : Diablo IV, le 24/10, est parti avec le d3d12 de Wine (D3D12CreateDevice
      # E_NOINTERFACE, « Echec de l'initialisation des systemes graphiques »). Les jeux
      # Battle.net vises sont en D3D12 : vkd3d-proton (system32, pose par un lancement en
      # dx12) passe devant, s'il est la. Le client, 32 bits, ne charge pas d3d12.
      grep -aq 'vkd3d-proton' "$PFX/drive_c/windows/system32/d3d12.dll" 2>/dev/null && export CIDRE_D3D12=${CIDRE_D3D12:-n}
      # la langue du Mac, comme l'installeur (Qt logiciel et --in-process-gpu : lancer_client)
      lancer_client "$JOURNAL_CLIENT" "--lang=$(locale_blizzard)"
      [ $J_ = non ] || echo '{"evenement":"ouvert","deja":false}'
      dire_ "Battle.net s'ouvre (une a deux minutes) : connecte-toi, installe ou mets a jour tes jeux. Lance-les par Cidre (Jouer dans Verger, ou \`cidre play bnet-...\`) : « Jouer » dans le client les lance sans les reglages de leur fiche." ;;
   arreter)
      dj=$(des_jeux)
      if [ -n "$dj" ] && [ "${2:-}" != --force ]; then
         echo "Un jeu Battle.net tourne ($(printf '%s' "$dj" | noms)) : quitte-le d'abord, ou \`cidre stop\`." >&2; exit 4
      fi
      if serveur_vivant; then arreter_client; else rm -f "$MARQUE"; echo "Battle.net n'etait pas ouvert."; fi ;;
   preparer)
      id=${2:?usage: battlenet.sh preparer <id> [arguments du jeu...]}; shift 2
      absent && exit 5
      dj=$(des_jeux)
      if [ -n "$dj" ]; then
         echo "    battlenet : un jeu tourne deja dans le prefixe Battle.net ($(printf '%s' "$dj" | noms)) : attends sa fin, ou \`cidre stop\`"
         exit 4
      fi
      if serveur_vivant; then
         # (le client relit Battle.net.config a son ouverture : des arguments changes le font rouvrir)
         if [ -n "$(du_client)" ] && [ "$(marque pour)" = "$id" ] && [ "$(marque arguments)" = "$(args_voulus "$id" "$@")" ]; then
            echo "    battlenet : client deja ouvert pour ce jeu"
         else
            pour=$(marque pour)
            arreter_client "ouvert ${pour:+pour $pour }; il sera rouvert pour ce jeu, avec son environnement"
         fi
      fi
      serveur_vivant || { config_lancement; sans_demarrage_auto; regler_args "$id" "$@"; }
      exit 0 ;;
   jouer)
      id=${2:?usage: battlenet.sh jouer <id> [arguments]}; shift 2
      absent && exit 5
      l=$(jeux | awk -F'\t' -v i="$id" '$1 == i')
      code=$(printf '%s' "$l" | cut -f4); exe=$(printf '%s' "$l" | cut -f6); nexe=${exe##*/}
      [ -n "$code" ] && [ -n "$nexe" ] || { echo "    battlenet : $id n'a pas de code de lancement (outil-steam/battlenet.conf)"; exit 2; }
      # (les arguments du jeu passent par Battle.net.config, poses par `preparer`)
      J=${CIDRE_BNET_JOURNAL:-$R/build/logs/steam-$id.log}
      emp=$(empreinte); garde=non
      if [ -n "$(du_client)" ]; then
         if [ "$(marque pour)" = "$id" ] && [ "$(marque empreinte)" = "$emp" ]; then garde=oui
         else arreter_client "ouvert avec un autre environnement"; fi
      fi
      debut=$(date +%s)
      if [ $garde = oui ]; then
         echo "    battlenet : client deja ouvert pour ce jeu, lancement de $code demande"
         lancer_client "$J" "--exec=launch $code"
      else
         printf 'pour=%s\nempreinte=%s\narguments=%s\n' "$id" "$emp" "$(args_voulus "$id" "$@")" >"$MARQUE"
         echo "    battlenet : ouverture du client ($CLIENT_ARGS, Qt logiciel), qui lancera $code"
         lancer_client "$J" "--exec=launch $code"
      fi
      # Le jeu. Une demande qui se perd (client encore a la connexion) est
      # refaite deux fois, tant que le jeu n'est pas la.
      ATT=${CIDRE_BNET_ATTENTE:-900}; relance=150; vu_client=non
      while :; do
         p=$(jeu_vu "$nexe"); [ -z "$p" ] || break
         t=$(( $(date +%s) - debut ))
         if [ -n "$(du_client)" ]; then vu_client=oui
         elif [ $vu_client = oui ] || [ $t -ge 60 ]; then
            echo "    battlenet : le client s'est ferme avant $nexe (apres $t s)"; exit 6
         fi
         [ $t -lt "$ATT" ] || { echo "    battlenet : $nexe pas vu apres $ATT s (connexion faite ? jeu a jour ?) ; client laisse ouvert"; exit 1; }
         if [ $t -ge $relance ] && [ $relance -le 400 ] && [ $vu_client = oui ]; then
            echo "    battlenet : $nexe pas encore la apres $t s : lancement de $code redemande"
            lancer_client "$J" "--exec=launch $code"; relance=$((relance + 250))
         fi
         sleep 2
      done
      echo "    battlenet : $nexe demarre apres $(( $(date +%s) - debut )) s (processus $p)"
      vides=0
      while [ $vides -lt 3 ]; do
         if [ -n "$(jeu_vu "$nexe")" ]; then vides=0; else vides=$((vides + 1)); fi
         sleep 2
      done
      echo "    battlenet : $nexe sorti apres $(( $(date +%s) - debut )) s ; client laisse ouvert (cidre battlenet arreter)"
      exit 0 ;;
   creer) creer ;;
   # (la locale Blizzard de la langue du Mac : essais)
   locale) locale_blizzard ;;
   installer)
      # --json : un evenement par ligne, pour Verger :
      #   {"evenement":"etape","etape":"prefixe"|"telechargement"|"installeur"|"client"}
      #   {"evenement":"installe","deja":bool,"prefixe":...}   {"evenement":"erreur","code":...,"message":...}
      J_=non; [ "${2:-}" = --json ] && J_=oui
      ev() { [ $J_ = non ] || printf '%s\n' "$1"; }
      dire_() { if [ $J_ = oui ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
      echec() { # <code> <message>
         ev "$(printf '{"evenement":"erreur","code":"%s","message":%s}' "$1" "$(json "$2")")"; echo "$2" >&2; exit 1; }
      if [ -f "$CLIENT" ]; then
         ev "$(printf '{"evenement":"installe","deja":true,"prefixe":%s}' "$(json "$PFX")")"
         dire_ "Battle.net est deja installe ($PFX) : \`cidre battlenet ouvrir\` pour te connecter ou installer un jeu."
         exit 0
      fi
      serveur_vivant && echec prefixe_en_usage "Le prefixe Battle.net est en usage (un programme Windows y tourne) : \`cidre battlenet arreter\`, puis recommence."
      # (l'installeur d'abord : hors ligne, pas de prefixe cree pour rien)
      ev '{"evenement":"etape","etape":"telechargement"}'
      dire_ "Telechargement de l'installeur Battle.net..."
      INST=$(installeur) || echec telechargement "L'installeur Battle.net n'a pas pu etre telecharge (hors ligne ?) : recommence une fois en ligne."
      installeur_valide "$INST" || { [ -n "${CIDRE_BNET_INSTALLEUR:-}" ] || rm -f "$INST"
         echec installeur_invalide "Le fichier telecharge n'est pas l'installeur de Blizzard (pas un executable Windows signe Blizzard Entertainment) : rien n'a ete lance."; }
      ev '{"evenement":"etape","etape":"prefixe"}'
      creer >&2 || echec prefixe "Le prefixe Battle.net n'a pas pu etre cree dans $PFX : \`cidre doctor\` dira si Wine demarre."
      LANG_B=$(locale_blizzard)
      ev '{"evenement":"etape","etape":"installeur"}'
      dire_ "Installation de Battle.net (langue $LANG_B) : suis l'installeur dans sa fenetre ; la connexion se fait ensuite dans le client."
      config_lancement >/dev/null
      printf 'pour=client\n' >"$MARQUE"
      INST_W="Z:$(printf '%s' "$INST" | tr '/' '\\')"
      lancer_client_prog "$JOURNAL_CLIENT" "$INST_W" "--lang=$LANG_B" '--installpath=C:\Program Files (x86)\Battle.net'
      # Le client installe apparait dans Program Files ; l'installeur l'ouvre ensuite.
      ATT=${CIDRE_BNET_ATTENTE_INSTALLATION:-1800}; t0=$(date +%s); vu=non
      while [ ! -f "$CLIENT" ]; do
         t=$(( $(date +%s) - t0 ))
         if processus | grep -qi 'battle\.net-setup\|battle\.net launcher\|[\\/]battle\.net[\\/]'; then vu=oui
         elif [ $vu = oui ] || [ $t -ge 120 ]; then
            echec installeur_ferme "L'installeur Battle.net s'est ferme sans installer le client (apres $t s) : journal $JOURNAL_CLIENT."
         fi
         [ $t -lt "$ATT" ] || echec trop_long "L'installation de Battle.net n'est pas finie apres $ATT s : l'installeur reste ouvert ; relance \`cidre battlenet installer\` quand il a fini."
         sleep 3
      done
      ev '{"evenement":"etape","etape":"client"}'
      ev "$(printf '{"evenement":"installe","deja":false,"prefixe":%s}' "$(json "$PFX")")"
      dire_ "Battle.net est installe ($PFX). Connecte-toi dans sa fenetre (coche « Rester connecte »), installe tes jeux, puis \`cidre play bnet-...\`." ;;
   *) echo "usage : battlenet.sh prefixe [<chemin>|defaut] | etat [--json] | jeux | pids | ouvrir [--json] | arreter [--force] | preparer <id> | jouer <id> [args] | creer | installer [--json]" >&2; exit 2 ;;
esac
exit 0
}
