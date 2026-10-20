/* Témoin des réveils perdus de la synchro en process (0103, sync_local).
 * Compiler : toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang -O1 -o temoin_sync_reveils.exe tests/temoin_sync_reveils.c
 * Lancer   : CIDRE_SYNC_LOCAL=1 wine temoin_sync_reveils.exe [manches] [strict]   (wineserver -k avant : l'option est lue au démarrage du serveur)
 *
 * Sous Windows (et avec wineserver), chaque unité rendue à un sémaphore et chaque SetEvent sur un événement auto
 * libère un fil qui attendait à cet instant, même si ces appels s'enchaînent avant que le premier fil réveillé ait
 * pris son dû. Un pool d'ouvriers endormis sur un sémaphore (ou un événement auto) que le fil principal réveille par
 * N appels rapprochés doit donc voir ses N ouvriers repartir aussitôt.
 * Cas : sem1 = ReleaseSemaphore(s, 1) N fois ; ev = SetEvent(auto) N fois ; versions « multi » où chaque ouvrier
 * attend { objet, événement jamais signalé } (chemin des attentes multiples) ; « borne » = attente de 1 s au lieu
 * d'infinie (un réveil perdu y devient un faux WAIT_TIMEOUT).
 * Verdict par manche : ok si les N ouvriers sont repartis en moins de 250 ms ; sinon ECHEC avec le délai et le nombre
 * de fils restés endormis (rattrapés par le garde-fou de 2 s pour un sémaphore, jamais pour un événement auto).
 * 0210 corrige le sémaphore ; les cas d'événement auto restent une limite connue, comptés seulement avec « strict ». */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define OUVRIERS 8
#define LIMITE_MS 250

enum cas { SEM1, EV_AUTO, SEM1_MULTI, EV_AUTO_MULTI, SEM1_BORNE, EV_AUTO_BORNE, NB_CAS };
static const char *noms[NB_CAS] = { "sem1", "ev", "sem1-multi", "ev-multi", "sem1-borne", "ev-borne" };

static HANDLE objet, jamais, tous_prets;
static volatile LONG prets, repartis, expires;
static enum cas cas_courant;
static LARGE_INTEGER freq, t_depart, t_reveil[OUVRIERS];

static DWORD WINAPI ouvrier( void *arg )
{
    HANDLE h[2] = { objet, jamais };
    int n = (int)(INT_PTR)arg;
    DWORD r, delai = (cas_courant == SEM1_BORNE || cas_courant == EV_AUTO_BORNE) ? 1000 : INFINITE;
    LARGE_INTEGER t;

    if (InterlockedIncrement( &prets ) == OUVRIERS) SetEvent( tous_prets );
    if (cas_courant == SEM1_MULTI || cas_courant == EV_AUTO_MULTI) r = WaitForMultipleObjects( 2, h, FALSE, delai );
    else r = WaitForSingleObject( objet, delai );
    if (r == WAIT_TIMEOUT) { InterlockedIncrement( &expires ); return 1; }
    QueryPerformanceCounter( &t );
    t_reveil[n] = t;
    InterlockedIncrement( &repartis );
    return 0;
}

static int manche( enum cas c )
{
    HANDLE fils[OUVRIERS];
    LARGE_INTEGER fin, dernier = { 0 };
    int evt = (c == EV_AUTO || c == EV_AUTO_MULTI || c == EV_AUTO_BORNE);
    DWORD i;
    double ms;
    int ok;

    cas_courant = c;
    prets = repartis = expires = 0;
    memset( t_reveil, 0, sizeof(t_reveil) );
    objet = evt ? CreateEventA( NULL, FALSE, FALSE, NULL ) : CreateSemaphoreA( NULL, 0, 1000, NULL );
    jamais = CreateEventA( NULL, TRUE, FALSE, NULL );
    tous_prets = CreateEventA( NULL, TRUE, FALSE, NULL );
    for (i = 0; i < OUVRIERS; i++) fils[i] = CreateThread( NULL, 0, ouvrier, (void *)(INT_PTR)i, 0, NULL );
    WaitForSingleObject( tous_prets, 5000 );
    Sleep( 60 );   /* les ouvriers sont endormis pour de bon */

    QueryPerformanceCounter( &t_depart );
    for (i = 0; i < OUVRIERS; i++)
    {
        if (evt) SetEvent( objet );
        else ReleaseSemaphore( objet, 1, NULL );
    }
    /* le délai = jusqu'au dernier ouvrier reparti (ou 4 s) */
    for (i = 0; i < 400 && repartis + expires < OUVRIERS; i++) Sleep( 10 );
    QueryPerformanceCounter( &fin );
    if (repartis + expires < OUVRIERS)   /* restés endormis : on les libère pour finir proprement */
    {
        SetEvent( jamais );
        for (i = 0; i < 100 && repartis + expires < OUVRIERS; i++)
        {
            if (evt) SetEvent( objet ); else ReleaseSemaphore( objet, 1, NULL );
            Sleep( 10 );
        }
    }
    WaitForMultipleObjects( OUVRIERS, fils, TRUE, 3000 );
    for (i = 0; i < OUVRIERS; i++) if (t_reveil[i].QuadPart > dernier.QuadPart) dernier = t_reveil[i];
    if (repartis < OUVRIERS) dernier = fin;
    ms = (double)(dernier.QuadPart - t_depart.QuadPart) * 1000.0 / freq.QuadPart;
    ok = (repartis == OUVRIERS && !expires && ms < LIMITE_MS);
    printf( "%-6s %-11s repartis %d/%d, expires %d, dernier a %.1f ms\n", ok ? "ok" : "ECHEC", noms[c],
            (int)repartis, OUVRIERS, (int)expires, ms );
    fflush( stdout );
    for (i = 0; i < OUVRIERS; i++) { TerminateThread( fils[i], 9 ); CloseHandle( fils[i] ); }
    CloseHandle( objet ); CloseHandle( jamais ); CloseHandle( tous_prets );
    return ok;
}

/* un evenement auto signale plusieurs fois avant que le premier fil reveille ait pris son du : 0210 ne le corrige pas
 * (limite connue, comme esync/fsync) ; ces cas ne comptent au verdict qu'avec l'argument « strict » */
static int evenement( int c ) { return c == EV_AUTO || c == EV_AUTO_MULTI || c == EV_AUTO_BORNE; }

int main( int argc, char **argv )
{
    int manches = argc > 1 ? atoi( argv[1] ) : 3, m, c, echecs[NB_CAS] = { 0 }, total = 0;
    int strict = argc > 2 && !strcmp( argv[2], "strict" );

    QueryPerformanceFrequency( &freq );
    for (m = 0; m < manches; m++)
        for (c = 0; c < NB_CAS; c++)
            if (!manche( c )) { echecs[c]++; if (strict || !evenement( c )) total++; }
    printf( "bilan :" );
    for (c = 0; c < NB_CAS; c++) printf( " %s %d/%d%s", noms[c], echecs[c], manches, !strict && evenement( c ) ? " (connu)" : "" );
    printf( " -> %s\n", total ? "ECHEC" : "ok" );
    return total ? 1 : 0;
}
