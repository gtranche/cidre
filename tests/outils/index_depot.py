#!/usr/bin/env python3
"""Les versions des fiches du depot dont part un catalogue : index-depot.toml,
publie dans l'archive de la base (.github/workflows/profils.yml) a cote de
index.toml.

    index_depot.py [dossier des fiches, profils par defaut] > index-depot.toml

Une table par fiche du depot : `empreinte`, le md5 de la fiche telle qu'elle est
(celle dont le catalogue est parti), et `anciennes`, les md5 de ses versions
precedentes dans l'historique git, separes par des espaces. Le client
(tests/fiche_profil.sh, `chemin`) s'en sert pour savoir si la copie livree d'une
fiche est plus recente que sa copie en cache : une copie livree dont le md5 est
l'empreinte ou l'une des anciennes est connue de l'archive, le cache (enrichi par
l'import) sert ; un md5 inconnu est une version que l'archive n'a pas vue (fiche
corrigee depuis, ou modifiee localement), la copie livree sert.

Il faut tout l'historique (pas de clone superficiel) : sans lui, chaque ancienne
version passerait pour plus recente que le cache. Code 0, 1 si le depot est
superficiel ou si git echoue.
"""
import hashlib
import os
import subprocess
import sys


def git(*args, entree=None):
    return subprocess.run(["git", *args], input=entree, capture_output=True, check=True).stdout


def main(argv):
    dossier = argv[1] if len(argv) > 1 else "profils"
    racine = git("-C", dossier, "rev-parse", "--show-toplevel").decode().strip()
    if git("-C", racine, "rev-parse", "--is-shallow-repository").decode().strip() == "true":
        print("index_depot.py : depot superficiel, l'historique des fiches manque (fetch-depth: 0)", file=sys.stderr)
        return 1
    rel = os.path.relpath(os.path.realpath(dossier), os.path.realpath(racine))
    fiches = sorted(n[:-5] for n in os.listdir(dossier)
                    if n.endswith(".toml") and n not in ("index.toml", "index-depot.toml"))
    # chaque blob qu'a porte chaque fiche, en une passe sur l'historique
    blobs = {}
    sortie = git("-C", racine, "log", "--format=", "--raw", "--no-abbrev", "--no-renames", "--", rel + "/")
    for ligne in sortie.decode("utf-8", "replace").splitlines():
        if not ligne.startswith(":") or "\t" not in ligne:
            continue
        champs, chemin = ligne.split("\t", 1)
        nom = os.path.basename(chemin)
        if os.path.dirname(chemin) != rel or not nom.endswith(".toml"):
            continue
        for b in champs.split()[2:4]:
            if b.strip("0"):
                blobs.setdefault(nom[:-5], set()).add(b)
    tous = sorted({b for s in blobs.values() for b in s})
    md5 = {}
    if tous:
        # git cat-file --batch : `<sha> blob <taille>\n<contenu>\n` par objet
        brut = git("-C", racine, "cat-file", "--batch", entree=("\n".join(tous) + "\n").encode())
        i = 0
        for b in tous:
            fin = brut.index(b"\n", i)
            taille = int(brut[i:fin].split()[2])
            md5[b] = hashlib.md5(brut[fin + 1:fin + 1 + taille]).hexdigest()
            i = fin + 1 + taille + 1
    print("# Versions des fiches du depot dont part ce catalogue (tests/outils/index_depot.py) :")
    print("# empreinte = md5 de la fiche du depot, anciennes = md5 de ses versions precedentes.")
    print("# tests/fiche_profil.sh s'en sert pour preferer une copie livree plus recente que le cache.")
    for a in fiches:
        with open(os.path.join(dossier, a + ".toml"), "rb") as f:
            e = hashlib.md5(f.read()).hexdigest()
        anciennes = sorted({md5[b] for b in blobs.get(a, ())} - {e})
        print()
        print(f"[{a}]")
        print(f'empreinte = "{e}"')
        print(f'anciennes = "{" ".join(anciennes)}"')
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"index_depot.py : {e}", file=sys.stderr)
        sys.exit(1)
