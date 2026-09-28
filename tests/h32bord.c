/*
 * Invite i386 : l'alerte qui arrive au bord du delai.
 *
 * NtWaitForAlertByThreadId pose un drapeau par fil. L'attente le consomme ;
 * l'expiration, elle, rendait la main sans le relire. Entre l'instant ou le
 * noyau decide que le delai est ecoule et celui ou l'appel revient, le fil peut
 * rester hors processeur -- et une alerte qui arrive la etait rapportee comme
 * une expiration. Le drapeau restait pose, donc rien n'etait perdu, mais
 * l'appelant attendait un tour de plus : cinq secondes pour une section
 * critique.
 *
 * On provoque la course : un fil attend avec un delai court, un autre l'alerte
 * pile a ce moment, avec un peu de gigue. Apres chaque expiration on redemande
 * la main sans attendre : si elle rend ALERTED, le drapeau etait pose au moment
 * meme ou l'on rapportait une expiration -- la course a eu lieu.
 */
#include <windows.h>
#include <stdio.h>

#ifndef STATUS_ALERTED
#define STATUS_ALERTED ((LONG)0x00000101)
#endif
#ifndef STATUS_TIMEOUT
#define STATUS_TIMEOUT ((LONG)0x00000102)
#endif

#define TOURS 20000
#define DELAI_MS 2

static LONG (WINAPI *p_alerter)( HANDLE );
static LONG (WINAPI *p_attendre)( const void *, const LARGE_INTEGER * );

static DWORD dormeur_id;
static volatile LONG pret;
static volatile LONG fini;
static volatile LONG courses, expirations, alertes;

static DWORD WINAPI alerteur( void *p )
{
    LONG i;

    for (i = 0; i < TOURS && !fini; i++)
    {
        while (!pret && !fini) Sleep( 0 );
        pret = 0;
        /* viser le bord : le delai du dormeur, plus ou moins un peu */
        Sleep( DELAI_MS + (i % 3) - 1 );
        p_alerter( (HANDLE)(ULONG_PTR)dormeur_id );
        InterlockedIncrement( &alertes );
    }
    return 0;
}

int main(void)
{
    HMODULE nt = GetModuleHandleW( L"ntdll.dll" );
    LARGE_INTEGER delai = { .QuadPart = -(LONGLONG)DELAI_MS * 10000 };
    LARGE_INTEGER zero = { .QuadPart = 0 };
    HANDLE h;
    LONG i;

    p_alerter  = (void *)GetProcAddress( nt, "NtAlertThreadByThreadId" );
    p_attendre = (void *)GetProcAddress( nt, "NtWaitForAlertByThreadId" );
    if (!p_alerter || !p_attendre) { printf( "appels introuvables\n" ); return 2; }

    dormeur_id = GetCurrentThreadId();
    h = CreateThread( NULL, 0, alerteur, NULL, 0, NULL );

    for (i = 0; i < TOURS; i++)
    {
        LONG st;

        pret = 1;
        st = p_attendre( NULL, &delai );
        if (st == STATUS_TIMEOUT)
        {
            InterlockedIncrement( &expirations );
            /* Le drapeau etait-il pose alors qu'on rapportait une expiration ? */
            if (p_attendre( NULL, &zero ) == STATUS_ALERTED)
                InterlockedIncrement( &courses );
        }
    }
    fini = 1;
    WaitForSingleObject( h, 5000 );
    CloseHandle( h );

    printf( "i386 alerte au bord du delai : %ld courses sur %ld expirations (%ld alertes, %d tours)\n",
            courses, expirations, alertes, TOURS );
    return 0;
}
