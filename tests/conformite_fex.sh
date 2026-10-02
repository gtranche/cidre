#!/bin/sh
# Suite de conformité FEX (pile arm64ec) : vérifie que FEX émule CORRECTEMENT les
# instructions et mécanismes dont dépendent les jeux Windows. C'est l'outillage qui a
# permis d'innocenter toute la pile pendant l'enquête DbD (et de rattraper un bug de mon
# propre test SHA). À relancer après toute reconstruction de FEX pour attraper une régression.
#
#   sh tests/conformite_fex.sh
R=$(cd "$(dirname "$0")/.." && pwd)
T="$R/toolchain/llvm-mingw-20260908-ucrt-macos-universal"
CLANG="$T/bin/clang"; INC="$T/generic-w64-mingw32/include"; SRC="$R/tests/conformite_fex"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

run_exe(){ # $1=nom $2=exe $3=motif_succes
  out=$(sh "$R/tests/etape2_pile_arm64ec.sh" "$2" 2>/dev/null)
  if printf '%s' "$out" | grep -aqF "$3"; then printf "  [OK]    %s\n" "$1"; PASS=$((PASS+1))
  else printf "  [ECHEC] %s\n" "$1"; printf '%s' "$out" | grep -aivE '^[[:space:]]*$|fixme' | tail -2 | sed 's/^/          /'; FAIL=$((FAIL+1)); fi
}
# Tests « freestanding » (sans CRT, mainCRTStartup, kernel32) : crypto pur.
t_fs(){ nom="$1"; src="$2"; marker="$3"; shift 3
  if "$CLANG" --target=x86_64-w64-mingw32 -O1 "$@" -ffreestanding -nostdlib -nostartfiles \
       -isystem "$INC" "$SRC/$src" -o "$TMP/t.exe" -Wl,-e,mainCRTStartup -lkernel32 2>/dev/null
  then run_exe "$nom" "$TMP/t.exe" "$marker"; else printf "  [BUILD] %s : compilation echouee\n" "$nom"; FAIL=$((FAIL+1)); fi
}
# Tests avec CRT statique (main).
t_crt(){ nom="$1"; src="$2"; marker="$3"; shift 3
  if "$CLANG" --target=x86_64-w64-mingw32 "$@" -static "$SRC/$src" -o "$TMP/t.exe" 2>/dev/null
  then run_exe "$nom" "$TMP/t.exe" "$marker"; else printf "  [BUILD] %s : compilation echouee\n" "$nom"; FAIL=$((FAIL+1)); fi
}

echo "=== Conformite FEX — pile arm64ec ==="
t_fs  "SHA-256 SHA-NI (vecteur NIST abc)"        sha.c            "SHA-NI : CORRECT"        -msha -mssse3 -msse4.1
t_fs  "AES-256-CBC AES-NI (vecteur NIST)"        aes256.c         "AES-256-CBC : CORRECT"   -maes -mssse3 -msse4.1
t_crt "Bignum MUL/MULX/ADCX (base RSA/EC)"       bignum.c         "bignum OK"               -O1 -mbmi2 -madx
t_crt "ADOX + double chaine (mul RSA/EC)"        adox.c           "bignum complet correct"  -O1 -madx
t_crt "Ordre memoire TSO (litmus MP)"            tso_mp.c         "TSO OK"                  -O2
t_crt "Code auto-modifiant SMC (detecte)"        smc.c            "SMC vu sans flush"       -O0
t_crt "Callbacks TLS (process + thread attach)"  tls_callbacks.c  "thread_attach OK"        -O0 -Wl,-u,_tls_used
t_crt "Static thread-safe MSVC (epoque TLS)"     static_msvc.c    "S1 OK"                   -O1 -Wl,-u,_tls_used
echo "=== Resultat : $PASS OK, $FAIL echec(s) ==="
[ "$FAIL" -eq 0 ]
