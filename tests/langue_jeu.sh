#!/bin/sh
# Pose la langue voulue dans le fichier de reglages d'un jeu qui ne suit ni la
# locale Windows ni Steam (table outil-steam/langues.conf). Appele par
# lancer_depuis_steam.sh avant le jeu.
# Ne reecrit que la valeur de la cle ; le reste du fichier passe tel quel. Ne
# cree pas le fichier : sans lui, le jeu n'a pas encore tourne et l'ecrira
# lui-meme, la langue sera posee au lancement suivant. Non bloquant.
#   langue_jeu.sh <appid> <code> [une-fois]
# une-fois (option `langue` = « auto », la langue du Mac) : posee une seule fois
# par langue du Mac, notee dans ETAT/<appid> ; la langue choisie ensuite dans le
# jeu reste la sienne. Un code du profil, lui, est repose a chaque lancement.
set -u
APPID=${1:-}; CODE=${2:-}; MODE=${3:-}
ETAT=${CIDRE_LANGUE_ETAT:-$HOME/Library/Application Support/Cidre/langue}
[ -n "$APPID" ] && [ -n "$CODE" ] || exit 0
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
CONF=${CIDRE_LANGUES:-$R/outil-steam/langues.conf}
[ -f "$CONF" ] || exit 0

LIGNE=$(awk -F'\t' -v a="$APPID" '!/^#/ && $1==a {print; exit}' "$CONF")
[ -n "$LIGNE" ] || exit 0
if [ "$MODE" = une-fois ] && [ "$(cat "$ETAT/$APPID" 2>/dev/null)" = "$CODE" ]; then
   echo "    langue : « $CODE » deja posee une fois (langue du Mac) ; le choix fait dans le jeu est garde"
   exit 0
fi
noter() { [ "$MODE" = une-fois ] || return 0; mkdir -p "$ETAT" && printf '%s\n' "$CODE" >"$ETAT/$APPID"; }
REL=$(printf '%s\n' "$LIGNE" | cut -f2)
CLE=$(printf '%s\n' "$LIGNE" | cut -f3)
VAL=$(printf '%s\n' "$LIGNE" | cut -f4 | tr ' ' '\n' | sed -n "s/^$CODE=//p" | head -1)
[ -n "$VAL" ] || { echo "    langue : le jeu n'a pas « $CODE », reglages du jeu inchanges"; exit 0; }

UH=$(ls -d "$PFX/drive_c/users/"*/AppData 2>/dev/null | head -1); [ -n "$UH" ] || exit 0
F="$(dirname "$UH")/$REL"
[ -f "$F" ] || { echo "    langue : $REL absent (premier lancement ?), rien a regler"; exit 0; }

awk -v cle="$CLE" -v val="$VAL" '
   {
      fin = ""; if (sub(/\r$/, "")) fin = "\r"
      i = index($0, "=")
      c = i ? substr($0, 1, i - 1) : ""; gsub(/[ \t]/, "", c)
      # cle au premier niveau seulement : une ligne indentee est dans un bloc
      if (!fait && i && c == cle && $0 !~ /^[ \t]/) {
         v = substr($0, i + 1); debut = substr($0, 1, i)
         match(v, /^[ \t]*/); debut = debut substr(v, 1, RLENGTH); v = substr(v, RLENGTH + 1)
         g = (v ~ /^"/) ? "\"" : ""
         $0 = debut g val g; fait = 1
      }
      print $0 fin
   }
   END { if (!fait) print cle " = \"" val "\"" }
' "$F" >"$F.langue-tmp" || { rm -f "$F.langue-tmp"; exit 0; }

if cmp -s "$F" "$F.langue-tmp"; then
   rm -f "$F.langue-tmp"
   echo "    langue : $CLE = $VAL deja en place"
   noter
else
   # cat, pas mv : le fichier garde ses droits et son inode
   cat "$F.langue-tmp" >"$F" && echo "    langue : $CLE = $VAL ecrit dans $REL" && noter
   rm -f "$F.langue-tmp"
fi
exit 0
