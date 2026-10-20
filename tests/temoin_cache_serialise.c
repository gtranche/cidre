// Témoin de 0209 (KosmicKrisp) : vkGetPipelineCacheData ne doit pas recompresser le MSL et le NIR à chaque appel.
// Mesa resérialise tout le cache à chaque appel (deux fois par sauvegarde : taille puis données), sous le verrou du
// cache ; avec 0166 seul, chaque appel recompressait tout (Detroit : ~10 s par passe, l'image gelait). Natif macOS :
//   construit et lancé par tests/temoin_cache_serialise.sh (gros_spv.h y est généré)
//   ./temoin_cache_serialise [pipelines]
// Étapes : N pipelines de calcul volumineux (constante de spécialisation distincte) dans un cache vide ; 4 appels
// « taille + données » chronométrés ; puis cache 2 créé depuis ces données, mêmes pipelines (objets relus du cache,
// donc désérialisés), 3 appels chronométrés, et comparaison octet pour octet avec les données du cache 1.
// Verdict : ok si les appels après le premier coûtent < 1/5 du premier (cache 1) et si le cache 2 rend exactement les
// mêmes octets, dès son premier appel, sans être plus lent que les appels suivants du cache 1 x 5.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dlfcn.h>
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include "gros_spv.h"

static PFN_vkGetInstanceProcAddr gipa;
#define F(n) static PFN_##n n
F(vkCreateInstance); F(vkEnumeratePhysicalDevices); F(vkGetPhysicalDeviceProperties); F(vkCreateDevice);
F(vkCreatePipelineCache); F(vkGetPipelineCacheData); F(vkDestroyPipelineCache); F(vkCreateShaderModule);
F(vkCreateDescriptorSetLayout); F(vkCreatePipelineLayout); F(vkCreateComputePipelines); F(vkDestroyPipeline);

static VkDevice dev;
static VkPipelineLayout pl;
static VkShaderModule sm;

/* empreinte du contenu indépendante de l'ordre des entrées (la table de hachage de Mesa peut les ranger
 * autrement d'un cache à l'autre) : somme des FNV-1a de chaque entrée (type, clé, données) */
static unsigned long long empreinte(const unsigned char *d, size_t l, unsigned *nb) {
   size_t off = 32;
   uint32_t count; memcpy(&count, d + off, 4); off += 4;
   unsigned long long somme = 0;
   for (uint32_t i = 0; i < count; i++) {
      off = (off + 3) & ~(size_t)3;
      uint32_t h[3]; if (off + 12 > l) break; memcpy(h, d + off, 12);
      size_t debut = off; off += 12 + h[1];
      off = (off + 7) & ~(size_t)7;
      size_t fin = off + h[2]; if (fin > l) break;
      unsigned long long f = 1469598103934665603ull;
      for (size_t k = debut; k < debut + 12 + h[1]; k++) f = (f ^ d[k]) * 1099511628211ull;
      for (size_t k = off; k < fin; k++) f = (f ^ d[k]) * 1099511628211ull;
      somme += f; off = fin;
   }
   *nb = count;
   return somme;
}

static double maintenant(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static double creer(VkPipelineCache cache, unsigned n) {
   double t0 = maintenant();
   for (unsigned k = 0; k < n; k++) {
      uint32_t val = k + 1;
      VkSpecializationMapEntry e = {0, 0, 4};
      VkSpecializationInfo si = {1, &e, 4, &val};
      VkComputePipelineCreateInfo ci = {VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
         .stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm,
                   .pName = "main", .pSpecializationInfo = &si},
         .layout = pl};
      VkPipeline p;
      VkResult r = vkCreateComputePipelines(dev, cache, 1, &ci, NULL, &p);
      if (r != VK_SUCCESS) { printf("pipeline %u : %d\n", k, r); exit(1); }
      vkDestroyPipeline(dev, p, NULL);
   }
   return maintenant() - t0;
}

/* un appel « taille puis données », comme un jeu qui sauvegarde son cache ; rend le temps et les données */
static double sauver(VkPipelineCache cache, unsigned char **out, size_t *len) {
   double t0 = maintenant();
   size_t taille = 0;
   vkGetPipelineCacheData(dev, cache, &taille, NULL);
   unsigned char *d = malloc(taille);
   size_t t2 = taille;
   VkResult r = vkGetPipelineCacheData(dev, cache, &t2, d);
   double t = maintenant() - t0;
   if (r != VK_SUCCESS || t2 != taille) { printf("donnees : %d (%zu/%zu)\n", r, t2, taille); exit(1); }
   *out = d; *len = t2;
   return t;
}

int main(int argc, char **argv) {
   unsigned n = argc > 1 ? (unsigned)atoi(argv[1]) : 150;
   void *h = dlopen("libvulkan.1.dylib", RTLD_NOW); if (!h) { printf("libvulkan absente\n"); return 1; }
   gipa = (PFN_vkGetInstanceProcAddr)dlsym(h, "vkGetInstanceProcAddr");
   vkCreateInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
   VkApplicationInfo ai = {VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   const char *iext[] = {"VK_KHR_portability_enumeration"};
   VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
                               .pApplicationInfo = &ai, .enabledExtensionCount = 1, .ppEnabledExtensionNames = iext};
   VkInstance inst; VkResult r = vkCreateInstance(&ici, NULL, &inst);
   if (r != VK_SUCCESS) { printf("instance : %d\n", r); return 1; }
#define G(n) n = (PFN_##n)gipa(inst, #n)
   G(vkEnumeratePhysicalDevices); G(vkGetPhysicalDeviceProperties); G(vkCreateDevice); G(vkCreatePipelineCache);
   G(vkGetPipelineCacheData); G(vkDestroyPipelineCache); G(vkCreateShaderModule); G(vkCreateDescriptorSetLayout);
   G(vkCreatePipelineLayout); G(vkCreateComputePipelines); G(vkDestroyPipeline);
   uint32_t c = 1; VkPhysicalDevice pd; vkEnumeratePhysicalDevices(inst, &c, &pd);
   VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd, &p);
   printf("peripherique \"%s\", %u pipelines de calcul (SPIR-V %u octets)\n", p.deviceName, n, gros_spv_len);
   float prio = 1;
   VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio};
   VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci};
   if ((r = vkCreateDevice(pd, &dci, NULL, &dev)) != VK_SUCCESS) { printf("peripherique : %d\n", r); return 1; }
   VkDescriptorSetLayoutBinding b = {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo lci = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &b};
   VkDescriptorSetLayout sl; vkCreateDescriptorSetLayout(dev, &lci, NULL, &sl);
   VkPipelineLayoutCreateInfo plci = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &sl};
   vkCreatePipelineLayout(dev, &plci, NULL, &pl);
   VkShaderModuleCreateInfo mi = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = gros_spv_len, .pCode = (const uint32_t *)gros_spv};
   if (vkCreateShaderModule(dev, &mi, NULL, &sm) != VK_SUCCESS) { printf("module : echec\n"); return 1; }

   VkPipelineCacheCreateInfo cci = {VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
   VkPipelineCache c1; vkCreatePipelineCache(dev, &cci, NULL, &c1);
   printf("cache 1 : %u pipelines crees en %.2f s\n", n, creer(c1, n));
   unsigned char *d1 = NULL; size_t l1 = 0; double t1[4];
   for (int i = 0; i < 4; i++) {
      unsigned char *d; size_t l;
      t1[i] = sauver(c1, &d, &l);
      if (i == 0) { d1 = d; l1 = l; }
      else { if (l != l1 || memcmp(d, d1, l)) printf("  cache 1 : appel %d rend d'autres octets\n", i + 1); free(d); }
      printf("  cache 1, sauvegarde %d : %.1f ms, %zu octets\n", i + 1, t1[i] * 1e3, l);
   }
   cci.initialDataSize = l1; cci.pInitialData = d1;
   VkPipelineCache c2; vkCreatePipelineCache(dev, &cci, NULL, &c2);
   printf("cache 2 (depuis les %zu octets) : %u pipelines en %.2f s\n", l1, n, creer(c2, n));
   int memes = 1; double t2[3];
   for (int i = 0; i < 3; i++) {
      unsigned char *d; size_t l;
      t2[i] = sauver(c2, &d, &l);
      unsigned na, nb;
      int m = (l == l1 && empreinte(d, l, &na) == empreinte(d1, l1, &nb) && na == nb);
      memes &= m;
      printf("  cache 2, sauvegarde %d : %.1f ms, %zu octets, %s\n", i + 1, t2[i] * 1e3, l, m ? "meme contenu que le cache 1" : "CONTENU DIFFERENT");
      free(d);
   }
   double suite = (t1[1] + t1[2] + t1[3]) / 3;
   int ok1 = suite < t1[0] / 5, ok2 = memes && t2[0] < suite * 5 + 0.002;
   printf("bilan : cache 1 premier %.1f ms / suivants %.1f ms -> %s ; cache 2 premier %.1f ms, octets %s -> %s\n",
          t1[0] * 1e3, suite * 1e3, ok1 ? "ok" : "ECHEC (recompresse a chaque appel)", t2[0] * 1e3,
          memes ? "identiques" : "differents", ok2 ? "ok" : "ECHEC");
   return ok1 && ok2 ? 0 : 1;
}
