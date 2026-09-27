/*
 * __cxa_get_globals sans x18.
 *
 * libc++abi range son etat d'exception dans un « thread_local », et clang le
 * traduit sur Windows ARM par « ldr x9, [x18, #0x58] » -- le
 * ThreadLocalStoragePointer du TEB. Sur macOS x18 ne survit pas, et un throw
 * dans un binaire ARM64EC lie statiquement se bloque (mesure : le programme
 * d'essai tourne indefiniment).
 *
 * Contrairement aux objets de demarrage, la substitution d'une instruction ne
 * s'applique pas : ce n'est pas un jeton mais un vrai pointeur, et il faut cinq
 * instructions pour le retrouver. On fournit donc l'implementation, en TLS
 * Win32 -- que le Wine corrige sert sans passer par x18. Passe a l'edition de
 * liens avant libc++abi, elle gagne.
 *
 * La disposition vient de l'ABI Itanium C++ et de cxa_exception.h de libc++abi :
 * deux champs, le pointeur de pile d'exceptions puis le compteur.
 */
#include <windows.h>

struct globaux_eh
{
    void        *exceptions_attrapees;
    unsigned int exceptions_non_attrapees;
    /* marge : si une version de libc++abi ajoute un champ, il est a zero et non
     * hors de la zone allouee. */
    void        *reserve[2];
};

static DWORD cle = TLS_OUT_OF_INDEXES;

static DWORD obtenir_cle( void )
{
    DWORD neuve, ancienne = cle;

    if (ancienne != TLS_OUT_OF_INDEXES) return ancienne;
    if ((neuve = TlsAlloc()) == TLS_OUT_OF_INDEXES) return TLS_OUT_OF_INDEXES;
    ancienne = InterlockedCompareExchange( (LONG volatile *)&cle, neuve, TLS_OUT_OF_INDEXES );
    if (ancienne != TLS_OUT_OF_INDEXES) { TlsFree( neuve ); return ancienne; }
    return neuve;
}

struct globaux_eh *__cxa_get_globals_fast( void )
{
    DWORD c = cle;
    if (c == TLS_OUT_OF_INDEXES) return NULL;
    return TlsGetValue( c );
}

struct globaux_eh *__cxa_get_globals( void )
{
    DWORD c = obtenir_cle();
    struct globaux_eh *g;

    if (c == TLS_OUT_OF_INDEXES) return NULL;
    if ((g = TlsGetValue( c ))) return g;
    /* Jamais libere : le fil peut lever une exception jusqu'a sa derniere
     * instruction, et libc++abi ne nous previent pas de sa fin. Quelques
     * dizaines d'octets par fil. */
    if (!(g = HeapAlloc( GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*g) ))) return NULL;
    TlsSetValue( c, g );
    return g;
}
