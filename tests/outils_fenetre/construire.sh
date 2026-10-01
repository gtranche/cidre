#!/bin/sh
# Bati touche.exe (invite x86-64, SendInput sans CRT) et fenetres (hote, CGWindowList).
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); T=$(ls -d $R/toolchain/llvm-mingw-*/bin | head -1)
cd "$(dirname "$0")"
$T/llvm-dlltool -m i386:x86-64 -d kernel32.def -l kernel32.lib
$T/llvm-dlltool -m i386:x86-64 -d user32.def -l user32.lib
$T/clang --target=x86_64-pc-windows-msvc -O1 -fno-stack-protector -nostdlib -c touche.c -o touche.obj
$T/lld-link /entry:mainCRTStartup /subsystem:console /nodefaultlib /out:touche.exe touche.obj kernel32.lib user32.lib
swiftc -O -o fenetres fenetres.swift
ls -la touche.exe fenetres
