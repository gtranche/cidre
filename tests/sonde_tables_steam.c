/* Relever les tables de methodes, sans en appeler aucune.
 *
 * L'unixlib partage l'espace d'adressage du cote PE : la table de methodes de
 * l'objet natif est donc simplement lisible. On la releve pour chaque version
 * d'ISteamClient que le client distribue. Comparer les versions entre elles
 * montre ou elles divergent, et une adresse identique a deux emplacements
 * differents designe la meme methode -- de quoi cartographier sans rien
 * appeler, donc sans risque pour la session Steam de l'utilisateur.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
struct objet_pe { void **table; void *natif; };

int main(void)
{
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer;
    int v;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
    if (!(creer = (fn_create)GetProcAddress(h, "CreateInterface"))) return 1;

    for (v = 6; v <= 23; v++) {
        char version[32];
        int err = 0, i;
        struct objet_pe *objet;
        void **table;

        sprintf(version, "SteamClient%03d", v);
        objet = creer(version, &err);
        if (!objet) continue;
        table = *(void ***)objet->natif;

        printf("%s natif=%p table=%p\n", version, objet->natif, (void *)table);
        for (i = 0; i < 100; i++) {
            if (IsBadReadPtr(&table[i], sizeof(void *))) break;
            printf("  %3d %p\n", i, table[i]);
        }
    }
    return 0;
}
