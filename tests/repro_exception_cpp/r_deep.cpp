#include "commun.h"
extern "C" int mainCRTStartup() { OutputDebugStringA("REPRO deep\n"); try { lance1(); } CATCH_BLOC }
