/*
 * Invite x86-64 : le client Steam rend-il le ticket de possession d'un jeu ?
 *
 * C'est la derniere question que pose l'enveloppe SteamStub avant de dechiffrer
 * un jeu : ISteamAppTicket::GetAppOwnershipTicketData, sept arguments. Si le
 * ticket revient vide, le jeu s'arrete sur « Application load error
 * 6:0000065432 ». Le pont relaie l'appel au client Steam de macOS ; en 64 bits
 * il ne transmettait que six arguments, et le septieme -- le pointeur ou le
 * client ecrit la longueur de la signature -- partait a zero.
 *
 * Ce temoin fait le meme chemin que l'enveloppe : la DLL que le registre
 * designe, CreateInterface, un tuyau, l'utilisateur global, l'interface de
 * ticket, puis l'appel. Il lui faut le client Steam de macOS ouvert et
 * connecte a un compte qui possede le jeu.
 *
 *   h64ticket.exe <appid>
 *   x86_64-w64-mingw32-clang -O1 -o h64ticket.exe h64ticket.c
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

typedef void *(__cdecl *fn_create)( const char *version, int *err );
/* Les methodes C++ de Valve : « this » d'abord, convention x64 de Microsoft. */
typedef int   (*m_pipe)( void *self );
typedef int   (*m_utilisateur)( void *self, int pipe );
typedef void *(*m_generique)( void *self, int utilisateur, int pipe, const char *version );
typedef unsigned (*m_ticket)( void *self, unsigned appid, void *tampon, unsigned taille,
                              unsigned *app, unsigned *steamid, unsigned *signature, unsigned *taille_signature );

int main( int argc, char **argv )
{
    unsigned appid = argc > 1 ? strtoul( argv[1], NULL, 10 ) : 0;
    char chemin[MAX_PATH] = "";
    DWORD taille = sizeof(chemin);
    unsigned char ticket[2048];
    unsigned app = ~0u, steamid = ~0u, signature = ~0u, taille_signature = ~0u, longueur;
    HMODULE module;
    fn_create creer;
    void *client = NULL, *tickets;
    void **table;
    int pipe, utilisateur, err = 0, i;
    static const char *versions[] = { "SteamClient021", "SteamClient020", "SteamClient017", NULL };

    setvbuf( stdout, NULL, _IONBF, 0 );
    if (!appid) { printf( "usage: h64ticket <appid>\n" ); return 2; }
    RegGetValueA( HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess", "SteamClientDll64",
                  RRF_RT_REG_SZ, NULL, chemin, &taille );
    printf( "  client designe au registre : %s\n", chemin );
    if (!(module = LoadLibraryA( chemin )) || !(creer = (fn_create)GetProcAddress( module, "CreateInterface" )))
    { printf( "x86-64 ticket Steam : ECHEC (DLL du client)\n" ); return 1; }
    for (i = 0; versions[i] && !client; i++) client = creer( versions[i], &err );
    if (!client) { printf( "x86-64 ticket Steam : ECHEC (pas d'interface client)\n" ); return 1; }

    table = *(void ***)client;
    pipe = ((m_pipe)table[0])( client );
    utilisateur = pipe ? ((m_utilisateur)table[2])( client, pipe ) : 0;
    printf( "  tuyau %d, utilisateur global %d\n", pipe, utilisateur );
    if (!pipe || !utilisateur)
    { printf( "x86-64 ticket Steam : ECHEC (client Steam de macOS ferme ou deconnecte ?)\n" ); return 1; }

    tickets = ((m_generique)table[12])( client, utilisateur, pipe, "STEAMAPPTICKET_INTERFACE_VERSION001" );
    if (!tickets) { printf( "x86-64 ticket Steam : ECHEC (pas d'interface de ticket)\n" ); return 1; }

    /* Un ticket jamais demande n'est pas en cache : le client le reclame a
     * Valve a la premiere demande, et ne l'a qu'un instant plus tard. */
    for (i = 0; i < 15; i++)
    {
        taille_signature = ~0u;
        longueur = ((m_ticket)(*(void ***)tickets)[0])( tickets, appid, ticket, sizeof(ticket),
                                                        &app, &steamid, &signature, &taille_signature );
        if (longueur) break;
        Sleep( 1000 );
    }
    if (i) printf( "  %d nouvelle(s) demande(s), une par seconde\n", i < 15 ? i : 15 );
    printf( "  ticket de l'application %u  : %u octets\n", appid, longueur );
    printf( "  positions rendues           : app %u, steamid %u, signature %u, longueur de signature %u\n",
            app, steamid, signature, taille_signature );
    if (!longueur)
        printf( "x86-64 ticket Steam : ECHEC (ticket vide : jeu non possede par ce compte, ou appel mal relaye)\n" );
    else if (taille_signature == ~0u)
        printf( "x86-64 ticket Steam : ECHEC (le septieme argument n'a pas ete transmis)\n" );
    else
        printf( "x86-64 ticket Steam : ok\n" );
    return !(longueur && taille_signature != ~0u);
}
