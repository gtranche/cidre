#!/bin/sh
# Voie « vulkan » apprise par etat_shaders.sh : dossiers d'etat fictifs.
B=$(cd "$(dirname "$0")/.." && pwd)
P=/Users/gtranche/Dev/proton-ouvert
R=$(mktemp -d); mkdir -p "$R/tests"
cp "$B/tests/etat_shaders.sh" "$R/tests/"
cp "$P/tests/profil_cidre.sh" "$P/tests/fiche_profil.sh" "$P/tests/machine.sh" "$R/tests/"
ln -s "$P/outil-steam" "$R/outil-steam"; ln -s "$P/profils" "$R/profils"
echo 1.5.12 >"$R/VERSION"
E() { sh "$R/tests/etat_shaders.sh" "$@"; }
ok=0; ko=0
verif() { if [ "$2" = "$3" ]; then ok=$((ok + 1)); echo "  ok   $1"; else ko=$((ko + 1)); echo "  KO   $1 : attendu « $2 », obtenu « $3 »"; fi; }

D=$(mktemp -d); export CIDRE_DIR=$D
mkdir -p "$D/vkd3d-cache/1222140"
debut=$(( $(date +%s) - 300 ))
sleep 1; : >"$D/vkd3d-cache/1222140/kk_pipelines.1.0.mtl4archive"
verif "jeu jamais joue : voie dxmt (profil)" dxmt "$(E voie 1222140)"
E noter 1222140 dxmt "$debut" >/dev/null
verif "archives KK ecrites pendant la partie : notee vulkan" "1222140.vulkan" "$(ls "$D/shaders")"
verif "lancement suivant : voie vulkan" vulkan "$(E voie 1222140)"
verif "300 s de jeu : en cache" en_cache "$(E etat 1222140 | sed -n 's/^etat=//p')"
echo 1.5.13 >"$R/VERSION"
verif "Cidre mis a jour : KK a refaire" "cache_invalide cidre" "$(E etat 1222140 | sed -n 's/^etat=//p;s/^raison=//p' | tr '\n' ' ' | sed 's/ $//')"
echo 1.5.12 >"$R/VERSION"

D2=$(mktemp -d); export CIDRE_DIR=$D2
E noter 3527290 dxmt "$debut" >/dev/null
verif "jeu DXMT sans archive KK : reste dxmt" "3527290.dxmt" "$(ls "$D2/shaders")"
verif "et sa voie reste dxmt" dxmt "$(E voie 3527290)"

D3=$(mktemp -d); export CIDRE_DIR=$D3
mkdir -p "$D3/vkd3d-cache/1222140"; : >"$D3/vkd3d-cache/1222140/kk_pipelines.1.0.mtl4archive"
sleep 1; debut2=$(date +%s)
E noter 1222140 dxmt "$debut2" >/dev/null
verif "archive KK d'avant la partie : pas vulkan" "1222140.dxmt" "$(ls "$D3/shaders")"

rm -rf "${R:?}" "${D:?}" "${D2:?}" "${D3:?}"
echo "$((ok + ko)) verifications, $ko en echec"
[ $ko -eq 0 ]
