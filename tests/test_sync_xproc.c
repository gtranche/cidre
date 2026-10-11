/* Test de la synchronisation en process (0103) : cas inter-processus et chemins non couverts par le micro-banc.
 * Compiler : toolchain/llvm-mingw/bin/x86_64-w64-mingw32-clang -O1 -o test_sync_xproc.exe tests/test_sync_xproc.c
 * Lancer : wine test_sync_xproc.exe  (se relance lui-meme comme enfant). Imprime ok/ECHEC par cas et un bilan. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int echecs;
#define CHECK(cond, nom) do { if (cond) printf( "ok     %s\n", nom ); else { printf( "ECHEC  %s (ligne %d)\n", nom, __LINE__ ); echecs++; } fflush( stdout ); } while (0)

static HANDLE lancer_enfant( const char *role )
{
    char cmd[MAX_PATH + 64], exe[MAX_PATH];
    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    GetModuleFileNameA( NULL, exe, MAX_PATH );
    snprintf( cmd, sizeof(cmd), "\"%s\" %s", exe, role );
    if (!CreateProcessA( NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi )) return NULL;
    CloseHandle( pi.hThread );
    return pi.hProcess;
}

static int enfant( const char *role )
{
    if (!strcmp( role, "signaleur" ))
    {
        HANDLE pret = OpenEventA( EVENT_ALL_ACCESS, FALSE, "cidre_test_pret" );
        HANDLE ev = OpenEventA( EVENT_ALL_ACCESS, FALSE, "cidre_test_ev" );
        HANDLE sem = OpenSemaphoreA( SEMAPHORE_ALL_ACCESS, FALSE, "cidre_test_sem" );
        HANDLE retour = OpenEventA( EVENT_ALL_ACCESS, FALSE, "cidre_test_retour" );
        int i;
        if (!pret || !ev || !sem || !retour) return 2;
        WaitForSingleObject( pret, 5000 );
        Sleep( 50 );                       /* le parent est endormi pour de bon */
        SetEvent( ev );
        ReleaseSemaphore( sem, 3, NULL );
        /* ping-pong inter-processus */
        for (i = 0; i < 1000; i++) { WaitForSingleObject( retour, 5000 ); SetEvent( ev ); }
        return 0;
    }
    if (!strcmp( role, "proprietaire" ))
    {
        HANDLE mtx = OpenMutexA( MUTEX_ALL_ACCESS, FALSE, "cidre_test_mtx" );
        HANDLE pret = OpenEventA( EVENT_ALL_ACCESS, FALSE, "cidre_test_pret" );
        if (!mtx || !pret) return 2;
        WaitForSingleObject( mtx, 5000 );  /* on prend le mutex... */
        SetEvent( pret );
        Sleep( 100 );
        return 0;                           /* ...et on meurt avec : abandon */
    }
    return 3;
}

struct multi { HANDLE evs[2]; HANDLE fini; LONG reveils; };
static DWORD WINAPI attente_multiple( void *arg )
{
    struct multi *m = arg;
    DWORD r = WaitForMultipleObjects( 2, m->evs, FALSE, 10000 );
    if (r == WAIT_OBJECT_0 || r == WAIT_OBJECT_0 + 1) InterlockedIncrement( &m->reveils );
    return r;
}

static DWORD WINAPI poste_message( void *arg )
{
    Sleep( 100 );
    PostMessageA( (HWND)arg, WM_USER + 1, 0, 0 );
    return 0;
}

static void CALLBACK apc( ULONG_PTR p ) { *(int *)p = 1; }

static DWORD WINAPI attend_tout( void *arg )
{
    HANDLE *h = arg;
    return WaitForMultipleObjects( 3, h, TRUE, 10000 );
}

int main( int argc, char **argv )
{
    HANDLE pret, ev, sem, retour, mtx, enfant_h, th, timer;
    DWORD r, t0;
    int i;

    if (argc > 1) return enfant( argv[1] );
    printf( "test_sync_xproc : %s\n", getenv( "CIDRE_SYNC_LOCAL" ) ? "CIDRE_SYNC_LOCAL pose" : "mode serveur" );

    pret   = CreateEventA( NULL, FALSE, FALSE, "cidre_test_pret" );
    ev     = CreateEventA( NULL, FALSE, FALSE, "cidre_test_ev" );
    sem    = CreateSemaphoreA( NULL, 0, 100, "cidre_test_sem" );
    retour = CreateEventA( NULL, FALSE, FALSE, "cidre_test_retour" );
    mtx    = CreateMutexA( NULL, FALSE, "cidre_test_mtx" );

    /* 1. evenement et semaphore signales depuis un autre processus pendant qu'on dort */
    enfant_h = lancer_enfant( "signaleur" );
    CHECK( enfant_h != NULL, "lancement de l'enfant signaleur" );
    SetEvent( pret );
    t0 = GetTickCount();
    r = WaitForSingleObject( ev, 5000 );
    CHECK( r == WAIT_OBJECT_0, "evenement nomme signale par l'autre processus" );
    CHECK( GetTickCount() - t0 >= 40, "on a vraiment dormi (>= 40 ms)" );
    r = WaitForSingleObject( sem, 5000 ); CHECK( r == WAIT_OBJECT_0, "semaphore nomme libere par l'autre processus (1)" );
    r = WaitForSingleObject( sem, 0 ); CHECK( r == WAIT_OBJECT_0, "semaphore (2)" );
    r = WaitForSingleObject( sem, 0 ); CHECK( r == WAIT_OBJECT_0, "semaphore (3)" );
    r = WaitForSingleObject( sem, 0 ); CHECK( r == WAIT_TIMEOUT, "semaphore vide ensuite" );
    t0 = GetTickCount();
    for (i = 0; i < 1000; i++) { SetEvent( retour ); if (WaitForSingleObject( ev, 5000 ) != WAIT_OBJECT_0) break; }
    CHECK( i == 1000, "1000 ping-pong inter-processus" );
    printf( "       ping-pong inter-processus : %.1f us par tour\n", (GetTickCount() - t0) * 1000.0 / 1000 );
    r = WaitForSingleObject( enfant_h, 5000 ); CHECK( r == WAIT_OBJECT_0, "attente de la fin du processus enfant (synchro interne)" );
    CloseHandle( enfant_h );

    /* 2. mutex abandonne par la mort d'un autre processus */
    enfant_h = lancer_enfant( "proprietaire" );
    CHECK( enfant_h != NULL, "lancement de l'enfant proprietaire" );
    r = WaitForSingleObject( pret, 5000 ); CHECK( r == WAIT_OBJECT_0, "l'enfant tient le mutex" );
    r = WaitForSingleObject( mtx, 5000 ); CHECK( r == WAIT_ABANDONED, "mutex abandonne a la mort du processus (WAIT_ABANDONED)" );
    CHECK( ReleaseMutex( mtx ), "ReleaseMutex apres abandon" );
    r = WaitForSingleObject( mtx, 0 ); CHECK( r == WAIT_OBJECT_0, "mutex repris proprement (plus abandonne)" );
    ReleaseMutex( mtx );
    WaitForSingleObject( enfant_h, 5000 ); CloseHandle( enfant_h );

    /* 3. attente de fil, minuterie, APC */
    th = CreateThread( NULL, 0, poste_message, NULL, CREATE_SUSPENDED, NULL );
    r = WaitForSingleObject( th, 0 ); CHECK( r == WAIT_TIMEOUT, "fil suspendu : pas fini" );
    ResumeThread( th );
    r = WaitForSingleObject( th, 5000 ); CHECK( r == WAIT_OBJECT_0, "attente de la fin d'un fil" );
    CloseHandle( th );
    timer = CreateWaitableTimerA( NULL, FALSE, NULL );
    { LARGE_INTEGER due; due.QuadPart = -500000; /* 50 ms */ SetWaitableTimer( timer, &due, 0, NULL, NULL, FALSE ); }
    t0 = GetTickCount();
    r = WaitForSingleObject( timer, 5000 ); CHECK( r == WAIT_OBJECT_0 && GetTickCount() - t0 >= 40, "minuterie auto-reset apres 50 ms" );
    r = WaitForSingleObject( timer, 0 ); CHECK( r == WAIT_TIMEOUT, "minuterie consommee" );
    {
        int touche = 0;
        QueueUserAPC( apc, GetCurrentThread(), (ULONG_PTR)&touche );
        r = WaitForSingleObjectEx( ev, 5000, TRUE );
        CHECK( r == WAIT_IO_COMPLETION && touche, "attente alertable interrompue par une APC" );
        touche = 0;
        QueueUserAPC( apc, GetCurrentThread(), (ULONG_PTR)&touche );
        r = SleepEx( 5000, TRUE );
        CHECK( r == WAIT_IO_COMPLETION && touche, "SleepEx alertable interrompu par une APC" );
    }

    /* 4. file de messages : MsgWaitForMultipleObjects reveille par PostMessage d'un autre fil */
    {
        HWND hwnd = CreateWindowExA( 0, "STATIC", "cidre", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, NULL, NULL );
        MSG msg;
        CHECK( hwnd != NULL, "fenetre message-only" );
        th = CreateThread( NULL, 0, poste_message, hwnd, 0, NULL );
        t0 = GetTickCount();
        r = MsgWaitForMultipleObjects( 1, &ev, FALSE, 5000, QS_POSTMESSAGE );
        CHECK( r == WAIT_OBJECT_0 + 1 && GetTickCount() - t0 >= 80, "MsgWait reveille par le message (apres ~100 ms)" );
        CHECK( PeekMessageA( &msg, hwnd, WM_USER + 1, WM_USER + 1, PM_REMOVE ), "le message est bien la" );
        WaitForSingleObject( th, 5000 ); CloseHandle( th );
        DestroyWindow( hwnd );
    }

    /* 5. 24 fils en attente multiple sur les memes 2 evenements (table d'inscription de 8 : debordement) */
    {
        struct multi m; HANDLE ths[24];
        m.evs[0] = CreateEventA( NULL, FALSE, FALSE, NULL );
        m.evs[1] = CreateEventA( NULL, TRUE, FALSE, NULL );
        m.reveils = 0;
        for (i = 0; i < 24; i++) ths[i] = CreateThread( NULL, 0, attente_multiple, &m, 0, NULL );
        Sleep( 200 );
        for (i = 0; i < 12; i++) { SetEvent( m.evs[0] ); Sleep( 2 ); }   /* auto : un reveil chacun */
        Sleep( 100 );
        CHECK( m.reveils == 12, "12 SetEvent auto -> exactement 12 fils reveilles" );
        SetEvent( m.evs[1] );                                              /* manuel : tous les autres */
        r = WaitForMultipleObjects( 24, ths, TRUE, 10000 );
        CHECK( r == WAIT_OBJECT_0, "les 24 fils sont finis (wait-all sur 24 fils)" );
        CHECK( m.reveils == 24, "24 fils reveilles au total" );
        for (i = 0; i < 24; i++) CloseHandle( ths[i] );
        CloseHandle( m.evs[0] ); CloseHandle( m.evs[1] );
    }

    /* 6. wait-all sur 3 objets signales un a un depuis un autre fil */
    {
        HANDLE h[3] = { CreateEventA( NULL, FALSE, FALSE, NULL ), CreateSemaphoreA( NULL, 0, 10, NULL ), CreateMutexA( NULL, FALSE, NULL ) };
        DWORD code;
        th = CreateThread( NULL, 0, attend_tout, h, 0, NULL );
        Sleep( 100 ); r = WaitForSingleObject( th, 0 ); CHECK( r == WAIT_TIMEOUT, "wait-all pas encore satisfait" );
        SetEvent( h[0] ); Sleep( 50 ); r = WaitForSingleObject( th, 0 ); CHECK( r == WAIT_TIMEOUT, "wait-all : 1/3" );
        ReleaseSemaphore( h[1], 1, NULL );
        r = WaitForSingleObject( th, 5000 ); GetExitCodeThread( th, &code );
        CHECK( r == WAIT_OBJECT_0 && code == WAIT_OBJECT_0, "wait-all satisfait quand le 3e (mutex libre) est pris" );
        r = WaitForSingleObject( h[0], 0 ); CHECK( r == WAIT_TIMEOUT, "wait-all a consomme l'evenement auto" );
        r = WaitForSingleObject( h[1], 0 ); CHECK( r == WAIT_TIMEOUT, "wait-all a consomme le semaphore" );
        CloseHandle( th ); for (i = 0; i < 3; i++) CloseHandle( h[i] );
    }

    /* 7. 64 objets, le dernier signale ; PulseEvent manuel */
    {
        HANDLE h[64];
        for (i = 0; i < 64; i++) h[i] = CreateEventA( NULL, TRUE, i == 63, NULL );
        r = WaitForMultipleObjects( 64, h, FALSE, 0 ); CHECK( r == WAIT_OBJECT_0 + 63, "64 objets : index du signale" );
        r = WaitForMultipleObjects( 64, h, TRUE, 0 ); CHECK( r == WAIT_TIMEOUT, "64 objets wait-all : timeout" );
        for (i = 0; i < 64; i++) CloseHandle( h[i] );
        PulseEvent( ev ); r = WaitForSingleObject( ev, 0 ); CHECK( r == WAIT_TIMEOUT, "PulseEvent sans waiter laisse l'evenement non signale" );
    }

    printf( "bilan : %d echec(s)\n", echecs );
    return echecs ? 1 : 0;
}
