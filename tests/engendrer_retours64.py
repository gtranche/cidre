"""Relever, par version exacte d'interface, les methodes Steamworks qui rendent
une structure par pointeur cache en 64 bits.

Pourquoi
--------
En Microsoft x64, une methode virtuelle qui rend une classe (un CSteamID, un
InputAnalogActionData_t...) recoit un pointeur de sortie cache juste apres
« this » ; en System V la meme classe revient dans RAX. Le pont doit donc
savoir, emplacement par emplacement, ou est ce pointeur. signatures32.h le dit
par NOM d'interface, d'apres un steam_api.dll i386 d'epoque SteamFriends017.
Or les emplacements bougent d'une version a l'autre : SteamFriends018 a retire
SetPersonaName (emplacement 1) et tout ISteamFriends a glisse d'un cran. Sur
Demonologist (UE 5.6, SteamFriends018), GetFriendRelationship -- nouvel
emplacement 4 -- etait pris pour GetFriendByIndex : le CSteamID passe en
argument (0x0110000114532c3b) servait d'adresse de sortie, et le jeu tombait
en ACCESS_VIOLATION a l'ecriture, sur son fil principal.

Le steam_api64.dll livre avec chaque jeu exporte une enveloppe plate par
methode, et chacune montre le retour cache sans en-tete du SDK :

    SteamAPI_ISteamFriends_GetFriendByIndex :
        mov  (%rcx),%rax
        lea  0x30(%rsp),%rdx     tampon de retour, en premier argument
        call *0x18(%rax)         emplacement 3
        mov  (%rax),%rax         relu par le pointeur rendu : 8 octets

Une structure plus grande que huit octets suit la meme forme, a ceci pres que
l'enveloppe rend elle-meme par pointeur cache (« this » arrive alors dans
RDX) ; la taille est la portee des lectures faites par le pointeur rendu.
Un argument passe par reference (« lea ..,%rdx » sans relecture apres
l'appel) n'est pas un retour : c'est la relecture qui decide.

Une version d'interface ne change pas de disposition : la table est donc
indexee par la chaine de version que le jeu transmet (« SteamFriends018 »).
Les versions relevees sans aucun retour cache sont listees aussi, pour que le
pont distingue « aucun » de « inconnue » -- et ne retombe sur la table i386
que dans le second cas.

    engendrer_retours64.py <sortie retours64.h> <steam_api64.dll>...
"""
import re, subprocess, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exports_pe import exports

OBJDUMP = os.environ.get("OBJDUMP64", os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "toolchain/llvm-mingw-20260908-ucrt-macos-universal/bin/llvm-objdump"))

LARGEUR = {"movq": 8, "movl": 4, "movzwl": 2, "movzbl": 1, "movw": 2, "movb": 1,
           "movups": 16, "movaps": 16, "movdqu": 16, "movsd": 8, "movss": 4}


def desassembler(chemin):
    out = subprocess.run([OBJDUMP, "-d", "--no-show-raw-insn", chemin],
                         capture_output=True, text=True, check=True).stdout
    instr = {}
    pat = re.compile(r"^\s*([0-9a-f]+):\s+(\S+)\s*(.*)$")
    for l in out.splitlines():
        m = pat.match(l)
        if m:
            instr[int(m.group(1), 16)] = (m.group(2), m.group(3).split("#")[0].strip())
    return instr


def base_image(chemin):
    import struct
    d = open(chemin, "rb").read(4096)
    (pe,) = struct.unpack_from("<I", d, 0x3C)
    return struct.unpack_from("<Q", d, pe + 24 + 24)[0]


def largeur(mn, op):
    if mn == "movq" and "%xmm" in op:
        return 8
    if mn == "movl" and re.search(r",\s*%r\w+$", op):
        return 4
    return LARGEUR.get(mn, 0)


def analyser(instr, debut):
    """Rend (emplacement, taille du retour cache, 0 si aucun) ou None."""
    adresses = sorted(a for a in instr if debut <= a < debut + 200)
    lea_rdx = False
    emplacement = None
    apres = None
    for i, a in enumerate(adresses):
        mn, op = instr[a]
        if mn == "int3" or mn.startswith("ret"):
            break
        if mn == "leaq" and re.match(r"0x[0-9a-f]+\(%rsp\), %rdx$", op):
            lea_rdx = True
        m = re.match(r"\*(0x[0-9a-f]+)?\(%rax\)$", op) if mn.startswith(("call", "jmp")) else None
        r10 = re.match(r"(0x[0-9a-f]+)?\(%rax\), %r10$", op) if mn == "movq" else None
        if m or r10:
            emplacement = int((m or r10).group(1) or "0", 16) // 8
            if mn.startswith("call"):
                apres = adresses[i + 1:]
            break
    if emplacement is None:
        return None
    if not (lea_rdx and apres):
        return emplacement, 0
    # La relecture par le pointeur rendu (RAX), avant toute autre ecriture de RAX.
    portee = 0
    for a in apres:
        mn, op = instr[a]
        if mn == "int3" or mn.startswith("ret"):
            break
        m = re.match(r"(0x[0-9a-f]+)?\(%rax\),\s*(%\w+)$", op)
        if m and mn.startswith("mov"):
            portee = max(portee, int(m.group(1) or "0", 16) + largeur(mn, op))
            if m.group(2) in ("%rax", "%eax"):
                break
            continue
        if re.search(r",\s*%(rax|eax)$", op):
            break
    return emplacement, portee


def version_de(interface, versions):
    """« ISteamFriends » -> la chaine de version que ce steam_api transmet."""
    i = interface[len("ISteam"):].lower()
    res = []
    for v in versions:
        if "_INTERFACE_VERSION" in v:
            u = v.split("_INTERFACE_VERSION")[0]
            u = u[5:] if u.lower().startswith("steam") else u
        else:
            u = v[5:] if v.lower().startswith("steam") else v
            u = re.match(r"[^0-9]*", u).group(0)
        if u.lower() == i:
            res.append(v)
    return res


def chaines_de_version(chemin):
    d = open(chemin, "rb").read()
    tout = set(s.decode() for s in re.findall(rb"(?<![A-Za-z0-9_])(Steam[A-Za-z]+0\d\d|STEAM[A-Z]+_INTERFACE_VERSION0\d\d)(?=\0)", d))
    return sorted(tout)


def relever(chemin):
    instr = desassembler(chemin)
    base = base_image(chemin)
    versions = chaines_de_version(chemin)
    par_interface = {}
    for nom, rva in exports(chemin).items():
        m = re.match(r"SteamAPI_(ISteam\w+?)_(\w+)$", nom)
        if not m:
            continue
        r = analyser(instr, base + rva)
        if r is None:
            continue
        par_interface.setdefault(m.group(1), []).append((r[0], r[1], m.group(2)))
    res = {}
    for interface, methodes in par_interface.items():
        vs = version_de(interface, versions)
        if len(vs) != 1:
            continue
        res[vs[0]] = sorted((e, t, n) for e, t, n in methodes if t)
    return res


def main():
    sortie, dlls = sys.argv[1], sys.argv[2:]
    table, sources = {}, {}
    for chemin in dlls:
        for version, retours in relever(chemin).items():
            if version in table and table[version] != retours:
                sys.exit("%s : disposition differente selon %s et %s" % (version, sources[version], chemin))
            table[version] = retours
            sources.setdefault(version, chemin)

    o = ["/* Engendre par tests/engendrer_retours64.py -- ne pas editer a la main.\n"
         " * Releve dans les steam_api64.dll des jeux : pour chaque version exacte\n"
         " * d'interface, les methodes qui rendent une structure par pointeur cache en\n"
         " * Microsoft x64, et sa taille. Une version listee dans versions64 sans\n"
         " * ligne ici n'en a aucune ; une version absente des deux est inconnue. */\n\n",
         "struct retour64\n{\n    const char *version;\n    unsigned    emplacement;\n"
         "    unsigned    taille;\n    const char *methode;\n};\n\n",
         "static const struct retour64 retours64[] =\n{\n"]
    for version in sorted(table):
        for e, t, n in table[version]:
            o.append('    { "%s", %d, %d, "%s" },\n' % (version, e, t, n))
    o.append("};\n\nstatic const char * const versions64[] =\n{\n")
    for version in sorted(table):
        o.append('    "%s",\n' % version)
    o.append("};\n")
    open(sortie, "w").write("".join(o))


if __name__ == "__main__":
    main()
