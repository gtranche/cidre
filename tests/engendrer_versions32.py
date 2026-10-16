#!/usr/bin/env python3
"""Engendre dlls/lsteamclient/versions32.h depuis le lsteamclient de Proton.

Usage : engendrer_versions32.py <dossier des winISteam*.c de Proton> > versions32.h

Les fichiers winISteam*.c de ValveSoftware/Proton (lsteamclient/, engendres par
son gen_wrapper.py a partir des en-tetes de chaque SDK Steamworks) donnent, pour
chaque version EXACTE d'interface :
  - l'ordre de la table de methodes : la suite des VTABLE_ADD_FUNC ;
  - la discipline de pile __thiscall : DEFINE_THISCALL_WRAPPER(nom, octets),
    « this » compris -- donc mots depiles = octets / 4 - 1 ;
  - le prototype : types des arguments, retour par pointeur cache (_ret),
    interface ou chaine rendue.

signatures32.h, releve dans UN steam_api i386 (SteamClient018/019,
SteamFriends017...), est indexe par NOM d'interface : faux des qu'un jeu parle
une autre version. Ce fichier-ci le complete, version par version.

Types des mots (meme alphabet que types32.h, plus deux lettres) :
  'e' entier, 'p' pointeur d'invite a rebaser,
  'L' moitie basse d'une valeur de 64 bits, 'l' sa moitie haute (le relais
      les recolle en un seul argument : System V passe un uint64 dans un
      seul registre, l'ABI i386 sur deux mots de pile),
  'f' flottant (passe tel quel ; System V l'attendrait dans un registre
      flottant -- limite connue du relais).
Rendu : 'i' interface (getter d'ISteamClient), 'c' chaine (const char *),
        '-' autre.
"""
import os
import re
import sys

# Types de 64 bits passes par valeur sur la pile i386.
TYPES_64 = {
    'uint64_t', 'int64_t', 'CSteamID', 'CGameID', 'double', 'const uint64_t',
}
# Structures rendues par pointeur cache, et leur taille (celles des manettes :
# les tailles deja relevees dans signatures32.h). Le relais ne sait rendre que
# 8 octets ; les autres sont signalees et rendent zero, mais depilent juste.
TAILLES_RETOUR = {'CSteamID': 8, 'CGameID': 8, 'SteamIPAddress_t': 20,
                  'InputDigitalActionData_t': 2, 'ControllerDigitalActionData_t': 2,
                  'InputAnalogActionData_t': 13, 'ControllerAnalogActionData_t': 13,
                  'InputMotionData_t': 40, 'ControllerMotionData_t': 40}


def couper_arguments(texte):
    """Separe les arguments au niveau zero des parentheses."""
    args, prof, cour = [], 0, ''
    for c in texte:
        if c == '(':
            prof += 1
        elif c == ')':
            prof -= 1
        if c == ',' and prof == 0:
            args.append(cour.strip())
            cour = ''
        else:
            cour += c
    if cour.strip():
        args.append(cour.strip())
    return args


def type_de(arg):
    """Le type d'un argument, sans son nom."""
    if '(' in arg:
        return 'fonction'
    m = re.match(r'^(.*?)([A-Za-z_][A-Za-z_0-9]*)$', arg)
    return m.group(1).strip() if m else arg


def mots_de(arg):
    t = type_de(arg)
    if t == 'fonction' or '*' in t or '&' in t:
        return 'p'
    if t in TYPES_64:
        return 'Ll'
    if t == 'float':
        return 'f'
    if t in ('SteamIPAddress_t', 'w_SteamPartyBeaconLocation_t',
             'w_RemoteStorageUpdatePublishedFileRequest_t'):
        return None          # structure par valeur : taille non tenue ici
    return 'e'


def lire(dossier):
    versions = {}            # version -> [(nom, mots, tampon, types, rendu)]
    # Les prototypes : engendres (winISteam*.c) ou ecrits a la main par Valve
    # (steam_*_manual.c), parfois sur plusieurs lignes.
    protos, octets = {}, {}
    for fic in sorted(os.listdir(dossier)):
        if not fic.endswith('.c'):
            continue
        src = open(os.path.join(dossier, fic)).read()
        octets.update((m.group(1), int(m.group(2))) for m in
                      re.finditer(r'DEFINE_THISCALL_WRAPPER\((\w+), (\d+)\)', src))
        for m in re.finditer(r'^([^\n;{}]+?)\s*__thiscall (\w+)\(\s*struct w_iface \*_this,?'
                             r'\s*([^{;]*?)\s*\)\s*\{', src, re.M | re.S):
            protos[m.group(2)] = (m.group(1).strip(), ' '.join(m.group(3).split()))
    for fic in sorted(os.listdir(dossier)):
        if not (fic.startswith('winISteam') and fic.endswith('.c')):
            continue
        src = open(os.path.join(dossier, fic)).read()
        for bloc in re.finditer(r'__ASM_VTABLE\((\w+),(.*?)\);', src, re.S):
            table = bloc.group(1)
            fonctions = re.findall(r'VTABLE_ADD_FUNC\((\w+)\)', bloc.group(2))
            interface = re.match(r'win(ISteam[A-Za-z]+?)_', table).group(1)
            version = table[len('win' + interface) + 1:]
            liste = []
            for f in fonctions:
                retour, texte = protos[f]
                args = couper_arguments(texte)
                mots = octets[f] // 4 - 1
                tampon = 0
                # Le pointeur cache vient juste apres « this ».
                if args and args[0].endswith('_ret') and retour.endswith('*') and \
                        retour[:-1].strip() in TAILLES_RETOUR:
                    tampon = TAILLES_RETOUR[retour[:-1].strip()]
                    args = args[1:]
                types = ''
                for a in args:
                    t = mots_de(a)
                    if t is None:
                        types = None
                        break
                    types += t
                if types is not None and len(types) + (1 if tampon else 0) != mots:
                    types = None     # incoherent : on laisse l'heuristique
                if '/*ISteam' in retour or f.endswith('_GetISteamGenericInterface'):
                    rendu = 'i'
                elif retour == 'const char *':
                    rendu = 'c'
                else:
                    rendu = '-'
                liste.append((f[len(table) + 1:], mots, tampon, types, rendu))
            versions[version] = liste
    return versions


def main():
    versions = lire(sys.argv[1])
    lignes = []
    for v in sorted(versions):
        for k, (nom, mots, tampon, types, rendu) in enumerate(versions[v]):
            t = '"%s"' % types if types is not None else 'NULL'
            lignes.append('    { "%s", %d, %d, %d, \'%s\', %s, "%s" },'
                          % (v, k, mots, tampon, rendu, t, nom))
    print('/* Engendre par tests/engendrer_versions32.py -- ne pas editer a la main.')
    print(' * Source : ValveSoftware/Proton, lsteamclient/winISteam*.c (%s).'
          % os.environ.get('PROTON_REV', 'revision non precisee'))
    print(' * Une ligne par methode : version exacte, emplacement, mots depiles,')
    print(' * taille rendue par pointeur cache, rendu (i/c/-), types des mots')
    print(' * (e, p, L/l, f ; NULL = inconnu), nom. Trie par version. */')
    print()
    print('#define NB_METHODES_VERSIONNEES %d' % len(lignes))
    print()
    print('struct methode_versionnee')
    print('{')
    print('    const char    *version;')
    print('    unsigned short emplacement;')
    print('    unsigned char  mots;')
    print('    unsigned char  tampon;')
    print('    char           rendu;')
    print('    const char    *types;')
    print('    const char    *methode;')
    print('};')
    print()
    print('static const struct methode_versionnee methodes_versionnees[] =')
    print('{')
    for l in lignes:
        print(l)
    print('};')


if __name__ == '__main__':
    main()
