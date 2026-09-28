/* Un invite i386 qui cree un fil et l'attend : le plus petit programme qui
 * distingue « le jeu est bloque » de « le jeu n'a jamais eu de fils ». */
#include <windows.h>
#include <stdio.h>

static DWORD WINAPI travail( void *p )
{
    printf( "fil %lu : parti\n", GetCurrentThreadId() ); fflush( stdout );
    *(int *)p = 42;
    return 7;
}

int main(void)
{
    int valeur = 0;
    DWORD id = 0, code = 0, r;
    HANDLE h = CreateThread( NULL, 0, travail, &valeur, 0, &id );

    printf( "CreateThread = %p id=%lu err=%lu\n", h, id, GetLastError() ); fflush( stdout );
    if (!h) return 1;
    r = WaitForSingleObject( h, 5000 );
    GetExitCodeThread( h, &code );
    printf( "attente = %lu, valeur = %d, code = %lu\n", r, valeur, code );
    printf( "i386 fils : %s\n", (r == WAIT_OBJECT_0 && valeur == 42 && code == 7) ? "ok" : "ECHEC" );
    return 0;
}
