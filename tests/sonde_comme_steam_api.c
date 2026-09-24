/* Refaire, pas a pas, ce que fait steam_api64.dll.
 *
 * Un jeu ne connait pas « lsteamclient » : son steam_api64.dll lit le registre
 * pour trouver steamclient64.dll, le charge, prend CreateInterface, puis
 * demande SteamClient0NN et remonte les interfaces. On rejoue cette chaine
 * exacte pour eprouver la plomberie avant qu'un vrai jeu n'arrive.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef int   (__cdecl *fn_pipe)(void);
typedef int   (__cdecl *fn_connect)(int pipe);
typedef void  (__cdecl *fn_release_user)(int pipe, int user);

struct ISteamClient { void **table; };
typedef void *(*m_generique)(struct ISteamClient *, int user, int pipe, const char *version);

int main(void)
{
    HKEY cle;
    char chemin[MAX_PATH]; DWORD taille = sizeof(chemin), type = 0;
    HMODULE h; fn_create creer; fn_pipe creer_tuyau; fn_connect connecter; fn_release_user liberer;
    struct ISteamClient *client; int err = 0, tuyau, utilisateur;
    m_generique generique; void *apps, *utils, *user;

    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess", 0, KEY_READ, &cle))
    { printf("cle ActiveProcess introuvable\n"); return 1; }
    if (RegQueryValueExA(cle, "SteamClientDll64", NULL, &type, (BYTE *)chemin, &taille))
    { printf("SteamClientDll64 absent\n"); return 1; }
    RegCloseKey(cle);
    printf("registre  : %s\n", chemin);

    if (!(h = LoadLibraryA(chemin))) { printf("chargement impossible : %lu\n", GetLastError()); return 1; }
    printf("charge    : %p\n", (void *)h);

#define SYM(v,t,n) v=(t)GetProcAddress(h,n); if(!v){printf("absent : %s\n",n);return 1;}
    SYM(creer,       fn_create,       "CreateInterface")
    SYM(creer_tuyau, fn_pipe,         "Steam_CreateSteamPipe")
    SYM(connecter,   fn_connect,      "Steam_ConnectToGlobalUser")
    SYM(liberer,     fn_release_user, "Steam_ReleaseUser")
#undef SYM

    if (!(client = creer("SteamClient021", &err))) { printf("SteamClient021 refuse\n"); return 1; }
    tuyau = creer_tuyau();
    utilisateur = connecter(tuyau);
    printf("tuyau %d, utilisateur %d\n", tuyau, utilisateur);
    if (!tuyau || !utilisateur) return 1;

    /* L'appel virtuel, emplacement 12, exactement comme un jeu l'ecrit. */
    generique = (m_generique)client->table[12];
    apps  = generique(client, utilisateur, tuyau, "STEAMAPPS_INTERFACE_VERSION008");
    utils = generique(client, utilisateur, tuyau, "SteamUtils011");
    user  = generique(client, utilisateur, tuyau, "SteamUser023");
    printf("ISteamApps  -> %p\n", apps);
    printf("ISteamUtils -> %p\n", utils);
    printf("ISteamUser  -> %p\n", user);

    liberer(tuyau, utilisateur);
    printf("%s\n", (apps && utils && user) ? "chaine complete" : "chaine incomplete");
    return 0;
}
