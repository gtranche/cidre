#!/usr/bin/env python3
"""Embarque dans le runtime les bibliotheques Homebrew dont il depend.

    embarquer_dependances.py <dossier du runtime> [bibliotheque chargee par dlopen ...]

Les binaires construits ici lient des bibliotheques Homebrew par leur chemin
absolu (/opt/homebrew/...) : sur une machine sans Homebrew, le pilote Vulkan ne
se charge pas et rien ne s'affiche. On copie ces bibliotheques dans
<runtime>/libs, avec celles dont elles dependent elles-memes, et on reecrit les
chemins en @loader_path : le runtime ne depend plus que du systeme.

Les bibliotheques que Wine charge par dlopen (FreeType) ne sont liees par aucun
binaire : on les nomme en argument, et le lanceur les prend dans <runtime>/libs.

Modifier un binaire invalide sa signature ; sur Apple Silicon il ne se charge
plus. On resigne donc (ad hoc) tout ce qu'on a touche.
"""
import os
import shutil
import subprocess
import sys

HOMEBREW = ("/opt/homebrew/", "/usr/local/")


def sortie(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def est_macho(chemin):
    try:
        with open(chemin, "rb") as f:
            return f.read(4) in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf")
    except OSError:
        return False


def dependances(chemin):
    """Les bibliotheques Homebrew que lie ce binaire (hors son propre identifiant)."""
    lignes = sortie("otool", "-L", chemin).splitlines()[1:]
    deps = [l.split(" (")[0].strip() for l in lignes]
    return [d for d in deps if d.startswith(HOMEBREW)]


def main():
    runtime = os.path.realpath(sys.argv[1])
    libs = os.path.join(runtime, "libs")
    os.makedirs(libs, exist_ok=True)
    touches = set()
    embarquees = {}  # nom de fichier -> chemin Homebrew d'origine

    def embarquer(origine):
        """Copie une bibliotheque Homebrew dans libs/, et celles dont elle depend."""
        nom = os.path.basename(origine)
        if nom in embarquees:
            return nom
        reel = os.path.realpath(origine)
        if not os.path.isfile(reel):
            sys.exit("bibliotheque introuvable : %s (brew install ?)" % origine)
        embarquees[nom] = reel
        cible = os.path.join(libs, nom)
        shutil.copyfile(reel, cible)
        os.chmod(cible, 0o755)
        subprocess.run(["install_name_tool", "-id", "@loader_path/" + nom, cible],
                       check=True, capture_output=True)
        relier(cible)
        touches.add(cible)
        return nom

    def relier(binaire):
        """Remplace les chemins Homebrew de ce binaire par des chemins vers libs/."""
        vers_libs = os.path.relpath(libs, os.path.dirname(binaire))
        for dep in dependances(binaire):
            if os.path.basename(dep) == os.path.basename(binaire) and binaire.startswith(libs):
                continue  # son propre identifiant
            nom = embarquer(dep)
            nouveau = "@loader_path/" + ("" if vers_libs == "." else vers_libs + "/") + nom
            subprocess.run(["install_name_tool", "-change", dep, nouveau, binaire],
                           check=True, capture_output=True)
            touches.add(binaire)

    for dossier, sous, fichiers in os.walk(runtime):
        if dossier == libs:
            continue
        for f in fichiers:
            chemin = os.path.join(dossier, f)
            if not os.path.islink(chemin) and est_macho(chemin):
                relier(chemin)

    for origine in sys.argv[2:]:
        embarquer(origine)

    for chemin in sorted(touches):
        subprocess.run(["codesign", "--force", "--sign", "-", chemin], check=True, capture_output=True)

    # Garde-fou : plus rien ne doit pointer vers Homebrew.
    restes = []
    for dossier, sous, fichiers in os.walk(runtime):
        for f in fichiers:
            chemin = os.path.join(dossier, f)
            if not os.path.islink(chemin) and est_macho(chemin):
                restes += ["%s -> %s" % (os.path.relpath(chemin, runtime), d) for d in dependances(chemin)
                           if not (dossier == libs and os.path.basename(d) == f)]
    if restes:
        sys.exit("dependances Homebrew restantes :\n  " + "\n  ".join(restes))

    for nom, origine in sorted(embarquees.items()):
        print("  libs/%s  <-  %s" % (nom, origine))
    print("  %d binaires relies et resignes" % len(touches))


if __name__ == "__main__":
    main()
