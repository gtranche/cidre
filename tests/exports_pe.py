"""Lire le repertoire d'export d'un PE : nom -> adresse relative.

objdump n'affiche que l'index du nom, pas son adresse ; pour relier les deux il
faut parcourir la table des ordinaux. Ce module sert a exploiter les enveloppes
plates de steam_api.dll, qui donnent a la fois le nom des methodes et leur
disposition de pile.
"""
import struct, sys


def exports(chemin):
    d = open(chemin, "rb").read()
    (pe,) = struct.unpack_from("<I", d, 0x3C)
    magie, = struct.unpack_from("<H", d, pe + 24)
    est64 = magie == 0x20B
    nb_sections, = struct.unpack_from("<H", d, pe + 6)
    taille_opt, = struct.unpack_from("<H", d, pe + 20)
    base_opt = pe + 24
    rep = base_opt + (112 if est64 else 96)          # DataDirectory[0] = export
    exp_rva, exp_taille = struct.unpack_from("<II", d, rep)

    sections = []
    off = base_opt + taille_opt
    for i in range(nb_sections):
        s = d[off + 40 * i: off + 40 * (i + 1)]
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", s, 8)
        sections.append((vaddr, vsize, raddr))

    def brut(rva):
        for vaddr, vsize, raddr in sections:
            if vaddr <= rva < vaddr + max(vsize, 1):
                return raddr + (rva - vaddr)
        return None

    e = brut(exp_rva)
    nb_fonctions, nb_noms = struct.unpack_from("<II", d, e + 20)
    a_fonctions, a_noms, a_ordinaux = struct.unpack_from("<III", d, e + 28)
    tf, tn, to = brut(a_fonctions), brut(a_noms), brut(a_ordinaux)

    res = {}
    for i in range(nb_noms):
        rva_nom, = struct.unpack_from("<I", d, tn + 4 * i)
        p = brut(rva_nom)
        nom = d[p:d.index(b"\0", p)].decode("ascii", "replace")
        ordinal, = struct.unpack_from("<H", d, to + 2 * i)
        rva, = struct.unpack_from("<I", d, tf + 4 * ordinal)
        res[nom] = rva
    return res


if __name__ == "__main__":
    for nom, rva in sorted(exports(sys.argv[1]).items()):
        print("%08x %s" % (rva, nom))
