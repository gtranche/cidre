#!/bin/sh
# monter.sh <arbre> [liste.tsv] : monte un arbre fantome du runtime installe ($R = ~/Dev/proton-ouvert) dans
# <arbre> (.../arbres/A ou .../arbres/B), sans rien ecrire dans $R.
#   - CLONES (APFS, cp -c : presque aucune place) : cidre, tests, profils, outil-steam, prefix (KK + son ICD),
#     wine/wine11-arm64, wine/pfx-arm64ec, third_party/FEX/build-{ec,wow64}/Bin, wine/.wine-builtin-backup ;
#   - build/logs neuf ; wine/vklib-arm64 absent (cidre le recree pointant sur l'arbre) ;
#   - tout le reste : liens vers $R, lus seulement (cidre n'y ecrit pas) ;
#   - l'ICD de prefix/ pointe sur la dylib KK de l'arbre ;
#   - [liste.tsv] (chemin de pose relatif a $R, sha1, source absolue ; format de cidre-release-*/livraison) est
#     pose dans l'arbre, sha1 verifie avant et apres ;
#   - le prefixe est remis en accord avec le runtime de l'arbre : system32\ntdll.dll, xtajit64.dll, xtajit.dll,
#     syswow64\ntdll.dll, plus aucun renommage en attente (sinon wineboot remet un vieux FEX).
# Ecrit <arbre>/.banc-arbre (sha1 des binaires cles). Code 0 = arbre pret.
set -eu
R=${CIDRE_R:-$HOME/Dev/proton-ouvert}
DST=${1:?arbre}; LISTE=${2:-}
case $DST in /*) ;; *) DST=$(pwd)/$DST ;; esac
case $DST in "$R"|"$R"/*) echo "REFUS : jamais dans l'installe" >&2; exit 2 ;; esac
case $DST in */arbres/A|*/arbres/B) ;; *) echo "REFUS : arbre attendu en .../arbres/A ou .../arbres/B" >&2; exit 2 ;; esac
[ -x "$R/cidre" ] && [ -d "$R/wine/wine11-arm64" ] && [ -d "$R/wine/pfx-arm64ec" ] || { echo "runtime introuvable : $R" >&2; exit 2; }
TAB=$(printf '\t')

delier() { # <chemin relatif> : un lien vers $R devient un dossier reel de liens (recursif sur les parents)
   # $1 et non une variable : sh n'a pas de variables locales, la recursion l'ecraserait
   [ "$1" = . ] && return
   delier "$(dirname "$1")"
   if [ -L "$DST/$1" ]; then
      rm "$DST/$1"; mkdir "$DST/$1"
      ls -A "$R/$1" | while IFS= read -r e; do ln -s "$R/$1/$e" "$DST/$1/$e"; done
   elif [ ! -e "$DST/$1" ]; then
      mkdir "$DST/$1"   # dossier nouveau de la livraison
   fi
   dans_arbre "$DST/$1"
}
dans_arbre() { # <chemin absolu d'un dossier> : il doit etre reellement dans l'arbre (pas un lien vers $R)
   reel=$(cd "$1" && pwd -P)
   case $reel in "$DST_REEL"|"$DST_REEL"/*) ;; *) echo "REFUS : $1 sort de l'arbre ($reel)" >&2; exit 3 ;; esac
}
cloner() { # <chemin relatif> : copie APFS de $R/<p> dans l'arbre
   p=$1
   [ -e "$R/$p" ] || return 0
   delier "$(dirname "$p")"
   dans_arbre "$DST/$(dirname "$p")"
   rm -f "$DST/$p"
   cp -cpR "$R/$p" "$DST/$p"
}
poser() { # <chemin relatif> <source> <sha1>
   p=$1; src=$2; sha=$3
   case $p in /*|*..*) echo "REFUS : chemin de pose $p" >&2; exit 3 ;; esac
   [ "$(shasum "$src" | cut -d' ' -f1)" = "$sha" ] || { echo "ECART source $src (attendu $sha)" >&2; exit 4; }
   delier "$(dirname "$p")"
   [ -L "$DST/$p" ] && rm "$DST/$p"
   dans_arbre "$DST/$(dirname "$p")"
   cp -p "$src" "$DST/$p.neuf"; mv "$DST/$p.neuf" "$DST/$p"
   [ "$(shasum "$DST/$p" | cut -d' ' -f1)" = "$sha" ] || { echo "ECART apres pose $p" >&2; exit 4; }
}
sha8() { if [ -f "$1" ]; then shasum "$1" | cut -c1-8; else echo absent; fi; }

# 1. squelette de liens, sans .git (aucune commande git ne doit viser $R depuis l'arbre)
rm -rf "$DST"; mkdir -p "$DST"; DST_REEL=$(cd "$DST" && pwd -P)
ls -A "$R" | while IFS= read -r e; do [ "$e" = .git ] || ln -s "$R/$e" "$DST/$e"; done
# 2. clones
for p in cidre tests profils outil-steam prefix wine/wine11-arm64 wine/pfx-arm64ec wine/.wine-builtin-backup \
         third_party/FEX/build-ec/Bin third_party/FEX/build-wow64/Bin; do cloner "$p"; done
delier build; dans_arbre "$DST/build"; rm -f "$DST/build/logs"; mkdir "$DST/build/logs"
delier wine; dans_arbre "$DST/wine"; rm -f "$DST/wine/vklib-arm64" "$DST/wine/gstreamer-registre.bin"
# 3. ICD sur la dylib KK de l'arbre
for j in "$DST"/prefix/share/vulkan/icd.d/*.json; do
   sed "s#$R/#$DST/#g" "$j" > "$j.neuf"; mv "$j.neuf" "$j"
   grep -q "\"$DST/prefix/lib/" "$j" || { echo "ICD $j ne pointe pas dans l'arbre" >&2; exit 5; }
done
# 4. livraison candidate
N=0
if [ -n "$LISTE" ]; then
   while IFS="$TAB" read -r p sha src; do
      case $p in ''|'#'*) continue ;; esac
      poser "$p" "$src" "$sha"; N=$((N + 1))
   done < "$LISTE"
fi
# 5. prefixe en accord avec le runtime de l'arbre
P=$DST/wine/pfx-arm64ec; W=$DST/wine/wine11-arm64/lib/wine
sed -i '' '/^"PendingFileRenameOperations"=/d' "$P/system.reg"
find "$P/drive_c/windows" -maxdepth 4 -name 'dll*.tmp' -delete
for x in ntdll xtajit64 xtajit; do
   [ -f "$W/aarch64-windows/$x.dll" ] && cp -p "$W/aarch64-windows/$x.dll" "$P/drive_c/windows/system32/$x.dll"
done
[ -f "$W/i386-windows/ntdll.dll" ] && [ -d "$P/drive_c/windows/syswow64" ] && cp -p "$W/i386-windows/ntdll.dll" "$P/drive_c/windows/syswow64/ntdll.dll"
for x in ntdll xtajit64 xtajit; do
   [ "$(sha8 "$P/drive_c/windows/system32/$x.dll")" = "$(sha8 "$W/aarch64-windows/$x.dll")" ] || { echo "prefixe en desaccord : $x" >&2; exit 6; }
done
# 6. etiquette
{
   echo "arbre=$DST"; echo "monte=$(date '+%Y-%m-%d %H:%M:%S')"; echo "runtime=$R"
   echo "liste=${LISTE:-aucune (runtime installe)} ($N fichiers)"
   echo "ntdll.so=$(sha8 "$W/aarch64-unix/ntdll.so")"
   echo "ntdll.dll=$(sha8 "$W/aarch64-windows/ntdll.dll")"
   echo "xtajit64=$(sha8 "$W/aarch64-windows/xtajit64.dll")"
   echo "xtajit=$(sha8 "$W/aarch64-windows/xtajit.dll")"
   echo "kk=$(sha8 "$DST/prefix/lib/libvulkan_kosmickrisp.dylib")"
   echo "cidre=$(sha8 "$DST/cidre")"
} > "$DST/.banc-arbre"
echo "arbre pret : $DST ($N fichiers poses)"
