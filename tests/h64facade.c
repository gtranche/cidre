/*
 * Invite x86-64 : la facade du client Steam repond-elle ?
 *
 * Un jeu protege par le DRM de Steam (enveloppe SteamStub) lit au registre le
 * chemin du steamclient64.dll du client, verifie dans ce fichier la signature
 * de Valve, le charge et lui demande CreateInterface. Cidre fait comme Proton :
 * la DLL authentique de Valve est chargee telle quelle, et ses exports sont
 * detournes en memoire vers lsteamclient, qui relaie au client Steam de macOS.
 *
 * Il faut donc que cette DLL soit dans le prefixe et que le registre la
 * designe. Sur une installation neuve elle manquait, et tout jeu protege
 * affichait « Application load error 3:0000065432 ».
 *
 *   x86_64-w64-mingw32-clang -O1 -o h64facade.exe h64facade.c
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)( const char *version, int *err );

int main( void )
{
    static const char *versions[] = { "SteamClient021", "SteamClient020", "SteamClient017", NULL };
    char chemin[MAX_PATH] = "";
    DWORD taille = sizeof(chemin), attributs;
    HMODULE module;
    fn_create creer;
    int i, trouvees = 0;

    setvbuf( stdout, NULL, _IONBF, 0 );
    RegGetValueA( HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess", "SteamClientDll64",
                  RRF_RT_REG_SZ, NULL, chemin, &taille );
    printf( "  registre SteamClientDll64 : %s\n", chemin[0] ? chemin : "(absent)" );
    attributs = GetFileAttributesA( chemin );
    printf( "  fichier                   : %s\n", attributs == INVALID_FILE_ATTRIBUTES ? "ABSENT" : "present" );
    if (!(module = LoadLibraryA( chemin )))
    {
        printf( "  chargement                : ECHEC %lu\nx86-64 facade Steam : ECHEC\n", GetLastError() );
        return 1;
    }
    if (!(creer = (fn_create)GetProcAddress( module, "CreateInterface" )))
    {
        printf( "  CreateInterface           : ABSENT\nx86-64 facade Steam : ECHEC\n" );
        return 1;
    }
    for (i = 0; versions[i]; i++)
    {
        int err = 0;
        void *iface = creer( versions[i], &err );
        printf( "  %s            : %s\n", versions[i], iface ? "interface rendue" : "rien" );
        if (iface) trouvees++;
    }
    printf( "x86-64 facade Steam : %s\n", trouvees ? "ok" : "ECHEC (client Steam de macOS arrete ?)" );
    return !trouvees;
}
