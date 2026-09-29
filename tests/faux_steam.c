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
     * L'etat que le client publie. Le code de l'enveloppe, lu en memoire, teste
     * deux mots avant d'aller plus loin :
     *
     *   cmp dword [vue+0x90], 2    sinon il abandonne (lettre « I »)
     *   cmp dword [vue+0x94], 0    la case de commande doit etre libre
     *
     * 0x90 est donc une version de protocole, et 0x94 la case ou il deposera
     * sa demande.
     */
    if (vue)
    {
        memset(vue, 0, 4096);
        *(DWORD *)((char *)vue + 0x90) = 2;

    }
    fprintf(stderr, "faux steam : pid %lu inscrit, verrou=%p segment=%p vue=%p\n",
            pid, verrou, segment, vue);
    fflush(stderr);

    /*
     * Tenir le role du client dans la poignee de main de SteamStart.
     *
     * L'enveloppe des jeux proteges n'attend pas une valeur dans le segment :
     * elle y *ecrit* une requete, puis attend que le client la traite. Le code
     * de deadcells.exe, lu en memoire pendant qu'il montrait sa boite d'erreur,
     * dit exactement quoi :
     *
     *   vue+0x94 : la commande (2)
     *   vue+0x98 : le numero du processus demandeur
     *   vue+0x9c : un evenement, cree par lui, qu'il attend cinq secondes
     *
     * Le handle appartient a son processus ; il faut donc le dupliquer chez
     * nous avant de le signaler -- ce que fait le vrai client. On remet ensuite
     * la commande a zero pour accuser reception.
     */
    for (;;)
    {
        volatile DWORD *req = (DWORD *)((char *)vue + 0x94);

        if (vue && req[0])
        {
            DWORD commande = req[0], demandeur = req[1], handle = req[2];
            HANDLE proc = OpenProcess(PROCESS_DUP_HANDLE, FALSE, demandeur);
            HANDLE chez_nous = NULL;

            if (proc && DuplicateHandle(proc, (HANDLE)(ULONG_PTR)handle, GetCurrentProcess(),
                                        &chez_nous, 0, FALSE, DUPLICATE_SAME_ACCESS))
            {
                SetEvent(chez_nous);
                CloseHandle(chez_nous);
                fprintf(stderr, "faux steam : commande %lu du processus %lu, evenement %p signale\n",
                        commande, demandeur, (void *)(ULONG_PTR)handle);
            }
            else
                fprintf(stderr, "faux steam : commande %lu du processus %lu, duplication impossible (%lu)\n",
                        commande, demandeur, GetLastError());
            if (proc) CloseHandle(proc);
            fflush(stderr);
            req[0] = 0;
        }
        Sleep(10);
    }
    return 0;
}
