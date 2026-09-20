#!/bin/sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
OUT=${1:-$R/build/probe_image_size}
cc -std=c11 -O1 -I"$R/prefix/include" "$DIR/probe_image_size.c" \
   -L"$R/prefix/lib" -lvulkan -o "$OUT"
echo "$OUT"
