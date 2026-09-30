// Reproducteur minimal : exception C++ x64 (ABI MSVC) attrapee par reference,
// puis appel virtuel sur l'objet attrape. Sans CRT.
extern "C" void __stdcall OutputDebugStringA(const char*);
extern "C" void __stdcall ExitProcess(unsigned);

/* vtable de type_info exigee par les descripteurs de type de clang */
extern "C" const void* __type_info_vft[1] __asm__("??_7type_info@@6B@");
extern "C" const void* __type_info_vft[1] = { 0 };

struct Exc {
    Exc() {}
    virtual const char* what() const { return "boom"; }
    unsigned long long pad[9];   /* un membre a +0x48, comme le jeu */
    unsigned long long marque = 0x4242424242424242ull;
};

static void hexa(const char* pre, unsigned long long v)
{
    char b[64]; int i = 0;
    while (*pre) b[i++] = *pre++;
    b[i++]='0'; b[i++]='x';
    for (int s = 60; s >= 0; s -= 4) { unsigned d = (v >> s) & 15; b[i++] = d < 10 ? '0'+d : 'a'+d-10; }
    b[i++]='\n'; b[i]=0;
    OutputDebugStringA(b);
}

extern "C" int mainCRTStartup()
{
    OutputDebugStringA("REPRO: avant throw\n");
    try {
        Exc x;
        hexa("REPRO: objet lance a ", (unsigned long long)&x);
        throw x;
    }
    catch (Exc& e) {
        OutputDebugStringA("REPRO: dans catch\n");
        hexa("REPRO: &e = ", (unsigned long long)&e);
        hexa("REPRO: e.marque = ", e.marque);      /* [e+0x48] : faute si e==NULL */
        OutputDebugStringA(e.what());
    }
    OutputDebugStringA("\nREPRO: fin OK\n");
    ExitProcess(0);
    return 0;
}
