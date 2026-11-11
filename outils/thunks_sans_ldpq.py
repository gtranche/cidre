#!/usr/bin/env python3
"""Cidre, ilot TSO : extrait les thunks d'entree Arm64EC ($ientry_thunk$...) de fichiers assembleur produits par clang -S,
les dedoublonne, recoud leurs `ldp qA, qB` d'epilogue en deux `ldr q` (+ add sp) avec les directives SEH, et ecrit un
seul fichier assembleur. Lie en tete, ses sections COMDAT (discard) l'emportent sur celles des objets ordinaires.
Usage : thunks_sans_ldpq.py sortie.s entree.s [entree.s...]"""
import re, sys
out, ins = sys.argv[1], sys.argv[2:]
vus = {}
for f in ins:
    L = open(f, errors="replace").read().split("\n")
    k = 0
    while k < len(L):
        m = re.match(r"^\t\.def\t(\$ientry_thunk\$[^;]*);$", L[k])
        if m and m.group(1) not in vus:
            j = k
            while not L[j].startswith("\t.seh_endproc"): j += 1
            vus[m.group(1)] = L[k:j + 1]; k = j + 1; continue
        k += 1
P = re.compile(r"^\tldp\tq(\d+), q(\d+), \[sp(?:, #(-?\d+))?\](, #(\d+))?(\s*//.*)?$")
R = ["\t.text"]; n = 0
for idx, (nom, B) in enumerate(vus.items()):
    B = [re.sub(r"\.L(\w+)", lambda m: f".Lt{idx}_{m.group(1)}", x) for x in B]
    epi = False; k = 0
    while k < len(B):
        l = B[k]
        if "\t.seh_startepilogue" in l: epi = True
        if "\t.seh_endepilogue" in l: epi = False
        m = P.match(l)
        if m and epi:
            a, b, off, post, pv = m.group(1), m.group(2), int(m.group(3) or 0), m.group(4), m.group(5)
            seh = B[k + 1] if k + 1 < len(B) else ""
            assert re.match(r"^\t\.seh_save_any_reg_px?\tq" + a + r", \d+$", seh), (nom, seh)
            if post:
                R += [f"\tldr\tq{b}, [sp, #16]", f"\t.seh_save_any_reg\tq{b}, 16", f"\tldr\tq{a}, [sp]", f"\t.seh_save_any_reg\tq{a}, 0",
                      f"\tadd\tsp, sp, #{pv}", f"\t.seh_stackalloc\t{pv}"]
            else:
                R += [f"\tldr\tq{b}, [sp, #{off + 16}]", f"\t.seh_save_any_reg\tq{b}, {off + 16}",
                      f"\tldr\tq{a}, [sp, #{off}]", f"\t.seh_save_any_reg\tq{a}, {off}"]
            n += 1; k += 2; continue
        R.append(re.sub(r'^(\t\.section\t)([^",\s]*[#$][^",\s]*)(,|$)', r'\1"\2"\3', l))
        k += 1
open(out, "w").write("\n".join(R) + "\n")
print(len(vus), "thunks,", n, "ldp q recousus", file=sys.stderr)
