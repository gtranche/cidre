/*
 * Invite x86-64 : la poignee de main de l'enveloppe SteamStub aboutit-elle ?
 *
 * Un jeu protege par le DRM de Steam demande au client, avant de se dechiffrer,
 * un accuse de reception (protocole « SteamStart », voir tests/faux_steam.c).
 * Sans reponse en cinq secondes il affiche « Application load error
 * 3:0000065432 ». Ce temoin tient le role du jeu, avec les memes objets nommes
 * et dans le meme ordre que Proton les decrit (steam_helper/steam.cpp) :
 *
 *   prendre SREAM_DIPC_PRODUCE, creer l'evenement STEAM_START_ACK_EVENT_<suffixe>,
 *   rendre STEAM_DIPC_CONSUME, attendre l'evenement.
 *
 * A lancer pendant que c:\faux_steam.exe tourne dans le meme prefixe.
 *
 *   x86_64-w64-mingw32-clang -O1 -o h64drm.exe h64drm.c
 */
#include <windows.h>
#include <stdio.h>

int main( void )
{
    HANDLE produire, consommer, accuse, segment;
    char nom[64];
    DWORD r;

    setvbuf( stdout, NULL, _IONBF, 0 );
    segment = OpenFileMappingA( FILE_MAP_READ, FALSE, "Local\\SteamStart_SharedMemFile" );
    printf( "  segment SteamStart_SharedMemFile        : %s\n", segment ? "ouvert" : "ABSENT" );
    produire  = OpenSemaphoreA( SEMAPHORE_ALL_ACCESS, FALSE, "SREAM_DIPC_PRODUCE" );
    consommer = OpenSemaphoreA( SEMAPHORE_ALL_ACCESS, FALSE, "STEAM_DIPC_CONSUME" );
    printf( "  semaphores DIPC                         : %s\n", produire && consommer ? "ouverts" : "ABSENTS" );
    if (!produire || !consommer) { printf( "x86-64 DRM : ECHEC (le client de service ne tourne pas ?)\n" ); return 2; }

    r = WaitForSingleObject( produire, 5000 );
    printf( "  jeton d'ecriture                        : %s\n", r == WAIT_OBJECT_0 ? "obtenu" : "REFUSE" );
    if (r != WAIT_OBJECT_0) { printf( "x86-64 DRM : ECHEC\n" ); return 1; }

    snprintf( nom, sizeof(nom), "STEAM_START_ACK_EVENT_%08lx", GetCurrentProcessId() );
    accuse = CreateEventA( NULL, FALSE, FALSE, nom );
    ReleaseSemaphore( consommer, 1, NULL );
    r = WaitForSingleObject( accuse, 5000 );
    printf( "  accuse du client                        : %s\n",
            r == WAIT_OBJECT_0 ? "recu" : "PAS RECU en 5 s (le jeu afficherait « Application load error 3 »)" );
    printf( "x86-64 DRM : %s\n", r == WAIT_OBJECT_0 ? "ok" : "ECHEC" );
    return r != WAIT_OBJECT_0;
}
