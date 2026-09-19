#!/bin/sh
# Compile tests/win_swapchain.c en PE Windows x86_64.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$DIR/.." && pwd)
MINGW=${MINGW:-/usr/local/opt/mingw-w64/bin}
mkdir -p "$R/wine/bin"
"$MINGW/x86_64-w64-mingw32-gcc" -O1 -Wall -o "$R/wine/bin/win_swapchain.exe" \
    "$DIR/win_swapchain.c" -ld3d12 -ldxgi -ldxguid -luuid -lole32 -luser32 -lgdi32
echo "$R/wine/bin/win_swapchain.exe"
