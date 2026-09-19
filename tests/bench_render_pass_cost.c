/* Repro : N couches MSAA 4x, clear + resolve par couche. Mesure le temps GPU. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){ \
   printf("ECHEC %s -> %d (ligne %d)\n",#x,_r,__LINE__); exit(1);} } while(0)
#define W 16
#define H 16
#define FMT VK_FORMAT_R8G8B8A8_SRGB

static VkInstance inst; static VkPhysicalDevice pdev; static VkDevice dev;
static VkQueue queue; static uint32_t qfam;

static uint32_t mem_type(uint32_t bits, VkMemoryPropertyFlags props){
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   for(uint32_t i=0;i<mp.memoryTypeCount;i++)
      if((bits&(1u<<i))&&(mp.memoryTypes[i].propertyFlags&props)==props) return i;
   printf("pas de type memoire\n"); exit(1);
}
static void mk_image(uint32_t layers, VkSampleCountFlagBits samples,
                     VkImageUsageFlags usage, VkImage *img, VkDeviceMemory *mem){
   VkImageCreateInfo ici={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType=VK_IMAGE_TYPE_2D,.format=FMT,.extent={W,H,1},.mipLevels=1,
      .arrayLayers=layers,.samples=samples,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=usage,.sharingMode=VK_SHARING_MODE_EXCLUSIVE,
      .initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
   CK(vkCreateImage(dev,&ici,NULL,img));
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,*img,&mr);
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize=mr.size,.memoryTypeIndex=mem_type(mr.memoryTypeBits,
         VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
   CK(vkAllocateMemory(dev,&mai,NULL,mem));
   CK(vkBindImageMemory(dev,*img,*mem,0));
}
static VkImageView mk_view(VkImage img, uint32_t layer){
   VkImageViewCreateInfo vci={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      .image=img,.viewType=VK_IMAGE_VIEW_TYPE_2D,.format=FMT,
      .subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,layer,1}};
   VkImageView v; CK(vkCreateImageView(dev,&vci,NULL,&v)); return v;
}
static double now_ms(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
   return ts.tv_sec*1000.0 + ts.tv_nsec/1e6; }

int main(int argc, char **argv){
   uint32_t passes = argc>1 ? (uint32_t)atoi(argv[1]) : 64u;
   uint32_t layers = passes > 1024u ? 1024u : passes;  /* Metal: <= 2048 */
   int do_resolve  = argc>2 ? atoi(argv[2]) : 1;
   int samples     = argc>3 ? atoi(argv[3]) : 4;

   VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
   CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qfam=i;break;}
   float prio=1.0f;
   VkDeviceQueueCreateInfo qci={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qfam,.queueCount=1,.pQueuePriorities=&prio};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      .dynamicRendering=VK_TRUE};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&v13,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&qci};
   CK(vkCreateDevice(pdev,&dci,NULL,&dev));
   vkGetDeviceQueue(dev,qfam,0,&queue);

   VkImage msaa,single; VkDeviceMemory mm,sm;
   VkBuffer readback; VkDeviceMemory rbm;
   {
      VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
         .size=W*H*4,.usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT,.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
      CK(vkCreateBuffer(dev,&bci,NULL,&readback));
      VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,readback,&mr);
      VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,
         .memoryTypeIndex=mem_type(mr.memoryTypeBits,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
      CK(vkAllocateMemory(dev,&mai,NULL,&rbm));
      CK(vkBindBufferMemory(dev,readback,rbm,0));
      void *z; CK(vkMapMemory(dev,rbm,0,VK_WHOLE_SIZE,0,&z)); memset(z,0xEE,W*H*4); vkUnmapMemory(dev,rbm);
   }
   mk_image(layers, samples==1 ? VK_SAMPLE_COUNT_1_BIT : VK_SAMPLE_COUNT_4_BIT,
            VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, &msaa,&mm);
   mk_image(layers, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|
                                           VK_IMAGE_USAGE_TRANSFER_SRC_BIT, &single,&sm);

   VkCommandPoolCreateInfo pci={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=qfam};
   VkCommandPool pool; CK(vkCreateCommandPool(dev,&pci,NULL,&pool));
   VkCommandBufferAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool=pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&ai,&cb));
   VkCommandBufferBeginInfo bi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
   double t_rec0=now_ms();
   CK(vkBeginCommandBuffer(cb,&bi));

   VkImageMemoryBarrier b[2]={
     {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,.dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
      .image=msaa,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,layers}},
     {.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,.dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,.newLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
      .image=single,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,layers}}};
   vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,0,NULL,0,NULL,2,b);

   VkImageView *mv=calloc(layers,sizeof(*mv)), *sv=calloc(layers,sizeof(*sv));
   for(uint32_t i=0;i<layers;i++){ mv[i]=mk_view(msaa,i); sv[i]=mk_view(single,i); }

   for(uint32_t p=0;p<passes;p++){
      uint32_t i=p%layers;
      VkRenderingAttachmentInfo att={.sType=VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
         .imageView=mv[i],.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
         .loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE,
         .clearValue.color.float32={(float)(i&0xff)/255.0f,0.0f,0.0f,1.0f}};
      if(do_resolve){
         att.resolveMode=VK_RESOLVE_MODE_AVERAGE_BIT;
         att.resolveImageView=sv[i];
         att.resolveImageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
         att.storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
      }
      VkRenderingInfo ri={.sType=VK_STRUCTURE_TYPE_RENDERING_INFO,
         .renderArea={{0,0},{W,H}},.layerCount=1,.colorAttachmentCount=1,.pColorAttachments=&att};
      vkCmdBeginRendering(cb,&ri);
      vkCmdEndRendering(cb);
   }

   /* Relire la couche 0 : preuve que le travail a reellement eu lieu. */
   if(do_resolve){
      VkImageMemoryBarrier rbb={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .srcAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,.dstAccessMask=VK_ACCESS_TRANSFER_READ_BIT,
         .oldLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
         .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
         .image=single,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
      vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                           VK_PIPELINE_STAGE_TRANSFER_BIT,0,0,NULL,0,NULL,1,&rbb);
      VkBufferImageCopy c={.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageExtent={W,H,1}};
      vkCmdCopyImageToBuffer(cb,single,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,readback,1,&c);
   }
   CK(vkEndCommandBuffer(cb));
   double t_rec=now_ms()-t_rec0;

   VkFenceCreateInfo fci={.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
   VkFence fence; CK(vkCreateFence(dev,&fci,NULL,&fence));
   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
   double t0=now_ms();
   VkResult sr=vkQueueSubmit(queue,1,&si,fence);
   VkResult wr=vkWaitForFences(dev,1,&fence,VK_TRUE,30ull*1000*1000*1000);
   double dt=now_ms()-t0;
   /* La fence peut signaler alors que la soumission a echoue : verifier que le
    * device est toujours vivant. */
   VkResult idle=vkDeviceWaitIdle(dev);
   int content_ok=1;
   if(do_resolve){
      unsigned char *px; CK(vkMapMemory(dev,rbm,0,VK_WHOLE_SIZE,0,(void**)&px));
      content_ok = !(px[0]==0xEE && px[1]==0xEE && px[2]==0xEE && px[3]==0xEE);
      fprintf(stderr,"[relecture] %02x %02x %02x %02x\n",px[0],px[1],px[2],px[3]);
      vkUnmapMemory(dev,rbm);
   }

   printf("%6u passes, %dx MSAA, resolve=%d : enregistrement %7.1f ms | execution %7.1f ms"
          " | %5.1f us/passe  %s\n",
          passes, samples, do_resolve, t_rec, dt, (t_rec+dt)*1000.0/passes,
          !content_ok ? "TRAVAIL NON EXECUTE" :
          (sr==VK_SUCCESS && wr==VK_SUCCESS && idle==VK_SUCCESS) ? "OK" : "ECHEC");
   return (content_ok && sr==VK_SUCCESS && wr==VK_SUCCESS && idle==VK_SUCCESS) ? 0 : 1;
}
