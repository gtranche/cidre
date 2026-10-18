/*
 * Temoin du correctif wine11 0182 : un invite 32 bits dont la fenetre est
 * rebasee (0096) peut faire ce que fait le client Battle.net (CEF/Chromium).
 * Sans reseau exterieur : tout passe par 127.0.0.1.
 *
 *   1. getaddrinfo (relais wow64 de ws2_32 cote unix)
 *   2. connexion non bloquante + WSAEventSelect + WSAEnumNetworkEvents
 *      (poignee d'evenement de IOCTL_AFD_GET_EVENTS)
 *   3. WSASend / WSARecv (tableaux de tampons des ioctl d'envoi et de reception)
 *   4. CreateDIBSection adossee a une section, ecriture dans ses bits
 *      (vue projetee par win32u pour l'invite)
 *   5. VirtualProtect sur une page ecrite de la section .data : l'ancienne
 *      protection doit etre PAGE_READWRITE, pas PAGE_WRITECOPY
 *   6. GetProcessMitigationPolicy remet le tampon a zero
 *
 *   i686-w64-mingw32-clang -O1 -o h32fenetre.exe h32fenetre.c -lws2_32 -lgdi32
 *   Sortie : « h32fenetre : ok » et code 0, ou la liste des echecs et le nombre.
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>

static int echecs;
#define VERIFIER(c, ...) do { if (!(c)) { echecs++; printf("ECHEC : " __VA_ARGS__); printf("\n"); } } while (0)

/* Une page de .data, alignee, ecrite avant le VirtualProtect. */
static __attribute__((aligned(4096))) volatile char page_donnees[4096] = { 1 };

static void reseau(void)
{
    WSADATA w;
    struct addrinfo h = {0}, *r = NULL;
    struct sockaddr_in a = {0};
    int la = sizeof(a), e;
    SOCKET ecoute, client, accepte;
    WSAEVENT ev;
    WSANETWORKEVENTS ne;
    u_long nb = 1;
    char envoi[] = "cidre", recu[8] = "";
    WSABUF be = { 5, envoi }, br = { sizeof(recu), recu };
    DWORD n = 0, drapeaux = 0;

    WSAStartup(MAKEWORD(2, 2), &w);
    h.ai_family = AF_INET; h.ai_socktype = SOCK_STREAM;
    e = getaddrinfo("127.0.0.1", "80", &h, &r);
    VERIFIER(!e && r, "getaddrinfo = %d", e);
    if (r) freeaddrinfo(r);

    ecoute = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(ecoute, (struct sockaddr *)&a, sizeof(a));
    listen(ecoute, 1);
    getsockname(ecoute, (struct sockaddr *)&a, &la);

    client = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    ev = WSACreateEvent();
    ioctlsocket(client, FIONBIO, &nb);
    WSAEventSelect(client, ev, FD_CONNECT);
    e = connect(client, (struct sockaddr *)&a, sizeof(a));
    VERIFIER(!e || WSAGetLastError() == WSAEWOULDBLOCK, "connect = %d", WSAGetLastError());
    WaitForSingleObject(ev, 5000);
    e = WSAEnumNetworkEvents(client, ev, &ne);
    VERIFIER(!e, "WSAEnumNetworkEvents = %d (WSA %d)", e, WSAGetLastError());
    VERIFIER(!e && (ne.lNetworkEvents & FD_CONNECT) && !ne.iErrorCode[FD_CONNECT_BIT],
             "FD_CONNECT absent ou en erreur (%lx, %d)", ne.lNetworkEvents, ne.iErrorCode[FD_CONNECT_BIT]);
    WSAEventSelect(client, NULL, 0);
    nb = 0;
    ioctlsocket(client, FIONBIO, &nb);

    accepte = accept(ecoute, NULL, NULL);
    e = WSASend(client, &be, 1, &n, 0, NULL, NULL);
    VERIFIER(!e && n == 5, "WSASend = %d (WSA %d), %lu octets", e, WSAGetLastError(), n);
    n = 0;
    e = WSARecv(accepte, &br, 1, &n, &drapeaux, NULL, NULL);
    VERIFIER(!e && n == 5 && !memcmp(recu, "cidre", 5), "WSARecv = %d (WSA %d), %lu octets", e, WSAGetLastError(), n);
    closesocket(accepte); closesocket(client); closesocket(ecoute);
}

static void dib_section(void)
{
    BITMAPINFO bi = {{ sizeof(BITMAPINFOHEADER), 256, -256, 1, 32, BI_RGB }};
    HANDLE s = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 256 * 256 * 4, NULL);
    void *bits = NULL;
    HBITMAP b = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, s, 0);
    MEMORY_BASIC_INFORMATION m = {0};

    VERIFIER(b && bits, "CreateDIBSection");
    if (!bits) return;
    VirtualQuery(bits, &m, sizeof(m));
    VERIFIER(m.State == MEM_COMMIT, "bits de la DIB hors de la fenetre (%p, etat %lx)", bits, m.State);
    if (m.State == MEM_COMMIT) ((volatile DWORD *)bits)[256 * 256 - 1] = 0x00c0ffee;
    DeleteObject(b);
    CloseHandle(s);
}

static void copie_a_l_ecriture(void)
{
    DWORD ancienne = 0, tmp;

    page_donnees[0] = 2;
    VERIFIER(VirtualProtect((void *)page_donnees, 4096, PAGE_READONLY, &ancienne), "VirtualProtect");
    VERIFIER(ancienne == PAGE_READWRITE, "ancienne protection %#lx, attendu PAGE_READWRITE", ancienne);
    VirtualProtect((void *)page_donnees, 4096, ancienne, &tmp);
}

static void politique(void)
{
    typedef BOOL (WINAPI *gpmp_t)(HANDLE, int, void *, SIZE_T);
    gpmp_t gpmp = (gpmp_t)GetProcAddress(GetModuleHandleA("kernelbase.dll"), "GetProcessMitigationPolicy");
    DWORD p = 0xdeadbeef;

    if (!gpmp) return;
    gpmp(GetCurrentProcess(), 4 /* ProcessSystemCallDisablePolicy */, &p, sizeof(p));
    VERIFIER(p == 0, "GetProcessMitigationPolicy laisse %#lx", p);
}

int main(void)
{
    reseau();
    dib_section();
    copie_a_l_ecriture();
    politique();
    if (echecs) printf("h32fenetre : %d echec(s)\n", echecs);
    else printf("h32fenetre : ok\n");
    return echecs;
}
