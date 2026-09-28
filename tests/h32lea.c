/* Le RIP fautif de DREDGE valait « base + cible » : une adresse de l'hote
 * s'etait glissee dans un registre puis dans un branchement. Le suspect est
 * LEA, qui demande une adresse effective sans acceder a la memoire.
 *
 * On reproduit le motif exact : lea vers un registre, puis call sur ce
 * registre, sans passage par la memoire qui tronquerait a 32 bits. */
#include <windows.h>
#include <stdio.h>

static int __attribute__((noinline)) cible( void ) { return 42; }

int main(void)
{
    int r = 0;
    void *p = (void *)cible;

    /* call direct : temoin */
    printf( "appel direct = %d\n", cible() ); fflush( stdout );

    /* lea puis call indirect sur le meme registre */
    __asm__ volatile ( "leal (%1), %%eax\n\t"
                       "call *%%eax"
                       : "=a"(r) : "r"(p) : "ecx", "edx", "memory" );
    printf( "lea + call = %d\n", r );

    /* lea avec index, la forme que le code compile utilise le plus */
    r = 0;
    __asm__ volatile ( "xorl %%ecx, %%ecx\n\t"
                       "leal (%1,%%ecx,1), %%eax\n\t"
                       "call *%%eax"
                       : "=a"(r) : "r"(p) : "ecx", "edx", "memory" );
    printf( "lea indexe + call = %d\n", r );

    printf( "i386 lea : %s\n", r == 42 ? "ok" : "ECHEC" );
    return 0;
}
