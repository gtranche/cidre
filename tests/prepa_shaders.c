/* prepa-shaders : outil de la preparation des shaders avant le lancement
 * (tests/preparer_shaders.sh, PREPARATION_SHADERS.md).
 *
 * Donnees lues (ecrites par KosmicKrisp pendant les parties) :
 *   - la base de pipelines (0444, CIDRE_BASE_PIPELINES) : pipelines.bin, une
 *     suite d'enregistrements { u32 magic "KKP1", u32 taille, charge } dont la
 *     charge commence par la cle de cache Vulkan du VS (32 octets, qui couvre
 *     toute la paire) puis celle du FS ;
 *   - la liste chaude (0441, <cache>/liste-chaude-kk.bin) : les cles (32
 *     octets) de chaque nuanceur effectivement lie par le jeu ;
 *   - les journaux de cles deja faites (rejoues-*.bin de KosmicKrisp,
 *     CIDRE_REJEU_JOURNAL, echecs-*.bin) : des cles de 32 octets bout a bout.
 *
 * usage :
 *   prepa-shaders compter <pipelines.bin> <liste> [<exclus>...]
 *       ecrit « <a_faire> <connus> » : connus = enregistrements de la base dont
 *       le VS ou le FS est dans la liste chaude ; a_faire = ceux-la, moins ceux
 *       dont le VS est dans un fichier <exclus>
 *   prepa-shaders filtrer <pipelines.bin> <liste> <sortie> [<exclus>...]
 *       ecrit les enregistrements a faire dans <sortie> (pipelines.bin d'une base
 *       filtree, meme format) et leur nombre sur la sortie standard
 *   prepa-shaders cles <pipelines.bin>
 *       ecrit dans la sortie standard (binaire) la cle VS de chaque enregistrement
 *   prepa-shaders ajouter <source> <depuis> <journal> [<exclus>...]
 *       ajoute au journal les cles de <source> a partir de l'octet <depuis>
 *       (arrondi a 32), sans doublon, sauf celles des fichiers <exclus> ; ecrit
 *       le nombre ajoute
 *   prepa-shaders noter <pipelines.bin> <liste> <depuis> <journal>
 *       les enregistrements de la base dont le VS ou le FS est dans la liste
 *       chaude a partir de l'octet <depuis> (cles liees pendant une partie) :
 *       leur cle VS est ajoutee au journal (sans doublon) ; ecrit le nombre
 *   prepa-shaders rejouer <pilote.dylib>
 *       rejoue la base CIDRE_REJEU dans le cache MESA_KK_PIPELINE_CACHE, sans
 *       Wine : KosmicKrisp compile tout dans vkCreateDevice (0444), puis
 *       vkDestroyDevice ecrit l'archive Metal (reprise de kk_rejeu.c,
 *       ~/Dev/cidre-d4-fond/outils)
 * Codes : 0 bien ; 2 usage ; 3 fichier illisible ; 4-5 Vulkan. */
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define CLE 32u
#define MAGIC_P 0x31504b4bu /* "KKP1" */
#define TAILLE_MAX (64u << 20)

/* --- ensemble de cles (adressage ouvert) --- */
struct ensemble {
   uint8_t *cles; /* cap * CLE */
   uint8_t *pris;
   size_t cap, n;
};

static uint64_t
hacher(const uint8_t *k)
{
   uint64_t h;
   memcpy(&h, k, sizeof(h)); /* les cles sont des empreintes (blake3) */
   return h * 0x9e3779b97f4a7c15ull;
}

static int
ens_grandir(struct ensemble *e, size_t cap)
{
   struct ensemble n = {calloc(cap, CLE), calloc(cap, 1), cap, 0};
   if (n.cles == NULL || n.pris == NULL)
      return -1;
   for (size_t i = 0; i < e->cap; i++) {
      if (!e->pris[i])
         continue;
      size_t j = hacher(e->cles + i * CLE) & (cap - 1);
      while (n.pris[j])
         j = (j + 1) & (cap - 1);
      memcpy(n.cles + j * CLE, e->cles + i * CLE, CLE);
      n.pris[j] = 1;
      n.n++;
   }
   free(e->cles);
   free(e->pris);
   *e = n;
   return 0;
}

static int
ens_contient(const struct ensemble *e, const uint8_t *k)
{
   if (e->cap == 0)
      return 0;
   size_t j = hacher(k) & (e->cap - 1);
   while (e->pris[j]) {
      if (memcmp(e->cles + j * CLE, k, CLE) == 0)
         return 1;
      j = (j + 1) & (e->cap - 1);
   }
   return 0;
}

/* 1 si ajoutee, 0 si deja la, -1 en cas de manque de memoire */
static int
ens_ajouter(struct ensemble *e, const uint8_t *k)
{
   if ((e->n + 1) * 2 > e->cap && ens_grandir(e, e->cap ? e->cap * 2 : 1024) != 0)
      return -1;
   size_t j = hacher(k) & (e->cap - 1);
   while (e->pris[j]) {
      if (memcmp(e->cles + j * CLE, k, CLE) == 0)
         return 0;
      j = (j + 1) & (e->cap - 1);
   }
   memcpy(e->cles + j * CLE, k, CLE);
   e->pris[j] = 1;
   e->n++;
   return 1;
}

/* Les cles d'un fichier de cles bout a bout (absent = vide). Une fin tronquee
 * (moins de 32 octets) est ignoree. */
static int
ens_charger(struct ensemble *e, const char *chemin, off_t depuis)
{
   int fd = open(chemin, O_RDONLY | O_CLOEXEC);
   if (fd < 0)
      return 0;
   depuis -= depuis % CLE;
   if (depuis > 0 && lseek(fd, depuis, SEEK_SET) < 0) {
      close(fd);
      return 0;
   }
   uint8_t buf[CLE * 512];
   size_t reste = 0;
   for (;;) {
      ssize_t r = read(fd, buf + reste, sizeof(buf) - reste);
      if (r <= 0)
         break;
      size_t tot = reste + (size_t)r, k;
      for (k = 0; k + CLE <= tot; k += CLE) {
         if (ens_ajouter(e, buf + k) < 0) {
            close(fd);
            return -1;
         }
      }
      reste = tot - k;
      memmove(buf, buf + k, reste);
   }
   close(fd);
   return 0;
}

/* --- parcours de pipelines.bin --- */
typedef int (*rappel_fn)(void *, int fd, off_t pos, uint32_t taille, const uint8_t *vs,
                         const uint8_t *fs);

static int
parcourir(const char *chemin, rappel_fn rappel, void *data)
{
   int fd = open(chemin, O_RDONLY | O_CLOEXEC);
   if (fd < 0)
      return -1;
   struct stat st;
   if (fstat(fd, &st) != 0) {
      close(fd);
      return -1;
   }
   off_t pos = 0;
   for (;;) {
      uint32_t h[2];
      uint8_t cles[2 * CLE];
      if (pread(fd, h, sizeof(h), pos) != (ssize_t)sizeof(h) || h[0] != MAGIC_P ||
          h[1] < 2 * CLE || h[1] > TAILLE_MAX)
         break;
      if (pos + 8 + (off_t)h[1] > st.st_size)
         break; /* enregistrement tronque (jeu tue pendant l'ecriture) */
      if (pread(fd, cles, sizeof(cles), pos + 8) != (ssize_t)sizeof(cles))
         break;
      if (rappel(data, fd, pos, h[1], cles, cles + CLE) != 0) {
         close(fd);
         return -1;
      }
      pos += 8 + h[1];
   }
   close(fd);
   return 0;
}

struct choix {
   struct ensemble liste, exclus, vus;
   unsigned a_faire, connus;
   int sortie; /* -1 : compter seulement */
};

static int
choisir(void *data, int fd, off_t pos, uint32_t taille, const uint8_t *vs, const uint8_t *fs)
{
   struct choix *c = data;
   if (!ens_contient(&c->liste, vs) && !ens_contient(&c->liste, fs))
      return 0;
   int r = ens_ajouter(&c->vus, vs); /* la base est dedoublonnee par le VS ; au cas ou */
   if (r < 0)
      return -1;
   if (r == 0)
      return 0;
   c->connus++;
   if (ens_contient(&c->exclus, vs))
      return 0;
   c->a_faire++;
   if (c->sortie < 0)
      return 0;
   size_t n = 8 + (size_t)taille;
   uint8_t *buf = malloc(n);
   if (buf == NULL)
      return -1;
   int ok = pread(fd, buf, n, pos) == (ssize_t)n && write(c->sortie, buf, n) == (ssize_t)n;
   free(buf);
   return ok ? 0 : -1;
}

static int
cmd_choisir(int argc, char **argv, int filtrer)
{
   /* compter <pipelines> <liste> [exclus...] ; filtrer <pipelines> <liste> <sortie> [exclus...] */
   const int premier_exclus = filtrer ? 5 : 4;
   if (argc < premier_exclus)
      return 2;
   struct choix c = {0};
   c.sortie = -1;
   if (ens_charger(&c.liste, argv[3], 0) != 0)
      return 3;
   for (int i = premier_exclus; i < argc; i++) {
      if (ens_charger(&c.exclus, argv[i], 0) != 0)
         return 3;
   }
   char tmp[4096];
   if (filtrer) {
      snprintf(tmp, sizeof(tmp), "%s.tmp", argv[4]);
      c.sortie = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
      if (c.sortie < 0)
         return 3;
   }
   int r = 0;
   if (c.liste.n > 0 && access(argv[2], R_OK) == 0)
      r = parcourir(argv[2], choisir, &c);
   if (filtrer) {
      if (close(c.sortie) != 0 || r != 0 || rename(tmp, argv[4]) != 0) {
         unlink(tmp);
         return 3;
      }
      printf("%u\n", c.a_faire);
   } else {
      if (r != 0)
         return 3;
      printf("%u %u\n", c.a_faire, c.connus);
   }
   return 0;
}

static int
ecrire_cle(void *data, int fd, off_t pos, uint32_t taille, const uint8_t *vs, const uint8_t *fs)
{
   (void)data, (void)fd, (void)pos, (void)taille, (void)fs;
   return fwrite(vs, CLE, 1, stdout) == 1 ? 0 : -1;
}

static int
cmd_ajouter(int argc, char **argv)
{
   if (argc < 5)
      return 2;
   char *fin;
   long long depuis = strtoll(argv[3], &fin, 10);
   if (*argv[3] == '\0' || *fin != '\0' || depuis < 0)
      return 2;
   struct ensemble deja = {0}, neuves = {0};
   if (ens_charger(&deja, argv[4], 0) != 0 || ens_charger(&neuves, argv[2], depuis) != 0)
      return 3;
   for (int i = 5; i < argc; i++) {
      if (ens_charger(&deja, argv[i], 0) != 0)
         return 3;
   }
   int fd = open(argv[4], O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
   if (fd < 0)
      return 3;
   /* un journal dont la fin serait tronquee : realigner avant d'ajouter */
   struct stat st;
   if (fstat(fd, &st) == 0 && st.st_size % CLE != 0 &&
       ftruncate(fd, st.st_size - st.st_size % CLE) != 0) {
      close(fd);
      return 3;
   }
   unsigned n = 0;
   for (size_t i = 0; i < neuves.cap; i++) {
      if (!neuves.pris[i] || ens_contient(&deja, neuves.cles + i * CLE))
         continue;
      if (write(fd, neuves.cles + i * CLE, CLE) != CLE) {
         close(fd);
         return 3;
      }
      n++;
   }
   close(fd);
   printf("%u\n", n);
   return 0;
}

struct notage {
   struct ensemble neuves, deja;
   int fd;
   unsigned n;
};

static int
noter_un(void *data, int fd, off_t pos, uint32_t taille, const uint8_t *vs, const uint8_t *fs)
{
   (void)fd, (void)pos, (void)taille;
   struct notage *t = data;
   if (!ens_contient(&t->neuves, vs) && !ens_contient(&t->neuves, fs))
      return 0;
   int r = ens_ajouter(&t->deja, vs);
   if (r < 0)
      return -1;
   if (r == 0)
      return 0;
   if (write(t->fd, vs, CLE) != CLE)
      return -1;
   t->n++;
   return 0;
}

static int
cmd_noter(int argc, char **argv)
{
   if (argc != 6)
      return 2;
   char *fin;
   long long depuis = strtoll(argv[4], &fin, 10);
   if (*argv[4] == '\0' || *fin != '\0' || depuis < 0)
      return 2;
   struct notage t = {0};
   if (ens_charger(&t.neuves, argv[3], depuis) != 0 || ens_charger(&t.deja, argv[5], 0) != 0)
      return 3;
   t.fd = open(argv[5], O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
   if (t.fd < 0)
      return 3;
   struct stat st;
   if (fstat(t.fd, &st) == 0 && st.st_size % CLE != 0 &&
       ftruncate(t.fd, st.st_size - st.st_size % CLE) != 0) {
      close(t.fd);
      return 3;
   }
   int r = t.neuves.n > 0 ? parcourir(argv[2], noter_un, &t) : 0;
   close(t.fd);
   if (r != 0)
      return 3;
   printf("%u\n", t.n);
   return 0;
}

/* --- rejeu (reprise de kk_rejeu.c) --- */
typedef PFN_vkVoidFunction (*icd_gipa)(VkInstance, const char *);

static int
cmd_rejouer(int argc, char **argv)
{
   if (argc != 3 || getenv("CIDRE_REJEU") == NULL)
      return 2;
   void *lib = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
   if (lib == NULL) {
      fprintf(stderr, "prepa-shaders : dlopen : %s\n", dlerror());
      return 3;
   }
   icd_gipa gipa = (icd_gipa)dlsym(lib, "vk_icdGetInstanceProcAddr");
   if (gipa == NULL) {
      fprintf(stderr, "prepa-shaders : vk_icdGetInstanceProcAddr absent\n");
      return 3;
   }
   PFN_vkCreateInstance createInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
   VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                            .pApplicationName = "prepa-shaders",
                            .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                               .pApplicationInfo = &app};
   VkInstance inst;
   VkResult r = createInstance(&ici, NULL, &inst);
   if (r != VK_SUCCESS) {
      fprintf(stderr, "prepa-shaders : vkCreateInstance : %d\n", r);
      return 4;
   }
   PFN_vkEnumeratePhysicalDevices enumerer =
      (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
   PFN_vkCreateDevice creer = (PFN_vkCreateDevice)gipa(inst, "vkCreateDevice");
   PFN_vkDestroyInstance detruireInstance = (PFN_vkDestroyInstance)gipa(inst, "vkDestroyInstance");
   PFN_vkGetDeviceProcAddr gdpa = (PFN_vkGetDeviceProcAddr)gipa(inst, "vkGetDeviceProcAddr");
   uint32_t n = 1;
   VkPhysicalDevice pd;
   r = enumerer(inst, &n, &pd);
   if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || n == 0) {
      fprintf(stderr, "prepa-shaders : aucun peripherique KosmicKrisp\n");
      return 4;
   }
   float prio = 0.0f;
   VkDeviceQueueCreateInfo qci = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                  .queueFamilyIndex = 0, .queueCount = 1,
                                  .pQueuePriorities = &prio};
   VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                             .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci};
   VkDevice dev;
   r = creer(pd, &dci, NULL, &dev); /* le rejeu a lieu ici */
   if (r != VK_SUCCESS) {
      fprintf(stderr, "prepa-shaders : vkCreateDevice : %d\n", r);
      return 5;
   }
   PFN_vkDestroyDevice detruire = (PFN_vkDestroyDevice)gdpa(dev, "vkDestroyDevice");
   detruire(dev, NULL); /* ecrit l'archive Metal du dernier lot */
   detruireInstance(inst, NULL);
   return 0;
}

int
main(int argc, char **argv)
{
   int r = 2;
   if (argc >= 2 && strcmp(argv[1], "compter") == 0)
      r = cmd_choisir(argc, argv, 0);
   else if (argc >= 2 && strcmp(argv[1], "filtrer") == 0)
      r = cmd_choisir(argc, argv, 1);
   else if (argc == 3 && strcmp(argv[1], "cles") == 0)
      r = parcourir(argv[2], ecrire_cle, NULL) == 0 ? 0 : 3;
   else if (argc >= 2 && strcmp(argv[1], "ajouter") == 0)
      r = cmd_ajouter(argc, argv);
   else if (argc >= 2 && strcmp(argv[1], "noter") == 0)
      r = cmd_noter(argc, argv);
   else if (argc >= 2 && strcmp(argv[1], "rejouer") == 0)
      r = cmd_rejouer(argc, argv);
   if (r == 2)
      fprintf(stderr, "usage : prepa-shaders compter|filtrer|cles|ajouter|noter|rejouer ... (voir tests/prepa_shaders.c)\n");
   return r;
}
