#!/bin/sh
# Compile le repere etage sommets (Metal natif, arm64).
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
mkdir -p "$R/build"
clang -arch arm64 -fobjc-arc -O2 -framework Metal -framework Foundation \
   "$DIR/bench_vertex_fetch_metal.m" -o "$R/build/bench_vertex_fetch_metal"
echo "$R/build/bench_vertex_fetch_metal"
