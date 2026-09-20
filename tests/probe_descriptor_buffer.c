/* Sonde : VK_EXT_descriptor_buffer. Un calcul lit un SSBO et un tampon de
 * texels a travers un descriptor buffer, puis ecrit dans un SSBO de sortie
 * lui aussi decrit par le descriptor buffer. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>

#define CHK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
   printf("ECHEC %s -> %d\n", #x, r_); return 1; } } while (0)

static VkDevice dev;
static VkPhysicalDevice phys;
static VkInstance inst;
static uint32_t qfam;

#define PFN(name) PFN_vk##name pfn_##name = (PFN_vk##name)vkGetDeviceProcAddr(dev, "vk" #name)

static uint32_t type_hote(VkPhysicalDeviceMemoryProperties *mp, uint32_t bits)
{
   for (uint32_t i = 0; i < mp->memoryTypeCount; ++i)
      if ((bits & (1u << i)) &&
          (mp->memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
          (mp->memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))
         return i;
   return UINT32_MAX;
}

struct tampon { VkBuffer buf; VkDeviceMemory mem; void *map; VkDeviceAddress va; };

static int cree(struct tampon *t, VkDeviceSize taille, VkBufferUsageFlags usage)
{
   VkPhysicalDeviceMemoryProperties mp;
   VkMemoryRequirements req;
   VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = taille, .usage = usage | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
   CHK(vkCreateBuffer(dev, &bi, NULL, &t->buf));
   vkGetBufferMemoryRequirements(dev, t->buf, &req);
   vkGetPhysicalDeviceMemoryProperties(phys, &mp);
   VkMemoryAllocateFlagsInfo fi = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
      .flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT };
   VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &fi,
      .allocationSize = req.size, .memoryTypeIndex = type_hote(&mp, req.memoryTypeBits) };
   CHK(vkAllocateMemory(dev, &ai, NULL, &t->mem));
   CHK(vkBindBufferMemory(dev, t->buf, t->mem, 0));
   CHK(vkMapMemory(dev, t->mem, 0, VK_WHOLE_SIZE, 0, &t->map));
   memset(t->map, 0, taille);
   VkBufferDeviceAddressInfo di = { .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = t->buf };
   t->va = vkGetBufferDeviceAddress(dev, &di);
   return 0;
}

int main(int argc, char **argv)
{
   const char *spv_path = argc > 1 ? argv[1] : "build/probe_descbuf.spv";
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
   uint32_t n = 1;
   float prio = 1.0f;

   CHK(vkCreateInstance(&ici, NULL, &inst));
   vkEnumeratePhysicalDevices(inst, &n, &phys);

   uint32_t nq = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, NULL);
   VkQueueFamilyProperties *qp = malloc(nq * sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, qp);
   qfam = 0;
   for (uint32_t i = 0; i < nq; ++i)
      if (qp[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }

   const char *exts[] = { "VK_EXT_descriptor_buffer" };
   VkPhysicalDeviceDescriptorBufferFeaturesEXT dbf = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
      .descriptorBuffer = VK_TRUE };
   VkPhysicalDeviceVulkan12Features v12 = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &dbf,
      .bufferDeviceAddress = VK_TRUE };
   VkPhysicalDeviceFeatures2 f2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v12 };
   VkDeviceQueueCreateInfo q = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qfam, .queueCount = 1, .pQueuePriorities = &prio };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f2,
      .queueCreateInfoCount = 1, .pQueueCreateInfos = &q,
      .enabledExtensionCount = 1, .ppEnabledExtensionNames = exts };
   CHK(vkCreateDevice(phys, &dci, NULL, &dev));

   VkPhysicalDeviceDescriptorBufferPropertiesEXT dbp = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT };
   VkPhysicalDeviceProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &dbp };
   vkGetPhysicalDeviceProperties2(phys, &p2);
   printf("pilote : %s\n", p2.properties.deviceName);
   printf("tailles : ssbo %zu, texel %zu, image %zu, sampler %zu ; alignement %llu\n",
          dbp.storageBufferDescriptorSize, dbp.storageTexelBufferDescriptorSize,
          dbp.sampledImageDescriptorSize, dbp.samplerDescriptorSize,
          (unsigned long long)dbp.descriptorBufferOffsetAlignment);

   PFN(GetDescriptorEXT); PFN(GetDescriptorSetLayoutSizeEXT);
   PFN(GetDescriptorSetLayoutBindingOffsetEXT); PFN(CmdBindDescriptorBuffersEXT);
   PFN(CmdSetDescriptorBufferOffsetsEXT);
   if (!pfn_GetDescriptorEXT || !pfn_CmdBindDescriptorBuffersEXT ||
       !pfn_CmdSetDescriptorBufferOffsetsEXT) {
      printf("points d'entree manquants\n"); return 1;
   }

   struct tampon entree, texels, sortie, descbuf;
   if (cree(&entree, 256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT)) return 1;
   if (cree(&texels, 64u << 20, VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT | VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT)) return 1;
   if (cree(&sortie, 256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT)) return 1;
   if (cree(&descbuf, 4096, VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT |
                            VK_BUFFER_USAGE_SAMPLER_DESCRIPTOR_BUFFER_BIT_EXT)) return 1;

   for (uint32_t i = 0; i < 64; ++i) ((uint32_t *)entree.map)[i] = 100 + i;
   for (uint32_t i = 0; i < 64; ++i) ((uint32_t *)texels.map)[i] = 1000 + i;

   VkDescriptorSetLayoutBinding binds[3] = {
      { 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT },
      { 1, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT },
      { 2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT },
   };
   VkDescriptorSetLayoutCreateInfo dli = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_DESCRIPTOR_BUFFER_BIT_EXT,
      .bindingCount = 3, .pBindings = binds };
   VkDescriptorSetLayout dsl;
   CHK(vkCreateDescriptorSetLayout(dev, &dli, NULL, &dsl));

   VkDeviceSize taille_set = 0;
   pfn_GetDescriptorSetLayoutSizeEXT(dev, dsl, &taille_set);
   VkDeviceSize off[3];
   for (uint32_t i = 0; i < 3; ++i)
      pfn_GetDescriptorSetLayoutBindingOffsetEXT(dev, dsl, i, &off[i]);
   printf("agencement : taille %llu, offsets %llu / %llu / %llu\n",
          (unsigned long long)taille_set, (unsigned long long)off[0],
          (unsigned long long)off[1], (unsigned long long)off[2]);

   VkDescriptorAddressInfoEXT a_in = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
      .address = entree.va, .range = 256, .format = VK_FORMAT_UNDEFINED };
   /* Decalage non nul : la vue commence au 8e texel. */
   const uint32_t decalage_texels = 8;
   VkDescriptorAddressInfoEXT a_tex = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
      .address = texels.va + decalage_texels * 4, .range = 256 - decalage_texels * 4,
      .format = VK_FORMAT_R32_UINT };
   VkDescriptorAddressInfoEXT a_out = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
      .address = sortie.va, .range = 256, .format = VK_FORMAT_UNDEFINED };
   VkDescriptorGetInfoEXT g;
   g = (VkDescriptorGetInfoEXT){ .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
      .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .data.pStorageBuffer = &a_in };
   pfn_GetDescriptorEXT(dev, &g, dbp.storageBufferDescriptorSize, (char *)descbuf.map + off[0]);
   g = (VkDescriptorGetInfoEXT){ .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
      .type = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .data.pStorageTexelBuffer = &a_tex };
   pfn_GetDescriptorEXT(dev, &g, dbp.storageTexelBufferDescriptorSize, (char *)descbuf.map + off[1]);
   g = (VkDescriptorGetInfoEXT){ .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
      .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .data.pStorageBuffer = &a_out };
   pfn_GetDescriptorEXT(dev, &g, dbp.storageBufferDescriptorSize, (char *)descbuf.map + off[2]);

   FILE *f = fopen(spv_path, "rb");
   if (!f) { printf("pas de %s\n", spv_path); return 1; }
   fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(sz);
   if (fread(code, 1, sz, f) != (size_t)sz) { printf("lecture spv\n"); return 1; }
   fclose(f);

   VkShaderModuleCreateInfo smi = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sz, .pCode = code };
   VkShaderModule sm; CHK(vkCreateShaderModule(dev, &smi, NULL, &sm));
   VkPipelineLayoutCreateInfo pli = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1, .pSetLayouts = &dsl };
   VkPipelineLayout pl; CHK(vkCreatePipelineLayout(dev, &pli, NULL, &pl));
   VkComputePipelineCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .flags = VK_PIPELINE_CREATE_DESCRIPTOR_BUFFER_BIT_EXT,
      .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                 .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main" },
      .layout = pl };
   VkPipeline pipe; CHK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpi, NULL, &pipe));

   VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .queueFamilyIndex = qfam };
   VkCommandPool pool; CHK(vkCreateCommandPool(dev, &cpci, NULL, &pool));
   VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   VkCommandBuffer cb; CHK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
   CHK(vkBeginCommandBuffer(cb, &bi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   VkDescriptorBufferBindingInfoEXT bbi = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
      .address = descbuf.va,
      .usage = VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT |
               VK_BUFFER_USAGE_SAMPLER_DESCRIPTOR_BUFFER_BIT_EXT };
   pfn_CmdBindDescriptorBuffersEXT(cb, 1, &bbi);
   uint32_t idx = 0; VkDeviceSize zero = 0;
   pfn_CmdSetDescriptorBufferOffsetsEXT(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &idx, &zero);
   vkCmdDispatch(cb, 16, 1, 1);
   CHK(vkEndCommandBuffer(cb));

   VkQueue queue; vkGetDeviceQueue(dev, qfam, 0, &queue);
   VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
   CHK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
   CHK(vkQueueWaitIdle(queue));

   int bons = 0;
   for (uint32_t i = 0; i < 16; ++i) {
      uint32_t attendu = (100 + i) + (1000 + i + decalage_texels);
      uint32_t lu = ((uint32_t *)sortie.map)[i];
      uint32_t ecrit = ((uint32_t *)texels.map)[decalage_texels + i];
      if (i < 4) printf("  texels[%u] ecrit par le shader = %u (attendu %u)\n",
                        decalage_texels + i, ecrit, 7000 + i);
      if (lu == attendu) ++bons;
      if (i < 4) printf("  sortie[%u] = %u  (attendu %u)\n", i, lu, attendu);
   }
   printf("%s : %d / 16 valeurs exactes\n", bons == 16 ? "SUCCES" : "ECHEC", bons);
   return bons == 16 ? 0 : 1;
}
