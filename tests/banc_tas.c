/*
 * banc_tas : cout de HeapAlloc/HeapFree vu d'un invite (LFH de Wine).
 * Motif qui fait liberer puis reallouer des groupes de blocs LFH : chaque fil
 * alloue une rafale de blocs de la meme taille, puis les libere tous, en boucle.
 * Plus un motif « regime » (alloue/libere un bloc a la fois) pour temoin.
 * Arguments : fils (4), rafale (2000), tours (300).
 *   x86_64-w64-mingw32-clang -O2 -o banc_tas.exe banc_tas.c
 * Imprime aussi ~MHz du registre et la cadence mesuree de rdtsc (0178).
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <intrin.h>

static int FILS = 4, RAFALE = 2000, TOURS = 300;
static HANDLE tas;
static const SIZE_T tailles[] = { 24, 48, 96, 200, 400, 1000 };

static DWORD WINAPI rafales( void *arg )
{
    void **p = malloc( RAFALE * sizeof(*p) );
    int t, i, k = (int)(INT_PTR)arg;
    for (t = 0; t < TOURS; t++)
    {
        SIZE_T sz = tailles[(t + k) % 6];
        for (i = 0; i < RAFALE; i++) p[i] = HeapAlloc( tas, 0, sz );
        for (i = 0; i < RAFALE; i++) HeapFree( tas, 0, p[i] );
    }
    free( p );
    return 0;
}

static DWORD WINAPI regime( void *arg )
{
    int i, k = (int)(INT_PTR)arg;
    for (i = 0; i < RAFALE * TOURS; i++) HeapFree( tas, 0, HeapAlloc( tas, 0, tailles[(i + k) % 6] ) );
    return 0;
}

static double banc( const char *nom, LPTHREAD_START_ROUTINE f )
{
    HANDLE h[64]; LARGE_INTEGER fr, t0, t1; int i;
    QueryPerformanceFrequency( &fr ); QueryPerformanceCounter( &t0 );
    for (i = 0; i < FILS; i++) h[i] = CreateThread( NULL, 0, f, (void *)(INT_PTR)i, 0, NULL );
    WaitForMultipleObjects( FILS, h, TRUE, INFINITE );
    QueryPerformanceCounter( &t1 );
    for (i = 0; i < FILS; i++) CloseHandle( h[i] );
    double ns = (double)(t1.QuadPart - t0.QuadPart) * 1e9 / fr.QuadPart / ((double)RAFALE * TOURS * FILS);
    printf( "%-26s %d fils : %7.1f ns par alloc+free\n", nom, FILS, ns );
    return ns;
}

int main( int argc, char **argv )
{
    HKEY k; DWORD mhz = 0, sz = sizeof(mhz); ULONG v = 2;
    LARGE_INTEGER fr, q0, q1; unsigned __int64 r0, r1;
    if (argc > 1) FILS = atoi( argv[1] );
    if (argc > 2) RAFALE = atoi( argv[2] );
    if (argc > 3) TOURS = atoi( argv[3] );
    if (!RegOpenKeyExA( HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_READ, &k ))
    {
        RegQueryValueExA( k, "~MHz", NULL, NULL, (BYTE *)&mhz, &sz );
        RegCloseKey( k );
    }
    QueryPerformanceFrequency( &fr );
    QueryPerformanceCounter( &q0 ); r0 = __rdtsc(); Sleep( 500 ); r1 = __rdtsc(); QueryPerformanceCounter( &q1 );
    printf( "~MHz %lu, rdtsc mesure %.0f MHz\n", mhz,
            (double)(r1 - r0) / ((double)(q1.QuadPart - q0.QuadPart) / fr.QuadPart) / 1e6 );
    tas = GetProcessHeap();
    HeapSetInformation( tas, HeapCompatibilityInformation, &v, sizeof(v) );
    banc( "rafales (groupes liberes)", rafales );
    banc( "regime (1 bloc)", regime );
    return 0;
}
