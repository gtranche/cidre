/* Piloter le vrai steam_api.dll i386 d'un jeu, comme le jeu le ferait.
 *
 * Fahrenheit (312840) s'arretait dans SteamAPI_Init : son steam_api de 2013
 * parle SteamClient012, dont l'emplacement 23 (GetISteamHTTP, trois mots) etait
 * pris pour celui de SteamClient019 (BShutdownIfAllPipesClosed, aucun) -- le
 * thunk ne depilait rien, et le ret sautait dans la .data du jeu. Ce temoin
 * refait la meme suite : SteamAPI_Init, puis les accesseurs que le jeu
 * importe (SteamUser, SteamFriends, SteamUserStats), et verifie que la pile
 * revient intacte de chaque appel.
 *
 * Usage : h32steamapi.exe <chemin\steam_api.dll>   (SteamAppId dans l'environnement)
 * Construit par i686-w64-mingw32-gcc -O1 -o h32steamapi.exe h32steamapi.c
 */
#include <windows.h>
#include <stdio.h>

typedef char (__cdecl *fn_bool)(void);
typedef void *(__cdecl *fn_iface)(void);
typedef const char *(__attribute__((thiscall)) *fn_chaine)( void *self );
typedef void *(__attribute__((thiscall)) *fn_steamid)( void *self, unsigned long long *ret );
typedef char (__attribute__((thiscall)) *fn_bool_this)( void *self );

static unsigned esp_avant, esp_apres;

/* Appelle f sans prototype et mesure ESP de part et d'autre : un thunk qui
 * depile de travers le laisse decale. */
static char init_mesure( fn_bool f )
{
    char r;
    __asm__ volatile ( "movl %%esp, %0" : "=m"(esp_avant) );
    r = f();
    __asm__ volatile ( "movl %%esp, %0" : "=m"(esp_apres) );
    return r;
}

int main( int argc, char **argv )
{
    HMODULE h;
    fn_bool init;
    fn_iface acc;
    void **user, **friends, **stats;
    unsigned long long id = 0;
    int echecs = 0;

    if (argc < 2) { fprintf( stderr, "usage : %s <steam_api.dll>\n", argv[0] ); return 2; }
    if (!(h = LoadLibraryA( argv[1] ))) { printf( "chargement impossible : %lu\n", GetLastError() ); return 1; }
    if (!(init = (fn_bool)GetProcAddress( h, "SteamAPI_Init" ))) { printf( "SteamAPI_Init absent\n" ); return 1; }

    printf( "SteamAPI_Init -> %d\n", init_mesure( init ) ? 1 : 0 ); fflush( stdout );
    printf( "pile : %s (esp %#x -> %#x)\n", esp_avant == esp_apres ? "intacte" : "DECALEE",
            esp_avant, esp_apres );
    if (esp_avant != esp_apres) echecs++;

    acc = (fn_iface)GetProcAddress( h, "SteamUser" );
    user = acc ? acc() : NULL;
    printf( "SteamUser() = %p\n", (void *)user );
    if (user)
    {
        /* SteamUser017 : 1 BLoggedOn, 2 GetSteamID (CSteamID par pointeur cache). */
        printf( "  BLoggedOn = %d\n", ((fn_bool_this)((void **)user[0])[1])( user ) );
        ((fn_steamid)((void **)user[0])[2])( user, &id );
        printf( "  GetSteamID = %#llx (univers %llu)\n", id, id >> 56 );
        if ((id >> 56) != 1) echecs++;
    }
    else echecs++;

    acc = (fn_iface)GetProcAddress( h, "SteamFriends" );
    friends = acc ? acc() : NULL;
    printf( "SteamFriends() = %p\n", (void *)friends );
    if (friends)
    {
        /* SteamFriends014 : 0 GetPersonaName (const char *). */
        const char *nom = ((fn_chaine)((void **)friends[0])[0])( friends );
        printf( "  GetPersonaName = %s\n", nom ? nom : "(nul)" );
        if (!nom || !nom[0]) echecs++;
    }
    else echecs++;

    acc = (fn_iface)GetProcAddress( h, "SteamUserStats" );
    stats = acc ? acc() : NULL;
    printf( "SteamUserStats() = %p\n", (void *)stats );
    if (stats)
    {
        /* STEAMUSERSTATS_INTERFACE_VERSION011 : 0 RequestCurrentStats. */
        printf( "  RequestCurrentStats = %d\n", ((fn_bool_this)((void **)stats[0])[0])( stats ) );
    }
    else echecs++;

    printf( "%s (%d echec%s)\n", echecs ? "ECHEC" : "ok", echecs, echecs > 1 ? "s" : "" );
    return echecs ? 1 : 0;
}
