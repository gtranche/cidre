/* Code auto-modifie vu par FEX (ARM64EC) : le code reecrit doit etre execute.
 *   x86_64-w64-mingw32-gcc -O1 -o h64smc.exe h64smc.c
 * Chaque cas ecrit « mov eax, N ; ret », l'execute, le reecrit avec N+1 sans
 * changer de protection, l'execute a nouveau.
 *   A : page RWX privee seule dans sa page d'hote de 16 Kio (voisines reservees) ;
 *   B : page RWX privee dont une voisine de 4 Kio, dans la meme page d'hote, est RW ;
 *   C : page RWX privee dont les voisines sont RWX (bloc de 64 Kio RWX) ;
 *   D : vue RX d'une section, reecrite par une vue RW de la meme section ;
 *   E : comme D, avec la vue RX en RWX. */
#include <windows.h>
#include <winternl.h>
#include <stdio.h>

typedef NTSTATUS (WINAPI *NtCreateSection_t)( HANDLE *, ACCESS_MASK, OBJECT_ATTRIBUTES *, LARGE_INTEGER *, ULONG, ULONG, HANDLE );
typedef NTSTATUS (WINAPI *NtMapViewOfSection_t)( HANDLE, HANDLE, void **, ULONG_PTR, SIZE_T, LARGE_INTEGER *, SIZE_T *, ULONG, ULONG, ULONG );

static int echecs;

static void ecrit( volatile unsigned char *p, int n )
{
    p[0] = 0xb8; p[1] = n & 0xff; p[2] = (n >> 8) & 0xff; p[3] = 0; p[4] = 0; p[5] = 0xc3;
}

static void cas( const char *nom, volatile unsigned char *ecr, unsigned char *exe )
{
    int (*f)(void) = (void *)exe;
    int i, r1, r2, mauvais = 0;
    for (i = 0; i < 50; i++)
    {
        ecrit( ecr, 1000 + 2 * i );
        r1 = f(); r1 = f();
        ecrit( ecr, 1001 + 2 * i );
        r2 = f();
        if (r1 != 1000 + 2 * i || r2 != 1001 + 2 * i) mauvais++;
    }
    printf( "%s : %s (%d tours perimes sur 50)\n", nom, mauvais ? "ECHEC" : "OK", mauvais );
    if (mauvais) echecs++;
}

int main( void )
{
    HMODULE ntdll = GetModuleHandleA( "ntdll" );
    NtCreateSection_t pNtCreateSection = (void *)GetProcAddress( ntdll, "NtCreateSection" );
    NtMapViewOfSection_t pNtMapViewOfSection = (void *)GetProcAddress( ntdll, "NtMapViewOfSection" );
    unsigned char *p;
    DWORD old;

    setvbuf( stdout, NULL, _IONBF, 0 );

    p = VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS );
    VirtualAlloc( p, 0x1000, MEM_COMMIT, PAGE_EXECUTE_READWRITE );
    cas( "A page RWX seule", p, p );

    p = VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS );
    VirtualAlloc( p, 0x1000, MEM_COMMIT, PAGE_EXECUTE_READWRITE );
    VirtualAlloc( p + 0x1000, 0x1000, MEM_COMMIT, PAGE_READWRITE );
    cas( "B page RWX, voisine RW", p, p );

    p = VirtualAlloc( NULL, 0x10000, MEM_COMMIT, PAGE_EXECUTE_READWRITE );
    cas( "C bloc RWX", p, p );

    {
        HANDLE s;
        LARGE_INTEGER taille = { .QuadPart = 0x10000 };
        void *rw = NULL, *rx = NULL;
        SIZE_T t = 0;
        NTSTATUS st = pNtCreateSection( &s, SECTION_ALL_ACCESS, NULL, &taille, PAGE_EXECUTE_READWRITE, SEC_COMMIT, NULL );
        if (st) { printf( "NtCreateSection %lx\n", st ); return 2; }
        st = pNtMapViewOfSection( s, GetCurrentProcess(), &rw, 0, 0, NULL, &t, 2 /* ViewUnmap */, 0, PAGE_READWRITE );
        t = 0;
        st |= pNtMapViewOfSection( s, GetCurrentProcess(), &rx, 0, 0, NULL, &t, 2, 0, PAGE_EXECUTE_READ );
        if (st) { printf( "NtMapViewOfSection %lx\n", st ); return 2; }
        cas( "D vue RX ecrite par la vue RW", rw, rx );
        VirtualProtect( (unsigned char *)rx + 0x2000, 0x1000, PAGE_EXECUTE_READWRITE, &old );
        cas( "E vue RWX ecrite par la vue RW", (unsigned char *)rw + 0x2000, (unsigned char *)rx + 0x2000 );
    }
    printf( "h64smc : %d echec(s)\n", echecs );
    return echecs;
}
