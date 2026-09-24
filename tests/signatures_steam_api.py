"""Relever les signatures Steamworks dans le steam_api.dll i386 d'un jeu.

Pourquoi
--------
En 32 bits, une methode virtuelle MSVC est appelee en __thiscall : c'est
l'appele qui depile. Un relais generique doit donc connaitre, methode par
methode, le nombre d'octets empiles -- ce que le SDK donne et qu'on s'interdit.

Mais le steam_api.dll livre avec le jeu exporte des enveloppes plates nommees,
une par methode, et chacune montre tout ce qu'il faut :

    SteamAPI_ISteamUser_GetSteamID :
        mov  0x8(%ebp),%ecx      this
        lea  -0x8(%ebp),%edx     tampon de retour
        push %edx                pointeur cache empile
        call *0x8(%eax)          emplacement 2

On y lit le nom, l'interface, l'emplacement, les octets empiles et le retour
par pointeur cache. Aucun en-tete n'est necessaire.
"""
import re, subprocess, sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exports_pe import exports

OBJDUMP = "i686-w64-mingw32-objdump"


def desassembler(chemin):
    """Desassemble .text une fois et indexe les instructions par adresse."""
    out = subprocess.run([OBJDUMP, "--disassemble", "--no-show-raw-insn", "-j", ".text", chemin],
                         capture_output=True, text=True).stdout
    instr = {}
    pat = re.compile(r"^\s*([0-9a-f]+):\s+(\S+)\s*(.*)$")
    for l in out.splitlines():
        m = pat.match(l)
        if m:
            instr[int(m.group(1), 16)] = (m.group(2), m.group(3).split("#")[0].strip())
    return instr


def analyser(instr, debut, base):
    """Rend (emplacement, octets empiles, taille du tampon) ou None.

    Une methode sans argument se termine par un saut de queue plutot que par un
    appel : « mov (%ecx),%eax ; jmp *(%eax) ». Il faut l'accepter, sinon on perd
    justement les methodes les plus simples.
    """
    p = debut
    pousses = 0
    tampon = 0
    edx_local = 0
    for _ in range(64):
        while p not in instr and p < debut + 160:
            p += 1
        if p not in instr:
            return None
        mn, op = instr[p]
        if mn.startswith("call") or mn.startswith("jmp"):
            m = re.match(r"\*(?:(0x[0-9a-f]+))?\(%eax\)$", op)
            if not m:
                return None
            dep = int(m.group(1), 16) if m.group(1) else 0
            return dep // 4, pousses * 4, tampon
        if mn.startswith("ret"):
            return None
        # « lea -0x18(%ebp),%edx » : un tampon local, dont le deplacement donne
        # la taille de la structure rendue.
        m = re.match(r"-(0x[0-9a-f]+)\(%ebp\),%edx$", op)
        if mn == "lea" and m:
            edx_local = int(m.group(1), 16)
        if mn == "push":
            # Le prologue empile %ebp et les registres sauvegardes par l'appele ;
            # ce ne sont pas des arguments.
            if op not in ("%ebp", "%ebx", "%esi", "%edi"):
                pousses += 1
            if op == "%edx" and edx_local:
                tampon = edx_local
        p += 1
    return None


def main(chemin):
    instr = desassembler(chemin)
    base = 0
    out = subprocess.run([OBJDUMP, "-h", chemin], capture_output=True, text=True).stdout
    m = re.search(r"\.text\s+\S+\s+([0-9a-f]+)\s+\S+\s+([0-9a-f]+)", out)
    vma_text, off_text = int(m.group(1), 16), int(m.group(2), 16)
    imagebase = int(re.search(r"ImageBase\s+([0-9a-f]+)",
                    subprocess.run([OBJDUMP, "-p", chemin], capture_output=True, text=True).stdout).group(1), 16)

    res = {}
    for nom, rva in exports(chemin).items():
        m = re.match(r"SteamAPI_(ISteam[A-Za-z]+)_(\w+)$", nom)
        if not m:
            continue
        a = analyser(instr, imagebase + rva, imagebase)
        if a is None:
            continue
        emplacement, octets, tampon = a
        res.setdefault(m.group(1), {})[m.group(2)] = {
            "emplacement": emplacement, "octets": octets, "tampon": tampon}
    return res


if __name__ == "__main__":
    r = main(sys.argv[1])
    json.dump(r, open("/tmp/signatures.json", "w"), indent=1, sort_keys=True)
    total = sum(len(v) for v in r.values())
    print("%d interfaces, %d methodes" % (len(r), total))
    for i in sorted(r, key=lambda k: -len(r[k]))[:8]:
        print("  %-28s %d methodes" % (i, len(r[i])))
