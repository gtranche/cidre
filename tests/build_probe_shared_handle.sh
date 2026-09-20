#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
MINGW=${MINGW:-/usr/local/opt/mingw-w64/bin}
OUT=${1:-$R/build/probe_shared_handle.exe}
mkdir -p "$(dirname "$OUT")"
"$MINGW/x86_64-w64-mingw32-gcc" -O0 -g -o "$OUT" "$DIR/probe_shared_handle.c" \
    -ld3d11 -ldxgi -lntdll -ldxguid -luuid -lole32
echo "$OUT"
