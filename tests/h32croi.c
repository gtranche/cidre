/* Une pile Windows n'est engagee qu'au fur et a mesure : toucher la page de
 * garde doit en engager une de plus. Si l'hote ne reconnait pas l'adresse
 * comme appartenant a la pile de l'invite, la croissance echoue et l'acces
 * devient une faute -- sur une adresse alignee sur une page, exactement ce que
 * DREDGE montrait. */
#include <windows.h>
#include <stdio.h>

static volatile LONG profondeur_max;

static int __attribute__((noinline)) creuser( int n )
{
    volatile char cadre[4096];
    cadre[0] = (char)n;
    cadre[4095] = (char)n;
    if (n <= 0) return cadre[0];
    return creuser( n - 1 ) + cadre[4095];
}

static DWORD WINAPI travail( void *p )
{
    /* 2000 cadres de 4 Kio = 8 Mio de pile, bien au-dela de l'engagement
     * initial (64 Kio par defaut). */
    creuser( 2000 );
    InterlockedExchange( &profondeur_max, 2000 );
    (void)p;
    return 0;
}

int main(void)
{
    HANDLE h[8];
    int i;
    DWORD r;

    /* Le fil principal n'a qu'un Mio reserve : on reste dessous. */
    printf( "fil principal : " ); fflush( stdout );
    creuser( 150 );
    printf( "ok\n" ); fflush( stdout );

    for (i = 0; i < 8; i++)
        h[i] = CreateThread( NULL, 16 * 1024 * 1024, travail, NULL,
                             STACK_SIZE_PARAM_IS_A_RESERVATION, NULL );
    r = WaitForMultipleObjects( 8, h, TRUE, 60000 );
    printf( "attente = %lu, profondeur = %ld\n", r, profondeur_max );
    printf( "i386 croissance de pile : %s\n",
            (r == WAIT_OBJECT_0 && profondeur_max == 2000) ? "ok" : "ECHEC" );
    return 0;
}
