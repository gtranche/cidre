/*
 * Invite x86-64 : jusqu'ou peut-on reserver bas ?
 *
 * Vermintide 2 demande son arene par
 *   VirtualAlloc(0x10000, 0x40000000, MEM_RESERVE, PAGE_READWRITE)
 * -- un gigaoctet a une adresse imposee tres basse. Sous Linux c'est
 * exactement mmap_min_addr et la demande passe. Ici elle rend NULL, et le jeu
 * ne teste que « != -1 », donc zero remonte jusqu'a un memset.
 *
 * Ce test ne suppose rien : il demande, et il note ce qui est rendu.
 */
#include <windows.h>
#include <stdio.h>

static void essai( const char *quoi, void *ou, SIZE_T taille )
{
    void *p = VirtualAlloc( ou, taille, MEM_RESERVE, PAGE_READWRITE );
    printf( "  %-46s -> ", quoi );
    if (p) { printf( "%p\n", p ); VirtualFree( p, 0, MEM_RELEASE ); }
    else   printf( "NULL (%lu)\n", GetLastError() );
    fflush( stdout );
}

int main(void)
{
    SYSTEM_INFO si;

    setvbuf( stdout, NULL, _IONBF, 0 );
    GetSystemInfo( &si );
    printf( "l'invite croit pouvoir aller de %p a %p\n",
            si.lpMinimumApplicationAddress, si.lpMaximumApplicationAddress );

    printf( "\nreserve d'un gigaoctet, a l'adresse demandee :\n" );
    essai( "0x10000   (ce que demande Vermintide 2)", (void *)(ULONG_PTR)0x10000, 0x40000000 );
    essai( "0x1000000  (16 Mio)",                     (void *)(ULONG_PTR)0x1000000, 0x40000000 );
    essai( "0x80000000 (2 Gio)",                      (void *)(ULONG_PTR)0x80000000, 0x40000000 );
    essai( "0x100000000 (4 Gio)",                     (void *)(ULONG_PTR)0x100000000, 0x40000000 );
    essai( "0x200000000 (8 Gio)",                     (void *)(ULONG_PTR)0x200000000, 0x40000000 );
    essai( "laissee au systeme",                      NULL, 0x40000000 );

    printf( "\npetite reserve, pour situer le plancher :\n" );
    {
        ULONG_PTR a;
        for (a = 0x10000; a <= 0x100000000ull; a <<= 1)
        {
            char t[32];
            sprintf( t, "%#llx", (unsigned long long)a );
            essai( t, (void *)a, 0x10000 );
        }
    }

    printf( "\nx86-64 plancher d'adressage : constat fait\n" );
    return 0;
}
