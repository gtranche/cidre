#!/usr/bin/env python3
"""Ajoute un jeu non-Steam dans shortcuts.vdf, et l'associe a notre outil.

    ajouter_raccourci_steam.py <chemin.exe> [nom affiche]

Le selecteur de fichiers macOS refuse les .exe, donc on ecrit le raccourci
directement. Le format binaire de shortcuts.vdf tient en trois marqueurs :
0x00 ouvre une table, 0x01 introduit une chaine, 0x02 un entier 32 bits, et
0x08 ferme. Steam doit etre arrete : il reecrit ce fichier en quittant.
"""
import os
import sys
import zlib

RACINE = os.path.expanduser("~/Library/Application Support/Steam")


def identifiant(exe_cite, nom):
    """Identifiant que Steam attribue a un raccourci : le CRC32 du couple,
    avec le bit de poids fort arme."""
    return (zlib.crc32((exe_cite + nom).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def chaine(cle, valeur):
    return b"\x01" + cle.encode() + b"\x00" + valeur.encode("utf-8") + b"\x00"


def entier(cle, valeur):
    return b"\x02" + cle.encode() + b"\x00" + (valeur & 0xFFFFFFFF).to_bytes(4, "little")


def construire(exe, nom):
    # Le client macOS ajoute lui-meme les guillemets : les mettre ici les double
    # et rend le chemin invalide.
    exe_cite = exe
    depart = os.path.dirname(exe)
    appid = identifiant(exe_cite, nom)

    corps = b"\x00" + b"0" + b"\x00"
    corps += entier("appid", appid)
    corps += chaine("AppName", nom)
    corps += chaine("Exe", exe_cite)
    corps += chaine("StartDir", depart)
    corps += chaine("icon", "")
    corps += chaine("ShortcutPath", "")
    corps += chaine("LaunchOptions", "")
    corps += entier("IsHidden", 0)
    corps += entier("AllowDesktopConfig", 1)
    corps += entier("AllowOverlay", 1)
    corps += entier("OpenVR", 0)
    corps += entier("Devkit", 0)
    corps += chaine("DevkitGameID", "")
    corps += entier("DevkitOverrideAppID", 0)
    corps += entier("LastPlayTime", 0)
    corps += chaine("FlatpakAppID", "")
    corps += b"\x00" + b"tags" + b"\x00" + b"\x08"
    corps += b"\x08"

    return b"\x00" + b"shortcuts" + b"\x00" + corps + b"\x08\x08", appid


def main(args):
    if not args:
        print(__doc__)
        return 2
    exe = os.path.abspath(args[0])
    nom = args[1] if len(args) > 1 else os.path.basename(exe)
    if not os.path.isfile(exe):
        print("introuvable : %s" % exe)
        return 2

    if os.popen("pgrep -f steam_osx").read().strip():
        print("Steam tourne : il reecrirait ce fichier en quittant. Arrete-le d'abord.")
        return 1

    users = os.path.join(RACINE, "userdata")
    comptes = [d for d in os.listdir(users) if d.isdigit() and d != "0"]
    if len(comptes) != 1:
        print("comptes trouves : %s — cas non gere" % comptes)
        return 1

    cible = os.path.join(users, comptes[0], "config", "shortcuts.vdf")
    if os.path.exists(cible):
        with open(cible, "rb") as f:
            ancien = f.read()
        if len(ancien) > 13:
            print("shortcuts.vdf contient deja des raccourcis, je n'ecrase pas")
            return 1
        with open(cible + ".avant-proton-ouvert", "wb") as f:
            f.write(ancien)

    donnees, appid = construire(exe, nom)
    with open(cible, "wb") as f:
        f.write(donnees)

    print("raccourci ecrit : %s" % cible)
    print("nom            : %s" % nom)
    print("identifiant    : %u" % appid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
