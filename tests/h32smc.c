/*
 * Invite i386 : du verrouillage pendant que le code se reecrit.
 *
 * Les epreuves de h32futex passent a vide. Ce que DREDGE a en plus, c'est Mono,
 * qui rustine son propre code sans arret : chaque ecriture dans une page
 * executable fait invalider les traductions de FEX, ce qui suspend des fils,
 * vide les piles d'appels et change de tampon de code. Le reveil perdu se
 * produit peut-etre la, et pas dans le futex tout seul.
 *
 * On reunit donc les deux : huit fils qui se disputent verrous et variables de
 * condition, deux fils qui reecrivent du code et l'appellent en boucle. Le
 * chien de garde arrete tout si le compteur cesse d'avancer.
 */
#include <windows.h>
#include <stdio.h>

#define FILS   8
#define TOURS  200000

static CRITICAL_SECTION section;
static SRWLOCK srw;
static CONDITION_VARIABLE cv;
static CRITICAL_SECTION cv_section;
static volatile LONG cv_pret;
static volatile LONG compteur;
static volatile LONG fini;
static volatile LONG partage;      /* protege par la section critique */
static volatile LONG partage_srw;  /* protege par le verrou SRW : deux verrous
                                    * differents ne se protegent pas l'un
                                    * l'autre, il faut donc deux compteurs. */
static const char *epreuve = "verrous pendant la reecriture du code";

static DWORD WINAPI chien_de_garde( void *p )
{
    LONG vu = -1;
    int immobile = 0;

    while (!fini)
    {
        LONG maintenant = compteur;
        if (maintenant == vu)
        {
            if (++immobile >= 10)
            {
                printf( "BLOQUE pendant \"%s\" : le compteur reste a %ld\n", epreuve, maintenant );
                fflush( stdout );
                ExitProcess( 1 );
            }
        }
        else { immobile = 0; vu = maintenant; }
        Sleep( 1000 );
    }
    return 0;
}

/* --- du code que l'on reecrit sous les pieds de l'emulateur -------------- */

typedef int (__cdecl *fonction)( int );

static unsigned char *fabrique;

/* « mov eax, [esp+4] ; add eax, N ; ret » : N change a chaque reecriture. */
static void ecrire_corps( unsigned char *p, int n )
{
    p[0] = 0x8b; p[1] = 0x44; p[2] = 0x24; p[3] = 0x04;   /* mov eax,[esp+4] */
    p[4] = 0x05;                                           /* add eax, imm32  */
    p[5] = (unsigned char)(n      );
    p[6] = (unsigned char)(n >>  8);
    p[7] = (unsigned char)(n >> 16);
    p[8] = (unsigned char)(n >> 24);
    p[9] = 0xc3;                                           /* ret             */
}

#define CORPS 16
#define CORPS_N 64

static DWORD WINAPI rustineur( void *p )
{
    LONG i = 0;

    while (!fini)
    {
        int k = (int)(++i % CORPS_N);
        unsigned char *c = fabrique + k * CORPS;

        ecrire_corps( c, k );
        FlushInstructionCache( GetCurrentProcess(), c, CORPS );
        if (((fonction)c)( 1 ) != k + 1)
        {
            printf( "la rustine ne prend pas : corps %d\n", k );
            fflush( stdout );
            fini = 1;
            return 1;
        }
        InterlockedIncrement( &compteur );
    }
    return 0;
}

/* --- les disputeurs ------------------------------------------------------ */

static DWORD WINAPI disputeur( void *p )
{
    LONG i;

    for (i = 0; i < TOURS; i++)
    {
        EnterCriticalSection( &section );
        partage++;
        LeaveCriticalSection( &section );

        AcquireSRWLockExclusive( &srw );
        partage_srw++;
        ReleaseSRWLockExclusive( &srw );

        EnterCriticalSection( &cv_section );
        cv_pret = 1;
        WakeAllConditionVariable( &cv );
        LeaveCriticalSection( &cv_section );

        InterlockedIncrement( &compteur );
    }
    return 0;
}

static DWORD WINAPI dormeur( void *p )
{
    while (!fini)
    {
        EnterCriticalSection( &cv_section );
        while (!cv_pret && !fini)
            SleepConditionVariableCS( &cv, &cv_section, 2000 );
        cv_pret = 0;
        LeaveCriticalSection( &cv_section );
        InterlockedIncrement( &compteur );
    }
    return 0;
}

int main(void)
{
    HANDLE h[FILS + 4], garde;
    int i, n = 0;

    fabrique = VirtualAlloc( NULL, CORPS * CORPS_N, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE );
    if (!fabrique) { printf( "VirtualAlloc : %lu\n", GetLastError() ); return 2; }

    InitializeCriticalSection( &section );
    InitializeCriticalSection( &cv_section );
    InitializeConditionVariable( &cv );
    InitializeSRWLock( &srw );
    garde = CreateThread( NULL, 0, chien_de_garde, NULL, 0, NULL );

    h[n++] = CreateThread( NULL, 0, rustineur, NULL, 0, NULL );
    h[n++] = CreateThread( NULL, 0, rustineur, NULL, 0, NULL );
    h[n++] = CreateThread( NULL, 0, dormeur, NULL, 0, NULL );
    for (i = 0; i < FILS; i++) h[n++] = CreateThread( NULL, 0, disputeur, NULL, 0, NULL );

    for (i = 3; i < n; i++) WaitForSingleObject( h[i], INFINITE );
    fini = 1;
    for (i = 0; i < 3; i++) WaitForSingleObject( h[i], 5000 );
    WaitForSingleObject( garde, 2000 );

    {
        LONG attendu = (LONG)FILS * TOURS;
        int bon = (partage == attendu && partage_srw == attendu);

        printf( "i386 verrous sous reecriture : %s (%ld tours ; section=%ld, SRW=%ld, attendu %ld)\n",
                bon ? "ok" : "ECART", compteur, partage, partage_srw, attendu );
        return bon ? 0 : 1;
    }
}
