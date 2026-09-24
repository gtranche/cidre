#!/bin/sh
# Verifie que la serie de correctifs reproduit l'arbre de travail a l'identique.
#
# On compare l'effet des correctifs, pas l'arborescence : un arbre de travail
# contient aussi des sous-projets telechardes et des journaux de construction,
# que git ne suit pas et qui n'ont rien a voir avec la serie. Pour chaque arbre
# amont : plan de travail a la revision figee, application de la serie, puis
# comparaison de « git diff » des deux cotes.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
. "$R/tests/series.sh"
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
      if patch -d "$dst" -p1 --silent < "$f" >/dev/null 2>&1; then
         n=$((n + 1))
      else
         echo "$arbre : ECHEC $(basename "$f")"; rc=1
      fi
   done

   # Les correctifs creent des fichiers, suivis ou non selon les arbres. Pour
   # comparer la meme chose des deux cotes, on indexe tout — l'arbre de travail
   # dans un index temporaire, pour ne jamais toucher le sien.
   git -C "$dst" add -A >/dev/null 2>&1
   git -C "$dst" diff HEAD > "$TMP/$arbre.attendu"

   idx="$TMP/$arbre.index"
   GIT_INDEX_FILE="$idx" git -C "$src" read-tree HEAD
   # Les traces de construction ne font pas partie de la serie.
   GIT_INDEX_FILE="$idx" git -C "$src" add -A -- . \
      ':!build-*.txt' ':!subprojects/.wraplock' ':!*.cache.write' ':!*.cache' \
      ':!*.log' ':!compile_commands.json' >/dev/null 2>&1
   GIT_INDEX_FILE="$idx" git -C "$src" diff HEAD > "$TMP/$arbre.obtenu"

   if cmp -s "$TMP/$arbre.attendu" "$TMP/$arbre.obtenu"; then
      echo "$arbre : $n correctifs, reproduction exacte"
   else
      ecart=$(diff "$TMP/$arbre.attendu" "$TMP/$arbre.obtenu" | grep -c '^[<>]')
      echo "$arbre : $n correctifs, $ecart lignes divergentes"
      diff "$TMP/$arbre.attendu" "$TMP/$arbre.obtenu" \
         | grep '^[<>] diff --git' | sed 's/^/   /' | sort -u | head -10
      rc=1
   fi
}

verifier mesa $(serie_mesa)
verifier wine $(serie_wine)
verifier wine11 $(serie_wine11)
verifier vkd3d-proton $(serie_vkd3d_proton)
verifier dxvk $(serie_dxvk)

[ $rc -eq 0 ] && echo "RECONSTRUCTION VERIFIEE" || echo "RECONSTRUCTION INCOMPLETE"
exit $rc
