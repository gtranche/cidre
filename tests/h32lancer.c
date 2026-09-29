/*
 * Invite i386 : un processus 32 bits peut-il en lancer un autre ?
 *
 * Le faux client Steam echoue en 998 (ERROR_NOACCESS) quand il tente de
 * relancer le jeu. Avant d'accuser le chemin ou le jeu, on demande si
 * CreateProcess fonctionne du tout depuis l'invite 32 bits.
 */
#include <windows.h>
#include <stdio.h>

static void essai( const char *quoi, const char *appli, char *ligne, const char *dossier )
{
    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };

    if (CreateProcessA( appli, ligne, NULL, NULL, FALSE, 0, NULL, dossier, &si, &pi ))
    {
        printf( "%-28s -> pid %lu\n", quoi, pi.dwProcessId );
        WaitForSingleObject( pi.hProcess, 20000 );
        CloseHandle( pi.hThread ); CloseHandle( pi.hProcess );
    }
    else printf( "%-28s -> ECHEC %lu\n", quoi, GetLastError() );
    fflush( stdout );
}

int main(void)
{
    static char l1[] = "cmd.exe /c exit 7";
    static char l2[] = "\"Z:\\Users\\gtranche\\Library\\Application Support\\Steam\\steamapps\\common\\Dead Cells\\deadcells.exe\"";
    static const char d2[] = "Z:\\Users\\gtranche\\Library\\Application Support\\Steam\\steamapps\\common\\Dead Cells";

    essai( "cmd.exe, ligne seule", NULL, l1, NULL );
    essai( "jeu, ligne seule", NULL, l2, NULL );
    essai( "jeu, ligne + dossier", NULL, l2, d2 );
    {
        static const char nu[] = "Z:\\Users\\gtranche\\Library\\Application Support\\Steam\\steamapps\\common\\Dead Cells\\deadcells.exe";
        essai( "jeu, nomme + dossier", nu, l2, d2 );
    }
    return 0;
}
