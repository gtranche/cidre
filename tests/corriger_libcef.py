#!/usr/bin/env python3
"""Neutralise command_line_args_disabled dans le libcef.dll du Steam Windows.

    corriger_libcef.py <chemin/libcef.dll>            applique
    corriger_libcef.py <chemin/libcef.dll> --annuler  remet les octets d'origine

Pourquoi
--------
Steam initialise CEF avec command_line_args_disabled, ce qui fait ignorer a
Chromium tous ses arguments de ligne de commande. Nos drapeaux -cef-disable-gpu
arrivent bien sur la ligne de commande du webhelper — verifie — et n'ont aucun
effet : le processus GPU demarre quand meme et rompt sur un point d'arret, a
libcef.dll + 0x59EF905. D'ou la fenetre noire.

CrossOver traite le meme probleme (CW HACK 23854) en corrigeant libcef.dll a des
decalages fixes, version par version. Leur table ne couvre pas le CEF de Chrome
126 qu'embarque le Steam actuel, mais la fonction qui recopie cef_settings_t a
exactement la meme forme, aux memes decalages, seul le registre de destination
differant :

    0x2781A3  mov eax,[rdi+0x58]  mov [rsi+0x58],eax
    0x2781A9  mov eax,[rdi+0x5c]  mov [rsi+0x5c],eax
    0x2781AF  mov eax,[rdi+0x60]  mov [rsi+0x60],eax
    0x2781B5  mov eax,[rdi+0x64]  mov [rsi+0x64],eax
    0x2781BB  mov eax,[rdi+0x68]  mov [rsi+0x68],eax   <- le champ vise
    0x2781C1  lea r8,[rsi+0x70]   (une chaine suit)

On remplace le chargement par « xor eax,eax ; nop », donc le champ est recopie a
zero. Trois octets, reversibles.

Ce qu'il faut savoir
--------------------
Steam peut detecter le fichier modifie et le retelecharger, ce qui annule le
correctif sans prevenir. Et toute mise a jour du client remet le binaire
d'origine, avec des decalages potentiellement differents : le script refuse alors
d'agir plutot que d'ecrire a l'aveugle.
"""
import os
import sys

OFFSET = 0x2781BB
ORIGINE = bytes([0x8B, 0x47, 0x68])   # mov eax,[rdi+0x68]
CORRIGE = bytes([0x31, 0xC0, 0x90])   # xor eax,eax ; nop


def main(args):
    if not args:
        print(__doc__)
        return 2
    chemin = args[0]
    annuler = "--annuler" in args[1:]

    if not os.path.isfile(chemin):
        print("introuvable : %s" % chemin)
        return 2

    with open(chemin, "rb") as f:
        donnees = bytearray(f.read())

    actuel = bytes(donnees[OFFSET:OFFSET + 3])
    attendu = CORRIGE if annuler else ORIGINE
    nouveau = ORIGINE if annuler else CORRIGE

    if actuel == nouveau:
        print("deja dans l'etat demande")
        return 0
    if actuel != attendu:
        print("octets inattendus a 0x%X : %s" % (OFFSET, actuel.hex(" ")))
        print("le binaire n'est pas celui attendu — rien n'a ete ecrit.")
        return 1

    donnees[OFFSET:OFFSET + 3] = nouveau
    with open(chemin, "wb") as f:
        f.write(bytes(donnees))
    print("%s : 0x%X %s -> %s" % ("annule" if annuler else "corrige",
                                  OFFSET, actuel.hex(" "), nouveau.hex(" ")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
