#!/bin/sh
# Diagnostic d'une installation de Cidre : ce qui est la, ce qui tourne, et
# surtout si Wine demarre -- avec ses messages d'erreur, que le lanceur des jeux
# fait taire. Sort un texte a copier, pour depanner une machine a distance.
#
#   diagnostic_cidre.sh        (c'est `cidre doctor`)
#
# N'arrete rien de ce qui tournait avant lui. Dure une minute au plus.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
WINE="$R/wine/wine11-arm64/bin/wine"
WS="$R/wine/wine11-arm64/bin/wineserver"
C="$WINEPREFIX/drive_c"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

titre() { printf '\n== %s ==\n' "$1"; }
oui()   { if "$@" >/dev/null 2>&1; then echo oui; else echo NON; fi; }
# presence et taille d'un fichier du runtime
piece() { if [ -e "$R/$1" ]; then printf '  %-52s %s octets\n' "$1" "$(stat -f %z "$R/$1" 2>/dev/null)"; else printf '  %-52s ABSENT\n' "$1"; fi; }
# Lance une commande avec un delai ; ecrit sa sortie dans $T/sortie.
# Rend 0 si elle a fini, 1 si on a du l'arreter.
avec_delai() { # <secondes> commande...
   d=$1; shift
   "$@" >"$T/sortie" 2>&1 &
   pid=$!; i=0
   while [ $i -lt "$d" ] && kill -0 $pid 2>/dev/null; do sleep 1; i=$((i + 1)); done
   if kill -0 $pid 2>/dev/null; then
      kill -TERM $pid 2>/dev/null; sleep 1; kill -KILL $pid 2>/dev/null
      wait $pid 2>/dev/null
      echo "  -> PAS DE REPONSE apres $d s (arretee)"
      return 1
   fi
   wait $pid; echo "  -> terminee en $i s, code $?"
   return 0
}
fin_de_sortie() { tail -n "${1:-25}" "$T/sortie" 2>/dev/null | cut -c1-300 | sed 's/^/  | /'; }

titre "Machine"
echo "  macOS       : $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
echo "  modele      : $(sysctl -n hw.model 2>/dev/null) -- $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  memoire     : $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) Go"
echo "  processeur  : $(uname -m)"
echo "  Rosetta     : $(oui arch -x86_64 /usr/bin/true)"
echo "  taille page : $(sysctl -n hw.pagesize 2>/dev/null)"

titre "Runtime"
echo "  version     : $(cat "$R/VERSION" 2>/dev/null || echo dev)"
echo "  racine      : $R"
for f in wine/wine11-arm64/bin/wine wine/wine11-arm64/bin/wineserver \
         wine/wine11-arm64/lib/wine/aarch64-unix/ntdll.so \
         wine/wine11-arm64/lib/wine/aarch64-unix/winemac.so \
         wine/wine11-arm64/lib/wine/aarch64-windows/xtajit64.dll \
         prefix/lib/libvulkan.1.dylib prefix/lib/libvulkan_kosmickrisp.dylib \
         libs/libSPIRV-Tools.dylib libs/libfreetype.6.dylib libs/libzstd.1.dylib \
         dxvk/async/d3d11.dll dxvk/async/dxgi.dll \
         build/faux_steam.exe build/cidre-outil tools/steamcmd/steamcmd; do piece "$f"; done
echo "  wine        : $(file -b "$WINE" 2>/dev/null | cut -c1-60)"
echo "  signature   : $(codesign --verify "$WINE" 2>&1 | head -1 | cut -c1-120 || true)$(codesign --verify "$WINE" >/dev/null 2>&1 && echo valide)"
echo "  quarantaine : $(xattr -p com.apple.quarantine "$WINE" 2>/dev/null || echo aucune)"
ICD=$(ls "$R/prefix/share/vulkan/icd.d/"*.json 2>/dev/null | head -1)
if [ -n "$ICD" ]; then
   lib=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$ICD" | head -1)
   echo "  pilote Vulkan declare : $lib"
   case $lib in /*) echo "    existe : $(oui test -f "$lib")" ;; *) echo "    (chemin relatif, ou jeton non remplace : cidre setup n'est pas passe ?)" ;; esac
else
   echo "  pilote Vulkan : aucun fichier .json dans prefix/share/vulkan/icd.d"
fi

titre "Prefixe Wine"
echo "  dossier     : $WINEPREFIX"
echo "  cree        : $(oui test -d "$C/windows/system32")"
echo "  system32    : $(ls "$C/windows/system32" 2>/dev/null | wc -l | tr -d ' ') fichiers"
for f in faux_steam.exe windows/system32/lsteamclient.dll windows/system32/xtajit64.dll \
         windows/system32/d3d11.dll windows/system32/dxgi.dll; do
   if [ -f "$C/$f" ]; then printf '  %-40s %s octets\n' "$f" "$(stat -f %z "$C/$f")"; else printf '  %-40s ABSENT\n' "$f"; fi
done
echo "  registre    : $(oui test -s "$WINEPREFIX/system.reg")"

titre "Processus"
ps -axo pid=,etime=,command= | grep -E "lancer_depuis_steam|etape2_pile|wineserver|[A-Za-z]:\\\\" | grep -v grep \
   | awk '{printf "  %s  depuis %s  ", $1, $2; for (i = 3; i <= NF && i <= 5; i++) printf "%s ", $i; print ""}' | cut -c1-200 | head -30 >"$T/processus"
if [ -s "$T/processus" ]; then cat "$T/processus"; else echo "  aucun lanceur, aucun processus Wine"; fi
# Wine tournait-il deja pour CE runtime ? (on ne lui ajoute alors pas de client Steam)
DEJA=$(ps -axo pid=,command= | grep -F "$R/wine/" | grep wineserver | grep -v grep | head -1)

titre "Wine repond-il ?"
echo "  wine --version"
avec_delai 15 "$WINE" --version; fin_de_sortie 5

titre "Une commande Windows (Wine seul)"
echo "  cmd /c ver, avec les messages d'erreur de Wine"
WINEDEBUG=err+all,fixme-all CIDRE_OVERLAY_DYLIB= avec_delai 45 sh "$R/tests/etape2_pile_arm64ec.sh" cmd /c ver; fin_de_sortie 30

titre "Un programme x86-64 (Wine + FEX) : le client Steam de service"
if [ -n "$DEJA" ]; then
   echo "  saute : Wine tournait deja (un jeu ?). Arrete-le (« Tout arreter ») et relance le diagnostic."
elif [ ! -f "$C/faux_steam.exe" ]; then
   echo "  saute : c:\\faux_steam.exe n'est pas dans le prefixe (l'etape « Pont Steam » de cidre setup a echoue)."
else
   # Il ne se termine jamais de lui-meme : on attend sa ligne « inscrit ».
   WINEDEBUG=err+all,fixme-all CIDRE_OVERLAY_DYLIB= sh "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >"$T/sortie" 2>&1 &
   i=0; while [ $i -lt 30 ] && ! grep -q "inscrit" "$T/sortie" 2>/dev/null; do sleep 1; i=$((i + 1)); done
   if grep -q "inscrit" "$T/sortie" 2>/dev/null; then echo "  -> demarre en $i s : l'emulation x86-64 fonctionne"
   else echo "  -> PAS DE LIGNE « inscrit » apres $i s : le programme x86-64 ne demarre pas"; fi
   fin_de_sortie 30
fi

titre "Vulkan (pilote KosmicKrisp sur Metal)"
if [ -x "$R/prefix/bin/vulkaninfo" ] && [ -n "$ICD" ]; then
   VK_DRIVER_FILES="$ICD" DYLD_LIBRARY_PATH="$R/prefix/lib" avec_delai 20 "$R/prefix/bin/vulkaninfo" --summary
   grep -E "deviceName|driverName|driverInfo|apiVersion|ERROR|error|rror:" "$T/sortie" 2>/dev/null | head -8 | cut -c1-200 | sed 's/^/  | /'
   [ -s "$T/sortie" ] || echo "  | (aucune sortie)"
else
   echo "  saute : vulkaninfo n'est pas livre dans ce runtime"
fi

# On n'arrete que ce qu'on a lance nous-memes.
[ -z "$DEJA" ] && [ -x "$WS" ] && "$WS" -k 2>/dev/null
titre "Fin du diagnostic"
