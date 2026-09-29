/*
 * Invite x86-64 : le stockage local par fil est-il en place ?
 *
 * Vermintide 2 tombe dans le demarrage de sa CRT, sur un memset dont la
 * destination vaut 0x10 -- un pointeur nul plus un deplacement. Son image porte
 * une section .tls, et c'est le chargeur qui doit poser le bloc et son pointeur
 * dans le TEB. S'il manque, toute donnee locale au fil se lit a « nul plus
 * deplacement », ce qui est exactement la forme de la faute.
 *
 * On verifie donc les trois choses que le chargeur doit garantir :
 *   - le pointeur de TLS du TEB existe,
 *   - les donnees __declspec(thread) sont lisibles et initialisees,
 *   - un fil cree ensuite en obtient sa propre copie, elle aussi initialisee.
 */
#include <windows.h>
#include <stdio.h>

__thread int temoin = 0x5A5A5A5A;
__thread char tampon[960];

static int echecs;

static void verifier( const char *quoi, int attendu, int obtenu )
{
    printf( "  %-38s attendu %#x, obtenu %#x : %s\n", quoi, attendu, obtenu,
            attendu == obtenu ? "ok" : "ECHEC" );
    if (attendu != obtenu) echecs++;
}

static DWORD WINAPI autre_fil( void *arg )
{
    printf( "fil cree :\n" );
    printf( "  &temoin                                %p\n", (void *)&temoin );
    verifier( "valeur initiale  locale au fil", 0x5A5A5A5A, temoin );
    temoin = 0x33333333;
    verifier( "apres ecriture", 0x33333333, temoin );
    memset( tampon, 0, sizeof(tampon) );   /* ce que fait la CRT du jeu */
    printf( "  memset(tampon, 0, %zu) : passe\n", sizeof(tampon) );
    return 0;
}

int main(void)
{
    HANDLE h;
    /* Le pointeur de TLS vit dans le TEB, a +0x58 sur x86-64. */
    void **teb = (void **)NtCurrentTeb();
    void *ptr_tls = *(void **)((char *)teb + 0x58);

    printf( "TEB %p, ThreadLocalStoragePointer (+0x58) = %p\n", (void *)teb, ptr_tls );
    if (!ptr_tls) { printf( "  le pointeur est NUL -- tout acces TLS lira « nul + deplacement »\n" ); echecs++; }

    printf( "fil principal :\n" );
    printf( "  &temoin                                %p\n", (void *)&temoin );
    verifier( "valeur initiale  locale au fil", 0x5A5A5A5A, temoin );
    temoin = 0x11111111;
    verifier( "apres ecriture", 0x11111111, temoin );
    memset( tampon, 0, sizeof(tampon) );
    printf( "  memset(tampon, 0, %zu) : passe\n", sizeof(tampon) );

    h = CreateThread( NULL, 0, autre_fil, NULL, 0, NULL );
    if (!h) { printf( "CreateThread : %lu\n", GetLastError() ); return 2; }
    WaitForSingleObject( h, 10000 );
    CloseHandle( h );

    verifier( "le fil principal garde sa copie", 0x11111111, temoin );

    printf( "x86-64 TLS : %s (%d echecs)\n", echecs ? "ECHEC" : "ok", echecs );
    return echecs ? 1 : 0;
}
