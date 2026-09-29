/*
 * Invite x86-64 : les rappels TLS de l'image sont-ils appeles ?
 *
 * Vermintide 2 porte un repertoire TLS avec des rappels (AddressOfCallBacks
 * non nul). Un rappel TLS sert justement a construire ce qu'un fil possede en
 * propre. S'il n'est pas appele, l'objet reste nul, et la premiere methode qui
 * ecrit dedans fait « memset(nul + deplacement) » -- la forme exacte de la
 * faute du jeu. Le §precedent a montre que le stockage par fil fonctionne ;
 * restait a verifier qui l'initialise.
 */
#include <windows.h>
#include <stdio.h>

static volatile LONG rappels_attache, rappels_fil_attache, rappels_fil_detache;

static void NTAPI rappel_tls( PVOID module, DWORD raison, PVOID reserve )
{
    switch (raison)
    {
    case DLL_PROCESS_ATTACH: InterlockedIncrement( &rappels_attache ); break;
    case DLL_THREAD_ATTACH:  InterlockedIncrement( &rappels_fil_attache ); break;
    case DLL_THREAD_DETACH:  InterlockedIncrement( &rappels_fil_detache ); break;
    }
}

/* L'enregistrement : un pointeur dans .CRT$XLB, et une reference a _tls_used
 * pour que l'editeur de liens emette le repertoire TLS. */
extern const IMAGE_TLS_DIRECTORY64 _tls_used;
__attribute__((section(".CRT$XLB"), used))
PIMAGE_TLS_CALLBACK table_rappels = rappel_tls;

__thread int par_fil = 0x1234;

static DWORD WINAPI autre_fil( void *arg )
{
    printf( "  dans le fil cree : par_fil = %#x\n", par_fil );
    return 0;
}

int main(void)
{
    HANDLE h;
    const IMAGE_TLS_DIRECTORY64 *rep = &_tls_used;

    printf( "repertoire TLS a %p, AddressOfCallBacks = %#llx\n",
            (const void *)rep, (unsigned long long)rep->AddressOfCallBacks );
    if (rep->AddressOfCallBacks)
    {
        PIMAGE_TLS_CALLBACK *t = (PIMAGE_TLS_CALLBACK *)(ULONG_PTR)rep->AddressOfCallBacks;
        printf( "  premier rappel enregistre : %p (le notre est %p)\n", (void *)t[0], (void *)rappel_tls );
    }

    printf( "au demarrage : PROCESS_ATTACH vu %ld fois, THREAD_ATTACH %ld\n",
            rappels_attache, rappels_fil_attache );

    h = CreateThread( NULL, 0, autre_fil, NULL, 0, NULL );
    WaitForSingleObject( h, 10000 );
    CloseHandle( h );
    Sleep( 200 );

    printf( "apres un fil : THREAD_ATTACH %ld, THREAD_DETACH %ld\n",
            rappels_fil_attache, rappels_fil_detache );

    {
        int mauvais = (rappels_attache != 1) + (rappels_fil_attache < 1);
        printf( "x86-64 rappels TLS : %s\n", mauvais ? "ECHEC" : "ok" );
        return mauvais ? 1 : 0;
    }
}
