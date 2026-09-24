#!/bin/sh
# Installe le pont lsteamclient la ou le steam_api d'un jeu va le chercher.
#
# Un steam_api64.dll ne connait pas « lsteamclient » : il lit le registre pour
# trouver steamclient64.dll, puis fait un LoadLibrary dessus et un
# GetProcAddress sur CreateInterface. On lui presente donc notre pont sous ce
# nom, dans un dossier Steam factice du prefixe. Le client Steam Windows n'a
# pas a exister : c'est le client macOS natif qui repond derriere.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-wow64}
WINE=$R/wine/wine10-wow64/bin/wine
B=$R/build/wine-wow64/dlls/lsteamclient
DOS='C:\Program Files (x86)\Steam'
DIR="$PFX/drive_c/Program Files (x86)/Steam"

# Le pont reste sous son nom. Wine resout l'unixlib d'un module PE par le nom
# de ce module : le presenter sous « steamclient64.dll » fait echouer DllMain
# avec 1114, faute de lsteamclient.so correspondant. Le registre peut designer
# n'importe quel chemin, alors on y met le module tel quel -- c'est aussi ce
# que fait Proton.
mkdir -p "$DIR"
cp -f "$B/x86_64-windows/lsteamclient.dll" "$PFX/drive_c/windows/system32/lsteamclient.dll"
cp -f "$B/i386-windows/lsteamclient.dll"   "$PFX/drive_c/windows/syswow64/lsteamclient.dll" 2>/dev/null || true
echo "pont installe sous son nom dans system32"

reg() { WINEPREFIX="$PFX" WINEDEBUG=-all "$WINE" reg add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1; }

K='HKCU\Software\Valve\Steam'
reg "$K" SteamPath "REG_SZ" "$DOS"
reg "$K" SteamExe  "REG_SZ" "$DOS\\steam.exe"

K='HKCU\Software\Valve\Steam\ActiveProcess'
reg "$K" SteamClientDll   "REG_SZ"    'C:\windows\system32\lsteamclient.dll'
reg "$K" SteamClientDll64 "REG_SZ"    'C:\windows\system32\lsteamclient.dll'
reg "$K" SteamPath        "REG_SZ"    "$DOS"
reg "$K" Universe         "REG_SZ"    "Public"
reg "$K" pid              "REG_DWORD" "1"
echo "registre renseigne :"
WINEPREFIX="$PFX" WINEDEBUG=-all "$WINE" reg query "$K" 2>/dev/null | grep -E "SteamClientDll|Universe|pid" || true
