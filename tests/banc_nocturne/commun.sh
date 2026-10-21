# commun.sh : fonctions partagees du banc nocturne (lu par `.`).
BANC=${CIDRE_BANC:-$HOME/Dev/cidre-banc-nocturne}
TAB=$(printf '\t')

# session verrouillee ? (une mesure ecran verrouille ne vaut rien : le jeu attend sa presentation)
ecran_verrouille() { ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'; }
# session hors console (changement rapide d'utilisateur, ecran de connexion)
hors_console() { ! ioreg -n Root -d1 | grep -q '"kCGSSessionOnConsoleKey"=Yes'; }

# un jeu, un wineserver ou un temoin tourne-t-il deja (n'importe quel arbre, n'importe quelle session) ?
# Rend la raison sur stdout, vide si rien.
deja_occupe() {
   if pgrep -x wineserver >/dev/null; then echo "wineserver en cours (pid $(pgrep -x wineserver | tr '\n' ' '))"; return; fi
   if pgrep -f "steamapps/common/" >/dev/null; then echo "un jeu Steam tourne (pid $(pgrep -f 'steamapps/common/' | head -3 | tr '\n' ' '))"; return; fi
   if pgrep -f "wine64-preloader|wine-preloader|/bin/wine " >/dev/null; then echo "un processus Wine tourne"; return; fi
   if pgrep -f "/Jeux Cidre/|Application Support/Cidre/games/" >/dev/null; then echo "un jeu Cidre tourne"; return; fi
}

# moyenne des N derniers releves d'images/s d'un journal (CIDRE_DXMT_STATS ou CIDRE_WSI_STATS)
releves() { # journal -> une valeur par ligne
   grep -a -E "cidre-stats: [0-9.]+ images|\[CIDRE_WSI\] [0-9.]+ images/s" "$1" 2>/dev/null |
      sed -E 's/.*(cidre-stats:|\[CIDRE_WSI\]) ([0-9.]+) images.*/\2/'
}

# verdict d'un temoin : <journal> <rc|bloque> -> "statut<TAB>resume<TAB>mesures"
# Un temoin qui a des lignes « bilan » est juge sur elles seules (temoin_sync_reveils : ses ECHEC « ev » sont une
# limite connue, son bilan dit ok) ; sinon toute ligne ECHEC ou « N echec(s) » avec N > 0 le fait echouer.
verdict_temoin() {
   log=$1; rc=$2
   res=$(tr -d '\r' < "$log" | grep -a -i -E "echec\(s\)|bilan|-> ok|: ok|injoignables" | tail -1 | cut -c1-110)
   [ -n "$res" ] || res=$(tr -d '\r' < "$log" | grep -a -v '^#' | tail -1 | cut -c1-110)
   mes=$(tr -d '\r' < "$log" | grep -a -E "ns par|us par tour|ms par appel" | sed -E 's/.* ([0-9.]+) (ns|us|ms) par.*/\1\2/' | head -6 | tr '\n' ' ')
   fin=$(tr -d '\r' < "$log" | grep -a -i "echec(s)" | tail -1)
   if [ "$rc" = bloque ]; then st=BLOQUE
   elif [ "$rc" != 0 ]; then st=ECHEC; res="rc=$rc ; $res"
   elif grep -a -q -E "WineDbg attached|Unhandled exception|page fault on" "$log"; then st=ECHEC; res="plantage ; $res"
   elif grep -a -q "^bilan" "$log"; then
      # Wine ecrit des fins de ligne CRLF : sans tr, aucune ligne ne finit par « -> ok »
      if tr -d '\r' < "$log" | grep -a "^bilan" | grep -q -e 'ECHEC' -e '-> ok$' -v; then st=ECHEC
      elif grep -a "^bilan" "$log" | grep -q ECHEC; then st=ECHEC; else st=ok; fi
   elif [ -n "$fin" ]; then
      # la ligne de synthese fait foi (h64sous_page : sa partie VirtualAlloc, informative, ecrit des ECHEC)
      if echo "$fin" | grep -q -E "^ECHEC|[1-9][0-9]* echec"; then st=ECHEC; else st=ok; fi
   elif tr -d '\r' < "$log" | grep -a -q -E "^ECHEC|-> ECHEC"; then st=ECHEC
   else st=ok; fi
   printf '%s\t%s\t%s\n' "$st" "$res" "${mes:--}"
}
