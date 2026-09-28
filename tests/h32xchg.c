/* RtlUnwind construit son contexte avec « xchgl %eax,(%esp) ». Un xchg a
 * operande memoire porte un LOCK implicite ; FEX annonce au demarrage
 * « Host CPU doesn't support atomics », donc il passe par un chemin de repli.
 * On verifie que l'echange rend bien les deux valeurs. */
#include <windows.h>
#include <stdio.h>

static int mauvais;

static void verifier( const char *quoi, unsigned a, unsigned b )
{
    if (a != b) { printf( "%-30s : %08x != %08x\n", quoi, a, b ); mauvais++; }
}

int main(void)
{
    unsigned m = 0x11112222, r = 0x33334444;
    unsigned pile[4], eax_apres, pile_apres;

    __asm__ volatile( "xchgl %0, %1" : "+r"(r), "+m"(m) );
    verifier( "xchg reg,mem : registre", r, 0x11112222 );
    verifier( "xchg reg,mem : memoire", m, 0x33334444 );

    /* La sequence exacte de RtlUnwind : empiler eax, calculer un pointeur,
     * puis echanger avec le sommet de pile. */
    pile[0] = 0;
    /* Tout en registres : une operande memoire de gcc serait relative a esp,
     * que nos push deplacent. */
    __asm__ volatile( "movl $0xdeadbeef, %%eax\n\t"
                      "pushl %%eax\n\t"
                      "leal 4(%%esp), %%eax\n\t"
                      "xchgl %%eax, (%%esp)\n\t"
                      "movl %%eax, %0\n\t"
                      "popl %1"
                      : "=&r"(eax_apres), "=&r"(pile_apres) :: "eax", "memory" );
    verifier( "sequence RtlUnwind : eax", eax_apres, 0xdeadbeef );
    if (pile_apres == 0) { printf( "sequence RtlUnwind : sommet de pile nul\n" ); mauvais++; }
    (void)pile;

    /* xchg avec une operande memoire par registre de base. */
    m = 0xaaaabbbb; r = 0xccccdddd;
    __asm__ volatile( "xchgl %0, (%2)" : "+r"(r), "+m"(m) : "r"(&m) : "memory" );
    verifier( "xchg reg,(reg) : registre", r, 0xaaaabbbb );
    verifier( "xchg reg,(reg) : memoire", m, 0xccccdddd );

    /* lock xchg explicite */
    m = 0x01020304; r = 0x05060708;
    __asm__ volatile( "lock xchgl %0, %1" : "+r"(r), "+m"(m) );
    verifier( "lock xchg : registre", r, 0x01020304 );
    verifier( "lock xchg : memoire", m, 0x05060708 );

    printf( "i386 xchg : %s (%d anomalies)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
