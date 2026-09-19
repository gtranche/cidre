/* Test cible de VK_EXT_transform_feedback sur KosmicKrisp. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vulkan/vulkan.h>
#include "shaders.h"

#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){ \
   printf("ECHEC %s -> %d (ligne %d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 64
#define H 64
#define NVERT 3
#define STRIDE 16

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;
static VkPipelineLayout layout; static VkPipeline pipe;
static VkBuffer xfb_buf, counter_buf;
static VkDeviceMemory xfb_mem, counter_mem;
static PFN_vkCmdBindTransformFeedbackBuffersEXT pBind;
static PFN_vkCmdBeginTransformFeedbackEXT pBegin;
static PFN_vkCmdEndTransformFeedbackEXT pEnd;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags props) {
   VkPhysicalDeviceMemoryProperties mp;
   vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++)
      if((bits&(1u<<i)) && (mp.memoryTypes[i].propertyFlags&props)==props) return i;
   printf("pas de type memoire\n"); exit(1);
}
static void mk_buffer(VkDeviceSize size, VkBufferUsageFlags usage,
                      VkBuffer *buf, VkDeviceMemory *mem) {
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size=size,.usage=usage,.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
   CK(vkCreateBuffer(dev,&bci,NULL,buf));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,*buf,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize=mr.size,
      .memoryTypeIndex=mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,mem));
   CK(vkBindBufferMemory(dev,*buf,*mem,0));
}
static VkShaderModule mk_shader(const unsigned char *c, unsigned n){
   VkShaderModuleCreateInfo ci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=n,.pCode=(const uint32_t*)c};
   VkShaderModule m; CK(vkCreateShaderModule(dev,&ci,NULL,&m)); return m;
}

int main(int argc, char **argv){
   int mode = argc>1 ? atoi(argv[1]) : 0;  /* 0=normal 1=sans capture 2=buffer trop petit 3=pause/reprise 4=draw indexe 5=draw indirect 6=draw depuis le compteur 7=idem avec counterOffset */
   /* L'ordre des indices, pas leur valeur, doit determiner l'ordre de capture. */
   static const uint16_t idx[NVERT] = {2, 0, 1};
   /* En mode 3 on capture deux fois de suite dans le meme buffer. */
   const int NSLOT = (mode==3||mode==6||mode==7) ? (2*NVERT) : NVERT;
   VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));

   VkPhysicalDeviceTransformFeedbackFeaturesEXT tf={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_FEATURES_EXT};
   VkPhysicalDeviceVulkan13Features v13={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.pNext=&tf};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&v13};
   vkGetPhysicalDeviceFeatures2(pdev,&f2);
   VkPhysicalDeviceTransformFeedbackPropertiesEXT tp={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_PROPERTIES_EXT};
   VkPhysicalDeviceProperties2 p2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,.pNext=&tp};
   vkGetPhysicalDeviceProperties2(pdev,&p2);
   printf("transformFeedback=%d geometryStreams=%d maxBuffers=%u maxStreams=%u queries=%d\n\n",
          tf.transformFeedback,tf.geometryStreams,tp.maxTransformFeedbackBuffers,
          tp.maxTransformFeedbackStreams,tp.transformFeedbackQueries);
   if(!tf.transformFeedback){printf("feature absente\n");return 2;}

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}
   float prio=1.0f;
   VkDeviceQueueCreateInfo qci={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   const char *exts[]={VK_EXT_TRANSFORM_FEEDBACK_EXTENSION_NAME};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&f2,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&qci,
      .enabledExtensionCount=1,.ppEnabledExtensionNames=exts};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev));
   vkGetDeviceQueue(dev,qfam,0,&queue);

   PFN_vkCmdDrawIndirectByteCountEXT pDrawBC=
      (void*)vkGetDeviceProcAddr(dev,"vkCmdDrawIndirectByteCountEXT");
   printf("transformFeedbackDraw=%d point d'entree=%p\n",
          tp.transformFeedbackDraw,(void*)pDrawBC);
   if((mode==6||mode==7) && (!tp.transformFeedbackDraw || !pDrawBC)){
      printf("transformFeedbackDraw absent, test sans objet\n"); return 77; }
   pBind=(void*)vkGetDeviceProcAddr(dev,"vkCmdBindTransformFeedbackBuffersEXT");
   pBegin=(void*)vkGetDeviceProcAddr(dev,"vkCmdBeginTransformFeedbackEXT");
   pEnd=(void*)vkGetDeviceProcAddr(dev,"vkCmdEndTransformFeedbackEXT");
   printf("points d'entree : bind=%p begin=%p end=%p\n",(void*)pBind,(void*)pBegin,(void*)pEnd);
   if(!pBind||!pBegin||!pEnd){printf("ECHEC: points d'entree manquants\n");return 1;}

   VkCommandPoolCreateInfo pci={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&pci,NULL,&pool));
   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   CK(vkCreatePipelineLayout(dev,&plci,NULL,&layout));

   VkDeviceSize xfb_size = (mode==2) ? (2*STRIDE) : (NSLOT*STRIDE);
   mk_buffer(NSLOT*STRIDE, VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_BUFFER_BIT_EXT,
             &xfb_buf,&xfb_mem);
   mk_buffer(sizeof(uint32_t),
             VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_COUNTER_BUFFER_BIT_EXT|
             VK_BUFFER_USAGE_TRANSFER_DST_BIT, &counter_buf,&counter_mem);
   VkBuffer indirect_buf; VkDeviceMemory indirect_mem;
   mk_buffer(sizeof(VkDrawIndirectCommand), VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT,
             &indirect_buf,&indirect_mem);
   { VkDrawIndirectCommand *ic;
     CK(vkMapMemory(dev,indirect_mem,0,VK_WHOLE_SIZE,0,(void**)&ic));
     *ic=(VkDrawIndirectCommand){.vertexCount=NVERT,.instanceCount=1};
     vkUnmapMemory(dev,indirect_mem); }
   VkBuffer index_buf; VkDeviceMemory index_mem;
   mk_buffer(sizeof(idx), VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
             &index_buf,&index_mem);
   { void *im; CK(vkMapMemory(dev,index_mem,0,VK_WHOLE_SIZE,0,&im));
     memcpy(im,idx,sizeof(idx)); vkUnmapMemory(dev,index_mem); }
   /* Pre-remplir pour distinguer "non ecrit" de "ecrit a zero". */
   void *m; CK(vkMapMemory(dev,xfb_mem,0,VK_WHOLE_SIZE,0,&m));
   memset(m,0xAB,NSLOT*STRIDE); vkUnmapMemory(dev,xfb_mem);
   CK(vkMapMemory(dev,counter_mem,0,VK_WHOLE_SIZE,0,&m));
   *(uint32_t*)m=0xDEADBEEF; vkUnmapMemory(dev,counter_mem);

   VkShaderModule vs=mk_shader(vs_spv,vs_spv_len), fs=mk_shader(fs_spv,fs_spv_len);
   VkPipelineShaderStageCreateInfo st[2]={
     {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      .stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
     {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      .stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
   VkViewport vp={0,0,W,H,0,1}; VkRect2D sc={{0,0},{W,H}};
   VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,
      .frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE,.lineWidth=1.0f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineDepthStencilStateCreateInfo ds={.sType=VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount=1,.pAttachments=&cba};
   VkFormat cfmt=VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo rend={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      .colorAttachmentCount=1,.pColorAttachmentFormats=&cfmt};
   VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .pNext=&rend,.stageCount=2,.pStages=st,.pVertexInputState=&vi,.pInputAssemblyState=&ia,
      .pViewportState=&vps,.pRasterizationState=&rs,.pMultisampleState=&ms,
      .pDepthStencilState=&ds,.pColorBlendState=&cb,.layout=layout};
   CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipe));

   VkCommandBufferAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cbuf; CK(vkAllocateCommandBuffers(dev,&ai,&cbuf));

   VkQueryPool qpool=VK_NULL_HANDLE;
   PFN_vkCmdBeginQueryIndexedEXT pBeginQ=(void*)vkGetDeviceProcAddr(dev,"vkCmdBeginQueryIndexedEXT");
   PFN_vkCmdEndQueryIndexedEXT pEndQ=(void*)vkGetDeviceProcAddr(dev,"vkCmdEndQueryIndexedEXT");
   if(tp.transformFeedbackQueries && pBeginQ && pEndQ){
      VkQueryPoolCreateInfo qi={.sType=VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
         .queryType=VK_QUERY_TYPE_TRANSFORM_FEEDBACK_STREAM_EXT,.queryCount=1};
      CK(vkCreateQueryPool(dev,&qi,NULL,&qpool));
   }
   VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cbuf,&bi));

   VkDeviceSize off=0, sz=xfb_size;
   pBind(cbuf,0,1,&xfb_buf,&off,&sz);

   VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,
      .renderArea={{0,0},{W,H}},.layerCount=1,.colorAttachmentCount=0};
   vkCmdBeginRendering(cbuf,&ri);
   vkCmdBindPipeline(cbuf,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
   if(qpool) vkCmdResetQueryPool(cbuf,qpool,0,1);
   if(qpool) pBeginQ(cbuf,qpool,0,0,0);
   VkDeviceSize coff=0;
   if(mode!=1) pBegin(cbuf,0,0,NULL,NULL);
   if(mode==4){
      vkCmdBindIndexBuffer(cbuf,index_buf,0,VK_INDEX_TYPE_UINT16);
      vkCmdDrawIndexed(cbuf,NVERT,1,0,0,0);
   } else if(mode==5){
      vkCmdDrawIndirect(cbuf,indirect_buf,0,1,sizeof(VkDrawIndirectCommand));
   } else {
      vkCmdDraw(cbuf,NVERT,1,0,0);
   }
   if(mode!=1) pEnd(cbuf,0,1,&counter_buf,&coff);
   if(mode==6||mode==7){
      /* Le nombre de sommets du second dessin vient du compteur ecrit par le
       * premier : (48 - counterOffset) / 16. Le CPU ne le connait pas.
       * Au mode 7 le decalage laisse 2 sommets, donc zero triangle complet :
       * rien ne doit etre capture. */
      uint32_t coffset = (mode==7) ? STRIDE : 0u;
      pBegin(cbuf,0,1,&counter_buf,&coff);
      pDrawBC(cbuf,1,0,counter_buf,0,coffset,STRIDE);
      pEnd(cbuf,0,1,&counter_buf,&coff);
   }
   if(mode==3){
      /* La reprise ne peut lire son point de depart que dans le buffer de
       * compteur, ecrit par le GPU : rien de tout cela n'est connu du CPU. */
      pBegin(cbuf,0,1,&counter_buf,&coff);
      vkCmdDraw(cbuf,NVERT,1,0,0);
      pEnd(cbuf,0,1,&counter_buf,&coff);
   }
   if(qpool) pEndQ(cbuf,qpool,0,0);
   vkCmdEndRendering(cbuf);
   CK(vkEndCommandBuffer(cbuf));

   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cbuf};
   CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
   CK(vkQueueWaitIdle(queue));

   float *cap; CK(vkMapMemory(dev,xfb_mem,0,VK_WHOLE_SIZE,0,(void**)&cap));
   int fail=0;
   /* Une primitive qui ne tient pas entiere n'est pas capturee du tout. */
   int captured = (mode==1 || mode==2) ? 0 : ((mode==7) ? NVERT : NSLOT);
   const char *titles[]={"capture normale","hors Begin/End : rien ne doit etre ecrit",
                         "buffer trop petit : la primitive entiere est rejetee",
                         "pause puis reprise depuis le buffer de compteur",
                         "draw indexe : l'ordre de capture suit les indices",
                         "draw indirect : le nombre de sommets vient du GPU",
                         "vkCmdDrawIndirectByteCountEXT : sommets deduits du compteur",
                         "vkCmdDrawIndirectByteCountEXT : counterOffset pris en compte"};
   printf("\n%s\n",titles[mode]);
   unsigned char *raw=(unsigned char*)cap;
   for(int i=0;i<NSLOT;i++){
      float *v=&cap[i*4];
      int ok;
      if(i<captured){
         int k = (mode==4) ? idx[i%NVERT] : (i%NVERT);
         float e[4]={(float)k,(float)k*2.0f,3.0f,4.0f};
         ok=1; for(int j=0;j<4;j++) if(fabsf(v[j]-e[j])>0.001f) ok=0;
         printf("  vertex %d : %.1f %.1f %.1f %.1f   %s\n",i,v[0],v[1],v[2],v[3],ok?"OK":"ECHEC");
      } else {
         ok=1; for(int j=0;j<STRIDE;j++) if(raw[i*STRIDE+j]!=0xAB) ok=0;
         printf("  vertex %d : intact (0xAB)          %s\n",i,ok?"OK":"ECHEC ECRIT");
      }
      if(!ok) fail++;
   }
   vkUnmapMemory(dev,xfb_mem);

   if(mode==0||mode==3||mode==6||mode==7){
      uint32_t *cnt; CK(vkMapMemory(dev,counter_mem,0,VK_WHOLE_SIZE,0,(void**)&cnt));
      uint32_t expected=captured*STRIDE;
      printf("  compteur : %u octets (attendu %u)  %s\n",*cnt,expected,
             *cnt==expected?"OK":"ECHEC");
      if(*cnt!=expected) fail++;
      vkUnmapMemory(dev,counter_mem);
   }

   if(qpool){
      uint64_t res[2]={0,0};
      VkResult qr=vkGetQueryPoolResults(dev,qpool,0,1,sizeof(res),res,sizeof(uint64_t),
         VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WAIT_BIT);
      uint64_t exp_gen=(mode==3||mode==6)?2:1;
      uint64_t exp_wr=(mode==1||mode==2)?0:((mode==3||mode==6)?2:1);
      if(mode==7){ exp_gen=1; exp_wr=1; }
      int ok=(qr==VK_SUCCESS && res[0]==exp_wr && res[1]==exp_gen);
      printf("  requete TF : ecrites=%llu generees=%llu (attendu %llu/%llu) %s\n",
             (unsigned long long)res[0],(unsigned long long)res[1],
             (unsigned long long)exp_wr,(unsigned long long)exp_gen, ok?"OK":"ECHEC");
      if(!ok) fail++;
   }
   printf("\n%s (%d echec(s))\n",fail?"ECHECS":"TOUT PASSE",fail);
   return fail?1:0;
}
