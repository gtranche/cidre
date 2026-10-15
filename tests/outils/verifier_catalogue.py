#!/usr/bin/env python3
"""Verifie un catalogue de fiches genere (importer_profils.py --catalogue-protondb)
contre les fiches du depot, avant de le publier.

    verifier_catalogue.py <profils du depot> <catalogue genere>

1. Rien d'ecrit a la main n'a bouge : pour chaque fiche du depot, toute valeur
   dont la provenance n'est pas une source d'import rejouable (steam, protondb,
   pcgamingwiki, applegamingwiki) -- sans provenance, cidre-test, utilisateur,
   crossover, winehq... -- se retrouve telle quelle dans le catalogue, comme les
   tableaux de tables ([[rapports]], [[reglages_jeu]], [[machine]]).
2. L'index et les fiches vont ensemble : chaque entree de index.toml a sa fiche,
   chaque fiche a son entree.
3. Chaque fiche se relit (TOML valide).
Code 0 si tout tient, 1 sinon (la liste des ecarts sur la sortie d'erreur).
"""
import os
import sys
import tomllib

REJOUABLES = ("steam", "protondb", "pcgamingwiki", "applegamingwiki")


def source_de(table, cle):
    """Meme regle que Fiche.source_de de l'importeur : [x.sources] cle, sinon la
    `source` de la table, sinon None (a la main)."""
    s = table.get("sources", {}).get(cle) if isinstance(table.get("sources"), dict) else None
    if isinstance(s, str) and s:
        return s.split()[0]
    if isinstance(table.get("source"), str):
        return table["source"]
    return None


def ecarts(avant, apres, chemin=""):
    """Les cles protegees de `avant` absentes ou changees dans `apres`."""
    out = []
    for cle, v in avant.items():
        ici = f"{chemin}.{cle}" if chemin else cle
        if cle == "sources" and isinstance(v, dict):
            # la provenance d'une cle protegee ne bouge pas non plus
            for k, s in v.items():
                if (s.split() or [""])[0] not in REJOUABLES and apres.get("sources", {}).get(k) != s:
                    out.append(f"{ici}.{k}")
            continue
        if isinstance(v, dict):
            sous = apres.get(cle)
            if not isinstance(sous, dict):
                out.append(ici)
            else:
                out += ecarts(v, sous, ici)
            continue
        if isinstance(v, list) and v and isinstance(v[0], dict):
            if apres.get(cle) != v:  # [[rapports]], [[reglages_jeu]], [[machine]] : intouchables
                out.append(ici)
            continue
        if source_de(avant, cle) in REJOUABLES:
            continue
        if cle not in apres or apres[cle] != v:
            out.append(ici)
    return out


def lire(chemin):
    with open(chemin, "rb") as f:
        return tomllib.load(f)


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    depot, catalogue = argv[1], argv[2]
    fautes = []
    fiches = sorted(n for n in os.listdir(catalogue) if n.endswith(".toml") and n != "index.toml")
    for n in fiches:
        try:
            apres = lire(os.path.join(catalogue, n))
        except (OSError, tomllib.TOMLDecodeError) as e:
            fautes.append(f"{n} : illisible ({e})")
            continue
        p = os.path.join(depot, n)
        if os.path.exists(p):
            for e in ecarts(lire(p), apres):
                fautes.append(f"{n} : {e} ecrite a la main, changee ou perdue")
    for n in sorted(os.listdir(depot)):
        if n.endswith(".toml") and n != "index.toml" and not os.path.exists(os.path.join(catalogue, n)):
            fautes.append(f"{n} : fiche du depot absente du catalogue")
    try:
        index = lire(os.path.join(catalogue, "index.toml"))
    except (OSError, tomllib.TOMLDecodeError) as e:
        index = {}
        fautes.append(f"index.toml : illisible ({e})")
    noms = {n[:-5] for n in fiches}
    for a in sorted(set(index) - noms):
        fautes.append(f"index.toml : {a} sans fiche")
    for a in sorted(noms - set(index)):
        fautes.append(f"{a}.toml : absente de l'index")
    for f in fautes[:200]:
        print(f, file=sys.stderr)
    print(f"{len(fiches)} fiche(s), {len(index)} entree(s) d'index, {len(fautes)} ecart(s)")
    return 1 if fautes else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
