/* Le pont 32 bits rend bien des objets ; mais un objet dont la table de
 * methodes ne s'appelle pas ne sert a rien. On appelle donc l'emplacement 0
 * d'ISteamClient -- CreateSteamPipe -- a la main, en __thiscall.
 *
 * MSVC passe « this » dans ECX et laisse l'appele depiler : « fastcall » a
 * deux parametres registre reproduit exactement cela, le second n'etant pas lu.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)( const char *version, int *err );
typedef int (__attribute__((fastcall)) *fn_slot0)( void *self, void *inutilise );
typedef int (__attribute__((fastcall)) *fn_slot1)( void *self, void *inutilise, int a );
typedef void *(__attribute__((fastcall)) *fn_slot3)( void *self, void *inutilise, int a, int b, const char *v );

int main(void)
{
    HMODULE m = LoadLibraryA( "lsteamclient.dll" );
    fn_create creer;
    void **objet, **table;
    int err = 0, pipe, user;
    void *iuser;

    if (!m) { printf( "lsteamclient absente : %lu\n", GetLastError() ); return 1; }
    creer = (fn_create)GetProcAddress( m, "CreateInterface" );
    if (!creer) { printf( "CreateInterface absente\n" ); return 1; }

    objet = creer( "SteamClient017", &err );
    printf( "objet = %p err = %d\n", (void *)objet, err ); fflush( stdout );
    if (!objet) return 1;

    table = (void **)objet[0];
    printf( "table = %p, emplacement 0 = %p\n", (void *)table, table ? table[0] : NULL );
    fflush( stdout );
    if (!table || !table[0]) return 1;

    pipe = ((fn_slot0)table[0])( objet, NULL );
    printf( "CreateSteamPipe = %d\n", pipe ); fflush( stdout );
    if (!pipe) return 1;

    /* ConnectToGlobalUser est l'emplacement 2 d'ISteamClient ; il rend le
     * HSteamUser de la session ouverte, ou zero si personne n'est connecte.
     * C'est la que SteamAPI_Init abandonne quand le client natif ne repond pas. */
    user = ((fn_slot1)table[2])( objet, NULL, pipe );
    printf( "ConnectToGlobalUser = %d\n", user ); fflush( stdout );
    if (!user) return 1;

    /* GetISteamUser : emplacement 5, (user, pipe, version). */
    iuser = ((fn_slot3)table[5])( objet, NULL, user, pipe, "SteamUser021" );
    printf( "GetISteamUser = %p\n", iuser );
    return 0;
}
