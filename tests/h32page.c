/* Les adresses fautives de DREDGE sont toutes alignees sur 0x4000 et le code
 * en cause est celui que Mono engendre. 0x4000, c'est la page de macOS. Que
 * croit l'invite 32 bits ? Sur un vrai Windows, dwPageSize vaut toujours 4096
 * pour un processus 32 bits, et beaucoup de programmes en dependent. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    SYSTEM_INFO si;
    MEMORY_BASIC_INFORMATION mbi;
    char *p;

    GetSystemInfo( &si );
    printf( "dwPageSize = %lu\n", si.dwPageSize );
    printf( "dwAllocationGranularity = %lu\n", si.dwAllocationGranularity );
    printf( "lpMinimumApplicationAddress = %p\n", si.lpMinimumApplicationAddress );
    printf( "lpMaximumApplicationAddress = %p\n", si.lpMaximumApplicationAddress );

    /* Reserver 64 Kio, n'en engager que 4 Kio : la page suivante doit rester
     * reservee, et la lecture a +0x1000 doit fauter. C'est la granularite que
     * le programme attend. */
    SetLastError( 0 );
    p = VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS );
    printf( "reserve NOACCESS = %p err=%lu\n", p, GetLastError() );
    if (!p)
    {
        SetLastError( 0 );
        p = VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_READWRITE );
        printf( "reserve READWRITE = %p err=%lu\n", p, GetLastError() );
    }
    if (!p)
    {
        SetLastError( 0 );
        p = VirtualAlloc( NULL, 0x10000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
        printf( "reserve+engage = %p err=%lu\n", p, GetLastError() );
    }
    if (p)
    {
        char *q = VirtualAlloc( p, 0x1000, MEM_COMMIT, PAGE_READWRITE );
        printf( "engage 4 Kio = %p\n", q );
        VirtualQuery( p, &mbi, sizeof(mbi) );
        printf( "region a +0      : taille=%Ix etat=%lx prot=%lx\n", mbi.RegionSize, mbi.State, mbi.Protect );
        VirtualQuery( p + 0x1000, &mbi, sizeof(mbi) );
        printf( "region a +0x1000 : taille=%Ix etat=%lx prot=%lx\n", mbi.RegionSize, mbi.State, mbi.Protect );
        VirtualQuery( p + 0x4000, &mbi, sizeof(mbi) );
        printf( "region a +0x4000 : taille=%Ix etat=%lx prot=%lx\n", mbi.RegionSize, mbi.State, mbi.Protect );
    }
    return 0;
}
