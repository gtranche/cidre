#!/bin/sh
# Verifie / re-applique les cles Info.plist « jeu » dans le binaire Wine qui
# cree la fenetre Cocoa du jeu -- lib/wine/aarch64-unix/wine (PAS bin/wine : le
# loader se re-execute, c'est ce binaire-la qui porte la fenetre, cf. NOTES).
#
# Les cles posees :
#   NSPrefersDisplaySafeAreaCompatibilityMode = false  -> la fenetre couvre
#       l'encoche du MacBook en plein ecran (comme un jeu Mac natif).
#   LSApplicationCategoryType = public.app-category.games
#   LSSupportsGameMode = true   (exige macOS 26+)
#   GCSupportsGameMode = true   -> macOS active le Game Mode (priorite CPU/GPU,
#       latence manette/audio) quand la fenetre est au premier plan en vrai
#       plein ecran.
#
# LE VRAI CORRECTIF EST EN AMONT : ces cles sont dans le template
# src/wine11/loader/wine_info.plist.in, donc posees au link (-Wl,-sectcreate)
# a CHAQUE build. Un `make install` ne les efface donc plus. Ce script n'est
# qu'un filet de securite : il repare EN PLACE, sans rebuild, un binaire qui ne
# les aurait pas (ex. un binaire stock restaure), via llvm-objcopy.
#
# Limite assumee : llvm-objcopy ne sait pas AGRANDIR une section Mach-O. Le
# plist compact (~920 o) tient dans la section stock de 938 o. Si la section est
# trop petite ou absente, on demande un rebuild -- qui, lui, pose la version
# DOCTYPE propre sans contrainte de taille.
#
#   plist_jeu_wine.sh [verifier|reparer] [chemin/vers/aarch64-unix/wine]
#
# verifier (defaut) : dit si les 4 cles sont presentes. Sort 0 si oui, 1 sinon.
# reparer           : les (re)pose en place si besoin, puis re-signe ad-hoc.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-verifier}
BIN=${2:-$R/wine/wine11-arm64/lib/wine/aarch64-unix/wine}

[ -f "$BIN" ] || { echo "binaire introuvable : $BIN" >&2; exit 2; }

# llvm-objcopy : dans le PATH, ou dans la toolchain livree.
OBJCOPY=$(command -v llvm-objcopy 2>/dev/null || true)
[ -n "$OBJCOPY" ] || for d in "$R"/toolchain/llvm-mingw-*/bin; do
   [ -x "$d/llvm-objcopy" ] && OBJCOPY="$d/llvm-objcopy" && break
done

CLES='NSPrefersDisplaySafeAreaCompatibilityMode LSApplicationCategoryType LSSupportsGameMode GCSupportsGameMode'

# otool imprime offset en decimal mais size en hexa ; on recalcule la taille en
# shell (awk de BSD n'a pas strtonum). Rend "<offset_decimal> <taille_hexa>".
lire_section() {
   # Dans otool -l, pour une section : sectname, segname, addr, size, offset...
   # (size AVANT offset) -> on capture les deux puis on imprime.
   otool -l "$BIN" 2>/dev/null | awk '
      /sectname __info_plist/ { f = 1; off = ""; sz = ""; next }
      f && $1 == "size"   { sz = $2 }
      f && $1 == "offset" { off = $2 }
      f && off != "" && sz != "" { print off, sz; exit }
   '
}

SECT=$(lire_section)
OFF=$(printf '%s' "$SECT" | awk '{print $1}')
SZHEX=$(printf '%s' "$SECT" | awk '{print $2}')
# size est du type 0x00000000000003aa
case $SZHEX in 0x*) SZ=$((SZHEX)) ;; '' ) SZ=0 ;; *) SZ=$SZHEX ;; esac
[ -n "${OFF:-}" ] || OFF=0

manquantes() {
   [ "$SZ" -gt 0 ] || { echo "$CLES"; return; }
   TXT=$(dd if="$BIN" bs=1 skip="$OFF" count="$SZ" 2>/dev/null)
   out=""
   for k in $CLES; do
      case $TXT in *"$k"*) : ;; *) out="$out $k" ;; esac
   done
   printf '%s' "${out# }"
}

MANQUE=$(manquantes)

if [ "$MODE" = verifier ]; then
   if [ -z "$MANQUE" ]; then
      echo "OK : les 4 cles jeu/encoche sont presentes dans $BIN"
      exit 0
   fi
   echo "MANQUE dans $BIN :$MANQUE" >&2
   echo "  -> reconstruire Wine (template wine_info.plist.in) ou : $0 reparer" >&2
   exit 1
fi

[ "$MODE" = reparer ] || { echo "usage : $0 [verifier|reparer] [binaire]" >&2; exit 2; }

if [ -z "$MANQUE" ]; then
   echo "rien a faire : les cles sont deja presentes dans $BIN"
   exit 0
fi

[ -n "$OBJCOPY" ] || { echo "llvm-objcopy introuvable (PATH ou toolchain)" >&2; exit 3; }
[ "$SZ" -gt 0 ] || {
   echo "pas de section __info_plist dans $BIN : objcopy ne peut pas en creer une." >&2
   echo "  -> reconstruire Wine, qui la pose au link depuis wine_info.plist.in." >&2
   exit 3; }

# On preserve la version deja embarquee (sinon on garde 11.18 par defaut).
VER=11.18
if [ "$SZ" -gt 0 ]; then
   V=$(dd if="$BIN" bs=1 skip="$OFF" count="$SZ" 2>/dev/null | tr '<' '\n' \
       | sed -n 's#^string>\(.*\)#\1#p' | sed -n '9p')
   # 9e <string> = CFBundleVersion dans notre ordre de cles ; sinon on garde VER.
   case ${V:-} in [0-9]*) VER=$V ;; esac
fi

TMP=$(mktemp -t cidre_plist) || exit 3
# Plist compact (une ligne, sans DOCTYPE) : ~920 o avec la version, tient dans la
# section stock de 938 o. Meme contenu que le template, en plus dense.
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'\
'<key>CFBundleAllowMixedLocalizations</key><true/>'\
'<key>CFBundleDevelopmentRegion</key><string>English</string>'\
'<key>CFBundleExecutable</key><string>wine</string>'\
'<key>CFBundleIdentifier</key><string>org.winehq.wine</string>'\
'<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>'\
'<key>CFBundleName</key><string>Wine</string>'\
'<key>CFBundlePackageType</key><string>APPL</string>'\
"<key>CFBundleShortVersionString</key><string>$VER</string>"\
'<key>CFBundleSignature</key><string>????</string>'\
"<key>CFBundleVersion</key><string>$VER</string>"\
'<key>NSPrincipalClass</key><string>WineApplication</string>'\
'<key>LSUIElement</key><string>1</string>'\
'<key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>'\
'<key>LSApplicationCategoryType</key><string>public.app-category.games</string>'\
'<key>LSSupportsGameMode</key><true/>'\
'<key>GCSupportsGameMode</key><true/>'\
'</dict></plist>' >"$TMP"

PLSZ=$(wc -c <"$TMP")
if [ "$PLSZ" -gt "$SZ" ]; then
   echo "plist ($PLSZ o) > section ($SZ o) : objcopy ne peut pas agrandir." >&2
   echo "  -> reconstruire Wine (section reposee au link, sans limite)." >&2
   rm -f "$TMP"; exit 3
fi

"$OBJCOPY" --update-section __TEXT,__info_plist="$TMP" "$BIN" || {
   echo "echec llvm-objcopy --update-section" >&2; rm -f "$TMP"; exit 3; }
rm -f "$TMP"

# objcopy invalide la signature ; re-signer ad-hoc (comme le linker le ferait).
codesign -f -s - "$BIN" >/dev/null 2>&1 || {
   echo "ATTENTION : re-signature ad-hoc echouee (codesign)" >&2; }

MANQUE=$(manquantes)
if [ -z "$MANQUE" ]; then
   echo "REPARE : cles reposees dans $BIN (version $VER), re-signe ad-hoc"
   exit 0
fi
echo "echec : cles toujours absentes apres reparation :$MANQUE" >&2
exit 3
