/* Banc des lectures memoire des nuanceurs de calcul (contournement KK 6, correctif 0132).
 *   bench_lecture lect <lecture.spv> [fils=1048576] [iters=64] [reps=7]
 *     un grand tampon en lecture seule (readonly), lu iters fois par fil ; temps mur median.
 *   bench_lecture rw <rw.spv> [iters=1000]
 *     un seul fil lit puis ecrit la meme case iters fois (le motif du bogue Metal que le
 *     contournement 6 corrige) : la case doit valoir iters a la fin.
 * Le mode des acces se choisit par l'environnement (CIDRE_LECTURES_CACHEES,
 * MESA_KK_DISABLE_WORKAROUNDS=6). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>
#define CK(x) do{VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__);exit(1);} }while(0)
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static VkDevice dev; static VkPhysicalDevice pd;
static int cmpd(const void*a,const void*b){double x=*(const double*)a,y=*(const double*)b;return x<y?-1:x>y;}
static VkBuffer mkbuf(VkDeviceSize sz, VkDeviceMemory *m, void **map){
   VkBufferCreateInfo bc={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=sz,.usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
   VkBuffer b; CK(vkCreateBuffer(dev,&bc,NULL,&b));
   VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,b,&mr);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
   uint32_t t=0; for(;t<mp.memoryTypeCount;t++) if((mr.memoryTypeBits&(1u<<t))&&(mp.memoryTypes[t].propertyFlags&VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,.memoryTypeIndex=t};
   CK(vkAllocateMemory(dev,&ai,NULL,m)); CK(vkBindBufferMemory(dev,b,*m,0)); CK(vkMapMemory(dev,*m,0,sz,0,map)); return b; }
int main(int argc,char**argv){
   if(argc<3){printf("usage : bench_lecture lect|rw <spv> ...\n");return 2;}
   int rw=!strcmp(argv[1],"rw");
   uint32_t fils=rw?1:(argc>3?atoi(argv[3]):1048576), iters=rw?(argc>3?atoi(argv[3]):1000):(argc>4?atoi(argv[4]):64);
   int reps=rw?1:(argc>5?atoi(argv[5]):7);
   FILE*f=fopen(argv[2],"rb"); if(!f) return 2; fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET);
   uint32_t*code=malloc(n); if(fread(code,1,n,f)!=(size_t)n) return 2; fclose(f);
   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in)); uint32_t c=1; vkEnumeratePhysicalDevices(in,&c,&pd);
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&pr};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};
   CK(vkCreateDevice(pd,&dc,NULL,&dev)); VkQueue q; vkGetDeviceQueue(dev,0,0,&q);
   const uint32_t N=16u<<20; uint32_t mask=N-1;
   VkDeviceMemory m0,m1; uint32_t *in0,*out0;
   VkBuffer b0=mkbuf((VkDeviceSize)N*4,&m0,(void**)&in0), b1=mkbuf((VkDeviceSize)(fils>1?fils:1)*4,&m1,(void**)&out0);
   for(uint32_t i=0;i<N;i++) in0[i]=rw?0:(i*2654435761u);
   VkShaderModuleCreateInfo si={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=n,.pCode=code};
   VkShaderModule sm; CK(vkCreateShaderModule(dev,&si,NULL,&sm));
   VkDescriptorSetLayoutBinding bd[2]={{0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT},{1,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_COMPUTE_BIT}};
   VkDescriptorSetLayoutCreateInfo dl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=2,.pBindings=bd};
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev,&dl,NULL,&dsl));
   VkPushConstantRange pcr={VK_SHADER_STAGE_COMPUTE_BIT,0,8};
   VkPipelineLayoutCreateInfo pl={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&dsl,.pushConstantRangeCount=1,.pPushConstantRanges=&pcr};
   VkPipelineLayout lay; CK(vkCreatePipelineLayout(dev,&pl,NULL,&lay));
   VkComputePipelineCreateInfo cp={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=lay};
   VkPipeline pipe; CK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cp,NULL,&pipe));
   VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,2};
   VkDescriptorPoolCreateInfo dp={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};
   VkDescriptorPool pool; CK(vkCreateDescriptorPool(dev,&dp,NULL,&pool));
   VkDescriptorSetAllocateInfo da={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=pool,.descriptorSetCount=1,.pSetLayouts=&dsl};
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev,&da,&ds));
   VkDescriptorBufferInfo bi[2]={{b0,0,VK_WHOLE_SIZE},{b1,0,VK_WHOLE_SIZE}};
   VkWriteDescriptorSet wd={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.descriptorCount=2,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=bi};
   vkUpdateDescriptorSets(dev,1,&wd,0,NULL);
   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=0};
   VkCommandPool cpool; CK(vkCreateCommandPool(dev,&cpi,NULL,&cpool));
   VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cpool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&ca,&cb));
   double *t=calloc(reps,sizeof(double)); uint32_t pcv[2]={mask,iters};
   for(int r=0;r<reps;r++){
      VkCommandBufferBeginInfo cbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb,&cbi));
      vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe);
      vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,lay,0,1,&ds,0,NULL);
      vkCmdPushConstants(cb,lay,VK_SHADER_STAGE_COMPUTE_BIT,0,8,pcv);
      vkCmdDispatch(cb,rw?1:fils/64,1,1);
      CK(vkEndCommandBuffer(cb));
      VkSubmitInfo sub={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
      double t0=now(); CK(vkQueueSubmit(q,1,&sub,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q)); t[r]=(now()-t0)*1e3;
   }
   const char*a=getenv("CIDRE_LECTURES_CACHEES"), *w=getenv("MESA_KK_DISABLE_WORKAROUNDS");
   const char*mode=(w&&strstr(w,"6"))?"sans_WA6":a?"lectures_cachees":"actuel";
   if(rw){ printf("RW mode=%s iters=%u : case finale = %u (attendu %u) -> %s\n",mode,iters,out0[0],iters,out0[0]==iters?"JUSTE":"FAUX"); return out0[0]==iters?0:3; }
   qsort(t,reps,sizeof(double),cmpd);
   uint32_t chk=0; for(uint32_t i=0;i<fils;i+=4097) chk^=out0[i];
   printf("LECT mode=%s fils=%u iters=%u : mur med=%.2f ms (min %.2f max %.2f) controle=%08x\n",mode,fils,iters,t[reps/2],t[0],t[reps-1],chk);
   return 0; }
