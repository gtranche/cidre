#include <windows.h>
#include <stdio.h>
int main(void)
{
    SIZE_T tailles[] = { 0x1000, 0x4000, 0x8000, 0xc000, 0x10000, 0x18000, 0x20000,
                         0x30000, 0x40000, 0x80000, 0x100000 };
    unsigned i;
    for (i = 0; i < sizeof(tailles)/sizeof(tailles[0]); i++)
    {
        void *a, *b;
        SetLastError( 0 );
        a = VirtualAlloc( NULL, tailles[i], MEM_RESERVE, PAGE_NOACCESS );
        b = VirtualAlloc( NULL, tailles[i], MEM_RESERVE, PAGE_READWRITE );
        printf( "%8Ix : NOACCESS=%p  READWRITE=%p\n", tailles[i], a, b );
        if (a) VirtualFree( a, 0, MEM_RELEASE );
        if (b) VirtualFree( b, 0, MEM_RELEASE );
    }
    return 0;
}
