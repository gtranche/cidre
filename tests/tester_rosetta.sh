#!/bin/sh
# Teste la bascule vers la version Windows d'un jeu dont la version macOS ne
# tourne pas sur ce Mac (cidre, mac_vers_windows) : 32 bits seulement, toujours ;
# Intel seulement (x86_64 sans arm64), quand Rosetta 2 est absente.
#   1. la detection de Rosetta (rosetta_etat) : CIDRE_ROSETTA l'impose ; le
#      moteur /Library/Apple/usr/libexec/oah/libRosettaRuntime present ou non
#      (CIDRE_ROSETTA_RUNTIME), macOS 28 et plus = partielle (CIDRE_MACOS_MAJEUR),
#      sans rien lancer ;
#   2. quatre jeux du client Steam installes en version macOS (faux Mach-O :
#      i386, x86_64, arm64, universel x86_64+arm64 ; plus un universel
#      i386+x86_64) : list (texte et --json), play, install, dl, avec Rosetta
#      presente (rien ne change), absente (le x86_64 seul bascule) et partielle ;
#   3. des jeux non installes, d'apres le cache du client Steam (faux
#      appinfo.vdf : osextended) et les fiches : install auto, et
#      cidre-outil bibliotheque --sans-rosetta (cidre library) ;
#   3b. [jeu] mac_arch : la fiche corrige les drapeaux de Steam (un universel
#      declare Intel), apres le binaire installe et avant mac_32bits.
# Rien n'est telecharge ni lance : HOME, CIDRE_DIR, le client Steam et `open`
# sont faux, et `cidre` tourne dans une copie du depot ou tests/cidre_install.sh
# (SteamCMD) ne fait que dire ce qu'on lui demande.
#   sh tests/tester_rosetta.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-rosetta.XXXXXX")
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
absent() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) echec "$1 : « $2 » present dans « $3 »" ;; *) ok "$1" ;; esac
}

# Le cidre-outil du depot, a jour
if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then
   sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1 || { echo "cidre-outil : construction impossible" >&2; exit 1; }
fi

# Une copie du depot : des liens, sauf cidre (copie : il prend sa racine dans
# son chemin), tests/cidre_install.sh (il dit sa plateforme, sans SteamCMD) et
# tests/fiche_profil.sh (pas de fiche provisoire : elle irait sur le reseau).
D=$T/depot
mkdir -p "$D/tests"
for f in "$R"/*; do
   case ${f##*/} in cidre|tests|tools) ;; *) ln -s "$f" "$D/${f##*/}" ;; esac
done
cp "$R/cidre" "$D/cidre"
for f in "$R"/tests/*; do ln -s "$f" "$D/tests/${f##*/}"; done
rm -f "$D/tests/cidre_install.sh" "$D/tests/fiche_profil.sh"
printf '#!/bin/sh\necho "cidre_install $*"\n' >"$D/tests/cidre_install.sh"
printf '#!/bin/sh\n[ "${1:-}" = provisoire ] && exit 0\nexec sh "%s/tests/fiche_profil.sh" "$@"\n' "$R" >"$D/tests/fiche_profil.sh"

export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/base" \
   CIDRE_PROFILS_PROVISOIRES="$T/provisoires" CIDRE_STEAMCMD="$T/pas-de-steamcmd" CIDRE_SANS_STEAM=1
mkdir -p "$HOME" "$CIDRE_DIR/games" "$CIDRE_PROFILS_BASE" "$CIDRE_PROFILS_PROVISOIRES" "$T/bin"
printf '#!/bin/sh\necho "open $*" >>"%s/open.txt"\n' "$T" >"$T/bin/open"; chmod +x "$T/bin/open"
PATH="$T/bin:$PATH"; export PATH
C() { sh "$D/cidre" "$@"; }
unset CIDRE_ROSETTA CIDRE_ROSETTA_RUNTIME CIDRE_MACOS_MAJEUR

# rosetta_etat seule, extraite du lanceur (sans executer le reste)
sed -n '/^ROSETTA_ETAT=$/,/^}$/p' "$R/cidre" >"$T/rosetta.sh"
etat() { sh -c '. "$1"; rosetta_etat' sh "$T/rosetta.sh"; }

echo "== 1. detection de Rosetta"
: >"$T/libRosettaRuntime"
verif "CIDRE_ROSETTA=absente l'impose" "absente" "$(CIDRE_ROSETTA=absente CIDRE_ROSETTA_RUNTIME="$T/libRosettaRuntime" etat)"
verif "CIDRE_ROSETTA=presente l'impose" "presente" "$(CIDRE_ROSETTA=presente CIDRE_ROSETTA_RUNTIME="$T/rien" etat)"
verif "CIDRE_ROSETTA=partielle l'impose" "partielle" "$(CIDRE_ROSETTA=partielle etat)"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
   verif "Apple Silicon, moteur absent : absente" "absente" "$(CIDRE_ROSETTA_RUNTIME="$T/rien" CIDRE_MACOS_MAJEUR=26 etat)"
   verif "Apple Silicon, moteur present, macOS 26 : presente" "presente" "$(CIDRE_ROSETTA_RUNTIME="$T/libRosettaRuntime" CIDRE_MACOS_MAJEUR=26 etat)"
   verif "Apple Silicon, moteur present, macOS 27 : presente" "presente" "$(CIDRE_ROSETTA_RUNTIME="$T/libRosettaRuntime" CIDRE_MACOS_MAJEUR=27 etat)"
   verif "Apple Silicon, moteur present, macOS 28 : partielle" "partielle" "$(CIDRE_ROSETTA_RUNTIME="$T/libRosettaRuntime" CIDRE_MACOS_MAJEUR=28 etat)"
   verif "Apple Silicon, moteur absent, macOS 28 : absente" "absente" "$(CIDRE_ROSETTA_RUNTIME="$T/rien" CIDRE_MACOS_MAJEUR=28 etat)"
   verif "valeur inconnue de CIDRE_ROSETTA : detection" "absente" "$(CIDRE_ROSETTA=peut-etre CIDRE_ROSETTA_RUNTIME="$T/rien" etat)"
   # ce Mac, tel qu'il est
   if [ -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]; then attendu=presente; else attendu=absente; fi
   [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 28 ] && [ $attendu = presente ] && attendu=partielle
   verif "ce Mac : $attendu" "$attendu" "$(etat)"
else
   verif "Mac Intel : presente (le x86_64 tourne en natif)" "presente" "$(CIDRE_ROSETTA_RUNTIME="$T/rien" etat)"
fi
grep -q 'arch -x86_64' "$T/rosetta.sh" && echec "rosetta_etat lance un binaire x86_64" || ok "rosetta_etat ne lance aucun binaire x86_64"

echo "== 2. jeux du client Steam installes en version macOS"
SAF="$HOME/Library/Application Support/Steam/steamapps"
octets() { for o in "$@"; do printf "\\$(printf %03o "$o")"; done; }
zeros() { i=0; while [ $i -lt "$1" ]; do octets 0; i=$((i + 1)); done; }
# en-tetes Mach-O, assez pour `file`
m_i386()  { octets 0xce 0xfa 0xed 0xfe 7 0 0 0 3 0 0 0 2 0 0 0; zeros 12; }
m_x86_64() { octets 0xcf 0xfa 0xed 0xfe 7 0 0 1 3 0 0 0 2 0 0 0; zeros 16; }
m_arm64() { octets 0xcf 0xfa 0xed 0xfe 12 0 0 1 0 0 0 0 2 0 0 0; zeros 16; }
jeu_mac() { # <appid> <nom> <fonction qui ecrit l'executable>
   app="$SAF/common/$2/$2.app"
   mkdir -p "$app/Contents/MacOS"
   printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"%s"\n}\n' "$1" "$2" "$2" >"$SAF/appmanifest_$1.acf"
   printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>%s</string></dict></plist>\n' "$2" >"$app/Contents/Info.plist"
   "$3" >"$app/Contents/MacOS/$2"
}
# binaires universels a deux tranches (en-tete fat, puis tranches a 64 et 128)
u_x86_arm() {
   octets 0xca 0xfe 0xba 0xbe 0 0 0 2  1 0 0 7 0 0 0 3 0 0 0 64 0 0 0 32 0 0 0 0
   octets 1 0 0 12 0 0 0 0 0 0 0 128 0 0 0 32 0 0 0 0
   zeros 16; m_x86_64; zeros 32; m_arm64
}
u_i386_x86() {
   octets 0xca 0xfe 0xba 0xbe 0 0 0 2  0 0 0 7 0 0 0 3 0 0 0 64 0 0 0 28 0 0 0 0
   octets 1 0 0 7 0 0 0 3 0 0 0 128 0 0 0 32 0 0 0 0
   zeros 16; m_i386; zeros 36; m_x86_64
}
jeu_mac 930001 JeuI386 m_i386
jeu_mac 930002 JeuIntel m_x86_64
jeu_mac 930003 JeuArm m_arm64
jeu_mac 930004 JeuUniversel u_x86_arm
jeu_mac 930005 JeuVieuxUniversel u_i386_x86
e() { file -b "$SAF/common/$1/$1.app/Contents/MacOS/$1"; }
contient "faux Mach-O : i386" "executable i386" "$(e JeuI386)"
contient "faux Mach-O : x86_64" "executable x86_64" "$(e JeuIntel)"
contient "faux Mach-O : arm64" "executable arm64" "$(e JeuArm)"
contient "faux Mach-O : universel x86_64 + arm64" "universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64" "$(e JeuUniversel)"
contient "faux Mach-O : universel i386 + x86_64" "universal binary with 2 architectures: [i386:Mach-O executable i386] [x86_64" "$(e JeuVieuxUniversel)"

ligne() { printf '%s\n' "$1" | tr '}' '\n' | grep "\"id\":\"$2\""; }
lancement() { ligne "$1" "$2" | sed -n 's/.*"lancement":"\([a-z]*\)".*/\1/p'; }
m32() { ligne "$1" "$2" | sed -n 's/.*"mac_32bits":\([a-z]*\).*/\1/p'; }
sr() { case $(ligne "$1" "$2") in *'"mac_sans_rosetta":true'*) echo true ;; *) echo absent ;; esac; }
# lancement, mac_32bits, mac_sans_rosetta des cinq jeux
resume() { # <sortie de list --json>
   for a in 930001 930002 930003 930004 930005; do printf '%s:%s/%s/%s ' "$a" "$(lancement "$1" $a)" "$(m32 "$1" $a)" "$(sr "$1" $a)"; done
}

for ro in presente absente partielle; do
   echo "-- Rosetta $ro"
   export CIDRE_ROSETTA=$ro
   l=$(C list --json)
   case $ro in
      presente) attendu="930001:cidre/true/absent 930002:natif/false/absent 930003:natif/false/absent 930004:natif/false/absent 930005:natif/false/absent " ;;
      *) attendu="930001:cidre/true/absent 930002:cidre/false/true 930003:natif/false/absent 930004:natif/false/absent 930005:cidre/false/true " ;;
   esac
   verif "list --json ($ro) : lancement/mac_32bits/mac_sans_rosetta" "$attendu" "$(resume "$l")"
   verif "list --json ($ro) : plateformes macos" "macos macos macos macos macos" "$(for a in 930001 930002 930003 930004 930005; do ligne "$l" $a | sed -n 's/.*"plateforme":"\([a-z]*\)".*/\1/p'; done | tr '\n' ' ' | sed 's/ $//')"
   t=$(C list)
   contient "list ($ro) : i386 dit Mac 32 bits" "Mac 32 bits : cidre dl 930001" "$t"
   if [ $ro = presente ]; then
      absent "list ($ro) : aucun Mac Intel sans Rosetta" "sans Rosetta" "$t"
   else
      contient "list ($ro) : x86_64 dit Mac Intel sans Rosetta" "Mac Intel sans Rosetta : cidre dl 930002" "$t"
      absent "list ($ro) : arm64 natif" "cidre dl 930003" "$t"
      absent "list ($ro) : universel natif" "cidre dl 930004" "$t"
   fi

   # play : refus (code 9) sans rien ouvrir, ou depart par Steam (faux open)
   for a in 930001 930002 930003 930004; do
      rm -f "$T/open.txt"
      p=$(C play $a --json 2>"$T/play.err"); rc=$?
      code=$(printf '%s' "$p" | sed -n 's/.*"evenement":"erreur","code":"\([a-z_0-9]*\)".*/\1/p')
      o=$(cat "$T/open.txt" 2>/dev/null)
      case $a:$ro in
         930001:*) verif "play $a ($ro) : refuse, code 9, mac_32bits, Steam pas appele" "9 mac_32bits " "$rc $code $o" ;;
         930002:absente)
            verif "play $a ($ro) : refuse, code 9, mac_sans_rosetta, Steam pas appele" "9 mac_sans_rosetta " "$rc $code $o"
            contient "play $a ($ro) : dit quoi faire" "cidre dl 930002" "$(cat "$T/play.err")" ;;
         *) verif "play $a ($ro) : part par Steam" "0  open steam://run/$a" "$rc $code $o" ;;
      esac
   done

   # install : auto -> windows pour ce qui bascule ; macos impose
   for a in 930001 930002 930003 930004; do
      s=$(C install $a 2>/dev/null)
      case $a:$ro in
         930001:*|930002:absente|930002:partielle) verif "install $a auto ($ro) : version Windows" "cidre_install $a windows" "$s" ;;
         *) verif "install $a auto ($ro) : inchange (auto)" "cidre_install $a" "$s" ;;
      esac
      s=$(C install $a macos 2>"$T/inst.err"); rc=$?
      case $a:$ro in
         930001:*|930002:absente) verif "install $a macos ($ro) : refuse (code 9)" "9 " "$rc $s" ;;
         *) verif "install $a macos ($ro) : accepte" "0 cidre_install $a macos" "$rc $s" ;;
      esac
      s=$(C install $a windows 2>/dev/null)
      verif "install $a windows ($ro) : windows" "cidre_install $a windows" "$s"
   done
   contient "install macos refuse : dit pourquoi" "Rosetta 2 n'est pas sur ce Mac" "$(CIDRE_ROSETTA=absente C install 930002 macos 2>&1)"

   # dl macos : refuse (9) ou poursuit jusqu'a SteamCMD (absent ici : code 1)
   for a in 930001 930002 930003 930004; do
      C dl $a macos >/dev/null 2>&1; rc=$?
      case $a:$ro in
         930001:*|930002:absente) verif "dl $a macos ($ro) : refuse (code 9)" "9" "$rc" ;;
         *) verif "dl $a macos ($ro) : pas refuse (SteamCMD absent : 1)" "1" "$rc" ;;
      esac
   done
done
unset CIDRE_ROSETTA

echo "== 3. jeux non installes : cache du client Steam et fiches"
# Un appinfo.vdf comme l'ecrit le client (v28) : common/name, type, oslist, osextended
le32() { octets $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)); }
fiche_client() { # <appid> <nom> <oslist> <osextended>
   { octets 0; printf 'appinfo\000'
       octets 2; printf 'appid\000'; le32 "$1"
       octets 0; printf 'common\000'
         octets 1; printf 'name\000%s\000' "$2"
         octets 1; printf 'type\000Game\000'
         octets 1; printf 'oslist\000%s\000' "$3"
         [ -z "$4" ] || { octets 1; printf 'osextended\000%s\000' "$4"; }
       octets 8
     octets 8
     octets 8
   } >"$T/corps"
   le32 "$1"; le32 $((60 + $(wc -c <"$T/corps")))
   le32 2; le32 1791900000; zeros 8; zeros 20; le32 42; zeros 20
   cat "$T/corps"
}
AI="$HOME/Library/Application Support/Steam/appcache/appinfo.vdf"
mkdir -p "$(dirname "$AI")"
{ le32 $((0x07564428)); le32 1
  fiche_client 940001 "Cache I386" "windows,macos" ""
  fiche_client 940002 "Cache Intel" "windows,macos" "macos64"
  fiche_client 940003 "Cache Arm" "windows,macos" "macos64,macosapplesilicon"
  fiche_client 940004 "Cache Arm Seul" "windows,macos" "macosapplesilicon,macosnotarized"
  fiche_client 940005 "Cache Windows" "windows" ""
  fiche_client 940006 "Fiche 64" "windows,macos" ""
  le32 0; } >"$AI"
O="$R/build/cidre-outil"
verif "cidre-outil plateformes : le faux cache se lit" "6" "$("$O" plateformes "$AI" 940001 940002 940003 940004 940005 940006 | wc -l | tr -d ' ')"
# une fiche (base de profils) : mac_32bits = false pour 940006 (Steam ne dit rien)
printf '[jeu]\nappid = 940006\nnom = "Fiche 64"\nmac_32bits = false\n' >"$CIDRE_PROFILS_BASE/940006.toml"
# 940007 : la fiche seule (absent du cache), 64 bits sans savoir l'architecture
printf '[jeu]\nappid = 940007\nnom = "Fiche 64 seule"\nmac_32bits = false\n' >"$CIDRE_PROFILS_BASE/940007.toml"
for ro in presente absente; do
   r=
   for a in 940001 940002 940003 940004 940005 940006 940007; do r="$r$a:$(CIDRE_ROSETTA=$ro C install $a 2>/dev/null | awk '{ print ($3 == "" ? "auto" : $3) }') "; done
   case $ro in
      presente) attendu="940001:windows 940002:auto 940003:auto 940004:auto 940005:auto 940006:auto 940007:auto " ;;
      absente)  attendu="940001:windows 940002:windows 940003:auto 940004:auto 940005:auto 940006:windows 940007:auto " ;;
   esac
   verif "install auto ($ro), d'apres le cache et les fiches" "$attendu" "$r"
done

# cidre library : cidre-outil bibliotheque, --sans-rosetta quand Rosetta manque
printf 'License packageID 1:\n - Apps    : 940001, 940002, 940003, 940004, 940005, 940006, (6 in total)\n' >"$T/licences.txt"
b=$("$O" bibliotheque "$T/licences.txt")
verif "bibliotheque : sans l'option, aucun mac_sans_rosetta" "0" "$(printf '%s' "$b" | grep -o mac_sans_rosetta | wc -l | tr -d ' ')"
verif "bibliotheque : mac_32bits sur le i386 et la fiche sans drapeau" "940001 940006" "$(printf '%s' "$b" | tr '}' '\n' | grep '"mac_32bits": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
b2=$("$O" bibliotheque --sans-rosetta --mac64 940006, "$T/licences.txt")
verif "bibliotheque --sans-rosetta : le x86_64 seul, et le 64 bits de la fiche sans drapeau arm64" "940002 940006" "$(printf '%s' "$b2" | tr '}' '\n' | grep '"mac_sans_rosetta": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
verif "bibliotheque --sans-rosetta : mac_32bits inchange (sauf la fiche)" "940001" "$(printf '%s' "$b2" | tr '}' '\n' | grep '"mac_32bits": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
t=$("$O" bibliotheque --texte --sans-rosetta "$T/licences.txt")
verif "bibliotheque --texte --sans-rosetta : (intel) sur le x86_64 seul" "940002" "$(printf '%s\n' "$t" | grep '(intel)' | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')"
# par cidre library (licences en cache)
mkdir -p "$CIDRE_DIR/cache"; cp "$T/licences.txt" "$CIDRE_DIR/cache/licences.txt"
verif "cidre library --json, Rosetta presente : pas de mac_sans_rosetta" "0" "$(CIDRE_ROSETTA=presente C library --json 2>/dev/null | grep -o mac_sans_rosetta | wc -l | tr -d ' ')"
verif "cidre library --json, Rosetta absente : le x86_64 seul, et la fiche 64 bits sans drapeau arm64" "940002 940006" "$(CIDRE_ROSETTA=absente C library --json 2>/dev/null | tr '}' '\n' | grep '"mac_sans_rosetta": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
verif "cidre library --json, Rosetta partielle : comme absente" "940002 940006" "$(CIDRE_ROSETTA=partielle C library --json 2>/dev/null | tr '}' '\n' | grep '"mac_sans_rosetta": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"

echo "== 3b. [jeu] mac_arch : la fiche tranche l'architecture"
# Les memes jeux, des fiches qui corrigent Steam : 940002 (macos64) est en fait
# universel, 940003 (macosapplesilicon) en fait Intel, 940001 (sans drapeau)
# en fait x86_64 ; 940008 (absent du cache) en i386 ; 940009 dit mac_32bits =
# true mais mac_arch = "arm64" (mac_arch prime).
fiche() { printf '[jeu]\nappid = %s\nnom = "Fiche %s"\n%s\n' "$1" "$1" "$2" >"$CIDRE_PROFILS_BASE/$1.toml"; }
fiche 940001 'mac_arch = "x86_64"'
fiche 940002 'mac_arch = "universel"'
fiche 940003 'mac_arch = "x86_64"'
fiche 940008 'mac_arch = "i386"'
fiche 940009 "$(printf 'mac_32bits = true\nmac_arch = "arm64"')"
verif "la fiche se lit : mac_arch" "universel" "$(sh "$R/tests/fiche_profil.sh" toml "$CIDRE_PROFILS_BASE/940002.toml" | awk -F'\t' '$1 == "jeu" && $2 == "mac_arch" { print $4 }')"
for ro in presente absente; do
   r=
   for a in 940001 940002 940003 940008 940009; do r="$r$a:$(CIDRE_ROSETTA=$ro C install $a 2>/dev/null | awk '{ print ($3 == "" ? "auto" : $3) }') "; done
   case $ro in
      presente) attendu="940001:auto 940002:auto 940003:auto 940008:windows 940009:auto " ;;
      absente)  attendu="940001:windows 940002:auto 940003:windows 940008:windows 940009:auto " ;;
   esac
   verif "install auto ($ro), d'apres mac_arch" "$attendu" "$r"
done
verif "install macos d'un universel de fiche, sans Rosetta : accepte" "0" "$(CIDRE_ROSETTA=absente C install 940002 macos >/dev/null 2>&1; echo $?)"
verif "dl macos d'un i386 de fiche : refuse (code 9)" "9" "$(CIDRE_ROSETTA=presente C dl 940008 macos >/dev/null 2>&1; echo $?)"
# le binaire installe passe avant la fiche
fiche 930002 'mac_arch = "arm64"'
fiche 930003 'mac_arch = "x86_64"'
verif "binaire installe prime : x86_64 malgre mac_arch arm64, sans Rosetta" "cidre_install 930002 windows" "$(CIDRE_ROSETTA=absente C install 930002 2>/dev/null)"
verif "binaire installe prime : arm64 malgre mac_arch x86_64, sans Rosetta" "cidre_install 930003" "$(CIDRE_ROSETTA=absente C install 930003 2>/dev/null)"
rm -f "$CIDRE_PROFILS_BASE/930002.toml" "$CIDRE_PROFILS_BASE/930003.toml"
# une valeur inconnue : ignoree
fiche 940002 'mac_arch = "ppc64"'
verif "mac_arch inconnue : ignoree (Steam : x86_64)" "cidre_install 940002 windows" "$(CIDRE_ROSETTA=absente C install 940002 2>/dev/null)"
fiche 940002 'mac_arch = "universel"'
# cidre library : --mac32/--mac64/--macarm/--macx64 d'apres les fiches
printf 'License packageID 1:\n - Apps    : 940001, 940002, 940003, 940004, 940005, 940006, 940009, (7 in total)\n' >"$CIDRE_DIR/cache/licences.txt"
lib() { CIDRE_ROSETTA=$1 C library --json 2>/dev/null | tr '}' '\n' | grep "\"$2\": true" | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | sort | tr '\n' ' ' | sed 's/ $//'; }
verif "library, Rosetta presente : aucun mac_32bits (940001 corrige en x86_64, 940006 par mac_32bits = false, 940009 arm64)" "" "$(lib presente mac_32bits)"
verif "library, Rosetta presente : aucun mac_sans_rosetta" "" "$(lib presente mac_sans_rosetta)"
verif "library, Rosetta absente : mac_sans_rosetta d'apres les fiches" "940001 940003 940006" "$(lib absente mac_sans_rosetta)"
verif "cidre-outil : --macx64 l'emporte sur macosapplesilicon, --macarm sur macos64" "940003" "$("$O" bibliotheque --sans-rosetta --macarm 940002, --macx64 940003, "$T/licences.txt" | tr '}' '\n' | grep '"mac_sans_rosetta": true' | sed -n 's/.*"appid": \([0-9]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"

echo "== 4. syntaxe"
sh -n "$R/cidre" && ok "sh -n cidre" || echec "sh -n cidre"
sh -n "$R/tests/tester_rosetta.sh" && ok "sh -n tester_rosetta.sh" || echec "sh -n tester_rosetta.sh"

echo
echo "$nb verifications, $ko en echec"
[ "$ko" -eq 0 ]
