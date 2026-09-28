/* Unity s'arrete sur « no class object {bcde0395-...} » : l'enumerateur de
 * peripheriques audio. On isole : la DLL se charge-t-elle, et la classe se
 * cree-t-elle, depuis un invite 32 bits ? */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <objbase.h>

static const GUID CLSID_MMDeviceEnumerator =
    { 0xBCDE0395, 0xE52F, 0x467C, { 0x8E,0x3D,0xC4,0x57,0x92,0x91,0x69,0x2E } };
static const GUID IID_IMMDeviceEnumerator =
    { 0xA95664D2, 0x9614, 0x4F35, { 0xA7,0x46,0xDE,0x8D,0xB6,0x36,0x17,0xE6 } };

int main(void)
{
    HMODULE m;
    void *enumerateur = NULL;
    HRESULT hr;

    SetLastError( 0 );
    m = LoadLibraryA( "mmdevapi.dll" );
    printf( "LoadLibrary(mmdevapi) = %p err=%lu\n", (void *)m, GetLastError() ); fflush( stdout );
    if (m) printf( "DllGetClassObject = %p\n", (void *)GetProcAddress( m, "DllGetClassObject" ) );
    fflush( stdout );

    CoInitializeEx( NULL, COINIT_MULTITHREADED );
    hr = CoCreateInstance( &CLSID_MMDeviceEnumerator, NULL, CLSCTX_INPROC_SERVER,
                           &IID_IMMDeviceEnumerator, &enumerateur );
    printf( "CoCreateInstance = %08lx, objet = %p\n", (unsigned long)hr, enumerateur );
    printf( "i386 audio : %s\n", (SUCCEEDED(hr) && enumerateur) ? "ok" : "ECHEC" );
    return 0;
}
