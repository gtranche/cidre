#!/bin/sh
# Sondes Metal pures, sans Vulkan : alignement des textures de tas.
set -e
DIR=$(cd "$(dirname "$0")" && pwd); R=$(cd "$DIR/.." && pwd)
for nom in metal_heap_texture_align metal_heap_placement_offset; do
   xcrun clang -arch arm64 -fobjc-arc -O1 -o "$R/build/$nom" "$DIR/$nom.m" \
      -framework Foundation -framework Metal
   echo "$R/build/$nom"
done
