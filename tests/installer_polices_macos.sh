#!/bin/sh
# Presente les polices de macOS a Wine.
#
# Sans fontconfig -- absent de cette machine -- Wine ne scanne que son propre
# dossier de polices. macOS fournit Arial, Times New Roman, Courier New et 170
# autres dans /System/Library/Fonts/Supplemental ; on les y lie. Le cache de
# polices du prefixe est efface pour forcer un nouveau balayage.
set -e
PFX=${WINEPREFIX:?WINEPREFIX requis}
DST="$PFX/drive_c/windows/Fonts"
mkdir -p "$DST"
n=0
for d in /System/Library/Fonts /System/Library/Fonts/Supplemental; do
   [ -d "$d" ] || continue
   for f in "$d"/*.ttf "$d"/*.ttc "$d"/*.otf; do
      [ -f "$f" ] || continue
      ln -sf "$f" "$DST/$(basename "$f")"
      n=$((n + 1))
   done
done
echo "$n polices liees dans $DST"

# Le cache vit dans user.reg ; Wine le reconstruit quand il disparait.
python3 - "$PFX/user.reg" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = len(re.findall(r'^\[Software\\\\Wine\\\\Fonts.*$', s, re.M))
s = re.sub(r'^\[Software\\\\Wine\\\\Fonts[^\]]*\].*?(?=^\[|\Z)', '', s, flags=re.M | re.S)
open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)
print(f"{n} section(s) de cache de polices retiree(s)")
PY
