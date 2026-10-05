#!/bin/sh
# Le nom du compte Steam que le client a memorise (config/loginusers.vdf) :
# celui marque MostRecent, sinon le premier. Une ligne vide s'il n'y en a pas,
# code 1 si le fichier est illisible.
#
#   compte_steam.sh [loginusers.vdf]
F=${1:-$HOME/Library/Application Support/Steam/config/loginusers.vdf}
[ -r "$F" ] || exit 1
# Un bloc par compte, entre une accolade et la suivante.
LC_ALL=C awk '
   function clore() {
      if (compte != "" && recent) { print compte; trouve = 1; exit }
      if (compte != "" && premier == "") premier = compte
      compte = ""; recent = 0
   }
   /^[ \t\r]*[{}][ \t\r]*$/ { clore(); next }
   compte == "" && match($0, /"AccountName"[ \t]*"[^"]+"/) {
      compte = substr($0, RSTART, RLENGTH - 1)
      sub(/^"AccountName"[ \t]*"/, "", compte)
   }
   /"MostRecent"[ \t]*"1"/ { recent = 1 }
   END { if (!trouve) { clore(); if (!trouve) print premier } }
' "$F"
