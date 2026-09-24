/* Relever la table de methodes d'une sous-interface, sans en appeler aucune.
 *
 * Meme principe qu'au paragraphe 202 pour ISteamClient : l'unixlib partageant
 * l'espace d'adressage, la table native est simplement lisible. On la releve,
 * puis le decodage des octets se fait hors ligne, sur la tranche x86_64 du
 * dylib.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef int   (__cdecl *fn_pipe)(void);
typedef int   (__cdecl *fn_connect)(int pipe);
typedef void  (__cdecl *fn_release_user)(int pipe, int user);
typedef void *(__cdecl *fn_generique)(void *client, int user, int pipe, const char *version);
typedef void *(__cdecl *fn_natif)(void *enveloppe);

static const char *cibles[] = {
    "STEAMAPPS_INTERFACE_VERSION008",
    "SteamUser023",
    "SteamUtils011",
    "STEAMUSERSTATS_INTERFACE_VERSION013",
};

int main(void)
{
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer; fn_pipe creer_tuyau; fn_connect connecter;
    fn_release_user liberer; fn_generique generique; fn_natif natif;
    void *client; int err = 0, tuyau, utilisateur; unsigned i;

    if (!h) return 1;
#define SYM(v,t,n) v=(t)GetProcAddress(h,n); if(!v){printf("absent : %s\n",n);return 1;}
    SYM(creer,       fn_create,       "CreateInterface")
    SYM(creer_tuyau, fn_pipe,         "Steam_CreateSteamPipe")
    SYM(connecter,   fn_connect,      "Steam_ConnectToGlobalUser")
    SYM(liberer,     fn_release_user, "Steam_ReleaseUser")
    SYM(generique,   fn_generique,    "SondeInterfaceGenerique")
    SYM(natif,       fn_natif,        "SondeInterfaceNative")
#undef SYM

    if (!(client = creer("SteamClient021", &err))) return 1;
    tuyau = creer_tuyau();
    utilisateur = connecter(tuyau);
    if (!tuyau || !utilisateur) return 1;

    for (i = 0; i < sizeof(cibles)/sizeof(cibles[0]); i++) {
        void *iface = natif(generique(client, utilisateur, tuyau, cibles[i]));
        void **table; int j;
        if (!iface) { printf("%s : absente\n", cibles[i]); continue; }
        table = *(void ***)iface;
        printf("%s natif=%p table=%p\n", cibles[i], iface, (void *)table);
        for (j = 0; j < 120; j++) {
            if (IsBadReadPtr(&table[j], sizeof(void *))) break;
            printf("  %3d %p\n", j, table[j]);
        }
    }
    liberer(tuyau, utilisateur);
    return 0;
}
