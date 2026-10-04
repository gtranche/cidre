#!/usr/bin/env python3
"""Les jeux que possede le compte Steam, en JSON (pour `cidre library`).

    bibliotheque_steam.py <licences.txt> [appid installe ...]

licences.txt est la sortie de `steamcmd +login <compte> +licenses_print` : elle
dit quels paquets le compte possede, et les applications de chacun. Les noms,
types et plateformes viennent du cache du client Steam (appcache/appinfo.vdf,
format binaire v27 a v29), qu'on lit sans rien y ecrire. SteamCMD tronque la
liste d'applications des gros paquets : on la complete par packageinfo.vdf.
"""
import json
import os
import re
import struct
import sys

STEAM = os.path.expanduser("~/Library/Application Support/Steam")


def lire_vdf_binaire(d, pos, table=None):
    """Un dictionnaire VDF binaire a partir de pos ; rend (dict, position suivante)."""
    out = {}
    while True:
        t = d[pos]
        pos += 1
        if t in (0x08, 0x0B):
            return out, pos
        if table is not None:
            cle = table[struct.unpack_from("<i", d, pos)[0]]
            pos += 4
        else:
            fin = d.index(b"\0", pos)
            cle = d[pos:fin].decode("utf-8", "replace")
            pos = fin + 1
        if t == 0x00:
            out[cle], pos = lire_vdf_binaire(d, pos, table)
        elif t == 0x01:
            fin = d.index(b"\0", pos)
            out[cle] = d[pos:fin].decode("utf-8", "replace")
            pos = fin + 1
        elif t in (0x02, 0x03):
            out[cle] = struct.unpack_from("<i", d, pos)[0]
            pos += 4
        elif t in (0x07, 0x0A):
            out[cle] = struct.unpack_from("<q", d, pos)[0]
            pos += 8
        else:
            raise ValueError("type VDF inconnu : %#x" % t)


def lire_appinfo(chemin, voulus):
    """{appid: section `common`} pour les appids voulus."""
    d = open(chemin, "rb").read()
    magie = struct.unpack_from("<I", d, 0)[0]
    version = magie & 0xFF
    if magie >> 8 != 0x075644 or version not in (0x27, 0x28, 0x29):
        raise ValueError("appinfo.vdf : format inconnu (%#x)" % magie)
    pos, table = 8, None
    if version == 0x29:
        debut = struct.unpack_from("<q", d, 8)[0]
        pos = 16
        n = struct.unpack_from("<I", d, debut)[0]
        table = [s.decode("utf-8", "replace") for s in d[debut + 4:].split(b"\0", n)[:n]]
    # entete d'une entree, apres appid et taille : etat, date, jeton, sha1,
    # numero de changement, et (v28+) sha1 binaire
    entete = 4 + 4 + 8 + 20 + 4 + (20 if version >= 0x28 else 0)
    out = {}
    while True:
        appid = struct.unpack_from("<I", d, pos)[0]
        if appid == 0:
            return out
        taille = struct.unpack_from("<I", d, pos + 4)[0]
        if appid in voulus:
            try:
                arbre, _ = lire_vdf_binaire(d, pos + 8 + entete, table)
                out[appid] = arbre.get("appinfo", arbre).get("common", {})
            except (ValueError, IndexError, struct.error):
                pass
        pos += 8 + taille


def lire_paquets(chemin):
    """{packageid: [appids]} depuis packageinfo.vdf ; vide si illisible."""
    try:
        d = open(chemin, "rb").read()
        magie = struct.unpack_from("<I", d, 0)[0]
        version = magie & 0xFF
        if magie >> 8 != 0x065655 or version not in (0x27, 0x28):
            return {}
        pos, out = 8, {}
        while True:
            pid = struct.unpack_from("<I", d, pos)[0]
            if pid == 0xFFFFFFFF:
                return out
            pos += 4 + 20 + 4 + (8 if version == 0x28 else 0)
            arbre, pos = lire_vdf_binaire(d, pos)
            corps = next(iter(arbre.values()), {}) if arbre else {}
            out[pid] = [v for v in corps.get("appids", {}).values() if isinstance(v, int)]
    except (OSError, ValueError, IndexError, struct.error):
        return {}


def main():
    licences = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    installes = {int(a) for a in sys.argv[2:] if a.isdigit()}
    paquets = lire_paquets(os.path.join(STEAM, "appcache/packageinfo.vdf"))
    possedes = set()
    for m in re.finditer(r"^License packageID (\d+):.*?^ - Apps\s*:([^\n]*)", licences, re.M | re.S):
        pid, apps = int(m.group(1)), m.group(2)
        possedes.update(int(a) for a in re.findall(r"\d+", apps.split("(")[0]))
        if "..." in apps:
            possedes.update(paquets.get(pid, []))
    infos = lire_appinfo(os.path.join(STEAM, "appcache/appinfo.vdf"), possedes)
    jeux = []
    for appid, c in infos.items():
        if str(c.get("type", "")).lower() != "game" or not c.get("name"):
            continue
        # sans oslist, Steam considere le jeu comme Windows
        os_ = [o for o in str(c.get("oslist") or "windows").split(",") if o in ("windows", "macos")]
        if not os_:
            continue
        jeux.append({"appid": appid, "nom": c["name"], "plateformes": os_, "installe": appid in installes})
    jeux.sort(key=lambda j: j["nom"].lower())
    json.dump(jeux, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
