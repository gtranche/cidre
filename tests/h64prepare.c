/* Flot de controle par exceptions, a la maniere du chargeur protege de D2R :
 * un crochet pose dans ntdll!Wow64PrepareForException (pointeur trouve en
 * lisant le KiUserExceptionDispatcher x64 : cld ; mov rax,[rip+d]) recoit les
 * fautes d'execution d'un « call » vers une adresse non projetee et redirige le
 * fil par NtContinue vers l'adresse de retour.
 *   x86_64-w64-mingw32-gcc -O1 -o h64prepare.exe h64prepare.c */
#include <windows.h>
#include <stdio.h>

typedef NTSTATUS (WINAPI *NtContinue_t)( CONTEXT *, BOOLEAN );
static NtContinue_t pNtContinue;
static ULONG_PTR cible;                 /* adresse non projetee */
static volatile LONG vus, profondeur_max, profondeur;
static ULONG_PTR rip_vu, rsp_vu, ret_vu, info0_vu, info1_vu, adr_vu;
static int echecs;

static int __attribute__((noinline)) appel_invalide( int n )
{
    int r;
    __asm__ volatile( "call *%1\n\tmov $7, %0" : "=r"(r) : "r"(cible) : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "memory" );
    return r + n;
}

static void WINAPI crochet( EXCEPTION_RECORD *rec, CONTEXT *ctx )
{
    LONG p;
    if (rec->ExceptionCode != STATUS_ACCESS_VIOLATION || rec->ExceptionInformation[1] != cible) return;
    InterlockedIncrement( &vus );
    p = InterlockedIncrement( &profondeur );
    if (p > profondeur_max) profondeur_max = p;
    rip_vu = ctx->Rip; rsp_vu = ctx->Rsp; ret_vu = *(ULONG_PTR *)ctx->Rsp;
    info0_vu = rec->ExceptionInformation[0]; info1_vu = rec->ExceptionInformation[1];
    adr_vu = (ULONG_PTR)rec->ExceptionAddress;
    /* une faute imbriquee dans le crochet, comme le fait la protection */
    if (p == 1) appel_invalide( 0 );
    InterlockedDecrement( &profondeur );
    if (profondeur > 50) ExitProcess( 99 );
    ctx->Rip = *(ULONG_PTR *)ctx->Rsp;   /* retour du call */
    ctx->Rsp += 8;
    pNtContinue( ctx, FALSE );
}

static void verifie( const char *nom, int ok )
{
    printf( "%s : %s\n", nom, ok ? "OK" : "ECHEC" );
    if (!ok) echecs++;
}

int main( void )
{
    HMODULE ntdll = GetModuleHandleA( "ntdll" );
    unsigned char *k = (unsigned char *)GetProcAddress( ntdll, "KiUserExceptionDispatcher" );
    void **pp;
    DWORD old;
    int i, r;

    setvbuf( stdout, NULL, _IONBF, 0 );
    pNtContinue = (NtContinue_t)GetProcAddress( ntdll, "NtContinue" );
    printf( "KiUserExceptionDispatcher %p : %02x %02x %02x %02x\n", k, k[0], k[1], k[2], k[3] );
    if (k[0] != 0xfc || k[1] != 0x48 || k[2] != 0x8b || k[3] != 0x05) { printf( "motif absent\n" ); return 2; }
    pp = (void **)(k + 8 + *(INT32 *)(k + 4));
    printf( "Wow64PrepareForException en %p = %p\n", pp, *pp );
    cible = (ULONG_PTR)VirtualAlloc( NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS );
    VirtualFree( (void *)cible, 0, MEM_RELEASE );
    cible += 0x794;
    if (getenv( "CIBLE_DLL" ))
    {
        /* adresse dans une DLL ARM64EC dechargee : ses bits EC sont-ils effaces ? */
        HMODULE m = LoadLibraryA( getenv( "CIBLE_DLL" ) );
        IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((char *)m + ((IMAGE_DOS_HEADER *)m)->e_lfanew);
        cible = (ULONG_PTR)m + nt->OptionalHeader.BaseOfCode + 0x794;
        printf( "%s en %p, FreeLibrary %d\n", getenv( "CIBLE_DLL" ), m, FreeLibrary( m ) );
    }
    {
        BOOLEAN (WINAPI *ec)(ULONG_PTR) = (void *)GetProcAddress( ntdll, "RtlIsEcCode" );
        MEMORY_BASIC_INFORMATION mbi;
        VirtualQuery( (void *)cible, &mbi, sizeof(mbi) );
        printf( "cible %p : etat %#lx, RtlIsEcCode %d\n", (void *)cible, mbi.State, ec ? ec( cible ) : -1 );
    }
    if (!VirtualProtect( pp, sizeof(*pp), PAGE_READWRITE, &old )) printf( "VirtualProtect %lu\n", GetLastError() );
    *pp = crochet;

    for (i = 0; i < 100; i++) r = appel_invalide( 1 );
    *pp = NULL;
    printf( "vus %ld, profondeur max %ld, r %d\n", vus, profondeur_max, r );
    printf( "derniere faute : adresse %p info %lx %p, Rip %p Rsp %p [Rsp] %p\n", (void *)adr_vu, info0_vu,
            (void *)info1_vu, (void *)rip_vu, (void *)rsp_vu, (void *)ret_vu );
    verifie( "crochet appele (2 par tour)", vus == 200 );
    verifie( "profondeur 2", profondeur_max == 2 );
    verifie( "retour du call", r == 8 );
    verifie( "faute d'execution sur la cible", info0_vu == 8 && info1_vu == cible && adr_vu == cible && rip_vu == cible );
    printf( "h64prepare : %d echec(s)\n", echecs );
    return echecs;
}
