#!/bin/sh
# `cidre diag <id>` : l'archive de diagnostic d'un jeu, a envoyer a l'equipe
# depuis un Mac qu'on ne peut pas approcher (testeurs sans ssh). Tout ce qui
# aide a comprendre un lancement rate y est, masque :
#
#   resume.txt       20 lignes : versions, machine, verdict de doctor, cause
#                    probable du dernier lancement, shaders, plantages, systeme
#   versions.txt     Cidre (runtime), Verger, macOS, puce, famille GPU (machine.sh)
#   doctor.txt       `cidre doctor` (pas quand un jeu tourne : il lance Wine)
#   journal.txt      `cidre log <id>` : le dernier lancement, sans les traces
#   explication.txt  tests/expliquer_sortie.sh sur ce lancement
#   play.txt         ce que `cidre play` a ecrit (le journal que garde Verger)
#   profil.txt       le profil resolu (profil_cidre.sh) et les reglages du joueur
#   fiche.toml       la fiche du jeu (base de profils), fiche.json telle qu'elle vaut ici
#   shaders.txt      etat des shaders (etat_shaders.sh), pipelines precompiles,
#                    reserve d'AIR locale de KosmicKrisp
#   systeme.txt      wineserver, processeur, memoire, disque, ecran verrouille,
#                    alimentation et temperature, Game Mode
#   plantages/       les rapports .ips recents du jeu et de Wine (7 jours, 5 au plus)
#   capture.png      SEULEMENT avec --capture (ecran entier, trois secondes apres)
#
# Confidentialite : chaque fichier texte passe par tests/masquer_diag.awk
# (dossier personnel, nom de session et nom complet, noms du Mac, numero de
# serie et UUID materiel, comptes Steam, jetons, e-mails, IP). Rien ne part
# d'ici : l'envoi est une autre commande (`cidre diag envoyer`, apres accord du
# testeur). La capture, une image, n'est pas masquee : elle n'est prise que si
# le testeur la demande.
#
#   diag_cidre.sh <id> [--json] [--capture] [--sans-doctor] [--play <fichier>] [--verger <version>]
#
# Sortie : le resume et la liste de ce qui partirait ; en --json, un objet :
#   {"archive":..., "dossier":..., "octets":n, "format":"tar.gz", "jeu":{"id","nom"},
#    "resume":[...], "fichiers":[{"nom","octets"}], "masques":{"chemin":n,...},
#    "capture":bool, "service":{"configure":bool,"chiffre":bool}}
# Codes : 0 archive faite, 1 jeu inconnu / echec, 2 usage.
#
# L'archive et son dossier (pour que le testeur voie exactement ce qui part)
# vont dans $CIDRE_DIR/diagnostics/ ; on y garde les 5 derniers.
# Pour les essais : CIDRE_DIAG_RACINE (le runtime a lire, $R par defaut),
# CIDRE_DIAG_PLANTAGES (dossier des .ips), CIDRE_DIAG_SANS_SYSTEME=1.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
RT=${CIDRE_DIAG_RACINE:-$R}
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
STEAM=${CIDRE_STEAM_DIR:-$HOME/Library/Application Support/Steam}
# 8 Mio : la limite du service de depot (service/diag-depot)
MAX=${CIDRE_DIAG_MAX:-8388608}

ID=; JSON=non; CAPTURE=non; DOCTOR=oui; PLAY=; VERGER=${CIDRE_VERGER_VERSION:-}
while [ $# -gt 0 ]; do
   case $1 in
      --json) JSON=oui ;; --capture) CAPTURE=oui ;; --sans-doctor) DOCTOR=non ;;
      --play) PLAY=${2:-}; shift ;; --verger) VERGER=${2:-}; shift ;;
      -*) echo "option inconnue : $1" >&2; exit 2 ;;
      *) ID=$1 ;;
   esac
   shift
done
case $ID in ''|*[!a-z0-9-]*) echo "usage: cidre diag <id> [--json] [--capture] [--sans-doctor]" >&2; exit 2 ;; esac

CIDRE="$RT/cidre"
info=$(sh "$CIDRE" info "$ID" --json 2>/dev/null)
[ -n "$info" ] || { echo "jeu inconnu : $ID" >&2; exit 1; }
nom=$(printf '%s' "$info" | sed -n 's/^{"id":"[^"]*","appid":[^,]*,"nom":"\([^"]*\)".*/\1/p')
[ -n "$nom" ] || nom=$(sh "$CIDRE" list 2>/dev/null | awk -v i="$ID" '$1 == i { $1 = ""; sub(/^ +/, ""); print; exit }' | cut -c1-26 | sed 's/ *$//')

stamp=$(date +%Y%m%d-%H%M%S)
BASE="diag-$ID-$stamp"
OUT="$CIDRE_DIR/diagnostics"
D="$OUT/$BASE"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 143' TERM INT HUP
mkdir -p "$T/brut/plantages" "$D" || exit 1
B="$T/brut"

# une commande, avec une limite de temps ; sa sortie (erreurs comprises) dans un fichier
limite() { # <secondes> <fichier> commande...
   l_d=$1 l_f=$2; shift 2
   "$@" >"$l_f" 2>&1 &
   l_p=$!; l_i=0
   while [ $l_i -lt "$l_d" ] && kill -0 $l_p 2>/dev/null; do sleep 1; l_i=$((l_i + 1)); done
   if kill -0 $l_p 2>/dev/null; then
      kill -TERM $l_p 2>/dev/null; sleep 1; kill -KILL $l_p 2>/dev/null; wait $l_p 2>/dev/null
      echo "(arrete apres $l_d s)" >>"$l_f"; return 124
   fi
   wait $l_p
}
section() { printf '\n== %s ==\n' "$1"; }

# --- Capture, sur demande seulement ----------------------------------------
# D'abord, trois secondes apres l'appel : Verger se cache le temps de la prendre
# (l'ecran du jeu, pas sa propre fenetre), puis reapparait.
if [ $CAPTURE = oui ]; then
   screencapture -x -T 3 "$D/capture.png" 2>/dev/null || rm -f "$D/capture.png"
fi

# --- Versions ---------------------------------------------------------------
v_cidre=$(cat "$RT/VERSION" 2>/dev/null); v_cidre=${v_cidre:-dev}
if [ -z "$VERGER" ]; then
   for app in /Applications/Verger.app "$HOME/Applications/Verger.app"; do
      [ -f "$app/Contents/Info.plist" ] && { VERGER=$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null); break; }
   done
fi
v_macos=$(sw_vers -productVersion 2>/dev/null)
{
   echo "cidre      : $v_cidre ($RT)"
   [ -d "$RT/.git" ] && echo "cidre git  : $(git -C "$RT" log -1 --format='%h %cs' 2>/dev/null)"
   echo "verger     : ${VERGER:-inconnu}"
   echo "macos      : $v_macos ($(sw_vers -buildVersion 2>/dev/null))"
   echo "modele     : $(sysctl -n hw.model 2>/dev/null)"
   echo "arch       : $(uname -m) ; rosetta : $(arch -x86_64 /usr/bin/true 2>/dev/null && echo oui || echo non)"
   section "machine.sh"
   sh "$RT/tests/machine.sh" 2>&1
   section "cidre status"
   sh "$CIDRE" status 2>&1
} >"$B/versions.txt"
fait() { sed -n "s/^$1=//p" "$B/versions.txt" | head -1; }

# --- Doctor -----------------------------------------------------------------
# Il lance Wine (un programme de service) : pas pendant qu'un jeu tourne.
en_cours=non
pgrep -f "$RT/wine/.*wineserver" >/dev/null 2>&1 && en_cours=oui
if [ $DOCTOR = non ]; then
   echo "(doctor non lance : --sans-doctor)" >"$B/doctor.txt"
elif [ $en_cours = oui ]; then
   echo "(doctor non lance : un jeu tourne, il aurait partage son serveur Wine)" >"$B/doctor.txt"
else
   limite 120 "$B/doctor.txt" sh "$RT/tests/diagnostic_cidre.sh"
fi

# --- Journal du dernier lancement, et son explication ----------------------
sh "$CIDRE" log "$ID" 4000 >"$B/journal.txt" 2>&1
J="$RT/build/logs/steam-$ID.log"
rc=$(sed -n 's/.*le jeu s.est termine sur le code \([0-9][0-9]*\).*/\1/p' "$B/journal.txt" | tail -1)
if [ -f "$J" ]; then
   CIDRE_JEU="$ID" CIDRE_CLIENT_STEAM_ETAT=${CIDRE_CLIENT_STEAM_ETAT:-inconnu} \
      limite 20 "$B/explication.txt" sh "$RT/tests/expliquer_sortie.sh" "${rc:-1}" "$J"
else
   echo "(aucun journal de lancement pour $ID)" >"$B/explication.txt"
fi
[ -n "$PLAY" ] || PLAY="$HOME/Library/Logs/Verger/play-$ID.log"
if [ -f "$PLAY" ]; then tail -n 2000 "$PLAY" >"$B/play.txt"; else echo "(pas de sortie de cidre play gardee par Verger)" >"$B/play.txt"; fi

# --- Profil et fiche --------------------------------------------------------
{
   echo "== profil resolu =="
   sh "$RT/tests/profil_cidre.sh" "$ID" env 2>&1
   echo; echo "== reglages poses par le joueur =="
   sh "$RT/tests/profil_cidre.sh" "$ID" perso 2>&1
} >"$B/profil.txt"
fiche=$(sh "$RT/tests/fiche_profil.sh" chemin "$ID" 2>/dev/null)
if [ -n "$fiche" ] && [ -f "$fiche" ]; then
   cp "$fiche" "$B/fiche.toml"
   sh "$RT/tests/fiche_profil.sh" json "$ID" >"$B/fiche.json" 2>&1
fi

# --- Shaders ----------------------------------------------------------------
voie=$(sh "$RT/tests/etat_shaders.sh" voie "$ID" 2>/dev/null)
{
   echo "voie : ${voie:-?}"
   sh "$RT/tests/etat_shaders.sh" etat "$ID" 2>&1
   section "pipelines precompiles (precompil_kk.sh)"
   sh "$RT/tests/precompil_kk.sh" etat "$ID" 2>&1
   section "reserve d'AIR locale (KosmicKrisp, 0171)"
   AL="$CIDRE_DIR/air-local/$ID"
   if [ -d "$AL" ]; then
      for v in "$AL"/*; do
         [ -d "$v" ] || continue
         printf '%s : %s bibliotheques, %s\n' "$(basename "$v")" "$(ls "$v/air" 2>/dev/null | grep -c '\.metallib$')" "$(du -sh "$v" 2>/dev/null | cut -f1)"
      done
   else
      echo "aucune"
   fi
   section "cache de pipelines (vkd3d-cache)"
   du -sh "$CIDRE_DIR/vkd3d-cache/$ID" 2>/dev/null || echo "aucun"
} >"$B/shaders.txt"

# --- Rapports de plantage ---------------------------------------------------
# Ceux du jeu (son dossier, son executable) et de Wine : sept jours, cinq au plus.
IPS=${CIDRE_DIAG_PLANTAGES:-$HOME/Library/Logs/DiagnosticReports}
jdir=$(sh "$CIDRE" chemin "$ID" 2>/dev/null)
jnom=$(basename "${jdir:-/aucun}")
n_ips=0
for f in $(find "$IPS" -maxdepth 2 -name '*.ips' -mtime -7 2>/dev/null | xargs ls -t 2>/dev/null); do
   [ $n_ips -ge 5 ] && break
   # la premiere ligne (en-tete JSON) et le chemin du processus
   tete=$(head -c 4000 "$f" 2>/dev/null)
   case $tete in
      *wine*|*Wine*|*preloader*|*"$RT"*|*"$jnom"*) ;;
      *) continue ;;
   esac
   cp "$f" "$B/plantages/$(basename "$f")" && n_ips=$((n_ips + 1))
done

# --- Systeme ----------------------------------------------------------------
if [ "${CIDRE_DIAG_SANS_SYSTEME:-}" != 1 ]; then
{
   echo "date        : $(date '+%Y-%m-%d %H:%M:%S %z')"
   echo "demarre     : $(sysctl -n kern.boottime 2>/dev/null | sed 's/.*} //')"
   echo "wineserver  : $( [ $en_cours = oui ] && echo actif || echo arrete )"
   pgrep -fl wineserver 2>/dev/null | sed 's/^/  /'
   # l'ecran verrouille : une mesure de jeu faite ainsi ne vaut rien
   verrou=non
   ioreg -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes' && verrou=oui
   echo "ecran verrouille : $verrou"
   # Game Mode : macOS ne dit pas s'il est actif (gamepolicyctl absent) ; il
   # s'active seul en plein ecran, pour un executable qui le declare.
   echo "game mode   : non observable (activation automatique de macOS en plein ecran)"
   section "processeur : les 15 processus les plus gourmands"
   ps -Ao pcpu,pmem,rss,comm -r 2>/dev/null | head -16 | sed 's|/Users/[^/]*/|~/|'
   section "memoire"
   memory_pressure -Q 2>/dev/null | tail -1
   vm_stat 2>/dev/null | head -12
   sysctl vm.swapusage 2>/dev/null
   section "disque"
   df -h "$HOME" "$CIDRE_DIR" ${jdir:+"$jdir"} 2>/dev/null | awk '!vu[$0]++'
   section "alimentation et temperature"
   pmset -g batt 2>/dev/null | head -3
   pmset -g therm 2>/dev/null | grep -v '^$' | head -5
   section "ecrans"
   system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|Type|Resolution|Retina|Main Display|Refresh|Mirror' | head -12
} >"$B/systeme.txt" 2>&1
fi

# --- Masquage ---------------------------------------------------------------
# Les textes propres a cette machine, le plus long d'abord (masquer_diag.awk trie).
L="$T/litteraux.tsv"
moi=$(id -un)
{
   printf 'chemin\t%s\t~\n' "$HOME"
   printf 'chemin\t/Users/%s\t/Users/‹utilisateur›\n' "$moi"
   printf 'chemin\t%s\t‹utilisateur›\n' "$moi"
   n_complet=$(id -F 2>/dev/null); [ -z "$n_complet" ] || printf 'chemin\t%s\t‹nom›\n' "$n_complet"
   for n in "$(scutil --get ComputerName 2>/dev/null)" "$(scutil --get LocalHostName 2>/dev/null)" "$(hostname 2>/dev/null)" "$(hostname -s 2>/dev/null)"; do
      [ -z "$n" ] || printf 'machine\t%s\t‹mac›\n' "$n"
   done
   ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -nE 's/.*"(IOPlatformSerialNumber|IOPlatformUUID)" = "([^"]*)".*/\2/p' |
      while IFS= read -r n; do printf 'machine\t%s\t‹serie›\n' "$n"; done
   # tous les comptes Steam connus du client : noms de connexion et de profil
   sed -nE 's/.*"(AccountName|PersonaName)"[[:space:]]*"([^"]*)".*/\2/p' "$STEAM/config/loginusers.vdf" 2>/dev/null |
      while IFS= read -r n; do printf 'compte_steam\t%s\t‹steam›\n' "$n"; done
   [ -z "${CIDRE_STEAM_USER:-}" ] || printf 'compte_steam\t%s\t‹steam›\n' "$CIDRE_STEAM_USER"
} | awk -F'\t' 'length($2) >= 3 && !vu[tolower($2)]++' >"$L"
C="$T/comptes.tsv"; : >"$C"
( cd "$B" && find . -type f ) | while IFS= read -r f; do
   f=${f#./}; mkdir -p "$D/$(dirname "$f")"
   DIAG_LITTERAUX="$L" DIAG_COMPTES="$C" LC_ALL=C awk -f "$R/tests/masquer_diag.awk" "$B/$f" >"$D/$f"
done
masques=$(awk -F'\t' '{ t[$1] += $2 } END { for (k in t) print k "\t" t[k] }' "$C" | sort)

# --- Resume (20 lignes au plus : c'est ce que lit la coordination) ---------
alertes=$(grep -c '^  -> .*\(PAS \|NON\|probleme\|ABSENT\)' "$D/doctor.txt" 2>/dev/null)
premiere=$(grep -m1 '^  -> .*\(PAS \|NON\|probleme\|ABSENT\)' "$D/doctor.txt" 2>/dev/null | sed 's/^  -> //' | cut -c1-110)
if grep -q '^(doctor non lance' "$D/doctor.txt"; then d_res=$(head -1 "$D/doctor.txt")
else d_res="${alertes:-0} alerte(s)${premiere:+ ; $premiere}"; fi
entete=$(grep -m1 '^=== [0-9]' "$D/journal.txt" 2>/dev/null | cut -c5-80)
cause=$(sed -n 's/^ *cause probable : //p' "$D/explication.txt" | head -1 | cut -c1-150)
afaire=$(sed -n 's/^ *a faire : //p' "$D/explication.txt" | head -1 | cut -c1-150)
sh_etat=$(sed -n 's/^etat=//p' "$D/shaders.txt" | head -1)
air=$(awk '/^== reserve/ { r = 1; next } /^== / { r = 0 } r' "$D/shaders.txt" | head -1)
prof=$(grep -E '^(d3d11|dx12|tso|windows_version|sortie|clavier)=' "$D/profil.txt" | tr '\n' ' ' | cut -c1-140)
f_etat=$(sed -n 's/^etat *= *"\([^"]*\)".*/\1/p' "$D/fiche.toml" 2>/dev/null | head -1)
f_orig=$(sed -n 's/.*"origine":"\([^"]*\)".*/\1/p' "$D/fiche.json" 2>/dev/null | head -1)
ips=$(ls -t "$D/plantages" 2>/dev/null | head -3 | tr '\n' ' ')
cpu=$(sed -n '/^== processeur/,/^== /p' "$D/systeme.txt" 2>/dev/null | sed -n '3p' | awk '{ c = $1; $1 = $2 = $3 = ""; sub(/^ +/, ""); n = split($0, p, "/"); print p[n] " " c " %" }')
mem=$(sed -n 's/^System-wide memory free percentage: /memoire libre /p' "$D/systeme.txt" 2>/dev/null | head -1)
verrou=$(sed -n 's/^ecran verrouille : //p' "$D/systeme.txt" 2>/dev/null)
masq_ligne=$(printf '%s\n' "$masques" | awk -F'\t' 'NF == 2 { printf "%s%s %s", s, $1, $2; s = ", " }')
{
   echo "diagnostic Cidre du $(date '+%Y-%m-%d %H:%M') -- jeu $ID${nom:+ ($nom)}"
   echo "cidre $v_cidre · verger ${VERGER:-?} · macOS $v_macos · $(fait puce) (famille_gpu $(fait famille_gpu), $(fait memoire_go) Go) · $(sysctl -n hw.model 2>/dev/null)"
   echo "doctor : $d_res"
   echo "dernier lancement : ${entete:-aucun}${rc:+ ; code $rc}"
   [ -z "$cause" ] || echo "cause probable : $cause"
   [ -z "$afaire" ] || echo "a faire : $afaire"
   echo "voie : ${voie:-?} ; shaders : ${sh_etat:-?} ; air local : ${air:-?}"
   echo "profil : ${prof:-?}"
   echo "fiche : ${f_etat:-aucune}${f_orig:+ ($f_orig)}"
   echo "plantages : $n_ips rapport(s) .ips sur 7 jours${ips:+ : $ips}"
   echo "systeme : wineserver $( [ $en_cours = oui ] && echo actif || echo arrete ) ; ecran verrouille ${verrou:-?} ; ${mem:-memoire ?} ; en tete du processeur : ${cpu:-?}"
   echo "masque : ${masq_ligne:-rien}"
   echo "capture : $( [ -f "$D/capture.png" ] && echo oui || echo non )"
} | DIAG_LITTERAUX="$L" LC_ALL=C awk -f "$R/tests/masquer_diag.awk" | cut -c1-300 >"$D/resume.txt"

# --- Archive ----------------------------------------------------------------
# gzip, toujours : il est sur tout Mac (zstd non, sans Homebrew), et c'est un
# format que GitHub accepte en piece jointe -- le repli quand le service ne
# repond pas. Un diagnostic pese quelques dizaines de Ko : zstd n'y gagnerait rien d'utile.
archiver() {
   FORMAT=tar.gz; A="$OUT/$BASE.tar.gz"
   ( cd "$OUT" && COPYFILE_DISABLE=1 tar -czf "$A" "$BASE" )
}
archiver || { echo "archive impossible dans $OUT" >&2; exit 1; }
taille() { stat -f %z "$1" 2>/dev/null || echo 0; }
# Trop lourde pour le service : on reduit ce qui pese (capture, journaux, plantages).
if [ "$(taille "$A")" -gt "$MAX" ]; then
   rm -f "$A" "$D/capture.png"
   for f in journal.txt play.txt; do tail -n 600 "$D/$f" >"$T/x" && mv "$T/x" "$D/$f"; done
   ls -t "$D/plantages" 2>/dev/null | tail -n +3 | while IFS= read -r f; do rm -f "$D/plantages/$f"; done
   echo "(archive reduite : elle depassait $MAX octets)" >>"$D/resume.txt"
   archiver
fi
# on garde les 5 derniers diagnostics
ls -dt "$OUT"/diag-* 2>/dev/null | awk '{ sub(/\.tar\.(zst|gz)$/, ""); if (!vu[$0]++) n++; if (n > 5) print }' |
   while IFS= read -r v; do rm -rf "$v" "$v.tar.zst" "$v.tar.gz"; done

# --- Ce qui partirait -------------------------------------------------------
service=$(sh "$R/tests/envoyer_diag.sh" service --json 2>/dev/null)
[ -n "$service" ] || service='{"configure":false,"chiffre":false}'
fichiers=$( cd "$D" && find . -type f | sed 's|^\./||' | sort | while IFS= read -r f; do printf '%s\t%s\n' "$f" "$(taille "$f")"; done )
if [ $JSON = oui ]; then
   js() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')"; }
   printf '{"archive":%s,"dossier":%s,"octets":%s,"format":"%s","jeu":{"id":%s,"nom":%s},"resume":[' \
      "$(js "$A")" "$(js "$D")" "$(taille "$A")" "$FORMAT" "$(js "$ID")" "$(js "${nom:-}")"
   s=; while IFS= read -r l; do printf '%s%s' "$s" "$(js "$l")"; s=,; done <"$D/resume.txt"
   printf '],"fichiers":['
   s=; printf '%s\n' "$fichiers" | while IFS="$(printf '\t')" read -r f o; do [ -n "$f" ] || continue; printf '%s{"nom":%s,"octets":%s}' "$s" "$(js "$f")" "$o"; s=,; done
   printf '],"masques":{'
   s=; printf '%s\n' "$masques" | while IFS="$(printf '\t')" read -r k n; do [ -n "$k" ] || continue; printf '%s%s:%s' "$s" "$(js "$k")" "$n"; s=,; done
   printf '},"capture":%s,"service":%s}\n' "$( [ -f "$D/capture.png" ] && echo true || echo false )" "$service"
else
   cat "$D/resume.txt"
   echo
   echo "Contenu ($(taille "$A") octets, $FORMAT), masque avant de partir :"
   printf '%s\n' "$fichiers" | awk -F'\t' 'NF == 2 { printf "  %-40s %s octets\n", $1, $2 }'
   echo "Archive : $A"
   echo "Dossier (a relire) : $D"
fi
exit 0
