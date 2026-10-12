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
 *
 * Le meme source sert aux deux invites :
 *   i686-w64-mingw32-clang -O1 -o h32alerte.exe h32alerte.c
 *   x86_64-w64-mingw32-clang -O1 -o h64alerte.exe h32alerte.c
 * Arguments : le nombre de manches de fils simultanes (1 par defaut), puis le
 * nombre de fils de charge (0 par defaut). Un fil de charge fabrique sans cesse
 * du code neuf : chaque fonction appelee une premiere fois oblige l'emulateur a
 * traduire un bloc, donc a prendre en ecriture le verrou de son cache de blocs.
 * Les fils de l'epreuve, eux, le prennent en lecture entre leur alerte et leur
 * attente -- et l'attente de ce verrou, quand il est dispute, reprenait l'alerte
 * posee par l'invite (0120). Sans charge le defaut ne se voit qu'a froid.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN64
#define INVITE "x86-64"
#else
#define INVITE "i386"
#endif

#define FILS 128

#ifndef STATUS_ALERTED
#define STATUS_ALERTED ((LONG)0x00000101)
#endif

static LONG (WINAPI *p_alerter)( HANDLE );
static LONG (WINAPI *p_attendre)( const void *, const LARGE_INTEGER * );

static volatile LONG injoignables;
static volatile LONG vus;

static volatile LONG fini;

static DWORD WINAPI charge( void *p )
{
    enum { TAILLE = 0x10000, PAS = 16 };
    unsigned int i, somme = 0;

    while (!fini)
    {
        unsigned char *code = VirtualAlloc( NULL, TAILLE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE );

        if (!code) break;
        for (i = 0; i < TAILLE / PAS; i++)
        {
            unsigned char *f = code + i * PAS;
            f[0] = 0xb8; *(unsigned int *)(f + 1) = i;  /* mov eax, i */
            f[5] = 0xc3;                                /* ret */
        }
        for (i = 0; i < TAILLE / PAS && !fini; i++) somme += ((unsigned int (*)(void))(code + i * PAS))();
        VirtualFree( code, 0, MEM_RELEASE );
    }
    return somme;
}

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

int main( int argc, char **argv )
{
    HMODULE nt = GetModuleHandleW( L"ntdll.dll" );
    HANDLE h[FILS];
    HANDLE hc[16];
    int i, manche, manches = argc > 1 ? atoi( argv[1] ) : 1;
    int charges = argc > 2 ? atoi( argv[2] ) : 0;

    p_alerter  = (void *)GetProcAddress( nt, "NtAlertThreadByThreadId" );
    p_attendre = (void *)GetProcAddress( nt, "NtWaitForAlertByThreadId" );
    if (!p_alerter || !p_attendre) { printf( "appels introuvables\n" ); return 2; }

    if (charges > 16) charges = 16;
    for (i = 0; i < charges; i++) hc[i] = CreateThread( NULL, 0, charge, NULL, 0, NULL );

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
    for (manche = 0; manche < manches; manche++)
    {
        for (i = 0; i < FILS; i++) h[i] = CreateThread( NULL, 0, essai, NULL, 0, NULL );
        for (i = 0; i < FILS; i++) { WaitForSingleObject( h[i], INFINITE ); CloseHandle( h[i] ); }
    }

    fini = 1;
    for (i = 0; i < charges; i++) { WaitForSingleObject( hc[i], INFINITE ); CloseHandle( hc[i] ); }

    printf( INVITE " alertes par numero de fil : %s (%ld injoignables sur %ld)\n",
            injoignables ? "ECHEC" : "ok", injoignables, vus + injoignables );
    return injoignables ? 1 : 0;
}
