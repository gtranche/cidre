/*
 * Invite x86-64 : une grosse reservation passe-t-elle ?
 *
 * Vermintide 2 tombe dans son demarrage sur memset(0x10, 0, 960), avec 0xc800000
 * -- 200 Mio exactement -- dans deux registres. La lecture la plus simple est
 * qu'une reservation de 200 Mio a rendu zero et que le jeu a ecrit a « zero plus
 * seize ». Cette hypothese se mesure au lieu de se supposer.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static void essai( const char *quoi, void *p, SIZE_T taille )
{
    printf( "  %-46s %s", quoi, p ? "ok" : "ECHEC" );
    if (p) printf( " a %p", p );
    else printf( " (%lu)", GetLastError() );
    printf( "\n" );
    fflush( stdout );
    if (p) { *(volatile char *)p = 1; ((volatile char *)p)[taille - 1] = 1; }
}

int main(void)
{
    const SIZE_T M = 1024 * 1024;
    MEMORY_BASIC_INFORMATION mbi;
    char *p;
    ULONG64 libre = 0, total = 0;
    SYSTEM_INFO si;
    void *v;

    GetSystemInfo( &si );
    setvbuf( stdout, NULL, _IONBF, 0 );
    printf( "espace d'adressage : %p .. %p\n",
            si.lpMinimumApplicationAddress, si.lpMaximumApplicationAddress );

    /* Pas de parcours de l'espace d'adressage : sur un invite x86-64, chaque
     * VirtualQuery traverse la couche d'emulation, et balayer 128 Tio ne se
     * termine pas. Seules les reservations nous interessent. */
    printf( "\nreservations, celle du jeu en premier :\n" );
    essai( "VirtualAlloc 200 Mio RESERVE|COMMIT", VirtualAlloc( NULL, 200 * M, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE ), 200 * M );
    essai( "malloc 200 Mio",                      malloc( 200 * M ), 200 * M );
    essai( "HeapAlloc 200 Mio",                   HeapAlloc( GetProcessHeap(), 0, 200 * M ), 200 * M );
    essai( "VirtualAlloc 1 Gio RESERVE",          (v = VirtualAlloc( NULL, 1024 * M, MEM_RESERVE, PAGE_READWRITE )), 1 );
    if (v) VirtualFree( v, 0, MEM_RELEASE );
    essai( "VirtualAlloc 4 Gio RESERVE",          (v = VirtualAlloc( NULL, (SIZE_T)4096 * M, MEM_RESERVE, PAGE_READWRITE )), 1 );
    if (v) VirtualFree( v, 0, MEM_RELEASE );

    printf( "\nx86-64 grosse reservation : constat fait\n" );
    return 0;
}
