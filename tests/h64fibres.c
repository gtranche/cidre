/* Fibres x64 sous FEX ARM64EC : bascules, exceptions (int3, int 2c) prises par
 * un VEH et par un SEH, recursion moderee, et etat de la pile a chaque etape.
 *   x86_64-w64-mingw32-gcc -O1 -o h64fibres.exe h64fibres.c
 * Chaque cas imprime OK ou ECHEC ; la pile de la fibre ne doit jamais descendre
 * a plus de quelques Kio de son sommet. */
#include <windows.h>
#include <stdio.h>

static void *principal, *fibres[4];
static volatile LONG pris_int3, pris_2c;
static int echecs;
static char *plus_bas[4];

static void note_pile( int i )
{
    char c, *p = &c;
    if (!plus_bas[i] || p < plus_bas[i]) plus_bas[i] = p;
}

static LONG CALLBACK veh( EXCEPTION_POINTERS *e )
{
    DWORD code = e->ExceptionRecord->ExceptionCode;
    unsigned char *pc = (unsigned char *)e->ContextRecord->Rip;
    if (code == EXCEPTION_BREAKPOINT)
    {
        InterlockedIncrement( &pris_int3 );
        /* Windows x64 : Rip pointe sur l'int3 (0xcc) */
        if (*pc == 0xcc) e->ContextRecord->Rip++;
        else printf( "  int3 : Rip %p ne pointe pas sur 0xcc (%02x), adresse %p\n",
                     pc, *pc, e->ExceptionRecord->ExceptionAddress );
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    if (code == STATUS_ASSERTION_FAILURE)
    {
        InterlockedIncrement( &pris_2c );
        /* Windows x64 : Rip pointe sur int 2c (cd 2c) */
        if (pc[0] == 0xcd && pc[1] == 0x2c) e->ContextRecord->Rip += 2;
        else printf( "  int 2c : Rip %p sur %02x %02x, adresse %p\n",
                     pc, pc[0], pc[1], e->ExceptionRecord->ExceptionAddress );
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static int __attribute__((noinline)) recurse( int n, int i )
{
    volatile char tampon[256];
    tampon[0] = (char)n;
    note_pile( i );
    if (n == 0) { __asm__ volatile( "int3" ); return tampon[0]; }
    return recurse( n - 1, i ) + tampon[0];
}

static void CALLBACK corps( void *arg )
{
    int i = (int)(INT_PTR)arg, tour;
    for (tour = 0; tour < 200; tour++)
    {
        note_pile( i );
        __asm__ volatile( "int3" );
        __asm__ volatile( "int $0x2c" );
        recurse( 20, i );
        SwitchToFiber( fibres[(i + 1) % 4] ? fibres[(i + 1) % 4] : principal );
    }
    for (;;) SwitchToFiber( principal );
}

static void verifie( const char *nom, int ok )
{
    printf( "%s : %s\n", nom, ok ? "OK" : "ECHEC" );
    if (!ok) echecs++;
}

int main( void )
{
    NT_TIB *tib = (NT_TIB *)NtCurrentTeb();
    void *base0 = tib->StackBase, *limite0 = tib->StackLimit;
    int i;

    setvbuf( stdout, NULL, _IONBF, 0 );
    AddVectoredExceptionHandler( 1, veh );
    principal = ConvertThreadToFiber( NULL );
    verifie( "ConvertThreadToFiber", principal != NULL );
    for (i = 0; i < 4; i++) fibres[i] = CreateFiber( 0, corps, (void *)(INT_PTR)i );

    for (i = 0; i < 200; i++) SwitchToFiber( fibres[0] );

    verifie( "pile du fil rendue", tib->StackBase == base0 && tib->StackLimit == limite0 );
    printf( "int3 pris %ld, int 2c pris %ld (attendu %d et %d)\n", pris_int3, pris_2c, 200 * 4 * 2, 200 * 4 );
    verifie( "exceptions prises", pris_int3 >= 200 * 4 * 2 && pris_2c >= 200 * 4 );
    for (i = 0; i < 4; i++)
    {
        void **f = fibres[i];
        char *base = f[2], *dealloc = f[4]; /* struct fiber_data de Wine : stack_base +0x10, allocation +0x20 */
        printf( "fibre %d : pile %p-%p, au plus bas %p (%#llx sous le sommet)\n", i, dealloc, base,
                plus_bas[i], (unsigned long long)(base - plus_bas[i]) );
        verifie( "profondeur de fibre bornee", plus_bas[i] && base - plus_bas[i] < 0x10000 );
    }
    printf( "h64fibres : %d echec(s)\n", echecs );
    return echecs;
}
