#!/bin/sh
# Verifie que la serie de correctifs reproduit l'arbre de travail a l'identique.
#
# Pour chaque arbre amont : cree un plan de travail git a la revision figee,
# applique la serie, compare au repertoire src/ correspondant. Ne modifie rien.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/reconstruction-$$
trap 'rm -rf "$TMP"; for t in mesa wine wine11 vkd3d-proton dxvk; do
        git -C "$R/src/$t" worktree prune 2>/dev/null || true; done' EXIT
mkdir -p "$TMP"
rc=0

verifier() {
   arbre=$1; shift
   src="$R/src/$arbre"
   [ -e "$src/.git" ] || { echo "$arbre : absent, ignore"; return 0; }
   dst="$TMP/$arbre"
   git -C "$src" worktree add -q --detach "$dst" "$(git -C "$src" rev-parse HEAD)"
   n=0
   for f in "$@"; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in 0000-*) continue;; esac
      if patch -d "$dst" -p1 --silent < "$f" >/dev/null 2>&1; then
         n=$((n + 1))
      else
         echo "$arbre : ECHEC $(basename "$f")"; rc=1
      fi
   done
   ecart=$(diff -rq --exclude=.git --exclude=__pycache__ --exclude='*.orig' \
           --exclude='*.rej' --exclude='*.pyc' "$dst/src" "$src/src" 2>/dev/null | wc -l)
   if [ "$ecart" -eq 0 ]; then
      echo "$arbre : $n correctifs, reproduction exacte"
   else
      echo "$arbre : $n correctifs, $ecart fichiers divergents"; rc=1
   fi
}

verifier mesa $(ls "$R"/00[0-9][0-9]-kosmickrisp-*.patch)
verifier wine "$R"/0028-*.patch "$R"/0035-*.patch "$R"/0036-*.patch \
              "$R"/0038-*.patch "$R"/0040-*.patch "$R"/0041-*.patch
verifier wine11 "$R"/0048-*.patch "$R"/0049-*.patch
verifier vkd3d-proton "$R"/0004-*.patch "$R"/0007-*.patch "$R"/0008-*.patch \
                      "$R"/0014-*.patch "$R"/0016-*.patch "$R"/0044-*.patch
verifier dxvk "$R"/0039-*.patch "$R"/0042-*.patch "$R"/0043-*.patch \
              "$R"/0061-*.patch

[ $rc -eq 0 ] && echo "RECONSTRUCTION VERIFIEE" || echo "RECONSTRUCTION INCOMPLETE"
exit $rc
