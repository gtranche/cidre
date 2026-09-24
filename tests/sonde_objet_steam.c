/* Le franchissement d'ABI dans le sens qui compte.
 *
 * On n'appelle plus une fonction exportee : on traite l'objet rendu comme un
 * jeu le ferait, c'est-a-dire en dereferencant sa table de methodes et en
 * invoquant l'emplacement zero. C'est un appel virtuel en ABI Microsoft x64,
 * exactement ce que fera le steam_api64.dll d'un jeu.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef void *(__cdecl *fn_wrap)(void *natif);

/* Ce qu'un jeu voit d'une interface Steamworks. */
struct ISteamClient { void **table; };
typedef int (*ISteamClient_CreateSteamPipe)(struct ISteamClient *self);
typedef int (*ISteamClient_BReleaseSteamPipe)(struct ISteamClient *self, int pipe);

int main(void)
{
    static const char *versions[] = { "SteamClient021", "SteamClient020", NULL };
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer;
    fn_wrap envelopper;
    int i;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
    creer      = (fn_create)GetProcAddress(h, "CreateInterface");
    envelopper = (fn_wrap)GetProcAddress(h, "SondeEnvelopperSteamClient");
    if (!creer || !envelopper) { printf("symboles manquants\n"); return 1; }

    for (i = 0; versions[i]; i++) {
        int err = 0, tuyau;
        void *natif = creer(versions[i], &err);
        struct ISteamClient *objet;
        ISteamClient_CreateSteamPipe methode;

        if (!natif) { printf("%s : pas d'interface\n", versions[i]); continue; }
        objet = envelopper(natif);
        if (!objet) { printf("%s : enveloppe impossible\n", versions[i]); continue; }

        /* L'appel virtuel, tel qu'un jeu l'ecrit. */
        methode = (ISteamClient_CreateSteamPipe)objet->table[0];
        tuyau = methode(objet);

        printf("%s : objet %p, CreateSteamPipe -> %d %s\n",
               versions[i], (void *)objet, tuyau,
               tuyau ? "(tuyau valide)" : "(nul)");

        if (tuyau) {
            ISteamClient_BReleaseSteamPipe liberer =
                (ISteamClient_BReleaseSteamPipe)objet->table[1];
            int ok = liberer(objet, tuyau);
            printf("%s : BReleaseSteamPipe(%d) -> %d %s\n",
                   versions[i], tuyau, ok,
                   ok ? "(argument transmis)" : "(refuse)");
        }
    }
    return 0;
}
