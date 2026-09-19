/* VK_EXT_device_generated_commands : chaque sequence doit voir SES constantes.
 *
 * Une mise en page a deux jetons, PUSH_CONSTANT puis DISPATCH. Le flux porte N
 * sequences ; la sequence i pousse {slot = i, value = 100 + i} et lance un
 * groupe. Le shader ecrit o.v[slot] = value. Si les constantes par sequence
 * fonctionnent, on relit 100 + i a l'indice i.
 *
 * Volontairement minimal : pas de vkd3d-proton, pas de streamout, rien qui
 * puisse brouiller le diagnostic.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "dgc_shaders.h"
#include "dgc_vs.h"
#include "dgc_m.h"

#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define SEQS 8

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam; static VkCommandPool pool;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags p){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&p)==p) return i;
   printf("pas de type memoire\n"); exit(1); }

struct buf { VkBuffer b; VkDeviceMemory m; void *cpu; VkDeviceAddress va; };

static struct buf mkbuf(VkDeviceSize size, VkBufferUsageFlags usage){
   struct buf o={0};
   VkBufferCreateInfo bi={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=size,
      .usage=usage|VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT};
   CK(vkCreateBuffer(dev,&bi,NULL,&o.b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,o.b,&mr);
   VkMemoryAllocateFlagsInfo fi={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
      .flags=VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT};
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.pNext=&fi,
      .allocationSize=mr.size,.memoryTypeIndex=mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,&o.m));
   CK(vkBindBufferMemory(dev,o.b,o.m,0));
   CK(vkMapMemory(dev,o.m,0,VK_WHOLE_SIZE,0,&o.cpu));
   memset(o.cpu,0,size);
   VkBufferDeviceAddressInfo ai={.sType=VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,.buffer=o.b};
   o.va=vkGetBufferDeviceAddress(dev,&ai);
   return o;
}

int main(int argc, char **argv){
   const uint32_t PCOFF = (argc > 1) ? (uint32_t)atoi(argv[1]) : 0u;
   const int GFX = (argc > 2) && (argv[2][0] == 'g' || argv[2][0] == 'i');
   const int IDX = (argc > 2) && argv[2][0] == 'i';
   const int MULTI = (argc > 2) && argv[2][0] == 'm';
   printf("mode = %s\n", MULTI ? "calcul, 3 jetons 64 bits"
                              : IDX ? "graphique (DRAW_INDEXED)"
                              : GFX ? "graphique (DRAW)" : "calcul (DISPATCH)");
   const VkShaderStageFlags stage = GFX ? VK_SHADER_STAGE_VERTEX_BIT
                                        : VK_SHADER_STAGE_COMPUTE_BIT;
   printf("decalage de destination = %u octets\n", PCOFF);
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));

   VkPhysicalDeviceDeviceGeneratedCommandsFeaturesEXT dgcf={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEVICE_GENERATED_COMMANDS_FEATURES_EXT};
   VkPhysicalDeviceFeatures2 f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&dgcf};
   vkGetPhysicalDeviceFeatures2(pdev,&f2);
   printf("deviceGeneratedCommands = %d\n", dgcf.deviceGeneratedCommands);
   if(!dgcf.deviceGeneratedCommands){ printf("extension absente, test sans objet\n"); return 77; }

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if((qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT)&&(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT)){qfam=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceDeviceGeneratedCommandsFeaturesEXT want_dgc={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEVICE_GENERATED_COMMANDS_FEATURES_EXT,
      .deviceGeneratedCommands=VK_TRUE};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      .pNext=&want_dgc,.dynamicRendering=VK_TRUE};
   VkPhysicalDeviceVulkan12Features v12={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
      .pNext=&v13,.bufferDeviceAddress=VK_TRUE};
   VkPhysicalDeviceFeatures2 want_f2={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
      .pNext=&v12,.features={.vertexPipelineStoresAndAtomics=VK_TRUE}};
   const char *exts[]={VK_EXT_DEVICE_GENERATED_COMMANDS_EXTENSION_NAME};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&want_f2,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,
      .enabledExtensionCount=1,.ppEnabledExtensionNames=exts};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev)); vkGetDeviceQueue(dev,qfam,0,&queue);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=qfam};
   CK(vkCreateCommandPool(dev,&cpi,NULL,&pool));

#define GPA(n) PFN_##n n = (PFN_##n)vkGetDeviceProcAddr(dev, #n); if(!n){printf("point d'entree absent: %s\n", #n); return 1;}
   GPA(vkCreateIndirectCommandsLayoutEXT)
   GPA(vkDestroyIndirectCommandsLayoutEXT)
   GPA(vkGetGeneratedCommandsMemoryRequirementsEXT)
   GPA(vkCmdExecuteGeneratedCommandsEXT)
#undef GPA

   struct buf out=mkbuf(2*SEQS*sizeof(uint32_t),VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

   VkDescriptorSetLayoutBinding dslb={.binding=0,
      .descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1,
      .stageFlags=stage};
   VkDescriptorSetLayoutCreateInfo dsli={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount=1,.pBindings=&dslb};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dsli,NULL,&dsl));

   VkPushConstantRange pcr={.stageFlags=stage,.offset=PCOFF,.size=MULTI?24u:8u};
   VkPipelineLayoutCreateInfo pli={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount=1,.pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pcr};
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev,&pli,NULL,&pl));

   VkShaderModuleCreateInfo smi={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize=MULTI?sizeof(m_spv):GFX?sizeof(vs_spv):sizeof(cs_spv),
      .pCode=(const uint32_t*)(MULTI?(const void*)m_spv
                                    :GFX?(const void*)vs_spv:(const void*)cs_spv)};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&smi,NULL,&sm));
   VkPipeline pipe;
   if(!GFX){
      VkComputePipelineCreateInfo cpci={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
         .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                 .stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},
         .layout=pl};
      CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cpci,NULL,&pipe));
   } else {
      VkPipelineShaderStageCreateInfo st={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage=VK_SHADER_STAGE_VERTEX_BIT,.module=sm,.pName="main"};
      VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
      VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .topology=VK_PRIMITIVE_TOPOLOGY_POINT_LIST};
      VkPipelineViewportStateCreateInfo vp={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .viewportCount=1,.scissorCount=1};
      VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .rasterizerDiscardEnable=VK_TRUE,.lineWidth=1.f};
      VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .rasterizationSamples=VK_SAMPLE_COUNT_1_BIT};
      VkDynamicState dyns[]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
      VkPipelineDynamicStateCreateInfo dy={.sType=VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
         .dynamicStateCount=2,.pDynamicStates=dyns};
      VkPipelineRenderingCreateInfo pr={.sType=VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
      VkGraphicsPipelineCreateInfo gpci={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
         .pNext=&pr,.stageCount=1,.pStages=&st,.pVertexInputState=&vi,
         .pInputAssemblyState=&ia,.pViewportState=&vp,.pRasterizationState=&rs,
         .pMultisampleState=&ms,.pDynamicState=&dy,.layout=pl};
      CK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gpci,NULL,&pipe));
   }

   VkDescriptorPoolSize dps={.type=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1};
   VkDescriptorPoolCreateInfo dpi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets=1,.poolSizeCount=1,.pPoolSizes=&dps};
   VkDescriptorPool dpool; CK(vkCreateDescriptorPool(dev,&dpi,NULL,&dpool));
   VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool=dpool,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&dsai,&ds));
   VkDescriptorBufferInfo dbi={.buffer=out.b,.offset=0,.range=VK_WHOLE_SIZE};
   VkWriteDescriptorSet wds={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,
      .dstBinding=0,.descriptorCount=1,
      .descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&dbi};
   vkUpdateDescriptorSets(dev,1,&wds,0,NULL);

   VkIndirectCommandsPushConstantTokenEXT pct={.updateRange=pcr};
   VkIndirectCommandsPushConstantTokenEXT pcm[3]={
      {.updateRange={stage,PCOFF+0u,8u}},
      {.updateRange={stage,PCOFF+8u,8u}},
      {.updateRange={stage,PCOFF+16u,8u}}};
   VkIndirectCommandsLayoutTokenEXT mtoks[4]={
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=VK_INDIRECT_COMMANDS_TOKEN_TYPE_PUSH_CONSTANT_EXT,
       .data={.pPushConstant=&pcm[0]},.offset=0},
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=VK_INDIRECT_COMMANDS_TOKEN_TYPE_PUSH_CONSTANT_EXT,
       .data={.pPushConstant=&pcm[1]},.offset=8},
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=VK_INDIRECT_COMMANDS_TOKEN_TYPE_PUSH_CONSTANT_EXT,
       .data={.pPushConstant=&pcm[2]},.offset=16},
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=VK_INDIRECT_COMMANDS_TOKEN_TYPE_DISPATCH_EXT,.offset=24},
   };
   VkIndirectCommandsLayoutTokenEXT toks[2]={
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=VK_INDIRECT_COMMANDS_TOKEN_TYPE_PUSH_CONSTANT_EXT,
       .data={.pPushConstant=&pct},.offset=0},
      {.sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_TOKEN_EXT,
       .type=IDX?VK_INDIRECT_COMMANDS_TOKEN_TYPE_DRAW_INDEXED_EXT
                :GFX?VK_INDIRECT_COMMANDS_TOKEN_TYPE_DRAW_EXT
                    :VK_INDIRECT_COMMANDS_TOKEN_TYPE_DISPATCH_EXT,.offset=8},
   };
   const uint32_t stride=MULTI?(24u+3u*4u):(8u+(IDX?5u:GFX?4u:3u)*(uint32_t)sizeof(uint32_t));
   VkIndirectCommandsLayoutCreateInfoEXT lci={
      .sType=VK_STRUCTURE_TYPE_INDIRECT_COMMANDS_LAYOUT_CREATE_INFO_EXT,
      .shaderStages=stage,.indirectStride=stride,
      .pipelineLayout=pl,.tokenCount=MULTI?4u:2u,.pTokens=MULTI?mtoks:toks};
   VkIndirectCommandsLayoutEXT layout;
   VkResult lr=vkCreateIndirectCommandsLayoutEXT(dev,&lci,NULL,&layout);
   if(lr!=VK_SUCCESS){ printf("ECHEC creation de la mise en page -> %d\n",lr); return 1; }

   struct buf stream=mkbuf(SEQS*stride,VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
   for(uint32_t i=0;i<SEQS;i++){
      uint32_t *s=(uint32_t*)((char*)stream.cpu+i*stride);
      s[0]=i; s[1]=100+i;
      if(MULTI){ s[0]=i; s[1]=0; s[2]=100+i; s[3]=0; s[4]=200+i; s[5]=0;
                 s[6]=1; s[7]=1; s[8]=1; }
      else if(IDX) { s[2]=1; s[3]=1; s[4]=0; s[5]=0; s[6]=0; }
      else if(GFX) { s[2]=1; s[3]=1; s[4]=0; s[5]=0; }
      else         { s[2]=1; s[3]=1; s[4]=1; }
   }

   VkGeneratedCommandsMemoryRequirementsInfoEXT gmri={
      .sType=VK_STRUCTURE_TYPE_GENERATED_COMMANDS_MEMORY_REQUIREMENTS_INFO_EXT,
      .indirectCommandsLayout=layout,.maxSequenceCount=SEQS,.maxDrawCount=1};
   VkMemoryRequirements2 gmr={.sType=VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2};
   vkGetGeneratedCommandsMemoryRequirementsEXT(dev,&gmri,&gmr);
   printf("memoire de pre-traitement = %llu octets\n",
          (unsigned long long)gmr.memoryRequirements.size);
   struct buf pre = gmr.memoryRequirements.size
      ? mkbuf(gmr.memoryRequirements.size,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT)
      : (struct buf){0};

   VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&cbai,&cb));
   VkCommandBufferBeginInfo cbbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   CK(vkBeginCommandBuffer(cb,&cbbi));
   VkPipelineBindPoint bp = GFX ? VK_PIPELINE_BIND_POINT_GRAPHICS
                                : VK_PIPELINE_BIND_POINT_COMPUTE;
   vkCmdBindPipeline(cb,bp,pipe);
   vkCmdBindDescriptorSets(cb,bp,pl,0,1,&ds,0,NULL);
   uint32_t poison[6]={0xdeadu,0,0xbeefu,0,0xcafeu,0};
   vkCmdPushConstants(cb,pl,stage,PCOFF,MULTI?24u:8u,poison);
   VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,
      .renderArea={.extent={1,1}},.layerCount=1};
   VkViewport vpt={0,0,1,1,0,1}; VkRect2D sci={{0,0},{1,1}};
   struct buf ib = {0};
   if(IDX){
      ib = mkbuf(4*sizeof(uint32_t), VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
      ((uint32_t*)ib.cpu)[0]=0;
      vkCmdBindIndexBuffer(cb, ib.b, 0, VK_INDEX_TYPE_UINT32);
   }
   if(GFX){ vkCmdBeginRendering(cb,&ri);
            vkCmdSetViewport(cb,0,1,&vpt); vkCmdSetScissor(cb,0,1,&sci); }

   VkGeneratedCommandsInfoEXT gci={
      .sType=VK_STRUCTURE_TYPE_GENERATED_COMMANDS_INFO_EXT,
      .shaderStages=stage,
      .indirectCommandsLayout=layout,
      .indirectAddress=stream.va,.indirectAddressSize=SEQS*stride,
      .preprocessAddress=pre.va,.preprocessSize=gmr.memoryRequirements.size,
      .maxSequenceCount=SEQS,.maxDrawCount=1};
   vkCmdExecuteGeneratedCommandsEXT(cb,VK_FALSE,&gci);
   if(GFX) vkCmdEndRendering(cb);
   CK(vkEndCommandBuffer(cb));

   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
   CK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE));
   CK(vkQueueWaitIdle(queue));

   int fail=0;
   const uint32_t *v=(const uint32_t*)out.cpu;
   for(uint32_t i=0;i<SEQS;i++){
      uint32_t want=100+i;
      if(v[i]!=want){ printf("  sequence %u : attendu %u, obtenu %u\n",i,want,v[i]); fail++; }
      if(MULTI && v[i+SEQS]!=200+i){
         printf("  sequence %u (2e valeur) : attendu %u, obtenu %u\n",i,200+i,v[i+SEQS]); fail++; }
   }
   printf("\n%s (%d echec(s) sur %d sequences)\n", fail?"ECHECS":"TOUT PASSE", fail, SEQS);
   return fail?1:0;
}
