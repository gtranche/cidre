"""Engendrer le relais __thiscall du cote i386.

En 32 bits, l'appele depile les arguments : un thunk doit donc retirer un
nombre d'octets fixe a la compilation. On engendre une grille
(emplacement x nombre de mots) de thunks « fastcall » a deux parametres
registre -- ce qui reproduit exactement __thiscall, « this » arrivant dans ECX
-- puis une table qui, pour chaque interface et chaque emplacement, donne le
nombre de mots a depiler et la taille de la structure rendue.

Ces chiffres viennent de tests/signatures_steam_api.py, qui les lit dans le
steam_api.dll du jeu. Rien n'est devine.

    engendrer_i386.py <signatures.json> <dossier de sortie>
"""
import json, sys, os

EMPLACEMENTS = 84     # emplacement maximal releve : 81
MOTS = 10             # au plus 36 octets empiles, soit 9 mots


def thunks():
    o = ['/* Engendre par tests/engendrer_i386.py -- ne pas editer a la main. */\n',
         '#ifndef _WIN64\n\n',
         '#define NB_EMPLACEMENTS32 %d\n#define NB_MOTS32 %d\n\n' % (EMPLACEMENTS, MOTS),
         'static UINT64 repartir32( unsigned emplacement, void *self, unsigned mots,\n'
         '                          const UINT32 *args );\n\n',
         '/*\n'
         ' * « fastcall » a deux parametres registre : le premier occupe ECX, comme\n'
         ' * « this » en __thiscall, le second occupe EDX et n\'est pas lu. Les mots\n'
         ' * suivants sont sur la pile, et l\'appele les depile -- exactement la\n'
         ' * discipline attendue. La valeur de retour est declaree sur 64 bits pour\n'
         ' * transporter EDX:EAX, ce que fait une methode rendant un entier long.\n'
         ' */\n']
    for s in range(EMPLACEMENTS):
        for n in range(MOTS):
            args = ''.join(', UINT32 a%d' % i for i in range(n))
            adr = '&a0' if n else 'NULL'
            o.append('static UINT64 __attribute__((fastcall)) t%d_%d( void *self, void *inutilise%s )\n'
                     '{ return repartir32( %d, self, %d, %s ); }\n' % (s, n, args, s, n, adr))
    o.append('\nstatic const void *table32[NB_EMPLACEMENTS32][NB_MOTS32] =\n{\n')
    for s in range(EMPLACEMENTS):
        o.append('    { ' + ', '.join('t%d_%d' % (s, n) for n in range(MOTS)) + ' },\n')
    o.append('};\n\n#endif /* _WIN64 */\n')
    return ''.join(o)


# Emplacements sans enveloppe plate, releves sur leurs sites d'appel dans
# steam_api.dll. On y reconnait ISteamClient a la variable globale qui le
# porte, puis on compte les poussees jusqu'a l'appel :
#
#   mov  0x3b4392c8,%ecx     l'objet ISteamClient
#   push $0x3b406620         un pointeur de fonction
#   mov  (%ecx),%eax
#   call *0x88(%eax)         emplacement 34, un mot
#
# Sans cette mesure, le thunk depilait zero octet et corrompait la pile de
# l'appelant -- la faute survenant plusieurs appels plus loin.
COMPLEMENT = [
    ("ISteamClient", 1, 1, 0, "BReleaseSteamPipe"),
    ("ISteamClient", 34, 1, 0, "sans_nom_34"),
]


def signatures(sig):
    o = ['/* Engendre par tests/engendrer_i386.py -- ne pas editer a la main.\n'
         ' * Releve dans le steam_api.dll i386 d\'un jeu : pour chaque methode, son\n'
         ' * emplacement, le nombre de mots empiles et la taille de la structure\n'
         ' * rendue par pointeur cache (zero si elle n\'en rend pas). */\n\n',
         'struct signature_steam\n{\n'
         '    const char *interface;\n'
         '    unsigned    emplacement;\n'
         '    unsigned    mots;\n'
         '    unsigned    tampon;\n'
         '    const char *methode;\n};\n\n',
         'static const struct signature_steam signatures[] =\n{\n']
    n = 0
    for iface, emp, mots, tampon, meth in COMPLEMENT:
        o.append('    { "%s", %d, %d, %d, "%s" },\n' % (iface, emp, mots, tampon, meth))
        n += 1
    for iface in sorted(sig):
        for meth in sorted(sig[iface]):
            v = sig[iface][meth]
            if v['emplacement'] >= EMPLACEMENTS or v['octets'] // 4 >= MOTS:
                continue
            o.append('    { "%s", %d, %d, %d, "%s" },\n'
                     % (iface, v['emplacement'], v['octets'] // 4, v['tampon'], meth))
            n += 1
    o.append('};\n')
    return ''.join(o), n


if __name__ == "__main__":
    sig = json.load(open(sys.argv[1]))
    dst = sys.argv[2]
    open(os.path.join(dst, "thunks32.h"), "w").write(thunks())
    s, n = signatures(sig)
    open(os.path.join(dst, "signatures32.h"), "w").write(s)
    print("thunks32.h : %d thunks" % (EMPLACEMENTS * MOTS))
    print("signatures32.h : %d methodes" % n)
