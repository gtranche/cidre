/*
 * Invite i386 : combien d'espace d'adressage reste-t-il vraiment ?
 *
 * DREDGE meurt en « System out of memory! » sur une demande de 13 Mio, et Wine
 * repond « out of memory for allocation ». Un jeu 32 bits doit disposer de
 * pres de deux gigaoctets ; si la fenetre de l'invite en offre beaucoup moins,
 * ou si elle est trop morcelee, la panne n'a rien a voir avec un verrou.
 *
 * On parcourt l'espace avec VirtualQuery, on fait les comptes, puis on verifie
 * par l'usage : reserver des blocs de plus en plus grands jusqu'a l'echec.
 */
#include <windows.h>
#include <stdio.h>

static const char *nom_etat( DWORD e )
{
    switch (e)
    {
    case MEM_FREE:    return "libre";
    case MEM_RESERVE: return "reserve";
    case MEM_COMMIT:  return "engage";
    }
    return "?";
}

int main(void)
{
    MEMORY_BASIC_INFORMATION mbi;
    SYSTEM_INFO si;
    char *p;
    ULONG64 total[3] = { 0, 0, 0 };
    SIZE_T plus_grand_libre = 0;
    char *ou_plus_grand = NULL;
    int n = 0;

    GetSystemInfo( &si );
    printf( "espace de l'invite : %p .. %p (%.0f Mio)\n",
            si.lpMinimumApplicationAddress, si.lpMaximumApplicationAddress,
            ((char *)si.lpMaximumApplicationAddress - (char *)si.lpMinimumApplicationAddress) / 1048576.0 );

    for (p = NULL; VirtualQuery( p, &mbi, sizeof(mbi) ); p = (char *)mbi.BaseAddress + mbi.RegionSize)
    {
        int i = mbi.State == MEM_FREE ? 0 : (mbi.State == MEM_RESERVE ? 1 : 2);

        total[i] += mbi.RegionSize;
        if (mbi.State == MEM_FREE && mbi.RegionSize > plus_grand_libre)
        {
            plus_grand_libre = mbi.RegionSize;
            ou_plus_grand = mbi.BaseAddress;
        }
        n++;
        if ((char *)mbi.BaseAddress + mbi.RegionSize < p) break;   /* debordement */
    }

    printf( "%d regions : libre %.0f Mio, reserve %.0f Mio, engage %.0f Mio\n", n,
            total[0] / 1048576.0, total[1] / 1048576.0, total[2] / 1048576.0 );
    printf( "plus grand bloc libre : %.0f Mio a %p\n", plus_grand_libre / 1048576.0, ou_plus_grand );

    /* Verification par l'usage : jusqu'ou peut-on reserver d'un coup ? */
    {
        SIZE_T taille = 1024 * 1024;
        SIZE_T maxi = 0;

        while (taille < (SIZE_T)2048 * 1024 * 1024)
        {
            void *v = VirtualAlloc( NULL, taille, MEM_RESERVE, PAGE_NOACCESS );
            if (!v) break;
            VirtualFree( v, 0, MEM_RELEASE );
            maxi = taille;
            taille += taille / 4;
        }
        printf( "plus grande reservation obtenue : %.0f Mio\n", maxi / 1048576.0 );
    }

    /* Et combien au total, par morceaux de 16 Mio ? */
    {
        static void *blocs[4096];
        int i = 0;
        ULONG64 pris = 0;

        while (i < 4096)
        {
            void *v = VirtualAlloc( NULL, 16 * 1024 * 1024, MEM_RESERVE, PAGE_NOACCESS );
            if (!v) break;
            blocs[i++] = v;
            pris += 16 * 1024 * 1024;
        }
        printf( "total reservable par blocs de 16 Mio : %.0f Mio (%d blocs)\n", pris / 1048576.0, i );
        while (i > 0) VirtualFree( blocs[--i], 0, MEM_RELEASE );
    }

    (void)nom_etat;
    return 0;
}
