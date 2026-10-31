#!/bin/sh
# Teste le lancement d'un jeu du dossier Cidre d'apres la configuration de
# lancement de Steam (appinfo config/launch), et la voie D3D9 64 bits :
#   1. cidre-outil lancement, sur un faux cache du client (appinfo.vdf v28) :
#      OS, architecture (paire 32/64), branche (betakey, « default »), type
#      (default/none avant option<n>, jamais server), ownsdlc, --exe impose,
#      arguments decoupes comme Windows, --toutes ; codes 3 et 4 ;
#   2. le meme, sur la sortie texte de SteamCMD (le cache de `cidre`) ;
#   3. cidre play, un faux lanceur qui note ce qu'on lui donne : Portal
#      (-game portal, dossier de travail bin, arguments de Steam devant ceux de
#      la ligne de commande), une branche, Jedi Academy (sous-dossier),
#      Civilization IV BtS (casse), Civilization V (option1 ; la fiche impose
#      l'exe DX11), une fiche qui retire les arguments de Steam, un exe de
#      fiche que Steam ne lance pas, un jeu absent des caches, un exe de Steam
#      absent du disque ;
#   4. le lanceur : dossier de travail, dependances nommees au journal ;
#   5. le bloc D3D9 du lanceur, sur un prefixe de test (fichiers factices) :
#      un exe 64 bits dont la fiche dit d3d9 recoit le d3d9 arm64ec de DXVK
#      en system32 (d3d9=n), un autre garde wined3d, sans DLL de DXVK : wined3d
#      dit, l'i386 inchange.
# Rien n'est lance ni lu hors d'un dossier temporaire (HOME, CIDRE_DIR,
# prefixe et runtime factices).
#   sh tests/tester_lancement_steam.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-lancement.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}

if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then
   sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1 || { echo "cidre-outil : construction impossible" >&2; exit 1; }
fi
O="$R/build/cidre-outil"

export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/base" \
   CIDRE_PROFILS_PROVISOIRES="$T/provisoires" CIDRE_STEAMCMD="$T/pas-de-steamcmd" CIDRE_SANS_STEAM=1 \
   CIDRE_LANCEUR="$T/lanceur.sh" CIDRE_MAJ_AVANT_LANCEMENT=0 CIDRE_PROTONDB_URL="file://$T/nulle-part/"
unset CIDRE_DOSSIER_TRAVAIL CIDRE_ARGUMENTS CIDRE_D3D9 CIDRE_DXVK64_DIR CIDRE_DXVK32_DIR 2>/dev/null
mkdir -p "$HOME" "$CIDRE_DIR/games" "$CIDRE_DIR/cache" "$CIDRE_PROFILS_BASE" "$CIDRE_PROFILS_PROVISOIRES" "$T/bin"
printf '#!/bin/sh\necho "open $*" >>"%s/open.txt"\n' "$T" >"$T/bin/open"; chmod +x "$T/bin/open"
PATH="$T/bin:$PATH"; export PATH
TAB=$(printf '\t')

# --- un faux appinfo.vdf du client (v28, cles en ligne) ----------------------
octets() { for o in "$@"; do printf "\\$(printf %03o "$o")"; done; }
zeros() { i=0; while [ $i -lt "$1" ]; do octets 0; i=$((i + 1)); done; }
le32() { octets $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)); }
ch() { octets 1; printf '%s\000%s\000' "$1" "$2"; }   # <cle> <chaine>
di() { octets 0; printf '%s\000' "$1"; }                # <cle> : ouvre un dictionnaire
fin() { octets 8; }
# entree <n> <type> <oslist> <osarch> <betakey> <exe> <arguments> <workingdir> [ownsdlc]
entree() {
   di "$1"
   ch executable "$6"
   [ -z "$7" ] || ch arguments "$7"
   [ -z "$8" ] || ch workingdir "$8"
   [ -z "$2" ] || ch type "$2"
   di config
   [ -z "$3" ] || ch oslist "$3"
   [ -z "$4" ] || ch osarch "$4"
   [ -z "$5" ] || ch betakey "$5"
   [ -z "${9:-}" ] || ch ownsdlc "$9"
   fin
   fin
}
# fiche_client <appid> <nom> <fonction qui ecrit les entrees>
fiche_client() {
   { di appinfo
       octets 2; printf 'appid\000'; le32 "$1"
       di common; ch name "$2"; ch type Game; ch oslist windows; fin
       di config; ch installdir "$2"; di launch; "$3"; fin; fin
     fin
     fin
   } >"$T/corps"
   le32 "$1"; le32 $((60 + $(wc -c <"$T/corps")))
   le32 2; le32 1791900000; zeros 8; zeros 20; le32 42; zeros 20
   cat "$T/corps"
}
l_portal() {
   entree 0 "" windows "" "" hl2.exe "-game portal -steam" bin
   entree 1 "" macos "" "" hl2.sh "-game portal -steam" ""
   entree 3 option1 windows "" "" 'PortalRTX\hl2.exe' "-game portal_rtx -steam" ""
}
l_hl2() {
   entree 0 "" windows "" default hl2.exe "-steam -game hl2_complete" bin
   entree 1 "" macos "" "" hl2.sh "-game hl2 -steam" ""
   entree 3 "" windows "" steam_legacy hl2.exe "-steam -game hl2" bin
}
l_jka() {
   entree 0 "" windows "" "" 'GameData\jasp.exe' "" GameData
   entree 1 "" windows "" "" 'GameData\jamp.exe' "" GameData
   entree 2 "" macos "" "" SWJKJA.app "" ""
}
l_civ4() { entree 0 "" windows "" "" 'beyond the sword\Civ4BeyondSword.exe' "" ""; }
l_civ5() {
   entree 0 default windows "" legacy Launcher.exe "" ""
   entree 1 "" macos "" "" "Civilization V.app" "" ""
   entree 5 option1 windows 64 "" CivilizationV.exe "" ""
   entree 6 option2 windows 64 "" CivilizationV_DX11.exe "" ""
   entree 7 option3 windows 64 "" CivilizationV_Tablet.exe "" ""
}
l_paire() {
   entree 0 "" windows 32 "" a32.exe "" ""
   entree 3 "" windows 64 "" a64.exe "" ""
}
l_divers() {
   entree 0 default windows "" "" dlc.exe "" "" 123
   entree 1 server windows "" "" srv.exe "" ""
   entree 2 none "" "" "" jeu.exe '-x "a b" -eac_dir "..\\E\\" -q' ""
}
l_serveur() { entree 0 server windows "" "" srv.exe "" ""; }
l_absent() { entree 0 "" windows "" "" Absent.exe "-steam" ""; }
AI="$HOME/Library/Application Support/Steam/appcache/appinfo.vdf"
mkdir -p "$(dirname "$AI")"
{ le32 $((0x07564428)); le32 1
  fiche_client 950400 Portal l_portal
  fiche_client 950220 HL2 l_hl2
  fiche_client 956020 JKA l_jka
  fiche_client 958800 Civ4 l_civ4
  fiche_client 958930 Civ5 l_civ5
  fiche_client 950320 Paire l_paire
  fiche_client 950555 Divers l_divers
  fiche_client 950556 Serveur l_serveur
  fiche_client 950557 Absent l_absent
  le32 0; } >"$AI"

echo "== 1. cidre-outil lancement (cache du client)"
L() { "$O" lancement "$AI" "$@"; }
champ() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
args() { printf '%s\n' "$1" | sed -n 's/^arg=//p' | tr '\n' '|'; }
s=$(L 950400); verif "Portal : entree 0" "0" "$(champ "$s" entree)"
verif "Portal : exe" "hl2.exe" "$(champ "$s" exe)"
verif "Portal : dossier de travail" "bin" "$(champ "$s" dossier)"
verif "Portal : type (sans type = default)" "default" "$(champ "$s" type)"
verif "Portal : arguments" "-game|portal|-steam|" "$(args "$s")"
s=$(L 950220); verif "HL2, branche publique : betakey default retenue" "0|-steam|-game|hl2_complete|" "$(champ "$s" entree)|$(args "$s")"
s=$(L 950220 --branche public); verif "HL2, --branche public : idem" "0" "$(champ "$s" entree)"
s=$(L 950220 --branche steam_legacy); verif "HL2, branche steam_legacy : son entree" "3|-steam|-game|hl2|" "$(champ "$s" entree)|$(args "$s")"
s=$(L 956020); verif "Jedi Academy : jasp (la premiere), sous-dossier" 'GameData\jasp.exe|GameData' "$(champ "$s" exe)|$(champ "$s" dossier)"
s=$(L 958930); verif "Civ V : legacy (autre branche) ecartee, option1" "5|option1|CivilizationV.exe" "$(champ "$s" entree)|$(champ "$s" type)|$(champ "$s" exe)"
s=$(L 958930 --exe CivilizationV_DX11.exe); verif "Civ V --exe DX11 : option2" "6|CivilizationV_DX11.exe" "$(champ "$s" entree)|$(champ "$s" exe)"
s=$(L 958930 --exe './civilizationv_dx11.EXE'); verif "Civ V --exe : casse et ./ ignores" "6" "$(champ "$s" entree)"
s=$(L 958930 --exe Autre.exe); rc=$?; verif "Civ V --exe que Steam ne lance pas : aucune entree (4)" "4|" "$rc|$s"
s=$(L 958930 --branche legacy); verif "Civ V, branche legacy : son lancement par defaut" "0|Launcher.exe" "$(champ "$s" entree)|$(champ "$s" exe)"
s=$(L 950320); verif "paire 32/64 : le 64" "a64.exe" "$(champ "$s" exe)"
s=$(L 950320 --arch 32); verif "paire 32/64, --arch 32 : le 32" "a32.exe" "$(champ "$s" exe)"
s=$(L 950555); verif "ownsdlc et server ecartes, none retenu" "2|jeu.exe" "$(champ "$s" entree)|$(champ "$s" exe)"
# (deux barres inverses sans guillemet derriere restent deux ; suivies d'un guillemet, une)
verif "arguments decoupes comme Windows (guillemets, barres inverses)" '-x|a b|-eac_dir|..\\E\|-q|' "$(args "$s")"
s=$(L 950555 --os macos); verif "--os macos : l'entree sans oslist vaut pour tous" "2" "$(champ "$s" entree)"
s=$(L 958930 --os linux); rc=$?; verif "--os linux, aucune entree pour lui : 4" "4" "$rc"
L 950556 >/dev/null; verif "server seul : aucune entree (4)" "4" "$?"
L 999999 >/dev/null; verif "jeu absent du cache : code 3" "3" "$?"
t=$(L 958930 --toutes)
verif "--toutes : une ligne par entree" "5" "$(printf '%s\n' "$t" | wc -l | tr -d ' ')"
verif "--toutes : la choisie" "choisie${TAB}5" "$(printf '%s\n' "$t" | grep '^choisie' | cut -f1,2)"
verif "--toutes : ecartees et possibles" "ecartee ecartee choisie possible possible" "$(printf '%s\n' "$t" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
"$O" lancement "$AI" >/dev/null 2>&1; verif "usage : code 2" "2" "$?"

echo "== 2. cidre-outil lancement (sortie texte de SteamCMD)"
TX="$CIDRE_DIR/cache/appinfo.txt"
cat >"$TX" <<'TEXTE'
Connecting anonymously to Steam Public...OK
AppID : 958931, change number : 1/1, last change : Tue Oct 13 12:00:00 2026
"958931"
{
	"common"
	{
		"name"		"Texte"
	}
	"config"
	{
		"launch"
		{
			"0"
			{
				"executable"		"bin\\linux.sh"
				"config"
				{
					"oslist"		"linux"
				}
			}
			"1"
			{
				"executable"		"Bin\\Jeu.exe"
				"arguments"		"-a \"b c\""
				"workingdir"		"Bin"
				"type"		"default"
				"config"
				{
					"oslist"		"windows"
				}
			}
		}
	}
}
AppID : 958932, change number : 1/1, last change : Tue Oct 13 12:00:00 2026
"958932"
{
	"common"
	{
		"name"		"Sans lancement"
	}
}
TEXTE
s=$("$O" lancement "$TX" 958931); verif "texte : l'entree Windows" '1|Bin\Jeu.exe|Bin' "$(champ "$s" entree)|$(champ "$s" exe)|$(champ "$s" dossier)"
verif "texte : echappements rendus, arguments decoupes" '-a|b c|' "$(args "$s")"
"$O" lancement "$TX" 958932 >/dev/null; verif "texte : sans config/launch, code 4" "4" "$?"
"$O" lancement "$TX" 958933 >/dev/null; verif "texte : jeu absent, code 3" "3" "$?"

echo "== 3. cidre play (jeux du dossier Cidre, faux lanceur)"
G="$CIDRE_DIR/games"
cat >"$T/lanceur.sh" <<'LANCEUR'
#!/bin/sh
F=$(dirname "$0")
{ echo "exe=$1"; shift; for a in "$@"; do echo "arg=$a"; done
  echo "travail=${CIDRE_DOSSIER_TRAVAIL:-}"; } >"$F/lance"
LANCEUR
chmod +x "$T/lanceur.sh"
jeu() { # <appid> <exe relatif> [autres exe relatifs...]
   a=$1; shift
   mkdir -p "$G/$a/steamapps"
   printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Jeu %s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"buildid"\t\t"1"\n}\n' "$a" "$a" >"$G/$a/steamapps/appmanifest_$a.acf"
   for e in "$@"; do mkdir -p "$(dirname "$G/$a/$e")"; printf 'MZ\n' >"$G/$a/$e"; done
}
P() { : >"$T/lance"; sh "$R/cidre" play "$@" >"$T/sortie" 2>&1; }
exe_lance() { sed -n 's/^exe=//p' "$T/lance"; }
args_lances() { sed -n 's/^arg=//p' "$T/lance" | tr '\n' '|'; }
travail() { sed -n 's/^travail=//p' "$T/lance"; }
jeu 950400 hl2.exe bin/launcher.dll PortalRTX/hl2.exe
P 950400 -- +map testchmb_a_00
verif "Portal : hl2.exe de la racine" "$G/950400/hl2.exe" "$(exe_lance)"
verif "Portal : arguments de Steam, puis ceux de la ligne de commande" "-game|portal|-steam|+map|testchmb_a_00|" "$(args_lances)"
verif "Portal : dossier de travail bin" "$G/950400/bin" "$(travail)"
contient "Portal : la sortie dit l'entree" "lancement Steam : entree 0, default, hl2.exe -game portal -steam, dossier de travail bin" "$(cat "$T/sortie")"
jeu 950220 hl2.exe bin/x.dll
P 950220; verif "HL2 : -game hl2_complete" "-steam|-game|hl2_complete|" "$(args_lances)"
printf '"AppState"\n{\n\t"appid"\t\t"950220"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"UserConfig"\n\t{\n\t\t"BetaKey"\t\t"steam_legacy"\n\t}\n}\n' >"$G/950220/steamapps/appmanifest_950220.acf"
P 950220; verif "HL2 sur la branche steam_legacy : son entree" "-steam|-game|hl2|" "$(args_lances)"
jeu 956020 GameData/jamp.exe GameData/jasp.exe Launcher.exe
P 956020
verif "Jedi Academy : GameData/jasp.exe" "$G/956020/GameData/jasp.exe" "$(exe_lance)"
verif "Jedi Academy : dossier de travail = celui de l'exe, rien a passer" "" "$(travail)"
jeu 958800 "Beyond the Sword/Civ4BeyondSword.exe" "Warlords/Civ4Warlords.exe" Civ4.exe
P 958800
e=$(exe_lance)
case $e in "$G/958800/Beyond the Sword/Civ4BeyondSword.exe") ok "Civ IV BtS : l exe de Steam, au nom du disque (Beyond the Sword)" ;; *) echec "Civ IV BtS : $e" ;; esac
[ -f "$e" ] && ok "Civ IV BtS : le chemin donne existe" || echec "Civ IV BtS : $e n'existe pas"
jeu 958930 Launcher.exe CivilizationV.exe CivilizationV_DX11.exe CivilizationV_Tablet.exe
P 958930; verif "Civ V sans fiche : option1 (DX9), comme la fenetre de choix" "$G/958930/CivilizationV.exe" "$(exe_lance)"
printf '[jeu]\nappid = 958930\nnom = "Civ5"\nexe = "CivilizationV_DX11.exe"\n' >"$CIDRE_PROFILS_BASE/958930.toml"
P 958930; verif "Civ V, fiche exe DX11 : l'exe de la fiche" "$G/958930/CivilizationV_DX11.exe" "$(exe_lance)"
contient "Civ V, fiche exe DX11 : l'entree option2" "entree 6, option2" "$(cat "$T/sortie")"
printf '[jeu]\nappid = 950400\nnom = "Portal"\narguments_steam = false\n' >"$CIDRE_PROFILS_BASE/950400.toml"
P 950400 -- -novid; verif "fiche arguments_steam = false : seuls ceux de la ligne de commande" "-novid|" "$(args_lances)"
verif "fiche arguments_steam = false : le dossier de travail reste" "$G/950400/bin" "$(travail)"
printf '[jeu]\nappid = 950400\nnom = "Portal"\nexe = "PortalRTX/hl2.exe"\n' >"$CIDRE_PROFILS_BASE/950400.toml"
P 950400; verif "fiche exe = celui d'une option : ses arguments" "$G/950400/PortalRTX/hl2.exe|-game|portal_rtx|-steam|" "$(exe_lance)|$(args_lances)"
mkdir -p "$G/950400/Autre"; printf 'MZ\n' >"$G/950400/Autre/x.exe"
printf '[jeu]\nappid = 950400\nnom = "Portal"\nexe = "Autre/x.exe"\n' >"$CIDRE_PROFILS_BASE/950400.toml"
P 950400; verif "fiche exe que Steam ne lance pas : sans arguments ni dossier de Steam" "$G/950400/Autre/x.exe||" "$(exe_lance)|$(args_lances)|$(travail)"
printf '[jeu]\nappid = 950400\nnom = "Portal"\nexe = "Absent/x.exe"\n' >"$CIDRE_PROFILS_BASE/950400.toml"
P 950400; verif "fiche exe absent du disque : l'entree de Steam" "$G/950400/hl2.exe|-game|portal|-steam|" "$(exe_lance)|$(args_lances)"
rm -f "$CIDRE_PROFILS_BASE/950400.toml"
jeu 950999 Jeu.exe
P 950999; verif "jeu absent des caches : l'exe de la racine, sans arguments" "$G/950999/Jeu.exe|" "$(exe_lance)|$(args_lances)"
jeu 950557 Autre.exe
P 950557; verif "exe de Steam absent du disque : l'exe de la racine, sans arguments" "$G/950557/Autre.exe||" "$(exe_lance)|$(args_lances)|$(travail)"

echo "== 4. le lanceur"
LS="$R/tests/lancer_depuis_steam.sh"
sh -n "$LS" && ok "lanceur : syntaxe" || echec "lanceur : syntaxe"
grep -q 'cd "$CIDRE_DOSSIER_TRAVAIL"' "$LS" && grep -q 'etape2_pile_arm64ec.sh" "$LANCE"' "$LS" \
   && ok "lanceur : dossier de travail de Steam, exe par son chemin complet" || echec "lanceur : dossier de travail non pris"
grep -q 'unset CIDRE_DOSSIER_TRAVAIL' "$LS" && ok "lanceur : la table des lanceurs annule le dossier de travail" || echec "lanceur : table et dossier de travail"
grep -q 'DEPS=$(profil dependances)' "$LS" && grep -q 'dependances notees par la fiche, NON posees' "$LS" \
   && ok "lanceur : dependances nommees au journal" || echec "lanceur : dependances muettes"
sh -n "$R/cidre" && ok "cidre : syntaxe" || echec "cidre : syntaxe"

echo "== 5. le bloc D3D9 du lanceur (prefixe de test)"
sed -n '/^est_pe32() {/,/^}/p' "$LS" >"$T/d3d9.sh"
sed -n '/^# --- d3d9 : debut ---$/,/^# --- d3d9 : fin ---$/p' "$LS" >>"$T/d3d9.sh"
grep -q 'D3D9_OV=' "$T/d3d9.sh" && ok "bloc d3d9 extrait" || echec "bloc d3d9 introuvable (marqueurs)"
# des PE factices : en-tete MZ, e_lfanew = 64, Machine i386 ou x86-64
pe() { # <0x014c|0x8664> <texte>
   printf 'MZ'; zeros 58; octets 64 0 0 0; printf 'PE\000\000'
   [ "$1" = 0x014c ] && octets 0x4c 0x01 || octets 0x64 0x86; printf '%s' "$2"
}
RT="$T/runtime"; PX="$T/prefixe"
mkdir -p "$RT/dxvk/async" "$RT/dxvk/i386" "$T/jeu"
pe 0x8664 " dxvk d3d9 arm64ec" >"$RT/dxvk/async/d3d9.dll"
pe 0x014c " dxvk d3d9 i386" >"$RT/dxvk/i386/d3d9.dll"
pe 0x8664 " jeu 64" >"$T/jeu/jeu64.exe"; pe 0x014c " jeu 32" >"$T/jeu/jeu32.exe"
pfx() { rm -rf "$PX"; mkdir -p "$PX/system32" "$PX/syswow64"; pe 0x8664 " wine builtin" >"$PX/system32/d3d9.dll"; pe 0x014c " wine builtin" >"$PX/syswow64/d3d9.dll"; }
D9() { # <exe> <api de la fiche> [VAR=valeur...] : rend « d3d9 surcharge » et ecrit le journal
   d9_e=$1; d9_a=$2; shift 2
   : >"$T/journal"
   env "$@" R="$RT" SYS32="$PX/system32" SYSWOW="$PX/syswow64" JOURNAL="$T/journal" DOSSIER="$T/jeu" PROG="$d9_e" API="$d9_a" sh -c '
      opt() { eval "v=\${$2:-}"; [ -n "$v" ] && echo "$v"; }
      profil() { case $1 in api) echo "$API" ;; api_disponibles) echo "${API_DISPO:-}" ;; esac; }
      poser() { cmp -s "$1" "$2" || cp "$1" "$2"; }
      . "$0"; echo "$D3D9 $CIDRE_DLL_OVERRIDES"' "$T/d3d9.sh"
}
pfx; r=$(D9 jeu64.exe d3d9)
verif "64 bits, fiche d3d9 : dxvk, d3d9=n" "dxvk d3d9=n" "$r"
cmp -s "$RT/dxvk/async/d3d9.dll" "$PX/system32/d3d9.dll" && ok "64 bits : le d3d9 arm64ec de DXVK pose en system32" || echec "64 bits : system32/d3d9.dll pas pose"
contient "64 bits : dit au journal" "d3d9  : dxvk arm64ec pose depuis $RT/dxvk/async" "$(cat "$T/journal")"
grep -q "wine builtin" "$PX/syswow64/d3d9.dll" && ok "64 bits : syswow64 intact" || echec "64 bits : syswow64 touche"
r=$(D9 jeu64.exe d3d9); contient "64 bits, deja pose : toujours dxvk" "dxvk d3d9=n" "$r"
pfx; r=$(D9 jeu64.exe d3d11)
verif "64 bits, fiche d3d11 : wined3d, d3d9=b" "wined3d d3d9=b" "$r"
grep -q "wine builtin" "$PX/system32/d3d9.dll" && ok "64 bits d3d11 : system32 intact" || echec "64 bits d3d11 : system32 touche"
pfx; r=$(D9 jeu64.exe "" API_DISPO="d3d9 opengl"); verif "64 bits, sans api, api_disponibles d3d9 opengl : dxvk" "dxvk d3d9=n" "$r"
pfx; r=$(D9 jeu64.exe "" API_DISPO="d3d9 d3d11"); verif "64 bits, sans api, api_disponibles d3d9 d3d11 : wined3d" "wined3d d3d9=b" "$r"
pfx; r=$(D9 jeu64.exe opengl API_DISPO="d3d9 opengl"); verif "64 bits, api opengl : wined3d (api prime)" "wined3d d3d9=b" "$r"
pfx; r=$(D9 jeu64.exe ""); verif "64 bits, fiche muette : wined3d" "wined3d d3d9=b" "$r"
pfx; r=$(D9 jeu64.exe "" CIDRE_D3D9=dxvk); verif "64 bits, CIDRE_D3D9=dxvk sans fiche : dxvk" "dxvk d3d9=n" "$r"
pfx; r=$(D9 jeu64.exe d3d9 CIDRE_D3D9=wined3d); verif "64 bits, CIDRE_D3D9=wined3d : passe devant la fiche" "wined3d d3d9=b" "$r"
pfx; mv "$RT/dxvk/async/d3d9.dll" "$T/d3d9-64.dll"
r=$(D9 jeu64.exe d3d9); verif "64 bits sans d3d9 arm64ec de DXVK : wined3d" "wined3d d3d9=b" "$r"
contient "64 bits sans DLL : dit au journal" "pas de d3d9.dll arm64ec de DXVK" "$(cat "$T/journal")"
mkdir -p "$T/essai"; cp "$T/d3d9-64.dll" "$T/essai/d3d9.dll"
pfx; r=$(D9 jeu64.exe d3d9 CIDRE_DXVK64_DIR="$T/essai"); verif "CIDRE_DXVK64_DIR : pris" "dxvk d3d9=n" "$r"
contient "CIDRE_DXVK64_DIR : dit au journal" "pose depuis $T/essai" "$(cat "$T/journal")"
pfx; pe 0x8664 " un autre d3d9" >"$T/essai/d3d9.dll"
r=$(D9 jeu64.exe d3d9 CIDRE_DXVK64_DIR="$T/essai"); verif "un d3d9.dll qui n'est pas DXVK n'est pas pose" "wined3d d3d9=b" "$r"
mv "$T/d3d9-64.dll" "$RT/dxvk/async/d3d9.dll"
pfx; r=$(D9 jeu32.exe "")
verif "32 bits : dxvk i386, comme avant" "dxvk d3d9=n" "$r"
cmp -s "$RT/dxvk/i386/d3d9.dll" "$PX/syswow64/d3d9.dll" && grep -q "wine builtin" "$PX/system32/d3d9.dll" \
   && ok "32 bits : syswow64 pose, system32 intact" || echec "32 bits : mauvais dossier"
r=$(D9 jeu64.exe d3d9 CIDRE_DLL_OVERRIDES="d3d9=b"); verif "une surcharge d3d9 deja donnee reste" "dxvk d3d9=b" "$r"

echo
echo "$nb verifications, $ko echec(s)"
[ $ko -eq 0 ]
