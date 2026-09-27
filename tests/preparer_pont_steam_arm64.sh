#!/bin/sh
# Meme chose que preparer_pont_steam.sh, pour la pile arm64.
#
# Le steam_api64.dll du jeu lit le registre, charge ce qu'il y trouve et y
# cherche CreateInterface. On lui presente le pont sous son propre nom : Wine
# resout l'unixlib d'un module PE par le nom du module, donc le renommer en
# steamclient64.dll ferait echouer DllMain avec 1114.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:?WINEPREFIX requis}
WINE=${WINE:-$R/wine/wine11-arm64/bin/wine}
B=${B:-$R/wine/wine11-arm64/lib/wine}
DOS='C:\Program Files (x86)\Steam'

mkdir -p "$PFX/drive_c/Program Files (x86)/Steam"
cp -f "$B/aarch64-windows/lsteamclient.dll" "$PFX/drive_c/windows/system32/lsteamclient.dll"
cp -f "$R/build/faux_steam.exe" "$PFX/drive_c/faux_steam.exe"

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
WINEPREFIX="$PFX" WINEDEBUG=-all "$WINE" reg query "$K" 2>/dev/null | grep -E "SteamClientDll|Universe|pid" || true
