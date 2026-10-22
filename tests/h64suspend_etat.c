/* Temoin de l'etat repris apres une suspension (FEX : la suspension est prise a la sonnette des entrees de bloc, des
 * retours d'appel (sauf 0224) et des aretes arriere (0194), puis l'etat de l'invite est reconstruit depuis les
 * registres de l'hote). Un fil enchaine des calculs deterministes dont chaque etape depend de la precedente :
 * retenue en chaine (adc/sbb, jb/jae), x87 (long double), SSE scalaire et compare (ucomisd, ja/jb), appels et retours
 * dans les boucles. Le fil principal le suspend sans arret ; selon le mode, il lit seulement son contexte, ou le lit
 * puis le reecrit a l'identique (SetThreadContext, comme une protection logicielle ou un debogueur).
 *
 *   E0  reference : 200 tours du calcul sans suspension, dans un fil cree comme celui de l'essai
 *   E1  les memes tours sous suspensions (GetThreadContext seul) : tours differents de la reference
 *   E2  idem avec SetThreadContext du contexte lu : tours differents
 *   E3  SetThreadContext qui change vraiment l'etat x87 (ST0 1.0 -> 2.0, mot de controle 0x27f -> 0x37f) : le fil
 *       repris doit voir les registres poses ; le mot de controle pose est perdu par Wine (rapporte), mais celui du
 *       fil doit rester valide (0 = l'etat « inconnu » de Wine pris tel quel)
 *
 * x86_64-w64-mingw32-clang -O1 h64suspend_etat.c -o h64suspend_etat.exe ; lancement : wine h64suspend_etat.exe */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

#define TOURS 200
static uint64_t reference[TOURS], obtenu[TOURS];
static uint64_t ref_parts[TOURS][3], obt_parts[TOURS][3];
static uint64_t (*parts)[3];
static volatile LONG fin, en_cours;

static uint64_t __attribute__((noinline)) retenue( uint64_t a, uint64_t b, unsigned n )
{
    uint64_t s = 0;
    for (unsigned i = 0; i < n; i++)
    {
        unsigned long long r;
        unsigned char c = __builtin_add_overflow( a, b, &r ); /* add + setc / adc */
        a = r ^ (b << 7); b += c ? 0x9e3779b97f4a7c15ULL : 3;
        if (a < b) s += 1; else s ^= a;                       /* cmp + jb/jae */
    }
    return s ^ a ^ b;
}

static long double __attribute__((noinline)) x87( long double x, unsigned n )
{
    for (unsigned i = 1; i <= n; i++) x = x * 1.0000003L + 1.0L / (i + x);
    return x;
}

static double __attribute__((noinline)) sse( double x, unsigned n )
{
    double s = 0;
    for (unsigned i = 1; i <= n; i++)
    {
        x = x * 1.0000001 + 0.5 / i;
        if (x > s) s += x * 0.25; else s -= 0.5;              /* ucomisd + ja/jb */
    }
    return s + x;
}

static uint64_t tour( unsigned k )
{
    uint64_t h = retenue( k * 2654435761u, k + 17, 2000 );
    long double l = x87( (long double)k + 0.5L, 1500 );
    double d = sse( k * 0.125, 1500 );
    uint64_t bl, bd;
    memcpy( &bl, &l, 8 ); memcpy( &bd, &d, 8 );
    parts[k][0] = h; parts[k][1] = bl; parts[k][2] = bd;
    return h ^ (bl * 31) ^ (bd * 131);
}

static DWORD WINAPI calcul( void *p )
{
    parts = obt_parts;
    while (!fin)
    {
        for (unsigned k = 0; k < TOURS; k++) obtenu[k] = tour( k );
        InterlockedIncrement( &en_cours );
    }
    return 0;
}

static int essai( const char *nom, BOOL ecrire, BOOL suspendre )
{
    int ecarts = 0, suspensions = 0;
    fin = 0; en_cours = 0;
    HANDLE h = CreateThread( NULL, 0, calcul, NULL, 0, NULL );
    DWORD t0 = GetTickCount();
    while (GetTickCount() - t0 < 8000)
    {
        CONTEXT c = { .ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT };
        if (!suspendre) { Sleep( 10 ); continue; }
        if (SuspendThread( h ) == (DWORD)-1) break;
        if (GetThreadContext( h, &c ) && ecrire) SetThreadContext( h, &c );
        ResumeThread( h );
        suspensions++;
        Sleep( 0 );
    }
    fin = 1;
    WaitForSingleObject( h, INFINITE );
    CloseHandle( h );
    int ep[3] = { 0, 0, 0 };
    for (unsigned k = 0; k < TOURS; k++)
    {
        ecarts += obtenu[k] != reference[k];
        for (int j = 0; j < 3; j++) ep[j] += obt_parts[k][j] != ref_parts[k][j];
    }
    printf( "      parties differentes : retenue %d, x87 %d, sse %d\n", ep[0], ep[1], ep[2] );
    printf( "%s %s : %d suspensions, %ld passages, %d tour(s) sur %d differents de la reference\n", ecarts ? "ECHEC" : "OK   ",
            nom, suspensions, en_cours, ecarts, TOURS );
    return ecarts != 0;
}

/* E3 : un fil garde 1.0 en ST0 et relit sans cesse son mot de controle et ST0 (sans les depiler). */
static volatile unsigned short cw_vu;
static volatile double st0_vu;
static volatile LONG e3_fin;
static DWORD WINAPI x87_garde( void *p )
{
    unsigned short cw;
    double v;
    __asm__ volatile( "fld1" );
    while (!e3_fin)
    {
        __asm__ volatile( "fnstcw %0\n\tfstl %1" : "=m"(cw), "=m"(v) );
        cw_vu = cw; st0_vu = v;
    }
    __asm__ volatile( "fstp %%st(0)" ::: "st" );
    return 0;
}

static int essai_e3( void )
{
    HANDLE h = CreateThread( NULL, 0, x87_garde, NULL, 0, NULL );
    Sleep( 200 );
    unsigned short avant = cw_vu; double v_avant = st0_vu;
    CONTEXT c = { .ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT };
    SuspendThread( h );
    GetThreadContext( h, &c );
    c.FltSave.ControlWord = 0x37f;
    /* ST0 = 2.0 en 80 bits : mantisse 0x8000000000000000, exposant 0x4000 */
    unsigned char deux[10] = { 0, 0, 0, 0, 0, 0, 0, 0x80, 0x00, 0x40 };
    memcpy( &c.FltSave.FloatRegisters[0], deux, 10 );
    SetThreadContext( h, &c );
    ResumeThread( h );
    Sleep( 200 );
    unsigned short apres = cw_vu; double v_apres = st0_vu;
    e3_fin = 1;
    WaitForSingleObject( h, INFINITE );
    CloseHandle( h );
    /* Les registres poses gagnent (ST0 = 2). Le mot de controle pose est perdu par Wine (le contexte ARM64 n'a pas de
     * place pour lui) : on le rapporte seulement ; il doit au moins rester valide (pas 0). */
    int ok = v_apres == 2.0 && apres != 0;
    printf( "%s E3 SetThreadContext x87 modifie : ST0 %g -> %g (attendu 2) ; mot de controle %#x -> %#x (0x37f pose, perdu par "
            "Wine ; 0 = defaut)\n", ok ? "OK   " : "ECHEC", v_avant, v_apres, avant, apres );
    return !ok;
}

/* La reference est calculee par un fil cree comme celui du calcul : le fil principal n'a pas forcement le meme mot
 * de controle x87 (precision), ce qui changerait les long double des le depart. */
static DWORD WINAPI calcul_reference( void *p )
{
    parts = ref_parts;
    for (unsigned k = 0; k < TOURS; k++) reference[k] = tour( k );
    return 0;
}

int main( void )
{
    int echecs = 0;
    HANDLE r = CreateThread( NULL, 0, calcul_reference, NULL, 0, NULL );
    WaitForSingleObject( r, INFINITE );
    CloseHandle( r );
    printf( "OK    E0 reference : %d tours\n", TOURS );
    echecs += essai( "E0b meme fil, sans suspension", FALSE, FALSE );
    echecs += essai( "E1 GetThreadContext seul", FALSE, TRUE );
    echecs += essai( "E2 GetThreadContext + SetThreadContext", TRUE, TRUE );
    echecs += essai_e3();
    printf( "%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs );
    return echecs;
}
