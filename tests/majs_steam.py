#!/usr/bin/env python3
"""Compare les jeux installes a la derniere version publiee (pour `cidre updates`).

    majs_steam.py <appinfo.txt> <appid>=<build installe> ...

appinfo.txt est la sortie de `steamcmd +app_info_print <appid>` : pour chaque
application, sa fiche, dont le numero de build de la branche publique. Un jeu
est a jour quand son build installe est celui-la.
"""
import json
import re
import sys


def main():
    texte = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    publies = {}
    fiches = list(re.finditer(r"^AppID : (\d+)", texte, re.M))
    for i, m in enumerate(fiches):
        fin = fiches[i + 1].start() if i + 1 < len(fiches) else len(texte)
        build = re.search(r'"branches"\s*\{\s*"public"\s*\{[^{}]*?"buildid"\s*"(\d+)"', texte[m.end():fin])
        if build:
            publies[int(m.group(1))] = int(build.group(1))
    majs = []
    for arg in sys.argv[2:]:
        appid, _, installe = arg.partition("=")
        if not (appid.isdigit() and installe.isdigit()) or int(appid) not in publies:
            continue  # pas de build connu d'un cote ou de l'autre : on ne dit rien
        dispo = publies[int(appid)]
        majs.append({"appid": int(appid), "build_installe": int(installe),
                     "build_disponible": dispo, "a_jour": int(installe) == dispo})
    json.dump(majs, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
