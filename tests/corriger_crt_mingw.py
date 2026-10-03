#!/usr/bin/env python3
"""Retire x18 des objets de demarrage de mingw, dans la chaine d'outils.

Le correctif 0069 corrige NtCurrentTeb() dans winnt.h, mais crt1/crt2/dllcrt2
sont livres **deja compiles** : l'en-tete ne peut rien pour eux. Et recompiler
depuis les sources amont ne marche pas, la version livree n'est ni v14 ni
master (symboles __main contre __mingw_dll_do_global_ctors).

Ces objets lisent x18 pour une seule chose, un jeton d'identite de fil :

    void *fiberid = ((PNT_TIB)NtCurrentTeb ())->StackBase;
    while ((lock_free = InterlockedCompareExchangePointer (&lock, fiberid, NULL)))
       if (lock_free == fiberid) ...

fiberid n'est jamais dereference : il sert de valeur unique et non nulle dans un
verrou. TPIDRRO_EL0 a exactement ces deux proprietes, et lui survit aux retours
du noyau. On remplace donc, instruction pour instruction :

    mov  x8, x18            ->   mrs  x8, tpidrro_el0
    ldr  xD, [x8, #0x8]     ->   mov  xD, x8

Hors de portee, documente : tlsdtor.o et __cxa_get_globals de libc++abi lisent
[x18, #0x58], le vrai ThreadLocalStoragePointer -- ceux-la demandent le TEB.
"""
import struct, sys, shutil, os

CIBLES = ["crt1.o", "crt1u.o", "crt2.o", "crt2u.o", "dllcrt1.o", "dllcrt2.o"]

def mov_de_x18(mot):
    """mov xD, x18 == orr xD, xzr, x18 ; rend D ou None."""
    return mot & 31 if (mot & 0xFFFFFFE0) == 0xAA1203E0 else None

def ldr_8_de(mot, n):
    """ldr xD, [xn, #0x8] ; rend D ou None."""
    attendu = 0xF9400000 | (1 << 10) | (n << 5)
    return mot & 31 if (mot & 0xFFFFFFE0) == attendu else None

def sections(d, base=0):
    """Rend (nom, offset absolu, taille) de chaque section d'un objet COFF.

    Les noms de plus de huit caracteres -- « .text$#__tmainCRTStartup », les
    variantes ARM64EC -- sont ranges dans la table des chaines et la section ne
    porte que « /decalage ».
    """
    nsec, = struct.unpack_from("<H", d, base + 2)
    ptr_sym, nb_sym = struct.unpack_from("<II", d, base + 8)
    taille_opt, = struct.unpack_from("<H", d, base + 16)
    tab = base + 20 + taille_opt
    chaines = base + ptr_sym + nb_sym * 18 if ptr_sym else 0

    def nom_de(brut8):
        if brut8[:1] == b"/" and chaines:
            dec = int(brut8[1:].rstrip(b"\0").decode("latin1"))
            fin = d.index(b"\0", chaines + dec)
            return d[chaines + dec:fin].decode("latin1")
        return brut8.rstrip(b"\0").decode("latin1")

    for i in range(nsec):
        e = tab + 40 * i
        brut, ptr = struct.unpack_from("<II", d, e + 16)
        if ptr and brut:
            yield nom_de(bytes(d[e:e+8])), base + ptr, brut


def sections_texte(d, base=0):
    """Sections de code, y compris celles de l'objet ARM64EC imbrique.

    Un objet aarch64 de la chaine llvm-mingw porte une section
    « .obj.arm64ec » : un objet COFF complet, la variante ARM64EC du meme code,
    que l'editeur de liens extrait pour une cible arm64ec. C'est *celle-la* que
    DXVK et les executables ARM64EC recoivent -- ne patcher que l'objet
    exterieur ne changeait rien au binaire produit.
    """
    for nom, ptr, brut in sections(d, base):
        if nom.startswith(".text"):
            yield ptr, brut
        elif nom == ".obj.arm64ec":
            yield from sections_texte(d, ptr)


def corriger(chemin):
    d = bytearray(open(chemin, "rb").read())
    n = 0
    for ptr, brut in sections_texte(d):
        i = ptr
        fin = ptr + (brut & ~3)
        while i + 4 <= fin:
            mot, = struct.unpack_from("<I", d, i)
            reg = mov_de_x18(mot)
            if reg is not None:
                # chercher le ldr correspondant dans les quatre instructions qui suivent
                j, cible = i + 4, None
                while j < min(i + 20, fin):
                    suite, = struct.unpack_from("<I", d, j)
                    dst = ldr_8_de(suite, reg)
                    if dst is not None:
                        cible = (j, dst); break
                    j += 4
                if cible is None:
                    print(f"   {os.path.basename(chemin)}+{i-ptr:#x} : mov x{reg}, x18 sans ldr [+8] -- laisse")
                else:
                    j, dst = cible
                    struct.pack_into("<I", d, i, 0xD53BD060 | reg)          # mrs xreg, tpidrro_el0
                    struct.pack_into("<I", d, j, 0xAA0003E0 | (reg << 16) | dst)  # mov xdst, xreg
                    n += 1
            i += 4
    return d, n

def main(lib):
    total = 0
    for nom in CIBLES:
        p = os.path.join(lib, nom)
        if not os.path.exists(p):
            print(f"   {nom} absent, ignore"); continue
        orig = p + ".x18.orig"
        if not os.path.exists(orig):
            shutil.copy2(p, orig)
        d, n = corriger(orig)          # toujours depuis l'original : idempotent
        if n:
            open(p, "wb").write(d)
        print(f"   {nom} : {n} site(s) corrige(s)")
        total += n
    print(f"{total} site(s) au total")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else
                  os.path.expanduser("~/Dev/cidre/toolchain/llvm-mingw/aarch64-w64-mingw32/lib")))
