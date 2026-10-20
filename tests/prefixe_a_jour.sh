#!/bin/sh
# Met le prefixe Wine a jour de son runtime (wineboot -u, puis copie des DLL de
# Wine restees anciennes) quand les DLL du runtime ont change depuis la derniere
# mise a jour : ajoutees, retirees, ou reconstruites (taille ou date).
#
#   prefixe_a_jour.sh            : met a jour si les DLL du runtime ont change
#   prefixe_a_jour.sh --marquer  : note seulement l'empreinte (prefixe tout juste cree)
#
# Wine ne refait de lui-meme « wineboot -u » (inscriptions COM, fichiers de
# system32) que si la date de share/wine/wine.inf change. Une reconstruction
# qui ajoute une DLL sans changer wine.inf laisse donc le prefixe sans ses
# inscriptions : le 2026-10-16, winegstreamer.dll etait dans le runtime mais
# son gestionnaire de flux {317df618-...} n'etait pas au registre, Media
# Foundation refusait tout .mp4 (0xc00d36c4) et Sherlock Holmes Chapter One
# attendait sans fin, sur l'ecran de chargement de la nouvelle partie, une
# video qui ne s'ouvrait pas. On garde dans le prefixe une empreinte des DLL
# du runtime (nom, taille, date) et on refait la mise a jour quand elle change.
# Les DLL que le lanceur pose et retire selon le jeu (winemetal de DXMT) n'y
# entrent pas.
#
# wineboot -u ne remplace pas ntdll.dll ni kernelbase.dll dans system32 et
# syswow64 : apres une mise a jour du runtime (v1.5.17, 0195/0199 dans
# ntdll.dll), le prefixe gardait leurs copies de la version d'avant. Wine charge
# bien les siennes, mais un jeu qui lit system32\ntdll.dll sur le disque pour
# calculer des adresses dans le ntdll charge tombe a cote : le chargeur protege
# de Diablo II Resurrected mourait sur une RVA qui, dans la copie du prefixe,
# etait le debut de RtlUnwindEx et, dans le ntdll charge, le milieu d'une autre
# fonction (2026-10-20). Apres wineboot -u, on recopie donc toute DLL de Wine
# (signature « Wine builtin DLL ») du prefixe qui differe de celle du runtime ;
# une DLL native (vcrun, DXMT, vkd3d...) n'est jamais touchee.
# Corps entre accolades, ferme par `exit` : lu en entier avant d'etre execute.
{
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
W=$R/wine/wine11-arm64
P=${WINEPREFIX:-$R/wine/pfx-arm64ec}
# Prefixe absent : c'est configurer_cidre.sh (`cidre setup`) qui le cree.
[ -d "$P/drive_c/windows/system32" ] || exit 0
TEMOIN=$P/.cidre-dll-runtime
empreinte=$(for d in aarch64-windows i386-windows; do
               [ -d "$W/lib/wine/$d" ] && (cd "$W/lib/wine/$d" && stat -f "$d/%N %z %m" *)
            done | grep -E '\.(dll|drv|sys|exe|cpl|ocx|acm|ax|ds|tlb) ' | grep -v '/winemetal\.dll ' | shasum | cut -c1-40)
[ "${1:-}" = --marquer ] && { echo "$empreinte" >"$TEMOIN"; exit 0; }
[ "$(cat "$TEMOIN" 2>/dev/null)" = "$empreinte" ] && exit 0
echo "Cidre : mise a jour du prefixe Wine pour ce runtime (une fois, quelques secondes)" >&2
export WINEPREFIX=$P
WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" DYLD_LIBRARY_PATH="$R/wine/vklib-arm64:$R/prefix/lib" \
   "$W/bin/wineboot" -u >/dev/null 2>&1 || true
"$W/bin/wineserver" -w 2>/dev/null || true
builtin_wine() { [ "$(dd if="$1" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ]; }
n=0
for paire in aarch64-windows:system32 i386-windows:syswow64; do
   src=$W/lib/wine/${paire%%:*}; dst=$P/drive_c/windows/${paire#*:}
   [ -d "$src" ] && [ -d "$dst" ] || continue
   for f in "$src"/*.dll; do
      b=${f##*/}; [ "$b" = winemetal.dll ] && continue
      [ -f "$dst/$b" ] || continue
      cmp -s "$f" "$dst/$b" && continue
      builtin_wine "$dst/$b" && builtin_wine "$f" || continue
      cp "$f" "$dst/$b.cidre-neuf" && mv "$dst/$b.cidre-neuf" "$dst/$b" && n=$((n + 1))
   done
done
[ $n -gt 0 ] && echo "Cidre : $n DLL de Wine du prefixe remises a la version du runtime" >&2
echo "$empreinte" >"$TEMOIN"
exit 0
}
