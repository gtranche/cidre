/* Un processus que steam_api accepte comme etant le client Steam.
 *
 * SteamAPI_Init verifie que le processus designe par
 * HKCU\Software\Valve\Steam\ActiveProcess\pid est vivant. Sans lui, il attend
 * indefiniment que Steam apparaisse -- et c'est bien ce qu'on observait. Le
 * client qui repond reellement est celui de macOS, derriere l'unixlib ; il
 * suffit donc d'un processus Windows vivant dans le prefixe, qui inscrit son
 * propre identifiant.
 *
 * L'enveloppe SteamStub des jeux proteges, elle, ne passe pas par le registre :
 * elle ouvre deux objets nommes que le vrai client Windows cree, un evenement
 * et un segment de memoire partagee. Sans eux elle refuse de dechiffrer le jeu
 * et affiche « Application load error 3:0000065432 ». On les cree donc ici. Ce
 * qu'elle y lit reste a etablir : le segment est rendu a zero pour commencer,
 * et la trace dira ce qu'elle en fait.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    HKEY cle;
    DWORD pid = GetCurrentProcessId();

    if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                        0, NULL, 0, KEY_WRITE, NULL, &cle, NULL))
    { fprintf(stderr, "cle impossible\n"); return 1; }
    RegSetValueExA(cle, "pid", 0, REG_DWORD, (const BYTE *)&pid, sizeof(pid));
    RegCloseKey(cle);

    /* Les noms sont ceux que la trace de deadcells.exe montre : OpenEventA sur
     * SteamStart_SharedMemLock, puis OpenFileMappingA sur
     * SteamStart_SharedMemFile. L'evenement est cree signale -- le stub
     * l'ouvre avec SYNCHRONIZE, donc il l'attend. */
    HANDLE verrou = CreateEventA(NULL, TRUE, TRUE, "Local\\SteamStart_SharedMemLock");
    HANDLE segment = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
                                        4096, "Local\\SteamStart_SharedMemFile");
    void *vue = segment ? MapViewOfFile(segment, FILE_MAP_ALL_ACCESS, 0, 0, 4096) : NULL;

    /*
     * Le contenu attendu n'est pas documente. Premiere tentative, volontairement
     * grossiere : remplir toute la page du numero du processus, repete en mots
     * de quatre octets. Si l'enveloppe lit un identifiant a un decalage que l'on
     * ignore, elle le trouvera quel qu'il soit. Si elle y cherche autre chose,
     * le refus sera le meme et on aura elimine cette hypothese en une fois.
     */
    if (vue)
    {
        DWORD *mots = vue;
        unsigned i;

        for (i = 0; i < 4096 / sizeof(*mots); i++) mots[i] = pid;
    }
    fprintf(stderr, "faux steam : pid %lu inscrit, verrou=%p segment=%p vue=%p\n",
            pid, verrou, segment, vue);
    fflush(stderr);
    for (;;) Sleep(1000);
    return 0;
}
