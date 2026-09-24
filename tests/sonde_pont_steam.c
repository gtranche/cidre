/* Le pont lsteamclient rend-il les interfaces du client Steam natif ? */
#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *fn_create)(const char *version, int *err);

int main(void)
{
    static const char *versions[] = {
        "SteamClient021", "SteamClient020", "SteamClient017", NULL
    };
    HMODULE h = LoadLibraryA("lsteamclient.dll");
    fn_create creer;
    int i;

    if (!h) { printf("LoadLibrary a echoue : %lu\n", GetLastError()); return 1; }
    printf("lsteamclient.dll charge\n");

    creer = (fn_create)GetProcAddress(h, "CreateInterface");
    if (!creer) { printf("CreateInterface introuvable : %lu\n", GetLastError()); return 1; }
    printf("CreateInterface trouve\n");

    for (i = 0; versions[i]; i++) {
        int err = 0;
        void *iface = creer(versions[i], &err);
        printf("  %s -> %p (err=%d)\n", versions[i], iface, err);
    }
    return 0;
}
