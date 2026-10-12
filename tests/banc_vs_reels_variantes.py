#!/usr/bin/env python3
# Banc « vrais vertex shaders » : extraction et variantes.
#
# Lit le cache de shaders de DXMT (SQLite, metallibs produits par airconv), en
# sort les vertex shaders d'un jeu et fabrique pour chacun des variantes du
# MEME code AIR, retouche au niveau de l'IR LLVM (llvm@15 de Homebrew, celui
# d'airconv) puis remis en metallib par l'outil `metallib` de Xcode :
#
#   a  shader complet. Seule la position finale est remplacee par une position
#      synthetique (lue dans le tampon « banc », a l'ecran) ; la vraie position
#      calculee part dans un puits (somme entiere masquee par un mot lu a
#      l'execution : le compilateur ne peut pas l'eliminer).
#   b  sorties reduites a SV_Position (+ distances de decoupe) : tous les
#      varyings partent dans le puits, l'arithmetique reste entiere. (Chaque
#      valeur passe par `freeze` : les voies non ecrites d'un registre de sortie
#      sont undef et rendraient tout le puits undef, donc tout le code mort.)
#   c  memes sorties que a, mais alimentees directement par les attributs lus
#      (passthrough) : l'arithmetique et les lectures uniformes sont retirees
#      par elimination de code mort (opt -passes=sroa,adce,simplifycfg).
#   d  lecture des attributs seule : sorties de b, valeurs de c.
#   e  comme a, mais chaque lecture `texture_buffer` (Buffer<T>, GPUScene)
#      devient un chargement direct en memoire device (borne haute de ce que
#      rapporterait une lecture directe des tampons types, cf. 0113).
#
# Variantes d'essai (a demander par --variantes), toutes a arithmetique entiere :
#   kN  seuls les N premiers varyings restent des sorties, le reste au puits
#   oN  seul le N-ieme varying reste une sortie
#   w   sorties de a et puits de b a la fois (controle : b calcule-t-il tout ?)
#   n   a sans puits (la vraie position devient du code mort)
#   p   sorties de c (passthrough) et puits de b
#   q   comme p, mais les valeurs ecrites ne sont lues qu'en fin de fonction
#   qN  q avec seulement N composantes definies par varying (le reste undef)
#   tN  q avec des varyings declares a N composantes (type de sortie du VS et
#       entree du fragment shader)
#   rX  variante X avec le puits accumule dans l'ordre inverse des sorties
#   zX  variante X repassee par opt -O2 de LLVM 15 avant l'assemblage
#
# Controle du puits : banc_vs_reels_metal --masque 0xffffffff --remplissages 1 ;
# la geometrie doit changer (temps de fragments different) pour a, b, c et d,
# sinon le compilateur de Metal a replie le puits et la variante ne mesure rien.
#
# « attribut lu » = chargement device ou lecture de texture dont l'adresse
# depend de la table des tampons de sommets ou de l'identifiant de sommet par
# de l'arithmetique seule (premier niveau) ; une lecture dont l'index vient
# d'une autre lecture (GPUScene, os du skinning) compte comme arithmetique.
#
# Usage :
#   banc_vs_reels_variantes.py extraire --db shaders_320.db --out DOSSIER
#   banc_vs_reels_variantes.py variantes --out DOSSIER [--seulement h1,h2] [--max N]
#                                        [--variantes a,b,k4,p] [--suffixe=-essais]
#   banc_vs_reels_variantes.py rapport --out DOSSIER   (tableaux a partir des mesures)
# Sorties : DOSSIER/src (metallib, .ll d'origine), DOSSIER/var (variantes,
# fragment shaders), DOSSIER/inventaire.tsv, DOSSIER/manifeste.tsv.
import argparse
import collections
import concurrent.futures
import hashlib
import os
import re
import sqlite3
import struct
import subprocess
import sys

LLVM = os.environ.get("LLVM15", "/opt/homebrew/opt/llvm@15/bin")
DEVELOPER_DIR = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
VARIANTES = ["a", "b", "c", "d", "e"]
# Emplacements des deux tampons ajoutes a chaque variante (hors des index 0-2
# de DXMT : table des cbuffers, table d'arguments, table des tampons de sommets).
BANC_INDEX = 30   # mot de masque (0) puis une position float4 par sommet
BANCD_INDEX = 29  # donnees lues par la variante e a la place des texture_buffer


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise RuntimeError("%s\n%s" % (" ".join(cmd), r.stderr[-2000:]))
    return r.stdout


# ---------------------------------------------------------------- extraction

def extraire(db, out):
    src = os.path.join(out, "src")
    os.makedirs(src, exist_ok=True)
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    table = [r[0] for r in con.execute("select name from sqlite_master where type='table' and name like 'cache_%'")]
    if not table:
        sys.exit("pas de table cache_* dans %s" % db)
    n = 0
    for (val,) in con.execute("select value from %s" % table[0]):
        if val[:4] != b"MTLB":
            continue
        i = val.find(b"NAME")
        ln = struct.unpack_from("<H", val, i + 4)[0]
        nom = val[i + 6:i + 6 + ln - 1].decode()
        if not nom.startswith("vs_"):
            continue
        hdr = struct.unpack_from("<4s6H9Q", val, 0)
        off, taille = hdr[14], hdr[15]
        bc = val[off:off + taille]
        if bc[:4] not in (b"BC\xc0\xde", b"\xde\xc0\x17\x0b"):
            continue
        p = os.path.join(src, nom)
        if not os.path.exists(p + ".ll"):
            open(p + ".metallib", "wb").write(val)
            open(p + ".bc", "wb").write(bc)
            run([LLVM + "/llvm-dis", p + ".bc", "-o", p + ".ll"])
            os.remove(p + ".bc")
        n += 1
    print("%d vertex shaders extraits dans %s" % (n, src))
    inventaire(out)


def inventaire(out):
    src = os.path.join(out, "src")
    lignes = []
    for f in sorted(os.listdir(src)):
        if not f.endswith(".ll"):
            continue
        s = open(os.path.join(src, f)).read()
        # Variantes d'options ecartees : fastMath (drapeaux sur les operations
        # flottantes) et l'essai 0113 (champs raw_t en queue de table).
        if "raw_t" in s or re.search(r"= f(add|mul|sub|div) [a-z ]*(reassoc|contract|fast)", s):
            continue
        try:
            m = Module(s)
        except Exception as e:  # forme inattendue : on le dit et on passe
            print("ignore %s : %s" % (f, e), file=sys.stderr)
            continue
        corps = "\n".join(m.corps)
        lignes.append(dict(
            nom=m.nom, dxbc=m.nom.split("_")[1], classe=m.classe(), varyings=m.nvar(),
            instr=sum(1 for l in m.corps if l.startswith("  ")),
            lect_tb=corps.count("@air.read_texture_buffer"),
            echant=corps.count("@air.sample_") + corps.count("@air.gather_"),
            tirages=len(re.findall(r"load i8 addrspace\(1\)\*, i8 addrspace\(1\)\* addrspace\(2\)\*", corps)),
            branches=len(re.findall(r"^  (br i1|switch) ", corps, re.M)),
            attributs=len(m.attributs()), attributs_cond=len(m.attributs(True))))
    cols = ["nom", "dxbc", "classe", "varyings", "instr", "lect_tb", "echant", "tirages", "branches", "attributs", "attributs_cond"]
    with open(os.path.join(out, "inventaire.tsv"), "w") as f:
        f.write("\t".join(cols) + "\n")
        for l in lignes:
            f.write("\t".join(str(l[c]) for c in cols) + "\n")
    print("%d variantes par defaut, %d DXBC -> %s/inventaire.tsv" % (len(lignes), len(set(l["dxbc"] for l in lignes)), out))


# ------------------------------------------------------------------ module IR

class Module:
    def __init__(self, texte):
        m = re.search(r"^define (.+?) @(vs_\w+)\((.*)\) local_unnamed_addr \{$", texte, re.M)
        if not m:
            raise ValueError("pas de fonction vs_")
        self.ret, self.nom = m.group(1), m.group(2)
        self.args = [(a.rsplit(" ", 1)[0], a.rsplit(" ", 1)[1]) for a in m.group(3).split(", ")]
        fin = texte.index("\n}\n", m.end())
        self.avant = texte[:m.start()]
        self.corps = texte[m.end() + 1:fin].split("\n")
        self.apres = texte[fin + 3:]
        if not self.ret.startswith("<{ ") or sum(1 for l in self.corps if l.startswith("  ret ")) != 1:
            raise ValueError("retour inattendu")
        self.elems = self.ret[3:-3].split(", ")
        self.md = dict(re.findall(r"^!(\d+) = (.*)$", self.apres, re.M))
        racine = re.search(r"^!air\.vertex = !\{!(\d+)\}$", self.apres, re.M).group(1)
        self.racine = racine
        mo = re.match(r"^!\{.* @vs_\w+, !(\d+), !(\d+)\}$", self.md[racine])
        self.id_sorties, self.id_entrees = mo.group(1), mo.group(2)
        self.sorties = []
        for i in re.findall(r"!(\d+)", self.md[self.id_sorties]):
            t = self.md[i]
            genre = re.match(r'!\{!"air\.(\w+)"', t).group(1)
            self.sorties.append(dict(
                id=i, genre=genre,
                type=re.search(r'"air.arg_type_name", !"([^"]+)"', t).group(1),
                user=(re.search(r'!"(user\([^"]+\))"', t) or [None, None])[1]))
        if len(self.sorties) != len(self.elems):
            raise ValueError("sorties et type de retour ne correspondent pas")
        self.vid = self.vb = None
        for i in re.findall(r"!(\d+)", self.md[self.id_entrees]):
            t = self.md[i]
            idx = int(re.match(r"!\{i32 (\d+)", t).group(1))
            if '"air.vertex_id"' in t:
                self.vid = self.args[idx][1]
            if '"air.arg_name", !"vertex_buffers"' in t:
                self.vb = self.args[idx][1]
        if self.vid is None:
            raise ValueError("pas d'identifiant de sommet")

    def nvar(self):
        return sum(1 for s in self.sorties if s["genre"] == "vertex_output")

    def classe(self):
        n = self.nvar()
        return "profondeur" if n == 0 else "ombres" if n <= 3 else "base" if n >= 6 else "autre"

    def defs(self):
        d = {}
        for i, l in enumerate(self.corps):
            m = re.match(r"  (%[\w.]+) = (.*)$", l)
            if m:
                d[m.group(1)] = (i, m.group(2))
        return d

    def blocs_inconditionnels(self):
        """Index de ligne -> vrai si l'instruction est executee pour tout sommet.

        Un bloc est inconditionnel s'il post-domine l'entree ; le bloc « alors »
        du test de nullite que DXMT pose devant chaque tirage d'attribut
        (base == null -> 0) est admis quand le bloc du test l'est.
        """
        blocs, cur = [], None
        for i, l in enumerate(self.corps):
            mo = re.match(r"^([\w.]+):", l)
            if mo or cur is None:
                cur = dict(nom=mo.group(1) if mo else "", debut=i, succ=[], term="")
                blocs.append(cur)
                if mo:
                    continue
            cur["fin"] = i
            if re.match(r"  (br|switch|ret|unreachable)\b", l):
                cur["term"] = l
            if cur["term"]:
                cur["succ"] += re.findall(r"label %([\w.]+)", l)
        noms = [b["nom"] for b in blocs]
        tout = set(noms)
        pdom = {n: set(tout) for n in noms}
        change = True
        while change:
            change = False
            for b in reversed(blocs):
                s = [pdom[x] for x in b["succ"]]
                n = ({b["nom"]} | set.intersection(*s)) if s else {b["nom"]}
                if n != pdom[b["nom"]]:
                    pdom[b["nom"]] = n
                    change = True
        incond = set(pdom[noms[0]])
        d = self.defs()
        preds = collections.defaultdict(list)
        for b in blocs:
            for x in b["succ"]:
                preds[x].append(b)
        for b in blocs:
            p = preds[b["nom"]]
            if b["nom"] in incond or len(p) != 1 or p[0]["nom"] not in incond:
                continue
            mo = re.match(r"  br i1 (%[\w.]+),", p[0]["term"])
            if mo and mo.group(1) in d and re.match(r"icmp eq i8 addrspace\(1\)\* %[\w.]+, null", d[mo.group(1)][1]):
                incond.add(b["nom"])
        res = {}
        for b in blocs:
            for i in range(b["debut"], b.get("fin", b["debut"]) + 1):
                res[i] = b["nom"] in incond
        return res

    def attributs(self, conditionnels=False):
        """Lectures d'attributs : [(ligne apres laquelle inserer, valeur, type)].

        Par defaut seulement celles executees pour tout sommet ; les lectures
        par sommet placees sous une condition de donnees (cibles de morphing,
        decoupes de sprites...) comptent comme arithmetique.
        """
        d = self.defs()
        incond = self.blocs_inconditionnels()
        noms = set(d) | set(a[1] for a in self.args)
        ops = {n: [t for t in re.findall(r"%[\w.]+", rhs) if t in noms] for n, (i, rhs) in d.items()}
        util = collections.defaultdict(list)
        for n, o in ops.items():
            for t in set(o):
                util[t].append(n)
        teinte = {self.vid} | ({self.vb} if self.vb else set())
        lect = {}
        change = True
        while change:
            change = False
            for n, (i, rhs) in d.items():
                if n in teinte or n in lect or not any(t in teinte for t in ops[n]):
                    continue
                m = re.match(r"load (.+?), \1 addrspace\(1\)\* %", rhs)
                if m:
                    lect[n] = m.group(1)
                elif re.match(r"(tail )?call .* @air\.(read|sample|gather)_texture", rhs):
                    lect[n] = re.match(r"(?:tail )?call (.+?) @air", rhs).group(1)
                else:
                    teinte.add(n)
                change = True
        res = []
        for n, ty in sorted(lect.items(), key=lambda kv: d[kv[0]][0]):
            if incond[d[n][0]] == conditionnels:
                continue
            # La conversion de format (unpack, demi-flottants) fait partie de la lecture.
            while len(util[n]) == 1:
                m = re.match(r"(?:tail )?call (.+?) @air\.(unpack|convert)\.", d[util[n][0]][1])
                if not m:
                    break
                n, ty = util[n][0], m.group(1)
            res.append((d[n][0], n, ty))
        return res


def vers_4i32(out, v, ty, tag):
    """Emet la conversion de v vers <4 x i32> ; renvoie le nom, ou None."""
    m = re.match(r"^\{ (<4 x (?:float|i32)>), i8 \}$", ty)
    if m:
        out.append("  %%%s.e = extractvalue %s %s, 0" % (tag, ty, v))
        v, ty = "%%%s.e" % tag, m.group(1)
    m = re.match(r"^\[\d+ x (float|i32)\]$", ty)
    if m:
        out.append("  %%%s.a = extractvalue %s %s, 0" % (tag, ty, v))
        v, ty = "%%%s.a" % tag, m.group(1)
    m = re.match(r"^<(\d) x (float|half|i32|i16|i8)>$", ty)
    if m:
        n, e = int(m.group(1)), m.group(2)
    elif ty in ("float", "half", "i32", "i16", "i8", "i64"):
        n, e = 1, ty
    else:
        return None
    bits = {"float": 32, "half": 16, "i32": 32, "i16": 16, "i8": 8, "i64": 64}[e]
    vt = lambda et: et if n == 1 else "<%d x %s>" % (n, et)
    if e in ("float", "half"):
        out.append("  %%%s.b = bitcast %s %s to %s" % (tag, vt(e), v, vt("i%d" % bits)))
        v = "%%%s.b" % tag
    if bits != 32:
        out.append("  %%%s.z = %s %s %s to %s" % (tag, "zext" if bits < 32 else "trunc", vt("i%d" % bits), v, vt("i32")))
        v = "%%%s.z" % tag
    if n == 1:
        out.append("  %%%s.v = insertelement <4 x i32> zeroinitializer, i32 %s, i64 0" % (tag, v))
        v = "%%%s.v" % tag
    elif n < 4:
        masque = ", ".join("i32 %d" % min(i, n) for i in range(4))
        out.append("  %%%s.v = shufflevector <%d x i32> %s, <%d x i32> zeroinitializer, <4 x i32> <%s>" % (tag, n, v, n, masque))
        v = "%%%s.v" % tag
    return v


def variante(m, v):
    """Variante v du module m : (texte .ll, passes opt a appliquer ou None, nombre de
    texture_buffer remplaces, index des sorties gardees, largeur des varyings)."""
    corps = list(m.corps)
    iret = next(i for i, l in enumerate(corps) if l.startswith("  ret "))
    val_ret = corps[iret].rsplit(" ", 1)[1]
    essai = v
    voies = 4
    largeur = 4
    if v[0] == "t":  # essai tN : q avec des varyings declares a N composantes (type de sortie et entree du fragment)
        largeur, v = int(v[1:]), "q"
    if v[0] == "q" and len(v) > 1:  # essai qN : q avec N composantes definies par varying, le reste undef
        voies, v = int(v[1:]), "q"
    if v[0] == "r":
        v = v[1:] or "b"
    if v[0] == "z":  # essai : za = a repasse par opt -O2 de LLVM 15 (zb = b, etc.)
        v = v[1:] or "a"
    reduit = v in "bd"
    garde = [i for i, s in enumerate(m.sorties) if not (reduit and s["genre"] == "vertex_output")]
    if v[0] == "k":  # essai : arithmetique entiere, seuls les n premiers varyings restent des sorties
        vus = 0
        garde = []
        for i, s in enumerate(m.sorties):
            if s["genre"] == "vertex_output":
                vus += 1
                if vus > int(v[1:]):
                    continue
            garde.append(i)
    if v[0] == "o":  # essai : arithmetique entiere, seul le n-ieme varying reste une sortie
        vus = 0
        garde = []
        for i, s in enumerate(m.sorties):
            if s["genre"] == "vertex_output":
                vus += 1
                if vus != int(v[1:]):
                    continue
            garde.append(i)
    if v == "w":     # essai : sorties de a ET puits de b
        garde = list(range(len(m.sorties)))
    ep = []
    ep.append("  %banc.mp = bitcast i8 addrspace(1)* %banc to i32 addrspace(1)*")
    ep.append("  %banc.m = load i32, i32 addrspace(1)* %banc.mp, align 4")
    ep.append("  %%banc.v64 = zext i32 %s to i64" % m.vid)
    ep.append("  %banc.o1 = shl i64 %banc.v64, 4")
    ep.append("  %banc.o2 = add i64 %banc.o1, 16")
    ep.append("  %banc.pp = getelementptr i8, i8 addrspace(1)* %banc, i64 %banc.o2")
    ep.append("  %banc.pq = bitcast i8 addrspace(1)* %banc.pp to <4 x float> addrspace(1)*")
    ep.append("  %banc.pos = load <4 x float>, <4 x float> addrspace(1)* %banc.pq, align 4")
    ep.append("  %banc.pb = bitcast <4 x float> %banc.pos to <4 x i32>")
    types_etroits = {}  # essai tN : index de sortie -> type reduit
    puits = []      # valeurs <4 x i32> a absorber
    valeurs = {}    # index de sortie -> valeur a ecrire
    inserts = collections.defaultdict(list)  # ligne -> lignes a inserer apres
    entete = []
    # essais p et q : arithmetique de b (puits de toutes les vraies sorties) et
    # sorties sans rapport avec elle, lues au debut (p, comme c) ou a la fin (q)
    passthrough = v in "cdpq"
    nslots = 0
    if passthrough:
        attrs = m.attributs()
        nslots = max(1, min(max(1, m.nvar()), len(attrs)))
        for j in range(nslots):
            entete.append("  %%banc.slot%d = alloca <4 x i32>, align 16" % j)
        for j in range(nslots):
            entete.append("  store <4 x i32> zeroinitializer, <4 x i32>* %%banc.slot%d, align 16" % j)
        k = 0
        for (ligne, nom, ty) in attrs:
            tmp = []
            x = vers_4i32(tmp, nom, ty, "banc.f%d" % k)
            if x is None:
                print("  %s : attribut de type %s ignore" % (m.nom, ty), file=sys.stderr)
                continue
            j = k % nslots
            tmp.append("  %%banc.f%d.o = load <4 x i32>, <4 x i32>* %%banc.slot%d, align 16" % (k, j))
            tmp.append("  %%banc.f%d.m = mul <4 x i32> %%banc.f%d.o, <i32 33, i32 33, i32 33, i32 33>" % (k, k))
            tmp.append("  %%banc.f%d.x = add <4 x i32> %%banc.f%d.m, %s" % (k, k, x))
            tmp.append("  store <4 x i32> %%banc.f%d.x, <4 x i32>* %%banc.slot%d, align 16" % (k, j))
            inserts[ligne] += tmp
            k += 1
        slots = []
        for j in range(nslots):
            ep.append("  %%banc.s%d = load <4 x i32>, <4 x i32>* %%banc.slot%d, align 16" % (j, j))
            slots.append("%%banc.s%d" % j)
        puits += slots
        source = slots if k and v != "q" else ["%banc.pb"]
        nv = 0
        for i in garde:
            s = m.sorties[i]
            if s["genre"] != "vertex_output":
                continue
            x = source[nv % len(source)]
            nv += 1
            if v == "q":  # valeurs distinctes, disponibles seulement en fin de fonction
                ep.append("  %%banc.q%d = xor <4 x i32> %s, <i32 %d, i32 %d, i32 %d, i32 %d>" % (i, x, nv, nv + 1, nv + 2, nv + 3))
                x = "%%banc.q%d" % i
                if voies < 4:
                    masque = ", ".join("i32 %d" % k if k < voies else "i32 undef" for k in range(4))
                    ep.append("  %%banc.u%d = shufflevector <4 x i32> %s, <4 x i32> undef, <4 x i32> <%s>" % (i, x, masque))
                    x = "%%banc.u%d" % i
            if largeur < 4:
                et = "i32" if m.elems[i] == "<4 x i32>" else "float"
                ep.append("  %%banc.l%d = shufflevector <4 x i32> %s, <4 x i32> undef, <%d x i32> <%s>" % (
                    i, x, largeur, ", ".join("i32 %d" % k for k in range(largeur))))
                valeurs[i] = "%%banc.l%d" % i
                if et == "float":
                    ep.append("  %%banc.w%d = bitcast <%d x i32> %%banc.l%d to <%d x float>" % (i, largeur, i, largeur))
                    valeurs[i] = "%%banc.w%d" % i
                types_etroits[i] = "<%d x %s>" % (largeur, et)
            elif m.elems[i] == "<4 x i32>":
                valeurs[i] = x
            elif m.elems[i] == "<4 x float>":
                ep.append("  %%banc.w%d = bitcast <4 x i32> %s to <4 x float>" % (i, x))
                valeurs[i] = "%%banc.w%d" % i
            else:
                raise ValueError("varying de type %s" % m.elems[i])
    if not passthrough or v in "pq":
        for i, s in enumerate(m.sorties):
            ep.append("  %%banc.x%d = extractvalue %s %s, %d" % (i, m.ret, val_ret, i))
            if s["genre"] == "vertex_output" and i in garde and v not in "pq":
                valeurs[i] = "%%banc.x%d" % i
            if not (s["genre"] == "vertex_output" and i in garde) or v in "wpq":
                x = vers_4i32(ep, "%%banc.x%d" % i, m.elems[i], "banc.p%d" % i)
                if x is None:
                    raise ValueError("sortie de type %s" % m.elems[i])
                # freeze : les voies non ecrites d'un registre de sortie sont
                # undef ; sans lui toute la somme devient undef et le
                # compilateur supprime l'arithmetique qu'on voulait garder.
                ep.append("  %%banc.g%d = freeze <4 x i32> %s" % (i, x))
                if v != "n":  # essai n : a sans puits (la vraie position devient du code mort)
                    puits.append("%%banc.g%d" % i)
    # Puits : acc = acc * 33 + x, puis reduction ponderee des quatre voies. Pas
    # un ou-exclusif : deux sorties identiques (la position recopiee dans un
    # varying, par exemple) s'annuleraient et le compilateur plierait tout.
    if essai[0] == "r":  # essai : meme puits, ordre inverse (r = b, rk4 = k4...)
        puits.reverse()
    acc = None
    for i, x in enumerate(puits):
        if acc is None:
            acc = x
        else:
            ep.append("  %%banc.mul%d = mul <4 x i32> %s, <i32 33, i32 33, i32 33, i32 33>" % (i, acc))
            ep.append("  %%banc.acc%d = add <4 x i32> %%banc.mul%d, %s" % (i, i, x))
            acc = "%%banc.acc%d" % i
    if acc is None:
        acc = "zeroinitializer"
    ep.append("  %%banc.pond = mul <4 x i32> %s, <i32 3, i32 5, i32 7, i32 11>" % acc)
    for i in range(4):
        ep.append("  %%banc.r%d = extractelement <4 x i32> %%banc.pond, i64 %d" % (i, i))
    ep.append("  %banc.r01 = add i32 %banc.r0, %banc.r1")
    ep.append("  %banc.r23 = add i32 %banc.r2, %banc.r3")
    ep.append("  %banc.red = add i32 %banc.r01, %banc.r23")
    ep.append("  %banc.k = and i32 %banc.red, %banc.m")
    ep.append("  %banc.px = extractelement <4 x i32> %banc.pb, i64 0")
    ep.append("  %banc.py = or i32 %banc.px, %banc.k")
    ep.append("  %banc.pc = insertelement <4 x i32> %banc.pb, i32 %banc.py, i64 0")
    ep.append("  %banc.posf = bitcast <4 x i32> %banc.pc to <4 x float>")
    elems = [types_etroits.get(i, e) for i, e in enumerate(m.elems)]
    nouv_ret = "<{ " + ", ".join(elems[i] for i in garde) + " }>"
    cur = "undef"
    for k, i in enumerate(garde):
        s = m.sorties[i]
        if s["genre"] == "position":
            x = "%banc.posf"
        elif s["genre"] == "clip_distance":
            n = int(re.match(r"\[(\d+) x float\]", m.elems[i]).group(1))
            x = "[" + ", ".join(["float 1.000000e+00"] * n) + "]"
        else:
            x = valeurs[i]
        ep.append("  %%banc.st%d = insertvalue %s %s, %s %s, %d" % (k, nouv_ret, cur, elems[i], x, k))
        cur = "%%banc.st%d" % k
    ep.append("  ret %s %s" % (nouv_ret, cur))

    nb_tb = 0
    sortie = []
    debut = 1 if corps and re.match(r"^[\w.]+:", corps[0]) else 0
    for i, l in enumerate(corps):
        if i == iret:
            sortie += ep
            continue
        if v == "e":
            mo = re.match(r"  (%[\w.]+) = (?:tail )?call (\{ (<4 x (?:float|i32)>), i8 \}) @air\.read_texture_buffer_1d\.[\w.]+\(\S+ addrspace\(1\)\* (?:nocapture readonly )?%[\w.]+, i32 (%[\w.]+|-?\d+), i32 \d+\)", l)
            if mo:
                n, sty, vty, idx = mo.groups()
                t = "banc.t%d" % nb_tb
                nb_tb += 1
                sortie.append("  %%%s.i = and i32 %s, 4095" % (t, idx))
                sortie.append("  %%%s.z = zext i32 %%%s.i to i64" % (t, t))
                sortie.append("  %%%s.s = shl i64 %%%s.z, 4" % (t, t))
                sortie.append("  %%%s.p = getelementptr i8, i8 addrspace(1)* %%bancd, i64 %%%s.s" % (t, t))
                sortie.append("  %%%s.q = bitcast i8 addrspace(1)* %%%s.p to %s addrspace(1)*" % (t, t, vty))
                sortie.append("  %%%s.l = load %s, %s addrspace(1)* %%%s.q, align 16" % (t, vty, vty, t))
                sortie.append("  %s = insertvalue %s undef, %s %%%s.l, 0" % (n, sty, vty, t))
                continue
        sortie.append(l)
        if i == debut - 1:
            sortie += entete
        if i in inserts:
            sortie += inserts[i]
    if debut == 0:
        sortie = entete + sortie

    narg = len(m.args)
    args = m.args + [("i8 addrspace(1)*", "%banc"), ("i8 addrspace(1)*", "%bancd")]
    define = "define %s @%s(%s) local_unnamed_addr {" % (nouv_ret, m.nom, ", ".join("%s %s" % a for a in args))
    apres = m.apres
    fty = "%s (%s)*" % (nouv_ret, ", ".join(a[0] for a in args))
    apres = re.sub(r"^!%s = .*$" % m.racine, lambda _: "!%s = !{%s @%s, !%s, !%s}" % (m.racine, fty, m.nom, m.id_sorties, m.id_entrees), apres, flags=re.M)
    apres = re.sub(r"^!%s = .*$" % m.id_sorties, lambda _: "!%s = !{%s}" % (m.id_sorties, ", ".join("!" + m.sorties[i]["id"] for i in garde)), apres, flags=re.M)
    apres = re.sub(r"^(!%s = !\{.*)\}$" % m.id_entrees, lambda mo: mo.group(1) + ", !900001, !900002}", apres, flags=re.M)
    for i in types_etroits:
        apres = re.sub(r'^(!%s = .*"air.arg_type_name", !"(?:float|uint|int))4"' % m.sorties[i]["id"],
                       lambda mo: mo.group(1) + '%d"' % largeur, apres, flags=re.M)
    for k, (nom, index) in enumerate((("banc", BANC_INDEX), ("bancd", BANCD_INDEX))):
        apres += ('!%d = !{i32 %d, !"air.buffer", !"air.location_index", i32 %d, i32 1, !"air.read", '
                  '!"air.address_space", i32 1, !"air.arg_type_size", i32 1, !"air.arg_type_align_size", i32 1, '
                  '!"air.arg_type_name", !"uchar", !"air.arg_name", !"%s"}\n' % (900001 + k, narg + k, index, nom))
    # Un nom de fonction par variante : deux metallibs de meme nom de fonction
    # ne doivent pas pouvoir se confondre dans un cache de Metal.
    texte = (m.avant + define + "\n" + "\n".join(sortie) + "\n}\n" + apres).replace("@" + m.nom, "@%s_%s" % (m.nom, essai))
    passes = "sroa" if v in "pq" else "sroa,adce,simplifycfg" if passthrough else None
    if essai[0] == "z":
        passes = "default<O2>"
    return texte, passes, nb_tb, garde, largeur


def fragment(m, garde, largeur=4):
    """Fragment shader MSL qui consomme tous les varyings (aucune sortie du VS ne peut etre elaguee a la liaison)."""
    champs = ["    float4 p [[position]];"]
    somme = []
    for i, s in enumerate(m.sorties):
        if s["genre"] != "vertex_output" or i not in garde:
            continue
        ext = "" if largeur == 4 else ", " + ", ".join(["0"] * (4 - largeur))
        if s["type"] == "float4":
            champs.append("    float%d v%d [[%s]];" % (largeur, i, s["user"]))
            somme.append("float4(e.v%d%s)" % (i, ext))
        elif s["type"] in ("uint4", "int4"):
            champs.append("    %s%d v%d [[%s, flat]];" % (s["type"][:-1], largeur, i, s["user"]))
            somme.append("float4(float%d(e.v%d)%s)" % (largeur, i, ext))
        else:
            raise ValueError("varying %s" % s["type"])
    return ("#include <metal_stdlib>\nusing namespace metal;\nstruct E {\n%s\n};\n"
            "fragment float4 f(E e [[stage_in]]) {\n    float4 s = %s;\n    return s * 1e-30f;\n}\n"
            % ("\n".join(champs), " + ".join(somme) if somme else "float4(e.p.z)"))


def fabriquer(tache):
    src, var, nom, liste = tache
    m = Module(open(os.path.join(src, nom + ".ll")).read())
    lignes = []
    env = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
    for v in liste:
        base = os.path.join(var, "%s.%s" % (nom, v))
        texte, opt, nb_tb, garde, largeur = variante(m, v)
        if v.endswith("e") and nb_tb == 0:
            continue  # aucun texture_buffer : e serait a
        if opt:
            # opt de LLVM 15 refuse le triplet « air64 » : on le retire le
            # temps des passes (elles ne dependent pas de la cible).
            triplet = re.search(r'^target triple = .*\n', texte, re.M).group(0)
            open(base + ".ll", "w").write(texte.replace(triplet, ""))
            # -vectorize-slp=false : le vectoriseur SLP d'O2 emet llvm.vector.reduce.*
            reste = run([LLVM + "/opt", "-S", "-passes=" + opt, "-vectorize-slp=false", base + ".ll", "-o", "-"])
            texte = reste.replace("\ntarget datalayout", "\n" + triplet + "target datalayout", 1) if "target datalayout" in reste else triplet + reste
        open(base + ".ll", "w").write(texte)
        run([LLVM + "/llvm-as", base + ".ll", "-o", base + ".bc"])
        reste = texte
        run(["xcrun", "metallib", base + ".bc", "-o", base + ".metallib"], env=env)
        os.remove(base + ".bc")
        corps = reste[reste.index("define "):reste.index("\n}\n")]
        fs = fragment(m, garde, largeur)
        fnom = os.path.join(var, "fs_%s.metal" % hashlib.sha1(fs.encode()).hexdigest()[:12])
        if not os.path.exists(fnom):
            open(fnom, "w").write(fs)
        lignes.append([
            nom, m.classe(), str(m.nvar()), v, base + ".metallib", fnom,
            str(sum(1 for l in corps.split("\n") if l.startswith("  "))),
            str(corps.count("@air.read_texture_buffer") + corps.count("@air.sample_") + corps.count("@air.gather_")),
            str(len(re.findall(r"= load [^\n]*addrspace\(1\)\* %", corps)))])
    return lignes


def variantes(out, seulement, maxi, toutes_dispositions, liste, suffixe):
    src, var = os.path.join(out, "src"), os.path.join(out, "var" + suffixe)
    os.makedirs(var, exist_ok=True)
    inv = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "inventaire.tsv"))]
    cols, inv = inv[0], [dict(zip(inv[0], l)) for l in inv[1:]]
    # Une disposition d'entree par DXBC : celle qui tire le plus d'attributs.
    if not toutes_dispositions:
        par = {}
        for l in sorted(inv, key=lambda l: (-int(l["tirages"]), l["nom"])):
            par.setdefault(l["dxbc"], l)
        inv = sorted(par.values(), key=lambda l: l["nom"])
    if seulement:
        inv = [l for l in inv if any(l["nom"].startswith("vs_" + h) or l["dxbc"] == h for h in seulement)]
    inv.sort(key=lambda l: -int(l["instr"]))
    if maxi:
        inv = inv[:maxi]
    lignes, rates = [], 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as ex:
        futs = {ex.submit(fabriquer, (src, var, l["nom"], liste)): l["nom"] for l in inv}
        for fu in concurrent.futures.as_completed(futs):
            try:
                lignes += fu.result()
            except Exception as e:
                rates += 1
                print("echec %s : %s" % (futs[fu], str(e)[:600]), file=sys.stderr)
    lignes.sort()
    with open(os.path.join(out, "manifeste%s.tsv" % suffixe), "w") as f:
        f.write("nom\tclasse\tvaryings\tvariante\tmetallib\tfragment\tinstr\tlectures_texture\tchargements_device\n")
        for l in lignes:
            f.write("\t".join(l) + "\n")
    print("%d shaders, %d variantes, %d echecs -> %s/manifeste%s.tsv" % (len(inv) - rates, len(lignes), rates, out, suffixe))


# -------------------------------------------------------------------- rapport

def lire_tsv(chemin):
    if not os.path.exists(chemin):
        return []
    lignes = [l.rstrip("\n").split("\t") for l in open(chemin) if l.strip()]
    return [dict(zip(lignes[0], l)) for l in lignes[1:]]


def quantile(v, q):
    v = sorted(v)
    if not v:
        return float("nan")
    i = q * (len(v) - 1)
    a, b = int(i), min(int(i) + 1, len(v) - 1)
    return v[a] + (v[b] - v[a]) * (i - a)


def rapport(out, top):
    mes = lire_tsv(os.path.join(out, "mesures.tsv"))
    if not mes:
        sys.exit("pas de %s/mesures.tsv" % out)
    inv = {l["nom"]: l for l in lire_tsv(os.path.join(out, "inventaire.tsv"))}
    court = lambda n: "_".join(n.split("_")[:2])
    # t[(config, remplissage, rejet)][nom][variante] = us par million de sommets uniques
    t = collections.defaultdict(lambda: collections.defaultdict(dict))
    infos, geo = {}, {}
    for l in mes:
        cle = (l["config"], l["remplissage"], l["rejet"])
        t[cle][l["nom"]][l["variante"]] = float(l["us_par_Msommets"])
        infos[l["nom"]] = l
        geo[l["config"]] = (int(l["dessins"]), float(l["sommets"]), float(l["indices"]))
    L = []
    L.append("# Banc des vrais vertex shaders : resultats\n")
    L.append("Unite : microsecondes d'etage sommets (shading + tiler, GPU seul) par million de sommets uniques.\n")
    L.append("| configuration | dessins par passe | sommets uniques | index | index par dessin | index par sommet |")
    L.append("|---|---|---|---|---|---|")
    for c, (d, sv, ix) in sorted(geo.items()):
        L.append("| %s | %d | %.0f | %.0f | %.0f | %.2f |" % (c, d, sv, ix, ix / d, ix / sv))
    L.append("")
    L.append("a complet ; b position seule (varyings au puits) ; c passthrough des attributs vers les memes sorties ; "
             "d lecture des attributs seule ; e = a sans unite de texture pour les Buffer<T>.")
    L.append("Decomposition : lecture = d ; arithmetique = b - d ; sorties seules = c - d ; "
             "surcout des sorties sur l'arithmetique = a - b - (c - d).\n")

    def decomp(v):
        a, b, c, d = v["a"], v["b"], v["c"], v["d"]
        return dict(a=a, lecture=d, arith=b - d, sorties=c - d, inter=a - b - (c - d), tb=a - v.get("e", a))

    for cle in sorted(t):
        cfg, rempl, rejet = cle
        complets = {n: v for n, v in t[cle].items() if all(x in v for x in "abcd")}
        L.append("## %s, remplissage %s, rejet %s %%\n" % (cfg, rempl, rejet))
        L.append("### Par classe (mediane des shaders ; classe = nombre de varyings : profondeur 0, ombres 1-3, autre 4-5, base >= 6)\n")
        L.append("| classe | shaders | a mediane | a p90 | lecture | arithmetique | sorties seules | surcout sorties x arithmetique | part texture_buffer (a - e) |")
        L.append("|---|---|---|---|---|---|---|---|---|")
        uniformes = []
        for classe in ("profondeur", "ombres", "autre", "base"):
            noms = [n for n in complets if infos[n]["classe"] == classe]
            if not noms:
                continue
            D = [decomp(complets[n]) for n in noms]
            med = lambda k: quantile([x[k] for x in D], 0.5)
            part = lambda k: quantile([x[k] / x["a"] for x in D], 0.5) * 100
            L.append("| %s | %d | %.0f | %.0f | %.0f (%.0f %%) | %.0f (%.0f %%) | %.0f (%.0f %%) | %.0f (%.0f %%) | %.0f %% |" % (
                classe, len(noms), med("a"), quantile([x["a"] for x in D], 0.9), med("lecture"), part("lecture"),
                med("arith"), part("arith"), med("sorties"), part("sorties"), med("inter"), part("inter"), part("tb")))
            tot = lambda k: sum(x[k] for x in D)
            uniformes.append("| %s | %d | %.0f | %.0f %% | %.0f %% | %.0f %% | %.0f %% | %.0f %% |" % (
                classe, len(noms), tot("a") / len(D), 100 * tot("lecture") / tot("a"), 100 * tot("arith") / tot("a"),
                100 * tot("sorties") / tot("a"), 100 * tot("inter") / tot("a"), 100 * tot("tb") / tot("a")))
        L.append("")
        L.append("### Par classe, a usage uniforme (chaque shader ombre le meme nombre de sommets : somme des temps)\n")
        L.append("| classe | shaders | a moyen | lecture | arithmetique | sorties seules | surcout sorties x arithmetique | part texture_buffer |")
        L.append("|---|---|---|---|---|---|---|---|")
        L += uniformes
        L.append("")
        for classe in ("base", "ombres", "profondeur"):
            noms = sorted((n for n in complets if infos[n]["classe"] == classe), key=lambda n: -complets[n]["a"])[:top]
            if not noms:
                continue
            L.append("### Les %d plus couteux de la classe %s\n" % (len(noms), classe))
            L.append("| shader | varyings | instr. | lectures tb | a | b | c | d | e | lecture | arithmetique | sorties seules | surcout sorties x arith. | ns par index (a) |")
            L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
            for n in noms:
                v, x = complets[n], decomp(complets[n])
                i = inv.get(n, {})
                L.append("| %s | %s | %s | %s | %.0f | %.0f | %.0f | %.0f | %s | %.0f %% | %.0f %% | %.0f %% | %.0f %% | %.2f |" % (
                    court(n), infos[n]["varyings"], i.get("instr", "?"), i.get("lect_tb", "?"), v["a"], v["b"], v["c"], v["d"],
                    "%.0f" % v["e"] if "e" in v else "-", 100 * x["lecture"] / x["a"], 100 * x["arith"] / x["a"],
                    100 * x["sorties"] / x["a"], 100 * x["inter"] / x["a"], v["a"] * geo[cfg][1] / geo[cfg][2] / 1000))
            L.append("")
    for nom, titre in (("mesures-essais.tsv", "Essais : nombre de sorties a arithmetique entiere"),
                       ("mesures-geometrie.tsv", "Geometrie : index partages ou non, part de triangles rejetes")):
        es = lire_tsv(os.path.join(out, nom))
        if not es:
            continue
        L.append("## %s\n" % titre)
        vs = sorted(set(l["variante"] for l in es), key=lambda v: (len(v), v))
        cles = sorted(set((l["nom"], l["config"], l["remplissage"], l["rejet"]) for l in es))
        val = {(l["nom"], l["config"], l["remplissage"], l["rejet"], l["variante"]): float(l["us_par_Msommets"]) for l in es}
        ixs = {l["config"]: float(l["indices"]) / float(l["sommets"]) for l in es}
        L.append("| shader | varyings | config | index par sommet | remplissage | rejet | " + " | ".join(vs) + " |")
        L.append("|---|---|---|---|---|---|" + "---|" * len(vs))
        for (n, c, r, j) in cles:
            L.append("| %s | %s | %s | %.2f | %s | %s | " % (court(n), inv.get(n, {}).get("varyings", "?"), c, ixs[c], r, j)
                     + " | ".join("%.0f" % val[(n, c, r, j, v)] if (n, c, r, j, v) in val else "-" for v in vs) + " |")
        L.append("")
    # Reference : p90 au remplissage le plus eleve de la manche principale.
    ref = sorted(k for k in t if k[0] == "p90") or sorted(t)
    ref = t[ref[-1]]
    el = {l["nom"]: float(l["us_par_Msommets"]) for l in lire_tsv(os.path.join(out, "mesures-elagage.tsv")) if l["variante"] == "a"}
    if el:
        L.append("## Elagage par Metal : cout quand le fragment shader ne lit aucun varying\n")
        L.append("Variante a liee au fragment shader de b (position seule) : Metal retire les sorties non lues et le code qui "
                 "ne sert qu'a elles. C'est ce que paie une passe de profondeur ou d'ombres avec le meme vertex shader.\n")
        L.append("| classe | shaders | position seule, mediane | p90 | lecture seule (d), mediane | complet / position seule : mediane | p10 | p90 | a usage uniforme |")
        L.append("|---|---|---|---|---|---|---|---|---|")
        for classe in ("ombres", "autre", "base"):
            noms = [n for n in el if infos.get(n, {}).get("classe") == classe and "a" in ref.get(n, {}) and "d" in ref[n]]
            if not noms:
                continue
            r = [ref[n]["a"] / el[n] for n in noms]
            L.append("| %s | %d | %.0f | %.0f | %.0f | %.1f | %.1f | %.1f | %.1f |" % (
                classe, len(noms), quantile([el[n] for n in noms], 0.5), quantile([el[n] for n in noms], 0.9),
                quantile([ref[n]["d"] for n in noms], 0.5), quantile(r, 0.5), quantile(r, 0.1), quantile(r, 0.9),
                sum(ref[n]["a"] for n in noms) / sum(el[n] for n in noms)))
        L.append("")
    o2 = collections.defaultdict(dict)
    for l in lire_tsv(os.path.join(out, "mesures-o2.tsv")):
        o2[l["nom"]][l["variante"]] = float(l["us_par_Msommets"])
    o2 = {n: v for n, v in o2.items() if "a" in v and "za" in v}
    if o2:
        L.append("## Variante a repassee par opt -O2 de LLVM 15 (za) : ce que rapporterait un pipeline de passes plus fort dans airconv\n")
        L.append("| classe | shaders | za / a - 1 : mediane | p10 | p90 | pondere par le cout |")
        L.append("|---|---|---|---|---|---|")
        for classe in ("ombres", "autre", "base"):
            noms = [n for n in o2 if infos.get(n, {}).get("classe") == classe]
            if not noms:
                continue
            g = [o2[n]["za"] / o2[n]["a"] - 1 for n in noms]
            L.append("| %s | %d | %+.1f %% | %+.1f %% | %+.1f %% | %+.1f %% |" % (
                classe, len(noms), 100 * quantile(g, 0.5), 100 * quantile(g, 0.1), 100 * quantile(g, 0.9),
                100 * (sum(o2[n]["za"] for n in noms) / sum(o2[n]["a"] for n in noms) - 1)))
        L.append("")
    open(os.path.join(out, "rapport.md"), "w").write("\n".join(L) + "\n")
    # selection pour les essais : les plus couteux de base et d'ombres (p90, remplissage le plus eleve)
    cles = sorted(k for k in t if k[0] == "p90") or sorted(t)
    cle = cles[-1]
    sel = []
    for classe in ("base", "ombres", "profondeur"):
        noms = [n for n, v in t[cle].items() if infos[n]["classe"] == classe and "a" in v]
        sel += sorted(noms, key=lambda n: -t[cle][n]["a"])[:top if classe != "profondeur" else 3]
    open(os.path.join(out, "selection.txt"), "w").write("\n".join(n[3:] for n in sel) + "\n")
    print("%s/rapport.md ; %s/selection.txt (%d shaders)" % (out, out, len(sel)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("extraire")
    p.add_argument("--db", required=True)
    p.add_argument("--out", required=True)
    p = sp.add_parser("variantes")
    p.add_argument("--out", required=True)
    p.add_argument("--seulement", default="")
    p.add_argument("--max", type=int, default=0)
    p.add_argument("--toutes-dispositions", action="store_true")
    p.add_argument("--variantes", default=",".join(VARIANTES))
    p.add_argument("--suffixe", default="")
    p = sp.add_parser("rapport")
    p.add_argument("--out", required=True)
    p.add_argument("--top", type=int, default=10)
    a = ap.parse_args()
    if a.cmd == "extraire":
        extraire(a.db, a.out)
    elif a.cmd == "rapport":
        rapport(a.out, a.top)
    else:
        variantes(a.out, [h for h in a.seulement.replace("\n", ",").split(",") if h.strip()], a.max, a.toutes_dispositions,
                  [v for v in a.variantes.split(",") if v], a.suffixe)


if __name__ == "__main__":
    main()
