/*
 * Invite i386 : chercher un reveil perdu.
 *
 * Sans semaphore, une section critique de Wine attend par RtlWaitOnAddress et
 * se fait reveiller par RtlWakeAddressSingle -- donc par le couple
 * NtWaitForAlertByThreadId / NtAlertThreadByThreadId. Sur DREDGE, une section
 * d'UnityPlayer finit verrouillee avec « blocked by 0000 » : un dormeur qui
 * n'a jamais ete reveille.
 *
 * Trois epreuves, de la plus directe a la plus realiste :
 *   1. va-et-vient strict sur WaitOnAddress / WakeByAddressSingle, deux fils ;
 *   2. huit fils qui se disputent une section critique ;
 *   3. une variable de condition, qui emprunte le meme chemin.
 *
 * Un chien de garde surveille la progression : un reveil perdu ne se voit pas
 * a un resultat faux, mais a un compteur qui cesse d'avancer.
 */
#include <windows.h>
#include <stdio.h>

#define FILS      8
#define TOURS     200000
#define VAETVIENT 200000

static BOOL (WINAPI *p_WaitOnAddress)( volatile VOID *, PVOID, SIZE_T, DWORD );
static void (WINAPI *p_WakeByAddressSingle)( PVOID );

static CRITICAL_SECTION section;
static volatile LONG compteur;      /* avance a chaque tour, toutes epreuves */
static volatile LONG jeton;         /* va-et-vient : a qui le tour */
static volatile LONG fini;
static CONDITION_VARIABLE cv;
static CRITICAL_SECTION cv_section;
static volatile LONG cv_pret;
static const char *epreuve = "depart";

static DWORD WINAPI chien_de_garde( void *p )
{
    LONG vu = -1;
    int immobile = 0;

    while (!fini)
    {
        LONG maintenant = compteur;

        if (maintenant == vu)
        {
            if (++immobile >= 10)
            {
                printf( "BLOQUE pendant l'epreuve \"%s\" : le compteur reste a %ld\n", epreuve, maintenant );
                fflush( stdout );
                ExitProcess( 1 );
            }
        }
        else { immobile = 0; vu = maintenant; }
        Sleep( 1000 );
    }
    return 0;
}

/* --- 1. va-et-vient strict sur le futex --------------------------------- */

static DWORD WINAPI cote( void *p )
{
    LONG moi = (LONG)(ULONG_PTR)p, i;

    for (i = 0; i < VAETVIENT; i++)
    {
        LONG pas_moi = !moi;

        while (jeton != moi)
        {
            /* Attendre tant que « jeton » vaut l'autre valeur. */
            p_WaitOnAddress( &jeton, &pas_moi, sizeof(jeton), INFINITE );
        }
        InterlockedExchange( &jeton, !moi );
        p_WakeByAddressSingle( (PVOID)&jeton );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

/* --- 2. huit fils sur une section critique ------------------------------ */

static volatile LONG partage;

static DWORD WINAPI disputeur( void *p )
{
    LONG i;

    for (i = 0; i < TOURS; i++)
    {
        EnterCriticalSection( &section );
        partage++;
        LeaveCriticalSection( &section );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

/* --- 3. variable de condition ------------------------------------------- */

static DWORD WINAPI dormeur( void *p )
{
    LONG i;

    for (i = 0; i < TOURS / 20; i++)
    {
        EnterCriticalSection( &cv_section );
        while (!cv_pret) SleepConditionVariableCS( &cv, &cv_section, INFINITE );
        cv_pret = 0;
        LeaveCriticalSection( &cv_section );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

static DWORD WINAPI reveilleur( void *p )
{
    LONG i;

    for (i = 0; i < TOURS / 20; i++)
    {
        EnterCriticalSection( &cv_section );
        cv_pret = 1;
        WakeConditionVariable( &cv );
        LeaveCriticalSection( &cv_section );
        while (cv_pret && !fini) Sleep( 0 );
    }
    return 0;
}

/* --- 4. le meme va-et-vient, mais harcele par des suspensions ----------- */

static HANDLE cibles[2];
static volatile LONG suspendre_fini;

static DWORD WINAPI harceleur( void *p )
{
    int i = 0;

    while (!suspendre_fini)
    {
        HANDLE h = cibles[i++ & 1];
        if (h && SuspendThread( h ) != (DWORD)-1)
        {
            Sleep( 0 );
            ResumeThread( h );
        }
    }
    return 0;
}

/* --- 5. verrous SRW : ceux-la attendent sans delai --------------------- */

static SRWLOCK srw;
static volatile LONG srw_partage;

static DWORD WINAPI srw_exclusif( void *p )
{
    LONG i;
    for (i = 0; i < TOURS / 2; i++)
    {
        AcquireSRWLockExclusive( &srw );
        srw_partage++;
        ReleaseSRWLockExclusive( &srw );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

static DWORD WINAPI srw_partage_fn( void *p )
{
    LONG i;
    for (i = 0; i < TOURS / 2; i++)
    {
        AcquireSRWLockShared( &srw );
        (void)srw_partage;
        ReleaseSRWLockShared( &srw );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

static void attendre( HANDLE *h, int n )
{
    int i;
    for (i = 0; i < n; i++) { WaitForSingleObject( h[i], INFINITE ); CloseHandle( h[i] ); }
}

int main(void)
{
    HANDLE h[FILS], garde;
    HMODULE kb = GetModuleHandleW( L"kernelbase.dll" );
    int i;

    p_WaitOnAddress = (void *)GetProcAddress( kb, "WaitOnAddress" );
    p_WakeByAddressSingle = (void *)GetProcAddress( kb, "WakeByAddressSingle" );
    if (!p_WaitOnAddress || !p_WakeByAddressSingle)
    { printf( "WaitOnAddress introuvable\n" ); return 2; }

    InitializeCriticalSection( &section );
    InitializeCriticalSection( &cv_section );
    InitializeConditionVariable( &cv );
    garde = CreateThread( NULL, 0, chien_de_garde, NULL, 0, NULL );

    epreuve = "va-et-vient WaitOnAddress";
    for (i = 0; i < 2; i++) h[i] = CreateThread( NULL, 0, cote, (void *)(ULONG_PTR)i, 0, NULL );
    attendre( h, 2 );
    printf( "va-et-vient : %d tours, ok\n", VAETVIENT * 2 ); fflush( stdout );

    epreuve = "section critique a huit fils";
    for (i = 0; i < FILS; i++) h[i] = CreateThread( NULL, 0, disputeur, NULL, 0, NULL );
    attendre( h, FILS );
    printf( "section critique : partage=%ld (attendu %d)%s\n", partage, FILS * TOURS,
            partage == FILS * TOURS ? ", ok" : " -- ECART" ); fflush( stdout );

    epreuve = "variable de condition";
    h[0] = CreateThread( NULL, 0, dormeur, NULL, 0, NULL );
    h[1] = CreateThread( NULL, 0, reveilleur, NULL, 0, NULL );
    attendre( h, 2 );
    printf( "variable de condition : %d reveils, ok\n", TOURS / 20 ); fflush( stdout );

    epreuve = "va-et-vient sous suspension";
    jeton = 0;
    for (i = 0; i < 2; i++)
    {
        h[i] = CreateThread( NULL, 0, cote, (void *)(ULONG_PTR)i, CREATE_SUSPENDED, NULL );
        cibles[i] = h[i];
    }
    h[2] = CreateThread( NULL, 0, harceleur, NULL, 0, NULL );
    for (i = 0; i < 2; i++) ResumeThread( h[i] );
    attendre( h, 2 );
    suspendre_fini = 1;
    WaitForSingleObject( h[2], INFINITE ); CloseHandle( h[2] );
    printf( "va-et-vient sous suspension : %d tours, ok\n", VAETVIENT * 2 ); fflush( stdout );

    epreuve = "verrous SRW";
    InitializeSRWLock( &srw );
    for (i = 0; i < FILS; i++)
        h[i] = CreateThread( NULL, 0, (i & 1) ? srw_partage_fn : srw_exclusif, NULL, 0, NULL );
    attendre( h, FILS );
    printf( "verrous SRW : partage=%ld (attendu %d)%s\n", srw_partage, FILS / 2 * (TOURS / 2),
            srw_partage == FILS / 2 * (TOURS / 2) ? ", ok" : " -- ECART" ); fflush( stdout );

    fini = 1;
    WaitForSingleObject( garde, 2000 );
    printf( "i386 reveils : ok (%ld tours)\n", compteur );
    return partage == FILS * TOURS ? 0 : 1;
}
