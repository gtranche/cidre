#!/bin/sh
# Empaquette le RUNTIME (binaires deja construits) en un tarball a livrer en
# release GitHub. Ne contient PAS les sources, le build, la toolchain, ni le
# prefixe (regenere a l'install). Verger (ou installer_cidre.sh) le decompresse
# puis lance `cidre setup`, qui relocalise l'ICD et regenere le prefixe.
#   CIDRE_VERSION=1.1.0 sh tests/empaqueter_runtime.sh [sortie.tar.zst]
# Sort deux archives du meme contenu : .tar.zst (installer_cidre.sh) et .tar.xz
# (Verger : macOS sait decompresser xz sans rien installer, pas zstd).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$R/cidre-runtime.tar.zst}
# La version que `cidre status` annonce et que Verger compare a la derniere
# release : celle du tag qu'on s'apprete a publier, sans le « v ».
: "${CIDRE_VERSION:?donne la version a publier, ex. CIDRE_VERSION=1.1.0}"
STAGE=$(mktemp -d)/cidre
mkdir -p "$STAGE"

echo "== Wine 11 arm64 (elague : sans include/doc/man) =="
mkdir -p "$STAGE/wine/wine11-arm64"
( cd "$R/wine/wine11-arm64" && tar cf - \
    --exclude='include' --exclude='share/man' --exclude='share/doc' \
    --exclude='*.avant-*' \
    bin lib share ) | ( cd "$STAGE/wine/wine11-arm64" && tar xf - )

echo "== KosmicKrisp + loader Vulkan (prefix/) =="
mkdir -p "$STAGE/prefix"
( cd "$R/prefix" && tar cf - lib share bin 2>/dev/null ) | ( cd "$STAGE/prefix" && tar xf - )
# L'ICD json : chemin a reecrire a l'install -> on le neutralise avec un jeton.
for j in "$STAGE/prefix/share/vulkan/icd.d/"*.json; do
   [ -f "$j" ] && sed -i '' "s#$R#@@CIDRE@@#g" "$j"
done

echo "== DXVK arm64ec (stock + async gplasync) =="
mkdir -p "$STAGE/dxvk/stock" "$STAGE/dxvk/async"
for d in d3d11 dxgi d3d10core d3d9 d3d8; do
   cp "$R/build/dxvk-winarm64ec/src/$d/$d.dll" "$STAGE/dxvk/stock/" 2>/dev/null || true
   cp "$R/build/dxvk-async-winarm64ec/src/$d/$d.dll" "$STAGE/dxvk/async/" 2>/dev/null || true
done

# vkd3d-proton arm64ec (vrai D3D12, option dx12). lancer_depuis_steam.sh installe
# ces DLL en system32 et force d3d12=n quand l'option dx12 est vraie ; sinon le
# d3d12 builtin de Wine (repli D3D11) est utilise. Cherche $R/vkd3d/*.dll au lancement.
mkdir -p "$STAGE/vkd3d"
for d in d3d12core d3d12; do
   cp "$R/build/vkd3d-winarm64ec/libs/$d/$d.dll" "$STAGE/vkd3d/" 2>/dev/null || true
done

# Outils de generation de code de Mesa : ils ne servent qu'a construire, et
# mesa_clc tirerait tout LLVM dans le runtime.
rm -f "$STAGE/prefix/bin/mesa_clc" "$STAGE/prefix/bin/kk_clc" "$STAGE/prefix/bin/vtn_bindgen2"

echo "== scripts de lancement + integration Steam =="
# Les scripts et les donnees partent tels qu'ils sont COMMITES, pas tels qu'ils
# sont sur le disque : une release ne doit pas embarquer un travail en cours.
# Hors d'un depot git (ou pour un fichier pas encore suivi), on prend le disque.
livrer() { # <chemin relatif au depot>
   mkdir -p "$(dirname "$STAGE/$1")"
   if git -C "$R" cat-file -e "HEAD:$1" 2>/dev/null; then
      git -C "$R" show "HEAD:$1" >"$STAGE/$1"
      git -C "$R" diff --quiet HEAD -- "$1" 2>/dev/null || echo "  $1 : modifie sur le disque, on livre la version commitee"
   elif [ -f "$R/$1" ]; then
      cp "$R/$1" "$STAGE/$1"
      echo "  $1 : pas dans git, on livre le disque"
   else
      echo "  $1 : ABSENT" >&2; return 1
   fi
   case $1 in *.sh|*.py|cidre) chmod +x "$STAGE/$1" ;; esac
}
for f in etape2_pile_arm64ec.sh lancer_depuis_steam.sh brancher_jeux_steam.sh \
         installer_agent_steam.sh preparer_pont_steam_arm64.sh sync_saves_steam.sh \
         installer_fex.sh profil_cidre.sh cidre_install.sh compte_steam.sh \
         majs_steam.awk brancher_jeux_steam.awk configurer_cidre.sh langue_jeu.sh \
         installer_steamcmd.sh installer_client_steam_windows.sh diagnostic_cidre.sh; do
   livrer "tests/$f"
done
# La CLI `cidre` : le contrat que pilote Verger (list/info --json, play, dl, sync).
livrer cidre
cp -R "$R/tests/outils_fenetre" "$STAGE/tests/" 2>/dev/null || true
mkdir -p "$STAGE/outil-steam" "$STAGE/build"
# jeux.conf est lu par lancer_depuis_steam.sh en $R/outil-steam/jeux.conf :
# le livrer a CE chemin, pas a la racine (sinon la table de lanceurs est muette).
for f in jeux.conf saves.conf profils.toml langues.conf; do livrer "outil-steam/$f"; done
# Le faux client Steam (occupe ActiveProcess\\pid pour que SteamAPI_Init ne
# patiente pas apres un client Windows absent). preparer_pont_steam_arm64.sh le
# lit en $R/build/faux_steam.exe et le depose dans le prefixe.
cp "$R/build/faux_steam.exe" "$STAGE/build/" 2>/dev/null || true

echo "== cidre-outil (terminal de SteamCMD, caches binaires de Steam) =="
# Construit ici, depuis la source commitee : la machine qui recoit le runtime
# n'a ni compilateur ni Python (sans les outils de developpement d'Apple,
# /usr/bin/python3 n'est qu'un relais qui propose de les installer). La source
# n'est pas livree : en la voyant, `cidre` voudrait reconstruire l'outil.
livrer tests/cidre_outil.c
sh "$R/tests/construire_cidre_outil.sh" "$STAGE/tests/cidre_outil.c" "$STAGE/build/cidre-outil"
rm "$STAGE/tests/cidre_outil.c"
# La sonde du basculement ecriture/execution, pour `cidre doctor` : meme raison,
# construite ici et livree sans sa source.
livrer tests/sonde_wx.c
cc -arch arm64 -mmacosx-version-min=13.0 -O1 -Wall -Wextra -o "$STAGE/build/sonde-wx" "$STAGE/tests/sonde_wx.c"
rm "$STAGE/tests/sonde_wx.c"
# Garde-fou : rien de ce qu'on livre ne doit appeler python3.
if grep -rnE '(^|[^[:alnum:]_/.-])python3?([^[:alnum:]_.-]|$)' "$STAGE/cidre" "$STAGE/tests" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; then
   echo "un script livre appelle python : un Mac sans outils de developpement ne l'a pas" >&2; exit 1
fi

echo "$CIDRE_VERSION" >"$STAGE/VERSION"

echo "== bibliotheques Homebrew embarquees (libs/) =="
# Le pilote Vulkan lie zstd et SPIRV-Tools, Wine charge FreeType par dlopen :
# on les livre, pour qu'une machine sans Homebrew fasse tourner les jeux.
python3 "$R/tests/embarquer_dependances.py" "$STAGE" /opt/homebrew/lib/libfreetype.6.dylib

echo "== compression (zstd) =="
( cd "$(dirname "$STAGE")" && tar cf - cidre ) | zstd -15 -T${CIDRE_FILS:-0} -o "$OUT" -f
echo "== compression (xz) =="
OUT_XZ="${OUT%.zst}"; OUT_XZ="${OUT_XZ%.xz}.xz"
( cd "$(dirname "$STAGE")" && /usr/bin/tar -c --xz --options "xz:compression-level=6,xz:threads=${CIDRE_FILS:-0}" -f "$OUT_XZ" cidre )
rm -rf "$(dirname "$STAGE")"
echo
echo "RUNTIME empaquete (version $CIDRE_VERSION) :"
ls -lh "$OUT" "$OUT_XZ" | awk '{print "  "$5"  "$9}'
