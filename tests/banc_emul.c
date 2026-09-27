/* Banc minimal pour chiffrer la taxe d'emulation : meme source compilee en
 * x86_64 (emule par FEX) et en arm64 (native), lancee par le meme Wine arm64.
 * Le temps est mesure dans le programme, donc sans le cout de demarrage. */
#include <stdio.h>
#include <stdint.h>
#include <windows.h>

static uint64_t melanger( uint64_t x )
{
    x ^= x >> 33; x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL;
    return x ^ (x >> 33);
}

int main( int argc, char **argv )
{
    unsigned tours = argc > 1 ? (unsigned)atoi( argv[1] ) : 20000000;
    LARGE_INTEGER f, a, b;
    uint64_t h = 1;
    unsigned i;

    QueryPerformanceFrequency( &f );
    QueryPerformanceCounter( &a );
    for (i = 0; i < tours; i++) h = melanger( h + i );
    QueryPerformanceCounter( &b );
    printf( "%u tours en %.1f ms, h=%llx\n", tours,
            (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart, (unsigned long long)h );
    return 0;
}
