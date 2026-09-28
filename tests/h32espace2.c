/*
 * Invite i386 : ce que coute un fil dans la fenetre de l'invite.
 *
 * DREDGE tourne avec une soixantaine de fils et meurt a court d'espace sur des
 * demandes de 576 Kio. Un programme nu, lui, reserve 4032 Mio sans peine. La
 * difference tient peut-etre aux fils : chacun apporte sa pile, son bloc
 * d'environnement, et tout ce que FEX place pour lui. On mesure avant, apres
 * soixante fils, et apres les avoir tous rendus.
 */
#include <windows.h>
#include <stdio.h>

static volatile LONG fini;

static DWORD WINAPI dormir( void *p )
{
    while (!fini) Sleep( 50 );
    return 0;
}

static ULONG64 reservable( void )
{
    static void *blocs[4096];
    int i = 0;
    ULONG64 pris = 0;

    while (i < 4096)
    {
        void *v = VirtualAlloc( NULL, 16 * 1024 * 1024, MEM_RESERVE, PAGE_NOACCESS );
        if (!v) break;
        blocs[i++] = v;
        pris += 16 * 1024 * 1024;
    }
    while (i > 0) VirtualFree( blocs[--i], 0, MEM_RELEASE );
    return pris >> 20;
}

int main(void)
{
    HANDLE h[60];
    int i, n = 0;

    printf( "avant           : %llu Mio reservables\n", reservable() ); fflush( stdout );

    for (i = 0; i < 60; i++)
        if ((h[n] = CreateThread( NULL, 0, dormir, NULL, 0, NULL ))) n++;
    Sleep( 500 );
    printf( "avec %2d fils    : %llu Mio reservables\n", n, reservable() ); fflush( stdout );

    fini = 1;
    for (i = 0; i < n; i++) { WaitForSingleObject( h[i], 3000 ); CloseHandle( h[i] ); }
    Sleep( 500 );
    printf( "fils rendus     : %llu Mio reservables\n", reservable() );
    return 0;
}
