#!/bin/sh
# Applique les series de correctifs aux cinq arbres amont.
#
#   mesa          -> KosmicKrisp : tous les 00NN-kosmickrisp-*.patch
#   wine          -> x86_64, memoire externe, suites de tests
#                    (0028, 0035, 0036, 0038, 0040, 0041)
#   wine11        -> ARM64/macOS, exploratoire (0048, 0049)
#   vkd3d-proton  -> 6 correctifs (0004, 0007, 0008, 0014, 0016, 0044)
#   dxvk          -> 4 correctifs (0039, 0042, 0043, 0061)
#
# Verifie par reconstruction : les cinq series s'appliquent sur les arbres
# vanilla aux revisions ci-dessous, et l'arbre mesa obtenu est identique octet
# pour octet a l'arbre de travail.
#
# Usage :
#   etape1_appliquer_correctifs.sh            verifie les arbres existants
#   etape1_appliquer_correctifs.sh --cloner   clone les cinq arbres aux commits ci-dessous
#
# Enchainer ensuite sur etape2_construire_pile.sh.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)

MESA_URL=https://gitlab.freedesktop.org/mesa/mesa.git
MESA_REV=5f253b93041eb8d101e6ddef2613006bfde859cd
WINE_URL=https://gitlab.winehq.org/wine/wine.git
WINE_REV=b073859675060c9211fcbccfd90e4e87520dc2c2
WINE11_URL=https://gitlab.winehq.org/wine/wine.git
WINE11_REV=7b3fff76fa5178f6ce0141b2c776afa2a822f101
VKD3D_URL=https://github.com/HansKristian-Work/vkd3d-proton.git
VKD3D_REV=5d0db7414b0b3f1afa7c9a84acf9ff483cb805d1
DXVK_URL=https://github.com/doitsujin/dxvk.git
DXVK_REV=c3dd74be6baec53786d4e064a572185b70347a17
FEX_URL=https://github.com/FEX-Emu/FEX.git
FEX_REV=72b2ff88aec8
VKLOADER_URL=https://github.com/KhronosGroup/Vulkan-Loader.git
VKLOADER_REV=e14698090707

cloner() {
   url=$1; rev=$2; dst=$3
   [ -d "$dst" ] && { echo "   $dst existe deja, ignore"; return 0; }
   echo "   clonage $dst"
   git clone -q --filter=blob:none "$url" "$dst"
   git -C "$dst" checkout -q "$rev"
   git -C "$dst" submodule update -q --init --recursive 2>/dev/null || true
}

if [ "${1:-}" = "--cloner" ]; then
   echo "== clonage des arbres amont =="
   mkdir -p "$R/src"
   cloner "$MESA_URL"  "$MESA_REV"  "$R/src/mesa"
   cloner "$WINE_URL"  "$WINE_REV"  "$R/src/wine"
   cloner "$WINE11_URL" "$WINE11_REV" "$R/src/wine11"
   cloner "$VKD3D_URL" "$VKD3D_REV" "$R/src/vkd3d-proton"
   cloner "$DXVK_URL"  "$DXVK_REV"  "$R/src/dxvk"
   cloner "$VKLOADER_URL" "$VKLOADER_REV" "$R/src/Vulkan-Loader"
   mkdir -p "$R/third_party"
   cloner "$FEX_URL"  "$FEX_REV"  "$R/third_party/FEX"
fi

. "$R/tests/series.sh"

appliquer() {
   arbre=$1; shift
   echo "== $arbre =="
   n=0
   for f in "$@"; do
      [ -f "$f" ] || { echo "   ABSENT : $f" >&2; exit 1; }
      if patch -d "$R/src/$arbre" -p1 --silent < "$f"; then
         n=$((n + 1))
      else
         echo "   ECHEC sur $(basename "$f")" >&2
         exit 1
      fi
   done
   echo "   $n correctifs appliques"
}

appliquer mesa $(serie_mesa)
appliquer wine $(serie_wine)
# configure est genere : on le refait plutot que de le versionner.
if git -C "$R/src/wine" diff --name-only | grep -qx "configure.ac"; then
   (cd "$R/src/wine" && autoconf -f >/dev/null 2>&1; rm -rf configure~ autom4te.cache)
fi
appliquer wine11 $(serie_wine11)
if git -C "$R/src/wine11" diff --name-only | grep -qx "configure.ac"; then
   (cd "$R/src/wine11" && autoconf -f >/dev/null 2>&1; rm -rf configure~ autom4te.cache)
fi
appliquer vkd3d-proton $(serie_vkd3d_proton)
appliquer dxvk $(serie_dxvk)

# La chaine d'outils n'est pas un arbre amont suivi par git : le correctif 0069
# remplace l'acces au TEB par x18 dans winnt.h de llvm-mingw, sans quoi tout
# binaire ARM64EC construit ici faute sur macOS. Idempotent.
TC="$R/toolchain/llvm-mingw-20260908-ucrt-macos-universal/generic-w64-mingw32/include/winnt.h"
if [ -f "$TC" ]; then
   echo "== toolchain =="
   if grep -q __MINGW_TEB_SANS_X18 "$TC"; then
      echo "   0069 deja applique"
   # cat, pas `< motif` : un sh non interactif n'etend pas un motif dans une
   # redirection, et cherche alors un fichier nomme « 0069-*.patch ».
   elif cat "$R"/0069-*.patch | patch "$TC" -p0 --silent; then
      echo "   1 correctif applique"
   else
      echo "   ECHEC sur 0069" >&2; exit 1
   fi
   sh "$R/tests/construire_import_teb.sh" arm64ec >/dev/null
   sh "$R/tests/construire_import_teb.sh" aarch64 >/dev/null
   # Les objets de demarrage sont livres deja compiles : l'en-tete ne les couvre
   # pas. Voir NOTES paragraphe 242. Idempotent.
   python3 "$R/tests/corriger_crt_mingw.py" >/dev/null
fi

# FEX : meme raison, et le correctif reste chez nous. Voir NOTES paragraphe 237.
if [ -d "$R/third_party/FEX" ]; then
   echo "== FEX =="
   # Idempotent, correctif par correctif : chacun est reconnu a une ligne qu'il
   # est seul a poser.
   n=0
   for f in $(serie_fex); do
      case "$(basename "$f")" in
         0070-*) temoin=FEX_TEB_SANS_X18;           ou=Source/Windows/ARM64EC/Module.S ;;
         0118-*) temoin="Demarquer AVANT de liberer"; ou=FEXCore/Source/Interface/Core/LookupCache.cpp ;;
         0161-*) temoin="Avancer en adresse de l'hote"; ou=Source/Windows/Common/InvalidationTracker.cpp ;;
         0179-*) temoin="Cidre 0179"; ou=FEXCore/Source/Interface/Core/Core.cpp ;;
         0194-*) temoin="Ref LastCodeBlockHint {};"; ou=FEXCore/Source/Interface/IR/IREmitter.h ;;
         0197-*) temoin="Range.FullSMC = true;"; ou=Source/Windows/Common/InvalidationTracker.cpp ;;
         0198-*) temoin="// une valeur indeterminee."; ou=FEXCore/Source/Interface/Core/JIT/BranchOps.cpp ;;
         0199-*) temoin="(1 << FEXCore::X86State::RFLAG_AF_RAW_LOC));"; ou=Source/Windows/ARM64EC/Module.cpp ;;
         0200-*) temoin="Info.State == MEM_COMMIT && !(Info.Protect & PAGE_GUARD) &&"; ou=Source/Windows/Common/Exception.h ;;
         0203-*) temoin="Data->UnmapSize = 0;"; ou=Source/Windows/ARM64EC/Module.cpp ;;
         0211-*) temoin="// Cidre, sous-pages (SousPages.cpp) : appele par un talon avec x16 = Site*,"; ou=Source/Windows/ARM64EC/Module.S ;;
         0217-*) temoin="* @brief Cidre : the frontend reads guest code through this hook."; ou=FEXCore/include/FEXCore/Core/Context.h ;;
         0219-*) temoin="acces seraient alors rejoues pour toujours. Wine reproposera au prochain rejeu."; ou=Source/Windows/ARM64EC/SousPages.cpp ;;
         0224-*) temoin="Cidre 0224"; ou=FEXCore/Source/Interface/Core/JIT/JIT.cpp ;;
         0226-*) temoin="Cidre 0226 : marque dans CidreLectureNue"; ou=FEXCore/Source/Interface/Core/JIT/JIT.cpp ;;
         0225-*) temoin="Cidre 0225 : entre la liberation"; ou=Source/Windows/ARM64EC/Module.cpp ;;
         0229-*) temoin="Cidre 0229 : le contexte ARM64"; ou=Source/Windows/ARM64EC/Module.cpp ;;
         0233-*) temoin="Cidre 0233 : NtDllRedirectionLUTSize"; ou=Source/Windows/ARM64EC/Module.S ;;
         *) echo "   correctif FEX sans temoin : $(basename "$f")" >&2; exit 1 ;;
      esac
      # -F : texte litteral (les temoins contiennent . ( * &).
      if [ -f "$R/third_party/FEX/$ou" ] && grep -qF "$temoin" "$R/third_party/FEX/$ou"; then
         echo "   $(basename "$f" | cut -c1-4) deja applique"
      elif patch -d "$R/third_party/FEX" -p1 --silent < "$f"; then
         n=$((n + 1))
      else
         echo "   ECHEC sur $(basename "$f")" >&2; exit 1
      fi
   done
   echo "   $n correctifs appliques"
fi

echo
echo "Les trois arbres sont patches. Enchainer sur :"
echo "   $R/tests/etape2_construire_pile.sh"
