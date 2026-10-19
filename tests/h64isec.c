/* RtlIsEcCode sur des adresses hors de l'espace utilisateur : FALSE, sans faute.
 *   x86_64-w64-mingw32-gcc -O1 -o h64isec.exe h64isec.c */
#include <windows.h>
#include <stdio.h>
int main( void )
{
    BOOLEAN (WINAPI *p)(ULONG_PTR) = (void *)GetProcAddress( GetModuleHandleA( "ntdll" ), "RtlIsEcCode" );
    const ULONG_PTR a[] = { 0x20074e904cb80ULL, 0xffff800000000000ULL, 0x800000000000ULL, (ULONG_PTR)GetProcAddress( GetModuleHandleA( "kernelbase" ), "GetLastError" ) };
    int i;
    if (!p) { printf( "RtlIsEcCode absent\n" ); return 1; }
    for (i = 0; i < 4; i++) printf( "RtlIsEcCode(%p) = %d\n", (void *)a[i], p( a[i] ) );
    printf( "h64isec : fini\n" );
    return 0;
}
