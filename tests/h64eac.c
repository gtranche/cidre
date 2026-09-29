/*
 * Invite x86-64 : ce qu'un anti-triche voit de notre pile.
 *
 * Easy Anti-Cheat ne se devine pas, il se documente. Trois affirmations d'Epic
 * decident du sort d'un jeu protege, et chacune se verifie ici plutot que de se
 * supposer :
 *
 *  1. « The player is launching the game on a platform where no client module
 *     has been activated, for example using Wine/Proton when no Linux module
 *     has been activated. »  -- l'amorceur reconnait Wine, et demande alors le
 *     module *Linux*. On mesure donc ce que notre pile annonce : est-elle
 *     reconnaissable comme Wine, et quel systeme hote declare-t-elle ?
 *
 *  2. « Anti-Cheat Client does not support ... virtual machines (VM). »
 *
 *  3. Sur Windows, l'integration passe par un « Windows Service Installer ».
 *     On demande donc au gestionnaire de services d'installer et de demarrer un
 *     service de type SERVICE_KERNEL_DRIVER, en designant un pilote qui existe
 *     reellement -- viser un fichier absent ne mesurerait que son absence.
 *
 * Ce programme n'essaie rien de dissimuler : il constate. Faire mentir la pile
 * a un anti-triche serait de l'evasion de detection, pas de la compatibilite.
 */
#include <windows.h>
#include <winsvc.h>
#include <stdio.h>

int main(void)
{
    HMODULE ntdll = GetModuleHandleA( "ntdll.dll" );
    const char *(CDECL *version)(void);
    void (CDECL *hote)( const char **sysname, const char **release );
    SC_HANDLE scm;

    printf( "--- 1. la pile est-elle reconnaissable comme Wine ?\n" );
    version = (void *)GetProcAddress( ntdll, "wine_get_version" );
    printf( "  ntdll!wine_get_version   : %s", version ? "present" : "absent" );
    if (version) printf( " -> \"%s\"", version() );
    printf( "\n" );

    hote = (void *)GetProcAddress( ntdll, "wine_get_host_version" );
    if (hote)
    {
        const char *sys = NULL, *rel = NULL;
        hote( &sys, &rel );
        printf( "  ntdll!wine_get_host_version : \"%s\" \"%s\"\n",
                sys ? sys : "(rien)", rel ? rel : "(rien)" );
    }
    else printf( "  ntdll!wine_get_host_version : absent\n" );

    printf( "  ntdll!wine_server_call   : %s\n",
            GetProcAddress( ntdll, "wine_server_call" ) ? "present" : "absent" );

    printf( "\n--- 2. sous quel emulateur tourne l'invite ?\n" );
    {
        USHORT procede = 0, machine = 0;
        BOOL (WINAPI *iswow64_2)( HANDLE, USHORT *, USHORT * ) =
            (void *)GetProcAddress( GetModuleHandleA("kernel32.dll"), "IsWow64Process2" );

        if (iswow64_2 && iswow64_2( GetCurrentProcess(), &procede, &machine ))
            printf( "  IsWow64Process2 : processus %#x, machine native %#x\n", procede, machine );
        else printf( "  IsWow64Process2 : indisponible\n" );

        /* Le nom du module d'emulation : sur Windows sur ARM c'est xtajit64se.dll,
         * et les modules d'EAC 2508.3+ ont un chemin de compatibilite pour lui.
         * Chez nous, c'est FEX installe sous le nom xtajit. */
        printf( "  xtajit.dll charge      : %p\n", (void *)GetModuleHandleA( "xtajit.dll" ) );
        printf( "  xtajit64.dll charge    : %p\n", (void *)GetModuleHandleA( "xtajit64.dll" ) );
        printf( "  xtajit64se.dll charge  : %p\n", (void *)GetModuleHandleA( "xtajit64se.dll" ) );
    }

    printf( "\n--- 3. un service en mode noyau est-il installable ?\n" );
    if (!(scm = OpenSCManagerA( NULL, NULL, SC_MANAGER_ALL_ACCESS )))
        printf( "  OpenSCManager : echec %lu\n", GetLastError() );
    else
    {
        SC_HANDLE svc = CreateServiceA( scm, "essai_pilote_noyau", "essai pilote noyau",
                                        SERVICE_ALL_ACCESS, SERVICE_KERNEL_DRIVER,
                                        SERVICE_DEMAND_START, SERVICE_ERROR_NORMAL,
                                        "C:\\windows\\system32\\drivers\\http.sys",
                                        NULL, NULL, NULL, NULL, NULL );
        if (!svc && GetLastError() == ERROR_SERVICE_EXISTS)
            svc = OpenServiceA( scm, "essai_pilote_noyau", SERVICE_ALL_ACCESS );

        if (!svc) printf( "  CreateService(SERVICE_KERNEL_DRIVER) : echec %lu\n", GetLastError() );
        else
        {
            printf( "  CreateService(SERVICE_KERNEL_DRIVER) : accepte\n" );
            printf( "  StartService : %s (%lu)\n",
                    StartServiceA( svc, 0, NULL ) ? "demarre" : "echec", GetLastError() );
            DeleteService( svc );
            CloseServiceHandle( svc );
        }
        CloseServiceHandle( scm );
    }

    printf( "\nx86-64 anti-triche : constat fait\n" );
    return 0;
}
