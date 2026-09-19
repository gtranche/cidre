/* Geometry shader sur KosmicKrisp : le meme dessin en direct puis en indirect.
 *
 * Un point traverse un geometry shader qui en fait un quad plein ecran vert.
 * Le tampon est efface en rouge : un pixel central rouge veut dire que rien
 * n'a ete rasterise. Le cas direct sert de temoin au cas indirect.
 *
 * Shaders : glslang -V, puis embarques par build_geometry_shader_indirect.sh.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <vulkan/vulkan.h>
#include "gs_indirect_shaders.h"

#define CK(x) do { VkResult _r = (x); if (_r != VK_SUCCESS) { \
   printf("ECHEC %s -> %d (ligne %d)\n", #x, _r, __LINE__); exit(1);} } while (0)

#define W 64
#define H 128
/* Pas un multiple de la taille de groupe : un dispatch indirect, qui ne peut
 * compter qu en groupes, lance alors 63 invocations de trop. */
#define NPOINTS 65
#define COLOR_FMT VK_FORMAT_R8G8B8A8_UNORM

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
static VkPipeline pipe_static, pipe_dynamic;
static VkBuffer readback, indirect_buf;
static VkDeviceMemory readback_mem, indirect_mem;

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
                             .size = size,
                             .usage = usage,
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

static VkShaderModule mk_module(const uint32_t *code, size_t size)
{
   VkShaderModuleCreateInfo ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = size,
      .pCode = code};
   VkShaderModule m;
   CK(vkCreateShaderModule(dev, &ci, NULL, &m));
   return m;
}

static void setup(void)
{
   VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                            .apiVersion = VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici = {.sType =
                                  VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                               .pApplicationInfo = &app};
   CK(vkCreateInstance(&ici, NULL, &inst));

   uint32_t n = 1;
   CK(vkEnumeratePhysicalDevices(inst, &n, &pdev));

   VkPhysicalDeviceFeatures feats;
   vkGetPhysicalDeviceFeatures(pdev, &feats);
   if (!feats.geometryShader) {
      printf("geometryShader absent, test sans objet\n");
      exit(77);
   }

   uint32_t qn = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, NULL);
   VkQueueFamilyProperties *qp = malloc(qn * sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, qp);
   qfam = 0;
   for (uint32_t i = 0; i < qn; i++)
      if (qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qfam = i; break; }
   free(qp);

   float prio = 1.0f;
   VkDeviceQueueCreateInfo dqi = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qfam,
      .queueCount = 1,
      .pQueuePriorities = &prio};
   VkPhysicalDeviceFeatures want = {.geometryShader = VK_TRUE,
                                    .multiDrawIndirect = VK_FALSE};
   VkPhysicalDeviceDynamicRenderingFeatures dr = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
      .dynamicRendering = VK_TRUE};
   VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                             .pNext = &dr,
                             .queueCreateInfoCount = 1,
                             .pQueueCreateInfos = &dqi,
                             .pEnabledFeatures = &want};
   CK(vkCreateDevice(pdev, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qfam, 0, &queue);

   VkCommandPoolCreateInfo cpi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = qfam};
   CK(vkCreateCommandPool(dev, &cpi, NULL, &pool));

   VkImageCreateInfo ici2 = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D,
      .format = COLOR_FMT,
      .extent = {W, H, 1},
      .mipLevels = 1,
      .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT,
      .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
               VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
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
      .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      .image = color,
      .viewType = VK_IMAGE_VIEW_TYPE_2D,
      .format = COLOR_FMT,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   CK(vkCreateImageView(dev, &ivci, NULL, &color_view));

   mk_buffer(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT, &readback,
             &readback_mem);
   mk_buffer(sizeof(VkDrawIndirectCommand),
             VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, &indirect_buf,
             &indirect_mem);

   VkDrawIndirectCommand *cmd;
   CK(vkMapMemory(dev, indirect_mem, 0, VK_WHOLE_SIZE, 0, (void **)&cmd));
   *cmd = (VkDrawIndirectCommand){.vertexCount = NPOINTS,
                                  .instanceCount = 1,
                                  .firstVertex = 0,
                                  .firstInstance = 0};
   vkUnmapMemory(dev, indirect_mem);

   VkPipelineLayoutCreateInfo plci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   CK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));

   VkShaderModule vs = mk_module(vs_spv, sizeof(vs_spv));
   VkShaderModule gs = mk_module(gs_spv, sizeof(gs_spv));
   VkShaderModule gsdyn = mk_module(gsdyn_spv, sizeof(gsdyn_spv));
   VkShaderModule fs = mk_module(fs_spv, sizeof(fs_spv));

   VkPipelineShaderStageCreateInfo stages[3] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = vs, .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_GEOMETRY_BIT, .module = gs, .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = fs, .pName = "main"},
   };

   VkPipelineVertexInputStateCreateInfo vi = {
      .sType =
         VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST};
   VkViewport vp = {0, 0, W, H, 0, 1};
   VkRect2D sc = {{0, 0}, {W, H}};
   VkPipelineViewportStateCreateInfo vps = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1, .pViewports = &vp,
      .scissorCount = 1, .pScissors = &sc};
   VkPipelineRasterizationStateCreateInfo rs = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL,
      .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
      .lineWidth = 1.0f};
   VkPipelineMultisampleStateCreateInfo ms = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba = {.colorWriteMask = 0xf};
   VkPipelineColorBlendStateCreateInfo cb = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = 1, .pAttachments = &cba};
   VkFormat cfmt = COLOR_FMT;
   VkPipelineRenderingCreateInfo prci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount = 1, .pColorAttachmentFormats = &cfmt};
   VkGraphicsPipelineCreateInfo gpi = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .pNext = &prci,
      .stageCount = 3, .pStages = stages,
      .pVertexInputState = &vi, .pInputAssemblyState = &ia,
      .pViewportState = &vps, .pRasterizationState = &rs,
      .pMultisampleState = &ms, .pColorBlendState = &cb,
      .layout = layout};
   CK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gpi, NULL,
                                &pipe_static));
   stages[1].module = gsdyn;
   CK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gpi, NULL,
                                &pipe_dynamic));

   vkDestroyShaderModule(dev, vs, NULL);
   vkDestroyShaderModule(dev, gs, NULL);
   vkDestroyShaderModule(dev, gsdyn, NULL);
   vkDestroyShaderModule(dev, fs, NULL);
}

/* Rend une fois, en direct ou en indirect, et rend la couleur du pixel
 * central sous forme 0xAABBGGRR. */
static void render(VkPipeline pipe, bool indirect, unsigned draws,
                   uint32_t *rows)
{
   VkCommandBufferAllocateInfo cbai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1};
   VkCommandBuffer cb;
   CK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkCommandBufferBeginInfo bi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb, &bi));

   VkImageMemoryBarrier to_color = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .srcAccessMask = 0,
      .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .image = color,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0,
                        NULL, 0, NULL, 1, &to_color);

   VkRenderingAttachmentInfo att = {
      .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      .imageView = color_view,
      .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
      .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
      .clearValue = {.color = {.float32 = {1.0f, 0.0f, 0.0f, 1.0f}}}};
   VkRenderingInfo ri = {.sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
                         .renderArea = {{0, 0}, {W, H}},
                         .layerCount = 1,
                         .colorAttachmentCount = 1,
                         .pColorAttachments = &att};
   vkCmdBeginRendering(cb, &ri);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
   for (unsigned d = 0; d < draws; d++) {
      if (indirect)
         vkCmdDrawIndirect(cb, indirect_buf, 0, 1,
                           sizeof(VkDrawIndirectCommand));
      else
         vkCmdDraw(cb, NPOINTS, 1, 0, 0);
   }
   vkCmdEndRendering(cb);

   VkImageMemoryBarrier to_src = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      .image = color,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                        VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1,
                        &to_src);

   VkBufferImageCopy copy = {
      .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
      .imageExtent = {W, H, 1}};
   vkCmdCopyImageToBuffer(cb, color, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                          readback, 1, &copy);
   CK(vkEndCommandBuffer(cb));

   VkSubmitInfo si = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                      .commandBufferCount = 1,
                      .pCommandBuffers = &cb};
   CK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
   CK(vkQueueWaitIdle(queue));
   vkFreeCommandBuffers(dev, pool, 1, &cb);

   uint32_t *px;
   CK(vkMapMemory(dev, readback_mem, 0, VK_WHOLE_SIZE, 0, (void **)&px));
   for (uint32_t y = 0; y < H; y++)
      rows[y] = px[y * W + (W / 2)];
   vkUnmapMemory(dev, readback_mem);
}

#define GREEN 0xff00ff00u
#define RED   0xff0000ffu

/* Chaque point peint la rangee de son primitive ID : les NPOINTS premieres
 * doivent etre vertes (une sur deux pour le compte dynamique), le reste rouge.
 * NPOINTS n'est pas un multiple de la taille de groupe, si bien qu'un dispatch
 * indirect lance des invocations en trop : elles peindraient les rangees
 * au-dela si la garde ne les arretait pas. */
static int check(const char *what, const uint32_t *rows, bool every_other)
{
   for (uint32_t y = 0; y < H; y++) {
      bool painted = y < NPOINTS && (!every_other || (y % 2) == 0);
      uint32_t want = painted ? GREEN : RED;
      if (rows[y] != want) {
         printf("%-28s ECHEC rangee %u : 0x%08x, attendu 0x%08x\n", what, y,
                rows[y], want);
         return 1;
      }
   }
   printf("%-28s OK\n", what);
   return 0;
}

int main(void)
{
   setup();

   int failures = 0;
   uint32_t rows[H];

   render(pipe_static, false, 1, rows);
   failures += check("compte statique, direct", rows, false);

   render(pipe_static, true, 1, rows);
   failures += check("compte statique, indirect", rows, false);

   render(pipe_dynamic, false, 1, rows);
   failures += check("compte dynamique, direct", rows, true);

   render(pipe_dynamic, true, 1, rows);
   failures += check("compte dynamique, indirect", rows, true);

   /* Deux dessins dans le meme command buffer puisent dans le meme tas : si le
    * premier ecrit au-dela de ce que poly lui a alloue, il abime les tampons du
    * second. */
   render(pipe_dynamic, true, 4, rows);
   failures += check("dynamique, 4 dessins", rows, true);

   printf("%s\n", failures ? "ECHEC" : "OK");
   return failures ? 1 : 0;
}
