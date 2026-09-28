/* Une reservation PAGE_NOACCESS demande une projection unix a protection nulle.
 * La premiere echoue ; les suivantes passent. Les ramasse-miettes et les
 * gestionnaires de code engendre reservent ainsi, et ne verifient pas toujours. */
#include <windows.h>
#include <stdio.h>
int main(void)
{
    int i, echecs = 0;
    void *p[8];
    for (i = 0; i < 8; i++)
    {
        SetLastError( 0 );
        p[i] = VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS );
        printf( "essai %d : %p err=%lu\n", i, p[i], GetLastError() );
        if (!p[i]) echecs++;
    }
    for (i = 0; i < 8; i++) if (p[i]) VirtualFree( p[i], 0, MEM_RELEASE );
    printf( "i386 reserve NOACCESS : %s (%d echecs)\n", echecs ? "ECHEC" : "ok", echecs );
    return 0;
}
