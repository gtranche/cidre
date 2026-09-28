/*
 * Invite i386 : chaque fil retrouve-t-il sa propre alerte ?
 *
 * RtlWaitOnAddress inscrit GetCurrentThreadId() dans sa file, et celui qui
 * reveille appelle NtAlertThreadByThreadId avec ce numero. Du cote hote,
 * l'attente, elle, cherche l'entree du fil courant. Si les deux numeros ne
 * designent pas la meme entree pour un fil donne, ce fil ne sera jamais
 * reveille -- et rien ne le dira.
 *
 * Epreuve : chaque fil s'alerte lui-meme, puis attend sans delai. L'alerte est
 * censee etre retenue, donc l'attente doit rendre STATUS_ALERTED tout de suite.
 * Un fil qui expire est un fil injoignable.
 */
#include <windows.h>
#include <stdio.h>

#define FILS 128

#ifndef STATUS_ALERTED
#define STATUS_ALERTED ((LONG)0x00000101)
#endif

static LONG (WINAPI *p_alerter)( HANDLE );
static LONG (WINAPI *p_attendre)( const void *, const LARGE_INTEGER * );

static volatile LONG injoignables;
static volatile LONG vus;

static DWORD WINAPI essai( void *p )
{
    LARGE_INTEGER zero = { .QuadPart = 0 };  /* pas d'attente du tout */
    LARGE_INTEGER court = { .QuadPart = -5000000 };  /* une demi-seconde */
    DWORD moi = GetCurrentThreadId();
    LONG st;

    /* 1. rien n'a ete alerte : l'attente doit expirer tout de suite */
    st = p_attendre( NULL, &zero );
    if (st == STATUS_ALERTED)
    {
        printf( "fil %04lx : alerte fantome avant toute alerte\n", moi );
        InterlockedIncrement( &injoignables );
        return 0;
    }

    /* 2. on s'alerte soi-meme, puis on attend : doit rendre STATUS_ALERTED */
    st = p_alerter( (HANDLE)(ULONG_PTR)moi );
    if (st)
    {
        printf( "fil %04lx : NtAlertThreadByThreadId rend %08lx\n", moi, st );
        InterlockedIncrement( &injoignables );
        return 0;
    }
    st = p_attendre( NULL, &court );
    if (st != STATUS_ALERTED)
    {
        printf( "fil %04lx : INJOIGNABLE, l'attente rend %08lx\n", moi, st );
        InterlockedIncrement( &injoignables );
    }
    InterlockedIncrement( &vus );
    return 0;
}

int main(void)
{
    HMODULE nt = GetModuleHandleW( L"ntdll.dll" );
    HANDLE h[FILS];
    int i;

    p_alerter  = (void *)GetProcAddress( nt, "NtAlertThreadByThreadId" );
    p_attendre = (void *)GetProcAddress( nt, "NtWaitForAlertByThreadId" );
    if (!p_alerter || !p_attendre) { printf( "appels introuvables\n" ); return 2; }

    /* Le fil principal d'abord. */
    essai( NULL );

    /* Puis des fils crees en serie, dont les numeros sont recycles. */
    for (i = 0; i < FILS; i++)
    {
        HANDLE t = CreateThread( NULL, 0, essai, NULL, 0, NULL );
        WaitForSingleObject( t, INFINITE );
        CloseHandle( t );
    }

    /* Puis des fils simultanes. */
    for (i = 0; i < FILS; i++) h[i] = CreateThread( NULL, 0, essai, NULL, 0, NULL );
    for (i = 0; i < FILS; i++) { WaitForSingleObject( h[i], INFINITE ); CloseHandle( h[i] ); }

    printf( "i386 alertes par numero de fil : %s (%ld injoignables sur %ld)\n",
            injoignables ? "ECHEC" : "ok", injoignables, vus + injoignables );
    return injoignables ? 1 : 0;
}
