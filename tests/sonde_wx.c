/* Sonde du basculement ecriture/execution sur lequel repose l'emulation x86-64.
 *
 * Wine pose le code de l'emulateur dans des pages MAP_JIT. macOS n'y accorde
 * qu'un droit a la fois, par fil : ecrire OU executer. Wine ne demande pas a
 * l'emulateur de dire lequel il veut ; il attend la faute, regarde si c'etait
 * une ecriture ou une execution, donne ce droit au fil (dans le gestionnaire
 * de signal) et reprend.
 *
 * Ce programme rejoue ce mecanisme hors de Wine et dit, pour la machine ou il
 * tourne :
 *   - comment le noyau decrit chaque faute (signal, registre de syndrome ESR) ;
 *   - si le droit donne dans le gestionnaire survit au retour du signal ;
 *   - si la reprise aboutit, ou si la meme faute revient sans fin.
 *
 * Chaque essai tourne dans un processus a part, borne dans le temps : une
 * boucle ou un plantage dans l'un ne cache pas les autres. C'est `cidre doctor`
 * qui le lance.
 *
 *   cc -arch arm64 -O1 -o sonde-wx sonde_wx.c
 */
#include <errno.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <libkern/OSCacheControl.h>

#define _XOPEN_SOURCE 700
#include <sys/ucontext.h>

static const unsigned int retourne_42[] = { 0xd2800540, 0xd65f03c0 }; /* mov x0,#42 ; ret */
static volatile unsigned int *code;

enum { CLASSE_PAR_ESR, CLASSE_PAR_ADRESSE, HORS_SIGNAL, SANS_BASCULE };

/*
 * Reprise hors du signal. Sur un Mac M4 sous macOS 27, le droit d'executer
 * donne pendant un signal ne tient pas : au retour, le noyau rend au fil le
 * droit d'ecrire qu'il avait a l'arrivee du signal. On le donne donc apres le
 * retour : le gestionnaire met de cote le contexte interrompu et fait reprendre
 * le fil dans un tremplin, qui donne le droit (hors de tout signal, la ou cela
 * marche) puis s'arrete sur un point d'arret ; le gestionnaire de ce point
 * d'arret remet le contexte mis de cote, registre pour registre. Le fil avait
 * alors deja le droit d'executer : le noyau n'a rien a lui rendre.
 */
struct cadre_wx
{
    unsigned long long magie;
    _STRUCT_ARM_THREAD_STATE64 ss;
    _STRUCT_ARM_NEON_STATE64 ns;
    sigset_t masque;
};
#define MAGIE_WX 0x7872656c61697377ull
extern void tremplin_wx( void );
extern void tremplin_wx_arret( void );
__asm__( ".text\n.p2align 2\n.globl _tremplin_wx\n.globl _tremplin_wx_arret\n"
         "_tremplin_wx:\n\tbl _pthread_jit_write_protect_np\n"
         "_tremplin_wx_arret:\n\tbrk #0x57e\n" );
static int methode;
static volatile int fautes;
static sigjmp_buf sortie;
static char pile_de_signal[65536];

/* Ce que le noyau dit de la premiere faute de l'essai. */
static volatile int premier_signal;
static volatile unsigned long long premier_esr, premier_far, premiere_adresse, premier_pc;

static void faute( int sig, siginfo_t *info, void *ctx )
{
    ucontext_t *uc = ctx;
    unsigned long long esr = uc->uc_mcontext->__es.__esr;
    unsigned long long pc = uc->uc_mcontext->__ss.__pc;
    unsigned long long adresse = (unsigned long long)info->si_addr;
    unsigned int ec = (esr >> 26) & 0x3f;
    int execution;

    if (!fautes)
    {
        premier_signal = sig;
        premier_esr = esr;
        premier_far = uc->uc_mcontext->__es.__far;
        premiere_adresse = adresse;
        premier_pc = pc;
    }
    if (++fautes > 20 || methode == SANS_BASCULE) siglongjmp( sortie, 1 );

    /* Comme Wine : une interruption d'instruction (EC 0x20/0x21) est une
     * execution, le reste une ecriture. Ou bien, sans se fier a l'ESR : on
     * executait si l'adresse fautive est celle de l'instruction. */
    if (methode == CLASSE_PAR_ESR) execution = (ec == 0x20 || ec == 0x21);
    else execution = (adresse == pc);
    if (execution && methode == HORS_SIGNAL)
    {
        /* sous la pile interrompue, zone rouge passee */
        struct cadre_wx *c = (struct cadre_wx *)((uc->uc_mcontext->__ss.__sp - 256 - sizeof(*c)) & ~15ull);

        c->magie = MAGIE_WX;
        c->ss = uc->uc_mcontext->__ss;
        c->ns = uc->uc_mcontext->__ns;
        c->masque = uc->uc_sigmask;
        uc->uc_mcontext->__ss.__pc = (unsigned long long)tremplin_wx;
        uc->uc_mcontext->__ss.__sp = (unsigned long long)c;
        uc->uc_mcontext->__ss.__x[0] = 1;
        /* rien ne doit s'intercaler dans le tremplin, sauf ce qu'il provoque */
        sigfillset( &uc->uc_sigmask );
        sigdelset( &uc->uc_sigmask, SIGTRAP );
        sigdelset( &uc->uc_sigmask, SIGBUS );
        sigdelset( &uc->uc_sigmask, SIGSEGV );
        sigdelset( &uc->uc_sigmask, SIGILL );
        return;
    }
    pthread_jit_write_protect_np( execution );
}

static void arret( int sig, siginfo_t *info, void *ctx )
{
    ucontext_t *uc = ctx;
    struct cadre_wx *c = (struct cadre_wx *)uc->uc_mcontext->__ss.__sp;

    (void)sig; (void)info;
    if (uc->uc_mcontext->__ss.__pc != (unsigned long long)tremplin_wx_arret || c->magie != MAGIE_WX) _exit( 4 );
    uc->uc_mcontext->__ss = c->ss;
    uc->uc_mcontext->__ns = c->ns;
    uc->uc_sigmask = c->masque;
}

static void autre_signal( int sig )
{
    /* Un signal quelconque, pendant lequel on change le droit du fil. */
    pthread_jit_write_protect_np( sig == SIGUSR1 );
}

static void poser_gestionnaires( void )
{
    stack_t pile = { .ss_sp = pile_de_signal, .ss_size = sizeof(pile_de_signal) };
    struct sigaction sa;

    sigaltstack( &pile, NULL );  /* Wine traite ses fautes sur une pile a part */
    memset( &sa, 0, sizeof(sa) );
    sa.sa_sigaction = faute;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction( SIGBUS, &sa, NULL );
    sigaction( SIGSEGV, &sa, NULL );
    sa.sa_sigaction = arret;
    sigaction( SIGTRAP, &sa, NULL );
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = autre_signal;
    sigaction( SIGUSR1, &sa, NULL );
    sigaction( SIGUSR2, &sa, NULL );
}

static void ecrire_le_code( void )
{
    code[0] = retourne_42[0];
    code[1] = retourne_42[1];
    sys_icache_invalidate( (void *)code, sizeof(retourne_42) );
}

static int executer_le_code( void )
{
    return ((int (*)(void))code)();
}

static void decrire_la_faute( void )
{
    printf( " ; 1re faute : signal %d, ESR %#llx (EC %#llx), adresse %s pc",
            premier_signal, premier_esr, (premier_esr >> 26) & 0x3f,
            premiere_adresse == premier_pc ? "=" : "!=" );
    if (premier_far != premiere_adresse) printf( ", FAR != adresse" );
}

/* Les essais. Chacun rend 0 si tout s'est passe comme Wine l'attend. */

static int essai_explicite( void )
{
    pthread_jit_write_protect_np( 0 );
    ecrire_le_code();
    pthread_jit_write_protect_np( 1 );
    if (executer_le_code() != 42) { printf( "mauvaise valeur" ); return 1; }
    printf( "ok" );
    return 0;
}

/* Le fil a le droit d'ecrire et veut executer : le cas ou la machine fautive boucle. */
static int essai_execution( void )
{
    int r = 1;

    pthread_jit_write_protect_np( 0 );
    ecrire_le_code();
    fautes = 0;
    if (!sigsetjmp( sortie, 1 ))
    {
        if (executer_le_code() == 42) { printf( "ok en %d faute(s)", fautes ); r = 0; }
        else printf( "mauvaise valeur" );
    }
    else if (methode == SANS_BASCULE) { printf( "faute attendue" ); r = 0; }
    else printf( "BOUCLE : la faute revient apres %d bascules", fautes - 1 );
    if (fautes) decrire_la_faute();
    return r;
}

/* Le fil a le droit d'executer et veut ecrire. */
static int essai_ecriture( void )
{
    int r = 1;

    pthread_jit_write_protect_np( 1 );
    fautes = 0;
    if (!sigsetjmp( sortie, 1 ))
    {
        ecrire_le_code();
        printf( "ok en %d faute(s)", fautes );
        r = 0;
    }
    else if (methode == SANS_BASCULE) { printf( "faute attendue" ); r = 0; }
    else printf( "BOUCLE : la faute revient apres %d bascules", fautes - 1 );
    if (fautes) decrire_la_faute();
    return r;
}

/* Un droit donne pendant un signal tient-il apres le retour du signal ? */
static int essai_persistance_execution( void )
{
    pthread_jit_write_protect_np( 0 );
    ecrire_le_code();
    kill( getpid(), SIGUSR1 );  /* le gestionnaire donne le droit d'executer */
    methode = SANS_BASCULE;
    fautes = 0;
    if (!sigsetjmp( sortie, 1 ))
    {
        if (executer_le_code() == 42) { printf( "tient" ); return 0; }
        printf( "mauvaise valeur" );
        return 1;
    }
    printf( "NE TIENT PAS : le noyau a remis le droit d'avant le signal" );
    return 1;
}

static int essai_persistance_ecriture( void )
{
    pthread_jit_write_protect_np( 1 );
    kill( getpid(), SIGUSR2 );  /* le gestionnaire donne le droit d'ecrire */
    methode = SANS_BASCULE;
    fautes = 0;
    if (!sigsetjmp( sortie, 1 ))
    {
        ecrire_le_code();
        printf( "tient" );
        return 0;
    }
    printf( "NE TIENT PAS : le noyau a remis le droit d'avant le signal" );
    return 1;
}

/* Le va-et-vient d'un emulateur : ecrire du code, l'executer, recommencer. On
 * verifie au passage que la reprise rend bien tous les registres (la valeur
 * de retour vient de x0, le compteur vit dans un registre preserve). */
static int essai_va_et_vient( void )
{
    enum { TOURS = 2000 };
    struct timespec debut, fin;
    volatile int i;
    double us;

    fautes = 0;
    if (sigsetjmp( sortie, 1 )) { printf( "BOUCLE apres %d tours", i ); decrire_la_faute(); return 1; }
    clock_gettime( CLOCK_MONOTONIC, &debut );
    for (i = 0; i < TOURS; i++)
    {
        fautes = 0;
        ecrire_le_code();
        if (executer_le_code() != 42) { printf( "mauvaise valeur au tour %d", i ); return 1; }
    }
    clock_gettime( CLOCK_MONOTONIC, &fin );
    us = ((fin.tv_sec - debut.tv_sec) * 1e9 + (fin.tv_nsec - debut.tv_nsec)) / 1e3 / TOURS;
    printf( "ok, %d tours, %.1f us par tour", TOURS, us );
    return 0;
}

static const struct
{
    const char *nom;
    int (*essai)( void );
    int methode;
} essais[] =
{
    { "bascule explicite, sans faute             ", essai_explicite, SANS_BASCULE },
    { "faute d'execution, telle que le noyau la dit", essai_execution, SANS_BASCULE },
    { "faute d'ecriture, telle que le noyau la dit ", essai_ecriture, SANS_BASCULE },
    { "droit d'executer donne pendant un signal  ", essai_persistance_execution, SANS_BASCULE },
    { "droit d'ecrire donne pendant un signal    ", essai_persistance_ecriture, SANS_BASCULE },
    { "reprise apres faute d'execution, par l'ESR ", essai_execution, CLASSE_PAR_ESR },
    { "reprise apres faute d'ecriture, par l'ESR  ", essai_ecriture, CLASSE_PAR_ESR },
    { "reprise apres faute d'execution, par le pc ", essai_execution, CLASSE_PAR_ADRESSE },
    { "reprise apres faute d'ecriture, par le pc  ", essai_ecriture, CLASSE_PAR_ADRESSE },
    { "reprise apres faute d'execution, hors signal", essai_execution, HORS_SIGNAL },
    { "reprise apres faute d'ecriture, hors signal ", essai_ecriture, HORS_SIGNAL },
    { "va-et-vient ecrire/executer, dans le signal ", essai_va_et_vient, CLASSE_PAR_ESR },
    { "va-et-vient ecrire/executer, hors signal    ", essai_va_et_vient, HORS_SIGNAL },
};

int main( void )
{
    unsigned int i;
    int echecs = 0;

    setvbuf( stdout, NULL, _IONBF, 0 );
    printf( "pthread_jit_write_protect_supported_np : %d\n", pthread_jit_write_protect_supported_np() );

    for (i = 0; i < sizeof(essais) / sizeof(essais[0]); i++)
    {
        int etat = 0;
        pid_t fils;

        printf( "%s : ", essais[i].nom );
        if (!(fils = fork()))
        {
            alarm( 5 );
            code = mmap( NULL, 16384, PROT_READ | PROT_WRITE | PROT_EXEC,
                         MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0 );
            if (code == MAP_FAILED) { printf( "MAP_JIT refuse : %s", strerror( errno ) ); _exit( 2 ); }
            poser_gestionnaires();
            methode = essais[i].methode;
            _exit( essais[i].essai() );
        }
        waitpid( fils, &etat, 0 );
        if (WIFSIGNALED( etat ))
        {
            if (WTERMSIG( etat ) == SIGALRM) printf( "BLOQUE : pas fini apres 5 s" );
            else printf( "TUE par le signal %d", WTERMSIG( etat ) );
            echecs++;
        }
        else if (WEXITSTATUS( etat )) echecs++;
        printf( "\n" );
    }
    return echecs ? 1 : 0;
}
