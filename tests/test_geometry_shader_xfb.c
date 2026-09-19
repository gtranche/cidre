/* Capture (transform feedback) depuis un geometry shader sur KosmicKrisp.
 *
 * Quatre points entrent ; le GS emet trois sommets par point et capture
 * (primitive, sommet, 3, 4). On relit le buffer de capture et le buffer de
 * compteur. Le cas "reprise" repart du compteur ecrit par le GPU.
 *
 * Shaders : glslang -V, embarques par build_geometry_shader_xfb.sh.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <math.h>
#include <vulkan/vulkan.h>
#include "gs_xfb_shaders.h"

#define CK(x) do { VkResult _r = (x); if (_r != VK_SUCCESS) { \
   printf("ECHEC %s -> %d (ligne %d)\n", #x, _r, __LINE__); exit(1);} } while (0)

#define W 64
#define H 64
#define NPRIM 4
#define NVERT_PER_PRIM 3
#define STRIDE 16
#define NCAP (NPRIM * NVERT_PER_PRIM)

static VkInstance inst;
static VkPhysicalDevice pdev;
static VkDevice dev;
static VkQueue queue;
static uint32_t qfam;
static VkCommandPool pool;
static VkImage color;
static VkDeviceMemory color_mem;
static VkImageView color_view;
static VkPipelineLayout layout;
static VkPipeline pipe;
static VkBuffer xfb_buf, xfb_buf2, counter_buf;
static VkDeviceMemory xfb_mem, xfb_mem2, counter_mem;
static int multistream;
static PFN_vkCmdBindTransformFeedbackBuffersEXT pBind;
static PFN_vkCmdBeginTransformFeedbackEXT pBegin;
static PFN_vkCmdEndTransformFeedbackEXT pEnd;
static PFN_vkCmdBeginQueryIndexedEXT pBeginQ;
static PFN_vkCmdEndQueryIndexedEXT pEndQ;
static VkQueryPool qpool = VK_NULL_HANDLE;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags props)
{
   VkPhysicalDeviceMemoryProperties mp;
   vkGetPhysicalDeviceMemoryProperties(pdev, &mp);
   for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
      if ((bits & (1u << i)) &&
          (mp.memoryTypes[i].propertyFlags & props) == props)
         return i;
   printf("pas de type memoire\n");
   exit(1);
}

static void mk_buffer(VkDeviceSize size, VkBufferUsageFlags usage,
                      VkBuffer *buf, VkDeviceMemory *mem)
{
   VkBufferCreateInfo bci = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                             .size = size, .usage = usage,
                             .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
   CK(vkCreateBuffer(dev, &bci, NULL, buf));
   VkMemoryRequirements mr;
   vkGetBufferMemoryRequirements(dev, *buf, &mr);
   VkMemoryAllocateInfo mai = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size,
      .memoryTypeIndex = mem_type(mr.memoryTypeBits,
                                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                     VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev, &mai, NULL, mem));
   CK(vkBindBufferMemory(dev, *buf, *mem, 0));
}

static VkShaderModule mk_module(const unsigned char *code, unsigned len)
{
   VkShaderModuleCreateInfo ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = len, .pCode = (const uint32_t *)code};
   VkShaderModule m;
   CK(vkCreateShaderModule(dev, &ci, NULL, &m));
   return m;
}

static void setup(int slots)
{
   VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                            .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                               .pApplicationInfo = &app};
   CK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t n = 1;
   CK(vkEnumeratePhysicalDevices(inst, &n, &pdev));

   VkPhysicalDeviceTransformFeedbackFeaturesEXT tf = {
      .sType =
         VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_FEATURES_EXT};
   VkPhysicalDeviceFeatures2 f2 = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &tf};
   vkGetPhysicalDeviceFeatures2(pdev, &f2);
   printf("transformFeedback=%d geometryShader=%d geometryStreams=%d\n\n",
          tf.transformFeedback, f2.features.geometryShader, tf.geometryStreams);
   if (!tf.transformFeedback || !f2.features.geometryShader) {
      printf("feature absente, test sans objet\n");
      exit(77);
   }

   uint32_t qn = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, NULL);
   VkQueueFamilyProperties *qp = calloc(qn, sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, qp);
   for (uint32_t i = 0; i < qn; i++)
      if (qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qfam = i; break; }
   free(qp);

   float prio = 1.0f;
   VkDeviceQueueCreateInfo dqi = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qfam, .queueCount = 1, .pQueuePriorities = &prio};
   VkPhysicalDeviceDynamicRenderingFeatures dr = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
      .dynamicRendering = VK_TRUE, .pNext = &tf};
   VkPhysicalDeviceFeatures want = {.geometryShader = VK_TRUE};
   const char *exts[] = {VK_EXT_TRANSFORM_FEEDBACK_EXTENSION_NAME};
   VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                             .pNext = &dr,
                             .queueCreateInfoCount = 1,
                             .pQueueCreateInfos = &dqi,
                             .enabledExtensionCount = 1,
                             .ppEnabledExtensionNames = exts,
                             .pEnabledFeatures = &want};
   CK(vkCreateDevice(pdev, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qfam, 0, &queue);

   pBind = (void *)vkGetDeviceProcAddr(dev,
                                       "vkCmdBindTransformFeedbackBuffersEXT");
   pBegin = (void *)vkGetDeviceProcAddr(dev, "vkCmdBeginTransformFeedbackEXT");
   pEnd = (void *)vkGetDeviceProcAddr(dev, "vkCmdEndTransformFeedbackEXT");
   if (!pBind || !pBegin || !pEnd) {
      printf("ECHEC: points d'entree manquants\n");
      exit(1);
   }
   pBeginQ = (void *)vkGetDeviceProcAddr(dev, "vkCmdBeginQueryIndexedEXT");
   pEndQ = (void *)vkGetDeviceProcAddr(dev, "vkCmdEndQueryIndexedEXT");

   VkCommandPoolCreateInfo cpi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = qfam};
   CK(vkCreateCommandPool(dev, &cpi, NULL, &pool));

   VkImageCreateInfo ici2 = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM,
      .extent = {W, H, 1}, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED};
   CK(vkCreateImage(dev, &ici2, NULL, &color));
   VkMemoryRequirements mr;
   vkGetImageMemoryRequirements(dev, color, &mr);
   VkMemoryAllocateInfo mai = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size,
      .memoryTypeIndex = mem_type(mr.memoryTypeBits,
                                  VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev, &mai, NULL, &color_mem));
   CK(vkBindImageMemory(dev, color, color_mem, 0));
   VkImageViewCreateInfo ivci = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = color,
      .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   CK(vkCreateImageView(dev, &ivci, NULL, &color_view));

   mk_buffer(slots * STRIDE, VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_BUFFER_BIT_EXT,
             &xfb_buf, &xfb_mem);
   mk_buffer(slots * STRIDE, VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_BUFFER_BIT_EXT,
             &xfb_buf2, &xfb_mem2);
   mk_buffer(sizeof(uint32_t),
             VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_COUNTER_BUFFER_BIT_EXT |
                VK_BUFFER_USAGE_TRANSFER_DST_BIT,
             &counter_buf, &counter_mem);
   void *m;
   CK(vkMapMemory(dev, xfb_mem, 0, VK_WHOLE_SIZE, 0, &m));
   memset(m, 0xAB, slots * STRIDE);
   vkUnmapMemory(dev, xfb_mem);
   CK(vkMapMemory(dev, xfb_mem2, 0, VK_WHOLE_SIZE, 0, &m));
   memset(m, 0xAB, slots * STRIDE);
   vkUnmapMemory(dev, xfb_mem2);
   CK(vkMapMemory(dev, counter_mem, 0, VK_WHOLE_SIZE, 0, &m));
   *(uint32_t *)m = 0xDEADBEEF;
   vkUnmapMemory(dev, counter_mem);

   if (pBeginQ && pEndQ) {
      VkQueryPoolCreateInfo qi = {
         .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
         .queryType = VK_QUERY_TYPE_TRANSFORM_FEEDBACK_STREAM_EXT,
         .queryCount = 2};
      CK(vkCreateQueryPool(dev, &qi, NULL, &qpool));
   }

   VkPipelineLayoutCreateInfo plci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   CK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));

   VkShaderModule vs = mk_module(vs_spv, vs_spv_len);
   VkShaderModule gs = mk_module(multistream ? gsms_spv : gs_spv,
                                 multistream ? gsms_spv_len : gs_spv_len);
   VkShaderModule fs = mk_module(fs_spv, fs_spv_len);
   VkPipelineShaderStageCreateInfo st[3] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = vs, .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_GEOMETRY_BIT, .module = gs, .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = fs, .pName = "main"}};

   VkPipelineVertexInputStateCreateInfo vi = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST};
   VkViewport vp = {0, 0, W, H, 0, 1};
   VkRect2D sc = {{0, 0}, {W, H}};
   VkPipelineViewportStateCreateInfo vps = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1, .pViewports = &vp, .scissorCount = 1,
      .pScissors = &sc};
   VkPipelineRasterizationStateCreateInfo rs = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f};
   VkPipelineMultisampleStateCreateInfo ms = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba = {.colorWriteMask = 0xf};
   VkPipelineColorBlendStateCreateInfo cb = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = 1, .pAttachments = &cba};
   VkFormat cfmt = VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo prci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount = 1, .pColorAttachmentFormats = &cfmt};
   VkGraphicsPipelineCreateInfo gpi = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .pNext = &prci, .stageCount = 3, .pStages = st,
      .pVertexInputState = &vi, .pInputAssemblyState = &ia,
      .pViewportState = &vps, .pRasterizationState = &rs,
      .pMultisampleState = &ms, .pColorBlendState = &cb, .layout = layout};
   CK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gpi, NULL, &pipe));
   vkDestroyShaderModule(dev, vs, NULL);
   vkDestroyShaderModule(dev, gs, NULL);
   vkDestroyShaderModule(dev, fs, NULL);
}

int main(int argc, char **argv)
{
   int mode = argc > 1 ? atoi(argv[1]) : 0;
   int resume = mode == 1;
   multistream = mode == 2;
   /* Le GS multi-flux emet un point par flux et par primitive d'entree. */
   int slots = multistream ? NPRIM : (resume ? 2 * NCAP : NCAP);

   setup(slots);

   VkCommandBufferAllocateInfo cbai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1};
   VkCommandBuffer cb;
   CK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkCommandBufferBeginInfo bi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb, &bi));

   VkImageMemoryBarrier to_color = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .image = color,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0,
                        NULL, 0, NULL, 1, &to_color);

   VkDeviceSize off[2] = {0, 0}, sz[2] = {slots * STRIDE, slots * STRIDE};
   VkBuffer bufs[2] = {xfb_buf, xfb_buf2};
   VkDeviceSize coff = 0;
   pBind(cb, 0, multistream ? 2 : 1, bufs, off, sz);

   VkRenderingAttachmentInfo att = {
      .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      .imageView = color_view,
      .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
      .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
      .clearValue = {.color = {.float32 = {0, 0, 0, 1}}}};
   VkRenderingInfo ri = {.sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
                         .renderArea = {{0, 0}, {W, H}}, .layerCount = 1,
                         .colorAttachmentCount = 1, .pColorAttachments = &att};
   vkCmdBeginRendering(cb, &ri);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);

   if (qpool) {
      vkCmdResetQueryPool(cb, qpool, 0, 2);
      pBeginQ(cb, qpool, 0, 0, 0);
      if (multistream)
         pBeginQ(cb, qpool, 1, 0, 1);
   }

   pBegin(cb, 0, 0, NULL, NULL);
   vkCmdDraw(cb, NPRIM, 1, 0, 0);
   pEnd(cb, 0, 1, &counter_buf, &coff);

   if (resume) {
      pBegin(cb, 0, 1, &counter_buf, &coff);
      vkCmdDraw(cb, NPRIM, 1, 0, 0);
      pEnd(cb, 0, 1, &counter_buf, &coff);
   }

   if (qpool) {
      if (multistream)
         pEndQ(cb, qpool, 1, 1);
      pEndQ(cb, qpool, 0, 0);
   }

   vkCmdEndRendering(cb);
   CK(vkEndCommandBuffer(cb));

   VkSubmitInfo si = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                      .commandBufferCount = 1, .pCommandBuffers = &cb};
   CK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
   CK(vkQueueWaitIdle(queue));

   float *cap;
   CK(vkMapMemory(dev, xfb_mem, 0, VK_WHOLE_SIZE, 0, (void **)&cap));
   int fail = 0;
   printf("%s\n", multistream ? "capture depuis le GS, deux flux"
                  : resume     ? "capture depuis le GS, puis reprise"
                               : "capture depuis le GS");
   for (int i = 0; i < slots; i++) {
      int k = i % NCAP;
      float e[4] = {(float)(k / NVERT_PER_PRIM), (float)(k % NVERT_PER_PRIM),
                    3.0f, 4.0f};
      if (multistream) {
         e[0] = (float)i; e[1] = 1.0f; e[2] = 2.0f; e[3] = 3.0f;
      }
      float *v = &cap[i * 4];
      int ok = 1;
      for (int j = 0; j < 4; j++)
         if (fabsf(v[j] - e[j]) > 0.001f) ok = 0;
      printf("  flux 0, capture %2d : %.0f %.0f %.0f %.0f   (attendu %.0f %.0f "
             "%.0f %.0f) %s\n", i, v[0], v[1], v[2], v[3], e[0], e[1], e[2],
             e[3], ok ? "OK" : "ECHEC");
      if (!ok) fail++;
   }
   vkUnmapMemory(dev, xfb_mem);

   if (multistream) {
      CK(vkMapMemory(dev, xfb_mem2, 0, VK_WHOLE_SIZE, 0, (void **)&cap));
      for (int i = 0; i < slots; i++) {
         float e[4] = {(float)i, 5.0f, 6.0f, 7.0f};
         float *v = &cap[i * 4];
         int ok = 1;
         for (int j = 0; j < 4; j++)
            if (fabsf(v[j] - e[j]) > 0.001f) ok = 0;
         printf("  flux 1, capture %2d : %.0f %.0f %.0f %.0f   (attendu %.0f "
                "%.0f %.0f %.0f) %s\n", i, v[0], v[1], v[2], v[3], e[0], e[1],
                e[2], e[3], ok ? "OK" : "ECHEC");
         if (!ok) fail++;
      }
      vkUnmapMemory(dev, xfb_mem2);
   }

   uint32_t *cnt;
   CK(vkMapMemory(dev, counter_mem, 0, VK_WHOLE_SIZE, 0, (void **)&cnt));
   uint32_t expected = slots * STRIDE;
   printf("  compteur : %u octets (attendu %u)  %s\n", *cnt, expected,
          *cnt == expected ? "OK" : "ECHEC");
   if (*cnt != expected) fail++;
   vkUnmapMemory(dev, counter_mem);

   if (qpool) {
      uint64_t res[2] = {0, 0};
      VkResult qr = vkGetQueryPoolResults(
         dev, qpool, 0, 1, sizeof(res), res, sizeof(uint64_t),
         VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT);
      /* Chaque point entre produit une bande de trois sommets, soit une
       * primitive capturee par point. */
      uint64_t exp = resume ? 2 * NPRIM : NPRIM;
      int ok = (qr == VK_SUCCESS && res[0] == exp && res[1] == exp);
      printf("  requete TF flux 0 : ecrites=%llu generees=%llu (attendu "
             "%llu/%llu) %s\n", (unsigned long long)res[0],
             (unsigned long long)res[1], (unsigned long long)exp,
             (unsigned long long)exp, ok ? "OK" : "ECHEC");
      if (!ok) fail++;

      if (multistream) {
         uint64_t r2[2] = {0, 0};
         qr = vkGetQueryPoolResults(dev, qpool, 1, 1, sizeof(r2), r2,
                                    sizeof(uint64_t),
                                    VK_QUERY_RESULT_64_BIT |
                                       VK_QUERY_RESULT_WAIT_BIT);
         ok = (qr == VK_SUCCESS && r2[0] == exp && r2[1] == exp);
         printf("  requete TF flux 1 : ecrites=%llu generees=%llu (attendu "
                "%llu/%llu) %s\n", (unsigned long long)r2[0],
                (unsigned long long)r2[1], (unsigned long long)exp,
                (unsigned long long)exp, ok ? "OK" : "ECHEC");
         if (!ok) fail++;
      }
   }

   printf("\n%s (%d echec(s))\n", fail ? "ECHECS" : "TOUT PASSE", fail);
   return fail ? 1 : 0;
}
