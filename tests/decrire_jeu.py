#!/usr/bin/env python3
"""Decrit un executable Windows : architecture, bit no-exec, API graphique.

    decrire_jeu.py jeu.exe [autre.exe ...]

L'architecture dit si le jeu passe par la transition WoW64 32/64 bits, le bit
NX_COMPAT si le processus va desarmer le no-exec, et les DLL importees quelle
couche de la pile le jeu va exercer.
"""
import struct
import sys
import os

MACHINE = {0x014c: "32 bits (i386)", 0x8664: "64 bits (x86_64)", 0xaa64: "64 bits (ARM64)"}
GRAPHIQUE = ("d3d8", "d3d9", "d3d10", "d3d11", "d3d12", "dxgi", "opengl32", "vulkan")


def lire(chemin):
    with open(chemin, "rb") as f:
        d = f.read()

    e = struct.unpack_from("<I", d, 0x3C)[0]
    if d[e:e + 4] != b"PE\0\0":
        return None

    machine, nsec = struct.unpack_from("<HH", d, e + 4)
    magic = struct.unpack_from("<H", d, e + 24)[0]
    dc = struct.unpack_from("<H", d, e + 24 + 70)[0]
    dir_off = e + 24 + (96 if magic == 0x10B else 112)
    imp_rva = struct.unpack_from("<I", d, dir_off + 8)[0]

    sections = []
    off = e + 24 + struct.unpack_from("<H", d, e + 20)[0]
    for i in range(nsec):
        va, _, raw_sz, raw_off = struct.unpack_from("<IIII", d, off + i * 40 + 12)
        sections.append((va, raw_sz, raw_off))

    def vers_offset(rva):
        for va, sz, raw in sections:
            if va <= rva < va + sz:
                return raw + rva - va
        return None

    dlls = []
    o = vers_offset(imp_rva)
    if o is not None:
        while True:
            nom_rva = struct.unpack_from("<I", d, o + 12)[0]
            if nom_rva == 0:
                break
            n = vers_offset(nom_rva)
            if n is None:
                break
            fin = d.index(b"\0", n)
            dlls.append(d[n:fin].decode("latin1"))
            o += 20

    return machine, dc, dlls


def est_installeur(chemin):
    """Un installeur GOG est lui-meme un binaire 32 bits : son architecture ne dit
    rien de celle du jeu qu'il contient. Mieux vaut le signaler que laisser conclure."""
    brut = open(chemin, "rb").read(4 << 20)
    for marque in (b"Inno Setup", b"InnoSetupLdr", b"Nullsoft.NSIS", b"This installation was built with"):
        if marque in brut:
            return True
    return False


def nommer_api(chemin, importees):
    """Les jeux chargent souvent Direct3D par LoadLibrary : on cherche les noms
    de DLL dans tout le fichier, pas seulement dans la table d'imports."""
    brut = open(chemin, "rb").read().lower()
    noms = ["d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll",
            "d3d12.dll", "dxgi.dll", "opengl32.dll", "vulkan-1.dll"]
    trouve = [n for n in noms if brut.find(n.encode()) >= 0]
    trouve += [n.lower() for n in importees if n.lower() in noms and n.lower() not in trouve]
    for n in range(24, 44):
        if brut.find(f"d3dx9_{n}.dll".encode()) >= 0:
            trouve.append(f"d3dx9_{n}.dll")
            break
    return trouve


def deplier(args):
    """Un repertoire est parcouru : l'executable interesse, mais aussi les DLL,
    puisqu'un seul module sans NX_COMPAT desarme le no-exec de tout le processus."""
    sortie = []
    for a in args:
        if os.path.isdir(a):
            for racine, _, fichiers in os.walk(a):
                for f in sorted(fichiers):
                    if f.lower().endswith((".exe", ".dll")):
                        sortie.append(os.path.join(racine, f))
        else:
            sortie.append(a)
    return sortie


def main(args):
    if not args:
        print(__doc__)
        return 2
    sans_nx = []
    for chemin in deplier(args):
        res = lire(chemin)
        print(f"=== {os.path.basename(chemin)} ===")
        if res is None:
            print("  ce n'est pas un executable Windows")
            continue
        machine, dc, dlls = res
        if est_installeur(chemin):
            print("  C'EST UN INSTALLEUR, pas le jeu. Son architecture est celle de")
            print("  l'installeur, pas celle du jeu. Extraire d'abord :")
            print(f"    innoextract -d /tmp/jeu \"{chemin}\"")
            print("  puis relancer cet outil sur le repertoire obtenu.")
            continue
        nx = "oui" if dc & 0x0100 else "NON — desarme le no-exec du processus"
        gfx = sorted(set(nommer_api(chemin, dlls)))
        print(f"  architecture : {MACHINE.get(machine, hex(machine))}")
        print(f"  NX_COMPAT    : {nx}")
        print(f"  graphique    : {', '.join(gfx) if gfx else 'aucune'}")
        if not dc & 0x0100:
            sans_nx.append(os.path.basename(chemin))
    if sans_nx:
        print()
        print("Modules sans NX_COMPAT (ils desarment le no-exec du processus,")
        print("ce que le correctif 0062 rattrape) : " + ", ".join(sans_nx))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
