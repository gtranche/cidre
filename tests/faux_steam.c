/* Un processus que steam_api accepte comme etant le client Steam.
 *
 * SteamAPI_Init verifie que le processus designe par
 * HKCU\Software\Valve\Steam\ActiveProcess\pid est vivant. Sans lui, il attend
 * indefiniment que Steam apparaisse -- et c'est bien ce qu'on observait. Le
 * client qui repond reellement est celui de macOS, derriere l'unixlib ; il
 * suffit donc d'un processus Windows vivant dans le prefixe, qui inscrit son
 * propre identifiant et ne fait rien d'autre.
 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HKEY cle;
    DWORD pid = GetCurrentProcessId();

    if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                        0, NULL, 0, KEY_WRITE, NULL, &cle, NULL))
    { fprintf(stderr, "cle impossible\n"); return 1; }
    RegSetValueExA(cle, "pid", 0, REG_DWORD, (const BYTE *)&pid, sizeof(pid));
    RegCloseKey(cle);

    fprintf(stderr, "faux steam : pid %lu inscrit\n", pid);
    for (;;) Sleep(1000);
    return 0;
}
