extern "C" void __stdcall OutputDebugStringA(const char*);
extern "C" void __stdcall ExitProcess(unsigned);
extern "C" const void* __type_info_vft[1] __asm__("??_7type_info@@6B@");
extern "C" const void* __type_info_vft[1] = { 0 };
struct Exc { Exc() {} virtual const char* what() const { return "boom"; }
             unsigned long long pad[9]; unsigned long long marque = 0x4242424242424242ull; };
static void hexa(const char* pre, unsigned long long v)
{ char b[64]; int i=0; while(*pre) b[i++]=*pre++; b[i++]='0'; b[i++]='x';
  for (int s=60;s>=0;s-=4){unsigned d=(v>>s)&15; b[i++]= d<10?'0'+d:'a'+d-10;} b[i++]='\n'; b[i]=0; OutputDebugStringA(b); }
struct Dtor { int v; Dtor(int x):v(x){} ~Dtor(){ OutputDebugStringA("REPRO: dtor\n"); } };
__attribute__((noinline)) void lance3() { Exc x; hexa("REPRO: objet lance a ", (unsigned long long)&x); throw x; }
__attribute__((noinline)) void lance2() { Dtor d(2); lance3(); }
__attribute__((noinline)) void lance1() { Dtor d(1); lance2(); }
#define CATCH_BLOC \
    catch (Exc& e) { OutputDebugStringA("REPRO: dans catch\n"); hexa("REPRO: &e = ", (unsigned long long)&e); \
                     hexa("REPRO: e.marque = ", e.marque); OutputDebugStringA(e.what()); } \
    OutputDebugStringA("\nREPRO: fin OK\n"); ExitProcess(0); return 0;
/* bouchons CRT : __chkstk (pas de sondage pour de petites allocas) et terminate */
__asm__(".globl __chkstk\n__chkstk:\n\tret\n");
extern "C" void __std_terminate() { OutputDebugStringA("REPRO: terminate!\n"); ExitProcess(3); }
