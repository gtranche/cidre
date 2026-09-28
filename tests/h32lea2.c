/* RtlUnwind fait « pushl %eax ; leal 4(%esp),%eax » pour se fabriquer un
 * pointeur sur le contexte. Si le deplacement se perd, tout le contexte est
 * decale de quatre octets -- et ContextFlags lit le mot d'avant. */
#include <windows.h>
#include <stdio.h>

static int mauvais;
static void verifier( const char *quoi, unsigned a, unsigned b )
{
    if (a != b) { printf( "%-34s : %08x != %08x\n", quoi, a, b ); mauvais++; }
}

int main(void)
{
    unsigned avant, apres, base, deplace;
    unsigned tab[8] = { 0, 1, 2, 3, 4, 5, 6, 7 };

    /* lea avec deplacement sur esp */
    __asm__ volatile( "movl %%esp, %0\n\t"
                      "pushl %%eax\n\t"
                      "leal 4(%%esp), %%eax\n\t"
                      "movl %%eax, %1\n\t"
                      "popl %%eax\n\t"
                      "movl %%esp, %2"
                      : "=&r"(avant), "=&r"(apres), "=&r"(base) :: "eax", "memory" );
    verifier( "lea 4(esp) apres push", apres, avant );
    verifier( "esp restaure", base, avant );

    /* lea avec deplacement sur un registre ordinaire */
    __asm__ volatile( "leal 12(%1), %0" : "=r"(deplace) : "r"(tab) );
    verifier( "lea 12(reg)", deplace, (unsigned)(ULONG_PTR)tab + 12 );

    /* lea avec base + index + deplacement */
    __asm__ volatile( "leal 8(%1,%2,4), %0" : "=r"(deplace) : "r"(tab), "r"(3) );
    verifier( "lea 8(reg,reg,4)", deplace, (unsigned)(ULONG_PTR)tab + 8 + 12 );

    /* lea deplacement negatif */
    __asm__ volatile( "leal -16(%1), %0" : "=r"(deplace) : "r"(tab) );
    verifier( "lea -16(reg)", deplace, (unsigned)(ULONG_PTR)tab - 16 );

    /* lea sur esp avec un grand deplacement, comme RtlUnwind */
    __asm__ volatile( "movl %%esp, %0\n\t"
                      "leal -(0x2cc+8)(%%esp), %%eax\n\t"
                      "movl %%eax, %1"
                      : "=&r"(avant), "=&r"(apres) :: "eax" );
    verifier( "lea -(0x2cc+8)(esp)", apres, avant - 0x2d4 );

    printf( "i386 lea deplacement : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
