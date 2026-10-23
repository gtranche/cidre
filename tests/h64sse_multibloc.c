/* Temoin inter-blocs des scalaires SSE et de la partie haute des xmm (FEX : CIDRE_HAUT_NUL=2, etat « haut nul »
 * propage entre les blocs du multibloc). Chaque cas fait entrer la valeur dans un bloc par registre (boucle, diamant,
 * appel, exception, saut indirect) puis applique un scalaire ; les 128 bits du resultat sont imprimes et, quand la
 * valeur x86 est calculable en C, compares. La sortie complete doit etre identique sous Rosetta (reference x86) et
 * sous FEX, avec et sans l'option.
 *
 *   M1  movsd avant une boucle, addsd dans la boucle : haut nul
 *   M2  movupd (haut non nul) avant la boucle, addsd dedans : haut garde
 *   M3  diamant movsd / movupd selon une valeur d'execution, mulsd a la jonction : les deux chemins
 *   M4  boucle ou movhpd charge le haut a la 4e iteration : les addsd suivants le gardent
 *   M5  movss (nul au-dela de 32) puis boucle addsd ; movsd puis boucle addss (bits 32-63 gardes)
 *   M6  appel entre le movsd et le addsd : l'appele charge le haut (movhpd) avant ret
 *   M7  sqrtsd, cvtsi2sd, cvtss2sd, roundsd dans une boucle sur une destination a haut nul, puis non nul
 *   M8  movsd reg,reg (insertion) dans la boucle : haut de la destination garde ; movq xmm,xmm : haut mis a zero
 *   M9  andpd par un masque 128 bits (haut nul garde) ; xorpd par le masque de signe (haut devient 0x8000...)
 *   M10 unpcklpd dans la boucle : le bas recopie en haut
 *   M11 exception (ud2) au milieu de la boucle : le gestionnaire ecrit le haut de xmm0 dans le contexte
 *   M12 saut indirect au milieu d'une boucle avec un haut non nul
 *   M13 NaN (signalisants, silencieux, deux NaN), infinis, denormaux avec et sans FTZ/DAZ, quatre modes d'arrondi,
 *       en boucle et en chaine jusqu'a sqrtsd : valeurs brutes (comparees a Rosetta)
 *   M14 minsd/maxsd en boucle avec zeros signes et NaN
 *
 * x86_64-w64-mingw32-clang -O1 h64sse_multibloc.c -o h64sse_multibloc.exe ; clang -arch x86_64 (Rosetta) idem. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#endif

static int echecs;
static void imprimer( const char *nom, const uint64_t r[2] )
{
    printf( "INFO  %s : %016llx %016llx\n", nom, (unsigned long long)r[1], (unsigned long long)r[0] );
}
static void verifier( const char *nom, const uint64_t r[2], uint64_t bas, uint64_t haut )
{
    int ok = r[0] == bas && r[1] == haut;
    printf( "%s %s : %016llx %016llx (attendu %016llx %016llx)\n", ok ? "OK   " : "ECHEC", nom, (unsigned long long)r[1],
            (unsigned long long)r[0], (unsigned long long)haut, (unsigned long long)bas );
    echecs += !ok;
}
static uint64_t bits_d( double d ) { uint64_t u; memcpy( &u, &d, 8 ); return u; }
static uint32_t bits_f( float f ) { uint32_t u; memcpy( &u, &f, 4 ); return u; }
static double d_bits( uint64_t u ) { double d; memcpy( &d, &u, 8 ); return d; }

static volatile int un = 1, zero = 0;
static const double a = 3.5, b = 1.25, c = 0.375;
static const float fa = 2.5f, fb = 0.75f;
static const uint64_t plein[2] __attribute__((aligned(16))) = { 0x4010000000000000ULL, 0x1122334455667788ULL };
static const uint64_t masque_abs[2] __attribute__((aligned(16))) = { 0x7fffffffffffffffULL, 0x7fffffffffffffffULL };
static const uint64_t masque_signe[2] __attribute__((aligned(16))) = { 0x8000000000000000ULL, 0x8000000000000000ULL };
static const uint64_t haut_m11 = 0xcafe0000beef0000ULL;

/* M6 : appele en asm, charge le haut de xmm0 */
__asm__( ".data\n"
         ".p2align 3\n"
         "cidre_haut_m6:\n\t"
         ".quad 0x1122334455667788\n"
         ".text\n"
         "cidre_charge_haut:\n\t"
         "movhpd cidre_haut_m6(%rip), %xmm0\n\t"
         "ret\n" );

#ifdef _WIN32
static LONG CALLBACK gestionnaire( EXCEPTION_POINTERS *e )
{
    if (e->ExceptionRecord->ExceptionCode != EXCEPTION_ILLEGAL_INSTRUCTION) return EXCEPTION_CONTINUE_SEARCH;
    e->ContextRecord->Xmm0.High = (LONGLONG)haut_m11;
    e->ContextRecord->Rip += 2;
    return EXCEPTION_CONTINUE_EXECUTION;
}
#else
#include <signal.h>
#include <sys/ucontext.h>
static void gestionnaire( int sig, siginfo_t *si, void *p )
{
    ucontext_t *u = p;
    (void)sig; (void)si;
    memcpy( (char *)&u->uc_mcontext->__fs.__fpu_xmm0 + 8, &haut_m11, 8 );
    u->uc_mcontext->__ss.__rip += 2;
}
#endif

int main( void )
{
    uint64_t r[2] __attribute__((aligned(16)));
    char nom[64];

    { /* M1 */
        double x = a; for (int i = 0; i < 10; i++) x += b;
        __asm__ volatile( "movsd %1, %%xmm0\n\tmov $10, %%ecx\n"
                          "1:\n\taddsd %2, %%xmm0\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm0, %0"
                          : "=m"(r) : "m"(a), "m"(b) : "xmm0", "rcx", "cc" );
        verifier( "M1 movsd puis boucle addsd", r, bits_d( x ), 0 );
    }
    { /* M2 */
        double x = 4.0; for (int i = 0; i < 10; i++) x += b;
        __asm__ volatile( "movupd %1, %%xmm1\n\tmov $10, %%ecx\n"
                          "1:\n\taddsd %2, %%xmm1\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm1, %0"
                          : "=m"(r) : "m"(plein), "m"(b) : "xmm1", "rcx", "cc" );
        verifier( "M2 movupd puis boucle addsd", r, bits_d( x ), plein[1] );
    }
    for (int chemin = 0; chemin < 2; chemin++) { /* M3 */
        int sel = chemin ? un : zero;
        __asm__ volatile( "test %3, %3\n\tjz 1f\n\tmovupd %1, %%xmm2\n\tjmp 2f\n"
                          "1:\n\tmovsd %1, %%xmm2\n"
                          "2:\n\tmulsd %2, %%xmm2\n\tmovupd %%xmm2, %0"
                          : "=m"(r) : "m"(plein), "m"(b), "r"(sel) : "xmm2", "cc" );
        snprintf( nom, sizeof(nom), "M3 diamant chemin %s", chemin ? "movupd" : "movsd" );
        verifier( nom, r, bits_d( 4.0 * b ), chemin ? plein[1] : 0 );
    }
    { /* M4 */
        double x = a; for (int i = 0; i < 8; i++) x += b;
        __asm__ volatile( "movsd %1, %%xmm3\n\txor %%ecx, %%ecx\n"
                          "1:\n\tcmp $3, %%ecx\n\tjne 2f\n\tmovhpd %3, %%xmm3\n"
                          "2:\n\taddsd %2, %%xmm3\n\tinc %%ecx\n\tcmp $8, %%ecx\n\tjne 1b\n\tmovupd %%xmm3, %0"
                          : "=m"(r) : "m"(a), "m"(b), "m"(plein[1]) : "xmm3", "rcx", "cc" );
        verifier( "M4 movhpd a la 4e iteration", r, bits_d( x ), plein[1] );
    }
    { /* M5 */
        uint64_t u = bits_f( fa ); double x = d_bits( u ); for (int i = 0; i < 5; i++) x += b;
        __asm__ volatile( "movss %1, %%xmm4\n\tmov $5, %%ecx\n"
                          "1:\n\taddsd %2, %%xmm4\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm4, %0"
                          : "=m"(r) : "m"(fa), "m"(b) : "xmm4", "rcx", "cc" );
        verifier( "M5 movss puis boucle addsd", r, bits_d( x ), 0 );
        uint64_t v = bits_d( a ); uint32_t l32 = (uint32_t)v; float lo; memcpy( &lo, &l32, 4 );
        for (int i = 0; i < 5; i++) lo += fb;
        __asm__ volatile( "movsd %1, %%xmm4\n\tmov $5, %%ecx\n"
                          "1:\n\taddss %2, %%xmm4\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm4, %0"
                          : "=m"(r) : "m"(a), "m"(fb) : "xmm4", "rcx", "cc" );
        verifier( "M5 movsd puis boucle addss", r, (v & 0xffffffff00000000ULL) | bits_f( lo ), 0 );
    }
    { /* M6 */
        __asm__ volatile( "movsd %1, %%xmm0\n\tcall cidre_charge_haut\n\taddsd %2, %%xmm0\n\tmovupd %%xmm0, %0"
                          : "=m"(r) : "m"(a), "m"(b) : "xmm0", "cc", "memory" );
        verifier( "M6 appel qui charge le haut", r, bits_d( a + b ), plein[1] );
        /* meme chose dans une boucle : l'appel est dans le corps */
        double x = a; for (int i = 0; i < 4; i++) x += b;
        __asm__ volatile( "movsd %1, %%xmm0\n\tmov $4, %%esi\n"
                          "1:\n\taddsd %2, %%xmm0\n\tcmp $2, %%esi\n\tjne 2f\n\tcall cidre_charge_haut\n"
                          "2:\n\tdec %%esi\n\tjnz 1b\n\tmovupd %%xmm0, %0"
                          : "=m"(r) : "m"(a), "m"(b) : "xmm0", "rsi", "cc", "memory" );
        verifier( "M6 appel dans la boucle", r, bits_d( x ), plein[1] );
    }
    for (int haut = 0; haut < 2; haut++) { /* M7 */
        static const double d2 = 2.0;
        static const float f3 = 3.0f;
        uint64_t h = haut ? plein[1] : 0;
        __asm__ volatile( "movupd %1, %%xmm5\n\ttest %3, %3\n\tjnz 1f\n\tmovsd %1, %%xmm5\n1:\n\tmov $3, %%ecx\n"
                          "2:\n\tsqrtsd %2, %%xmm5\n\tdec %%ecx\n\tjnz 2b\n\tmovupd %%xmm5, %0"
                          : "=m"(r) : "m"(plein), "m"(d2), "r"(haut) : "xmm5", "rcx", "cc" );
        snprintf( nom, sizeof(nom), "M7 sqrtsd boucle, haut %s", haut ? "plein" : "nul" );
        verifier( nom, r, bits_d( __builtin_sqrt( 2.0 ) ), h );
        __asm__ volatile( "movupd %1, %%xmm5\n\ttest %3, %3\n\tjnz 1f\n\tmovsd %1, %%xmm5\n1:\n\tmov $3, %%ecx\n"
                          "2:\n\tcvtsi2sd %%ecx, %%xmm5\n\tdec %%ecx\n\tjnz 2b\n\tmovupd %%xmm5, %0"
                          : "=m"(r) : "m"(plein), "m"(d2), "r"(haut) : "xmm5", "rcx", "cc" );
        snprintf( nom, sizeof(nom), "M7 cvtsi2sd boucle, haut %s", haut ? "plein" : "nul" );
        verifier( nom, r, bits_d( 1.0 ), h );
        __asm__ volatile( "movupd %1, %%xmm5\n\ttest %3, %3\n\tjnz 1f\n\tmovsd %1, %%xmm5\n1:\n\tmov $3, %%ecx\n"
                          "2:\n\tcvtss2sd %2, %%xmm5\n\tdec %%ecx\n\tjnz 2b\n\tmovupd %%xmm5, %0"
                          : "=m"(r) : "m"(plein), "m"(f3), "r"(haut) : "xmm5", "rcx", "cc" );
        snprintf( nom, sizeof(nom), "M7 cvtss2sd boucle, haut %s", haut ? "plein" : "nul" );
        verifier( nom, r, bits_d( 3.0 ), h );
        __asm__ volatile( "movupd %1, %%xmm5\n\ttest %3, %3\n\tjnz 1f\n\tmovsd %1, %%xmm5\n1:\n\tmov $3, %%ecx\n"
                          "2:\n\troundsd $1, %2, %%xmm5\n\tdec %%ecx\n\tjnz 2b\n\tmovupd %%xmm5, %0"
                          : "=m"(r) : "m"(plein), "m"(a), "r"(haut) : "xmm5", "rcx", "cc" );
        snprintf( nom, sizeof(nom), "M7 roundsd boucle, haut %s", haut ? "plein" : "nul" );
        verifier( nom, r, bits_d( 3.0 ), h );
        /* cvtsd2ss : element 32 bits, les bits 32-63 viennent de la destination */
        __asm__ volatile( "movupd %1, %%xmm5\n\ttest %3, %3\n\tjnz 1f\n\tmovsd %1, %%xmm5\n1:\n\tmov $3, %%ecx\n"
                          "2:\n\tcvtsd2ss %2, %%xmm5\n\tdec %%ecx\n\tjnz 2b\n\tmovupd %%xmm5, %0"
                          : "=m"(r) : "m"(plein), "m"(a), "r"(haut) : "xmm5", "rcx", "cc" );
        snprintf( nom, sizeof(nom), "M7 cvtsd2ss boucle, haut %s", haut ? "plein" : "nul" );
        verifier( nom, r, (plein[0] & 0xffffffff00000000ULL) | bits_f( 3.5f ), h );
    }
    { /* M8 */
        double x = a; for (int i = 0; i < 3; i++) x += b;
        __asm__ volatile( "movupd %1, %%xmm6\n\tmovsd %2, %%xmm7\n\tmov $3, %%ecx\n"
                          "1:\n\tmovsd %%xmm7, %%xmm6\n\taddsd %3, %%xmm7\n\tdec %%ecx\n\tjnz 1b\n\taddsd %3, %%xmm6\n\tmovupd %%xmm6, %0"
                          : "=m"(r) : "m"(plein), "m"(a), "m"(b) : "xmm6", "xmm7", "rcx", "cc" );
        verifier( "M8 movsd reg,reg dans la boucle", r, bits_d( x ), plein[1] );
        __asm__ volatile( "movupd %1, %%xmm6\n\tmov $3, %%ecx\n"
                          "1:\n\tmovq %%xmm6, %%xmm6\n\taddsd %2, %%xmm6\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm6, %0"
                          : "=m"(r) : "m"(plein), "m"(b) : "xmm6", "rcx", "cc" );
        verifier( "M8 movq xmm,xmm dans la boucle", r, bits_d( 4.0 + 3 * b ), 0 );
    }
    { /* M9 */
        static const double neg = -2.5;
        __asm__ volatile( "movsd %1, %%xmm8\n\tmov $2, %%ecx\n"
                          "1:\n\tandpd %2, %%xmm8\n\taddsd %3, %%xmm8\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm8, %0"
                          : "=m"(r) : "m"(neg), "m"(masque_abs), "m"(b) : "xmm8", "rcx", "cc" );
        verifier( "M9 andpd masque abs", r, bits_d( 2.5 + 2 * b ), 0 );
        __asm__ volatile( "movsd %1, %%xmm8\n\tmov $3, %%ecx\n"
                          "1:\n\txorpd %2, %%xmm8\n\taddsd %3, %%xmm8\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm8, %0"
                          : "=m"(r) : "m"(a), "m"(masque_signe), "m"(b) : "xmm8", "rcx", "cc" );
        /* x = 3.5 ; -3.5+1.25 = -2.25 ; 2.25+1.25 = 3.5 ; -3.5+1.25 = -2.25 ; haut : signe bascule trois fois */
        verifier( "M9 xorpd masque signe", r, bits_d( -2.25 ), 0x8000000000000000ULL );
    }
    { /* M10 */
        double x = a; for (int i = 0; i < 2; i++) x += b;
        __asm__ volatile( "movsd %1, %%xmm9\n\tmov $2, %%ecx\n"
                          "1:\n\tunpcklpd %%xmm9, %%xmm9\n\taddsd %2, %%xmm9\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm9, %0"
                          : "=m"(r) : "m"(a), "m"(b) : "xmm9", "rcx", "cc" );
        verifier( "M10 unpcklpd dans la boucle", r, bits_d( x ), bits_d( a + b ) );
    }
    { /* M11 */
#ifdef _WIN32
        void *g = AddVectoredExceptionHandler( 1, gestionnaire );
#else
        struct sigaction sa = { 0 };
        sa.sa_sigaction = gestionnaire; sa.sa_flags = SA_SIGINFO;
        sigaction( SIGILL, &sa, NULL );
#endif
        double x = a; for (int i = 0; i < 4; i++) x += b;
        __asm__ volatile( "movsd %1, %%xmm0\n\tmov $4, %%ecx\n"
                          "1:\n\taddsd %2, %%xmm0\n\tcmp $2, %%ecx\n\tjne 2f\n\tud2\n"
                          "2:\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm0, %0"
                          : "=m"(r) : "m"(a), "m"(b) : "xmm0", "rcx", "cc", "memory" );
        verifier( "M11 exception qui ecrit le haut", r, bits_d( x ), haut_m11 );
#ifdef _WIN32
        RemoveVectoredExceptionHandler( g );
#endif
    }
    { /* M12 */
        double x = 4.0; for (int i = 0; i < 3; i++) x += b;
        __asm__ volatile( "movsd %2, %%xmm10\n\tmov $3, %%ecx\n\tlea 2f(%%rip), %%rax\n\tmovupd %1, %%xmm10\n\tjmp *%%rax\n"
                          "1:\n\tmovsd %2, %%xmm10\n"
                          "2:\n\taddsd %3, %%xmm10\n\tdec %%ecx\n\tjz 3f\n\tmovupd %%xmm10, %0\n\tjmp 2b\n"
                          "3:\n\tmovupd %%xmm10, %0"
                          : "=m"(r) : "m"(plein), "m"(a), "m"(b) : "xmm10", "rax", "rcx", "cc" );
        verifier( "M12 saut indirect au milieu de la boucle", r, bits_d( x ), plein[1] );
    }
    { /* M13 : valeurs brutes, comparees a Rosetta */
        static const uint64_t vals[] = {
            0x7ff4000000000001ULL, /* NaN signalisant */
            0x7ff8000000000002ULL, /* NaN silencieux */
            0xfff8000000000003ULL, /* NaN silencieux negatif */
            0x7ff0000000000000ULL, /* +inf */
            0xfff0000000000000ULL, /* -inf */
            0x0000000000000001ULL, /* plus petit denormal */
            0x000fffffffffffffULL, /* plus grand denormal */
            0x0010000000000000ULL, /* plus petit normal */
            0x8000000000000000ULL, /* -0 */
            0x3ff0000000000001ULL, /* 1 + ulp */
            0x4340000000000001ULL, /* 2^53 + 2 */
        };
        static const char *ops[] = { "addsd", "subsd", "mulsd", "divsd", "minsd", "maxsd", "sqrtsd" };
        static const uint32_t mxcsrs[] = { 0x1f80, 0x3f80, 0x5f80, 0x7f80, 0x9fc0 };
        uint32_t mx_orig; __asm__ volatile( "stmxcsr %0" : "=m"(mx_orig) );
        for (unsigned m = 0; m < sizeof(mxcsrs) / sizeof(*mxcsrs); m++)
            for (unsigned o = 0; o < sizeof(ops) / sizeof(*ops); o++)
                for (unsigned i = 0; i < sizeof(vals) / sizeof(*vals); i++)
                    for (unsigned j = 0; j < sizeof(vals) / sizeof(*vals); j += 2)
                    {
                        uint64_t x = vals[i], y = vals[j]; uint32_t mx = mxcsrs[m], st;
                        /* deux tours de boucle : la deuxieme operation voit le resultat de la premiere par registre */
#define M13( OP )                                                                                                            \
                        __asm__ volatile( "ldmxcsr %4\n\tmovsd %2, %%xmm11\n\tmovsd %3, %%xmm12\n\tmov $2, %%ecx\n"  \
                                          "1:\n\t" OP " %%xmm12, %%xmm11\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm11, %0\n\t" \
                                          "stmxcsr %1\n\tldmxcsr %5"                                                 \
                                          : "=m"(r), "=m"(st) : "m"(x), "m"(y), "m"(mx), "m"(mx_orig)                \
                                          : "xmm11", "xmm12", "rcx", "cc" );
                        switch (o) {
                        case 0: M13( "addsd" ) break; case 1: M13( "subsd" ) break; case 2: M13( "mulsd" ) break;
                        case 3: M13( "divsd" ) break; case 4: M13( "minsd" ) break; case 5: M13( "maxsd" ) break;
                        case 6: M13( "sqrtsd" ) break;
                        }
                        snprintf( nom, sizeof(nom), "M13 %s mx%04x %016llx %016llx", ops[o], mx, (unsigned long long)x,
                                  (unsigned long long)y );
                        imprimer( nom, r );
                        if (r[1]) { printf( "ECHEC %s : haut non nul\n", nom ); echecs++; }
                    }
        /* chaine 32 bits et croisement : movss, addss, mulss, sqrtss, puis cvtss2sd et addsd en boucle */
        for (unsigned m = 0; m < sizeof(mxcsrs) / sizeof(*mxcsrs); m++)
        {
            static const float f1 = 1.1f, f2 = 3.3e-39f; /* f2 denormal */
            uint32_t mx = mxcsrs[m];
            __asm__ volatile( "ldmxcsr %3\n\tmovss %1, %%xmm13\n\tmov $3, %%ecx\n"
                              "1:\n\taddss %2, %%xmm13\n\tmulss %1, %%xmm13\n\tsqrtss %%xmm13, %%xmm13\n\tdec %%ecx\n\tjnz 1b\n\t"
                              "cvtss2sd %%xmm13, %%xmm14\n\taddsd %%xmm14, %%xmm14\n\tunpcklps %%xmm13, %%xmm14\n\t"
                              "movupd %%xmm14, %0\n\tldmxcsr %4"
                              : "=m"(r) : "m"(f1), "m"(f2), "m"(mx), "m"(mx_orig) : "xmm13", "xmm14", "rcx", "cc" );
            snprintf( nom, sizeof(nom), "M13 chaine 32/64 mx%04x", mx );
            imprimer( nom, r );
        }
    }
    { /* M14 */
        static const double z = 0.0, mz = -0.0;
        static const uint64_t qnan = 0x7ff8000000000005ULL;
        __asm__ volatile( "movsd %1, %%xmm15\n\tmov $3, %%ecx\n"
                          "1:\n\tminsd %2, %%xmm15\n\tmaxsd %1, %%xmm15\n\tminsd %3, %%xmm15\n\tdec %%ecx\n\tjnz 1b\n\tmovupd %%xmm15, %0"
                          : "=m"(r) : "m"(z), "m"(mz), "m"(qnan) : "xmm15", "rcx", "cc" );
        imprimer( "M14 minsd/maxsd zeros signes et NaN", r );
        if (r[1]) { printf( "ECHEC M14 : haut non nul\n" ); echecs++; }
    }

    printf( "%s : %d echec(s)\n", echecs ? "ECHEC" : "OK", echecs );
    return echecs;
}
