/* « push %esp » empile la valeur d'ESP *avant* la decrementation. C'est une
 * bizarrerie documentee du 386 (le 8086 faisait l'inverse), et RtlUnwind s'en
 * sert pour passer l'adresse du contexte qu'il vient de construire :
 *
 *     leal -(0x2cc+8)(%esp),%esp   ; place pour le contexte
 *     ...                          ; RtlCaptureContext le remplit
 *     pushl %esp                   ; 5e argument = adresse du contexte
 *
 * Empiler la valeur decrementee donne une case qui contient sa propre adresse :
 * le contexte est alors lu quatre octets trop bas, ContextFlags tombe sur le
 * mot d'avant, et l'etat x87 de l'invite est restaure depuis n'importe quoi. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    unsigned avant, empile, apres;
    unsigned avant16, empile16;

    __asm__ volatile( "movl %%esp, %0\n\t"
                      "pushl %%esp\n\t"
                      "popl %1\n\t"
                      "movl %%esp, %2"
                      : "=&r"(avant), "=&r"(empile), "=&r"(apres) :: "memory" );
    printf( "push %%esp : esp avant = %08x, valeur empilee = %08x, esp apres = %08x\n",
            avant, empile, apres );

    /* La variante 16 bits, meme regle. */
    __asm__ volatile( "movl %%esp, %0\n\t"
                      ".byte 0x66\n\t pushl %%esp\n\t"
                      ".byte 0x66\n\t popl %1\n\t"
                      : "=&r"(avant16), "=&r"(empile16) :: "memory" );

    printf( "i386 push esp : %s\n", (empile == avant && apres == avant) ? "ok" : "ECHEC" );
    return 0;
}
