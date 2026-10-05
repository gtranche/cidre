/*
 * __emutls_get_address sans x18.
 *
 * clang traduit un `__thread` sur Windows ARM par « ldr x9, [x18, #0x58] » -- le
 * ThreadLocalStoragePointer du TEB. Sur macOS x18 ne survit pas, donc tout acces
 * a une variable `__thread` dans un binaire ARM64EC se bloque ou faute (mesure :
 * vkd3d_dbg_sprintf plante en lisant [x18,#0x58]). Le correctif 0069 ne corrige
 * que NtCurrentTeb(), pas la codegen `__thread` de clang.
 *
 * En compilant avec -femulated-tls, clang n'emet plus l'acces x18 : chaque acces
 * passe par un appel a __emutls_get_address(controle). On fournit ce runtime en
 * TLS Win32 -- que le Wine corrige sert sans passer par x18. Meme principe que
 * cxa_globals_sans_x18.c. Passe a l'edition de liens, il gagne.
 *
 * ABI emutls (LLVM/compiler-rt) : controle = {taille, alignement, index/adresse,
 * valeur modele}. L'index, nul au depart, est attribue a la premiere demande ;
 * chaque fil garde un tableau de pointeurs indexe par cet index.
 */
#include <windows.h>
#include <string.h>

struct emutls_control
{
    size_t size;
    size_t align;
    union { size_t index; void *address; } object;
    void *value;
};

struct emutls_array
{
    size_t size;
    void *data[];
};

static DWORD cle = TLS_OUT_OF_INDEXES;
static volatile LONG64 compteur;

static DWORD obtenir_cle(void)
{
    DWORD neuve, ancienne = cle;

    if (ancienne != TLS_OUT_OF_INDEXES) return ancienne;
    if ((neuve = TlsAlloc()) == TLS_OUT_OF_INDEXES) return TLS_OUT_OF_INDEXES;
    ancienne = InterlockedCompareExchange((LONG volatile *)&cle, neuve, TLS_OUT_OF_INDEXES);
    if (ancienne != TLS_OUT_OF_INDEXES) { TlsFree(neuve); return ancienne; }
    return neuve;
}

static size_t index_de(struct emutls_control *c)
{
    size_t vu = c->object.index;
    LONG64 neuf, vainqueur;

    if (vu) return vu;
    neuf = InterlockedIncrement64(&compteur);
    vainqueur = InterlockedCompareExchange64((LONG64 volatile *)&c->object.index, neuf, 0);
    return vainqueur ? (size_t)vainqueur : (size_t)neuf;
}

void *__emutls_get_address(struct emutls_control *c)
{
    size_t idx = index_de(c);
    DWORD k = obtenir_cle();
    struct emutls_array *arr;
    void *obj;

    if (k == TLS_OUT_OF_INDEXES) return NULL;

    arr = TlsGetValue(k);
    if (!arr || arr->size < idx)
    {
        size_t n = idx + 16;
        size_t octets = sizeof(struct emutls_array) + n * sizeof(void *);
        struct emutls_array *neuf = arr
            ? HeapReAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, arr, octets)
            : HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, octets);
        if (!neuf) return NULL;
        neuf->size = n;
        arr = neuf;
        TlsSetValue(k, arr);
    }

    obj = arr->data[idx - 1];
    if (!obj)
    {
        /* Jamais libere : on ne connait pas la fin du fil. Quelques octets/fil. */
        obj = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, c->size ? c->size : 1);
        if (!obj) return NULL;
        if (c->value) memcpy(obj, c->value, c->size);
        arr->data[idx - 1] = obj;
    }
    return obj;
}
