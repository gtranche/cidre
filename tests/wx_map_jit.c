/* Le basculement W^X par page ne peut pas marcher a plusieurs fils : un fil qui
 * ecrit une page de code la rend non executable pour tous les autres. macOS
 * offre le bon mecanisme, APRR, qui est *par fil*. On verifie ici les trois
 * points dont depend le portage :
 *   1. MAP_JIT peut-il etre pose en MAP_FIXED sur une reservation ?
 *   2. mprotect sur une region MAP_JIT la casse-t-il ?
 *   3. deux fils peuvent-ils etre simultanement, l'un en ecriture, l'autre en
 *      execution, sur la meme page ?
 */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <pthread.h>
#include <errno.h>
#include <stdatomic.h>
#include <unistd.h>

static const unsigned int retourne_42[] = { 0xd2800540, 0xd65f03c0 }; /* mov x0,#42 ; ret */
static unsigned int *code;
static atomic_int pret, stop, tours_ecriture, tours_execution;

static void *fil_ecriture( void *p )
{
    pthread_jit_write_protect_np( 0 );
    atomic_fetch_add( &pret, 1 );
    while (!atomic_load( &stop ))
    {
        code[2] = 0xd503201f; /* nop */
        atomic_fetch_add( &tours_ecriture, 1 );
    }
    return NULL;
}

static void *fil_execution( void *p )
{
    pthread_jit_write_protect_np( 1 );
    atomic_fetch_add( &pret, 1 );
    while (!atomic_load( &stop ))
    {
        if (((int (*)(void))code)() != 42) { printf("  mauvaise valeur\n"); return NULL; }
        atomic_fetch_add( &tours_execution, 1 );
    }
    return NULL;
}

int main(void)
{
    size_t t = 16384;
    void *res, *p;
    pthread_t a, b;

    /* 1. reservation puis MAP_JIT par-dessus */
    res = mmap( NULL, t * 4, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0 );
    printf( "reservation PROT_NONE      %s\n", res == MAP_FAILED ? strerror(errno) : "ok" );
    p = mmap( res, t, PROT_READ | PROT_WRITE | PROT_EXEC,
              MAP_PRIVATE | MAP_ANON | MAP_JIT | MAP_FIXED, -1, 0 );
    printf( "MAP_JIT en MAP_FIXED       %s\n", p == MAP_FAILED ? strerror(errno) : "ok" );
    if (p == MAP_FAILED)
    {
        p = mmap( NULL, t, PROT_READ | PROT_WRITE | PROT_EXEC,
                  MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0 );
        printf( "MAP_JIT sans adresse       %s\n", p == MAP_FAILED ? strerror(errno) : "ok" );
        if (p == MAP_FAILED) return 1;
    }
    code = p;

    /* 2. ecrire puis executer, sur le meme fil */
    pthread_jit_write_protect_np( 0 );
    memcpy( code, retourne_42, sizeof(retourne_42) );
    pthread_jit_write_protect_np( 1 );
    __builtin___clear_cache( (char *)code, (char *)code + t );
    printf( "ecriture puis execution    -> %d\n", ((int (*)(void))code)() );

    /* 3. mprotect sur une region MAP_JIT */
    printf( "mprotect RWX sur MAP_JIT   %s\n",
            mprotect( code, t, PROT_READ|PROT_WRITE|PROT_EXEC ) ? strerror(errno) : "ok" );
    printf( "execution apres mprotect   -> %d\n", ((int (*)(void))code)() );

    /* 4. deux fils, l'un ecrit, l'autre execute, en meme temps */
    pthread_create( &a, NULL, fil_ecriture, NULL );
    pthread_create( &b, NULL, fil_execution, NULL );
    while (atomic_load( &pret ) < 2) usleep( 1000 );
    usleep( 200000 );
    atomic_store( &stop, 1 );
    pthread_join( a, NULL ); pthread_join( b, NULL );
    printf( "en parallele : %d ecritures, %d executions\n",
            atomic_load( &tours_ecriture ), atomic_load( &tours_execution ) );
    return 0;
}
