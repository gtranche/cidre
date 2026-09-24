/* Piloter le vrai steam_api64.dll d'un jeu.
 *
 * Le jeu lui-meme passe par son lanceur et se comporte differemment d'un
 * lancement a l'autre ; son steam_api64.dll, lui, est du code Valve
 * deterministe. On l'appelle directement : SteamAPI_Init fait exactement la
 * meme suite d'appels sur ISteamClient que dans le jeu, et la table de
 * decouverte la journalise.
 */
#include <windows.h>
#include <stdio.h>

typedef char (__cdecl *fn_bool)(void);
typedef void (__cdecl *fn_void)(void);

int main(int argc, char **argv)
{
    HMODULE h;
    fn_bool init, tourne;
    fn_void rappels, arret;
    int i;

    if (argc < 2) { fprintf(stderr, "usage : %s <chemin\\steam_api64.dll>\n", argv[0]); return 2; }
    if (!(h = LoadLibraryA(argv[1]))) { fprintf(stderr, "chargement impossible : %lu\n", GetLastError()); return 1; }
    fprintf(stderr, "steam_api64 charge : %p\n", (void *)h);

    tourne  = (fn_bool)GetProcAddress(h, "SteamAPI_IsSteamRunning");
    init    = (fn_bool)GetProcAddress(h, "SteamAPI_Init");
    rappels = (fn_void)GetProcAddress(h, "SteamAPI_RunCallbacks");
    arret   = (fn_void)GetProcAddress(h, "SteamAPI_Shutdown");
    if (!init) { fprintf(stderr, "SteamAPI_Init absent\n"); return 1; }

    if (tourne) fprintf(stderr, "SteamAPI_IsSteamRunning -> %d\n", tourne());

    fprintf(stderr, "--- SteamAPI_Init ---\n");
    fprintf(stderr, "SteamAPI_Init -> %d\n", init() ? 1 : 0);

    if (rappels) {
        fprintf(stderr, "--- SteamAPI_RunCallbacks x20 ---\n");
        for (i = 0; i < 20; i++) { rappels(); Sleep(50); }
    }
    if (arret) arret();
    return 0;
}
