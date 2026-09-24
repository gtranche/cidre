/* Deux questions, une mesure.
 *
 * 1. Les bits de poids faible de TPIDRRO_EL0 portent-ils le numero de coeur ?
 *    Si oui, la valeur change quand le fil migre, et la cle du paragraphe 214
 *    doit etre masquee -- sinon la table des TEB perd son entree au premier
 *    changement de coeur.
 *
 * 2. Le stockage local d'un fil est-il atteignable a
 *    « (TPIDRRO_EL0 & ~7) + 8 * cle » ? Si oui, NtCurrentTeb() redevient deux
 *    instructions, sans appel ni sondage.
 */
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

static inline uint64_t brut(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(v));
    return v;
}

static pthread_key_t cle;

static void *fil(void *arg)
{
    uint64_t depart = brut(), masque = depart & ~7ULL;
    uint64_t bits_vus = depart & 7ULL;
    long i;
    void *tesse;

    pthread_setspecific(cle, (void *)0xDEADBEEFCAFEULL);

    for (i = 0; i < 300000000L; i++) {
        uint64_t v = brut();
        bits_vus |= (v & 7ULL);
        if ((v & ~7ULL) != masque) {
            printf("  fil %s : la partie HAUTE a change apres %ld tours\n", (char *)arg, i);
            return NULL;
        }
    }
    printf("  fil %s : partie haute STABLE sur %ld tours ; bits bas vus : 0x%llx\n",
           (char *)arg, i, (unsigned long long)bits_vus);

    /* Le stockage local est-il a l'adresse attendue ? */
    tesse = *(void **)((char *)(masque) + 8 * (unsigned)cle);
    printf("  fil %s : cle=%u, [(tpidrro & ~7) + 8*cle] = %p %s\n",
           (char *)arg, (unsigned)cle, tesse,
           tesse == (void *)0xDEADBEEFCAFEULL ? "<-- CONCORDE" : "(ne concorde pas)");
    return NULL;
}

int main(void)
{
    pthread_t a, b;
    pthread_key_create(&cle, NULL);
    printf("cle pthread = %u\n", (unsigned)cle);
    pthread_create(&a, NULL, fil, "A");
    pthread_create(&b, NULL, fil, "B");
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    return 0;
}
