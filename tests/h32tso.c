/*
 * Invite i386 : le modele memoire du x86 tient-il a la traduction ?
 *
 * Le x86 est en TSO : deux ecritures faites dans l'ordre par un fil sont vues
 * dans cet ordre par les autres, et deux lectures ne se doublent pas. ARM64 ne
 * promet rien de tel ; c'est a l'emulateur de retablir l'ordre, et FEX ne peut
 * pas s'appuyer sur le bit TSO du materiel -- il passe par une bibliotheque
 * unix que notre portage ne fournit pas.
 *
 * Tout le verrouillage de Windows repose sur cet ordre. RtlWaitOnAddress
 * inscrit son entree dans une file puis relache un verrou tournant ; celui qui
 * reveille prend le verrou et lit la file. Si une ecriture se double, le
 * reveilleur voit une file vide, n'alerte personne, et le dormeur reste.
 *
 * Deux epreuves, sans poignee de main entre les fils -- le but est d'observer,
 * pas de synchroniser :
 *
 *   1. ecritures doublees : l'ecrivain pose la donnee puis le drapeau ; le
 *      lecteur lit le drapeau puis la donnee. Voir un drapeau plus avance que
 *      la donnee est interdit en TSO.
 *   2. lectures doublees : l'ecrivain avance deux compteurs ; le lecteur lit le
 *      second puis le premier. Voir le premier en retard sur le second est
 *      interdit de la meme facon.
 */
#include <windows.h>
#include <stdio.h>

#define DUREE_MS 8000

static volatile LONG donnee, drapeau;
static volatile LONG fini;
static volatile LONG doublages_ecriture, doublages_lecture;
static volatile LONG tours_lus;

static DWORD WINAPI ecrivain( void *p )
{
    LONG i = 0;

    while (!fini)
    {
        i++;
        donnee  = i;   /* d'abord la donnee */
        drapeau = i;   /* puis le drapeau : en TSO, jamais l'inverse */
    }
    return 0;
}

static DWORD WINAPI lecteur( void *p )
{
    while (!fini)
    {
        LONG f = drapeau;   /* d'abord le drapeau */
        LONG d = donnee;    /* puis la donnee : elle ne peut pas etre en retard */

        if (d < f)
        {
            if (InterlockedIncrement( &doublages_ecriture ) <= 5)
            {
                printf( "doublage : drapeau=%ld vu avec donnee=%ld (retard de %ld)\n", f, d, f - d );
                fflush( stdout );
            }
        }
        InterlockedIncrement( &tours_lus );
    }
    return 0;
}

/* Lectures doublees : meme motif, lu dans l'autre sens. */
static volatile LONG un, deux;

static DWORD WINAPI avanceur( void *p )
{
    LONG i = 0;
    while (!fini) { i++; un = i; deux = i; }
    return 0;
}

static DWORD WINAPI observateur( void *p )
{
    while (!fini)
    {
        LONG b = deux;
        LONG a = un;
        if (a < b && InterlockedIncrement( &doublages_lecture ) <= 5)
        {
            printf( "lecture doublee : deux=%ld vu avec un=%ld\n", b, a );
            fflush( stdout );
        }
    }
    return 0;
}

int main(void)
{
    HANDLE h[4];

    h[0] = CreateThread( NULL, 0, ecrivain, NULL, 0, NULL );
    h[1] = CreateThread( NULL, 0, lecteur, NULL, 0, NULL );
    h[2] = CreateThread( NULL, 0, avanceur, NULL, 0, NULL );
    h[3] = CreateThread( NULL, 0, observateur, NULL, 0, NULL );

    Sleep( DUREE_MS );
    fini = 1;
    WaitForMultipleObjects( 4, h, TRUE, 10000 );

    printf( "i386 ordre memoire : %s (%ld doublages d'ecriture, %ld de lecture, %ld observations)\n",
            (doublages_ecriture || doublages_lecture) ? "ECHEC" : "ok",
            doublages_ecriture, doublages_lecture, tours_lus );
    return (doublages_ecriture || doublages_lecture) ? 1 : 0;
}
