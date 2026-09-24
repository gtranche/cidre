/* Atteindre les sous-interfaces par l'emplacement 12.
 *
 * GetISteamGenericInterface prend le nom que l'appelant fournit. Si
 * l'identification de l'emplacement est juste, les 204 chaines de version que
 * le dylib contient doivent devenir autant d'interfaces vivantes -- sans
 * qu'aucun autre emplacement de la table ait eu besoin d'etre connu.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef int   (__cdecl *fn_pipe)(void);
typedef int   (__cdecl *fn_connect)(int pipe);
typedef void  (__cdecl *fn_release_user)(int pipe, int user);
typedef void *(__cdecl *fn_generique)(void *client, int user, int pipe, const char *version);
typedef void *(__cdecl *fn_natif)(void *enveloppe);

static const char *versions[] = {
    "STEAMAPPLIST_INTERFACE_VERSION001",
    "STEAMAPPS_INTERFACE_VERSION001",
    "STEAMAPPS_INTERFACE_VERSION002",
    "STEAMAPPS_INTERFACE_VERSION003",
    "STEAMAPPS_INTERFACE_VERSION004",
    "STEAMAPPS_INTERFACE_VERSION005",
    "STEAMAPPS_INTERFACE_VERSION006",
    "STEAMAPPS_INTERFACE_VERSION007",
    "STEAMAPPS_INTERFACE_VERSION008",
    "STEAMAPPS_INTERFACE_VERSION009",
    "STEAMAPPTICKET_INTERFACE_VERSION001",
    "STEAMCHAT_INTERFACE_VERSION003",
    "STEAMHTTP_INTERFACE_VERSION001",
    "STEAMHTTP_INTERFACE_VERSION002",
    "STEAMHTTP_INTERFACE_VERSION003",
    "STEAMMUSICREMOTE_INTERFACE_VERSION001",
    "STEAMMUSIC_INTERFACE_VERSION001",
    "STEAMPARENTALSETTINGS_INTERFACE_VERSION001",
    "STEAMREMOTEPLAY_INTERFACE_VERSION001",
    "STEAMREMOTEPLAY_INTERFACE_VERSION002",
    "STEAMREMOTEPLAY_INTERFACE_VERSION003",
    "STEAMREMOTEPLAY_INTERFACE_VERSION004",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION001",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION002",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION003",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION004",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION005",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION006",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION007",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION008",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION009",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION010",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION011",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION012",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION013",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION014",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION015",
    "STEAMREMOTESTORAGE_INTERFACE_VERSION016",
    "STEAMSCREENSHOTS_INTERFACE_VERSION001",
    "STEAMSCREENSHOTS_INTERFACE_VERSION002",
    "STEAMSCREENSHOTS_INTERFACE_VERSION003",
    "STEAMUGC_INTERFACE_VERSION001",
    "STEAMUGC_INTERFACE_VERSION002",
    "STEAMUGC_INTERFACE_VERSION003",
    "STEAMUGC_INTERFACE_VERSION004",
    "STEAMUGC_INTERFACE_VERSION005",
    "STEAMUGC_INTERFACE_VERSION006",
    "STEAMUGC_INTERFACE_VERSION007",
    "STEAMUGC_INTERFACE_VERSION008",
    "STEAMUGC_INTERFACE_VERSION009",
    "STEAMUGC_INTERFACE_VERSION010",
    "STEAMUGC_INTERFACE_VERSION011",
    "STEAMUGC_INTERFACE_VERSION012",
    "STEAMUGC_INTERFACE_VERSION013",
    "STEAMUGC_INTERFACE_VERSION014",
    "STEAMUGC_INTERFACE_VERSION015",
    "STEAMUGC_INTERFACE_VERSION016",
    "STEAMUGC_INTERFACE_VERSION017",
    "STEAMUGC_INTERFACE_VERSION018",
    "STEAMUGC_INTERFACE_VERSION019",
    "STEAMUGC_INTERFACE_VERSION020",
    "STEAMUGC_INTERFACE_VERSION021",
    "STEAMUNIFIEDMESSAGES_INTERFACE_VERSION001",
    "STEAMUSERSTATS_INTERFACE_VERSION001",
    "STEAMUSERSTATS_INTERFACE_VERSION002",
    "STEAMUSERSTATS_INTERFACE_VERSION003",
    "STEAMUSERSTATS_INTERFACE_VERSION004",
    "STEAMUSERSTATS_INTERFACE_VERSION005",
    "STEAMUSERSTATS_INTERFACE_VERSION006",
    "STEAMUSERSTATS_INTERFACE_VERSION007",
    "STEAMUSERSTATS_INTERFACE_VERSION008",
    "STEAMUSERSTATS_INTERFACE_VERSION009",
    "STEAMUSERSTATS_INTERFACE_VERSION010",
    "STEAMUSERSTATS_INTERFACE_VERSION011",
    "STEAMUSERSTATS_INTERFACE_VERSION012",
    "STEAMUSERSTATS_INTERFACE_VERSION013",
    "SteamAppDisableUpdate001",
    "SteamApps001",
    "SteamBilling002",
    "SteamController003",
    "SteamController004",
    "SteamController005",
    "SteamController006",
    "SteamController007",
    "SteamController008",
    "SteamFriends001",
    "SteamFriends002",
    "SteamFriends003",
    "SteamFriends004",
    "SteamFriends005",
    "SteamFriends006",
    "SteamFriends007",
    "SteamFriends008",
    "SteamFriends009",
    "SteamFriends010",
    "SteamFriends011",
    "SteamFriends012",
    "SteamFriends013",
    "SteamFriends014",
    "SteamFriends015",
    "SteamFriends016",
    "SteamFriends017",
    "SteamFriends018",
    "SteamGameCoordinator001",
    "SteamGameServer002",
    "SteamGameServer003",
    "SteamGameServer004",
    "SteamGameServer005",
    "SteamGameServer006",
    "SteamGameServer007",
    "SteamGameServer008",
    "SteamGameServer009",
    "SteamGameServer010",
    "SteamGameServer011",
    "SteamGameServer012",
    "SteamGameServer013",
    "SteamGameServer014",
    "SteamGameServer015",
    "SteamGameServerStats001",
    "SteamGameStats001",
    "SteamInput001",
    "SteamInput002",
    "SteamInput003",
    "SteamInput004",
    "SteamInput005",
    "SteamInput006",
    "SteamInput007",
    "SteamMasterServerUpdater001",
    "SteamMatchGameSearch001",
    "SteamMatchMaking001",
    "SteamMatchMaking002",
    "SteamMatchMaking003",
    "SteamMatchMaking004",
    "SteamMatchMaking005",
    "SteamMatchMaking006",
    "SteamMatchMaking007",
    "SteamMatchMaking008",
    "SteamMatchMaking009",
    "SteamMatchMakingServers001",
    "SteamMatchMakingServers002",
    "SteamMatchMakingServers003",
    "SteamNetworking001",
    "SteamNetworking002",
    "SteamNetworking003",
    "SteamNetworking004",
    "SteamNetworking005",
    "SteamNetworking006",
    "SteamNetworkingMessages002",
    "SteamNetworkingSockets002",
    "SteamNetworkingSockets003",
    "SteamNetworkingSockets004",
    "SteamNetworkingSockets005",
    "SteamNetworkingSockets006",
    "SteamNetworkingSockets008",
    "SteamNetworkingSockets009",
    "SteamNetworkingSockets010",
    "SteamNetworkingSockets011",
    "SteamNetworkingSockets012",
    "SteamNetworkingSockets013",
    "SteamNetworkingSocketsSerialized001",
    "SteamNetworkingSocketsSerialized002",
    "SteamNetworkingSocketsSerialized003",
    "SteamNetworkingSocketsSerialized004",
    "SteamNetworkingSocketsSerialized005",
    "SteamNetworkingUtils001",
    "SteamNetworkingUtils002",
    "SteamNetworkingUtils003",
    "SteamNetworkingUtils004",
    "SteamParties001",
    "SteamParties002",
    "SteamSteamVRPrivate001",
    "SteamSteamVRPrivate002",
    "SteamStreamLauncher001",
    "SteamUser004",
    "SteamUser005",
    "SteamUser006",
    "SteamUser007",
    "SteamUser008",
    "SteamUser009",
    "SteamUser010",
    "SteamUser011",
    "SteamUser012",
    "SteamUser013",
    "SteamUser014",
    "SteamUser015",
    "SteamUser016",
    "SteamUser017",
    "SteamUser018",
    "SteamUser019",
    "SteamUser020",
    "SteamUser021",
    "SteamUser022",
    "SteamUser023",
    "SteamUtils001",
    "SteamUtils002",
    "SteamUtils003",
    "SteamUtils004",
    "SteamUtils005",
    "SteamUtils006",
    "SteamUtils007",
    "SteamUtils008",
    "SteamUtils009",
    "SteamUtils010",
    "SteamUtils011",
};

int main(void)
{
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer; fn_pipe creer_tuyau; fn_connect connecter;
    fn_release_user liberer; fn_generique generique; fn_natif natif;
    void *client; int err = 0, tuyau, utilisateur; unsigned i, ok = 0;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
#define SYM(v,t,n) v=(t)GetProcAddress(h,n); if(!v){printf("absent : %s\n",n);return 1;}
    SYM(creer,       fn_create,       "CreateInterface")
    SYM(creer_tuyau, fn_pipe,         "Steam_CreateSteamPipe")
    SYM(connecter,   fn_connect,      "Steam_ConnectToGlobalUser")
    SYM(liberer,     fn_release_user, "Steam_ReleaseUser")
    SYM(generique,   fn_generique,    "SondeInterfaceGenerique")
    SYM(natif,       fn_natif,        "SondeInterfaceNative")
#undef SYM

    if (!(client = creer("SteamClient021", &err))) { printf("pas de SteamClient021\n"); return 1; }
    tuyau = creer_tuyau();
    utilisateur = connecter(tuyau);
    printf("tuyau %d, utilisateur %d\n\n", tuyau, utilisateur);
    if (!tuyau || !utilisateur) return 1;

    for (i = 0; i < sizeof(versions)/sizeof(versions[0]); i++) {
        void *iface = generique(client, utilisateur, tuyau, versions[i]);
        if (iface) { printf("  %-45s -> %p\n", versions[i], natif(iface)); ok++; }
    }
    printf("\n--- %u interfaces sur %u ---\n", ok, (unsigned)(sizeof(versions)/sizeof(versions[0])));
    liberer(tuyau, utilisateur);
    return 0;
}
