#!/bin/sh
# Preparation des shaders avant le lancement (tests/preparer_shaders.sh), sans
# jeu ni GPU : base de pipelines, liste chaude et pilote fictifs, rejeu simule
# par un faux outil (le vrai build/prepa-shaders sert pour compter/filtrer/
# cles/ajouter). Ne lit ni n'ecrit aucun cache reel (CIDRE_DIR temporaire).
#   sh tests/tester_preparation_shaders.sh
set -u
B=$(cd "$(dirname "$0")/.." && pwd)
P="$B/tests/preparer_shaders.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-prepa.XXXXXX")
export CIDRE_DIR="$T/cidre"; mkdir -p "$CIDRE_DIR"
export CIDRE_PRECOMPIL_FAMILLE=apple7 CIDRE_PREPARATION_MACOS=25A100 CIDRE_PRECOMPIL_SANS_RESEAU=1
unset MESA_SHADER_CACHE_MAX_SIZE MESA_KK_PIPELINE_CACHE CIDRE_BASE_PIPELINES CIDRE_LISTE_CHAUDE CIDRE_PREPARATION_SHADERS CIDRE_PIPELINE_CACHE
ok=0; ko=0
verif() { if [ "$2" = "$3" ]; then ok=$((ok + 1)); echo "  ok   $1"; else ko=$((ko + 1)); echo "  KO   $1 : attendu « $2 », obtenu « $3 »"; fi; }
champ() { sed -n -E "s/^($1)=//p"; }

# Le vrai outil, construit dans le temporaire (rien dans build/)
VRAI="$T/prepa-shaders"
cc -arch arm64 -O1 \
   -o "$VRAI" "$B/tests/prepa_shaders.c" || { echo "construction de prepa-shaders impossible"; exit 1; }
# Le faux : rejouer = ajoute au journal chaque cle de la base filtree (FAUX_PAUSE
# s entre deux, FAUX_ECHEC = rang qui echoue), comme KosmicKrisp lot par lot.
FAUX="$T/faux-prepa"
cat >"$FAUX" <<FIN
#!/bin/sh
case \$1 in rejouer) ;; *) exec "$VRAI" "\$@" ;; esac
env | sort >"$T/env-rejeu.txt"
echo \$\$ >"$T/pid-rejeu"
mkdir -p "\$MESA_KK_PIPELINE_CACHE/mesa"   # comme disk_cache_create a la creation du device
"$VRAI" cles "\$CIDRE_REJEU/pipelines.bin" >"$T/cles-rejeu"
n=\$(( \$(stat -f %z "$T/cles-rejeu") / 32 )); i=0; r=0
while [ \$i -lt \$n ]; do
   [ "\$i" = "\${FAUX_ECHEC:-x}" ] || { dd if="$T/cles-rejeu" bs=32 skip=\$i count=1 2>/dev/null >>"\$MESA_KK_PIPELINE_CACHE/\$CIDRE_REJEU_JOURNAL"; r=\$((r + 1)); }
   i=\$((i + 1)); sleep \${FAUX_PAUSE:-0}
done
mkdir -p "\$MESA_KK_PIPELINE_CACHE/mesa"
echo "kk: rejeu fini en 0.1 s : \$n lances, \$r reussis, \$((n - r)) echecs, 0 deja faits, 0 illisibles" >&2
FIN
chmod +x "$FAUX"
export CIDRE_PREPARATION_OUTIL="$FAUX"
# Pilote fictif : la cle de code et le rejeu dans un journal nomme (0472)
pilote() { printf 'xx KK_CODEGEN=1-%s yy %s zz\n' "$1" "$2" >"$T/kk-$1.dylib"; echo "$T/kk-$1.dylib"; }
export CIDRE_KK_DYLIB=$(pilote 0123456789abcdef CIDRE_REJEU_JOURNAL)

# Base : enregistrement = "KKP1", taille 72, cle VS, cle FS, 8 octets d'etat
cle() { printf '%08d%s%023d' "$1" "$2" 0; }
base() { # <dossier> <n>
   mkdir -p "$1"; : >"$1/pipelines.bin"; i=1
   while [ $i -le "$2" ]; do printf 'KKP1\110\000\000\000%s%sETAT%04d' "$(cle $i V)" "$(cle $i F)" $i >>"$1/pipelines.bin"; i=$((i + 1)); done
   : >"$1/nuanceurs.bin"; : >"$1/fonctions.bin"
   printf 'CIDRE_CACHE_DISQUE=1\nCIDRE_COMPILE_FOND=4\nCIDRE_LISTE_CHAUDE=/ailleurs/liste.bin\nCIDRE_BASE_PIPELINES=/ailleurs/base\nCIDRE_COMPILE_DIFFEREE=8\nCIDRE_ILOT_EXE=Diablo IV.exe\nMESA_KK_PIPELINE_CACHE=/ailleurs/cache\nMESA_SHADER_CACHE_DIR=/ailleurs/mesa\nCIDRE_AIR_DIRECT=1\n' >"$1/env.txt"
}
chaude() { for c in "$@"; do printf '%s' "$c"; done; }

ID=999001; C="$CIDRE_DIR/vkd3d-cache/$ID"
verif "rien de note : inactive (sans_base)" "inactive sans_base" "$(sh "$P" etat $ID | champ 'etat|raison' | tr '\n' ' ' | sed 's/ $//')"
base "$C/base-pipelines" 20
verif "base sans liste chaude : inactive (sans_liste)" "sans_liste" "$(sh "$P" etat $ID | champ raison)"
# Liste chaude : les VS 1 a 8 et les FS 9 et 10 ont ete lies ; plus une cle inconnue
chaude "$(cle 1 V)" "$(cle 2 V)" "$(cle 3 V)" "$(cle 4 V)" "$(cle 5 V)" "$(cle 6 V)" "$(cle 7 V)" "$(cle 8 V)" \
       "$(cle 9 F)" "$(cle 10 F)" "$(cle 999 V)" >"$C/liste-chaude-kk.bin"
verif "option coupee : inactive (option)" "option" "$(CIDRE_PREPARATION_SHADERS=0 sh "$P" etat $ID | champ raison)"
verif "pilote sans rejeu nomme : inactive (pilote)" "pilote" "$(CIDRE_KK_DYLIB=$(pilote 1111111111111111 rien) sh "$P" etat $ID | champ raison)"
mkdir -p "$CIDRE_DIR/en-cours"; echo $$ >"$CIDRE_DIR/en-cours/$ID"
verif "jeu en cours : inactive (en_cours)" "en_cours" "$(sh "$P" etat $ID | champ raison)"
rm -f "$CIDRE_DIR/en-cours/$ID"
E=$(sh "$P" etat $ID)
verif "10 pipelines lies sur 20 : a preparer" "a_preparer 10 10" "$(printf '%s\n' "$E" | champ 'etat|a_faire|connus' | tr '\n' ' ' | sed 's/ $//')"
rm -f "$C/preparation/chaud"
verif "outil absent : construit a la demande (sans en-tetes Vulkan)" "a_preparer oui" \
   "$(CIDRE_PREPARATION_OUTIL="$T/construit/prepa-shaders" sh "$P" etat $ID | champ etat) $( [ -x "$T/construit/prepa-shaders" ] && echo oui || echo non)"
verif "identite : cle KK, famille, build de macOS" "1-0123456789abcdef-apple7-25A100" "$(printf '%s\n' "$E" | champ identite)"
verif "premiere rencontre sans cache : non adoptee" "non" "$(cut -d' ' -f2 "$C/preparation/adoption")"

S=$(sh "$P" preparer $ID --json 2>"$T/err")
verif "evenement debut" '{"evenement":"preparation","etat":"debut","fait":0,"total":10}' "$(printf '%s\n' "$S" | sed -n 1p)"
verif "evenement finie" '"finie",10,10,0' "$(printf '%s\n' "$S" | tail -1 | sed -E 's/.*"etat":("[a-z]+"),"fait":([0-9]+),"total":([0-9]+),"echecs":([0-9]+).*/\1,\2,\3,\4/')"
verif "rien d'autre que des evenements sur la sortie" "0" "$(printf '%s\n' "$S" | grep -vc '^{"evenement":"preparation"')"
J="$C/rejoues-prep-1-0123456789abcdef-apple7-25A100.bin"
verif "journal de l'identite : 10 cles" 320 "$(stat -f %z "$J" 2>/dev/null)"
verif "rejeu : journal nomme" "CIDRE_REJEU_JOURNAL=rejoues-prep-1-0123456789abcdef-apple7-25A100.bin" "$(grep '^CIDRE_REJEU_JOURNAL=' "$T/env-rejeu.txt")"
verif "rejeu : cache du jeu" "MESA_KK_PIPELINE_CACHE=$C" "$(grep '^MESA_KK_PIPELINE_CACHE=' "$T/env-rejeu.txt")"
verif "rejeu : ni liste chaude, ni base, ni fond, ni dossier d'ailleurs" "0" "$(grep -c -E '^(CIDRE_LISTE_CHAUDE|CIDRE_BASE_PIPELINES|CIDRE_COMPILE_FOND|MESA_SHADER_CACHE_DIR)=' "$T/env-rejeu.txt")"
verif "rejeu : options du jeu reprises (valeur a espace comprise)" "CIDRE_AIR_DIRECT=1|CIDRE_ILOT_EXE=Diablo IV.exe" "$(grep -E '^(CIDRE_AIR_DIRECT|CIDRE_ILOT_EXE)=' "$T/env-rejeu.txt" | tr '\n' '|' | sed 's/|$//')"
verif "rejeu : fils = CIDRE_PREPARATION_FILS ou coeurs, pas ceux du jeu" "$(sysctl -n hw.ncpu)" "$(sed -n 's/^CIDRE_COMPILE_DIFFEREE=//p' "$T/env-rejeu.txt")"
verif "rejeu : lots de 50 au moins" "50" "$(sed -n 's/^CIDRE_REJEU_LOT=//p' "$T/env-rejeu.txt")"
verif "base filtree : seulement les 10 lies" 320 "$(stat -f %z "$T/cles-rejeu")"
verif "travail et verrou nettoyes" "" "$(ls "$C/preparation" | grep -E '^travail|^verrou')"

verif "relance : chaude" chaude "$(sh "$P" etat $ID | champ etat)"
S=$(sh "$P" preparer $ID --json 2>&1)
verif "relance : aucun evenement, rien a dire" "" "$S"
t0=$(date +%s)
i=0; while [ $i -lt 5 ]; do sh "$P" preparer $ID --json >/dev/null 2>&1; i=$((i + 1)); done
verif "cout nul si chaud : 5 relances en moins de 3 s" oui "$( [ $(( $(date +%s) - t0 )) -lt 3 ] && echo oui || echo non)"

# Partie : deux pipelines de plus lies (11, 12), notes a la sortie par le lanceur
DEB=$(sh "$P" debut $ID)
chaude "$(cle 11 V)" "$(cle 12 F)" >>"$C/liste-chaude-kk.bin"
verif "noter : cles liees pendant la partie" "preparation des shaders : 2 pipelines lies pendant la partie, notes faits (1-0123456789abcdef-apple7-25A100)" "$(sh "$P" noter $ID "$DEB")"
verif "apres la partie : chaude (rien a recompiler)" chaude "$(sh "$P" etat $ID | champ etat)"

# Mise a jour de KosmicKrisp : nouvelle cle de code -> tout ce qui a ete lie est a refaire
export CIDRE_KK_DYLIB=$(pilote fedcba9876543210 CIDRE_REJEU_JOURNAL)
verif "nouvelle cle KK : 12 a preparer" "a_preparer 12" "$(sh "$P" etat $ID | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"
S=$(FAUX_ECHEC=3 sh "$P" preparer $ID --json 2>/dev/null | tail -1)
verif "un echec : 11 faits sur 12, 1 echec" '"finie",11,12,1' "$(printf '%s\n' "$S" | sed -E 's/.*"etat":("[a-z]+"),"fait":([0-9]+),"total":([0-9]+),"echecs":([0-9]+).*/\1,\2,\3,\4/')"
verif "l'echec n'est pas retente : chaude" chaude "$(sh "$P" etat $ID | champ etat)"
verif "l'ancienne identite garde son journal" 384 "$(stat -f %z "$J")"

# macOS mis a jour : le compilateur Metal change
verif "nouveau build de macOS : a preparer" a_preparer "$(CIDRE_PREPARATION_MACOS=25B1 sh "$P" etat $ID | champ etat)"

# Cache disque des nuanceurs vide : ce qui a ete fait est perdu
rm -rf "$C/mesa"
verif "cache disque vide : tout est a refaire" "a_preparer 12" "$(sh "$P" etat $ID | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"

# Passer : la preparation s'arrete, ce qui est fait reste fait
FAUX_PAUSE=0.4 sh "$P" preparer $ID --json >"$T/passer.out" 2>/dev/null &
PP=$!
sleep 2
sh "$P" passer $ID
wait $PP; rc=$?
verif "passer : code 0 (le jeu part)" 0 $rc
verif "passer : evenement passee" '"passee"' "$(tail -1 "$T/passer.out" | sed -E 's/.*"etat":("[a-z]+").*/\1/')"
f=$(tail -1 "$T/passer.out" | sed -E 's/.*"fait":([0-9]+).*/\1/')
verif "passer : en partie fait (0 < fait < 12)" oui "$( [ "$f" -gt 0 ] && [ "$f" -lt 12 ] && echo oui || echo non)"
sleep 0.5
verif "passer : le rejeu ne survit pas" non "$(kill -0 "$(cat "$T/pid-rejeu")" 2>/dev/null && echo oui || echo non)"
verif "passer : verrou et drapeau nettoyes" "" "$(ls "$C/preparation" | grep -E '^travail|^verrou')"
verif "passer : le reste est encore a faire" "a_preparer $((12 - f))" "$(sh "$P" etat $ID | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"

# cidre play arrete (Verger annule) : la preparation et le rejeu s'arretent avec lui
sh -c "FAUX_PAUSE=0.4 sh '$P' preparer $ID --json >'$T/parent.out' 2>/dev/null & sleep 1.5"
sleep 1.5
verif "parent disparu : le rejeu ne survit pas" non "$(kill -0 "$(cat "$T/pid-rejeu")" 2>/dev/null && echo oui || echo non)"
verif "parent disparu : verrou nettoye" "" "$(ls "$C/preparation" | grep -E '^travail|^verrou')"

# Mode « tout » : toute la base, pipelines jamais lies compris (zones jamais visitees)
ID4=999004; C4="$CIDRE_DIR/vkd3d-cache/$ID4"
base "$C4/base-pipelines" 20; mkdir -p "$C4/mesa"
verif "tout : sans liste chaude, toute la base a preparer" "a_preparer tout 20 20" \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID4 | champ 'etat|mode|a_faire|connus' | tr '\n' ' ' | sed 's/ $//')"
verif "lies (defaut) : sans liste chaude, inactive" "lies sans_liste" "$(sh "$P" etat $ID4 | champ 'raison|mode' | tr '\n' ' ' | sed 's/ $//')"
chaude "$(cle 1 V)" "$(cle 2 F)" "$(cle 3 V)" >"$C4/liste-chaude-kk.bin"
verif "lies : 3 sur 20" "a_preparer 3" "$(sh "$P" etat $ID4 | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"
verif "CIDRE_PREPARATION_SHADERS=1 garde le mode de la fiche (lies)" "lies 3" "$(CIDRE_PREPARATION_SHADERS=1 sh "$P" etat $ID4 | champ 'mode|a_faire' | tr '\n' ' ' | sed 's/ $//')"
S=$(CIDRE_PREPARATION_SHADERS=tout sh "$P" preparer $ID4 --json 2>/dev/null)
verif "tout : evenement debut sur toute la base" '{"evenement":"preparation","etat":"debut","fait":0,"total":20}' "$(printf '%s\n' "$S" | sed -n 1p)"
verif "tout : finie 20 / 20" '"finie",20,20,0' "$(printf '%s\n' "$S" | tail -1 | sed -E 's/.*"etat":("[a-z]+"),"fait":([0-9]+),"total":([0-9]+),"echecs":([0-9]+).*/\1,\2,\3,\4/')"
verif "tout : base filtree = toute la base" 640 "$(stat -f %z "$T/cles-rejeu")"
verif "tout : lots de 50 au moins (une dizaine pour une grosse base)" "50" "$(sed -n 's/^CIDRE_REJEU_LOT=//p' "$T/env-rejeu.txt")"
verif "tout : mode au journal de la preparation" 1 "$(grep -c 'preparation (tout) de 999004 : 20 pipelines' "$C4/preparation/journal.txt")"
verif "tout : relance chaude" chaude "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID4 | champ etat)"
verif "apres tout : lies chaude aussi" chaude "$(sh "$P" etat $ID4 | champ etat)"
verif "tout : relance sans evenement" "" "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" preparer $ID4 --json 2>&1)"
printf 'KKP1\110\000\000\000%s%sETAT%04d' "$(cle 21 V)" "$(cle 21 F)" 21 >>"$C4/base-pipelines/pipelines.bin"
verif "tout : un pipeline cree de plus (jamais lie) est a preparer" "a_preparer 1 21" \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID4 | champ 'etat|a_faire|connus' | tr '\n' ' ' | sed 's/ $//')"
verif "lies : ce pipeline-la n'est pas a preparer" chaude "$(sh "$P" etat $ID4 | champ etat)"
verif "rejeu : cache disque Mesa borne a 4 Gio (1 Gio par defaut : evictions)" "MESA_SHADER_CACHE_MAX_SIZE=4G" "$(grep '^MESA_SHADER_CACHE_MAX_SIZE=' "$T/env-rejeu.txt")"
: >"$C4/kk_pipelines.1.0.mtl4archive"
verif "pilote sans index (avant 0496) : archives sans index laissees" "chaude 1" \
   "$(sh "$P" etat $ID4 | champ etat) $(ls "$C4" | grep -c '^kk_pipelines.*mtl4archive$')"

# Index des archives (0496) : une fois par identite, les archives sans index sont mises de cote et la preparation refaite
ID5=999005; C5="$CIDRE_DIR/vkd3d-cache/$ID5"
base "$C5/base-pipelines" 6; mkdir -p "$C5/mesa"
KK0=$CIDRE_KK_DYLIB
export CIDRE_KK_DYLIB=$(pilote 0496049604960496 'CIDRE_REJEU_JOURNAL kk-index 1 msl=')
verif "0496 : premiere preparation (tout)" '"finie",6,6,0' \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" preparer $ID5 --json 2>/dev/null | tail -1 | sed -E 's/.*"etat":("[a-z]+"),"fait":([0-9]+),"total":([0-9]+),"echecs":([0-9]+).*/\1,\2,\3,\4/')"
J5="$C5/rejoues-prep-1-0496049604960496-apple7-25A100.bin"
verif "0496 : marque une fois par identite" 1 "$(ls "$C5/preparation" | grep -c '^index-1-0496049604960496-apple7-25A100$')"
verif "0496 : chaude" chaude "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID5 | champ etat)"
# un cache d'avant 0496 : deux archives sans index, une indexee, le journal d'une preparation complete
rm -f "$C5/preparation/index-1-0496049604960496-apple7-25A100" "$C5/preparation/chaud"
: >"$C5/kk_pipelines.7.0.mtl4archive"; : >"$C5/kk_pipelines.7.1.mtl4archive"
: >"$C5/kk_pipelines.8.0.mtl4archive"; echo 'kk-index 1 msl=0' >"$C5/kk_pipelines.8.0.mtl4archive.index"
verif "0496 : archives sans index -> tout est a refaire" "a_preparer 6" \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID5 | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"
verif "0496 : archives sans index mises de cote, l'indexee reste" "2 kk_pipelines.8.0.mtl4archive" \
   "$(ls "$C5/archives-sans-index" | grep -c mtl4archive) $(ls "$C5" | grep 'mtl4archive$' | tr '\n' ' ' | sed 's/ $//')"
verif "0496 : journal d'avant mis de cote" "192" "$(stat -f %z "$J5.sans-index" 2>/dev/null)"
verif "0496 : relance de l'etat : rien de plus deplace" "a_preparer 6" \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID5 | champ 'etat|a_faire' | tr '\n' ' ' | sed 's/ $//')"
verif "0496 : preparation refaite" '"finie",6,6,0' \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" preparer $ID5 --json 2>/dev/null | tail -1 | sed -E 's/.*"etat":("[a-z]+"),"fait":([0-9]+),"total":([0-9]+),"echecs":([0-9]+).*/\1,\2,\3,\4/')"
verif "0496 : finie : archives mises de cote et vieux journal effaces" "non non" \
   "$( [ -e "$C5/archives-sans-index" ] && echo oui || echo non) $( [ -e "$J5.sans-index" ] && echo oui || echo non)"
: >"$C5/kk_pipelines.9.0.mtl4archive"
verif "0496 : une archive sans index plus tard (fait une fois) : laissee, chaude" "chaude oui" \
   "$(CIDRE_PREPARATION_SHADERS=tout sh "$P" etat $ID5 | champ etat) $( [ -f "$C5/kk_pipelines.9.0.mtl4archive" ] && echo oui || echo non)"
export CIDRE_KK_DYLIB=$KK0

# Adoption : un jeu dont les shaders sont deja en cache (etat_shaders) n'est pas recompile a la premiere rencontre
ID2=999002; C2="$CIDRE_DIR/vkd3d-cache/$ID2"
base "$C2/base-pipelines" 5; mkdir -p "$C2/mesa"
chaude "$(cle 1 V)" "$(cle 2 V)" >"$C2/liste-chaude-kk.bin"
sh "$B/tests/etat_shaders.sh" noter $ID2 "$(sh "$B/tests/etat_shaders.sh" voie $ID2)" $(( $(date +%s) - 600 )) >/dev/null 2>&1
verif "shaders en cache : liste adoptee, chaude" chaude "$(sh "$P" etat $ID2 | champ etat)"
verif "adoption notee" adoptee "$(cut -d' ' -f2 "$C2/preparation/adoption")"

# cidre play --json : la preparation passe avant le lancement, ses evenements sur la sortie standard
export HOME="$T/home" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/profils-base" CIDRE_LANCEUR="$T/lanceur.sh" \
       CIDRE_MAJ_AVANT_LANCEMENT=0 CIDRE_SANS_STEAM=1 CIDRE_PROTONDB_URL="file://$T/rien/"
mkdir -p "$HOME" "$CIDRE_DIR/games/9020/steamapps"
printf '#!/bin/sh\necho "lance $*"\necho "${MESA_SHADER_CACHE_MAX_SIZE:-}" >"%s/borne-jeu"\n' "$T" >"$T/lanceur.sh"; chmod +x "$T/lanceur.sh"
printf 'MZ\n' >"$CIDRE_DIR/games/9020/Jeu.exe"
printf '"AppState"\n{\n\t"appid"\t\t"9020"\n\t"name"\t\t"Jeu 9020"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"1000"\n\t"buildid"\t\t"100"\n}\n' \
   >"$CIDRE_DIR/games/9020/steamapps/appmanifest_9020.acf"
C3="$CIDRE_DIR/vkd3d-cache/9020"; base "$C3/base-pipelines" 4
chaude "$(cle 1 V)" "$(cle 3 F)" >"$C3/liste-chaude-kk.bin"
verif "cidre preparation etat --json" '{"etat":"a_preparer","mode":"lies","raison":null,"a_faire":2,"connus":2,"identite":"1-fedcba9876543210-apple7-25A100"}' \
   "$(sh "$B/cidre" preparation 9020 etat --json 2>/dev/null)"
sh "$B/cidre" play 9020 --json --sans-maj >"$T/evts" 2>"$T/err"
verif "cidre play --json : shaders, preparation debut puis finie, lancement" "shaders preparation:debut preparation:finie lancement" \
   "$(sed -E 's/^\{"evenement":"([a-z]+)"(,"etat":"([a-z_]+)")?.*/\1:\3/; s/^shaders:.*/shaders/; s/^lancement:$/lancement/' "$T/evts" | grep -v ':en_cours' | tr '\n' ' ' | sed 's/ $//')"
verif "cidre play --json : rien que du JSON sur la sortie" 0 "$(grep -vc '^{.*}$' "$T/evts")"
verif "cidre play : le jeu part apres la preparation" 1 "$(grep -c '^lance ' "$T/err")"
verif "cidre play : cache disque Mesa du jeu borne a 4 Gio" 4G "$(cat "$T/borne-jeu" 2>/dev/null)"
sh "$B/cidre" play 9020 --json --sans-maj >"$T/evts2" 2>/dev/null
verif "cidre play suivant : aucun evenement de preparation" 0 "$(grep -c '"evenement":"preparation"' "$T/evts2")"
verif "cidre help : preparation documentee" 3 "$(sh "$B/cidre" help 2>/dev/null | grep -c '^  cidre preparation <id>')"
verif "cidre set : option preparation_shaders reconnue" 0 "$(sh "$B/cidre" set 9020 preparation_shaders false >/dev/null 2>&1; echo $?)"
verif "option coupee par cidre set : inactive" option "$(sh "$P" etat 9020 | champ raison)"
verif "cidre set preparation_shaders tout" 0 "$(sh "$B/cidre" set 9020 preparation_shaders tout >/dev/null 2>&1; echo $?)"
verif "fiche a tout : toute la base (2 faits, 2 jamais lies)" "a_preparer tout 2 4" \
   "$(sh "$P" etat 9020 | champ 'etat|mode|a_faire|connus' | tr '\n' ' ' | sed 's/ $//')"
verif "cidre set preparation_shaders : valeur refusee" 2 "$(sh "$B/cidre" set 9020 preparation_shaders tous >/dev/null 2>&1; echo $?)"
verif "CIDRE_PREPARATION_SHADERS=lies l'emporte sur la fiche" "chaude lies" "$(CIDRE_PREPARATION_SHADERS=lies sh "$P" etat 9020 | champ 'mode|etat' | tr '\n' ' ' | sed 's/ $//')"

pkill -f "$FAUX" 2>/dev/null
rm -rf "${T:?}"
echo "$((ok + ko)) verifications, $ko en echec"
[ $ko -eq 0 ]
