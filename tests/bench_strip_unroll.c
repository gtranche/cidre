/* Cout du correctif 0033 : deroulement force des bandes indexees en uint32
 * quand le redemarrage de primitive est desactive.
 *
 * Trois configurations :
 *   strip32 : TRIANGLE_STRIP / uint32 / restart off  -> deroule avec 0033 seulement
 *   strip16 : TRIANGLE_STRIP / uint16 / restart off  -> deroule dans les deux cas (temoin)
 *   list32  : TRIANGLE_LIST  / uint32                -> jamais deroule (temoin)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <vulkan/vulkan.h>
#include "strip_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 256
#define H 256

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static VkImage color; static VkDeviceMemory color_mem; static VkImageView view;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }
static VkShaderModule mk(const unsigned char *c, unsigned l){
   VkShaderModuleCreateInfo ci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=l,.pCode=(const uint32_t*)c};
   VkShaderModule m; CK(vkCreateShaderModule(dev,&ci,NULL,&m)); return m; }
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec + t.tv_nsec*1e-9; }
static int cmp_d(const void *a, const void *b){ double x=*(const double*)a, y=*(const double*)b; return x<y?-1:(x>y); }

static void mk_buffer(VkDeviceSize sz, VkBufferUsageFlags use, VkBuffer *b, VkDeviceMemory *m, void **map){
   VkBufferCreateInfo bi={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=sz,.usage=use};
   CK(vkCreateBuffer(dev,&bi,NULL,b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,*b,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,m)); CK(vkBindBufferMemory(dev,*b,*m,0));
   CK(vkMapMemory(dev,*m,0,VK_WHOLE_SIZE,0,map));
}

int main(int argc, char **argv){
   const char *mode = argc>1 ? argv[1] : "strip32";
   uint32_t nidx    = argc>2 ? (uint32_t)atoi(argv[2]) : 256;
   uint32_t ndraw   = argc>3 ? (uint32_t)atoi(argv[3]) : 200;
   uint32_t niter   = argc>4 ? (uint32_t)atoi(argv[4]) : 60;

   bool u16  = !strcmp(mode,"strip16");
   bool list = !strcmp(mode,"list32");
   if (strcmp(mode,"strip32") && !u16 && !list){ printf("mode inconnu: %s\n",mode); return 2; }

   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(pdev,&pp);

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceDynamicRenderingFeatures dr={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,.dynamicRendering=VK_TRUE};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&dr,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

   VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
      .format=VK_FORMAT_R8G8B8A8_UNORM,.extent={W,H,1},.mipLevels=1,.arrayLayers=1,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT};
   CK(vkCreateImage(dev,&ii,NULL,&color));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,color,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&color_mem)); CK(vkBindImageMemory(dev,color,color_mem,0));
   VkImageViewCreateInfo vi={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=color,
      .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   CK(vkCreateImageView(dev,&vi,NULL,&view));

   VkBuffer ib; VkDeviceMemory ib_mem; void *ib_map;
   VkDeviceSize esz = u16 ? 2 : 4;
   mk_buffer(nidx*esz, VK_BUFFER_USAGE_INDEX_BUFFER_BIT, &ib, &ib_mem, &ib_map);
   for(uint32_t i=0;i<nidx;i++){
      if(u16) ((uint16_t*)ib_map)[i] = (uint16_t)i;
      else    ((uint32_t*)ib_map)[i] = i;
   }

   VkPipelineLayoutCreateInfo pli={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&pli,NULL,&pl));
   VkShaderModule vs=mk(vs_spv,vs_spv_len), fs=mk(fs_spv,fs_spv_len);
   VkPipelineShaderStageCreateInfo st[2]={
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vin={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo iaci={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = list ? VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
      .primitiveRestartEnable = VK_FALSE};
   VkViewport vp={0,0,W,H,0,1}; VkRect2D sc={{0,0},{W,H}};
   VkPipelineViewportStateCreateInfo vsc={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.lineWidth=1.f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount=1,.pAttachments=&cba};
   VkFormat cf=VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo prci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount=1,.pColorAttachmentFormats=&cf};
   VkGraphicsPipelineCreateInfo gpi={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&prci,
      .stageCount=2,.pStages=st,.pVertexInputState=&vin,.pInputAssemblyState=&iaci,
      .pViewportState=&vsc,.pRasterizationState=&rs,.pMultisampleState=&ms,
      .pColorBlendState=&cb,.layout=pl};
   VkPipeline pipe; CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gpi,NULL,&pipe));

   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb2; CK(vkAllocateCommandBuffers(dev,&cbai,&cb2));
   VkFenceCreateInfo fci={.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
   VkFence fence; CK(vkCreateFence(dev,&fci,NULL,&fence));

   double *rec=calloc(niter,sizeof(double)), *gpu=calloc(niter,sizeof(double));

   for(uint32_t it=0; it<niter; it++){
      CK(vkResetCommandBuffer(cb2,0));
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cb2,&bi));
      VkImageMemoryBarrier imb={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
         .image=color,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1},
         .dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT};
      vkCmdPipelineBarrier(cb2,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,0,NULL,0,NULL,1,&imb);
      VkRenderingAttachmentInfo rai={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=view,.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE,
         .clearValue={{{0,0,0,1}}}};
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea={{0,0},{W,H}},
         .layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&rai};
      vkCmdBeginRendering(cb2,&ri);
      vkCmdBindPipeline(cb2,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
      vkCmdBindIndexBuffer(cb2,ib,0, u16?VK_INDEX_TYPE_UINT16:VK_INDEX_TYPE_UINT32);

      double t0=now();
      for(uint32_t d=0; d<ndraw; d++) vkCmdDrawIndexed(cb2,nidx,1,0,0,0);
      rec[it]=now()-t0;

      vkCmdEndRendering(cb2);
      CK(vkEndCommandBuffer(cb2));
      CK(vkResetFences(dev,1,&fence));
      VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb2};
      double t1=now();
      CK(vkQueueSubmit(queue,1,&si,fence));
      CK(vkWaitForFences(dev,1,&fence,VK_TRUE,UINT64_MAX));
      gpu[it]=now()-t1;
   }

   uint32_t warm = niter/4;           /* on jette le premier quart */
   uint32_t k = niter - warm;
   qsort(rec+warm,k,sizeof(double),cmp_d);
   qsort(gpu+warm,k,sizeof(double),cmp_d);
   double mrec=rec[warm+k/2], mgpu=gpu[warm+k/2];

   printf("%-8s  indices=%-6u draws=%-5u iters=%-4u  %s\n", mode, nidx, ndraw, niter, pp.deviceName);
   printf("  enregistrement  mediane %9.3f ms  soit %8.3f us/draw\n", mrec*1e3, mrec*1e6/ndraw);
   printf("  soumission+GPU  mediane %9.3f ms  soit %8.3f us/draw\n", mgpu*1e3, mgpu*1e6/ndraw);
   printf("  total           mediane %9.3f ms  soit %8.3f us/draw\n",
          (mrec+mgpu)*1e3, (mrec+mgpu)*1e6/ndraw);
   return 0;
}
