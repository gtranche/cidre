/* Le « GetPC trick » : une instruction x87 puis fnstenv, et l'image contient
 * l'adresse de cette instruction (FIP). Les compilateurs JIT s'en servent pour
 * connaitre leur propre EIP sans appel. Si l'emulateur rend zero, tout ce qui
 * en decoule est une adresse fausse. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    unsigned env[7];
    unsigned fip, attendu;

    __asm__ volatile (
        "fldz\n"
        "1: fnstenv %0\n"
        "movl $1b, %1\n"
        : "=m"(env), "=r"(attendu) :: "memory" );

    fip = env[3];
    printf( "control=%04x status=%04x tag=%04x\n", env[0] & 0xffff, env[1] & 0xffff, env[2] & 0xffff );
    printf( "FIP = %08x, attendu %08x\n", fip, attendu );
    printf( "FCS = %08x, FDP = %08x, FDS = %08x\n", env[4], env[5], env[6] );
    /* FEX amont range zero dans ce champ (X87FNSTENV, « Instruction Offset ») :
     * ce n'est pas une regression du portage, mais un manque a connaitre --
     * tout programme qui lit son propre EIP par la lira zero. */
    printf( "i386 fnstenv : FIP=%s (limite connue de FEX amont)\n", fip ? "emule" : "nul" );
    return 0;
}
