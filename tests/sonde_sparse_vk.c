/* Sonde Vulkan du sparse de KosmicKrisp (drapeau fl12) : image 2D sparse residente
 * cible de rendu et inscriptible (le cas qui faisait planter Metal en stockage partage),
 * une tuile liee par vkQueueBindSparse, effacement, relecture d'un pixel de la tuile
 * liee (couleur attendue) et d'un pixel d'une tuile non liee (0 attendu).
 * usage : MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod,fl12 sonde_sparse_vk */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do{VkResult r=(x); if(r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,r,__LINE__);exit(1);} }while(0)

int main(void){
   VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ii={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};
   VkInstance in; CK(vkCreateInstance(&ii,NULL,&in));
   VkPhysicalDevice pd; uint32_t n=1; vkEnumeratePhysicalDevices(in,&n,&pd);
   VkPhysicalDeviceFeatures f; vkGetPhysicalDeviceFeatures(pd,&f);
   printf("sparseBinding=%u sparseResidencyImage2D=%u\n",f.sparseBinding,f.sparseResidencyImage2D);
   if(!f.sparseBinding||!f.sparseResidencyImage2D){printf("pas de sparse (fl12 absent ?)\n");return 2;}
   VkQueueFamilyProperties qp; uint32_t nq=1; vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,&qp);
   printf("file 0 : sparse=%d\n",!!(qp.queueFlags&VK_QUEUE_SPARSE_BINDING_BIT));
   float pr=1.f; VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&pr};
   VkPhysicalDeviceFeatures en={.sparseBinding=VK_TRUE,.sparseResidencyImage2D=VK_TRUE};
   VkPhysicalDeviceVulkan13Features v13={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,.synchronization2=VK_TRUE};
   VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&v13,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc,.pEnabledFeatures=&en};
   VkDevice dev; CK(vkCreateDevice(pd,&dc,NULL,&dev));
   VkQueue q; vkGetDeviceQueue(dev,0,0,&q);

   VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .flags=VK_IMAGE_CREATE_SPARSE_BINDING_BIT|VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT,
      .imageType=VK_IMAGE_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,.extent={256,256,1},.mipLevels=1,.arrayLayers=1,
      .samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
      .usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_STORAGE_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
   VkImage im; CK(vkCreateImage(dev,&ci,NULL,&im));
   printf("image sparse cible de rendu + stockage : creee\n");
   VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,im,&mr);
   uint32_t ns=0; vkGetImageSparseMemoryRequirements(dev,im,&ns,NULL);
   VkSparseImageMemoryRequirements sr; ns=1; vkGetImageSparseMemoryRequirements(dev,im,&ns,&sr);
   VkExtent3D g=sr.formatProperties.imageGranularity;
   printf("taille=%llu alignement(tuile)=%llu granularite=%ux%u\n",(unsigned long long)mr.size,(unsigned long long)mr.alignment,g.width,g.height);
   uint32_t mt=0; while(!(mr.memoryTypeBits&(1u<<mt))) mt++;
   VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.alignment,.memoryTypeIndex=mt};
   VkDeviceMemory mem; CK(vkAllocateMemory(dev,&ai,NULL,&mem));
   VkSparseImageMemoryBind b={.subresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0},.offset={0,0,0},.extent=g,.memory=mem,.memoryOffset=0};
   VkSparseImageMemoryBindInfo bi={.image=im,.bindCount=1,.pBinds=&b};
   VkBindSparseInfo bsi={.sType=VK_STRUCTURE_TYPE_BIND_SPARSE_INFO,.imageBindCount=1,.pImageBinds=&bi};
   VkFenceCreateInfo fi={.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fe; CK(vkCreateFence(dev,&fi,NULL,&fe));
   CK(vkQueueBindSparse(q,1,&bsi,fe)); CK(vkWaitForFences(dev,1,&fe,VK_TRUE,~0ull));
   printf("tuile (0,0) liee\n");

   VkBufferCreateInfo bc={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=8,.usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT};
   VkBuffer rb; CK(vkCreateBuffer(dev,&bc,NULL,&rb));
   VkMemoryRequirements br; vkGetBufferMemoryRequirements(dev,rb,&br);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
   uint32_t ht=0; for(;ht<mp.memoryTypeCount;ht++) if((br.memoryTypeBits&(1u<<ht))&&(mp.memoryTypes[ht].propertyFlags&VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) break;
   VkMemoryAllocateInfo ba={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=br.size,.memoryTypeIndex=ht};
   VkDeviceMemory bm; CK(vkAllocateMemory(dev,&ba,NULL,&bm)); CK(vkBindBufferMemory(dev,rb,bm,0));
   unsigned char *p; CK(vkMapMemory(dev,bm,0,8,0,(void**)&p)); memset(p,0x11,8);

   VkCommandPoolCreateInfo cpi={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=0};
   VkCommandPool cp; CK(vkCreateCommandPool(dev,&cpi,NULL,&cp));
   VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cp,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev,&ca,&cb));
   VkCommandBufferBeginInfo cbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; CK(vkBeginCommandBuffer(cb,&cbi));
   VkImageMemoryBarrier2 b1={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      .dstStageMask=VK_PIPELINE_STAGE_2_CLEAR_BIT,.dstAccessMask=VK_ACCESS_2_TRANSFER_WRITE_BIT,.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,.image=im,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}};
   VkDependencyInfo d1={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&b1};
   vkCmdPipelineBarrier2(cb,&d1);
   VkClearColorValue cc={.float32={1.0f,0.5f,0.25f,1.0f}}; VkImageSubresourceRange rg={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
   vkCmdClearColorImage(cb,im,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,&cc,1,&rg);
   VkImageMemoryBarrier2 b2={.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,.srcStageMask=VK_PIPELINE_STAGE_2_CLEAR_BIT,
      .srcAccessMask=VK_ACCESS_2_TRANSFER_WRITE_BIT,.dstStageMask=VK_PIPELINE_STAGE_2_COPY_BIT,.dstAccessMask=VK_ACCESS_2_TRANSFER_READ_BIT,
      .oldLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,.newLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,.image=im,.subresourceRange=rg};
   VkDependencyInfo d2={.sType=VK_STRUCTURE_TYPE_DEPENDENCY_INFO,.imageMemoryBarrierCount=1,.pImageMemoryBarriers=&b2};
   vkCmdPipelineBarrier2(cb,&d2);
   VkBufferImageCopy c[2]={
      {.bufferOffset=0,.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageOffset={1,1,0},.imageExtent={1,1,1}},
      {.bufferOffset=4,.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1},.imageOffset={200,200,0},.imageExtent={1,1,1}}};
   vkCmdCopyImageToBuffer(cb,im,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,rb,2,c);
   CK(vkEndCommandBuffer(cb));
   VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};
   CK(vkQueueSubmit(q,1,&si,VK_NULL_HANDLE)); CK(vkQueueWaitIdle(q));
   printf("tuile liee  (1,1)     = %u %u %u %u (attendu 255 128 64 255)\n",p[0],p[1],p[2],p[3]);
   printf("tuile libre (200,200) = %u %u %u %u (attendu 0 0 0 0)\n",p[4],p[5],p[6],p[7]);
   int ok=p[0]==255&&p[3]==255&&p[4]==0&&p[7]==0;
   printf("RESULTAT sparse : %s\n",ok?"OK":"FAUX");
   return ok?0:3;
}
