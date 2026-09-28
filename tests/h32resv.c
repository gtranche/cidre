/* Reserver sans acces, puis engager morceau par morceau : c'est ce que font
 * les ramasse-miettes et les gestionnaires de code engendre. */
#include <windows.h>
#include <stdio.h>

static void essai( const char *quoi, SIZE_T taille, DWORD type, DWORD prot )
{
    void *p;
    SetLastError( 0 );
    p = VirtualAlloc( NULL, taille, type, prot );
    printf( "%-34s -> %p err=%lu\n", quoi, p, GetLastError() );
    if (p) VirtualFree( p, 0, MEM_RELEASE );
}

int main(void)
{
    char *p;
    MEMORY_BASIC_INFORMATION mbi;
    int i, mauvais = 0;

    essai( "64K RESERVE NOACCESS", 0x10000, MEM_RESERVE, PAGE_NOACCESS );
    essai( "64K RESERVE READWRITE", 0x10000, MEM_RESERVE, PAGE_READWRITE );
    essai( "64K RESERVE EXECUTE_READWRITE", 0x10000, MEM_RESERVE, PAGE_EXECUTE_READWRITE );
    essai( "1M  RESERVE NOACCESS", 0x100000, MEM_RESERVE, PAGE_NOACCESS );
    essai( "16M RESERVE NOACCESS", 0x1000000, MEM_RESERVE, PAGE_NOACCESS );
    essai( "64K COMMIT NOACCESS", 0x10000, MEM_RESERVE|MEM_COMMIT, PAGE_NOACCESS );

    /* Le motif exact des adresses fautives : un granule de 64 Kio, engage par
     * tranches de 16 Kio. */
    p = VirtualAlloc( NULL, 0x100000, MEM_RESERVE, PAGE_READWRITE );
    printf( "reserve 1 Mio = %p\n", p );
    if (!p) return 1;
    for (i = 0; i < 0x100000 / 0x4000; i++)
    {
        char *q = VirtualAlloc( p + i * 0x4000, 0x4000, MEM_COMMIT, PAGE_READWRITE );
        if (q != p + i * 0x4000) { printf( "engagement %d -> %p\n", i, q ); mauvais++; continue; }
        q[0] = 1; q[0x3fff] = 2;
        VirtualQuery( q, &mbi, sizeof(mbi) );
        if (mbi.State != MEM_COMMIT) { printf( "tranche %d : etat=%lx\n", i, mbi.State ); mauvais++; }
    }
    printf( "i386 reservation : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
