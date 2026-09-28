/*
 * Invite i386 : le chemin GDI.
 *
 * « get_full_gdi_handle » du gdi32 de l'invite lit la table partagee des
 * poignees GDI dans le PEB 64 bits, qu'il atteint par GdiBatchCount --
 * l'emplacement ou Wine range l'adresse du TEB 64 bits pour un processus
 * wow64. Trois lectures, trois occasions de se tromper de monde d'adresses ;
 * ce programme les affiche avant de s'en servir.
 */
#include <windows.h>
#include <stdio.h>

static DWORD lire( const void *p, unsigned decalage )
{
    const void *a = (const char *)p + decalage;

    if (!p || IsBadReadPtr( a, 4 )) return 0xDEADBEEF;
    return *(const DWORD *)a;
}

int main(void)
{
    const void *teb32 = (const void *)(ULONG_PTR)__readfsdword( 0x18 );
    DWORD batch = lire( teb32, 0xf70 );
    DWORD peb32 = lire( teb32, 0x30 );
    HGDIOBJ pinceau;
    LOGBRUSH lb = { 0 };
    HDC dc;
    int n;

    printf( "TEB32          = %p\n", teb32 );
    printf( "GdiBatchCount  = %08x  (adresse du TEB 64 bits)\n", (unsigned)batch );
    printf( "  TEB64->Peb   = %08x\n", (unsigned)lire( (const void *)(ULONG_PTR)batch, 0x60 ) );
    printf( "  PEB64->Gdi   = %08x\n",
            (unsigned)lire( (const void *)(ULONG_PTR)lire( (const void *)(ULONG_PTR)batch, 0x60 ), 0xf8 ) );
    printf( "PEB32          = %08x\n", (unsigned)peb32 );
    printf( "  PEB32->Gdi   = %08x\n", (unsigned)lire( (const void *)(ULONG_PTR)peb32, 0x94 ) );
    fflush( stdout );

    {
        /* La table partagee : 32 poignees reservees, puis les objets de
         * reserve. Type non nul = l'emplacement est pris. */
        const unsigned char *h = (const unsigned char *)(ULONG_PTR)
            lire( (const void *)(ULONG_PTR)lire( (const void *)(ULONG_PTR)batch, 0x60 ), 0xf8 );
        unsigned k;

        printf( "table des poignees a %p :", h );
        for (k = 32; k < 44 && h; k++)
            printf( " %u", IsBadReadPtr( h + k * 24 + 0xe, 1 ) ? 255 : h[k * 24 + 0xe] );
        printf( "\n" );
        fflush( stdout );
    }

    pinceau = GetStockObject( BLACK_BRUSH );
    printf( "pinceau de reserve = %p\n", pinceau );
    fflush( stdout );

    n = GetObjectW( pinceau, sizeof(lb), &lb );
    printf( "GetObject = %d, style %u, couleur %06x\n", n, (unsigned)lb.lbStyle, (unsigned)lb.lbColor );
    fflush( stdout );

    dc = GetDC( NULL );
    printf( "GetDC(NULL) = %p, largeur %d\n", dc, dc ? GetDeviceCaps( dc, HORZRES ) : -1 );
    if (dc) ReleaseDC( NULL, dc );

    printf( "i386 GDI : ok\n" );
    return 0;
}
