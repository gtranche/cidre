#!/bin/sh
# temoin_0233.sh <dossier de construction FEX> : temoin de 0233 sans Wine. Desassemble CheckCall (Module.S, ARM64EC) dans
# l'objet construit et verifie que la taille de la table de redirection de ntdll est lue sur 32 bits (ldr w17, lu sur
# 8 octets avant : moitie haute prise dans la variable voisine, et lien refuse par lld quand le symbole tombe sur une
# adresse non alignee sur 8) et que l'indice egal a la taille est rejete (b.hs, b.hi avant). Code de sortie 0 si tout va.
B=${1:?dossier de construction FEX (ex. fex/build)}
OBJDUMP=${OBJDUMP:-llvm-objdump}
O=$(find "$B" -name "Module.S.obj" | head -1)
[ -n "$O" ] || { echo "ECHEC Module.S.obj introuvable sous $B"; exit 2; }
D=$("$OBJDUMP" -d --no-show-raw-insn "$O" | awk '/<CheckCall>:/{p=1; next} p && /^$/{exit} p')
[ -n "$D" ] || { echo "ECHEC CheckCall introuvable dans $O"; exit 2; }
e=0
if echo "$D" | grep -q "ldr[[:space:]]*w17"; then echo "OK    taille de la table lue sur 32 bits (ldr w17)"; else echo "ECHEC taille lue sur 64 bits (ldr x17)"; e=1; fi
if echo "$D" | grep -q "b\.hs"; then echo "OK    indice egal a la taille rejete (b.hs)"; else echo "ECHEC borne laissant passer l'indice egal a la taille (b.hi)"; e=1; fi
echo "$( [ $e = 0 ] && echo OK || echo ECHEC ) : temoin 0233"
exit $e
