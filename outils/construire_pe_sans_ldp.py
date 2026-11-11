#!/usr/bin/env python3
"""Cidre, ilot TSO : DLL PE ARM64X de Wine recompilees sans les ldp/stp formes par l'optimiseur
(-mllvm -aarch64-enable-ldst-opt=false) : sous le bit TSO materiel d'un vCPU de l'ilot, un ldp q coute 11 a 14 fois
plus qu'en dehors. Les deux drapeaux TEB (-DWINE_TEB_SANS_X18) sont passes, comme pour toute cible PE du depot.

Usage : construire_pe_sans_ldp.py --build <build/wine11-arm64-ec> --src <src/wine11> --sortie <dossier>
                                   [--toolchain <llvm-mingw/bin>] [--normal] [--thunks] <dll> [<dll>...]
  --normal  sans le drapeau (controle de la methode : redonne a l'octet pres la taille et le nombre de ldp q des DLL
            du build)
  --thunks  les thunks d'entree Arm64EC ($ientry_thunk$...) sont recompiles en assembleur, leurs ldp q d'epilogue
            recousus en ldr q (thunks_sans_ldpq.py) et lies en tete : leurs COMDAT l'emportent. Assembles en cible
            MSVC (0309) : en cible mingw, leurs tables de deroulement tombaient dans un seul bloc .pdata$aa que
            l'editeur de liens ARM64X ne compte pas, et toute exception C++ ou RaiseException depuis du code x86 qui
            traversait un thunk tombait sur la garde 0119 (code 67).
Rien n'est ecrit dans le build : objets et DLL dans --sortie (obj-<dll>/, <dll>.dll).
DLL de l'ilot de Diablo IV : ntdll kernelbase kernel32 ucrtbase msvcrt, avec --thunks (INTEGRATION_D4.md).
Repris de ~/Dev/cidre-fex-banc/dossier-ilot-defaut/outils (31/10) ; les sources pe19 de ntdll (signal_arm64ec.c,
string.c, time.c, exception.c) sont maintenant dans la serie (wine11 0290, 0301) : plus de substitution."""
import os, re, subprocess, sys

def arg(nom, defaut=None):
    if nom in sys.argv:
        i = sys.argv.index(nom)
        v = sys.argv[i + 1]
        del sys.argv[i:i + 2]
        return v
    return defaut

B = os.path.abspath(arg("--build") or sys.exit("--build manquant"))
S = os.path.abspath(arg("--src") or sys.exit("--src manquant"))
OUT = os.path.abspath(arg("--sortie") or sys.exit("--sortie manquant"))
TC = arg("--toolchain", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "toolchain", "llvm-mingw", "bin"))
normal = "--normal" in sys.argv
thk = "--thunks" in sys.argv
dlls = [a for a in sys.argv[1:] if not a.startswith("--")]
if not dlls:
    sys.exit(__doc__)
ICI = os.path.dirname(os.path.abspath(__file__))
X = "" if normal else " -mllvm -aarch64-enable-ldst-opt=false"
env = dict(os.environ, PATH=f"{os.path.abspath(TC)}:/usr/bin:/bin:/usr/sbin:/sbin")
VARS = {"aarch64_CC": "aarch64-w64-mingw32-clang -D__STDC__", "arm64ec_CC": "arm64ec-w64-mingw32-clang -D__STDC__",
        "aarch64_CFLAGS": "-g -O2 -DWINE_TEB_SANS_X18" + X, "arm64ec_CFLAGS": "-g -O2 -DWINE_TEB_SANS_X18" + X,
        "LDFLAGS": "", "CFLAGS": "-g -O2", "arm64ec_LDFLAGS": "--no-default-config -Wl,-debug:dwarf -Wl,--build-id",
        "aarch64_LDFLAGS": "--no-default-config -Wl,-debug:dwarf -Wl,--build-id"}
lignes = open(f"{B}/Makefile").read().split("\n")

def bloc(cible):
    """dependances et recette d'une cible du Makefile genere par makedep"""
    i = next(k for k, l in enumerate(lignes) if l.startswith(cible + ":"))
    deps = ""
    while not lignes[i].startswith("\t"):
        deps += lignes[i].rstrip("\\") + " "
        i += 1
    r = ""
    while True:
        r += lignes[i].lstrip("\t").rstrip("\\") + " "
        if not lignes[i].endswith("\\"):
            break
        i += 1
    return deps, r

def dev(cmd, sortie):
    cmd = cmd.replace("$@", sortie)
    for k, v in VARS.items():
        cmd = cmd.replace(f"$({k})", v)
    assert "$(" not in cmd, re.findall(r"\$\([^)]*\)", cmd)
    return cmd

def attendre(procs):
    for p in procs:
        e = p.communicate()[1]
        assert p.returncode == 0, e.decode()[-2000:]

os.makedirs(OUT, exist_ok=True)
for d in dlls:
    tag = d + ("-normal" if normal else "")
    O = f"{OUT}/obj-{tag}"
    os.makedirs(O, exist_ok=True)
    deps, lien = bloc(f"dlls/{d}/aarch64-windows/{d}.dll")
    objs = sorted(set(re.findall(rf"dlls/{re.escape(d)}/(?:aarch64|arm64ec)-windows/[\w.-]+\.o", deps + lien)))
    procs = []
    for o in objs:
        _, r = bloc(o)
        if "$(x86_64_CC)" in r:
            continue  # objet x86-64 du build (signal_x86_64.o) : garde tel quel, lu seulement
        so = f"{O}/{o.replace('/', '_')}"
        procs.append(subprocess.Popen(dev(r, so), shell=True, cwd=B, env=env, stderr=subprocess.PIPE))
        lien = lien.replace(o + " ", so + " ")
        if len(procs) >= 6:
            attendre(procs)
            procs = []
    attendre(procs)
    if thk and not normal:
        ss = []
        for o in objs:
            if "/arm64ec-windows/" not in o:
                continue
            _, r = bloc(o)
            if "$(x86_64_CC)" in r or not re.search(r"\.c\s", r + " "):
                continue
            s = f"{O}/{o.replace('/', '_')}.s"
            subprocess.run(dev(r, s).replace(" -c ", " -S ", 1), shell=True, cwd=B, env=env, check=True,
                           stderr=subprocess.DEVNULL)
            ss.append(s)
        subprocess.run([sys.executable, "-I", f"{ICI}/thunks_sans_ldpq.py", f"{O}/thunks.s"] + ss, check=True)
        subprocess.run(f"clang --target=arm64ec-pc-windows-msvc -c {O}/thunks.s -o {O}/thunks.o", shell=True, env=env,
                       check=True)
        premier = re.search(rf"dlls/{re.escape(d)}/arm64ec-windows/[\w.-]+\.o|{re.escape(O)}/dlls_{re.escape(d)}_arm64ec-windows_[\w.-]+\.o",
                            lien).group(0)
        lien = lien.replace(premier + " ", f"{O}/thunks.o {premier} ", 1)
    sortie = f"{OUT}/{tag}.dll"
    subprocess.run(dev(lien, sortie), shell=True, cwd=B, env=env, check=True)
    print("ok", sortie, len(objs), "objets")
