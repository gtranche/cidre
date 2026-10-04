#!/usr/bin/env python3
"""Lance SteamCMD sur la session memorisee, sans jamais tenter de mot de passe.

    steamcmd_session.py <steamcmd.sh> <arguments de SteamCMD...>

Sans session memorisee, SteamCMD demande un mot de passe ; si personne ne peut
repondre (entree fermee), il envoie un mot de passe vide, et c'est une tentative
de connexion ratee sur le compte. Ici on lui prete un terminal, on relaie sa
sortie, et s'il demande un mot de passe on l'arrete AVANT qu'il n'essaie :
code de retour 3, « pas de session ». Sinon, son propre code de retour.

Le terminal a un second interet : SteamCMD n'ecrit ligne a ligne que sur un
terminal, et l'avancement d'un telechargement arrive alors au fil de l'eau.
"""
import os
import pty
import signal
import sys

PAS_DE_SESSION = (b"cached credentials not found", b"password:")


def main():
    pid, maitre = pty.fork()
    if pid == 0:
        os.execv(sys.argv[1], sys.argv[1:])
    vu = b""
    sans_session = False
    sortie = sys.stdout.buffer
    while True:
        try:
            bloc = os.read(maitre, 4096)
        except OSError:
            break
        if not bloc:
            break
        sortie.write(bloc)
        sortie.flush()
        vu = (vu + bloc.lower())[-200:]
        if any(m in vu for m in PAS_DE_SESSION):
            sans_session = True
            break
    if sans_session:
        # Tout le groupe (steamcmd.sh et le binaire qu'il a lance), et on lache
        # le terminal : un processus qui sort attend que sa sortie soit lue, et
        # resterait bloque a mi-chemin si on gardait le terminal sans le lire.
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
    os.close(maitre)
    _, etat = os.waitpid(pid, 0)
    if sans_session:
        sys.exit(3)
    sys.exit(os.WEXITSTATUS(etat) if os.WIFEXITED(etat) else 1)


if __name__ == "__main__":
    main()
