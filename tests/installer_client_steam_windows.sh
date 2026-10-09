#!/bin/sh
# Pose dans un prefixe Wine les DLL du client Steam de Windows.
#
#   installer_client_steam_windows.sh <prefixe>
#
# Un jeu protege par le DRM de Steam (enveloppe SteamStub) lit au registre le
# chemin de steamclient.dll, verifie dans ce fichier la signature de Valve, puis
# le charge. Cidre fait comme Proton : la DLL authentique est chargee telle
# quelle, et Wine detourne ses exports vers lsteamclient, qui relaie au client
# Steam de macOS -- ou l'utilisateur est connecte, et ou Valve verifie qu'il
# possede le jeu. Sans ces fichiers, tout jeu protege s'arrete sur
# « Application load error 3:0000065432 ».
#
# Proton les copie depuis le client Steam de Linux (legacycompat/) ; celui de
# macOS ne les a pas. On les prend donc la ou Valve les publie : le manifeste
# du client Windows, son paquet bins_win32, empreinte verifiee. On ne les
# redistribue pas, on ne les modifie pas.
set -u
PFX=${1:?usage: installer_client_steam_windows.sh <prefixe>}
CDN=${CIDRE_STEAM_CDN:-https://steamcdn-a.akamaihd.net/client}
DEST="$PFX/drive_c/Program Files (x86)/Steam"
FICHIERS="steamclient.dll steamclient64.dll Steam.dll"

complet() { for f in $FICHIERS; do [ -s "$DEST/$f" ] || return 1; done; }
if complet; then echo "  DLL du client Steam : deja la"; exit 0; fi

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

curl -fsSL --retry 3 -m 60 -o "$T/manifeste" "$CDN/steam_client_win32" || {
   echo "  manifeste du client Steam injoignable ($CDN)" >&2; exit 1; }
# Le bloc « "bins_win32" { "file" "bins_win32.zip.<hash>" ... "sha2" "<sha256>" } ».
paquet=$(awk -F'"' '$2 == "bins_win32" { p = 1 } p && $2 == "file" { print $4; exit }' "$T/manifeste")
sha=$(awk -F'"' '$2 == "bins_win32" { p = 1 } p && $2 == "sha2" { print $4; exit }' "$T/manifeste")
[ -n "$paquet" ] && [ -n "$sha" ] || { echo "  manifeste du client Steam illisible" >&2; exit 1; }

echo "  telechargement des DLL du client Steam (60 Mo, chez Valve)..."
curl -fsSL --retry 3 -m 900 -o "$T/paquet.zip" "$CDN/$paquet" || {
   echo "  telechargement impossible : $paquet" >&2; exit 1; }
obtenu=$(openssl dgst -sha256 -r "$T/paquet.zip" | cut -d' ' -f1)
[ "$obtenu" = "$sha" ] || { echo "  empreinte inattendue pour $paquet : on ne l'installe pas" >&2; exit 1; }

mkdir -p "$T/contenu" "$DEST"
# shellcheck disable=SC2086
unzip -oq "$T/paquet.zip" $FICHIERS -d "$T/contenu" || { echo "  archive illisible : $paquet" >&2; exit 1; }
for f in $FICHIERS; do
   [ -s "$T/contenu/$f" ] || { echo "  le paquet de Valve ne contient pas $f" >&2; exit 1; }
done
# En place par renommage : jamais de DLL a moitie ecrite, ni de copie par-dessus
# un fichier qu'un jeu aurait charge.
for f in $FICHIERS; do
   cp "$T/contenu/$f" "$DEST/$f.neuf" && mv -f "$DEST/$f.neuf" "$DEST/$f" || exit 1
done
echo "  DLL du client Steam installees"
