/*
 * Invite x86-64 : la page KUSER_SHARED_DATA est-elle lisible a son adresse fixe ?
 *
 * Windows la pose a 0x7ffe0000 dans tout processus, et du code x86-64 la lit
 * la, en dur. Deux cas reels :
 *   - les routines systeme de ntdll (« mov r10,rcx ; mov eax,N ;
 *     test byte ptr [7FFE0308h],1 ; syscall »), qu'un programme atteint des
 *     qu'il appelle une fonction Nt* lui-meme -- le lanceur de Clair Obscur:
 *     Expedition 33 le fait pour NtSetInformationThread(ThreadHideFromDebugger)
 *     et tombait la, dans une cascade d'exceptions jusqu'au bout de sa pile ;
 *   - les lectures directes de l'heure ou du compteur de tics.
 * macOS interdit toute adresse sous 4 Gio a un processus arm64 : la page vit
 * ailleurs pour l'hote, et Wine doit rendre ces lectures de l'invite.
 *
 *   x86_64-w64-mingw32-clang -O1 -o h64kuser.exe h64kuser.c
 */
#include <windows.h>
#include <stdio.h>

typedef LONG (WINAPI *nt_set_information_thread)( HANDLE, int, void *, ULONG );

int main( void )
{
    volatile const BYTE *kuser = (const BYTE *)0x7ffe0000;
    int echecs = 0;
    ULONGLONG t1, t2;
    nt_set_information_thread set_info;
    LONG status;

    setvbuf( stdout, NULL, _IONBF, 0 );

    printf( "  octet SystemCall (0x308)               : %u\n", kuser[0x308] );
    printf( "  NtMajorVersion (0x26c)                 : %lu", *(volatile const ULONG *)(kuser + 0x26c) );
    if (*(volatile const ULONG *)(kuser + 0x26c) != 10) { printf( " : ECHEC, attendu 10" ); echecs++; }
    printf( "\n" );

    t1 = *(volatile const ULONGLONG *)(kuser + 0x14);   /* SystemTime, lu en dur */
    Sleep( 30 );
    t2 = *(volatile const ULONGLONG *)(kuser + 0x14);
    printf( "  SystemTime (0x14) avance                : %s\n", t2 > t1 ? "oui" : "NON" );
    if (t2 <= t1) echecs++;

    /* La routine systeme elle-meme, comme la prend un programme qui se passe
     * de kernel32 : son code x86-64 lit 0x7ffe0308 avant l'appel systeme. */
    set_info = (nt_set_information_thread)GetProcAddress( GetModuleHandleA( "ntdll.dll" ), "NtSetInformationThread" );
    printf( "  NtSetInformationThread                 : %p, premiers octets %02x %02x %02x\n",
            set_info, ((const BYTE *)set_info)[0], ((const BYTE *)set_info)[1], ((const BYTE *)set_info)[2] );
    status = set_info( GetCurrentThread(), 0x11 /* ThreadHideFromDebugger */, NULL, 0 );
    printf( "  appel direct de la routine systeme     : %08lx\n", (unsigned long)status );
    if (status) echecs++;

    printf( "x86-64 KUSER : %s (%d echecs)\n", echecs ? "ECHEC" : "ok", echecs );
    return echecs;
}
