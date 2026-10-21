#!/bin/sh
# Le runtime Visual C++, declare au registre d'un prefixe ($WINEPREFIX) dans ses
# deux vues. Wine fournit ces bibliotheques (msvcp140, vcruntime140...) et les
# declare lui-meme, mais la vue 32 bits -- celle que lisent les installeurs et
# les lanceurs Unreal -- est ecrite par un programme 32 bits : la ou il n'a pas
# pu tourner, le lanceur du jeu croit le runtime absent, propose de l'installer,
# et son installeur echoue. On l'ecrit donc depuis le cote 64 bits. La version
# est celle du redistribuable courant de Microsoft : seuls des controles de
# version la lisent. Appele par configurer_cidre.sh (prefixe Steam) et
# battlenet.sh creer (prefixe Battle.net). Rend le code de `wine reg import`.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
VC="$PFX/drive_c/cidre-vcruntime.reg"
{
   echo 'Windows Registry Editor Version 5.00'
   for vue in 'SOFTWARE\Microsoft' 'SOFTWARE\Wow6432Node\Microsoft'; do
      for arch in x64 x86 arm64; do
         printf '\n[HKEY_LOCAL_MACHINE\\%s\\VisualStudio\\14.0\\VC\\Runtimes\\%s]\n' "$vue" "$arch"
         echo '"Installed"=dword:00000001'
         echo '"Major"=dword:0000000e'
         echo '"Minor"=dword:0000002c'
         echo '"Bld"=dword:0000898b'
         echo '"Rbld"=dword:00000000'
         echo '"Version"="v14.44.35211.00"'
      done
   done
} >"$VC"
WINEPREFIX=$PFX "${CIDRE_VC_WINE:-$R/wine/wine11-arm64/bin/wine}" reg import 'C:\cidre-vcruntime.reg' >/dev/null 2>&1 && rc=0 || rc=$?
rm -f "$VC"
[ $rc -ne 0 ] || echo "  runtime Visual C++ declare au registre (14.44, vues 64 et 32 bits)"
exit $rc
