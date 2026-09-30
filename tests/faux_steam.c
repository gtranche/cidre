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
#include <wchar.h>
#include <winternl.h>

/* ---------------------------------------------------------------------------
 * La poignee de main SteamStart, telle que Proton la tient.
 *
 * Source primaire : Proton, steam_helper/steam.cpp, fonction steam_drm_thread,
 * branche proton_9.0. Le script `proton` lance chaque jeu par
 * c:\windows\system32\steam.exe -- le steam_helper de Proton, pas le client de
 * Valve -- et ce steam.exe demarre le fil ci-dessous pour tout jeu.
 *
 * Le protocole a deux moities. On ne connaissait que la seconde :
 *
 *   - deux semaphores nommes encadrent le segment partage. PRODUCE nait a 1
 *     (la case est libre), CONSUME a 0 (aucune requete en attente). Le jeu
 *     prend PRODUCE, ecrit sa demande, rend CONSUME ; le client attend
 *     CONSUME, traite, rend PRODUCE. Sans eux le jeu n'a jamais le jeton qui
 *     l'autorise a ecrire -- ce que notre scrutation du segment ne pouvait pas
 *     lui donner.
 *
 *   - le jeu cree un evenement dont le nom commence par STEAM_START_ACK_EVENT
 *     et se termine par un suffixe variable, donc introuvable par son nom : il
 *     faut enumerer le repertoire d'objets et le reconnaitre a son prefixe.
 *
 * Le nom « SREAM_DIPC_PRODUCE » n'est pas une faute de frappe de notre part :
 * c'est celle de Valve, et le nom doit etre reproduit tel quel pour que les
 * deux cotes designent le meme objet.
 */
#ifndef DIRECTORY_QUERY
#define DIRECTORY_QUERY 0x0001
#endif

typedef struct { UNICODE_STRING nom; UNICODE_STRING type; } INFO_REPERTOIRE;
typedef NTSTATUS (NTAPI *ouvrir_repertoire_t)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES);
typedef NTSTATUS (NTAPI *lire_repertoire_t)(HANDLE, PVOID, ULONG, BOOLEAN, BOOLEAN, PULONG, PULONG);

static const WCHAR prefixe_ack[] = L"STEAM_START_ACK_EVENT";
#define LONGUEUR_PREFIXE_ACK 21   /* sans le zero final */

/* Chercher l'evenement d'accuse dans un repertoire d'objets donne. */
static HANDLE chercher_ack_dans(const WCHAR *repertoire)
{
    static ouvrir_repertoire_t ouvrir;
    static lire_repertoire_t lire;
    INFO_REPERTOIRE *info;
    OBJECT_ATTRIBUTES attr;
    UNICODE_STRING chemin;
    HANDLE rep = NULL, trouve = NULL;
    ULONG contexte = 0, taille;
    char tampon[1024];
    NTSTATUS st;
    BOOLEAN debut = TRUE;

    if (!ouvrir)
    {
        HMODULE nt = GetModuleHandleA("ntdll.dll");
        ouvrir = (ouvrir_repertoire_t)GetProcAddress(nt, "NtOpenDirectoryObject");
        lire = (lire_repertoire_t)GetProcAddress(nt, "NtQueryDirectoryObject");
    }
    if (!ouvrir || !lire) return NULL;

    chemin.Buffer = (PWSTR)repertoire;
    chemin.Length = (USHORT)(wcslen(repertoire) * sizeof(WCHAR));
    chemin.MaximumLength = (USHORT)(chemin.Length + sizeof(WCHAR));
    memset(&attr, 0, sizeof(attr));
    attr.Length = sizeof(attr);
    attr.ObjectName = &chemin;

    if (ouvrir(&rep, DIRECTORY_QUERY, &attr)) return NULL;

    info = (INFO_REPERTOIRE *)tampon;
    while (!(st = lire(rep, info, sizeof(tampon), TRUE, debut, &contexte, &taille)))
    {
        debut = FALSE;
        if (info->nom.Length >= LONGUEUR_PREFIXE_ACK * sizeof(WCHAR) &&
            !wcsncmp(info->nom.Buffer, prefixe_ack, LONGUEUR_PREFIXE_ACK))
        {
            /* Le nom rendu n'est pas garanti termine par un zero : on le
             * recopie avant de s'en servir. Proton s'en sert tel quel ; c'est
             * un pari que rien n'oblige a prendre. */
            WCHAR nom[256];
            unsigned n = info->nom.Length / sizeof(WCHAR);

            if (n >= 256) n = 255;
            memcpy(nom, info->nom.Buffer, n * sizeof(WCHAR));
            nom[n] = 0;
            /* Proton ouvre avec SYNCHRONIZE seul, puis appelle SetEvent, qui
             * demande EVENT_MODIFY_STATE : Wine ne le verifie pas, donc le
             * defaut ne se voit pas. On demande le droit qu'on exerce. */
            trouve = OpenEventW(EVENT_MODIFY_STATE | SYNCHRONIZE, FALSE, nom);
            fprintf(stderr, "faux steam : accuse %ls -> %p\n", nom, trouve);
            break;
        }
    }
    CloseHandle(rep);
    return trouve;
}

static HANDLE chercher_ack(void)
{
    /* Proton ne regarde que dans la session 1. On garde la racine en second
     * recours : rien ne garantit que notre prefixe range ses objets au meme
     * endroit, et un echec silencieux ici ressemblerait a un jeu muet. */
    HANDLE h = chercher_ack_dans(L"\\BaseNamedObjects\\Session\\1");
    if (!h) h = chercher_ack_dans(L"\\BaseNamedObjects");
    return h;
}

static DWORD WINAPI fil_drm(void *inutilise)
{
    HANDLE consommer, produire;

    (void)inutilise;
    consommer = CreateSemaphoreA(NULL, 0, 512, "STEAM_DIPC_CONSUME");
    produire  = CreateSemaphoreA(NULL, 1, 512, "SREAM_DIPC_PRODUCE");
    if (!consommer || !produire)
    {
        fprintf(stderr, "faux steam : semaphores impossibles (%lu)\n", GetLastError());
        return 1;
    }
    fprintf(stderr, "faux steam : semaphores DIPC en place (consommer=%p produire=%p)\n",
            consommer, produire);
    fflush(stderr);

    while (WaitForSingleObject(consommer, INFINITE) == WAIT_OBJECT_0)
    {
        /* Proton retient le premier accuse trouve pour toute la duree du
         * processus. Notre client survit a plusieurs jeux successifs, donc on
         * cherche a chaque tour : l'evenement appartient au jeu en cours. */
        HANDLE ack = chercher_ack();

        fprintf(stderr, "faux steam : requete DIPC%s\n", ack ? "" : ", aucun accuse trouve");
        if (ack) { SetEvent(ack); CloseHandle(ack); }
        ReleaseSemaphore(produire, 1, NULL);
        fflush(stderr);
    }
    return 0;
}

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
    CreateThread(NULL, 0, fil_drm, NULL, 0, NULL);

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

            /*
             * Ce que la requete porte d'autre. Le code du stub, lu au §263,
             * remplit encore +0xa0, +0xa4, +0xa8 et +0xac depuis son propre
             * etat ; on ne sait pas ce que c'est, alors on le montre.
             */
            {
                const DWORD *m = (const DWORD *)((const char *)vue + 0x90);
                unsigned k;

                fprintf(stderr, "faux steam : requete");
                for (k = 0; k < 10; k++) fprintf(stderr, " +%02x=%08lx", 0x90 + k * 4, m[k]);
                fprintf(stderr, "\n");
            }
            /*
             * Ce que le vrai client fait ensuite : lancer l'application. Le
             * stub s'efface en code 51 -- il l'annonce lui-meme en +0xa8 -- et
             * compte sur Steam pour le relancer. La seconde instance doit se
             * distinguer de la premiere ; l'hypothese testee ici est la
             * filiation, le jeu lance par Steam ayant Steam pour parent.
             *
             * FAUX_STEAM_JEU donne le chemin. Un seul lancement, sinon les
             * deux processus se relanceraient l'un l'autre sans fin.
             */
            {
                static int deja;
                char jeu[MAX_PATH] = { 0 };

                if (!deja && GetEnvironmentVariableA("FAUX_STEAM_JEU", jeu, sizeof(jeu)) && *jeu)
                {
                    STARTUPINFOA si = { sizeof(si) };
                    PROCESS_INFORMATION pi = { 0 };
                    char cmd[MAX_PATH + 2], dossier[MAX_PATH], *barre;

                    deja = 1;
                    snprintf(cmd, sizeof(cmd), "\"%s\"", jeu);
                    /* Le jeu cherche ses donnees a cote de lui : il lui faut
                     * son propre dossier comme repertoire courant. */
                    lstrcpynA(dossier, jeu, sizeof(dossier));
                    if ((barre = strrchr(dossier, '\\'))) *barre = 0; else *dossier = 0;
                    fprintf(stderr, "faux steam : jeu [%s] dossier [%s]\n", jeu, dossier);
                    if (CreateProcessA(jeu, cmd, NULL, NULL, FALSE, 0, NULL,
                                       *dossier ? dossier : NULL, &si, &pi))
                    {
                        fprintf(stderr, "faux steam : relance %s -> pid %lu\n", jeu, pi.dwProcessId);
                        CloseHandle(pi.hThread);
                        CloseHandle(pi.hProcess);
                    }
                    else
                        fprintf(stderr, "faux steam : relance impossible (%lu)\n", GetLastError());
                }
            }
            fflush(stderr);
            req[0] = 0;
        }
        Sleep(10);
    }
    return 0;
}
