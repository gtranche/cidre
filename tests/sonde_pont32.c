/* Le pont repond-il a un binaire 32 bits ?
 *
 * Avant d'engendrer des centaines de thunks pour l'ABI __thiscall, il faut
 * savoir si la plomberie tient : un PE i386 doit charger notre lsteamclient
 * 32 bits, dont l'unixlib est en 64 bits -- c'est le fonctionnement du nouveau
 * WoW64. CreateInterface est en __cdecl, donc ce test isole la plomberie de la
 * question des conventions d'appel.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef int   (__cdecl *fn_pipe)(void);
typedef int   (__cdecl *fn_connect)(int pipe);

int main(void)
{
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer; fn_pipe tuyau; fn_connect connecter;
    void *client; int err = 0, t, u;

    if (!h) { fprintf(stderr, "LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
    fprintf(stderr, "lsteamclient 32 bits charge : %p\n", (void *)h);

    creer     = (fn_create)GetProcAddress(h, "CreateInterface");
    tuyau     = (fn_pipe)GetProcAddress(h, "Steam_CreateSteamPipe");
    connecter = (fn_connect)GetProcAddress(h, "Steam_ConnectToGlobalUser");
    if (!creer || !tuyau || !connecter) { fprintf(stderr, "symboles manquants\n"); return 1; }

    client = creer("SteamClient020", &err);
    fprintf(stderr, "CreateInterface -> %p\n", client);
    if (!client) return 1;

    t = tuyau();
    u = connecter(t);
    fprintf(stderr, "tuyau %d, utilisateur %d\n", t, u);
    fprintf(stderr, "%s\n", (t && u) ? "plomberie 32 bits operationnelle" : "echec");
    return 0;
}
