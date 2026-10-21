#!/bin/sh
# planifier.sh activer [HH:MM] | desactiver | etat : lancement nocturne du banc par launchd (agent de l'utilisateur,
# domaine gui/<uid> : la session graphique est requise pour les jeux). DESACTIVE PAR DEFAUT : rien n'est installe
# tant que `activer` n'a pas ete lance. Heure par defaut 03:30. Un Mac endormi a l'heure dite lance le banc a son
# reveil ; le banc refuse de lui-meme si l'ecran est verrouille, si un jeu tourne ou si le M1 est tenu.
#   sh tests/banc_nocturne/planifier.sh activer 03:30
#   sh tests/banc_nocturne/planifier.sh desactiver
# Le banc lance est celui de ce dossier (il se copie dans le dossier de la nuit avant de s'executer).
set -eu
H=$(cd "$(dirname "$0")" && pwd)
. "$H/commun.sh"
ETIQ=fr.cidre.banc-nocturne
PL=$HOME/Library/LaunchAgents/$ETIQ.plist
DOM=gui/$(id -u)
case ${1:-} in
activer)
   HM=${2:-03:30}; HE=${HM%%:*}; MI=${HM#*:}
   case $HE$MI in *[!0-9]*|'') echo "heure HH:MM attendue" >&2; exit 2 ;; esac
   mkdir -p "$BANC" "$HOME/Library/LaunchAgents"
   cat > "$PL" <<FIN
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
   <key>Label</key><string>$ETIQ</string>
   <key>ProgramArguments</key>
   <array><string>/bin/sh</string><string>$H/nuit.sh</string></array>
   <key>StartCalendarInterval</key>
   <dict><key>Hour</key><integer>$(expr "$HE" + 0)</integer><key>Minute</key><integer>$(expr "$MI" + 0)</integer></dict>
   <key>EnvironmentVariables</key>
   <dict>
      <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
      <key>CIDRE_BANC</key><string>$BANC</string>
   </dict>
   <key>ProcessType</key><string>Interactive</string>
   <key>StandardOutPath</key><string>$BANC/launchd.log</string>
   <key>StandardErrorPath</key><string>$BANC/launchd.log</string>
</dict>
</plist>
FIN
   plutil -lint "$PL" >/dev/null
   launchctl bootout "$DOM/$ETIQ" 2>/dev/null || true
   launchctl bootstrap "$DOM" "$PL"
   echo "banc nocturne active chaque nuit a $HM ($PL)" ;;
desactiver)
   launchctl bootout "$DOM/$ETIQ" 2>/dev/null || true
   rm -f "$PL"
   echo "banc nocturne desactive" ;;
etat)
   if launchctl print "$DOM/$ETIQ" >/dev/null 2>&1; then
      echo "actif : $(plutil -extract StartCalendarInterval.Hour raw "$PL"):$(plutil -extract StartCalendarInterval.Minute raw "$PL") ($PL)"
   else echo "inactif"; fi
   [ -f "$BANC/derniere.txt" ] && echo "derniere nuit : $(cat "$BANC/derniere.txt")"
   [ -f "$BANC/candidat" ] && echo "candidat : $(head -1 "$BANC/candidat")" || echo "candidat : aucun (contre-epreuve A/A)"
   ;;
*) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
