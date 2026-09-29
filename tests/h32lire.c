/*
 * Invite i386 : lire la memoire d'un autre processus du prefixe.
 *
 * L'enveloppe SteamStub de deadcells.exe se dechiffre en memoire, puis compare
 * quelque chose dans un segment partage et refuse. Elle ne passe aucune valeur
 * a une API, donc la trace ne dit rien de plus : il faut son code. Et comme
 * elle attend un clic sur sa boite d'erreur, sa memoire est stable le temps
 * qu'on la lise.
 *
 *   h32lire.exe <nom.exe> <adresse hexa> <taille hexa> <fichier de sortie>
 */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>

static DWORD trouver( const char *nom )
{
    PROCESSENTRY32 e = { sizeof(e) };
    HANDLE instantane = CreateToolhelp32Snapshot( TH32CS_SNAPPROCESS, 0 );
    DWORD pid = 0;

    if (instantane == INVALID_HANDLE_VALUE) return 0;
    if (Process32First( instantane, &e ))
        do {
            if (!lstrcmpiA( e.szExeFile, nom )) { pid = e.th32ProcessID; break; }
        } while (Process32Next( instantane, &e ));
    CloseHandle( instantane );
    return pid;
}

int main( int argc, char **argv )
{
    DWORD pid;
    HANDLE proc;
    ULONG_PTR debut;
    SIZE_T taille, lus = 0;
    void *tampon;
    FILE *f;

    if (argc < 5) { printf( "usage: h32lire <nom.exe> <adresse> <taille> <sortie>\n" ); return 2; }
    debut  = (ULONG_PTR)strtoul( argv[2], NULL, 16 );
    taille = (SIZE_T)strtoul( argv[3], NULL, 16 );

    if (!(pid = trouver( argv[1] ))) { printf( "%s : introuvable\n", argv[1] ); return 1; }
    printf( "%s : pid %lu\n", argv[1], pid );

    if (!(proc = OpenProcess( PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid )))
    { printf( "OpenProcess : %lu\n", GetLastError() ); return 1; }

    /* Dire ce qu'est la zone avant de la lire : une region non engagee
     * expliquerait une lecture vide sans qu'on s'en apercoive. */
    {
        MEMORY_BASIC_INFORMATION mbi;

        if (VirtualQueryEx( proc, (void *)debut, &mbi, sizeof(mbi) ))
            printf( "zone %p : base %p taille %llx etat %lx prot %lx\n", (void *)debut,
                    mbi.BaseAddress, (unsigned long long)mbi.RegionSize, mbi.State, mbi.Protect );
    }

    if (!(tampon = malloc( taille ))) { printf( "malloc\n" ); return 1; }
    if (!ReadProcessMemory( proc, (void *)debut, tampon, taille, &lus ))
        printf( "ReadProcessMemory : %lu (lus %llu)\n", GetLastError(), (unsigned long long)lus );

    if (!(f = fopen( argv[4], "wb" ))) { printf( "fopen %s\n", argv[4] ); return 1; }
    fwrite( tampon, 1, lus, f );
    fclose( f );
    printf( "%llu octets ecrits dans %s\n", (unsigned long long)lus, argv[4] );
    CloseHandle( proc );
    return lus ? 0 : 1;
}
