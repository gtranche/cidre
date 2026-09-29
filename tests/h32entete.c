/*
 * Invite i386 : l'image en memoire de steamclient.dll est-elle identique a son
 * fichier ?
 *
 * C'est la question que pose steamdrmp.dll, et la reponse decide de tout. Son
 * code, a 0x10002ab0, fait exactement ceci :
 *
 *   - lire le fichier du module entier
 *   - comparer les 0x3c premiers octets (en-tete DOS)
 *   - recopier ImageBase (e_lfanew + 0x34) de la memoire vers la copie fichier,
 *     puisque le chargeur l'a forcement change
 *   - comparer octet par octet jusqu'a e_lfanew + 0x120, c'est-a-dire tout
 *     l'en-tete PE plus le premier en-tete de section
 *
 * Si un seul octet differe, il rend le caractere '3' et le jeu affiche
 * « Application load error 3:0000065432 ».
 *
 * Ce test refait la comparaison et nomme chaque octet qui differe.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static const char *nom_champ( unsigned lfanew, unsigned o )
{
    if (o < 0x3c) return "en-tete DOS";
    if (o < lfanew) return "bouchon DOS";
    o -= lfanew;
    if (o < 4)    return "signature PE";
    if (o < 0x18) return "en-tete COFF";
    o -= 0x18;                                  /* debut de l'en-tete optionnel */
    if (o == 0x1c) return "ImageBase";
    if (o == 0x38) return "SizeOfImage";
    if (o == 0x3c) return "SizeOfHeaders";
    if (o == 0x40) return "CheckSum";
    if (o < 0x60)  return "en-tete optionnel";
    if (o < 0xe0)  return "repertoires de donnees";
    return "premier en-tete de section";
}

int main(void)
{
    HMODULE m;
    HANDLE f;
    DWORD taille, lus = 0;
    unsigned char *fichier, *memoire;
    WCHAR chemin[MAX_PATH];
    unsigned lfanew, fin, i, ecarts = 0;

    if (!(m = LoadLibraryA( "steamclient.dll" )))
    { printf( "steamclient.dll : %lu\n", GetLastError() ); return 2; }
    memoire = (unsigned char *)m;

    if (!GetModuleFileNameW( m, chemin, MAX_PATH )) { printf( "GetModuleFileName\n" ); return 2; }
    printf( "module a %p, fichier %ls\n", m, chemin );

    f = CreateFileW( chemin, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL );
    if (f == INVALID_HANDLE_VALUE) { printf( "CreateFile : %lu\n", GetLastError() ); return 2; }
    taille = GetFileSize( f, NULL );
    if (!(fichier = malloc( taille ))) return 2;
    if (!ReadFile( f, fichier, taille, &lus, NULL )) { printf( "ReadFile : %lu\n", GetLastError() ); return 2; }
    CloseHandle( f );
    printf( "fichier : %lu octets lus sur %lu\n", lus, taille );

    lfanew = *(DWORD *)(memoire + 0x3c);
    fin = lfanew + 0x120;
    printf( "e_lfanew = %#x, comparaison sur %#x octets\n", lfanew, fin );
    if (taille < fin) { printf( "fichier trop court\n" ); return 1; }

    /* Ce que le controle s'autorise : ImageBase, que le chargeur a relocalise. */
    *(DWORD *)(fichier + lfanew + 0x34) = *(DWORD *)(memoire + lfanew + 0x34);

    for (i = 0; i < fin; i++)
    {
        if (memoire[i] == fichier[i]) continue;
        if (ecarts < 40)
            printf( "  %#06x : memoire %02x, fichier %02x   (%s)\n",
                    i, memoire[i], fichier[i], nom_champ( lfanew, i ) );
        ecarts++;
    }

    printf( "i386 en-tete : %u octets differents -> steamdrmp rendrait '%c'\n",
            ecarts, ecarts ? '3' : '0' );
    return ecarts ? 1 : 0;
}
