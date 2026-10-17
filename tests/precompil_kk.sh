#!/bin/sh
# Pipelines precompiles par jeu pour KosmicKrisp (correctif 0165), cote joueur.
#
# Au premier lancement d'un jeu en D3D12 (ou Vulkan natif), KosmicKrisp compile
# chaque bibliotheque depuis son MSL puis chaque pipeline pour la puce : des
# minutes, des heures pour Detroit: Become Human (99 453 pipelines). Cidre peut
# livrer ce travail fait d'avance : l'AIR des bibliotheques (le meme pour toute
# une famille de MSL : Apple7, c'est-a-dire M1, ou Apple8 et suivants, et pour
# toute version de macOS), et, en plus s'il y en a une, une archive de pipelines
# par architecture de GPU ET version majeure de macOS (applegpu_g16g-macos27 :
# Metal refuse une archive faite par le compilateur d'un autre macOS). Au
# demarrage d'un jeu, KosmicKrisp cree surtout des bibliotheques (Detroit :
# ~100 000, pour 87 pipelines Metal) : l'AIR seul fait l'essentiel du gain.
# KosmicKrisp les prend dans le dossier MESA_KK_PRECOMPIL, que le lanceur pose.
#
# Les paquets sont des assets de la release « precompil » du depot, decrits par
# precompil-index.tsv : appid, famille, kk, element (air, ou <arch>-macos<N>),
# fichier, parties, taille, sha256 (du fichier entier). « kk » designe la version
# du generateur de MSL de KosmicKrisp (empreinte de la serie de correctifs mesa,
# $R/kk-msl.txt dans un runtime) : un paquet fait pour un autre KosmicKrisp ne
# servirait a rien (chaque bibliotheque se recompilerait), on ne le prend pas.
# Un asset de plus de 2 Gio est decoupe en parties (.part01, .part02...).
# Telechargement a la demande seulement (`cidre precompil`, fin de `cidre dl`),
# jamais au demarrage de Cidre.
#
# usage :
#   precompil_kk.sh arch                   l'architecture GPU de ce Mac (ou inconnu)
#   precompil_kk.sh famille                apple7 | apple8 | inconnu
#   precompil_kk.sh kk                     la version du generateur de MSL de ce runtime
#   precompil_kk.sh dossier <id>           le dossier a donner a MESA_KK_PRECOMPIL (rien si aucun)
#   precompil_kk.sh etat <id> [--json]     installe | disponible | absent | sans_reseau, et les tailles
#   precompil_kk.sh telecharger <id> [--json]
#                                          prend ce qui manque (AIR, et l'archive de cette
#                                          architecture pour ce macOS s'il y en a une)
#   precompil_kk.sh retirer <id>
# Variables : CIDRE_DIR, CIDRE_PRECOMPIL_SANS_RESEAU=1 (l'index en cache seulement), CIDRE_PRECOMPIL_URL (base des assets, defaut la release
# precompil de gtranche/cidre), CIDRE_PRECOMPIL_ARCH et CIDRE_PRECOMPIL_FAMILLE
# (essais : se faire passer pour une autre puce).
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
BASE=${CIDRE_PRECOMPIL_URL:-https://github.com/gtranche/cidre/releases/download/precompil}
CACHE="$CIDRE_DIR/cache"
INDEX="$CACHE/precompil-index.tsv"
ACTION=${1:-}; ID=${2:-}; JSON=non
for a in "$@"; do [ "$a" = --json ] && JSON=oui; done

arch() {
   [ -n "${CIDRE_PRECOMPIL_ARCH:-}" ] && { echo "$CIDRE_PRECOMPIL_ARCH"; return; }
   modele=$(sysctl -n hw.model 2>/dev/null)
   f="$CACHE/puce-gpu"
   if [ -f "$f" ] && [ "$(cut -f1 "$f")" = "$modele" ]; then cut -f2 "$f"; return; fi
   b="$R/build/puce-gpu"
   a=inconnu
   [ -x "$b" ] && a=$("$b" 2>/dev/null)
   case $a in applegpu_*) mkdir -p "$CACHE"; printf '%s\t%s\n' "$modele" "$a" >"$f" ;; *) a=inconnu ;; esac
   echo "$a"
}
famille() {
   [ -n "${CIDRE_PRECOMPIL_FAMILLE:-}" ] && { echo "$CIDRE_PRECOMPIL_FAMILLE"; return; }
   n=$(sh "$R/tests/machine.sh" famille_gpu 2>/dev/null | sed -n 's/^famille_gpu=//p')
   case $n in 7) echo apple7 ;; ''|*[!0-9]*) echo inconnu ;; *) [ "$n" -ge 8 ] && echo apple8 || echo inconnu ;; esac
}
# La version du generateur de MSL : livree dans le runtime, sinon (arbre de
# developpement) l'empreinte des correctifs mesa de la serie.
kk() {
   if [ -s "$R/kk-msl.txt" ]; then head -1 "$R/kk-msl.txt"; return; fi
   [ -f "$R/tests/series.sh" ] || { echo inconnu; return; }
   ( . "$R/tests/series.sh"; serie_mesa | while read -r f; do cat "$f"; done ) | shasum -a 256 | cut -c1-12
}
dossier_jeu() { echo "$CIDRE_DIR/precompil/$1"; }
# l'element d'archive de ce Mac : <arch>-macos<version majeure>
elt_archive() { echo "$1-macos$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"; }

# L'index de la release, garde un jour ; « frais » le redemande. 0 : index la ;
# 1 : pas d'index (hors ligne, ou release absente).
index() {
   if [ "${1:-}" != frais ] && [ -s "$INDEX" ] && [ -z "$(find "$INDEX" -mmin +1440 2>/dev/null)" ]; then return 0; fi
   # CIDRE_PRECOMPIL_SANS_RESEAU=1 (`cidre info`) : l'index en cache seulement
   [ "${CIDRE_PRECOMPIL_SANS_RESEAU:-}" = 1 ] && [ "${1:-}" != frais ] && { [ -s "$INDEX" ]; return; }
   mkdir -p "$CACHE"
   code=$(curl -sSL --connect-timeout 10 --max-time 60 -o "$INDEX.tmp" -w '%{http_code}' "$BASE/precompil-index.tsv" 2>/dev/null)
   case $code in
      200|000) [ "$code" = 000 ] && [ ! -s "$INDEX.tmp" ] && { rm -f "$INDEX.tmp"; [ -s "$INDEX" ]; return; }
               mv "$INDEX.tmp" "$INDEX"; return 0 ;;   # (000 : file://, essais)
      404) # pas de release : un index vide, garde comme l'autre (rien a telecharger)
               rm -f "$INDEX.tmp"; echo "# pas de paquets publies" >"$INDEX"; return 0 ;;
   esac
   rm -f "$INDEX.tmp"
   [ -s "$INDEX" ]
}
# Les lignes de l'index pour ce jeu, cette famille et ce KosmicKrisp : l'AIR et,
# s'il y en a une, l'archive de cette architecture pour ce macOS.
entrees() { # <id> <famille> <kk> <arch>
   awk -F'\t' -v id="$1" -v fa="$2" -v kk="$3" -v ar="$(elt_archive "$4")" \
      '!/^#/ && $1 == id && $2 == fa && $3 == kk && ($4 == "air" || $4 == ar)' "$INDEX" 2>/dev/null
}
# <id> : le dossier si l'AIR est la pour ce KosmicKrisp (et l'archive de ce Mac si
# le paquet en avait une : notee dans « elements »)
installe() {
   d="$(dossier_jeu "$1")/$(famille)"
   [ "$(cat "$d/kk" 2>/dev/null)" = "$(kk)" ] && [ -d "$d/air" ] || return 1
   if grep -qx "archive" "$d/elements" 2>/dev/null; then [ -f "$d/archives/$(elt_archive "$(arch)").metallib" ] || return 1; fi
   echo "$d"
}
a_air() { printf '%s\n' "$1" | cut -f4 | grep -qx air; }

json_chaine() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
dire() { if [ "$JSON" = oui ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
evenement() { [ "$JSON" != oui ] || printf '%s\n' "$1"; }

case $ACTION in
   arch) arch ;;
   famille) famille ;;
   kk) kk ;;
   dossier)
      [ -n "$ID" ] || exit 2
      installe "$ID" ;;
   etat)
      [ -n "$ID" ] || exit 2
      A=$(arch); F=$(famille); K=$(kk)
      if d=$(installe "$ID"); then
         E=installe; T=$(du -sk "$d" 2>/dev/null | cut -f1); T=$((${T:-0} * 1024))
      elif index; then
         T=$(entrees "$ID" "$F" "$K" "$A" | awk -F'\t' '{ s += $7 } END { printf "%d", s }')
         if a_air "$(entrees "$ID" "$F" "$K" "$A")"; then E=disponible; else E=absent; T=0; fi
      else
         E=sans_reseau; T=0
      fi
      if [ "$JSON" = oui ]; then
         printf '{"etat":"%s","arch":"%s","famille":"%s","kk":"%s","taille":%s}\n' "$E" "$A" "$F" "$K" "$T"
      else
         echo "etat=$E"; echo "arch=$A"; echo "famille=$F"; echo "kk=$K"; echo "taille=$T"
      fi ;;
   telecharger)
      [ -n "$ID" ] || exit 2
      A=$(arch); F=$(famille); K=$(kk)
      case $F in inconnu) dire "pipelines precompiles : famille de GPU inconnue"; exit 1 ;; esac
      if d=$(installe "$ID"); then dire "pipelines precompiles de $ID : deja installes ($d)"; evenement '{"evenement":"precompil","etat":"installe"}'; exit 0; fi
      index frais || { dire "pipelines precompiles : index injoignable (hors ligne ?)"; evenement '{"evenement":"precompil","etat":"sans_reseau"}'; exit 1; }
      L=$(entrees "$ID" "$F" "$K" "$A")
      if ! a_air "$L"; then
         dire "pipelines precompiles : rien pour $ID ($F, $A, KosmicKrisp $K)"
         evenement '{"evenement":"precompil","etat":"absent"}'; exit 0
      fi
      D=$(dossier_jeu "$ID"); DF="$D/$F"; T="$D/.telechargement"
      rm -rf "${T:?}"; mkdir -p "$T"
      total=$(printf '%s\n' "$L" | awk -F'\t' '{ s += $7 } END { printf "%d", s }')
      dire "pipelines precompiles de $ID : $(( total / 1048576 )) Mo ($F, $A)"
      fait=0
      printf '%s\n' "$L" | while IFS='	' read -r _ _ _ el fichier parties taille sha; do
         : >"$T/$el.tar.zst"
         k=1
         while [ "$k" -le "$parties" ]; do
            nom=$fichier; [ "$parties" -gt 1 ] && nom=$(printf '%s.part%02d' "$fichier" "$k")
            curl -fsSL --connect-timeout 15 --retry 3 -o "$T/partie" "$BASE/$nom" || { echo "echec : $nom" >"$T/erreur"; exit 1; }
            cat "$T/partie" >>"$T/$el.tar.zst"; rm -f "$T/partie"
            k=$((k + 1))
         done
         [ "$(shasum -a 256 "$T/$el.tar.zst" | cut -c1-64)" = "$sha" ] || { echo "empreinte fausse : $fichier" >"$T/erreur"; exit 1; }
         fait=$((fait + taille))
         [ "$JSON" != oui ] || printf '{"evenement":"precompil","etat":"en_cours","octets":%s,"total":%s}\n' "$fait" "$total"
      done
      if [ -f "$T/erreur" ]; then
         dire "pipelines precompiles : $(cat "$T/erreur")"; rm -rf "${T:?}"
         evenement '{"evenement":"precompil","etat":"echoue"}'; exit 1
      fi
      # Pose : un autre KosmicKrisp ou une autre architecture laissent la place.
      rm -rf "${DF:?}.neuf"; mkdir -p "$DF.neuf"
      for f in "$T"/*.tar.zst; do tar -xf "$f" -C "$DF.neuf" || { dire "pipelines precompiles : archive illisible"; rm -rf "${T:?}" "${DF:?}.neuf"; exit 1; }; done
      echo "$K" >"$DF.neuf/kk"
      printf '%s\n' "$L" | cut -f4 | grep -qv '^air$' && echo archive >"$DF.neuf/elements" || : >"$DF.neuf/elements"
      rm -rf "${DF:?}" "${T:?}"; mv "$DF.neuf" "$DF"
      dire "pipelines precompiles de $ID : installes ($DF)"
      evenement '{"evenement":"precompil","etat":"installe"}' ;;
   retirer)
      [ -n "$ID" ] || exit 2
      rm -rf "$(dossier_jeu "$ID")" ;;
   *) sed -n '/^# usage/,/^# Variables/p' "$0" >&2; exit 2 ;;
esac
