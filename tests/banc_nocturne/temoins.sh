#!/bin/sh
# temoins.sh construire <dossier-exe>
#   construit les .exe de temoins.tsv depuis les sources de $R/tests (memes binaires pour A et B : seul le runtime
#   change), avec le clang mingw de $R/toolchain (repli : x86_64-w64-mingw32-gcc).
# temoins.sh passer <arbre> <A|B> <dossier-exe> <dossier-sortie>
#   passe les temoins sur l'arbre fantome, dans un prefixe a part (wine/pfx-temoins, clone du prefixe en accord de
#   l'arbre : jamais pfx-arm64ec lui-meme). Ecrit une ligne TSV par temoin sur stdout :
#     temoin nom arbre statut duree_s resume mesures
#   Un temoin marque « rare » dans temoins.tsv est rejoue jusqu'a 3 fois ; ECHEC seulement si les 3 echouent.
#   statut : ok | ECHEC | BLOQUE | absent | refus. Code 3 = refus (un jeu ou un wineserver tourne).
set -u
H=$(cd "$(dirname "$0")" && pwd)
. "$H/commun.sh"
R=${CIDRE_R:-$HOME/Dev/proton-ouvert}
LISTE=${CIDRE_TEMOINS:-$H/temoins.tsv}

construire() {
   X=${1:?dossier-exe}; mkdir -p "$X"
   CC=$R/toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang
   grep -v '^#' "$LISTE" | while IFS="$TAB" read -r nom src args env lim; do
      case $src in *.c) ;; *) continue ;; esac
      exe=$X/${src%.c}.exe; [ "$src" = h32alerte.c ] && exe=$X/h64alerte.exe
      [ -f "$exe" ] && continue
      "$CC" -O1 -o "$exe" "$R/tests/$src" 2>"$X/${src%.c}.cc.log" ||
         x86_64-w64-mingw32-gcc -O1 -o "$exe" "$R/tests/$src" 2>>"$X/${src%.c}.cc.log" ||
         echo "construction impossible : $src (voir $X/${src%.c}.cc.log)" >&2
   done
   ls "$X"/*.exe 2>/dev/null | wc -l | tr -d ' '
}

passer() {
   S=${1:?arbre}; T=${2:?A|B}; X=${3:?dossier-exe}; OUT=${4:?sortie}
   case $S in */arbres/A|*/arbres/B) ;; *) echo "arbre attendu en .../arbres/A|B" >&2; exit 2 ;; esac
   [ -f "$S/.banc-arbre" ] || { echo "arbre non monte : $S" >&2; exit 2; }
   r=$(deja_occupe); [ -z "$r" ] || { printf 'temoin\t*\t%s\trefus\t-\t%s\t-\n' "$T" "$r"; exit 3; }
   J=$OUT/temoins-$T; mkdir -p "$J"
   WR=$S/wine/wine11-arm64; P=$S/wine/pfx-temoins
   case $P in "$R"/*) echo "jamais le prefixe de l'installe" >&2; exit 2 ;; esac
   rm -rf "$P"; cp -cpR "$S/wine/pfx-arm64ec" "$P"
   cp -p "$X"/*.exe "$P/drive_c/"
   export WINEPREFIX="$P" WINEDEBUG=-all
   export WINEDLLOVERRIDES="mscoree,mshtml=;dxgi,d3d11,d3d10core,winemetal=b;d3d12,d3d12core=b"
   export VK_DRIVER_FILES=$S/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
   # vklib-arm64 de l'arbre (comme etape2_pile_arm64ec.sh) : FreeType/SDL2 arm64, la boucle Vulkan de l'arbre
   mkdir -p "$S/wine/vklib-arm64"
   ln -sf "$S/prefix/lib/libvulkan.1.dylib" "$S/wine/vklib-arm64/libMoltenVK.dylib"
   for l in libfreetype.6.dylib libSDL2-2.0.0.dylib; do [ -f /opt/homebrew/lib/$l ] && ln -sf /opt/homebrew/lib/$l "$S/wine/vklib-arm64/$l"; done
   export DYLD_LIBRARY_PATH=$S/wine/vklib-arm64
   export DYLD_FALLBACK_LIBRARY_PATH=$S/prefix/lib
   export MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod
   export FEX_HOSTFEATURES=enablecrypto
   unset CIDRE_SYNC_LOCAL
   renice -n 10 $$ >/dev/null   # nice (binaire protege) effacerait les DYLD_* ; la priorite basse est heritee
   W=$WR/bin/wine; WS=$WR/bin/wineserver

   lancer() { # limite journal commande... ; pose $rc et $n
      lim=$1; log=$2; shift 2
      echo "# $(date '+%H:%M:%S') $*" > "$log"
      "$@" >> "$log" 2>&1 &
      pid=$!; n=0
      while kill -0 $pid 2>/dev/null && [ $n -lt "$lim" ]; do sleep 1; n=$((n + 1)); done
      if kill -0 $pid 2>/dev/null; then kill $pid; rc=bloque; else wait $pid; rc=$?; fi
   }
   # mise a jour du prefixe clone, puis un demarrage pour les renommages en attente ; le FEX et le ntdll de
   # system32 doivent ensuite etre ceux de l'arbre
   lancer 300 "$J/wineboot.log" "$W" wineboot -u; "$WS" -w
   lancer 120 "$J/boot2.log" "$W" cmd /c exit; "$WS" -w
   for x in ntdll xtajit64 xtajit; do
      a=$(shasum "$P/drive_c/windows/system32/$x.dll" | cut -c1-8); b=$(shasum "$WR/lib/wine/aarch64-windows/$x.dll" | cut -c1-8)
      if [ "$a" != "$b" ]; then
         # wineboot -u a pu remettre un vieux binaire : on recopie, une seule fois
         cp -p "$WR/lib/wine/aarch64-windows/$x.dll" "$P/drive_c/windows/system32/$x.dll"
         echo "system32/$x.dll $a remis a $b apres wineboot" >> "$J/accord.log"
      fi
   done
   DYLD_PRINT_LIBRARIES=1 "$W" cmd /c exit > "$J/dyld.log" 2>&1; "$WS" -w
   if ! grep -a -q "$WR/lib/wine/aarch64-unix/ntdll.so" "$J/dyld.log"; then
      printf 'temoin\t*\t%s\tECHEC\t-\tntdll.so de l arbre non charge (%s)\t-\n' "$T" "$J/dyld.log"; "$WS" -k; return 0
   fi

   ENV_PREC=-
   grep -v '^#' "$LISTE" | while IFS="$TAB" read -r nom src args env lim rare; do
      [ -n "$nom" ] || continue
      [ "$args" = - ] && args=
      exe=${src%.c}.exe; [ "$src" = h32alerte.c ] && exe=h64alerte.exe
      if [ "$env" != natif ] && [ ! -f "$P/drive_c/$exe" ]; then
         printf 'temoin\t%s\t%s\tabsent\t-\t%s non construit\t-\n' "$nom" "$T" "$exe"; continue
      fi
      # temoin « rare » (defaut connu a quelques % des passes) : rejoue jusqu'a 3 fois, l'echec ne compte que s'il
      # persiste ; le resume dit « [rare k/3] » (k echecs) des qu'un essai a echoue
      essais=1; [ "$rare" = rare ] && essais=3
      i=0; echecs=0
      while [ $i -lt $essais ]; do
         i=$((i + 1))
         log=$J/$nom.log; [ $i -gt 1 ] && log=$J/$nom.essai$i.log
         if [ "$env" = natif ]; then
            # shellcheck disable=SC2086
            ( unset WINEPREFIX DYLD_LIBRARY_PATH; lancer "$lim" "$log" sh "$S/tests/$src" $args "$S/prefix/lib/libvulkan_kosmickrisp.dylib"; echo "$rc $n" > "$log.rc" )
            read -r rc n < "$log.rc"
         else
            if [ "$env" != "$ENV_PREC" ]; then "$WS" -k 2>/dev/null; "$WS" -w; ENV_PREC=$env; fi
            # shellcheck disable=SC2086
            if [ "$env" = - ]; then lancer "$lim" "$log" "$W" "c:\\$exe" $args
            else lancer "$lim" "$log" env "$env" "$W" "c:\\$exe" $args; fi
            [ "$rc" = bloque ] && { "$WS" -k 2>/dev/null; "$WS" -w; }
         fi
         v=$(verdict_temoin "$log" "$rc")
         [ "$(echo "$v" | cut -f1)" = ok ] && break
         echecs=$((echecs + 1))
      done
      st=$(echo "$v" | cut -f1); res=$(echo "$v" | cut -f2); mes=$(echo "$v" | cut -f3)
      [ $essais -gt 1 ] && [ $echecs -gt 0 ] && res="[rare $echecs/$essais] $res"
      printf 'temoin\t%s\t%s\t%s\t%s\t%s\t%s\n' "$nom" "$T" "$st" "$n" "$res" "$mes"
   done
   "$WS" -k 2>/dev/null; "$WS" -w
}

case ${1:-} in
construire) shift; construire "$@" ;;
passer) shift; passer "$@" ;;
*) sed -n '2,9p' "$0" >&2; exit 2 ;;
esac
