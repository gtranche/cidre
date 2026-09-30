#include "commun.h"
extern "C" int mainCRTStartup(int n) { OutputDebugStringA("REPRO alloca\n");
   volatile char* p = (volatile char*)__builtin_alloca(64 + (n & 255)); p[0] = 1;
   try { lance1(); } CATCH_BLOC }
