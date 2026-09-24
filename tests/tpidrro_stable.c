/* TPIDRRO_EL0 tient-il la ou x18 tombe ?
 *
 * x18 est efface par macOS a chaque retour du noyau, preemption comprise
 * (paragraphe 144) : aucun point de restauration n'existe. Si un autre
 * registre lisible en mode utilisateur reste stable et propre au fil, il peut
 * servir de cle pour retrouver le TEB, et le code PE d'ARM64 n'a plus besoin
 * de x18.
 *
 * On eprouve donc TPIDRRO_EL0 exactement comme x18 l'a ete : une boucle serree
 * sans appel systeme, qui compare a chaque tour.
 */
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

static inline uint64_t lire_tpidrro(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(v));
    return v;
}

static void *fil(void *arg)
{
    uint64_t depart = lire_tpidrro();
    uint64_t tours = 0;
    long limite = 200000000L;

    printf("  fil %s : TPIDRRO_EL0 = 0x%llx (pthread_self = %p)\n",
           (const char *)arg, (unsigned long long)depart, (void *)pthread_self());

    while (tours < limite) {
        uint64_t v = lire_tpidrro();
        if (v != depart) {
            printf("  fil %s : PERDU apres %llu tours (0x%llx -> 0x%llx)\n",
                   (const char *)arg, (unsigned long long)tours,
                   (unsigned long long)depart, (unsigned long long)v);
            return NULL;
        }
        tours++;
    }
    printf("  fil %s : STABLE sur %ld tours\n", (const char *)arg, limite);
    return NULL;
}

int main(void)
{
    pthread_t a, b;

    printf("TPIDRRO_EL0, deux fils, 200 millions de tours chacun\n");
    pthread_create(&a, NULL, fil, (void *)"A");
    pthread_create(&b, NULL, fil, (void *)"B");
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    return 0;
}
