#include <windows.h>
#include <stdio.h>
#include <limits.h>
/* Réplique FIDÈLE du mécanisme MSVC thread-safe static, d'après le désassemblage DbD. */
static int _Init_global_epoch = INT_MIN;     /* .data, initial INT_MIN */
static __thread int _Init_thread_epoch = INT_MIN;  /* TLS, modèle INT_MIN */
static CRITICAL_SECTION cs;

static void init_thread_header(volatile int* guard){
    EnterCriticalSection(&cs);
    if(*guard == 0){ *guard = -1; }                 /* on revendique l'init */
    else if(*guard == -1){                          /* un autre initialise : on attend */
        while(*guard == -1){ LeaveCriticalSection(&cs); Sleep(0); EnterCriticalSection(&cs); }
        _Init_thread_epoch = _Init_global_epoch;
    } else { _Init_thread_epoch = _Init_global_epoch; }
    LeaveCriticalSection(&cs);
}
static void init_thread_footer(volatile int* guard){
    EnterCriticalSection(&cs);
    ++_Init_global_epoch;
    *guard = _Init_global_epoch;
    _Init_thread_epoch = _Init_global_epoch;
    LeaveCriticalSection(&cs);
}
/* le singleton */
typedef struct { int magic; char pad[0xfa0-4]; } S;
static volatile int guard_X = 0;
static S* ptr_X = 0;
static S storage_X;
static S* get_X(void){
    if(guard_X > _Init_thread_epoch){               /* cmp [guard], epoch ; jg init */
        init_thread_header(&guard_X);
        if(guard_X == -1){
            storage_X.magic = 0xCAFE;               /* "constructeur" */
            ptr_X = &storage_X;                      /* mov [singleton], ptr */
            init_thread_footer(&guard_X);
        }
    }
    return ptr_X;
}
volatile int worker_result = -1;
static DWORD WINAPI worker(void* p){ S* s=get_X(); worker_result = s ? s->magic : 0; return 0; }

int main(void){
    InitializeCriticalSection(&cs);
    /* Scénario 1 : le worker est le PREMIER à accéder (comme le fil de chargement DbD) */
    HANDLE h=CreateThread(0,0,worker,0,0,0); WaitForSingleObject(h,4000);
    printf("S1 (worker premier) : ptr=%p magic=0x%x\n",(void*)ptr_X,(unsigned)worker_result);

    /* Scénario 2 : plusieurs threads qui initialisent d'autres statics d'abord, puis accèdent */
    /* simulate: le thread bump son epoch via un autre static, PUIS lit un static jamais initialisé */
    printf(ptr_X ? "=> S1 OK\n" : "=> S1 NUL = reproduit !\n");
    return 0;
}
