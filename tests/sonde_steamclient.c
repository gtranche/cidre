/* Le steamclient.dylib du client macOS est-il utilisable depuis un processus
 * x86_64 traduit ? C'est la condition de base d'un pont lsteamclient : si ce
 * programme repond, le reste est du travail ; s'il ne repond pas, l'idee meurt.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void *(*fn_create)(const char *version, int *err);

int main(int argc, char **argv)
{
   const char *chemin = (argc > 1) ? argv[1] :
      "/Users/gtranche/Library/Application Support/Steam/Steam.AppBundle/Steam/"
      "Contents/MacOS/steamclient.dylib";
   /* Les versions que reclame un jeu recent, de la plus recente a la plus ancienne. */
   static const char *versions[] = {
      "SteamClient021", "SteamClient020", "SteamClient019", "SteamClient017", NULL
   };
   void *h;
   fn_create creer;
   int i;

   printf("architecture du programme : %zu bits\n", sizeof(void *) * 8);

   h = dlopen(chemin, RTLD_NOW | RTLD_LOCAL);
   if (!h) {
      printf("dlopen a echoue : %s\n", dlerror());
      return 1;
   }
   printf("dlopen : ok\n");

   creer = (fn_create)dlsym(h, "CreateInterface");
   if (!creer) {
      printf("CreateInterface introuvable : %s\n", dlerror());
      return 1;
   }
   printf("CreateInterface : trouve a %p\n", (void *)creer);

   for (i = 0; versions[i]; i++) {
      int err = 0;
      void *iface = creer(versions[i], &err);
      printf("  %s -> %p (err=%d)\n", versions[i], iface, err);
   }
   return 0;
}
