/*
 * Est-ce qu'une page reservee en PAGE_NOACCESS garde vraiment ?
 *
 * FEX encadre sa pile d'appels de deux pages de garde reservees sans acces, et
 * compte sur la faute pour rattraper un desequilibre. Si l'ecriture passe sans
 * lever, la garde ne garde rien et le pointeur sort de ses bornes en silence.
 *
 * On reserve trois pages, on engage celle du milieu, puis on ecrit dans la page
 * basse et sous la reservation. Un gestionnaire vectorise compte les fautes et
 * engage la page pour pouvoir continuer.
 */
#include <windows.h>
#include <stdio.h>

static volatile LONG fautes;
static volatile ULONG_PTR derniere;

static LONG CALLBACK gestionnaire( EXCEPTION_POINTERS *p )
{
    EXCEPTION_RECORD *r = p->ExceptionRecord;

    void *p4k;

    if (r->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement( &fautes );
    derniere = r->ExceptionInformation[1];
    p4k = (void *)(r->ExceptionInformation[1] & ~(ULONG_PTR)0xffff);
    /* Rendre la page utilisable pour que l'instruction fautive puisse reprendre.
     * Si elle est libre il faut d'abord la reserver, sinon on tourne en rond. */
    if (!VirtualAlloc( p4k, 0x10000, MEM_COMMIT, PAGE_READWRITE ))
        VirtualAlloc( p4k, 0x10000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    if (fautes > 20) return EXCEPTION_CONTINUE_SEARCH;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static void essai( const char *quoi, volatile char *ou )
{
    LONG avant = fautes;

    *ou = 0x42;
    printf( "%-28s %p : %s", quoi, (void *)ou,
            fautes > avant ? "faute levee" : "ECRITURE PASSEE SANS FAUTE" );
    if (fautes > avant) printf( " (adresse %p)", (void *)derniere );
    printf( "\n" );
    fflush( stdout );
}

static void serie( const char *titre, SIZE_T garde )
{
    SIZE_T milieu = 0x10000;
    char *base;
    MEMORY_BASIC_INFORMATION mbi;

    printf( "\n=== gardes de %llx octets : %s ===\n", (unsigned long long)garde, titre );
    base = VirtualAlloc( NULL, milieu + 2 * garde, MEM_RESERVE | MEM_TOP_DOWN, PAGE_NOACCESS );
    if (!base) { printf( "reservation : %lu\n", GetLastError() ); return; }
    if (!VirtualAlloc( base + garde, milieu, MEM_COMMIT, PAGE_READWRITE ))
    { printf( "engagement : %lu\n", GetLastError() ); return; }
    printf( "reservation %p, milieu engage %p\n", base, base + garde );

    VirtualQuery( base, &mbi, sizeof(mbi) );
    printf( "garde basse : base %p taille %llx etat %lx prot %lx\n", mbi.BaseAddress,
            (unsigned long long)mbi.RegionSize, mbi.State, mbi.Protect );

    essai( "milieu engage", base + garde );
    essai( "garde basse", base + garde - 0x10 );
    essai( "garde haute", base + garde + milieu + 0x10 );
}

/*
 * L'autre facon de poser une garde : engager toute la zone, puis retirer
 * l'acces a la derniere page. FEX s'en sert pour detecter le debordement d'un
 * tampon de code (PooledAllocatorVirtualWithGuard). Meme question : une demande
 * de 4 Kio sur une machine a pages de 16 Kio protege-t-elle trop, trop peu, ou
 * juste ce qu'il faut ?
 */
static void serie_protect( SIZE_T page )
{
    SIZE_T taille = 0x40000;
    char *base;
    DWORD vieux = 0;
    MEMORY_BASIC_INFORMATION mbi;

    printf( "\n=== VirtualProtect sur les %llx derniers octets ===\n", (unsigned long long)page );
    base = VirtualAlloc( NULL, taille, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    if (!base) { printf( "allocation : %lu\n", GetLastError() ); return; }
    if (!VirtualProtect( base + taille - page, page, PAGE_NOACCESS, &vieux ))
    { printf( "VirtualProtect : %lu\n", GetLastError() ); return; }
    printf( "zone %p..%p, derniere page %p sans acces\n", base, base + taille, base + taille - page );

    VirtualQuery( base + taille - page, &mbi, sizeof(mbi) );
    printf( "vue de Wine : base %p taille %llx prot %lx\n", mbi.BaseAddress,
            (unsigned long long)mbi.RegionSize, mbi.Protect );

    essai( "utile, 5 pages avant", base + taille - page - 5 * 0x1000 );
    essai( "utile, juste avant", base + taille - page - 0x10 );
    essai( "la garde", base + taille - 0x10 );
}

int main(void)
{
    AddVectoredExceptionHandler( 1, gestionnaire );

    /*
     * La premiere serie doit montrer les deux gardes qui laissent passer : une
     * garde plus petite que la page de l'hote partage sa page materielle avec
     * le milieu engage. La seconde doit lever les deux fois.
     */
    serie( "plus petite que la page de l'hote", 0x1000 );
    serie( "granularite d'allocation de Windows", 0x10000 );
    serie_protect( 0x1000 );
    serie_protect( 0x10000 );

    printf( "\ntotal fautes : %ld (attendu : 3)\n", fautes );
    return fautes == 3 ? 0 : 1;
}
