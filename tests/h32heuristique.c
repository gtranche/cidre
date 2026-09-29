/*
 * Invite i386 : que vaut l'heuristique de rebasage du pont Steam ?
 *
 * Le relais 32 -> 64 doit decider, pour chaque mot de quatre octets passe a une
 * methode, s'il s'agit d'un pointeur a rebaser ou d'un entier a laisser tel
 * quel. Sa regle :
 *
 *     si mot < 0x110000            -> entier
 *     si la page n'est pas lisible -> entier
 *     sinon                        -> pointeur, rebase
 *
 * Le risque est declare dans le code : un entier qui tombe sur une page
 * engagee est traduit a tort. Ce test le chiffre et le provoque.
 *
 * 1. Quelle part de l'espace d'adressage est lisible ? C'est la probabilite
 *    qu'un entier quelconque soit pris pour un pointeur.
 * 2. On appelle ensuite BReleaseSteamPipe -- un entier, inoffensif, et refuse
 *    proprement si le tuyau n'existe pas -- avec une valeur qui est une adresse
 *    lisible. La trace du pont dira s'il l'a rebasee.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef unsigned (__thiscall *methode0)( void * );
typedef unsigned (__thiscall *methode1)( void *, unsigned );

int main(void)
{
    void *(__cdecl *creer)( const char *, int * );
    HMODULE client;
    void *objet;
    void **table;
    unsigned tuyau;
    MEMORY_BASIC_INFORMATION mbi;
    char *p;
    ULONG64 lisible = 0, total = 0;
    unsigned regions = 0;

    /* 1. La part lisible au-dessus du seuil. */
    for (p = (char *)0x110000; VirtualQuery( p, &mbi, sizeof(mbi) ); p = (char *)mbi.BaseAddress + mbi.RegionSize)
    {
        static const DWORD lit = PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE_READ |
                                 PAGE_EXECUTE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_WRITECOPY;

        total += mbi.RegionSize;
        if (mbi.State == MEM_COMMIT && (mbi.Protect & lit) && !(mbi.Protect & PAGE_GUARD))
            lisible += mbi.RegionSize;
        regions++;
        if ((char *)mbi.BaseAddress + mbi.RegionSize <= p) break;
        if (regions > 100000) break;
    }
    printf( "espace au-dessus de 0x110000 : %.0f Mio, dont %.0f Mio lisibles (%.3f %%)\n",
            total / 1048576.0, lisible / 1048576.0, total ? 100.0 * lisible / total : 0.0 );
    printf( "%u regions\n", regions );
    fflush( stdout );

    /*
     * Le chiffre ci-dessus vaut pour ce test, qui n'occupe presque rien. Un jeu
     * en occupe des centaines de mega-octets -- DREDGE en tient 723 -- et
     * chaque page engagee agrandit d'autant la cible. On refait donc la mesure
     * apres avoir engage de quoi ressembler a un jeu.
     */
    {
        SIZE_T voulu = 700u * 1024 * 1024, pris = 0;
        void *blocs[64];
        unsigned n = 0;

        while (n < 64 && pris < voulu)
        {
            void *v = VirtualAlloc( NULL, 16 * 1024 * 1024, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
            if (!v) break;
            memset( v, 0, 4096 );       /* toucher, pour que ce soit vraiment engage */
            blocs[n++] = v;
            pris += 16 * 1024 * 1024;
        }

        lisible = total = regions = 0;
        for (p = (char *)0x110000; VirtualQuery( p, &mbi, sizeof(mbi) ); p = (char *)mbi.BaseAddress + mbi.RegionSize)
        {
            static const DWORD lit = PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE_READ |
                                     PAGE_EXECUTE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_WRITECOPY;
            total += mbi.RegionSize;
            if (mbi.State == MEM_COMMIT && (mbi.Protect & lit) && !(mbi.Protect & PAGE_GUARD))
                lisible += mbi.RegionSize;
            if (++regions > 100000 || (char *)mbi.BaseAddress + mbi.RegionSize <= p) break;
        }
        printf( "avec %.0f Mio engages : %.0f Mio lisibles sur %.0f (%.2f %%)\n",
                pris / 1048576.0, lisible / 1048576.0, total / 1048576.0,
                total ? 100.0 * lisible / total : 0.0 );
        fflush( stdout );
        while (n > 0) VirtualFree( blocs[--n], 0, MEM_RELEASE );
    }

    /* 2. La meprise, sur un appel inoffensif. */
    if (!(client = LoadLibraryA( "steamclient.dll" ))) { printf( "pas de steamclient\n" ); return 2; }
    if (!(creer = (void *)GetProcAddress( client, "CreateInterface" ))) return 2;
    if (!(objet = creer( "SteamClient017", NULL ))) { printf( "pas d'interface\n" ); return 1; }
    table = *(void ***)objet;

    tuyau = ((methode0)table[0])( objet );
    printf( "tuyau = %u\n", tuyau ); fflush( stdout );

    /*
     * Deux valeurs de « tuyau » qui n'existent pas, donc deux refus attendus.
     * Seule difference : la premiere est une adresse lisible -- la base de
     * l'image du programme -- la seconde ne l'est pas. Si l'heuristique est en
     * cause, le pont ne traitera pas les deux de la meme facon, et sa trace le
     * dira : « mot ... pris pour un pointeur ».
     */
    {
        unsigned faux_lisible = 0x00400000;   /* base de l'image, engagee */
        unsigned faux_absent  = 0x7F000000;   /* rien a cette adresse */

        printf( "IsBadReadPtr(%08x) = %d\n", faux_lisible, IsBadReadPtr( (void *)(ULONG_PTR)faux_lisible, 1 ) );
        printf( "IsBadReadPtr(%08x) = %d\n", faux_absent,  IsBadReadPtr( (void *)(ULONG_PTR)faux_absent, 1 ) );
        fflush( stdout );

        printf( "BReleaseSteamPipe(%08x) -> %u   (adresse lisible)\n",
                faux_lisible, ((methode1)table[1])( objet, faux_lisible ) );
        fflush( stdout );
        printf( "BReleaseSteamPipe(%08x) -> %u   (adresse absente)\n",
                faux_absent, ((methode1)table[1])( objet, faux_absent ) );
        fflush( stdout );
    }

    ((methode1)table[1])( objet, tuyau );
    printf( "i386 heuristique de rebasage : mesure faite\n" );
    return 0;
}
