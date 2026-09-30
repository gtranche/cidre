#include "commun.h"
__attribute__((noinline)) int attrape(int n) {
   volatile char* p = (volatile char*)__builtin_alloca(64 + (n & 255)); p[0] = 1;
   Dtor d(9);
   try { lance1(); } catch (Exc& e) { OutputDebugStringA("REPRO: dans catch\n"); hexa("REPRO: &e = ", (unsigned long long)&e);
     hexa("REPRO: e.marque = ", e.marque); OutputDebugStringA(e.what()); return 1; }
   return 0; }
extern "C" int mainCRTStartup(int n) { OutputDebugStringA("REPRO mid\n"); attrape(n); OutputDebugStringA("\nREPRO: fin OK\n"); ExitProcess(0); return 0; }
