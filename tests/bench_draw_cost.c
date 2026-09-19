/* D'ou viennent les 5,5 us par tirage ? On isole chaque cause de cout en
 * n'enregistrant que du CPU : aucun attente de GPU dans la mesure.
 *
 *   plain : lier une fois, puis N tirages
 *   push  : constantes de poussee changees avant chaque tirage
 *   desc  : ensemble de descripteurs different avant chaque tirage
 *   pipe  : pipeline different avant chaque tirage
 *   all   : les trois a la fois (le plus proche de Godot)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#endif
#include <vulkan/vulkan.h>
#include "drawcost_shaders.h"
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 256
#define H 256
#define NVAR 64

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
#ifdef _WIN32
static double now(void){
   LARGE_INTEGER f, c; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c);
   return (double)c.QuadPart / (double)f.QuadPart; }
#else
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec + t.tv_nsec*1e-9; }
#endif
static int cmp_d(const void *a,const void *b){ double x=*(const double*)a,y=*(const double*)b; return x<y?-1:(x>y); }

int main(int argc, char **argv){
   const char *mode = argc>1 ? argv[1] : "all";
   uint32_t ndraw = argc>2 ? (uint32_t)atoi(argv[2]) : 2000;
   uint32_t niter = argc>3 ? (uint32_t)atoi(argv[3]) : 40;
   bool m_push = !strcmp(mode,"push") || !strcmp(mode,"all");
   bool m_desc = !strcmp(mode,"desc") || !strcmp(mode,"all");
   bool m_pipe = !strcmp(mode,"pipe") || !strcmp(mode,"all");
   /* pipesame : relier le MEME pipeline a chaque tirage. Si cela coute autant que
    * "pipe", c'est qu'aucun filtrage de liaison redondante n'a lieu. */
   bool m_pipe1 = !strcmp(mode,"pipesame");
   bool m_desc1 = !strcmp(mode,"descsame");
   if (strcmp(mode,"plain") && !m_push && !m_desc && !m_pipe && !m_pipe1 && !m_desc1){
      printf("mode inconnu\n"); return 2; }

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

   /* un tampon uniforme par variante */
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=256*NVAR,
      .usage=VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT};
   VkBuffer ubo; CK(vkCreateBuffer(dev,&bci,NULL,&ubo));
   VkMemoryRequirements bmr; vkGetBufferMemoryRequirements(dev,ubo,&bmr);
   VkMemoryAllocateInfo bmai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=bmr.size,
      .memoryTypeIndex=mem_type(bmr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory ubo_mem; CK(vkAllocateMemory(dev,&bmai,NULL,&ubo_mem));
   CK(vkBindBufferMemory(dev,ubo,ubo_mem,0));

   VkDescriptorSetLayoutBinding b={.binding=0,.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount=1,.stageFlags=VK_SHADER_STAGE_FRAGMENT_BIT};
   VkDescriptorSetLayoutCreateInfo dsli={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount=1,.pBindings=&b};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dsli,NULL,&dsl));
   VkDescriptorPoolSize ps={.type=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,.descriptorCount=NVAR};
   VkDescriptorPoolCreateInfo dpi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets=NVAR,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpi,NULL,&dp));
   VkDescriptorSet sets[NVAR]; VkDescriptorSetLayout layouts[NVAR];
   for(int i=0;i<NVAR;i++) layouts[i]=dsl;
   VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool=dp,.descriptorSetCount=NVAR,.pSetLayouts=layouts};
   CK(vkAllocateDescriptorSets(dev,&dsai,sets));
   for(int i=0;i<NVAR;i++){
      VkDescriptorBufferInfo dbi={.buffer=ubo,.offset=(VkDeviceSize)i*256,.range=256};
      VkWriteDescriptorSet w={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=sets[i],
         .dstBinding=0,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
         .pBufferInfo=&dbi};
      vkUpdateDescriptorSets(dev,1,&w,0,NULL);
   }

   VkPushConstantRange pcr={.stageFlags=VK_SHADER_STAGE_VERTEX_BIT,.offset=0,.size=64};
   VkPipelineLayoutCreateInfo pli={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pcr};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&pli,NULL,&pl));

   VkShaderModule vs=mk(vs_spv,vs_spv_len), fs=mk(fs_spv,fs_spv_len);
   VkPipeline pipes[NVAR];
   {
      VkPipelineVertexInputStateCreateInfo vin={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
      VkPipelineInputAssemblyStateCreateInfo iaci={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
      VkViewport vp={0,0,W,H,0,1}; VkRect2D sc={{0,0},{W,H}};
      VkPipelineViewportStateCreateInfo vsc={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
      VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
      VkFormat cf=VK_FORMAT_R8G8B8A8_UNORM;
      VkPipelineRenderingCreateInfo prci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
         .colorAttachmentCount=1,.pColorAttachmentFormats=&cf};
      for(int i=0;i<NVAR;i++){
         /* chaque pipeline differe par un detail d'etat fixe : objets distincts */
         VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .polygonMode=VK_POLYGON_MODE_FILL,
            .cullMode=(i%2)?VK_CULL_MODE_NONE:VK_CULL_MODE_BACK_BIT,
            .frontFace=(i%4<2)?VK_FRONT_FACE_CLOCKWISE:VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .lineWidth=1.f};
         VkPipelineColorBlendAttachmentState cba={.colorWriteMask=(VkColorComponentFlags)(0x1|((i%8)<<1)|0x8)};
         VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .attachmentCount=1,.pAttachments=&cba};
         VkPipelineShaderStageCreateInfo st[2]={
            {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
            {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
         VkGraphicsPipelineCreateInfo gpi={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&prci,
            .stageCount=2,.pStages=st,.pVertexInputState=&vin,.pInputAssemblyState=&iaci,
            .pViewportState=&vsc,.pRasterizationState=&rs,.pMultisampleState=&ms,
            .pColorBlendState=&cb,.layout=pl};
         CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gpi,NULL,&pipes[i]));
      }
   }

   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&cbai,&cb));

   unsigned char pcdata[64]; memset(pcdata,0x5a,sizeof(pcdata));
   double *rec=calloc(niter,sizeof(double));

   for(uint32_t it=0; it<niter; it++){
      CK(vkResetCommandBuffer(cb,0));
      VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
      CK(vkBeginCommandBuffer(cb,&bi));
      VkImageMemoryBarrier imb={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
         .image=color,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1},
         .dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT};
      vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,0,NULL,0,NULL,1,&imb);
      VkRenderingAttachmentInfo rai={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=view,.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE,
         .clearValue={{{0,0,0,1}}}};
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea={{0,0},{W,H}},
         .layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&rai};
      vkCmdBeginRendering(cb,&ri);
      vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[0]);
      vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pl,0,1,&sets[0],0,NULL);

      double t0=now();
      for(uint32_t d=0; d<ndraw; d++){
         uint32_t v = d % NVAR;
         if (m_pipe) vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[v]);
         if (m_pipe1) vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[0]);
         if (m_desc) vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pl,0,1,&sets[v],0,NULL);
         if (m_desc1) vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pl,0,1,&sets[0],0,NULL);
         if (m_push) vkCmdPushConstants(cb,pl,VK_SHADER_STAGE_VERTEX_BIT,0,64,pcdata);
         vkCmdDraw(cb,3,1,0,0);
      }
      rec[it]=now()-t0;

      vkCmdEndRendering(cb);
      CK(vkEndCommandBuffer(cb));
   }

   uint32_t warm=niter/4, k=niter-warm;
   qsort(rec+warm,k,sizeof(double),cmp_d);
   double med=rec[warm+k/2];
   printf("%-6s %-10s tirages=%-5u  %8.3f us/tirage  (%.3f ms pour %u)\n",
          mode,
#if defined(_WIN32)
          "PE/Wine"
#elif defined(__aarch64__)
          "arm64"
#else
          "x86_64"
#endif
          , ndraw, med*1e6/ndraw, med*1e3, ndraw);
   return 0;
}
