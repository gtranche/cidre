#!/bin/sh
# Met le prefixe Wine a jour de son runtime (wineboot -u) quand le runtime a
# gagne ou perdu des DLL depuis la derniere mise a jour.
#
#   prefixe_a_jour.sh            : met a jour si la liste a change
#   prefixe_a_jour.sh --marquer  : note seulement la liste (prefixe tout juste cree)
#
# Wine ne refait de lui-meme « wineboot -u » (inscriptions COM, fichiers de
# system32) que si la date de share/wine/wine.inf change. Une reconstruction
# qui ajoute une DLL sans changer wine.inf laisse donc le prefixe sans ses
# inscriptions : le 2026-10-16, winegstreamer.dll etait dans le runtime mais
# son gestionnaire de flux {317df618-...} n'etait pas au registre, Media
# Foundation refusait tout .mp4 (0xc00d36c4) et Sherlock Holmes Chapter One
# attendait sans fin, sur l'ecran de chargement de la nouvelle partie, une
# video qui ne s'ouvrait pas. On garde dans le prefixe la liste des DLL du
# runtime et on refait la mise a jour quand elle change. Les DLL que le
# lanceur pose et retire selon le jeu (winemetal de DXMT) n'y entrent pas.
# Corps entre accolades, ferme par `exit` : lu en entier avant d'etre execute.
{
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
W=$R/wine/wine11-arm64
P=${WINEPREFIX:-$R/wine/pfx-arm64ec}
# Prefixe absent : c'est configurer_cidre.sh (`cidre setup`) qui le cree.
[ -d "$P/drive_c/windows/system32" ] || exit 0
TEMOIN=$P/.cidre-dll-runtime
liste=$(for d in aarch64-windows i386-windows; do
           [ -d "$W/lib/wine/$d" ] && ls "$W/lib/wine/$d" | sed "s#^#$d/#"
        done | grep -E '\.(dll|drv|sys|exe|cpl|ocx|acm|ax|ds|tlb)$' | grep -v '/winemetal\.dll$' | shasum | cut -c1-40)
[ "${1:-}" = --marquer ] && { echo "$liste" >"$TEMOIN"; exit 0; }
[ "$(cat "$TEMOIN" 2>/dev/null)" = "$liste" ] && exit 0
echo "Cidre : mise a jour du prefixe Wine pour ce runtime (une fois, quelques secondes)" >&2
export WINEPREFIX=$P
WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" DYLD_LIBRARY_PATH="$R/wine/vklib-arm64:$R/prefix/lib" \
   "$W/bin/wineboot" -u >/dev/null 2>&1 || true
"$W/bin/wineserver" -w 2>/dev/null || true
echo "$liste" >"$TEMOIN"
exit 0
}
