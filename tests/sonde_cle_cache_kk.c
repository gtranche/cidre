/* Sonde de la cle des caches de nuanceurs de KosmicKrisp (0208), sans jeu.
 *
 *   sonde_cle_cache_kk <dossier des .spv> <fichier de cache>
 *
 * Imprime pipelineCacheUUID, cree un VkPipelineCache depuis le fichier (s'il
 * existe), y cree 4 pipelines de calcul (constante de specialisation 0..3) et
 * 1 pipeline graphique, compte ceux que la creation dit servis par le cache
 * (VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT), puis
 * reecrit le fichier avec vkGetPipelineCacheData. Une ligne finale :
 *   uuid=<hex> donnees_lues=<octets> acceptees=<0|1> pipelines=5 servis=<n>
 * Construite par tests/temoin_cle_cache_kk.sh.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
   fprintf(stderr, "%s : %d\n", #x, r_); exit(1); } } while (0)

static void *
lire(const char *chemin, size_t *taille)
{
   FILE *f = fopen(chemin, "rb");
   if (!f) { *taille = 0; return NULL; }
   fseek(f, 0, SEEK_END);
   long n = ftell(f);
   fseek(f, 0, SEEK_SET);
   void *p = malloc(n > 0 ? n : 1);
   *taille = fread(p, 1, n, f);
   fclose(f);
   return p;
}

static VkShaderModule
module(VkDevice dev, const char *dossier, const char *nom)
{
   char chemin[2048];
   snprintf(chemin, sizeof(chemin), "%s/%s", dossier, nom);
   size_t n;
   void *code = lire(chemin, &n);
   if (!code || n == 0) { fprintf(stderr, "%s absent\n", chemin); exit(1); }
   VkShaderModuleCreateInfo ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = n, .pCode = code };
   VkShaderModule m;
   CK(vkCreateShaderModule(dev, &ci, NULL, &m));
   free(code);
   return m;
}

static double
ms(struct timespec a, struct timespec b)
{
   return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

int
main(int argc, char **argv)
{
   if (argc != 3) { fprintf(stderr, "usage : %s <spv> <cache>\n", argv[0]); return 2; }
   const char *spv = argv[1], *fcache = argv[2];

   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                             .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                .pApplicationInfo = &app };
   VkInstance inst;
   CK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t n = 1;
   VkPhysicalDevice pd;
   vkEnumeratePhysicalDevices(inst, &n, &pd);
   if (n == 0) { fprintf(stderr, "aucun GPU\n"); return 1; }
   VkPhysicalDeviceProperties pp;
   vkGetPhysicalDeviceProperties(pd, &pp);
   char uuid[2 * VK_UUID_SIZE + 1];
   for (unsigned i = 0; i < VK_UUID_SIZE; i++)
      snprintf(uuid + 2 * i, 3, "%02x", pp.pipelineCacheUUID[i]);

   float prio = 1;
   VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                   .queueCount = 1, .pQueuePriorities = &prio };
   VkPhysicalDeviceVulkan13Features f13 = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      .dynamicRendering = VK_TRUE };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                              .pNext = &f13, .queueCreateInfoCount = 1,
                              .pQueueCreateInfos = &qci };
   VkDevice dev;
   CK(vkCreateDevice(pd, &dci, NULL, &dev));

   size_t lu;
   void *donnees = lire(fcache, &lu);
   VkPipelineCacheCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
                                     .initialDataSize = lu, .pInitialData = donnees };
   VkPipelineCache cache;
   CK(vkCreatePipelineCache(dev, &pci, NULL, &cache));
   free(donnees);

   VkDescriptorSetLayoutBinding b = { .binding = 0,
      .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1,
      .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT };
   VkDescriptorSetLayoutCreateInfo dslci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1, .pBindings = &b };
   VkDescriptorSetLayout dsl;
   CK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
   VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                       .setLayoutCount = 1, .pSetLayouts = &dsl };
   VkPipelineLayout pl;
   CK(vkCreatePipelineLayout(dev, &plci, NULL, &pl));
   VkPipelineLayoutCreateInfo plci_vide = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
   VkPipelineLayout pl_vide;
   CK(vkCreatePipelineLayout(dev, &plci_vide, NULL, &pl_vide));

   VkShaderModule mc = module(dev, spv, "c.spv");
   VkShaderModule mv = module(dev, spv, "v.spv");
   VkShaderModule mf = module(dev, spv, "f.spv");

   unsigned servis = 0, total = 0;
   struct timespec t0, t1;
   clock_gettime(CLOCK_MONOTONIC, &t0);
   for (uint32_t k = 0; k < 4; k++) {
      VkSpecializationMapEntry e = { .constantID = 0, .offset = 0, .size = 4 };
      VkSpecializationInfo si = { .mapEntryCount = 1, .pMapEntries = &e,
                                  .dataSize = 4, .pData = &k };
      VkPipelineCreationFeedback fb = { 0 };
      VkPipelineCreationFeedbackCreateInfo fbci = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_CREATION_FEEDBACK_CREATE_INFO,
         .pPipelineCreationFeedback = &fb };
      VkComputePipelineCreateInfo cci = {
         .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, .pNext = &fbci,
         .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = mc,
                    .pName = "main", .pSpecializationInfo = &si },
         .layout = pl };
      VkPipeline p;
      CK(vkCreateComputePipelines(dev, cache, 1, &cci, NULL, &p));
      total++;
      if (fb.flags & VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT)
         servis++;
      vkDestroyPipeline(dev, p, NULL);
   }

   {
      VkPipelineShaderStageCreateInfo st[2] = {
         { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
           .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = mv, .pName = "main" },
         { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
           .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = mf, .pName = "main" } };
      VkPipelineVertexInputStateCreateInfo vi = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
      VkPipelineInputAssemblyStateCreateInfo ia = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
      VkViewport vp = { 0, 0, 64, 64, 0, 1 };
      VkRect2D sc = { { 0, 0 }, { 64, 64 } };
      VkPipelineViewportStateCreateInfo vps = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .viewportCount = 1, .pViewports = &vp, .scissorCount = 1, .pScissors = &sc };
      VkPipelineRasterizationStateCreateInfo rs = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .lineWidth = 1 };
      VkPipelineMultisampleStateCreateInfo ms_ = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT };
      VkPipelineColorBlendAttachmentState ba = { .colorWriteMask = 0xf };
      VkPipelineColorBlendStateCreateInfo cb = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
         .attachmentCount = 1, .pAttachments = &ba };
      VkFormat fmt = VK_FORMAT_B8G8R8A8_UNORM;
      VkPipelineCreationFeedback fb = { 0 };
      VkPipelineCreationFeedbackCreateInfo fbci = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_CREATION_FEEDBACK_CREATE_INFO,
         .pPipelineCreationFeedback = &fb };
      VkPipelineRenderingCreateInfo ri = {
         .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .pNext = &fbci,
         .colorAttachmentCount = 1, .pColorAttachmentFormats = &fmt };
      VkGraphicsPipelineCreateInfo gci = {
         .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &ri,
         .stageCount = 2, .pStages = st, .pVertexInputState = &vi,
         .pInputAssemblyState = &ia, .pViewportState = &vps,
         .pRasterizationState = &rs, .pMultisampleState = &ms_,
         .pColorBlendState = &cb, .layout = pl_vide };
      VkPipeline p;
      CK(vkCreateGraphicsPipelines(dev, cache, 1, &gci, NULL, &p));
      total++;
      if (fb.flags & VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT)
         servis++;
      vkDestroyPipeline(dev, p, NULL);
   }
   clock_gettime(CLOCK_MONOTONIC, &t1);

   size_t taille = 0;
   CK(vkGetPipelineCacheData(dev, cache, &taille, NULL));
   void *sortie = malloc(taille);
   CK(vkGetPipelineCacheData(dev, cache, &taille, sortie));
   /* l'en-tete du cache garde l'UUID sous lequel il a ete ecrit : relu par le
    * temoin pour dire si les donnees lues ont ete acceptees */
   int acceptees = 0;
   if (lu >= 32) {
      size_t n2;
      unsigned char *ancien = lire(fcache, &n2);
      acceptees = ancien && memcmp(ancien + 16, pp.pipelineCacheUUID, VK_UUID_SIZE) == 0;
      free(ancien);
   }
   FILE *f = fopen(fcache, "wb");
   if (!f) { perror(fcache); return 1; }
   fwrite(sortie, 1, taille, f);
   fclose(f);
   free(sortie);

   printf("uuid=%s donnees_lues=%zu acceptees=%d pipelines=%u servis=%u ms=%.1f\n",
          uuid, lu, acceptees, total, servis, ms(t0, t1));

   vkDestroyShaderModule(dev, mc, NULL);
   vkDestroyShaderModule(dev, mv, NULL);
   vkDestroyShaderModule(dev, mf, NULL);
   vkDestroyPipelineLayout(dev, pl, NULL);
   vkDestroyPipelineLayout(dev, pl_vide, NULL);
   vkDestroyDescriptorSetLayout(dev, dsl, NULL);
   vkDestroyPipelineCache(dev, cache, NULL);
   vkDestroyDevice(dev, NULL);
   vkDestroyInstance(inst, NULL);
   return 0;
}
