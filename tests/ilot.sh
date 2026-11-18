#!/bin/sh
# L'ilot TSO (option de fiche `ilot = true`) : le jeu tourne dans un vCPU de Hypervisor.framework, en TSO
# materiel et avec des sous-pages exactes de 4 Kio, au lieu du TSO logiciel de FEX et des talons de sous-pages.
# Seul l'executable du jeu y entre (CIDRE_ILOT_EXE, un seul processus par prefixe) ; le client Battle.net et les
# services de Wine tournent hors ilot, sur le meme runtime (le code de l'ilot y dort).
#
#   ilot.sh chemin                     le runtime de l'ilot (CIDRE_ILOT_RUNTIME, sinon <dossier Cidre>/ilot/wine11-arm64)
#   ilot.sh importer <runtime de dev>  copie les fichiers propres a l'ilot d'un runtime de dev (ilot-rt19) dans les
#                                      artefacts (CIDRE_ILOT_SOURCE, sinon wine/ilot), avec leur manifeste
#   ilot.sh preparer                   (re)fait le runtime de l'ilot s'il manque ou si le runtime de Cidre ou les
#                                      artefacts ont change : clone APFS du runtime de Cidre (cp -c, sans place
#                                      disque), fichiers de l'ilot par-dessus, chargeurs re-signes ad hoc avec le
#                                      droit com.apple.security.hypervisor (outils/hyperviseur.plist)
#   ilot.sh disponible                 « oui », ou « non : <raison> » (code 1) : Mac arm64, hyperviseur du noyau
#                                      (kern.hv_support), runtime a jour, chargeur signe avec le droit, garde de l'ilot
#   ilot.sh env <exe>                  l'environnement de production de l'ilot pour cet executable, en lignes
#                                      « export VAR='valeur' » (CIDRE_ILOT_JOURNAL=1 : chronologie et fils bloques)
#   ilot.sh aligner <prefixe> ilot|normal
#                                      met dans system32 du prefixe les DLL que le jeu lit sur le disque et qui
#                                      different d'un runtime a l'autre (les cinq DLL ci-dessous, et xtajit64.dll),
#                                      celles du runtime de l'ilot ou celles du runtime de Cidre ; refuse (code 4) si
#                                      le wineserver du prefixe tourne
#
# Depuis la serie D4 (wine11 0290-0294, 0301, 0355, 0462, 0463 ; FEX 0292-0493 ; INTEGRATION_D4.md), le runtime de
# Cidre porte lui-meme l'ilot : ntdll.so (ilot.c, garde des regions, relie a Hypervisor.framework), win32u.so
# (memoire Vulkan de l'hote en memoire Windows) et xtajit64.dll (FEX de l'ilot), tout inactif sans CIDRE_ILOT=1.
# Les fichiers propres au runtime de l'ilot sont les cinq DLL PE reconstruites sans ldp q (un ldp q coute 11 a 14
# fois plus sous le TSO materiel ; thunks d'entree recousus, 0309) : ntdll, kernelbase, kernel32, ucrtbase, msvcrt
# (tests/construire_pile_d4.sh pe puis ilot). Le reste est le runtime de Cidre lui-meme, clone, chargeurs re-signes
# avec le droit hyperviseur : une mise a jour de Cidre refait le runtime de l'ilot au lancement suivant.
# Corps entre accolades, ferme par `exit` : lu en entier avant d'etre execute.
{
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
CIDRE_DIR=${CIDRE_DIR:-$HOME/Library/Application Support/Cidre}
REL=${CIDRE_ILOT_REL:-$R/wine/wine11-arm64}
SRC=${CIDRE_ILOT_SOURCE:-$R/wine/ilot}
RT=${CIDRE_ILOT_RUNTIME:-$CIDRE_DIR/ilot/wine11-arm64}
PLIST=$R/outils/hyperviseur.plist
FICHIERS="lib/wine/aarch64-windows/ntdll.dll lib/wine/aarch64-windows/kernelbase.dll lib/wine/aarch64-windows/kernel32.dll lib/wine/aarch64-windows/ucrtbase.dll lib/wine/aarch64-windows/msvcrt.dll"
# (xtajit.dll, le FEX des invites 32 bits du client Battle.net, reste celui du runtime de Cidre : jamais aligne)
DLL_DISQUE="ntdll.dll kernelbase.dll kernel32.dll ucrtbase.dll msvcrt.dll xtajit64.dll"

# l'empreinte qui oblige a refaire le runtime : le runtime de Cidre (ses .so, son chargeur, ses DLL) et le manifeste
empreinte() {
   { (cd "$REL" 2>/dev/null && stat -f '%N %z %m' lib/wine/aarch64-unix/* lib/wine/aarch64-windows/*.dll bin/wine 2>/dev/null)
     cat "$SRC/ilot.manifeste" 2>/dev/null; } | shasum | cut -c1-40
}
signe_hv() { codesign -d --entitlements - "$1" 2>/dev/null | grep -q 'com.apple.security.hypervisor'; }
macho() { file "$1" 2>/dev/null | grep -q 'Mach-O'; }
# le runtime de l'ilot sert-il en ce moment ? (un processus de Wine lance depuis lui)
en_usage() { ps -axo command= 2>/dev/null | grep -F "$RT/" | grep -v grep >/dev/null; }

case ${1:-} in
   chemin) printf '%s\n' "$RT" ;;
   importer)
      d=${2:?usage: ilot.sh importer <runtime de dev de l ilot>}
      grep -aq 'garde controlee' "$REL/lib/wine/aarch64-unix/ntdll.so" 2>/dev/null || { echo "$REL : ntdll.so sans la garde de l'ilot (serie 0290 absente)" >&2; exit 2; }
      for f in $FICHIERS; do
         [ -f "$d/$f" ] || { echo "$d : $f absent" >&2; exit 2; }
         mkdir -p "$SRC/$(dirname "$f")"
         cp "$d/$f" "$SRC/$f.neuf" && mv "$SRC/$f.neuf" "$SRC/$f"
      done
      (cd "$SRC" && for f in $FICHIERS; do printf '%s  %s\n' "$(md5 -q "$f")" "$f"; done) >"$SRC/ilot.manifeste"
      echo "artefacts de l'ilot : $SRC"; cat "$SRC/ilot.manifeste" ;;
   preparer)
      [ -f "$SRC/ilot.manifeste" ] || { echo "ilot : artefacts absents ($SRC)" >&2; exit 3; }
      (cd "$SRC" && md5 -r $FICHIERS 2>/dev/null | awk '{ print $1 "  " $2 }') | cmp -s - "$SRC/ilot.manifeste" \
         || { echo "ilot : artefacts differents de leur manifeste ($SRC)" >&2; exit 3; }
      [ -x "$REL/bin/wine" ] || { echo "ilot : runtime de Cidre absent ($REL)" >&2; exit 3; }
      e=$(empreinte)
      [ "$(cat "$RT/.cidre-ilot-empreinte" 2>/dev/null)" = "$e" ] && { echo "ilot : runtime a jour ($RT)"; exit 0; }
      en_usage && { echo "ilot : runtime en usage, refait au prochain lancement" >&2; exit 4; }
      mkdir -p "$(dirname "$RT")"
      rm -rf "$RT.neuf"
      # clone APFS : aucune place disque tant que rien n'est reecrit (5 Gio sinon ; on refuse plutot que copier)
      cp -c -R "$REL" "$RT.neuf" 2>/dev/null || { rm -rf "$RT.neuf"; echo "ilot : clone APFS impossible (disque non APFS ?)" >&2; exit 3; }
      for f in $FICHIERS; do cp "$SRC/$f" "$RT.neuf/$f.neuf" && mv "$RT.neuf/$f.neuf" "$RT.neuf/$f"; done
      for b in "$RT.neuf/lib/wine/aarch64-unix/wine" "$RT.neuf/bin/wine"; do
         [ -f "$b" ] && [ ! -L "$b" ] && macho "$b" || continue
         codesign -f -s - --entitlements "$PLIST" "$b" >/dev/null 2>&1 || { rm -rf "$RT.neuf"; echo "ilot : signature de $b impossible" >&2; exit 3; }
         signe_hv "$b" || { rm -rf "$RT.neuf"; echo "ilot : $b sans le droit hyperviseur apres signature" >&2; exit 3; }
      done
      printf '%s\n' "$e" >"$RT.neuf/.cidre-ilot-empreinte"
      rm -rf "$RT.ancien"; [ ! -d "$RT" ] || mv "$RT" "$RT.ancien"
      mv "$RT.neuf" "$RT" && rm -rf "$RT.ancien"
      echo "ilot : runtime prepare ($RT)" ;;
   disponible)
      non() { echo "non : $1"; exit 1; }
      [ "$(uname -m)" = arm64 ] || non "Mac sans Apple Silicon"
      [ "$(sysctl -n kern.hv_support 2>/dev/null)" = 1 ] || non "hyperviseur indisponible sur ce Mac (kern.hv_support)"
      [ -x "$RT/bin/wine" ] || non "runtime de l'ilot absent ($RT)"
      [ "$(cat "$RT/.cidre-ilot-empreinte" 2>/dev/null)" = "$(empreinte)" ] || non "runtime de l'ilot perime (ilot.sh preparer)"
      signe_hv "$RT/lib/wine/aarch64-unix/wine" || non "chargeur sans le droit com.apple.security.hypervisor"
      grep -aq 'garde controlee' "$RT/lib/wine/aarch64-unix/ntdll.so" 2>/dev/null || non "ntdll.so sans la garde de l'ilot"
      echo oui ;;
   env)
      x=${2:?usage: ilot.sh env <exe>}
      case $x in *"'"*|*/*|*\\*) echo "ilot : nom d'executable refuse : $x" >&2; exit 2 ;; esac
      # Reglage de jeu de l'ilot (manches D2R/D4 du 24/10) : TSO materiel (FEX sans TSO logiciel pour l'exe du
      # jeu, par son AppConfig : lancer_depuis_steam.sh), code auto-modifie suivi par jumelles armees, vues
      # partagees de fichier en copie reecrite, sous-pages exactes (defaut de l'ilot), sommeil de wait_on_address
      # par tranches (defaut de l'ilot, parade aux reveils perdus). La compilation Metal hors verrou de KosmicKrisp
      # est deja le defaut du lanceur pour tous les jeux (CIDRE_COMPILE_HORS_VERROU).
      # Depuis les parties D4 (partie_combo.sh, 11/11) : appels entre processus de l'ilot (CIDRE_ILOT_XPROC=1),
      # pages validees rearmees (FEX 0360, CIDRE_SMC_REARMER=1), extensions de l'hote donnees a FEX limitees a crypto
      # comme dans ces parties (flagm/flagm2 jamais validees dans un vCPU ; CIDRE_ILOT_FEX_HOSTFEATURES les remet).
      # Chaque valeur deja posee dans l'environnement garde la main.
      for v in "CIDRE_ILOT=1" "CIDRE_ILOT_EXE=$x" "CIDRE_ILOT_UNIQUE=1" "CIDRE_ILOT_VUES_PARTAGEES=copie" "CIDRE_SMC_ARME=1" \
               "CIDRE_SOUS_PAGES_EN_LIGNE=0" "CIDRE_DIAG_SOUS_PAGES=0" "CIDRE_ILOT_XPROC=1" "CIDRE_SMC_REARMER=1"; do
         n=${v%%=*}
         case $n in CIDRE_ILOT|CIDRE_ILOT_EXE) val=${v#*=} ;; *) eval "val=\${$n:-${v#*=}}" ;; esac
         printf "export %s='%s'\n" "$n" "$val"
      done
      printf "export FEX_HOSTFEATURES='%s'\n" "${CIDRE_ILOT_FEX_HOSTFEATURES:-enablecrypto}"
      # diagnostic seulement (journal detaille) : chronologie par 100 ms et fils bloques plus de 5 s
      if [ "${CIDRE_ILOT_JOURNAL:-0}" = 1 ]; then printf "export CIDRE_ILOT_CHRONO='1'\nexport CIDRE_ILOT_BLOQUES='5'\n"; fi ;;
   aligner)
      p=${2:?usage: ilot.sh aligner <prefixe> ilot|normal}; m=${3:?usage: ilot.sh aligner <prefixe> ilot|normal}
      case $m in ilot) s=$RT ;; normal) s=$REL ;; *) echo "mode inconnu : $m" >&2; exit 2 ;; esac
      d=$p/drive_c/windows/system32
      [ -d "$d" ] || { echo "ilot : prefixe sans system32 ($p)" >&2; exit 2; }
      srv=/tmp/.wine-$(id -u)/server-$(stat -f '%Xd-%Xi' "$p" 2>/dev/null)
      [ -S "$srv/socket" ] && pgrep -x wineserver >/dev/null 2>&1 && { echo "ilot : le wineserver du prefixe tourne, rien aligne" >&2; exit 4; }
      # Renommages en attente (wineboot -u : DLL qu'il avait chargees, ecrites en dllXXXX.tmp) : le demarrage suivant
      # du prefixe les execute et ecraserait ce qu'on aligne ici (D4 gele, 17/11). On les execute d'abord.
      if grep -aq '^"PendingFileRenameOperations"=' "$p/system.reg" 2>/dev/null; then
         WINEPREFIX=$p WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" "$REL/bin/wineboot" --init >/dev/null 2>&1 || true
         WINEPREFIX=$p "$REL/bin/wineserver" -w 2>/dev/null || true
         ! grep -aq '^"PendingFileRenameOperations"=' "$p/system.reg" 2>/dev/null \
            || echo "ilot : renommages en attente dans $p/system.reg : l'alignement sera defait au demarrage" >&2
      fi
      n=0
      for f in $DLL_DISQUE; do
         [ -f "$s/lib/wine/aarch64-windows/$f" ] || continue
         cmp -s "$s/lib/wine/aarch64-windows/$f" "$d/$f" && continue
         cp "$s/lib/wine/aarch64-windows/$f" "$d/$f.cidre-neuf" && mv "$d/$f.cidre-neuf" "$d/$f" && n=$((n + 1))
      done
      printf '%s\n' "$m" >"$p/.cidre-ilot-alignement"
      [ $n -eq 0 ] || echo "    ilot    : prefixe aligne sur le runtime $([ "$m" = ilot ] && echo "de l'ilot" || echo "de Cidre") ($n DLL : $DLL_DISQUE)" ;;
   *) echo "usage : ilot.sh chemin | importer <runtime> | preparer | disponible | env <exe> | aligner <prefixe> ilot|normal" >&2; exit 2 ;;
esac
exit 0
}
