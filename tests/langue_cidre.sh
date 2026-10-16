#!/bin/sh
# La langue d'un jeu, sous ses trois formes. Lu par lancer_depuis_steam.sh (la
# locale annoncee par Wine, le fichier de reglages du jeu) et par `cidre`
# (les depots de langue que SteamCMD installe).
#
#   langue_cidre.sh <auto|code>
#
# rend, une par ligne :
#   code=fr                 la langue Cidre (option `langue`, outil-steam/langues.conf)
#   locale=fr_FR.UTF-8      LC_ALL/LANG du Wine du jeu : la locale Windows qu'il annonce
#   steam=french            le nom Steam (app_update -language, depots de langue)
#   origine=mac|profil      d'ou elle vient
#   mac=fr-FR               la premiere langue de macOS (vide si illisible)
#
# « auto » (defaut) = la premiere langue de macOS (Reglages Systeme > General >
# Langue et region), sinon l'anglais. Un code (profil, CIDRE_LANGUE) l'emporte.
# On ne s'en remet pas a l'environnement : Verger herite LANG=C.UTF-8, et Steam
# lance ses jeux sous LC_ALL=en_US.UTF-8 -- Wine annoncait alors en-US a tous
# les jeux, et un Unreal (Sherlock Holmes Chapter One) demarrait en anglais.
# CIDRE_LANGUE_MAC=fr-FR remplace la lecture de macOS (essais).
set -u
DEMANDE=${1:-auto}

MAC=${CIDRE_LANGUE_MAC-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2{s/[[:space:]",]//g;p;}')}

# <langue> <script> <region> -> "code locale steam"
traduire() {
   tr_l=$1; tr_s=$2; tr_r=$3
   case $tr_l in
      fr) set -- fr FR french ;;      en) set -- en US english ;;
      de) set -- de DE german ;;      it) set -- it IT italian ;;
      ru) set -- ru RU russian ;;     pl) set -- pl PL polish ;;
      ja) set -- ja JP japanese ;;    ko) set -- ko KR koreana ;;
      nl) set -- nl NL dutch ;;       sv) set -- sv SE swedish ;;
      da) set -- da DK danish ;;      fi) set -- fi FI finnish ;;
      nb|no) set -- nb NO norwegian ;; tr) set -- tr TR turkish ;;
      uk) set -- uk UA ukrainian ;;   cs) set -- cs CZ czech ;;
      hu) set -- hu HU hungarian ;;   el) set -- el GR greek ;;
      ro) set -- ro RO romanian ;;    bg) set -- bg BG bulgarian ;;
      th) set -- th TH thai ;;        vi) set -- vi VN vietnamese ;;
      ar) set -- ar SA arabic ;;      id) set -- id ID indonesian ;;
      es) case $tr_r in ''|ES) set -- es ES spanish ;; *) set -- es MX latam ;; esac ;;
      pt) case $tr_r in PT) set -- pt PT portuguese ;; *) set -- pt BR brazilian ;; esac ;;
      zh) case $tr_s$tr_r in Hant*|*TW|*HK|*MO) set -- zh TW tchinese ;; *) set -- zh CN schinese ;; esac ;;
      *) return 1 ;;
   esac
   # la region de macOS quand elle est un pays (fr-CA -> fr_CA), pas une zone (es-419)
   case $tr_r in [A-Z][A-Z]) [ "$3" = latam ] || set -- "$1" "$tr_r" "$3" ;; esac
   echo "$1 ${1}_$2.UTF-8 $3"
}

# fr-FR, zh-Hans-CN, es-419, en -> langue, script, region
decouper() {
   dc_l=${1%%[-_]*}; dc_reste=${1#"$dc_l"}; dc_reste=${dc_reste#[-_]}
   dc_s=; dc_r=
   case $dc_reste in [A-Z][a-z][a-z][a-z]*) dc_s=${dc_reste%%[-_]*}; dc_reste=${dc_reste#"$dc_s"}; dc_reste=${dc_reste#[-_]} ;; esac
   dc_r=${dc_reste%%[-_@]*}
   echo "$(printf '%s' "$dc_l" | tr '[:upper:]' '[:lower:]') ${dc_s:-_} ${dc_r:-_}"
}

MAC_T=
if [ -n "$MAC" ]; then
   set -- $(decouper "$MAC"); [ "$2" = _ ] && s= || s=$2; [ "$3" = _ ] && r= || r=$3
   MAC_T=$(traduire "$1" "$s" "$r" 2>/dev/null || true)
fi

# un code que Cidre ne connait pas vaut « auto », comme dans le lanceur
case $DEMANDE in fr|en|de|es|it|pt|ru|pl|ja|ko|zh) ;; *) DEMANDE=auto ;; esac
case $DEMANDE in
   auto)
      ORIGINE=mac; T=$MAC_T
      [ -n "$T" ] || T=$(traduire en '' '') ;;
   *)
      ORIGINE=profil
      # la langue du Mac quand c'est la meme : sa region avec (fr + fr-CA -> fr_CA)
      if [ -n "$MAC_T" ] && [ "${MAC_T%% *}" = "$DEMANDE" ]; then T=$MAC_T
      else T=$(traduire "$DEMANDE" '' ''); fi ;;
esac
set -- $T
printf 'code=%s\nlocale=%s\nsteam=%s\norigine=%s\nmac=%s\n' "$1" "$2" "$3" "$ORIGINE" "$MAC"
exit 0
