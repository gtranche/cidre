/* La pompe a rappels.
 *
 * Steamworks ne rappelle pas le jeu : le jeu vient chercher ses evenements.
 * SteamAPI_RunCallbacks, que le jeu appelle a chaque image, se resume a une
 * boucle sur Steam_BGetCallback suivie d'une repartition vers les objets de
 * rappel du jeu -- repartition qui reste entierement en code PE. La frontiere
 * d'ABI n'est donc franchie que dans le sens jeu -> client, comme le reste.
 *
 * Cette sonde fait ce que fait un jeu : elle ouvre un tuyau, se rattache a
 * l'utilisateur deja connecte du client natif, verifie qu'il est en ligne,
 * puis pompe.
 */
#include <windows.h>
#include <stdio.h>

typedef int  (__cdecl *fn_pipe)(void);
typedef int  (__cdecl *fn_connect)(int pipe);
typedef void (__cdecl *fn_release_user)(int pipe, int user);
typedef BOOL (__cdecl *fn_user_pipe)(int user, int pipe);
typedef void (__cdecl *fn_free_last)(int pipe);

typedef struct {
    int            m_hSteamUser;
    int            m_iCallback;
    unsigned char *m_pubParam;
    int            m_cubParam;
} CallbackMsg_t;

typedef BOOL (__cdecl *fn_get_callback)(int pipe, CallbackMsg_t *msg, int *call);

static const char *nom_rappel(int id)
{
    switch (id) {
    case 101: return "SteamServersConnected";
    case 102: return "SteamServerConnectFailure";
    case 103: return "SteamServersDisconnected";
    case 117: return "IPCFailure";
    case 125: return "LicensesUpdated";
    case 143: return "ValidateAuthTicketResponse";
    case 152: return "GetAuthSessionTicketResponse";
    case 304: return "PersonaStateChange";
    case 331: return "GameOverlayActivated";
    case 336: return "AvatarImageLoaded";
    case 703: return "SteamAPICallCompleted";
    case 704: return "SteamShutdown";
    case 714: return "GamepadTextInputDismissed";
    case 1005: return "SteamAppInstalled";
    case 1101: return "UserStatsReceived";
    case 1102: return "UserStatsStored";
    default:  return "inconnu";
    }
}

int main(void)
{
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_pipe         creer_tuyau;
    fn_connect      connecter;
    fn_user_pipe    connecte, en_ligne;
    fn_get_callback prendre;
    fn_free_last    liberer_dernier;
    fn_release_user liberer_utilisateur;
    int tuyau, utilisateur, tours = 0, recus = 0;
    DWORD debut;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }

#define SYM(v, t, n) v = (t)GetProcAddress(h, n); \
    if (!v) { printf("symbole absent : %s\n", n); return 1; }
    SYM(creer_tuyau,         fn_pipe,         "Steam_CreateSteamPipe")
    SYM(connecter,           fn_connect,      "Steam_ConnectToGlobalUser")
    SYM(connecte,            fn_user_pipe,    "Steam_BConnected")
    SYM(en_ligne,            fn_user_pipe,    "Steam_BLoggedOn")
    SYM(prendre,             fn_get_callback, "Steam_BGetCallback")
    SYM(liberer_dernier,     fn_free_last,    "Steam_FreeLastCallback")
    SYM(liberer_utilisateur, fn_release_user, "Steam_ReleaseUser")
#undef SYM

    tuyau = creer_tuyau();
    printf("Steam_CreateSteamPipe -> %d\n", tuyau);
    if (!tuyau) { printf("pas de tuyau, on s'arrete\n"); return 1; }

    utilisateur = connecter(tuyau);
    printf("Steam_ConnectToGlobalUser(%d) -> %d\n", tuyau, utilisateur);
    if (!utilisateur) { printf("pas d'utilisateur global\n"); return 1; }

    printf("Steam_BConnected -> %d\n", connecte(utilisateur, tuyau));
    printf("Steam_BLoggedOn  -> %d %s\n", en_ligne(utilisateur, tuyau),
           en_ligne(utilisateur, tuyau) ? "(session Steam reelle)" : "(hors ligne)");

    printf("--- pompe, 5 secondes ---\n");
    debut = GetTickCount();
    while (GetTickCount() - debut < 5000) {
        CallbackMsg_t msg = { 0 };
        int appel = 0;
        tours++;
        if (prendre(tuyau, &msg, &appel)) {
            recus++;
            printf("  rappel %-5d %-28s utilisateur %d, %3d octets a %p",
                   msg.m_iCallback, nom_rappel(msg.m_iCallback),
                   msg.m_hSteamUser, msg.m_cubParam, (void *)msg.m_pubParam);
            /* Le parametre vit dans la memoire du client natif ; unixlib
             * partageant l'espace d'adressage, le cote PE doit pouvoir le
             * lire sans recopie. On le prouve en lisant le premier octet. */
            if (msg.m_pubParam && msg.m_cubParam > 0)
                printf(", 1er octet 0x%02x", msg.m_pubParam[0]);
            printf("\n");
            liberer_dernier(tuyau);
        } else {
            Sleep(10);
        }
    }
    printf("--- %d tours, %d rappels ---\n", tours, recus);

    liberer_utilisateur(tuyau, utilisateur);
    printf("Steam_ReleaseUser : rendu\n");
    return 0;
}
