/*
 * Invite x86-64 : suspendre un fil, lire et reecrire son contexte, le reprendre.
 *
 * Le chargeur protege de Diablo II Resurrected (D2R_loader.dll) se figeait sous
 * FEX ARM64EC : des fils crees suspendus restaient dans wait_suspend, jamais
 * repris, et le fil principal les attendait. Ce temoin rejoue, hors jeu, les
 * schemas qu'un tel chargeur emploie :
 *
 *   A  fil cree suspendu, Rcx (routine de depart) reecrit, puis repris ;
 *   B  fil cree suspendu, Rip reecrit directement, puis repris ;
 *   C  NtCreateThreadEx suspendu et cache au debogueur, repris d'un autre fil ;
 *   D  fil qui tourne en code x86-64 : suspendre, lire, reecrire, reprendre, en boucle ;
 *   E  fil dans une attente noyau : suspendre, lire, reecrire, reprendre ;
 *   F  un fil se suspend lui-meme, un autre le reprend ;
 *   G  compte de suspension (deux suspensions, deux reprises) ;
 *   H  registres de debogage poses sur un fil suspendu, relus ;
 *   I  rafale : un fil cree des fils suspendus, un autre les reprend.
 *
 * Chaque attente a un delai : un fil qui ne revient pas est BLOQUE, pas oublie.
 *   x86_64-w64-mingw32-gcc -O1 -o h64suspend.exe h64suspend.c
 * Argument : nombre de tours de D (200 par defaut).
 */
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

#define DELAI 10000

static int echecs;

static void verdict( const char *cas, int ok, const char *detail )
{
    printf( "%s %s%s%s\n", ok ? "OK    " : "ECHEC ", cas, detail ? " : " : "", detail ? detail : "" );
    fflush( stdout );
    if (!ok) echecs++;
}

/* ---------- A, B : fil cree suspendu, contexte reecrit ---------- */

static volatile LONG marque;

static DWORD WINAPI routine_leurre( void *arg )
{
    InterlockedExchange( &marque, 0x1eu );
    return 1;
}

static DWORD WINAPI routine_vraie( void *arg )
{
    InterlockedExchange( &marque, (LONG)(ULONG_PTR)arg );
    return 2;
}

/* Cible de B : appelee comme RtlUserThreadStart ne l'est pas, elle doit donc
 * sortir elle-meme. */
static void routine_rip( void )
{
    InterlockedExchange( &marque, 0x5a );
    ExitThread( 3 );
}

static void cas_a( void )
{
    CONTEXT ctx;
    DWORD code = 0, r;
    char buf[128];
    HANDLE h;

    marque = 0;
    h = CreateThread( NULL, 0, routine_leurre, NULL, CREATE_SUSPENDED, NULL );
    ctx.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext( h, &ctx )) { verdict( "A contexte d'un fil neuf", 0, "GetThreadContext" ); return; }
    snprintf( buf, sizeof(buf), "Rip=%p Rcx=%p (attendu %p) Rdx=%p",
              (void *)ctx.Rip, (void *)ctx.Rcx, (void *)routine_leurre, (void *)ctx.Rdx );
    verdict( "A contexte d'un fil neuf", ctx.Rcx == (DWORD64)routine_leurre, buf );
    ctx.Rcx = (DWORD64)routine_vraie;
    ctx.Rdx = 0x77;
    if (!SetThreadContext( h, &ctx )) { verdict( "A Rcx reecrit", 0, "SetThreadContext" ); return; }
    ResumeThread( h );
    r = WaitForSingleObject( h, DELAI );
    GetExitCodeThread( h, &code );
    snprintf( buf, sizeof(buf), "attente=%lu marque=%#lx code=%lu", r, marque, code );
    verdict( "A Rcx reecrit puis repris", r == 0 && marque == 0x77 && code == 2, buf );
    CloseHandle( h );
}

static void cas_b( void )
{
    CONTEXT ctx;
    DWORD code = 0, r;
    char buf[128];
    HANDLE h;

    marque = 0;
    h = CreateThread( NULL, 0, routine_leurre, NULL, CREATE_SUSPENDED, NULL );
    ctx.ContextFlags = CONTEXT_FULL;
    GetThreadContext( h, &ctx );
    ctx.Rip = (DWORD64)routine_rip;
    ctx.Rsp = (ctx.Rsp & ~15) - 8;
    if (!SetThreadContext( h, &ctx )) { verdict( "B Rip reecrit", 0, "SetThreadContext" ); return; }
    ResumeThread( h );
    r = WaitForSingleObject( h, DELAI );
    GetExitCodeThread( h, &code );
    snprintf( buf, sizeof(buf), "attente=%lu marque=%#lx code=%lu", r, marque, code );
    verdict( "B Rip reecrit puis repris", r == 0 && marque == 0x5a && code == 3, buf );
    CloseHandle( h );
}

/* ---------- C : NtCreateThreadEx suspendu, cache, repris d'ailleurs ---------- */

typedef NTSTATUS (NTAPI *NtCreateThreadEx_t)( HANDLE *, ACCESS_MASK, void *, HANDLE, void *, void *,
                                              ULONG, SIZE_T, SIZE_T, SIZE_T, void * );
static HANDLE a_reprendre;

static DWORD WINAPI repreneur( void *arg )
{
    Sleep( 50 );
    return ResumeThread( a_reprendre );
}

static void cas_c( void )
{
    NtCreateThreadEx_t pNtCreateThreadEx =
        (NtCreateThreadEx_t)GetProcAddress( GetModuleHandleA( "ntdll" ), "NtCreateThreadEx" );
    HANDLE h = NULL, r2;
    NTSTATUS st;
    DWORD r, code = 0;
    char buf[128];

    marque = 0;
    st = pNtCreateThreadEx( &h, THREAD_ALL_ACCESS, NULL, GetCurrentProcess(), routine_vraie, (void *)0x33,
                            0x1 /* CREATE_SUSPENDED */ | 0x4 /* HIDE_FROM_DEBUGGER */, 0, 0, 0, NULL );
    if (st) { snprintf( buf, sizeof(buf), "NtCreateThreadEx %#lx", st ); verdict( "C cache et suspendu", 0, buf ); return; }
    a_reprendre = h;
    r2 = CreateThread( NULL, 0, repreneur, NULL, 0, NULL );
    r = WaitForSingleObject( h, DELAI );
    GetExitCodeThread( h, &code );
    snprintf( buf, sizeof(buf), "attente=%lu marque=%#lx code=%lu", r, marque, code );
    verdict( "C cache, suspendu, repris d'un autre fil", r == 0 && marque == 0x33, buf );
    WaitForSingleObject( r2, DELAI );
    CloseHandle( r2 );
    CloseHandle( h );
}

/* ---------- D : fil qui tourne ---------- */

static volatile LONG64 tours_boucle;
static volatile LONG arret;

__attribute__((noinline)) static DWORD WINAPI boucle( void *arg )
{
    while (!arret)
    {
        unsigned i;
        LONG64 x = tours_boucle;
        for (i = 0; i < 1000; i++) x = x * 6364136223846793005LL + 1442695040888963407LL;
        tours_boucle = tours_boucle + 1 + (x & 0);
    }
    return 4;
}

__attribute__((noinline)) static void fin_boucle( void ) { }

static void cas_d( int tours )
{
    HANDLE h;
    CONTEXT ctx;
    int i, hors = 0, echec_get = 0, echec_set = 0, sans_progres = 0;
    DWORD r, max_ms = 0, t0, dt;
    LONG64 avant;
    char buf[200];

    arret = 0;
    tours_boucle = 0;
    h = CreateThread( NULL, 0, boucle, NULL, 0, NULL );
    while (!tours_boucle) Sleep( 1 );
    for (i = 0; i < tours; i++)
    {
        t0 = GetTickCount();
        if (SuspendThread( h ) == (DWORD)-1) { echec_get++; break; }
        ctx.ContextFlags = CONTEXT_FULL;
        if (!GetThreadContext( h, &ctx )) echec_get++;
        dt = GetTickCount() - t0;
        if (dt > max_ms) max_ms = dt;
        /* Rip dans la boucle ou dans du code d'ntdll (tranche de temps) : on
         * ne compte que les Rip hors de l'image. */
        if (ctx.Rip < (DWORD64)GetModuleHandleA( NULL ) || ctx.Rip > (DWORD64)fin_boucle + 0x10000) hors++;
        if (!SetThreadContext( h, &ctx )) echec_set++;
        avant = tours_boucle;
        ResumeThread( h );
        if (i % 20 == 19)
        {
            Sleep( 5 );
            if (tours_boucle == avant) sans_progres++;
        }
    }
    arret = 1;
    r = WaitForSingleObject( h, DELAI );
    snprintf( buf, sizeof(buf), "tours=%d get=%d set=%d Rip hors image=%d sans progres=%d max suspendre+lire=%lums fin=%lu",
              i, echec_get, echec_set, hors, sans_progres, max_ms, r );
    verdict( "D fil en calcul suspendu/lu/reecrit/repris", r == 0 && !echec_get && !echec_set && !sans_progres, buf );
    CloseHandle( h );
}

/* ---------- E : fil en attente noyau ---------- */

static HANDLE evt;

static DWORD WINAPI attendeur( void *arg )
{
    return WaitForSingleObject( evt, INFINITE ) == 0 ? 5 : 6;
}

static void cas_e( void )
{
    HANDLE h;
    CONTEXT ctx;
    DWORD r, code = 0;
    int i, bad = 0;
    char buf[128];

    evt = CreateEventA( NULL, FALSE, FALSE, NULL );
    h = CreateThread( NULL, 0, attendeur, NULL, 0, NULL );
    Sleep( 50 );
    for (i = 0; i < 50; i++)
    {
        SuspendThread( h );
        ctx.ContextFlags = CONTEXT_FULL;
        if (!GetThreadContext( h, &ctx )) bad++;
        if (!SetThreadContext( h, &ctx )) bad++;
        ResumeThread( h );
    }
    SetEvent( evt );
    r = WaitForSingleObject( h, DELAI );
    GetExitCodeThread( h, &code );
    snprintf( buf, sizeof(buf), "erreurs=%d attente=%lu code=%lu", bad, r, code );
    verdict( "E fil en attente suspendu/lu/reecrit/repris", !bad && r == 0 && code == 5, buf );
    CloseHandle( h );
    CloseHandle( evt );
}

/* ---------- F : un fil se suspend lui-meme ---------- */

static volatile LONG apres_suspension;

static DWORD WINAPI auto_suspendu( void *arg )
{
    SuspendThread( GetCurrentThread() );
    InterlockedExchange( &apres_suspension, 1 );
    return 7;
}

static void cas_f( void )
{
    HANDLE h;
    DWORD r, prev = 0;
    int i;
    char buf[128];

    apres_suspension = 0;
    h = CreateThread( NULL, 0, auto_suspendu, NULL, 0, NULL );
    for (i = 0; i < 1000; i++)
    {
        /* attendre qu'il soit suspendu : SuspendThread rend le compte d'avant */
        prev = SuspendThread( h );
        ResumeThread( h );
        if (prev == 1) break;
        Sleep( 1 );
    }
    ResumeThread( h );
    r = WaitForSingleObject( h, DELAI );
    snprintf( buf, sizeof(buf), "compte vu=%lu attente=%lu", prev, r );
    verdict( "F fil suspendu par lui-meme, repris", r == 0 && apres_suspension == 1, buf );
    CloseHandle( h );
}

/* ---------- G : compte de suspension ---------- */

static void cas_g( void )
{
    HANDLE h;
    DWORD s1, s2, r1, r2, r3, w;
    char buf[128];

    arret = 0;
    tours_boucle = 0;
    h = CreateThread( NULL, 0, boucle, NULL, 0, NULL );
    while (!tours_boucle) Sleep( 1 );
    s1 = SuspendThread( h );
    s2 = SuspendThread( h );
    r1 = ResumeThread( h );
    r2 = ResumeThread( h );
    r3 = ResumeThread( h );
    arret = 1;
    w = WaitForSingleObject( h, DELAI );
    snprintf( buf, sizeof(buf), "suspendre %lu,%lu reprendre %lu,%lu,%lu attente=%lu", s1, s2, r1, r2, r3, w );
    verdict( "G compte de suspension", s1 == 0 && s2 == 1 && r1 == 2 && r2 == 1 && r3 == 0 && w == 0, buf );
    CloseHandle( h );
}

/* ---------- H : registres de debogage ---------- */

static void cas_h( void )
{
    CONTEXT ctx;
    HANDLE h;
    DWORD r;
    BOOL s;
    char buf[160];

    marque = 0;
    h = CreateThread( NULL, 0, routine_vraie, (void *)0x44, CREATE_SUSPENDED, NULL );
    memset( &ctx, 0, sizeof(ctx) );
    ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    ctx.Dr0 = (DWORD64)fin_boucle;
    ctx.Dr7 = 0;  /* adresse posee, point d'arret desarme */
    s = SetThreadContext( h, &ctx );
    memset( &ctx, 0, sizeof(ctx) );
    ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    GetThreadContext( h, &ctx );
    ResumeThread( h );
    r = WaitForSingleObject( h, DELAI );
    snprintf( buf, sizeof(buf), "set=%d Dr0 relu=%p (pose %p) attente=%lu marque=%#lx",
              s, (void *)ctx.Dr0, (void *)fin_boucle, r, marque );
    /* Seul le blocage compte : FEX n'emule pas les points d'arret materiels. */
    verdict( "H registres de debogage sur un fil suspendu", r == 0 && marque == 0x44, buf );
    CloseHandle( h );
}

/* ---------- I : rafale de fils suspendus ---------- */

#define RAFALE 64
static HANDLE rafale[RAFALE];
static volatile LONG rafale_prets, rafale_finis;

static DWORD WINAPI membre( void *arg )
{
    InterlockedIncrement( &rafale_finis );
    return 0;
}

static DWORD WINAPI createur( void *arg )
{
    int i;
    CONTEXT ctx;
    for (i = 0; i < RAFALE; i++)
    {
        rafale[i] = CreateThread( NULL, 0, routine_leurre, NULL, CREATE_SUSPENDED, NULL );
        ctx.ContextFlags = CONTEXT_FULL;
        GetThreadContext( rafale[i], &ctx );
        ctx.Rcx = (DWORD64)membre;
        SetThreadContext( rafale[i], &ctx );
        InterlockedIncrement( &rafale_prets );
    }
    return 0;
}

static void cas_i( void )
{
    HANDLE c;
    int i, rep = 0;
    DWORD r;
    char buf[128];

    rafale_prets = rafale_finis = 0;
    c = CreateThread( NULL, 0, createur, NULL, 0, NULL );
    for (i = 0; i < RAFALE; i++)
    {
        while (rafale_prets <= i) Sleep( 0 );
        if (ResumeThread( rafale[i] ) == 1) rep++;
    }
    WaitForSingleObject( c, DELAI );
    r = WaitForMultipleObjects( RAFALE, rafale, TRUE, DELAI );
    snprintf( buf, sizeof(buf), "repris=%d finis=%ld attente=%lu", rep, rafale_finis, r );
    verdict( "I rafale de fils suspendus repris", rep == RAFALE && rafale_finis == RAFALE && r == 0, buf );
    for (i = 0; i < RAFALE; i++) CloseHandle( rafale[i] );
    CloseHandle( c );
}

int main( int argc, char **argv )
{
    int tours = argc > 1 ? atoi( argv[1] ) : 200;

    setvbuf( stdout, NULL, _IONBF, 0 );
    cas_a();
    cas_b();
    cas_c();
    cas_d( tours );
    cas_e();
    cas_f();
    cas_g();
    cas_h();
    cas_i();
    printf( "h64suspend : %d echec(s)\n", echecs );
    return echecs;
}
