#!/bin/sh
# Imprime la valeur de FEX_HOSTFEATURES pour ce Mac : les extensions ARM de
# l'hote que le JIT de FEX doit employer.
#
#   sh tests/extensions_fex.sh                         ex. « enablecrypto,enableflagm,enableflagm2 »
#   CIDRE_FEX_EXTENSIONS=1 sh tests/extensions_fex.sh  ex. « enablecrypto,enableflagm,enableflagm2,enablelrcpc,enablelrcpc2 »
#   CIDRE_FEX_EXTENSIONS=0 sh tests/extensions_fex.sh  « enablecrypto » (l'etat d'avant le 22/10)
#
# Sous Wine/macOS, FEX arm64ec ne voit aucune extension : il lit les registres
# ID (ISAR0/1, MMFR…) dans HKLM\Hardware\Description\System\CentralProcessor\N,
# que wineboot remplit depuis get_core_id_regs_arm64, un stub sous macOS (0
# registre) ; un `mrs ID_AA64ISAR0_EL1` en EL0 y donne SIGILL, et aucune API
# Windows ne porte FlagM2 ou LRCPC2. FEX se croit donc sur un ARMv8.0 nu. La
# verite de chaque Mac est dans sysctl hw.optional.arm.FEAT_* : une extension
# n'est donnee a FEX que si CE Mac l'annonce.
#
# Liste retenue apres bancs (M1 Max, FEX 0179, 2026-10-18, medianes de 7 passes
# entrelacees, tests/banc_extensions_fex.c,
# tests/banc_drapeaux_fex.c ; justesse : tests/temoin_drapeaux.c) :
#   FlagM2  : comparaisons flottantes scalaires (ucomiss/comisd) -38,6 %
#   LRCPC + LRCPC2 : SQLite -1,8 %, zlib -1,6 %, acces TSO a deplacement -2,1 %
#             (ldapr coute un ldar sur M1 : la taxe TSO elle-meme ne bouge pas)
# Ecartees : LSE (atomiques +10 a +88 %, plus lent que LL/SC sous contention
# sur M1), FlagM, FRINTTS, FCMA, DotProd (dans le bruit), AFP (absent du M1,
# jamais mesure sur M2+ : FPCR.AH/NEP a valider par un temoin x87/SSE d'abord).
# enablecrypto (CRC32/AES/SHA/PMULL, presents sur tout Apple Silicon) rend au
# CPUID invite SSE4.2 et AES-NI (Dead by Daylight, NOTES §21251).
#
# En jeu, aucun gain ne tient (M1 Max, 2026-10-18, A B A B) : PEAK au loin sous
# TSO 13,85 -> 13,65 fps (bruit, la taxe TSO ne bouge pas) ; Exp33 au menu,
# limite par le GPU, 162,4 -> 161,4/163,4 fps, CPU 7,76 -> 7,93/7,76 ms par image.
# D'ou : LRCPC/LRCPC2 ETEINTS par defaut ; CIDRE_FEX_EXTENSIONS=1 les donne a
# FEX, pour un jeu limite par le CPU hors TSO a mesurer.
#
# FlagM + FlagM2 ALLUMES par defaut (2026-10-22) : instructions de drapeaux
# (cfinv, rmif, setf8/16, axflag/xaflag) qui remplacent des suites mrs/msr NZCV,
# sans changer le resultat (temoin_drapeaux : memes empreintes avec et sans).
# Banc FEX contre Rosetta (banc-rosetta, 3 series entrelacees, medianes) :
# switch +2,7 %, entier +1,3 %, zlib +1,0 %, sqlite +0,8 %, rien ne recule.
# Chaque Mac ne recoit que ce que sysctl lui annonce (FlagM : ARMv8.4,
# FlagM2 : ARMv8.5, tous deux presents du M1 au M4).
# CIDRE_FEX_EXTENSIONS=0 revient a enablecrypto seul.
l=enablecrypto
if [ "${CIDRE_FEX_EXTENSIONS:-}" != 0 ]; then
   for e in FEAT_FlagM:enableflagm FEAT_FlagM2:enableflagm2; do
      if [ "$(sysctl -n "hw.optional.arm.${e%%:*}" 2>/dev/null)" = 1 ]; then
         l=$l,${e#*:}
      fi
   done
fi
if [ "${CIDRE_FEX_EXTENSIONS:-0}" = 1 ]; then
   for e in FEAT_LRCPC:enablelrcpc FEAT_LRCPC2:enablelrcpc2; do
      if [ "$(sysctl -n "hw.optional.arm.${e%%:*}" 2>/dev/null)" = 1 ]; then
         l=$l,${e#*:}
      fi
   done
fi
echo "$l"
