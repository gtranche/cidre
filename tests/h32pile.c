/* Les fautes de DREDGE tombent sur un « ret » dont l'ESP est aberrant et
 * aligne sur une page. On verifie donc que chaque fil recoit bien une pile
 * dans la fenetre de l'invite, y compris quand on en demande beaucoup et de
 * grandes -- ce que fait le systeme de taches d'Unity. */
#include <windows.h>
#include <stdio.h>

#define N 48

static volatile LONG mauvais;
static volatile LONG vus;

static DWORD WINAPI travail( void *p )
{
    volatile int local = 0;
    ULONG_PTR esp = (ULONG_PTR)&local;
    NT_TIB *tib = (NT_TIB *)NtCurrentTeb();

    InterlockedIncrement( &vus );
    /* La pile doit etre sous la limite de l'invite et contenir notre variable. */
    if (esp >= 0x80000000u || esp >= (ULONG_PTR)tib->StackBase || esp < (ULONG_PTR)tib->StackLimit)
    {
        printf( "fil %lu : esp=%p base=%p limite=%p\n", GetCurrentThreadId(),
                (void *)esp, tib->StackBase, tib->StackLimit );
        InterlockedIncrement( &mauvais );
    }
    Sleep( 50 );
    (void)p;
    return 0;
}

int main(void)
{
    HANDLE h[N];
    int i, crees = 0;

    for (i = 0; i < N; i++)
    {
        /* 16 Mio reserves, comme un ouvrier de moteur de jeu. */
        h[i] = CreateThread( NULL, 16 * 1024 * 1024, travail, NULL,
                             STACK_SIZE_PARAM_IS_A_RESERVATION, NULL );
        if (!h[i]) { printf( "CreateThread %d : %lu\n", i, GetLastError() ); break; }
        crees++;
    }
    if (crees) WaitForMultipleObjects( crees, h, TRUE, 60000 );
    printf( "crees = %d/%d, vus = %ld, piles aberrantes = %ld\n", crees, N, vus, mauvais );
    printf( "i32 piles : %s\n", (crees == N && vus == N && mauvais == 0) ? "ok" : "ECHEC" );
    return 0;
}
