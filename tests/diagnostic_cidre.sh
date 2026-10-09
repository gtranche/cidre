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
# Ce que le diagnostic a lance lui-meme est arrete a sa sortie, meme s'il est
# interrompu (fenetre de Verger fermee en cours de route).
LANCE=; DEJA=
nettoyer() {
   [ -n "$LANCE" ] && [ -z "$DEJA" ] && [ -x "$WS" ] && "$WS" -k 2>/dev/null
   rm -rf "$T"
}
trap nettoyer EXIT
trap 'exit 143' TERM INT HUP

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
# Comme avec_delai, sans rien dire : pour les outils d'observation. Sortie dans $T/outil.
limite() { # <secondes> commande...
   d=$1; shift
   "$@" >"$T/outil" 2>&1 &
   pid=$!; i=0
   while [ $i -lt "$d" ] && kill -0 $pid 2>/dev/null; do sleep 1; i=$((i + 1)); done
   if kill -0 $pid 2>/dev/null; then kill -KILL $pid 2>/dev/null; wait $pid 2>/dev/null; return 1; fi
   wait $pid
}

# Lance le client Steam de service (un programme x86-64, donc Wine + FEX) et
# attend la ligne qu'il ecrit une fois demarre. Rend 0 s'il l'a ecrite.
# $X64 = son pid : etape2 fait `exec wine`, c'est le processus Wine lui-meme.
# CIDRE_DIAG_TEMOIN change la ligne attendue : sert a essayer, sur une machine
# saine, ce que le diagnostic ecrit quand le programme ne demarre pas.
TEMOIN=${CIDRE_DIAG_TEMOIN:-inscrit}
essai_x64() { # <secondes> <WINEDEBUG> [VAR=valeur...]
   d=$1; trace=$2; shift 2
   env WINEDEBUG="$trace" CIDRE_OVERLAY_DYLIB= "$@" sh "$R/tests/etape2_pile_arm64ec.sh" 'c:\faux_steam.exe' >"$T/sortie" 2>&1 &
   X64=$!; i=0
   while [ $i -lt "$d" ] && kill -0 $X64 2>/dev/null && ! grep -q "$TEMOIN" "$T/sortie" 2>/dev/null; do sleep 1; i=$((i + 1)); done
   grep -q "$TEMOIN" "$T/sortie" 2>/dev/null
}
# Un processus bloque peut ne pas obeir au serveur : on le tue aussi nous-memes.
arreter_wine() {
   "$WS" -k 2>/dev/null; limite 10 "$WS" -w
   kill -KILL $X64 2>/dev/null; wait $X64 2>/dev/null
}

# Ce que fait le programme x86-64 qui n'a pas demarre : vivant ou mort, ou il
# attend, ce que contient son espace d'adressage.
autopsie_x64() {
   if kill -0 $X64 2>/dev/null; then
      a=$(ps -o time= -p $X64 2>/dev/null | tr -d ' '); sleep 3; b=$(ps -o time= -p $X64 2>/dev/null | tr -d ' ')
      echo "  processus   : vivant ; temps processeur $a -> $b en 3 s ; $(ps -M -p $X64 2>/dev/null | tail -n +2 | wc -l | tr -d ' ') fils"
      echo "  pile d'appels (sample, 2 s) :"
      if limite 40 sample $X64 2 -mayDie -file "$T/pile" && [ -s "$T/pile" ]; then
         awk '/^Call graph:/ { p = 1; next } /^Total number in stack/ { p = 0 } p' "$T/pile" | head -90 | cut -c1-190 | sed 's/^/  | /'
      else
         echo "  | sample n'a rien rendu : $(head -2 "$T/outil" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
      fi
      echo "  espace d'adressage (vmmap) :"
      if limite 40 vmmap $X64 && grep -q "^==== " "$T/outil"; then
         # une ligne de region : « TYPE  debut-fin  [tailles] droits ... »
         awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9a-f]+-[0-9a-f]+$/) { split($i, a, "-"); print length(a[1]), substr(a[1], 1, 1), a[1], $0; break } }' "$T/outil" | sort -k1,1n -k3,3 >"$T/regions"
         echo "  | $(wc -l <"$T/regions" | tr -d ' ') regions. La page KUSER de l'hote (17ffe0000) et celle de l'invite (47ffe0000) :"
         awk '$3 == "17ffe0000" || $3 == "47ffe0000" { $1 = $2 = $3 = ""; print "  |  " $0 }' "$T/regions" | cut -c1-170
         echo "  | La fenetre de l'invite, de 400000000 a 500000000 : $(awk '$1 == 9 && $2 == "4"' "$T/regions" | wc -l | tr -d ' ') regions ; les premieres :"
         awk '$1 == 9 && $2 == "4" { $1 = $2 = $3 = ""; print "  |  " $0 }' "$T/regions" | head -25 | cut -c1-170
         echo "  | Ou tombe chaque genre de region (la plus basse de chaque) :"
         awk '{ g = $4; for (i = 5; i <= NF && $i !~ /^[0-9a-f]+-[0-9a-f]+$/; i++) g = g " " $i
                if (!(g in vu)) { vu[g] = 1; printf "  |   %-28s %s\n", g, $3 } }' "$T/regions" | head -45
      else
         echo "  | vmmap n'a rien rendu : $(head -2 "$T/outil" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
      fi
   else
      wait $X64 2>/dev/null; c=$?
      if [ $c -gt 128 ]; then echo "  processus   : mort, tue par le signal $((c - 128))"; else echo "  processus   : mort, code $c"; fi
   fi
   # Un processus tue par le noyau (signature, page de code, garde) laisse un rapport.
   for f in $(find "$HOME/Library/Logs/DiagnosticReports" -name '*.ips' -newer "$T/debut" 2>/dev/null | head -2); do
      echo "  rapport de plantage : $(basename "$f")"
      if [ -x /usr/bin/jq ]; then
         tail -n +2 "$f" | /usr/bin/jq -r '. as $r | "exception : \(.exception | tojson)", "fin : \(.termination | tojson)",
            (.threads[] | select(.triggered == true) | .frames[:14][] | "  \($r.usedImages[.imageIndex].name // "?") + \(.imageOffset) \(.symbol // "")")' 2>/dev/null | cut -c1-220 | sed 's/^/  | /'
      else
         grep -o '"exception" : {[^}]*}\|"termination" : {[^}]*}' "$f" | cut -c1-300 | sed 's/^/  | /'
      fi
   done
}

titre "Machine"
echo "  macOS       : $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
echo "  modele      : $(sysctl -n hw.model 2>/dev/null) -- $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  memoire     : $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) Go"
echo "  processeur  : $(uname -m)"
echo "  Rosetta     : $(oui arch -x86_64 /usr/bin/true)"
echo "  taille page : $(sysctl -n hw.pagesize 2>/dev/null)"
echo "  noyau       : $(uname -r) ; protection systeme : $(csrutil status 2>/dev/null | sed 's/.*: *//' | cut -c1-40)"
echo "  jeu d'instructions : $(sysctl hw.optional.arm 2>/dev/null | awk -F'[.:]' '$NF + 0 == 1 { printf "%s ", $(NF - 1) }' | sed 's/FEAT_//g')" | fold -s -w 150 | sed '2,$s/^/    /'

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
         build/faux_steam.exe build/cidre-outil build/sonde-wx tools/steamcmd/steamcmd; do piece "$f"; done
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
serveur() { ps -axo pid=,command= | grep -F "$R/wine/" | grep wineserver | grep -v grep | head -1; }
DEJA=$(serveur)
# Juste apres `cidre setup` (une installation, une mise a jour), le serveur de
# Wine s'attarde quelques secondes sans qu'aucun jeu ne tourne : on le laisse
# partir plutot que de sauter l'essai x86-64.
i=0
while [ -n "$DEJA" ] && [ $i -lt 30 ] && ! pgrep -f "lancer_depuis_steam|faux_steam" >/dev/null 2>&1; do
   sleep 1; i=$((i + 1)); DEJA=$(serveur)
done
LANCE=1

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
   touch "$T/debut"
   if essai_x64 30 err+all,fixme-all; then
      echo "  -> demarre en $i s : l'emulation x86-64 fonctionne"
      fin_de_sortie 30
   else
      echo "  -> PAS DE LIGNE « $TEMOIN » apres $i s : le programme x86-64 ne demarre pas"
      fin_de_sortie 30
      autopsie_x64
      arreter_wine

      titre "Le meme, avec la trace de Wine (chargements, exceptions, processus)"
      essai_x64 15 +loaddll,+seh,+process,+pid && echo "  -> cette fois il demarre"
      echo "  $(wc -l <"$T/sortie" | tr -d ' ') lignes, dont $(grep -c "seh:" "$T/sortie") d'exceptions ; les dernieres :"
      fin_de_sortie 45
      arreter_wine

      titre "Le meme, avec d'autres reglages"
      for v in FEX_TSOENABLED=0 FEX_MULTIBLOCK=0 PROTON_OUVERT_LUAJIT=1; do
         if essai_x64 12 err+all,fixme-all "$v"; then echo "  $v : DEMARRE en $i s"; else echo "  $v : ne demarre pas"; fi
         arreter_wine
      done
   fi
fi

# Le mecanisme dont depend l'emulation x86-64, rejoue hors de Wine : comment le
# noyau decrit une faute sur une page de code, et si la reprise aboutit.
titre "Bascule ecriture/execution des pages de code (sonde, sans Wine)"
SONDE="$R/build/sonde-wx"
# un depot de developpement la construit au besoin ; un runtime installe la recoit
[ -x "$SONDE" ] || { [ -f "$R/tests/sonde_wx.c" ] && cc -arch arm64 -O1 -o "$SONDE" "$R/tests/sonde_wx.c" 2>/dev/null; }
if [ -x "$SONDE" ]; then
   limite 60 "$SONDE" || echo "  -> au moins un essai a echoue"
   cut -c1-200 "$T/outil" | sed 's/^/  | /'
else
   echo "  saute : la sonde n'est pas livree dans ce runtime"
fi

titre "Vulkan (pilote KosmicKrisp sur Metal)"
if [ -x "$R/prefix/bin/vulkaninfo" ] && [ -n "$ICD" ]; then
   VK_DRIVER_FILES="$ICD" DYLD_LIBRARY_PATH="$R/prefix/lib" avec_delai 20 "$R/prefix/bin/vulkaninfo" --summary
   grep -E "deviceName|driverName|driverInfo|apiVersion|ERROR|error|rror:" "$T/sortie" 2>/dev/null | head -8 | cut -c1-200 | sed 's/^/  | /'
   [ -s "$T/sortie" ] || echo "  | (aucune sortie)"
else
   echo "  saute : vulkaninfo n'est pas livre dans ce runtime"
fi

# Ce qu'on a lance nous-memes est arrete a la sortie (voir nettoyer).
titre "Fin du diagnostic"
