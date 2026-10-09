#!/bin/sh
# Installe SteamCMD (l'outil de Valve qui telecharge les jeux) dans un dossier.
#
#   installer_steamcmd.sh <dossier>
#
# On ne passe PAS par l'archive « steamcmd_osx.tar.gz » de Valve : elle date de
# 2020 et ne contient qu'un binaire Intel, qui se met a jour au premier
# lancement. Sur un Mac Apple Silicon neuf il n'y a pas Rosetta : ce premier
# lancement echoue (« Bad CPU type in executable ») et SteamCMD n'existe jamais.
#
# On fait donc nous-memes ce que ferait cette mise a jour : lire le manifeste
# que publie Valve, telecharger ses paquets, verifier leur empreinte, les
# decompresser. Le binaire obtenu est universel (Intel + arm64).
set -u
DEST=${1:?usage: installer_steamcmd.sh <dossier>}
CDN=${CIDRE_STEAMCMD_CDN:-https://steamcdn-a.akamaihd.net/client}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

curl -fsSL --retry 3 -m 60 -o "$T/manifeste" "$CDN/steam_cmd_osx" || {
   echo "  manifeste de SteamCMD injoignable ($CDN)" >&2; exit 1; }

# Le manifeste : des blocs « "file" "nom.zip.<hash>" ... "sha2" "<sha256>" ».
awk -F'"' '$2 == "file" { f = $4 } $2 == "sha2" && f != "" { print f, $4; f = "" }' "$T/manifeste" >"$T/paquets"
[ -s "$T/paquets" ] || { echo "  manifeste de SteamCMD illisible" >&2; exit 1; }

mkdir -p "$T/contenu"
while read -r fichier sha; do
   curl -fsSL --retry 3 -m 600 -o "$T/$fichier" "$CDN/$fichier" || {
      echo "  telechargement impossible : $fichier" >&2; exit 1; }
   obtenu=$(openssl dgst -sha256 -r "$T/$fichier" | cut -d' ' -f1)
   [ "$obtenu" = "$sha" ] || { echo "  empreinte inattendue pour $fichier : on ne l'installe pas" >&2; exit 1; }
   unzip -oq "$T/$fichier" -d "$T/contenu" || { echo "  archive illisible : $fichier" >&2; exit 1; }
done <"$T/paquets"

# Les archives de Valve nomment leurs fichiers a la facon de Windows
# (« Frameworks\Breakpad.framework\... ») : unzip en fait des fichiers au nom
# plein de contre-obliques, a la racine. On les range dans leurs dossiers.
( cd "$T/contenu" && find . -maxdepth 1 -name '*\\*' | while IFS= read -r f; do
     cible=$(printf '%s' "$f" | tr '\\' '/')
     if [ -d "$f" ]; then mkdir -p "$cible" && rmdir "$f" 2>/dev/null
     else mkdir -p "$(dirname "$cible")" && mv "$f" "$cible"; fi
  done )

[ -f "$T/contenu/steamcmd" ] && [ -f "$T/contenu/steamcmd.sh" ] || {
   echo "  les paquets de Valve ne contiennent pas SteamCMD" >&2; exit 1; }
# Le binaire doit pouvoir tourner ici : sur Apple Silicon, il lui faut sa
# tranche arm64. (`file`, pas `lipo` : lipo fait partie des outils de
# developpement, absents d'un Mac neuf.)
ARCHS=$(file "$T/contenu/steamcmd" 2>/dev/null)
case "$(uname -m):$ARCHS" in
   arm64:*arm64*|x86_64:*x86_64*) ;;
   *) echo "  le SteamCMD de Valve n'a pas de version pour ce processeur" >&2; exit 1 ;;
esac

# En place d'un coup : pas de SteamCMD a moitie pose si on est interrompu.
mkdir -p "$DEST"
cp -R "$T/contenu/." "$DEST/" || exit 1
chmod +x "$DEST/steamcmd" "$DEST/steamcmd.sh"
xattr -cr "$DEST" 2>/dev/null || true
echo "  SteamCMD installe"
