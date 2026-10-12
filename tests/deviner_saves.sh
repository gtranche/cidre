#!/bin/sh
# Devine ou un jeu range ses sauvegardes, quand ni le saves.conf livre ni celui
# de l'utilisateur ne le disent -- pour que Verger n'ait pas a le demander.
#
#   deviner_saves.sh <appid> [depuis]   ecrit le dossier relatif (meme forme que
#                                       saves.conf : `AppData/...` sous le dossier
#                                       utilisateur du prefixe, ou `jeu:...`) et
#                                       rend 0 ; rien et 1 si on ne sait pas.
#
# Deux sources, dans l'ordre :
# 1. La fiche de la base de profils ([compat.pcgamingwiki] sauvegardes, releve
#    de PCGamingWiki) quand c'est un dossier sous le dossier utilisateur
#    (AppData/..., Documents/..., Saved Games/...) ou dans le jeu (jeu:...) ;
#    un motif de fichiers (`jeu:*.sav`) est tronque a son dossier. Les formes
#    `steam:` (Steam Cloud) et `registre:` ne sont pas des dossiers : ignorees.
#    Retenue seulement si le dossier existe deja : la fiche peut se tromper.
# 2. Apres une partie (`depuis` = date de lancement, en secondes epoch), les
#    dossiers de sauvegarde que les moteurs connus creent, modifies depuis :
#    AppData/Local/<X>/Saved/SaveGames (Unreal), AppData/LocalLow/<dev>/<jeu>
#    (Unity), Documents/My Games/<jeu>, Saved Games/<jeu>, AppData/Roaming/<X>
#    et le dossier du jeu lui-meme (fichiers .sav/.save). Plusieurs candidats :
#    celui dont le fichier est le plus recent. Sans `depuis`, cette source
#    n'est pas consultee : un dossier ancien peut etre celui d'un autre jeu.
#
# Pour les essais : CIDRE_PREFIXE_UTIL (dossier utilisateur du prefixe),
# CIDRE_JEU_DOSSIER (dossier du jeu), CIDRE_FICHE_SAUVEGARDES (valeur de la
# fiche, `-` pour aucune).
set -u
APPID=${1:?usage: deviner_saves.sh <appid> [depuis]}
DEPUIS=${2:-}
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}

UTIL=${CIDRE_PREFIXE_UTIL:-}
if [ -z "$UTIL" ]; then
   a=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1)
   [ -n "$a" ] && UTIL=$(dirname "$a")
fi
JEUDIR=${CIDRE_JEU_DOSSIER:-}
[ -n "$JEUDIR" ] || JEUDIR=$(sh "$R/cidre" chemin "$APPID" 2>/dev/null || true)

# --- 1. la fiche ----------------------------------------------------------------
fiche_sauvegardes() {
   if [ -n "${CIDRE_FICHE_SAUVEGARDES:-}" ]; then
      [ "$CIDRE_FICHE_SAUVEGARDES" = - ] || printf '%s\n' "$CIDRE_FICHE_SAUVEGARDES"; return 0
   fi
   f=$(sh "$R/tests/fiche_profil.sh" chemin "$APPID" 2>/dev/null) || return 0
   [ -n "$f" ] || return 0
   sh "$R/tests/fiche_profil.sh" toml "$f" 2>/dev/null \
      | awk -F'\t' '$1 == "compat.pcgamingwiki" && $2 == "sauvegardes" { print $4; exit }'
}
# un chemin de la fiche -> dossier relatif saves.conf, ou rien
normaliser() { # <valeur>
   v=$(printf '%s' "$1" | sed 's|\\|/|g; s|^ *||; s| *$||')
   # plusieurs emplacements separes par « ; » : le premier qui est un dossier
   case $v in *\;*) v=${v%%;*}; v=$(printf '%s' "$v" | sed 's| *$||') ;; esac
   case $v in
      steam:*|registre:*|'') return 1 ;;
      jeu:*)      v="jeu:$(printf '%s' "${v#jeu:}" | sed 's|^/||')" ;;
      AppData/*|Documents/*|"Saved Games/"*) ;;
      *) return 1 ;;
   esac
   # un motif de fichiers (etoile, point d'interrogation, <uid>) : son dossier
   case $v in
      *[\*\?\<]*) v=$(printf '%s' "$v" | sed 's|/[^/]*[*?<][^/]*$||') ;;
   esac
   v=${v%/}
   [ -n "$v" ] && [ "$v" != jeu: ] || return 1
   printf '%s\n' "$v"
}
absolu() { # <relatif> -> chemin absolu
   case $1 in
      jeu:*) [ -n "$JEUDIR" ] && printf '%s\n' "$JEUDIR/${1#jeu:}" ;;
      *)     [ -n "$UTIL" ] && printf '%s\n' "$UTIL/$1" ;;
   esac
}
v=$(fiche_sauvegardes)
if rel=$(normaliser "$v"); then
   d=$(absolu "$rel")
   if [ -n "$d" ] && [ -d "$d" ]; then printf '%s\n' "$rel"; exit 0; fi
fi

# --- 2. apres une partie : les dossiers des moteurs connus, modifies depuis ------
[ -n "$DEPUIS" ] || exit 1
case $DEPUIS in ''|*[!0-9]*) exit 1 ;; esac
# un fichier temoin date de DEPUIS, pour `find -newer` (le find de macOS ne lit
# pas une date epoch)
REF=$(mktemp "${TMPDIR:-/tmp}/deviner-saves.XXXXXX"); trap 'rm -f "$REF"' EXIT
touch -t "$(date -r "$DEPUIS" '+%Y%m%d%H%M.%S')" "$REF" 2>/dev/null || exit 1
# le fichier le plus recent d'un dossier, s'il est posterieur a DEPUIS : « mtime<TAB>dossier »
plus_recent() { # <dossier>
   find "$1" -type f -newer "$REF" 2>/dev/null | grep -avE '/cache/|/logs?/|/crash|\.log$|\.tmp$' | while IFS= read -r f; do
      stat -f '%m' "$f" 2>/dev/null
   done | sort -n | tail -1
}
candidats() {
   [ -n "$UTIL" ] && for g in "$UTIL"/AppData/Local/*/Saved/SaveGames "$UTIL"/AppData/LocalLow/*/* \
                              "$UTIL/Documents/My Games"/* "$UTIL/Saved Games"/* "$UTIL"/AppData/Roaming/*; do
      [ -d "$g" ] || continue
      rel=${g#$UTIL/}
      case $rel in */Microsoft/*|*/CryptnetUrlCache*|*/Temp*|*/wine*) continue ;; esac
      m=$(plus_recent "$g"); [ -n "$m" ] && printf '%s\t%s\n' "$m" "$rel"
   done
   if [ -n "$JEUDIR" ] && [ -d "$JEUDIR" ]; then
      find "$JEUDIR" -type f -newer "$REF" \( -iname '*.sav' -o -iname '*.save' -o -iname '*.dat' \) 2>/dev/null \
         | grep -avE '/cache/|/logs?/' | head -200 | while IFS= read -r f; do
         printf '%s\t%s\n' "$(stat -f '%m' "$f" 2>/dev/null)" "jeu:$(dirname "${f#$JEUDIR/}")"
      done | sort -t"$(printf '\t')" -k2,2 -u
   fi
}
c=$(candidats | sort -n | tail -1 | cut -f2-)
[ -n "$c" ] || exit 1
printf '%s\n' "$c"
