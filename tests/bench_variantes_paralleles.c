/* Banc : T fils enregistrent en parallele des dessins qui exigent chacun une variante de
 * pipeline Metal neuve (compilee au premier dessin par KosmicKrisp), comme les Job.Worker
 * d'Unity en D3D12. Mesure le temps mur de l'enregistrement (tous fils) : avec le verrou
 * global tenu pendant la compilation, les fils se serialisent.
 * Chaque execution tire une constante de specialisation au hasard : pipelines neufs, pas de
 * cache systeme de Metal d'un lancement a l'autre.
 * usage : bench_variantes_paralleles <dossier spv> [fils=8] [pipelines=128] */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#define CK(x) do{VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__);exit(1);} }while(0)
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static VkDevice dev; static VkPhysicalDevice pd; static VkQueue queue;
static VkImageView rtv; static VkPipeline *pipes; static uint32_t npipes, nfils;
static VkShaderModule mod(const char *p){
   FILE*f=fopen(p,"rb"); if(!f){printf("pas de %s\n",p);exit(1);}
   fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET);
   uint32_t*c=malloc(n); if(fread(c,1,n,f)!=(size_t)n){printf("lecture\n");exit(1);} fclose(f);
   VkShaderModuleCreateInfo i={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=n,.pCode=c};
   VkShaderModule s; CK(vkCreateShaderModule(dev,&i,NULL,&s)); free(c); return s; }
static uint32_t mtype(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties m; vkGetPhysicalDeviceMemoryProperties(pd,&m);
   for(uint32_t i=0;i<m.memoryTypeCount;++i) if((bits&(1u<<i))&&(m.memoryTypes[i].propertyFlags&p)==p) return i;
   return 0; }
struct fil { uint32_t id; VkCommandPool cp; VkCommandBuffer cb; double t; };
static void *enregistre(void *a){
   struct fil *f=a;
   VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   double t0=now();
   CK(vkBeginCommandBuffer(f->cb,&bi));
   VkRenderingAttachmentInfo at={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=rtv,
      .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.loadOp=VK_ATTACHMENT_LOAD_OP_LOAD,.storeOp=VK_ATTACHMENT_STORE_OP_STORE};
   VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea={{0,0},{64,64}},.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&at};
   vkCmdBeginRendering(f->cb,&ri);
   for(uint32_t k=f->id;k<npipes;k+=nfils){
      vkCmdBindPipeline(f->cb,VK_PIPELINE_BIND_POINT_GRAPHICS,pipes[k]);
      vkCmdDraw(f->cb,3,1,0,0);
   }
   vkCmdEndRendering(f->cb);
   CK(vkEndCommandBuffer(f->cb));
   f->t=now()-t0;
   return NULL; }
int main(int argc,char**argv){
   const char*dir=argc>1?argv[1]:".";
   nfils=argc>2?atoi(argv[2]):8; npipes=argc>3?atoi(argv[3]):128;
   srand((unsigned)time(NULL)^(unsigned)getpid());
   float seed=(float)(rand()%100000)*0.001f;
   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in));
   uint32_t n=1; vkEnumeratePhysicalDevices(in,&n,&pd);
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&pr};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.dynamicRendering=VK_TRUE,.synchronization2=VK_TRUE};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&v13};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&f2,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};
   CK(vkCreateDevice(pd,&dc,NULL,&dev)); vkGetDeviceQueue(dev,0,0,&queue);
   VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,
      .extent={64,64,1},.mipLevels=1,.arrayLayers=1,.samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
   VkImage im; CK(vkCreateImage(dev,&ci,NULL,&im));
   VkMemoryRequirements rq; vkGetImageMemoryRequirements(dev,im,&rq);
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=rq.size,.memoryTypeIndex=mtype(rq.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   VkDeviceMemory me; CK(vkAllocateMemory(dev,&ai,NULL,&me)); CK(vkBindImageMemory(dev,im,me,0));
   VkImageViewCreateInfo vc={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=im,.viewType=VK_IMAGE_VIEW_TYPE_2D,
      .format=VK_FORMAT_R8G8B8A8_UNORM,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   CK(vkCreateImageView(dev,&vc,NULL,&rtv));
   VkPipelineLayoutCreateInfo pl={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev,&pl,NULL,&lay));
   char p[512]; snprintf(p,sizeof p,"%s/v.vert.spv",dir); VkShaderModule vs=mod(p);
   VkFormat fmt=VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo rci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,.colorAttachmentCount=1,.pColorAttachmentFormats=&fmt};
   VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
   VkViewport vp={0,0,64,64,0,1}; VkRect2D sc={{0,0},{64,64}};
   VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,.viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,.polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.lineWidth=1.f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,.attachmentCount=1,.pAttachments=&cba};
   VkSpecializationMapEntry se={0,0,4}; VkSpecializationInfo si={1,&se,4,&seed};
   pipes=calloc(npipes,sizeof(VkPipeline));
   double tc=now();
   for(uint32_t k=0;k<npipes;k++){
      snprintf(p,sizeof p,"%s/f%u.frag.spv",dir,k%128);
      float s2=seed+(float)k; si.pData=&s2;
      VkPipelineShaderStageCreateInfo st[2]={
         {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
         {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=mod(p),.pName="main",.pSpecializationInfo=&si}};
      VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&rci,.stageCount=2,.pStages=st,
         .pVertexInputState=&vi,.pInputAssemblyState=&ia,.pViewportState=&vps,.pRasterizationState=&rs,.pMultisampleState=&ms,.pColorBlendState=&cb,.layout=lay};
      CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipes[k]));
   }
   tc=now()-tc;
   struct fil *fl=calloc(nfils,sizeof *fl); pthread_t *th=calloc(nfils,sizeof *th);
   for(uint32_t i=0;i<nfils;i++){
      fl[i].id=i;
      VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=0};
      CK(vkCreateCommandPool(dev,&cpi,NULL,&fl[i].cp));
      VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=fl[i].cp,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
      CK(vkAllocateCommandBuffers(dev,&ca,&fl[i].cb));
   }
   double t0=now();
   for(uint32_t i=0;i<nfils;i++) pthread_create(&th[i],NULL,enregistre,&fl[i]);
   for(uint32_t i=0;i<nfils;i++) pthread_join(th[i],NULL);
   double mur=now()-t0, max1=0;
   for(uint32_t i=0;i<nfils;i++) if(fl[i].t>max1) max1=fl[i].t;
   const char*m=getenv("CIDRE_COMPILE_HORS_VERROU");
   printf("VARIANTES mode=%s fils=%u pipelines=%u : creation %.0f ms ; enregistrement mur %.0f ms (fil le plus lent %.0f ms)\n",
          m?"hors_verrou":"verrou",nfils,npipes,tc*1e3,mur*1e3,max1*1e3);
   return 0; }
