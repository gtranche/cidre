/* Le SEH de x86 32 bits ne passe pas par les tables : la chaine des cadres est
 * dans FS:[0]. h32seh n'exercait qu'un gestionnaire vectorise, qui ne s'en sert
 * pas. Ici on installe un cadre a la main, comme le fait tout compilateur
 * Microsoft, et on verifie qu'il est bien appele.
 *
 * DREDGE meurt sur « Unhandled exception c0000093 » : le CRT leve une
 * exception que Windows attend, et personne ne la rattrape. */
#include <windows.h>
#include <stdio.h>

static int appele, continue_ici;

static EXCEPTION_DISPOSITION __cdecl gestionnaire( EXCEPTION_RECORD *rec, void *cadre,
                                                   CONTEXT *ctx, void *dispatch )
{
    appele++;
    if (rec->ExceptionFlags & (EXCEPTION_UNWINDING | EXCEPTION_EXIT_UNWIND)) return ExceptionContinueSearch;
    /* On reprend apres l'instruction fautive, en detournant l'ecriture. */
    ctx->Eax = (DWORD)(ULONG_PTR)&continue_ici;
    return ExceptionContinueExecution;
}

int main(void)
{
    unsigned ancien, cadre[2];
    unsigned tib0;

    /* Lire FS:[0] avant installation. */
    __asm__ volatile ( "movl %%fs:0, %0" : "=r"(tib0) );
    printf( "FS:[0] au depart = %08x\n", tib0 );

    cadre[0] = tib0;
    cadre[1] = (unsigned)(ULONG_PTR)gestionnaire;
    __asm__ volatile ( "movl %%fs:0, %0\n\t"
                       "movl %1, %%fs:0"
                       : "=&r"(ancien) : "r"(&cadre[0]) : "memory" );

    /* Une ecriture a l'adresse nulle : le gestionnaire doit corriger EAX. */
    __asm__ volatile ( "xorl %%eax, %%eax\n\t"
                       "movl $42, (%%eax)"
                       ::: "eax", "memory" );

    __asm__ volatile ( "movl %0, %%fs:0" :: "r"(ancien) : "memory" );

    printf( "gestionnaire appele %d fois, valeur = %d\n", appele, continue_ici );
    printf( "i386 SEH fs:0 : %s\n", (appele && continue_ici == 42) ? "ok" : "ECHEC" );
    return 0;
}
