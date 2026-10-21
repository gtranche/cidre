/* Témoin des rafales de SetEvent sur un événement auto (synchro en process, 0103 / remise directe 0216).
 * Sous Windows, chaque SetEvent arrivé pendant qu'au moins un fil attend en libère exactement un, et l'événement reste
 * non signalé ; c'est ce que suppose un pool d'ouvriers réveillés « un SetEvent par travail » (Detroit: Become Human ne
 * présentait jamais une image au démarrage avec recompilation quand des réveils se perdaient, 2026-10-21).
 * Compiler : toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang -O1 -o temoin_rafale_auto.exe tests/temoin_rafale_auto.c
 * Lancer   : CIDRE_SYNC_LOCAL=1 wine temoin_rafale_auto.exe [manches]
 * Par manche : M = 12 dormeurs (moitié WaitForSingleObject, moitié WaitForMultipleObjects { ev, fin }), tous
 * endormis ; une fois sur quatre, l'un d'eux est tué (TerminateThread) avant la rafale ; P = 4 producteurs envoient
 * ensemble autant de SetEvent qu'il reste de dormeurs vivants. Attendu : tous repartent en moins de 250 ms, chacun une
 * seule fois, et l'événement finit non signalé ; puis un SetEvent de plus sans dormeur doit laisser exactement une
 * libération (une attente à 0 ms réussit, la suivante non). */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define M 12
#define P 4

static HANDLE ev, fin, depart, prets_ev;
static volatile LONG prets, repartis, a_envoyer;

static DWORD WINAPI dormeur( void *arg )
{
    HANDLE h[2] = { ev, fin };
    DWORD r;
    if (InterlockedIncrement( &prets ) == M) SetEvent( prets_ev );
    if ((INT_PTR)arg & 1) r = WaitForMultipleObjects( 2, h, FALSE, 5000 );
    else r = WaitForSingleObject( ev, 5000 );
    if (r == WAIT_OBJECT_0) InterlockedIncrement( &repartis );
    return r;
}

static DWORD WINAPI producteur( void *arg )
{
    WaitForSingleObject( depart, INFINITE );
    while (InterlockedDecrement( &a_envoyer ) >= 0) SetEvent( ev );
    return 0;
}

int main( int argc, char **argv )
{
    int manches = argc > 1 ? atoi( argv[1] ) : 2000, m, i, perdus = 0, exces = 0, residu = 0, lents = 0;
    int detail = 0, sans_tue = 0;   /* arguments : « detail » (une ligne par manche fautive), « sans-tue » */
    for (i = 2; i < argc; i++) { if (!strcmp( argv[i], "detail" )) detail = 1; if (!strcmp( argv[i], "sans-tue" )) sans_tue = 1; }
    LARGE_INTEGER f, t0, t1;
    double pire = 0;

    QueryPerformanceFrequency( &f );
    for (m = 0; m < manches; m++)
    {
        HANDLE d[M], p[P];
        int tue = !sans_tue && (m % 4 == 3), vivants = M - tue, passes = 0, apres;
        double ms;

        ev = CreateEventA( NULL, FALSE, FALSE, NULL );
        fin = CreateEventA( NULL, TRUE, FALSE, NULL );
        depart = CreateEventA( NULL, TRUE, FALSE, NULL );
        prets_ev = CreateEventA( NULL, TRUE, FALSE, NULL );
        prets = repartis = 0;
        for (i = 0; i < M; i++) d[i] = CreateThread( NULL, 0, dormeur, (void *)(INT_PTR)i, 0, NULL );
        WaitForSingleObject( prets_ev, 5000 );
        Sleep( 20 );   /* tous endormis pour de bon (sous l'emulateur, 3 ms ne suffisaient pas toujours) */
        /* le tue : tour a tour un dormeur simple (indice 0) et un dormeur en attente multiple (indice 1) */
        if (tue) { TerminateThread( d[(m / 4) % 2], 99 ); WaitForSingleObject( d[(m / 4) % 2], 2000 ); }
        a_envoyer = vivants;
        for (i = 0; i < P; i++) p[i] = CreateThread( NULL, 0, producteur, NULL, 0, NULL );
        QueryPerformanceCounter( &t0 );
        SetEvent( depart );
        for (i = 0; i < 250 && repartis < vivants; i++) Sleep( 1 );
        QueryPerformanceCounter( &t1 );
        ms = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / f.QuadPart;
        if (ms > pire) pire = ms;
        WaitForMultipleObjects( P, p, TRUE, 2000 );
        Sleep( 2 );
        apres = repartis;
        if (repartis < vivants) { perdus += vivants - repartis; lents++; }
        if (repartis > vivants) exces += repartis - vivants;
        if (WaitForSingleObject( ev, 0 ) == WAIT_OBJECT_0) residu++;   /* devait finir non signale */
        SetEvent( ev );   /* sans dormeur : une liberation en reserve, pas deux */
        while (passes < 3 && WaitForSingleObject( ev, 0 ) == WAIT_OBJECT_0) passes++;
        if (passes != 1) residu++;
        SetEvent( fin );   /* libere les restes (WaitForMultipleObjects) ; les autres expirent a 5 s */
        for (i = 0; i < 300 && repartis < vivants; i++) { SetEvent( ev ); Sleep( 1 ); }
        if (detail && (apres != vivants || passes != 1))
        {
            LARGE_INTEGER t2;
            QueryPerformanceCounter( &t2 );
            printf( "  manche %d : %d/%d repartis a la rafale, %d apres nettoyage (%.0f ms), tue %s, passages %d\n",
                    m, apres, vivants, (int)repartis, (double)(t2.QuadPart - t1.QuadPart) * 1000.0 / f.QuadPart,
                    tue ? ((m / 4) % 2 ? "multiple" : "simple") : "non", passes );
            fflush( stdout );
        }
        WaitForMultipleObjects( M, d, TRUE, 6000 );
        for (i = 0; i < M; i++) CloseHandle( d[i] );
        for (i = 0; i < P; i++) CloseHandle( p[i] );
        CloseHandle( ev ); CloseHandle( fin ); CloseHandle( depart ); CloseHandle( prets_ev );
    }
    printf( "%s rafales : %d manches, %d dormeurs restes endormis (dans %d manches), %d liberations de trop, "
            "%d etats finaux faux, pire %.1f ms\n", perdus || exces || residu ? "ECHEC" : "ok", manches, perdus, lents,
            exces, residu, pire );
    return perdus || exces || residu;
}
