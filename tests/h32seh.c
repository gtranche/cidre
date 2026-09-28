/* Deux choses que DREDGE fait sans arret et que rien ne mesurait encore :
 * beaucoup de fils a la fois, et des exceptions rattrapees.
 *
 * gcc i686 ne connait pas __try ; on rattrape donc par un gestionnaire
 * vectorise, qui suffit a exercer le meme chemin -- l'invite prend la faute,
 * wow64 lui construit un CONTEXT 32 bits, et il reprend. */
#include <windows.h>
#include <stdio.h>

#define N 16

static volatile LONG total;

static int poubelle;

static LONG CALLBACK rattraper( EXCEPTION_POINTERS *ep )
{
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    /* On detourne l'ecriture vers une case valide et on reprend a la meme
     * instruction : elle refera l'acces, cette fois sur EAX corrige. */
    ep->ContextRecord->Eax = (DWORD)(ULONG_PTR)&poubelle;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI travail( void *p )
{
    int i, local = 0;
    for (i = 0; i < 20000; i++)
    {
        if (i % 997 == 0)
        {
            volatile int *cible = NULL;
            __asm__ volatile( "movl $1, (%%eax)" :: "a"(cible) : "memory" );
        }
        local++;
    }
    InterlockedAdd( &total, local );
    (void)p;
    return 0;
}

int main(void)
{
    HANDLE h[N];
    int i;
    DWORD r;

    AddVectoredExceptionHandler( 1, rattraper );

    for (i = 0; i < N; i++)
        if (!(h[i] = CreateThread( NULL, 0, travail, NULL, 0, NULL )))
        { printf( "CreateThread %d : %lu\n", i, GetLastError() ); return 1; }

    r = WaitForMultipleObjects( N, h, TRUE, 30000 );
    printf( "attente = %lu, total = %ld (attendu %d)\n", r, total, N * 20000 );
    printf( "i386 fils+seh : %s\n", (r == WAIT_OBJECT_0 && total == N * 20000) ? "ok" : "ECHEC" );
    return 0;
}
