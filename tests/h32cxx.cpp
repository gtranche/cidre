/* Les deux fautes de DREDGE tombent sur un « ret » dont l'ESP est aberrant :
 * la pile a ete deroulee de travers. On exerce donc le deroulement lui-meme --
 * exceptions C++ a travers plusieurs cadres, avec des objets a detruire. */
#include <windows.h>
#include <stdio.h>
#include <string>

struct Trace { LONG *n; ~Trace() { InterlockedIncrement( n ); } };

static volatile LONG detruits;

static void __attribute__((noinline)) profond( int n )
{
    Trace t { (LONG *)&detruits };
    std::string s( "un peu de tas pour occuper le cadre" );
    if (n == 0) throw std::string( "au fond" );
    profond( n - 1 );
    printf( "jamais atteint %s\n", s.c_str() );
}

static DWORD WINAPI travail( void *p )
{
    int i, pris = 0;
    for (i = 0; i < 2000; i++)
    {
        try { profond( 8 ); }
        catch (const std::string &e) { pris++; }
    }
    *(int *)p = pris;
    return 0;
}

int main(void)
{
    HANDLE h[8];
    int pris[8] = { 0 }, i, total = 0;

    for (i = 0; i < 8; i++)
        if (!(h[i] = CreateThread( NULL, 0, travail, &pris[i], 0, NULL )))
        { printf( "CreateThread %d : %lu\n", i, GetLastError() ); return 1; }
    WaitForMultipleObjects( 8, h, TRUE, 60000 );
    for (i = 0; i < 8; i++) total += pris[i];
    printf( "exceptions prises = %d (attendu 16000), destructeurs = %ld\n", total, detruits );
    printf( "i386 c++ : %s\n", (total == 16000 && detruits == 16000 * 9) ? "ok" : "ECHEC" );
    return 0;
}
