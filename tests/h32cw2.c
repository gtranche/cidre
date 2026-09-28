#include <windows.h>
#include <stdio.h>
static unsigned short lire( void ) { unsigned short c; __asm__ volatile("fnstcw %0":"=m"(c)); return c; }
static void ecrire( unsigned short c ) { __asm__ volatile("fldcw %0"::"m"(c)); }
int main(void)
{
    unsigned short essais[] = { 0x037f, 0x027f, 0x133f, 0x0362 };
    unsigned i, mxcsr, mx2;
    unsigned short avant, apres;
    for (i = 0; i < 4; i++)
    {
        ecrire( essais[i] );
        avant = lire();
        __asm__ volatile("stmxcsr %0":"=m"(mxcsr));
        OutputDebugStringA( "x\n" );
        apres = lire();
        __asm__ volatile("stmxcsr %0":"=m"(mx2));
        printf( "CW %04x -> %04x   MXCSR %08x -> %08x\n", avant, apres, mxcsr, mx2 );
        fflush( stdout );
    }
    ecrire( 0x037f );
    return 0;
}
