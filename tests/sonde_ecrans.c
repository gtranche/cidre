/* Etat du cache d'ecrans de user32, vu par un processus qui vient de demarrer.
   Repete la mesure a intervalle fixe pour distinguer un cache vide d'un cache
   qui se remplit en retard. */
#include <windows.h>
#include <stdio.h>

static void mesure(const char *quand)
{
    DISPLAY_DEVICEA d;
    UINT i = 0;
    int trouve = 0;

    printf("%-10s SM_CMONITORS=%d\n", quand, GetSystemMetrics(SM_CMONITORS));
    ZeroMemory(&d, sizeof(d));
    d.cb = sizeof(d);
    while (EnumDisplayDevicesA(NULL, i, &d, 0)) {
        printf("%-10s ecran %u nom=\"%s\" chaine=\"%s\" flags=0x%08x\n",
               quand, i, d.DeviceName, d.DeviceString, (unsigned)d.StateFlags);
        trouve++;
        i++;
        ZeroMemory(&d, sizeof(d));
        d.cb = sizeof(d);
    }
    if (!trouve)
        printf("%-10s aucun ecran\n", quand);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    int tours = (argc > 1) ? atoi(argv[1]) : 1;
    int i;

    for (i = 0; i < tours; i++) {
        char quand[32];
        sprintf(quand, "t=%ds", i);
        mesure(quand);
        if (i + 1 < tours)
            Sleep(1000);
    }
    return 0;
}
