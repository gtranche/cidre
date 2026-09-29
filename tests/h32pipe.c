/*
 * Invite i386 : le premier appel de methode qui traverse le pont Steam.
 *
 * Tout ce que la session a montre passait par CreateInterface, jamais par une
 * methode : le relais __thiscall n'a jamais imprime une ligne. Ce test fait
 * l'appel le plus simple et le plus inoffensif qui soit -- celui que tout jeu
 * Steam fait en premier.
 *
 *   emplacement 0 : CreateSteamPipe()            -> un tuyau
 *   emplacement 2 : ConnectToGlobalUser(tuyau)   -> un utilisateur
 *   emplacement 1 : BReleaseSteamPipe(tuyau)     -> on rend ce qu'on a pris
 *
 * On s'en tient a ces trois-la. Appeler un emplacement inconnu sur la session
 * Steam vivante de l'utilisateur peut le deconnecter, et ce n'est pas au test
 * de le decouvrir.
 */
#include <windows.h>
#include <stdio.h>

/*
 * Appel __thiscall : « this » dans ECX, les arguments sur la pile, et c'est
 * l'appele qui les depile. Le compilateur sait le faire ; le faire a la main
 * en assembleur m'a coute une faute de page, parce qu'une contrainte « g »
 * peut designer un emplacement relatif a ESP -- que les « pushl » venaient
 * justement de deplacer.
 */
typedef unsigned (__thiscall *methode0)( void * );
typedef unsigned (__thiscall *methode1)( void *, unsigned );
typedef unsigned (__thiscall *methode2)( void *, unsigned, const char * );
typedef unsigned (__thiscall *methode3)( void *, unsigned, unsigned, const char * );

int main(void)
{
    void *(__cdecl *creer)( const char *, int * );
    HMODULE client;
    void *objet;
    void **table;
    unsigned tuyau, utilisateur, rendu;

    if (!(client = LoadLibraryA( "steamclient.dll" )))
    { printf( "steamclient.dll : %lu\n", GetLastError() ); return 2; }

    if (!(creer = (void *)GetProcAddress( client, "CreateInterface" )))
    { printf( "CreateInterface introuvable\n" ); return 2; }

    if (!(objet = creer( "SteamClient017", NULL )))
    { printf( "SteamClient017 : rien\n" ); return 1; }
    printf( "SteamClient017 : objet %p\n", objet ); fflush( stdout );

    table = *(void ***)objet;
    printf( "table de methodes %p, emplacement 0 = %p\n", table, table[0] ); fflush( stdout );

    tuyau = ((methode0)table[0])( objet );
    printf( "CreateSteamPipe       -> %u %s\n", tuyau, tuyau ? "" : "(echec)" ); fflush( stdout );
    if (!tuyau) { printf( "i386 pont Steam : ECHEC au premier appel\n" ); return 1; }

    utilisateur = ((methode1)table[2])( objet, tuyau );
    printf( "ConnectToGlobalUser   -> %u %s\n", utilisateur, utilisateur ? "" : "(echec)" );
    fflush( stdout );

    /*
     * Les deux interfaces que l'enveloppe du DRM reclame. Elles sont rendues
     * par les emplacements 5 et 9 d'ISteamClient, que la table mesuree du pont
     * nomme GetISteamUser et GetISteamUtils -- on ne devine rien.
     */
    {
        void *iuser  = (void *)((methode3)table[5])( objet, utilisateur, tuyau, "SteamUser017" );
        void *iutils = (void *)((methode2)table[9])( objet, tuyau, "SteamUtils007" );

        printf( "GetISteamUser         -> %p\n", iuser );
        printf( "GetISteamUtils        -> %p\n", iutils );
        fflush( stdout );

        /* Deux lectures inoffensives, aux emplacements que la table donne :
         * ISteamUtils::GetAppID (9) et ISteamUser::BLoggedOn (1). */
        if (iutils)
        {
            void **t = *(void ***)iutils;
            printf( "  ISteamUtils::GetAppID -> %u\n", ((methode0)t[9])( iutils ) );
        }
        if (iuser)
        {
            void **t = *(void ***)iuser;
            printf( "  ISteamUser::BLoggedOn -> %u\n", ((methode0)t[1])( iuser ) );
        }
        fflush( stdout );

        /*
         * L'interface que reclame l'enveloppe du DRM. Elle n'a pas de
         * GetISteam* dedie : elle passe par le passe-partout, emplacement 12,
         * qui rend n'importe quelle interface d'apres sa chaine de version.
         *
         * On verifie qu'on l'obtient et qu'elle revient enveloppee. On
         * n'appelle aucune de ses methodes : « ISteamAppTicket » ne figure pas
         * dans la table mesuree du pont, donc ses emplacements seraient devines
         * -- et c'est precisement ce que ce projet refuse de faire sur une
         * session Steam vivante. C'est au jeu de les reveler, en appelant a
         * travers les thunks qui journalisent.
         */
        {
            void *billet = (void *)((methode3)table[12])( objet, utilisateur, tuyau,
                                                          "STEAMAPPTICKET_INTERFACE_VERSION001" );

            printf( "GetISteamGenericInterface(\"STEAMAPPTICKET...001\") -> %p\n", billet );
            if (billet)
            {
                void **t = *(void ***)billet;
                printf( "  table de methodes %p, emplacement 0 = %p (non appele)\n", t, t[0] );
            }
            fflush( stdout );
        }

        /*
         * Une position encore inconnue, pour montrer l'apprentissage :
         * GetISteamApps (emplacement 15) ne figure pas dans types32.h, donc le
         * pont retombe sur l'heuristique -- et imprime une PREUVE pour chaque
         * mot qui passe sous le seuil, puisqu'un tel mot ne peut pas etre un
         * pointeur. Ces lignes sont faites pour etre reportees dans la table.
         */
        {
            void *iapps = (void *)((methode3)table[15])( objet, utilisateur, tuyau, "STEAMAPPS_INTERFACE_VERSION008" );
            printf( "GetISteamApps         -> %p\n", iapps );
            fflush( stdout );
        }

        rendu = ((methode1)table[1])( objet, tuyau );
        printf( "BReleaseSteamPipe     -> %u\n", rendu );

        printf( "i386 pont Steam : %s\n",
                (tuyau && utilisateur && iuser && iutils) ? "ok" : "incomplet" );
        return (tuyau && utilisateur && iuser && iutils) ? 0 : 1;
    }
}
