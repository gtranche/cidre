#!/bin/sh
# Brancher les nouveaux jeux tout seul, sans commande a taper.
#
#   installer_agent_steam.sh            pose l'agent
#   installer_agent_steam.sh --retirer  le retire
#
# Ce que ca fait : un agent de session macOS surveille le dossier steamapps et
# le fichier que Steam reecrit en quittant. Quand l'un bouge, il relance
# brancher_jeux_steam.sh --ecrire. Celui-ci refuse d'ecrire tant que Steam
# tourne, ne touche jamais une option de lancement personnelle, et ne fait rien
# quand tout est deja en place : on peut donc le declencher sans precaution.
#
# Rien n'est installe dans le systeme : l'agent vit dans ~/Library/LaunchAgents,
# qui est a l'utilisateur, et il se retire d'une commande.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
STEAM=${STEAM:-$HOME/Library/Application Support/Steam}
ETIQUETTE=com.proton-ouvert.brancher
PLIST=$HOME/Library/LaunchAgents/$ETIQUETTE.plist

if [ "${1:-}" = "--retirer" ]; then
   launchctl bootout "gui/$(id -u)/$ETIQUETTE" 2>/dev/null || true
   rm -f "$PLIST"
   echo "agent retire"
   exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ETIQUETTE</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$R/tests/brancher_jeux_steam.sh</string>
    <string>--ecrire</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>$STEAM/steamapps</string>
    <string>$STEAM/registry.vdf</string>
  </array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$R/build/logs/agent-steam.log</string>
  <key>StandardErrorPath</key><string>$R/build/logs/agent-steam.log</string>
</dict>
</plist>
PLISTEOF

mkdir -p "$R/build/logs"
launchctl bootout "gui/$(id -u)/$ETIQUETTE" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "agent pose : $PLIST"
launchctl print "gui/$(id -u)/$ETIQUETTE" 2>/dev/null | sed -n 's/^\tstate = /  etat : /p'
echo "  journal : $R/build/logs/agent-steam.log"
