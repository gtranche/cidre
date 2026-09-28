/* ARM demarre volontiers en « flush-to-zero » : un denormal y devient zero.
 * x86 ne le fait pas par defaut. Si l'emulation laisse passer ce mode, un
 * calcul qui doit rendre un tres petit nombre rend zero -- et atan2(0,0)
 * devient une operation invalide, ce que le CRT de Microsoft signale. */
#include <windows.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

static int mauvais;

/* Dans le domaine denormal, un calcul en deux etapes arrondit deux fois : on
 * compare donc a un ulp pres, pas au bit pres. Ce qu'on veut prouver, c'est
 * qu'aucun denormal n'est mis a zero. */
static void verifier( const char *quoi, double obtenu, double attendu )
{
    double ecart = obtenu - attendu;
    int ok = (obtenu != 0.0 || attendu == 0.0) &&
             (ecart == 0.0 || (ecart < 0 ? -ecart : ecart) <= attendu * 1e-14);
    if (!ok) mauvais++;
    printf( "%-34s = %.17g (attendu %.17g) %s\n", quoi, obtenu, attendu, ok ? "" : "<-- ECART" );
}

int main(void)
{
    volatile double petit = 1e-308;      /* normal, tout juste */
    volatile double denorm = 5e-324;     /* le plus petit denormal */
    volatile double deux = 2.0, moitie = 0.5;
    volatile float fd;
    double r;

    verifier( "5e-324 tel quel", denorm, 5e-324 );
    r = denorm * deux;                   verifier( "denormal * 2", r, 1e-323 );
    r = petit * moitie;                  verifier( "1e-308 / 2", r, 5e-309 );
    r = petit * moitie * moitie;         verifier( "1e-308 / 4", r, 2.5e-309 );
    r = denorm + denorm;                 verifier( "denormal + denormal", r, 1e-323 );

    fd = (float)1e-40;                   /* denormal simple precision */
    printf( "float denormal 1e-40 = %.9g %s\n", (double)fd, (fd == 0.0f) ? "<-- ECART (mis a zero)" : "" );
    if (fd == 0.0f) mauvais++;

    /* atan2 sur des denormaux : doit rendre un angle, pas une erreur. */
    r = atan2( denorm, denorm );         verifier( "atan2(denorm,denorm)", r, 0.78539816339744828 );
    r = atan2( denorm, 1.0 );            printf( "atan2(denorm,1) = %.17g\n", r );

    printf( "i386 denormaux : %s (%d ecarts)\n", mauvais ? "ECHEC" : "ok", mauvais );
    return 0;
}
