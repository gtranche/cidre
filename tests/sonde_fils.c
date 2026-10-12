/* Combien coute la creation d'un fil ? Chaque fil recoit de ntdll une zone de
 * 1,1 Mo (pile de signal + pile noyau, virtual_alloc_thread_data) demandee
 * « au-dessus de 4 Gio ». Sur macOS arm64 tout l'hote vit la : quand la zone
 * est pleine, la recherche d'une adresse libre essayait chaque pas de 64 Kio
 * par un appel systeme, et un fil coutait des secondes (Expedition 33 sur un
 * Mac M4, GameThread fige dans NtCreateThreadEx).
 *
 *   sonde_fils.exe [fils] [tours]
 *
 * Phase 1 : `fils` fils crees et gardes en vie (un jeu en garde des dizaines).
 * Phase 2 : `tours` fils crees, attendus, fermes (les fils de courte duree).
 * Temoin : VirtualAlloc( NULL ) de 1 Mo, qui laisse le noyau choisir.
 * Phase 3 (64 bits) : des demandes vraiment bornees (VirtualAlloc2 et ses
 * MEM_ADDRESS_REQUIREMENTS), de bas en haut et de haut en bas. Elles passent
 * toutes par la recherche d'adresse libre : ce qui est rendu doit tenir dans
 * les bornes, etre aligne et s'ecrire ; et dans une zone saturee a dessein
 * (FRAGMENTER_HAUT) l'adresse rendue est connue d'avance, a l'octet.
 * S'emploie avec fragmenter_espace.dylib, voir sonde_fils.sh. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static HANDLE depart;
static LONG partis;

static DWORD WINAPI dormeur( void *p )
{
    InterlockedIncrement( &partis );
    WaitForSingleObject( depart, INFINITE );
    return 0;
}

static DWORD WINAPI passant( void *p )
{
    InterlockedIncrement( &partis );
    return 0;
}

static double micro( LARGE_INTEGER a, LARGE_INTEGER b, LARGE_INTEGER f )
{
    return (b.QuadPart - a.QuadPart) * 1e6 / f.QuadPart;
}

static int croissant( const void *a, const void *b )
{
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static void dire( const char *quoi, double *t, int n )
{
    double somme = 0;
    int i;

    for (i = 0; i < n; i++) somme += t[i];
    qsort( t, n, sizeof(*t), croissant );
    printf( "%-28s n=%-4d mediane %10.1f us   min %10.1f   max %10.1f   total %9.1f ms\n",
            quoi, n, t[n / 2], t[0], t[n - 1], somme / 1000 );
    fflush( stdout );
}

#ifdef _WIN64
typedef void * (WINAPI *alloc2_t)( HANDLE, void *, SIZE_T, ULONG, ULONG, MEM_EXTENDED_PARAMETER *, ULONG );
static alloc2_t alloc2;

#define ZONE 0x30000000000ull  /* 3 Tio : la zone que fragmenter_espace.dylib sature avec FRAGMENTER_HAUT */
#define GIO  0x40000000ull

static char *borne( ULONG_PTR bas, ULONG_PTR haut, SIZE_T taille, int vers_le_bas, double *duree, LARGE_INTEGER f )
{
    MEM_ADDRESS_REQUIREMENTS bornes = { (void *)bas, (void *)(haut - 1), 0 };
    MEM_EXTENDED_PARAMETER param = { 0 };
    LARGE_INTEGER a, b;
    char *p;

    param.Type = MemExtendedParameterAddressRequirements;
    param.Pointer = &bornes;
    QueryPerformanceCounter( &a );
    p = alloc2( GetCurrentProcess(), NULL, taille, MEM_RESERVE | MEM_COMMIT | (vers_le_bas ? MEM_TOP_DOWN : 0),
                PAGE_READWRITE, &param, 1 );
    QueryPerformanceCounter( &b );
    if (duree) *duree = micro( a, b, f );
    if (!p) return NULL;
    if ((ULONG_PTR)p < bas || (ULONG_PTR)p + taille > haut || ((ULONG_PTR)p & 0xffff))
    {
        printf( "HORS BORNES : %p taille %#lx pour [%#llx, %#llx)\n", p, (unsigned long)taille,
                (unsigned long long)bas, (unsigned long long)haut );
        return (char *)-1;
    }
    p[0] = 1; p[taille - 1] = 2;
    return p;
}

/* Rend le nombre d'ecarts (0 attendu). */
static int demandes_bornees( LARGE_INTEGER f )
{
    static const SIZE_T tailles[] = { 0x10000, 0x110000, 0x1000000 };
    char *blocs[64];
    double t[64];
    int n = 0, ecarts = 0, j, sens, k, i;

    alloc2 = (alloc2_t)(void *)GetProcAddress( GetModuleHandleA( "kernelbase.dll" ), "VirtualAlloc2" );
    if (!alloc2) { printf( "VirtualAlloc2 absent\n" ); return 1; }

    /* Dans le vide : tout doit etre servi, dans les bornes, dans les deux sens. */
    for (j = 0; j < 3; j++) for (sens = 0; sens < 2; sens++) for (k = 0; k < 4; k++, n++)
    {
        blocs[n] = borne( ZONE + 4 * GIO, ZONE + 8 * GIO, tailles[j], sens, &t[n], f );
        if (!blocs[n] || blocs[n] == (char *)-1) ecarts++;
    }
    dire( "VirtualAlloc2, zone vide", t, n );

    /* Dans la zone de l'hote, de bas en haut. Le plafond est mis tres haut :
     * un plafond sous la fenetre de l'invite 32 bits ferait prendre la demande
     * pour celle d'un invite 32 bits (map_view). C'est la recherche bornee dans
     * la zone encombree, celle que les donnees de fil faisaient a chaque fil. */
    for (j = 0, i = n; j < 3; j++) for (k = 0; k < 4; k++, n++)
    {
        blocs[n] = borne( 0x100000000ull, ZONE, tailles[j], 0, &t[n - i], f );
        if (!blocs[n] || blocs[n] == (char *)-1) ecarts++;
    }
    dire( "VirtualAlloc2, zone hote", t, n - i );

    /* Dans la zone saturee a dessein : une page de 16 Kio a chaque megaoctet
     * de [ZONE, ZONE + 1 Gio). La reponse est connue d'avance, et la meme pour
     * la recherche pas a pas et pour celle qui saute les regions. */
    if (getenv( "FRAGMENTER_HAUT" ))
    {
        /* Les blocs restent poses d'un cas au suivant : chacun compte avec les precedents. */
        static const struct { ULONG_PTR haut; SIZE_T taille; int sens; ULONG_PTR attendu; const char *quoi; } cas[] =
        {
            { ZONE + GIO,     0x10000,  0, ZONE + 0x10000,           "64 Kio de bas en haut : derriere la premiere page" },
            { ZONE + GIO,     0x10000,  1, ZONE + GIO - 0x10000,     "64 Kio de haut en bas : au bout de la zone" },
            { ZONE + 2 * GIO, 0x110000, 0, ZONE + GIO,               "1,1 Mo de bas en haut : aucun trou, donc apres la zone" },
            { ZONE + GIO,     0x110000, 1, 0,                        "1,1 Mo de haut en bas : aucun trou, donc rien" },
            { ZONE + GIO,     0xf0000,  1, ZONE + GIO - 0x1f0000,    "960 Kio de haut en bas : l'avant-dernier trou" },
            { ZONE + GIO,     0xf0000,  0, ZONE + 0x110000,          "960 Kio de bas en haut : le deuxieme trou" },
        };
        for (i = 0; i < sizeof(cas) / sizeof(cas[0]); i++, n++)
        {
            blocs[n] = borne( ZONE, cas[i].haut, cas[i].taille, cas[i].sens, &t[i], f );
            if (blocs[n] != (char *)cas[i].attendu)
            {
                printf( "ECART : %s, attendu %#llx, rendu %p\n", cas[i].quoi, (unsigned long long)cas[i].attendu, blocs[n] );
                ecarts++;
            }
        }
        dire( "VirtualAlloc2, zone saturee", t, i );
    }
    for (i = 0; i < n; i++) if (blocs[i] && blocs[i] != (char *)-1) VirtualFree( blocs[i], 0, MEM_RELEASE );
    printf( "demandes bornees : %d, %d ecarts\n", n, ecarts );
    return ecarts;
}
#endif

int main( int argc, char **argv )
{
    int fils = argc > 1 ? atoi( argv[1] ) : 32, tours = argc > 2 ? atoi( argv[2] ) : 32;
    int i, rates = 0;
    LARGE_INTEGER f, a, b;
    HANDLE *h = calloc( fils ? fils : 1, sizeof(*h) );
    double *t = calloc( (fils > tours ? fils : tours) + 64, sizeof(*t) );

    QueryPerformanceFrequency( &f );
    depart = CreateEventW( NULL, TRUE, FALSE, NULL );

    for (i = 0; i < 64; i++)
    {
        void *p;
        QueryPerformanceCounter( &a );
        p = VirtualAlloc( NULL, 0x100000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
        QueryPerformanceCounter( &b );
        t[i] = micro( a, b, f );
        if (!p) rates++;
    }
    dire( "VirtualAlloc 1 Mo (temoin)", t, 64 );

    for (i = 0; i < fils; i++)
    {
        QueryPerformanceCounter( &a );
        h[i] = CreateThread( NULL, 0, dormeur, NULL, 0, NULL );
        QueryPerformanceCounter( &b );
        t[i] = micro( a, b, f );
        if (!h[i]) rates++;
    }
    if (fils) dire( "CreateThread, fil garde", t, fils );

    for (i = 0; i < tours; i++)
    {
        HANDLE p;
        QueryPerformanceCounter( &a );
        p = CreateThread( NULL, 0, passant, NULL, 0, NULL );
        QueryPerformanceCounter( &b );
        t[i] = micro( a, b, f );
        if (!p) { rates++; continue; }
        WaitForSingleObject( p, INFINITE );
        CloseHandle( p );
    }
    if (tours) dire( "CreateThread, fil passant", t, tours );

#ifdef _WIN64
    rates += demandes_bornees( f );
#endif

    SetEvent( depart );
    for (i = 0; i < fils; i++) if (h[i]) { WaitForSingleObject( h[i], INFINITE ); CloseHandle( h[i] ); }
    printf( "fils partis %ld sur %d, echecs %d : %s\n", partis, fils + tours, rates,
            (partis == fils + tours && !rates) ? "ok" : "ECHEC" );
    return rates != 0;
}
