#!/bin/sh
# Verifie que la serie de correctifs reproduit l'arbre de travail a l'identique.
#
# On compare l'effet des correctifs, pas l'arborescence : un arbre de travail
# contient aussi des sous-projets telechardes et des journaux de construction,
# que git ne suit pas et qui n'ont rien a voir avec la serie. Pour chaque arbre
# amont : plan de travail a la revision figee, application de la serie, puis
# comparaison de « git diff » des deux cotes.
#
# Sous-modules : un « git worktree add » ne les extrait pas. Ceux que la serie
# touche (FEX : External/rpmalloc, 0488/0489) sont extraits dans le plan de
# travail depuis le sous-module de l'arbre de travail, et compares a part (le
# superprojet n'en voit qu'un pointeur « -dirty »).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
. "$R/tests/series.sh"
TMP=${TMPDIR:-/tmp}/reconstruction-$$
SOUS="$R/third_party/FEX/External/rpmalloc"
trap 'rm -rf "$TMP"; for t in mesa wine wine11 vkd3d-proton dxvk dxmt; do
        git -C "$R/src/$t" worktree prune 2>/dev/null || true; done
        git -C "$SOUS" worktree prune 2>/dev/null || true
        git -C "$R/third_party/FEX" worktree prune 2>/dev/null || true' EXIT
mkdir -p "$TMP"
rc=0

# comparer <nom> <plan de travail patche> <arbre de travail>
comparer() {
   # (sh n'a pas de variables locales : ne pas reprendre dst/src de verifier)
   nom=$1; c_dst=$2; c_src=$3
   find "$c_dst" -name '*.orig' -delete 2>/dev/null
   git -C "$c_dst" add -A >/dev/null 2>&1
   git -C "$c_dst" diff --ignore-submodules=dirty HEAD > "$TMP/$nom.attendu"

   idx="$TMP/$nom.index"
   GIT_INDEX_FILE="$idx" git -C "$c_src" read-tree HEAD
   # Les traces de construction ne font pas partie de la serie, ni les restes
   # de « patch » (.orig, .rej) d'un arbre de developpement : etape1 ne les
   # produit pas, et le plan de travail les efface ci-dessus.
   GIT_INDEX_FILE="$idx" git -C "$c_src" add -A -- . \
      ':!build-*.txt' ':!subprojects/.wraplock' ':!*.cache.write' ':!*.cache' \
      ':!*.log' ':!compile_commands.json' ':!*.orig' ':!*.rej' >/dev/null 2>&1 \
      || { echo "$nom : indexation de l'arbre de travail impossible (droits d'ecriture sur son .git ?)"; rc=1; return 0; }
   GIT_INDEX_FILE="$idx" git -C "$c_src" diff --ignore-submodules=dirty HEAD > "$TMP/$nom.obtenu"

   if cmp -s "$TMP/$nom.attendu" "$TMP/$nom.obtenu"; then
      echo "$nom : $n correctifs, reproduction exacte"
   else
      ecart=$(diff "$TMP/$nom.attendu" "$TMP/$nom.obtenu" | grep -c '^[<>]')
      echo "$nom : $n correctifs, $ecart lignes divergentes"
      diff "$TMP/$nom.attendu" "$TMP/$nom.obtenu" \
         | grep '^[<>] diff --git' | sed 's/^/   /' | sort -u | head -10
      rc=1
   fi
}

verifier() {
   arbre=$1; shift
   src="$R/src/$arbre"
   # FEX n'est pas sous src/.
   [ "$arbre" = FEX ] && src="$R/third_party/FEX"
   [ -e "$src/.git" ] || { echo "$arbre : absent, ignore"; return 0; }
   dst="$TMP/$arbre"
   git -C "$src" worktree add -q --detach "$dst" "$(git -C "$src" rev-parse HEAD)"
   sous=
   if [ "$arbre" = FEX ] && [ -e "$SOUS/.git" ]; then
      sous=External/rpmalloc
      rmdir "$dst/$sous" 2>/dev/null || true
      git -C "$SOUS" worktree add -q --detach "$dst/$sous" "$(git -C "$SOUS" rev-parse HEAD)"
   fi

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
   # Meme regeneration que dans etape1, sinon la comparaison porterait sur un
   # configure produit d'un cote et pas de l'autre.
   if git -C "$dst" diff --name-only | grep -qx "configure.ac"; then
      (cd "$dst" && autoconf -f >/dev/null 2>&1; rm -rf configure~ autom4te.cache)
   fi
   [ -n "$sous" ] && comparer "$arbre-$(basename "$sous")" "$dst/$sous" "$src/$sous"
   comparer "$arbre" "$dst" "$src"
}

verifier mesa $(serie_mesa)
verifier wine $(serie_wine)
verifier wine11 $(serie_wine11)
verifier vkd3d-proton $(serie_vkd3d_proton)
verifier dxvk $(serie_dxvk)
verifier dxmt $(serie_dxmt)
verifier FEX $(serie_fex)

[ $rc -eq 0 ] && echo "RECONSTRUCTION VERIFIEE" || echo "RECONSTRUCTION INCOMPLETE"
exit $rc
