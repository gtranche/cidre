/* Sonde 0149 (tests/sonde_make_ratio.c) : passe l'ecran dans un mode dont le rapport a la sortie physique est
 * irreductible (1496x967 par defaut), puis interroge le DPI du moniteur comme le
 * fait un jeu apres ChangeDisplaySettings. Sans 0149, win32u assertait dans
 * make_ratio (« num / d < 65536 »). A lancer avec CIDRE_EMULATE_MODESET=1 dans un prefixe clone ;
 * construire : x86_64-w64-mingw32-gcc -O1 -o sonde_make_ratio.exe sonde_make_ratio.c -luser32 -lshcore
 * usage : sonde_make_ratio.exe [largeur hauteur] */
#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <shellscalingapi.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    DEVMODEA dm = {.dmSize = sizeof(dm)};
    MONITORINFO mi = {.cbSize = sizeof(mi)};
    UINT dx = 0, dy = 0;
    HMONITOR mon;
    LONG r;
    int w = argc > 2 ? atoi(argv[1]) : 1496, h = argc > 2 ? atoi(argv[2]) : 967;

    setvbuf(stdout, NULL, _IONBF, 0);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm);
    printf("avant : %lux%lu\n", dm.dmPelsWidth, dm.dmPelsHeight);
    dm.dmPelsWidth = w; dm.dmPelsHeight = h;
    dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
    r = ChangeDisplaySettingsA(&dm, CDS_FULLSCREEN);
    printf("ChangeDisplaySettings %dx%d -> %ld\n", w, h, r);
    EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm);
    printf("apres : %lux%lu\n", dm.dmPelsWidth, dm.dmPelsHeight);

    mon = MonitorFromPoint((POINT){0, 0}, MONITOR_DEFAULTTOPRIMARY);
    GetMonitorInfoA(mon, &mi);
    printf("moniteur : %ld,%ld-%ld,%ld\n", mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right, mi.rcMonitor.bottom);
    GetDpiForMonitor(mon, MDT_RAW_DPI, &dx, &dy);
    printf("DPI brut : %u x %u\n", dx, dy);
    GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dx, &dy);
    printf("DPI effectif : %u x %u\n", dx, dy);
    printf("ecran (systeme) : %dx%d\n", GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));

    ChangeDisplaySettingsA(NULL, 0);
    printf("SONDE OK\n");
    return 0;
}
