#!/bin/sh
# Verifie (et installe ce qui manque) les prerequis systeme d'une install propre.
# Idempotent, ne casse rien : signale ce qui va, installe ce qui manque.
#   sh tests/etape0_prerequis.sh            verifie
#   sh tests/etape0_prerequis.sh --installer  installe les paquets manquants
set -e
MODE=${1:-verifier}
manque=0
ok(){ echo "  [ok] $1"; }
ko(){ echo "  [MANQUE] $1"; manque=1; }

echo "== Xcode Command Line Tools =="
xcode-select -p >/dev/null 2>&1 && ok "CLT ($(xcode-select -p))" || { ko "CLT (xcode-select --install)"; }

echo "== Homebrew =="
BREW_ARM=/opt/homebrew/bin/brew
BREW_X86=/usr/local/bin/brew
[ -x "$BREW_ARM" ] && ok "Homebrew arm64 (/opt/homebrew)" || ko "Homebrew arm64 (/opt/homebrew) -- installer arch -arm64"
[ -x "$BREW_X86" ] && ok "Homebrew Intel (/usr/local)" || ko "Homebrew Intel (/usr/local) -- installer sous Rosetta (arch -x86_64)"

verifier_paquets(){
   brew=$1; shift
   [ -x "$brew" ] || return 0
   for p in "$@"; do
      if "$brew" list --formula "$p" >/dev/null 2>&1; then ok "$p ($brew)"; else
         ko "$p ($brew)"
         [ "$MODE" = "--installer" ] && { echo "    -> installation $p"; "$brew" install "$p" || true; }
      fi
   done
}
echo "== paquets Homebrew arm64 (outils de build) =="
verifier_paquets "$BREW_ARM" llvm spirv-tools cmake glslang
echo "== outils de build (commande disponible, source libre : venv toolchain, brew, pip) =="
export PATH="$(cd "$(dirname "$0")/.." && pwd)/toolchain/bin:$PATH"
for c in meson ninja; do
   if command -v "$c" >/dev/null 2>&1; then ok "$c ($(command -v "$c"))"; else
      ko "$c"
      [ "$MODE" = "--installer" ] && { [ "$c" = ninja ] && "$BREW_X86" install ninja 2>/dev/null || pip3 install --user "$c" 2>/dev/null || true; }
   fi
done

echo "== autres outils (commande ; mingw-w64 est fourni par la toolchain llvm-mingw) =="
# bison/zstd : utilises par les builds ; peuvent venir du systeme, d'un brew, ou
# etre deja la. On verifie la commande, non bloquant (avertissement seulement).
for c in bison zstd; do
   command -v "$c" >/dev/null 2>&1 && ok "$c ($(command -v "$c"))" || echo "  [avert] $c absent (souvent fourni ailleurs ; a installer si un build le reclame)"
done

echo
[ $manque -eq 0 ] && echo "prerequis : TOUT l'essentiel est la." || {
   echo "prerequis : il manque des elements (ci-dessus)."
   [ "$MODE" != "--installer" ] && echo "Relancez avec --installer pour poser les paquets Homebrew manquants (les 2 Homebrew + Xcode CLT restent manuels)."
   exit 1
}
