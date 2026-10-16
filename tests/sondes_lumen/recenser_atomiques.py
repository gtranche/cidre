#!/usr/bin/env python3
# Recense les atomiques des modules SPIR-V d'un dossier : sur memoire, ou sur image (par
# dimension et format), avec la liste des modules.  python3 -I recenser_atomiques.py <dossier>
import os, struct, sys, collections
d = sys.argv[1]
dimn = {0: '1D', 1: '2D', 2: '3D', 3: 'Cube', 4: 'Rect', 5: 'Buffer'}
fmtn = {0: 'Unknown', 3: 'R32f', 24: 'R32i', 33: 'R32ui', 40: 'R64ui', 41: 'R64i'}
atom_ops = {227: 'Load', 228: 'Store', 229: 'Exchange', 230: 'CmpXchg', 232: 'IIncrement', 233: 'IDecrement',
            234: 'IAdd', 235: 'ISub', 236: 'SMin', 237: 'UMin', 238: 'SMax', 239: 'UMax', 240: 'And', 241: 'Or', 242: 'Xor'}
tot = collections.Counter(); per = collections.defaultdict(set); used = collections.Counter()
for f in sorted(os.listdir(d)):
    b = open(os.path.join(d, f), 'rb').read(); w = struct.unpack('<%dI' % (len(b) // 4), b)
    types = {}; var = {}; tex = {}; chain = {}; insts = []; uses = collections.Counter()
    i = 5
    while i < len(w):
        op = w[i] & 0xffff; wc = w[i] >> 16
        if wc == 0: break
        a = w[i + 1:i + wc]
        if op == 25: types[a[0]] = ('img', a[2], a[7])
        elif op == 32: types[a[0]] = ('ptr', a[2])
        elif op in (28, 29): types[a[0]] = ('arr', a[1])
        elif op == 59: var[a[1]] = a[0]
        elif op in (65, 66, 67, 70): chain[a[1]] = a[2]
        elif op == 60: tex[a[1]] = a[2]
        elif op in atom_ops: insts.append((op, a))
        # compte les usages de chaque id resultat (pour savoir si la valeur rendue est lue)
        for x in a: uses[x] += 1
        i += wc
    def img_of(pid):
        seen = 0
        while pid in chain and seen < 16: pid = chain[pid]; seen += 1
        t = var.get(pid)
        while t is not None:
            tt = types.get(t)
            if tt is None: return '?'
            if tt[0] == 'img': return dimn.get(tt[1], tt[1]) + '/' + fmtn.get(tt[2], str(tt[2]))
            t = tt[1]
        return '?'
    for op, a in insts:
        p = a[2]
        k = atom_ops[op] + ('@image ' + img_of(tex[p]) if p in tex else '@memoire')
        r = a[1]
        if op not in (228,) and uses[r] > 1: k += ' (valeur lue)'
        tot[k] += 1; per[k].add(f)
for k in sorted(tot, key=lambda x: -len(per[x])):
    print('%4d modules %4d ops  %s' % (len(per[k]), tot[k], k))
    if len(per[k]) <= 8: print('        ' + ' '.join(sorted(per[k])))
