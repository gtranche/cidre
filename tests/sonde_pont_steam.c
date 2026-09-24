/* Un appel de methode traverse-t-il la frontiere d'ABI ?
 *
 * On demande une interface au client Steam natif, puis on appelle son premier
 * emplacement de table, ISteamClient::CreateSteamPipe. S'il rend un tuyau non
 * nul, l'objet natif est utilisable depuis Wine et le generateur de Proton
 * devient adaptable.
 */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);
typedef int   (__cdecl *fn_pipe)(void *iface);

int main(void)
{
    static const char *versions[] = { "SteamClient021", "SteamClient020", "SteamClient017", NULL };
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer;
    fn_pipe   tuyau;
    int i;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
    creer = (fn_create)GetProcAddress(h, "CreateInterface");
    tuyau = (fn_pipe)GetProcAddress(h, "SondeCreateSteamPipe");
    if (!creer || !tuyau) { printf("symboles manquants\n"); return 1; }

    for (i = 0; versions[i]; i++) {
        int err = 0, p;
        void *iface = creer(versions[i], &err);
        if (!iface) { printf("%s : pas d'interface\n", versions[i]); continue; }
        p = tuyau(iface);
        printf("%s : interface %p, CreateSteamPipe -> %d %s\n",
               versions[i], iface, p, p ? "(tuyau valide)" : "(nul)");
    }
    return 0;
}
