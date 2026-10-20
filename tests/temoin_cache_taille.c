// Témoin de 0213 (runtime Vulkan de Mesa, KosmicKrisp) : la taille rendue par vkGetPipelineCacheData (pData NULL)
// est gardée tant que le contenu du cache ne change pas. Detroit: Become Human demande sans cesse la taille de son
// cache (96 505 objets) ; chaque demande parcourait tout le cache sous son verrou.
// Construit et lancé par tests/temoin_cache_taille.sh (petit_spv.h y est généré).
// Étapes : cache créé depuis un blob fabriqué de N objets bruts (1 Ko chacun, en-tête du périphérique) ; 200 demandes
// de taille chronométrées ; justesse : taille == longueur des données rendues ; après un pipeline créé dans le cache,
// puis après vkMergePipelineCaches d'un cache qui apporte un objet, la taille suit et vaut toujours la longueur
// des données. Verdict : justesse toujours ; et, sans CIDRE_CACHE_TAILLE_RECALCULEE, une demande de taille coûte
// moins de 1/20 du premier calcul.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dlfcn.h>
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include "petit_spv.h"

static PFN_vkGetInstanceProcAddr gipa;
#define F(n) static PFN_##n n
F(vkCreateInstance); F(vkEnumeratePhysicalDevices); F(vkGetPhysicalDeviceProperties); F(vkCreateDevice);
F(vkCreatePipelineCache); F(vkGetPipelineCacheData); F(vkDestroyPipelineCache); F(vkCreateShaderModule);
F(vkCreateDescriptorSetLayout); F(vkCreatePipelineLayout); F(vkCreateComputePipelines); F(vkDestroyPipeline);
F(vkMergePipelineCaches);

static VkDevice dev;
static VkPipelineLayout pl;
static VkShaderModule sm;
static int echecs;

static double maintenant(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static size_t taille(VkPipelineCache c) { size_t t = 0; vkGetPipelineCacheData(dev, c, &t, NULL); return t; }

/* taille demandée seule, puis longueur réellement rendue avec un tampon de cette taille : elles doivent être égales */
static size_t verifier(VkPipelineCache c, const char *etape) {
   size_t t = taille(c), l = t;
   unsigned char *d = malloc(t ? t : 1);
   VkResult r = vkGetPipelineCacheData(dev, c, &l, d);
   size_t t2 = taille(c);
   int ok = (r == VK_SUCCESS && l == t && t2 == t);
   printf("  %-6s %s : taille %zu, donnees %zu (%d), taille redemandee %zu\n", ok ? "ok" : "ECHEC", etape, t, l, r, t2);
   if (!ok) echecs++;
   free(d);
   return t;
}

static void pipeline(VkPipelineCache c, uint32_t val) {
   VkSpecializationMapEntry e = {0, 0, 4};
   VkSpecializationInfo si = {1, &e, 4, &val};
   VkComputePipelineCreateInfo ci = {VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm,
                .pName = "main", .pSpecializationInfo = &si},
      .layout = pl};
   VkPipeline p;
   if (vkCreateComputePipelines(dev, c, 1, &ci, NULL, &p) != VK_SUCCESS) { printf("pipeline : echec\n"); exit(1); }
   vkDestroyPipeline(dev, p, NULL);
}

int main(int argc, char **argv) {
   unsigned n = argc > 1 ? (unsigned)atoi(argv[1]) : 96505, i;
   void *h = dlopen("libvulkan.1.dylib", RTLD_NOW); if (!h) { printf("libvulkan absente\n"); return 1; }
   gipa = (PFN_vkGetInstanceProcAddr)dlsym(h, "vkGetInstanceProcAddr");
   vkCreateInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
   VkApplicationInfo ai = {VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3};
   const char *iext[] = {"VK_KHR_portability_enumeration"};
   VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
                               .pApplicationInfo = &ai, .enabledExtensionCount = 1, .ppEnabledExtensionNames = iext};
   VkInstance inst; if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) { printf("instance : echec\n"); return 1; }
#define G(x) x = (PFN_##x)gipa(inst, #x)
   G(vkEnumeratePhysicalDevices); G(vkGetPhysicalDeviceProperties); G(vkCreateDevice); G(vkCreatePipelineCache);
   G(vkGetPipelineCacheData); G(vkDestroyPipelineCache); G(vkCreateShaderModule); G(vkCreateDescriptorSetLayout);
   G(vkCreatePipelineLayout); G(vkCreateComputePipelines); G(vkDestroyPipeline); G(vkMergePipelineCaches);
   uint32_t c1 = 1; VkPhysicalDevice pd; vkEnumeratePhysicalDevices(inst, &c1, &pd);
   VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd, &p);
   float prio = 1;
   VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio};
   VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci};
   if (vkCreateDevice(pd, &dci, NULL, &dev) != VK_SUCCESS) { printf("peripherique : echec\n"); return 1; }
   VkDescriptorSetLayoutBinding b = {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT};
   VkDescriptorSetLayoutCreateInfo lci = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &b};
   VkDescriptorSetLayout sl; vkCreateDescriptorSetLayout(dev, &lci, NULL, &sl);
   VkPipelineLayoutCreateInfo plci = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &sl};
   vkCreatePipelineLayout(dev, &plci, NULL, &pl);
   VkShaderModuleCreateInfo mi = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = petit_spv_len, .pCode = (const uint32_t *)petit_spv};
   vkCreateShaderModule(dev, &mi, NULL, &sm);

   /* blob du runtime de Mesa : en-tete Vulkan (32 o), compte, puis par objet : type (-1 = brut), taille de cle, taille
    * des donnees (alignes sur 4), cle, alignement sur 8, donnees. Cles de 32 o distinctes, donnees de 1 Ko. */
   const uint32_t ks = 32, ds = 1024;
   size_t cap = 36 + (size_t)n * (12 + ks + 8 + ds) + 64, off = 0;
   unsigned char *blob = calloc(1, cap);
   VkPipelineCacheHeaderVersionOne hd = {32, VK_PIPELINE_CACHE_HEADER_VERSION_ONE, p.vendorID, p.deviceID};
   memcpy(hd.pipelineCacheUUID, p.pipelineCacheUUID, VK_UUID_SIZE);
   memcpy(blob, &hd, 32); off = 32;
   memcpy(blob + off, &n, 4); off += 4;
   for (i = 0; i < n; i++) {
      int32_t type = -1;
      off = (off + 3) & ~(size_t)3;
      memcpy(blob + off, &type, 4); memcpy(blob + off + 4, &ks, 4); memcpy(blob + off + 8, &ds, 4); off += 12;
      for (uint32_t k = 0; k < ks; k += 4) { uint32_t v = i * 2654435761u ^ (k * 40503u) ^ 0x9e3779b9u; memcpy(blob + off + k, &v, 4); }
      off += ks;
      off = (off + 7) & ~(size_t)7;
      memset(blob + off, (int)(i & 0xff), ds); off += ds;
   }
   VkPipelineCacheCreateInfo cci = {VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO, .initialDataSize = off, .pInitialData = blob};
   VkPipelineCache c; vkCreatePipelineCache(dev, &cci, NULL, &c);
   printf("peripherique \"%s\" ; cache de %u objets bruts (%zu octets)%s\n", p.deviceName, n, off,
          getenv("CIDRE_CACHE_TAILLE_RECALCULEE") ? ", CIDRE_CACHE_TAILLE_RECALCULEE=1" : "");

   double t0 = maintenant();
   size_t t1 = taille(c);
   double premier = maintenant() - t0;
   t0 = maintenant();
   for (i = 0; i < 200; i++) if (taille(c) != t1) { printf("  ECHEC taille instable\n"); echecs++; break; }
   double suivant = (maintenant() - t0) / 200;
   int relu = (t1 >= off - 64 && t1 <= off + 64);
   printf("  %-6s cache relu en entier : taille %zu pour un blob de %zu\n", relu ? "ok" : "ECHEC", t1, off);
   if (!relu) echecs++;
   printf("  demande de taille : premiere %.2f ms, suivantes %.4f ms par appel\n", premier * 1e3, suivant * 1e3);

   size_t a = verifier(c, "avant tout changement");
   pipeline(c, 1);
   size_t b2 = verifier(c, "apres un pipeline cree dans le cache");
   if (b2 <= a) { printf("  ECHEC la taille n'a pas suivi le pipeline\n"); echecs++; }
   VkPipelineCacheCreateInfo vide = {VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
   VkPipelineCache autre; vkCreatePipelineCache(dev, &vide, NULL, &autre);
   pipeline(autre, 2);
   vkMergePipelineCaches(dev, c, 1, &autre);
   size_t m = verifier(c, "apres vkMergePipelineCaches");
   if (m <= b2) { printf("  ECHEC la taille n'a pas suivi la fusion\n"); echecs++; }

   int rapide = getenv("CIDRE_CACHE_TAILLE_RECALCULEE") || suivant < premier / 20;
   printf("bilan : justesse %s, demande de taille %.4f ms contre %.2f ms au premier calcul -> %s\n",
          echecs ? "ECHEC" : "ok", suivant * 1e3, premier * 1e3, echecs ? "ECHEC" : rapide ? "ok" : "LENT (taille recalculee a chaque appel)");
   return echecs || !rapide;
}
