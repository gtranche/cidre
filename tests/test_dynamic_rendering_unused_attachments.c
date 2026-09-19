/* Test cible de VK_EXT_dynamic_rendering_unused_attachments sur KosmicKrisp. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "shaders.h"

#define CK(x) do { VkResult _r = (x); if (_r != VK_SUCCESS) { \
   printf("ECHEC %s -> %d (ligne %d)\n", #x, _r, __LINE__); exit(1);} } while (0)

#define W 64
#define H 64
#define COLOR_FMT VK_FORMAT_R8G8B8A8_UNORM
#define DEPTH_FMT VK_FORMAT_D32_SFLOAT

static VkInstance inst;
static VkPhysicalDevice pdev;
static VkDevice dev;
static VkQueue queue;
static uint32_t qfam;
static VkCommandPool pool;
static VkShaderModule vs_mod, fs_mod;
static VkPipelineLayout layout;
static VkImageView color_view, depth_view;
static VkImage color_img;
static VkBuffer readback_buf;
static VkDeviceMemory readback_mem;
static int failures;

static VkShaderModule mk_shader(const unsigned char *code, unsigned len) {
   VkShaderModuleCreateInfo ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = len, .pCode = (const uint32_t *)code };
   VkShaderModule m; CK(vkCreateShaderModule(dev, &ci, NULL, &m)); return m;
}

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags props) {
   VkPhysicalDeviceMemoryProperties mp;
   vkGetPhysicalDeviceMemoryProperties(pdev, &mp);
   for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
      if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & props) == props)
         return i;
   printf("pas de type memoire\n"); exit(1);
}

static VkImageView mk_attachment(VkFormat fmt, VkImageUsageFlags usage,
                                 VkImageAspectFlags aspect) {
   VkImageCreateInfo ici = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D, .format = fmt,
      .extent = {W, H, 1}, .mipLevels = 1, .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = usage, .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
   VkImage img; CK(vkCreateImage(dev, &ici, NULL, &img));
   if (aspect == VK_IMAGE_ASPECT_COLOR_BIT) color_img = img;
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
   VkMemoryAllocateInfo mai = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size,
      .memoryTypeIndex = mem_type(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
   VkDeviceMemory mem; CK(vkAllocateMemory(dev, &mai, NULL, &mem));
   CK(vkBindImageMemory(dev, img, mem, 0));
   VkImageViewCreateInfo vci = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = img,
      .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = fmt,
      .subresourceRange = {aspect, 0, 1, 0, 1} };
   VkImageView view; CK(vkCreateImageView(dev, &vci, NULL, &view));
   return view;
}

/* Pipeline declarant `color_fmt` (eventuellement UNDEFINED) et `depth_fmt`. */
static VkPipeline mk_pipeline(VkFormat color_fmt, VkFormat depth_fmt, int depth_test) {
   VkPipelineShaderStageCreateInfo stages[2] = {
      { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = vs_mod, .pName = "main" },
      { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = fs_mod, .pName = "main" } };
   VkPipelineVertexInputStateCreateInfo vi = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
   VkPipelineInputAssemblyStateCreateInfo ia = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
   VkViewport vp = {0, 0, W, H, 0, 1};
   VkRect2D sc = {{0, 0}, {W, H}};
   VkPipelineViewportStateCreateInfo vps = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1, .pViewports = &vp, .scissorCount = 1, .pScissors = &sc };
   VkPipelineRasterizationStateCreateInfo rs = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f };
   VkPipelineMultisampleStateCreateInfo ms = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT };
   VkPipelineDepthStencilStateCreateInfo ds = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
      .depthTestEnable = depth_test, .depthWriteEnable = depth_test,
      .depthCompareOp = VK_COMPARE_OP_LESS };
   VkPipelineColorBlendAttachmentState cba = { .colorWriteMask = 0xf };
   VkPipelineColorBlendStateCreateInfo cb = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = 1, .pAttachments = &cba };
   VkPipelineRenderingCreateInfo rend = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount = 1, .pColorAttachmentFormats = &color_fmt,
      .depthAttachmentFormat = depth_fmt };
   VkGraphicsPipelineCreateInfo gp = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &rend,
      .stageCount = 2, .pStages = stages, .pVertexInputState = &vi,
      .pInputAssemblyState = &ia, .pViewportState = &vps,
      .pRasterizationState = &rs, .pMultisampleState = &ms,
      .pDepthStencilState = &ds, .pColorBlendState = &cb, .layout = layout };
   VkPipeline p; CK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gp, NULL, &p));
   return p;
}

static void mk_readback(void) {
   VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = W * H * 4, .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
   CK(vkCreateBuffer(dev, &bci, NULL, &readback_buf));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, readback_buf, &mr);
   VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size,
      .memoryTypeIndex = mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) };
   CK(vkAllocateMemory(dev, &mai, NULL, &readback_mem));
   CK(vkBindBufferMemory(dev, readback_buf, readback_mem, 0));
}

static void barrier(VkCommandBuffer cb, VkImageLayout from, VkImageLayout to,
                    VkAccessFlags src, VkAccessFlags dst,
                    VkPipelineStageFlags sstage, VkPipelineStageFlags dstage) {
   VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .srcAccessMask = src, .dstAccessMask = dst, .oldLayout = from, .newLayout = to,
      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = color_img,
      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1} };
   vkCmdPipelineBarrier(cb, sstage, dstage, 0, 0, NULL, 0, NULL, 1, &b);
}

/* Enregistre une passe avec/sans attachements et dessine. */
static void run(const char *name, VkPipeline pipe, int bind_color, int bind_depth,
                const char *expect) {
   VkCommandBufferAllocateInfo ai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &ai, &cb));
   VkCommandBufferBeginInfo bi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
   CK(vkBeginCommandBuffer(cb, &bi));

   VkRenderingAttachmentInfo color = {
      .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      .imageView = bind_color ? color_view : VK_NULL_HANDLE,
      .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE };
   VkRenderingAttachmentInfo depth = {
      .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      .imageView = bind_depth ? depth_view : VK_NULL_HANDLE,
      .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
      .clearValue.depthStencil.depth = 1.0f };
   VkRenderingInfo ri = {
      .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
      .renderArea = {{0, 0}, {W, H}}, .layerCount = 1,
      .colorAttachmentCount = 1, .pColorAttachments = &color,
      .pDepthAttachment = bind_depth ? &depth : NULL };

   if (bind_color)
      barrier(cb, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
              0, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
              VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);

   vkCmdBeginRendering(cb, &ri);
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
   vkCmdDraw(cb, 3, 1, 0, 0);
   vkCmdEndRendering(cb);

   if (bind_color && expect) {
      barrier(cb, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
              VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
              VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT,
              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
              VK_PIPELINE_STAGE_TRANSFER_BIT);
      VkBufferImageCopy c = { .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
                              .imageExtent = {W, H, 1} };
      vkCmdCopyImageToBuffer(cb, color_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                             readback_buf, 1, &c);
   }
   CK(vkEndCommandBuffer(cb));

   VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                       .commandBufferCount = 1, .pCommandBuffers = &cb };
   VkResult r = vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE);
   VkResult w = vkQueueWaitIdle(queue);
   int ok = (r == VK_SUCCESS && w == VK_SUCCESS);
   char got[32] = "";
   if (ok && bind_color && expect) {
      unsigned char *px; CK(vkMapMemory(dev, readback_mem, 0, VK_WHOLE_SIZE, 0, (void **)&px));
      snprintf(got, sizeof(got), "%02x%02x%02x%02x", px[0], px[1], px[2], px[3]);
      vkUnmapMemory(dev, readback_mem);
      if (strcmp(got, expect) != 0) ok = 0;
   }
   if (!ok) failures++;
   if (expect)
      printf("  %-56s %s  pixel=%s attendu=%s\n", name, ok ? "OK   " : "ECHEC", got, expect);
   else
      printf("  %-56s %s\n", name, ok ? "OK   " : "ECHEC");
   vkFreeCommandBuffers(dev, pool, 1, &cb);
}

int main(void) {
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                             .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                .pApplicationInfo = &app };
   CK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t n = 1; CK(vkEnumeratePhysicalDevices(inst, &n, &pdev));

   VkPhysicalDeviceDynamicRenderingUnusedAttachmentsFeaturesEXT dru = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_FEATURES_EXT };
   VkPhysicalDeviceVulkan13Features v13 = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .pNext = &dru };
   VkPhysicalDeviceFeatures2 f2 = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v13 };
   vkGetPhysicalDeviceFeatures2(pdev, &f2);
   printf("dynamicRendering=%d dynamicRenderingUnusedAttachments=%d\n\n",
          v13.dynamicRendering, dru.dynamicRenderingUnusedAttachments);
   if (!dru.dynamicRenderingUnusedAttachments) {
      printf("feature absente, test sans objet\n"); return 2;
   }

   uint32_t qn = 0; vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, NULL);
   VkQueueFamilyProperties *qp = calloc(qn, sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qn, qp);
   for (uint32_t i = 0; i < qn; i++)
      if (qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qfam = i; break; }

   float prio = 1.0f;
   VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                   .queueFamilyIndex = qfam, .queueCount = 1,
                                   .pQueuePriorities = &prio };
   const char *exts[] = { VK_EXT_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_EXTENSION_NAME };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                              .pNext = &f2, .queueCreateInfoCount = 1,
                              .pQueueCreateInfos = &qci,
                              .enabledExtensionCount = 1, .ppEnabledExtensionNames = exts };
   CK(vkCreateDevice(pdev, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qfam, 0, &queue);

   VkCommandPoolCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                   .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                                   .queueFamilyIndex = qfam };
   CK(vkCreateCommandPool(dev, &pci, NULL, &pool));
   vs_mod = mk_shader(vs_spv, vs_spv_len);
   fs_mod = mk_shader(fs_spv, fs_spv_len);
   VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
   CK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));
   color_view = mk_attachment(COLOR_FMT, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                                         VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                              VK_IMAGE_ASPECT_COLOR_BIT);
   depth_view = mk_attachment(DEPTH_FMT, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                              VK_IMAGE_ASPECT_DEPTH_BIT);

   VkPipeline p_color   = mk_pipeline(COLOR_FMT, VK_FORMAT_UNDEFINED, 0);
   VkPipeline p_nocolor = mk_pipeline(VK_FORMAT_UNDEFINED, VK_FORMAT_UNDEFINED, 0);
   VkPipeline p_depth   = mk_pipeline(COLOR_FMT, DEPTH_FMT, 1);

   printf("temoins (formats concordants) :\n");
   mk_readback();
   run("pipeline=RGBA8 | passe AVEC couleur", p_color, 1, 0, "ff0000ff");
   run("pipeline=RGBA8+depth | passe AVEC couleur+depth", p_depth, 1, 1, "ff0000ff");

   printf("\nVK_EXT_dynamic_rendering_unused_attachments :\n");
   run("pipeline=RGBA8 | passe SANS couleur (imageView NULL)", p_color, 0, 0, NULL);
   run("pipeline=UNDEFINED | passe AVEC couleur (non ecrite)", p_nocolor, 1, 0, "00000000");
   run("pipeline=depth+test actif | passe SANS depth", p_depth, 1, 0, "ff0000ff");

   printf("\n%s (%d echec(s))\n", failures ? "ECHECS" : "TOUS LES CAS PASSENT", failures);
   return failures ? 1 : 0;
}
