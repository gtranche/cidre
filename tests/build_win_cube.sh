#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
MINGW=${MINGW:-/usr/local/opt/mingw-w64/bin}
OUT=${1:-$R/wine/bin/win_cube.exe}
mkdir -p "$(dirname "$OUT")"
"$MINGW/x86_64-w64-mingw32-gcc" -O2 -o "$OUT" \
    "$DIR/win_cube.c" -ld3d12 -ldxgi -ld3dcompiler -ldxguid -luuid -lole32 -luser32 -lgdi32 -lm
echo "$OUT"
