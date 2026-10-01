/* touche.exe [VK_hex [scan_hex]]      : met la fenetre Vermintide 2 au premier plan et envoie la touche
   touche.exe clic <x_pct> <y_pct>      : clic gauche a (x %, y %) de la zone cliente (decimal, 0-100)
   (defaut : espace 0x20/0x39). Sans CRT : bati avec clang --target=x86_64-pc-windows-msvc. */
typedef void *HWND; typedef unsigned int DWORD; typedef unsigned short WORD;
typedef struct { int left, top, right, bottom; } RECT; typedef struct { int x, y; } POINT;
__declspec(dllimport) char *GetCommandLineA(void);
__declspec(dllimport) int GetClientRect(HWND, RECT*);
__declspec(dllimport) int ClientToScreen(HWND, POINT*);
__declspec(dllimport) int SetCursorPos(int, int);
static int decv(const char *c){ int v=0; while(*c>='0'&&*c<='9'){ v=v*10+(*c-'0'); c++; } return v; }
/* « clic x y » en tete de ligne de commande ? rend 1 et remplit x,y (pourcents) */
static int arg_clic(int *x, int *y){
    char *c = GetCommandLineA();
    if (*c=='"'){ c++; while(*c && *c!='"') c++; if(*c) c++; } else while(*c && *c!=' ') c++;
    while(*c==' ') c++;
    int mode = 0;
    if (c[0]=='c'&&c[1]=='l'&&c[2]=='i'&&c[3]=='c'&&c[4]=='a'&&c[5]=='b'&&c[6]=='s'&&c[7]==' ') { mode = 2; c += 8; }
    else if (c[0]=='s'&&c[1]=='o'&&c[2]=='u'&&c[3]=='r'&&c[4]=='i'&&c[5]=='s'&&c[6]==' ') { mode = 3; c += 7; }
    else if (c[0]=='c'&&c[1]=='l'&&c[2]=='i'&&c[3]=='c'&&c[4]==' ') { mode = 1; c += 5; }
    else return 0;
    while(*c==' ') c++; *x=decv(c); while(*c && *c!=' ') c++; while(*c==' ') c++; *y=decv(c); return mode;
}
typedef struct { DWORD type; DWORD pad; union { struct { WORD vk, scan; DWORD flags, time; unsigned long long extra; } ki; unsigned char raw[32]; } u; } INPUT;
__declspec(dllimport) HWND FindWindowA(const char*, const char*);
__declspec(dllimport) int SetForegroundWindow(HWND);
__declspec(dllimport) HWND GetForegroundWindow(void);
__declspec(dllimport) int GetWindowTextA(HWND, char*, int);
__declspec(dllimport) DWORD SendInput(DWORD, INPUT*, int);
__declspec(dllimport) void Sleep(DWORD);
__declspec(dllimport) void ExitProcess(DWORD);
__declspec(dllimport) void *GetStdHandle(DWORD);
__declspec(dllimport) int WriteFile(void*, const void*, DWORD, DWORD*, void*);
static void dire(const char *s){ DWORD n=0,l=0; while(s[l])l++; WriteFile(GetStdHandle((DWORD)-11), s, l, &n, 0); }
static int hexv(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }
/* lit jusqu'a deux nombres hexa en fin de ligne de commande */
static void args(WORD *vk, WORD *scan){
    char *c = GetCommandLineA(); int n=0; unsigned v[2]={0,0}; int got[2]={0,0};
    /* saute le programme (gere les guillemets) */
    if (*c=='"'){ c++; while(*c && *c!='"') c++; if(*c) c++; } else while(*c && *c!=' ') c++;
    while (*c && n<2){ while(*c==' ') c++; if(!*c) break; unsigned v2=0; int ok=0;
        if (c[0]=='0' && (c[1]=='x'||c[1]=='X')) c+=2;
        while (*c && *c!=' '){ int h=hexv(*c); if(h<0){ok=0;break;} v2=v2*16+h; ok=1; c++; }
        while(*c && *c!=' ') c++;
        if(ok){ v[n]=v2; got[n]=1; } n++; }
    if(got[0]) *vk=(WORD)v[0]; if(got[1]) *scan=(WORD)v[1];
}
void mainCRTStartup(void) {
    WORD vk=0x20, scan=0x39; args(&vk,&scan);
    HWND w = FindWindowA(0, "Warhammer: Vermintide 2");
    if (!w) { dire("fenetre introuvable\n"); ExitProcess(1); }
    SetForegroundWindow(w); Sleep(400);
    char t[128]; t[0]=0; GetWindowTextA(GetForegroundWindow(), t, sizeof t); dire("premier plan : "); dire(t); dire("\n");
    INPUT in; for (int i=0;i<(int)sizeof in;i++) ((char*)&in)[i]=0;
    int cx, cy, mode;
    if ((mode = arg_clic(&cx, &cy))) {
        RECT r; POINT p; GetClientRect(w, &r); p.x = (r.right - r.left) * cx / 100; p.y = (r.bottom - r.top) * cy / 100;
        ClientToScreen(w, &p); SetCursorPos(p.x, p.y); Sleep(80);
        in.type = 0; /* MOUSEINPUT : dx,dy,mouseData,dwFlags,time,extra */
        DWORD *mi = (DWORD*)in.u.raw; int *md = (int*)in.u.raw;
        if (mode == 3) { dire("souris posee\n"); ExitProcess(0); }
        if (mode == 1) {
            /* Un jeu qui pilote son curseur aux deltas bruts ignore SetCursorPos :
             * on l'envoie d'abord loin en haut a gauche (il bute sur le bord), puis
             * on avance de la distance voulue en pixels de la zone cliente. */
            md[0] = -20000; md[1] = -20000; mi[3] = 0x0001; /* MOVE */ SendInput(1, &in, sizeof in); Sleep(60);
            { POINT o = {0,0}; ClientToScreen(w, &o); md[0] = p.x - o.x; md[1] = p.y - o.y; }
            SendInput(1, &in, sizeof in); Sleep(80);
        } else {
            /* un petit mouvement nul pour que le jeu rafraichisse sa position */
            md[0] = 1; md[1] = 0; mi[3] = 0x0001; SendInput(1, &in, sizeof in); Sleep(40);
            md[0] = -1; SendInput(1, &in, sizeof in); Sleep(80);
        }
        md[0] = 0; md[1] = 0; mi[3] = 0x0002; /* LEFTDOWN */
        DWORD a1 = SendInput(1, &in, sizeof in); Sleep(60); mi[3] = 0x0004; /* LEFTUP */ DWORD b1 = SendInput(1, &in, sizeof in);
        dire(a1 && b1 ? "clic envoye\n" : "SendInput souris a echoue\n"); ExitProcess(0);
    }
    in.type = 1; in.u.ki.vk = vk; in.u.ki.scan = scan;
    DWORD a = SendInput(1, &in, sizeof in); Sleep(60);
    in.u.ki.flags = 2; DWORD b = SendInput(1, &in, sizeof in);
    dire(a && b ? "touche envoyee\n" : "SendInput a echoue\n");
    ExitProcess(0);
}
