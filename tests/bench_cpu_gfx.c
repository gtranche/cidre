/* Mesure le cout CPU du pilote sur le chemin graphique, par profil de commandes.
 * Le banc bench_cpu_overhead ne couvrait que vkCmdDispatch, la commande la moins chere.
 * Ici on separe les chemins qu'un jeu emprunte vraiment : liaison de pipeline, jeu de
 * descripteurs, constantes pousses, etat dynamique. Le meme source est compile en arm64 et
 * en x86_64 pour chiffrer la taxe Rosetta sur chacun.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
#include "gfx_shaders.h"

#define CK(x) do{ VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} }while(0)
#define DRAWS  20000
#define ROUNDS 15
#define W 256
#define H 256

static VkInstance inst; static VkPhysicalDevice pd; static VkDevice dev;
static VkQueue queue; static uint32_t qfam;

static int cmpd(const void*a,const void*b){ double x=*(const double*)a,y=*(const double*)b; return x<y?-1:(x>y?1:0); }
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return t.tv_sec+t.tv_nsec*1e-9; }
static uint32_t mtype(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }
static VkShaderModule mod(const uint32_t*code, size_t n){
   VkShaderModuleCreateInfo ci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=n,.pCode=code};
   VkShaderModule m; CK(vkCreateShaderModule(dev,&ci,NULL,&m)); return m; }

enum { P_DRAW, P_PUSH, P_DESC, P_PIPE, P_DYN, P_N };
static const char *noms[P_N] = {
   "tirage seul            ",
   "+ constantes poussees  ",
   "+ jeu de descripteurs  ",
   "+ liaison de pipeline  ",
   "+ etat dynamique       ",
};

int main(void)
{
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pd));
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd,&props);

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pd,&qn,NULL);
   VkQueueFamilyProperties qp[16]; if(qn>16)qn=16; vkGetPhysicalDeviceQueueFamilyProperties(pd,&qn,qp);
   qfam=0; for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}

   float prio=1.0f;
   VkDeviceQueueCreateInfo qci={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.dynamicRendering=VK_TRUE};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&v13,.queueCreateInfoCount=1,.pQueueCreateInfos=&qci};
   CK(vkCreateDevice(pd,&dci,NULL,&dev));
   vkGetDeviceQueue(dev,qfam,0,&queue);

   /* cible de rendu */
   VkImageCreateInfo ii={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,
      .format=VK_FORMAT_R8G8B8A8_UNORM,.extent={W,H,1},.mipLevels=1,.arrayLayers=1,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
   VkImage im; CK(vkCreateImage(dev,&ii,NULL,&im));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,im,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
      .memoryTypeIndex=mtype(mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   VkDeviceMemory me; CK(vkAllocateMemory(dev,&mai,NULL,&me)); CK(vkBindImageMemory(dev,im,me,0));
   VkImageViewCreateInfo vci={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=im,
      .viewType=VK_IMAGE_VIEW_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   VkImageView vi; CK(vkCreateImageView(dev,&vci,NULL,&vi));

   /* tampon uniforme + deux jeux de descripteurs pour alterner */
   VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=256,
      .usage=VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT};
   VkBuffer buf; CK(vkCreateBuffer(dev,&bci,NULL,&buf));
   VkMemoryRequirements bmr; vkGetBufferMemoryRequirements(dev,buf,&bmr);
   VkMemoryAllocateInfo bmai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=bmr.size,
      .memoryTypeIndex=mtype(bmr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   VkDeviceMemory bme; CK(vkAllocateMemory(dev,&bmai,NULL,&bme)); CK(vkBindBufferMemory(dev,buf,bme,0));

   VkDescriptorSetLayoutBinding dslb={.binding=0,.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount=1,.stageFlags=VK_SHADER_STAGE_FRAGMENT_BIT};
   VkDescriptorSetLayoutCreateInfo dslci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&dslb};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dslci,NULL,&dsl));
   VkDescriptorPoolSize dps={.type=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,.descriptorCount=2};
   VkDescriptorPoolCreateInfo dpci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=2,.poolSizeCount=1,.pPoolSizes=&dps};
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev,&dpci,NULL,&dp));
   VkDescriptorSetLayout dsls[2]={dsl,dsl};
   VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=dp,.descriptorSetCount=2,.pSetLayouts=dsls};
   VkDescriptorSet ds[2]; CK(vkAllocateDescriptorSets(dev,&dsai,ds));
   VkDescriptorBufferInfo dbi={.buffer=buf,.offset=0,.range=VK_WHOLE_SIZE};
   VkWriteDescriptorSet w[2];
   for(int i=0;i<2;i++){ w[i]=(VkWriteDescriptorSet){.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet=ds[i],.dstBinding=0,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,.pBufferInfo=&dbi}; }
   vkUpdateDescriptorSets(dev,2,w,0,NULL);

   VkPushConstantRange pcr={.stageFlags=VK_SHADER_STAGE_VERTEX_BIT,.offset=0,.size=16};
   VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pcr};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&plci,NULL,&pl));

   VkShaderModule vs=mod((const uint32_t*)vs_spv,sizeof(vs_spv));
   VkShaderModule fs=mod((const uint32_t*)fs_spv,sizeof(fs_spv));
   VkPipelineShaderStageCreateInfo st[2]={
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vs,.pName="main"},
      {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fs,.pName="main"}};
   VkPipelineVertexInputStateCreateInfo vin={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
   VkPipelineInputAssemblyStateCreateInfo iasm={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
   VkViewport vp={0,0,W,H,0,1}; VkRect2D sc={{0,0},{W,H}};
   VkPipelineViewportStateCreateInfo vps={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,.viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
   VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,.polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.lineWidth=1.0f};
   VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
   VkPipelineColorBlendAttachmentState cba={.colorWriteMask=0xf};
   VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,.attachmentCount=1,.pAttachments=&cba};
   VkDynamicState dyn[2]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
   VkPipelineDynamicStateCreateInfo dsci={.sType=VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,.dynamicStateCount=2,.pDynamicStates=dyn};
   VkFormat cf=VK_FORMAT_R8G8B8A8_UNORM;
   VkPipelineRenderingCreateInfo prci={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,.colorAttachmentCount=1,.pColorAttachmentFormats=&cf};
   VkGraphicsPipelineCreateInfo gp={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.pNext=&prci,
      .stageCount=2,.pStages=st,.pVertexInputState=&vin,.pInputAssemblyState=&iasm,.pViewportState=&vps,
      .pRasterizationState=&rs,.pMultisampleState=&ms,.pColorBlendState=&cb,.pDynamicState=&dsci,.layout=pl};
   VkPipeline pipe[2];
   CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipe[0]));
   CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,NULL,&pipe[1]));

   VkCommandPoolCreateInfo cpci={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=qfam};
   VkCommandPool pool; CK(vkCreateCommandPool(dev,&cpci,NULL,&pool));
   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev,&cbai,&cmd));
   VkCommandBufferBeginInfo cbbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};

   printf("%s  --  %d tirages par tour, %d tours\n\n", props.deviceName, DRAWS, ROUNDS);

   float pc[4]={0,0,0,0};
   for(int prof=0; prof<P_N; prof++){
      double rec[ROUNDS];
      for(int r=0;r<ROUNDS;r++){
         CK(vkResetCommandPool(dev,pool,0));
         double t0=now();
         CK(vkBeginCommandBuffer(cmd,&cbbi));
         VkRenderingAttachmentInfo ra={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,.imageView=vi,
            .imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp=VK_ATTACHMENT_STORE_OP_STORE};
         VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,.renderArea=sc,.layerCount=1,
            .colorAttachmentCount=1,.pColorAttachments=&ra};
         vkCmdBeginRendering(cmd,&ri);
         vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe[0]);
         vkCmdBindDescriptorSets(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pl,0,1,&ds[0],0,NULL);
         vkCmdSetViewport(cmd,0,1,&vp); vkCmdSetScissor(cmd,0,1,&sc);
         for(int i=0;i<DRAWS;i++){
            switch(prof){
            case P_PUSH: pc[0]=(float)i; vkCmdPushConstants(cmd,pl,VK_SHADER_STAGE_VERTEX_BIT,0,16,pc); break;
            case P_DESC: vkCmdBindDescriptorSets(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pl,0,1,&ds[i&1],0,NULL); break;
            case P_PIPE: vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe[i&1]); break;
            case P_DYN:  vkCmdSetViewport(cmd,0,1,&vp); vkCmdSetScissor(cmd,0,1,&sc); break;
            default: break;
            }
            vkCmdDraw(cmd,3,1,0,0);
         }
         vkCmdEndRendering(cmd);
         CK(vkEndCommandBuffer(cmd));
         double t1=now();
         VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cmd};
         CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
         CK(vkQueueWaitIdle(queue));
         rec[r]=t1-t0;
      }
      qsort(rec,ROUNDS,sizeof(double),cmpd);
      printf("%s  %8.3f ms   %7.1f ns/tirage\n", noms[prof], rec[ROUNDS/2]*1e3, rec[ROUNDS/2]*1e9/DRAWS);
   }
   return 0;
}
