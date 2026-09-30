#!/bin/sh
# Reproducteur d'exception C++ x64 (ABI MSVC, sans CRT) pour la pile arm64ec.
# Construit avec clang --target=x86_64-pc-windows-msvc + lld-link ; imports fabriques
# par llvm-dlltool. Lancer : WINEPREFIX=... tests/etape2_pile_arm64ec.sh 'c:\r_deep.exe'
# avec WINEDEBUG=+seh, et lire les lignes "REPRO:". Etat 2026-09-30 : repro, r_deep,
# r_alloca, r_mid PASSENT tous (&e valide, e.marque lu) -- le chemin Wine->funclet x64
# via FEX est sain dans ces cas ; le gel de Vermintide 2 (NOTES §296) tient a quelque
# chose de plus specifique (a cerner : std::exception de msvcp140 arm64ec, FH3 reel).
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); T=$(ls -d $R/toolchain/llvm-mingw-*/bin | head -1)
cd "$(dirname "$0")"
$T/llvm-dlltool -m i386:x86-64 -d vcruntime140.def -l vcruntime140.lib
$T/llvm-dlltool -m i386:x86-64 -d kernel32.def -l kernel32.lib
for v in repro r_deep r_alloca r_mid; do
  $T/clang++ --target=x86_64-pc-windows-msvc -O1 -fexceptions -fcxx-exceptions -fno-rtti -fno-stack-protector -nostdlib -c $v.cpp -o $v.obj
  $T/lld-link /entry:mainCRTStartup /subsystem:console /nodefaultlib /out:$v.exe $v.obj vcruntime140.lib kernel32.lib
done
ls -la *.exe
