#!/bin/sh
R=/Users/gtranche/Dev/cidre
TAG="$1"
export WINEPREFIX=$R/wine/pfx
export WINEDEBUG=-all
export WINEDLLOVERRIDES="d3d12,d3d12core,dxgi,d3d11,d3d10core=n"
export MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod
export VK_ICD_FILENAMES=$R/prefix-x64/share/vulkan/icd.d/kosmickrisp_mesa_icd.x86_64.json
$R/build/wine/wine $R/wine/bin/d3d12.exe > $R/build/logs/d3d12-$TAG.log 2>&1
echo "D3D12=$(grep -c 'Test failed' $R/build/logs/d3d12-$TAG.log)  (adaptateur: $(grep -m1 -o 'Adapter: [^,]*' $R/build/logs/d3d12-$TAG.log))"
$R/build/wine/wine $R/build/wine/dlls/d3d11/tests/x86_64-windows/d3d11_test.exe > $R/build/logs/d3d11-$TAG.log 2>&1
echo "D3D11=$(grep -c 'Test failed' $R/build/logs/d3d11-$TAG.log)"
echo FINI
