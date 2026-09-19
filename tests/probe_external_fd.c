/* VK_KHR_external_memory_fd : exporter une allocation en descripteur, la
 * reimporter, et verifier que les deux vues designent la meme memoire.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){printf("ECHEC %s -> %d (l.%d)\n",#x,_r,__LINE__); exit(1);} } while(0)

int main(void)
{
   VkApplicationInfo ai={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   VkInstance inst; CK(vkCreateInstance(&ici,NULL,&inst));
   uint32_t n=1; VkPhysicalDevice pdev; CK(vkEnumeratePhysicalDevices(inst,&n,&pdev));
   VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(pdev,&pp);
   printf("peripherique : %s\n", pp.deviceName);

   uint32_t ec=0; vkEnumerateDeviceExtensionProperties(pdev,NULL,&ec,NULL);
   VkExtensionProperties *ex=calloc(ec,sizeof(*ex));
   vkEnumerateDeviceExtensionProperties(pdev,NULL,&ec,ex);
   int a=0; for(uint32_t i=0;i<ec;i++) if(!strcmp(ex[i].extensionName,"VK_KHR_external_memory_fd")) a=1;
   printf("VK_KHR_external_memory_fd annonce : %s\n", a?"oui":"non");
   if(!a) return 1;

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   uint32_t qf=0; for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qf=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qf,.queueCount=1,.pQueuePriorities=&prio};
   const char *devext[]={"VK_KHR_external_memory","VK_KHR_external_memory_fd"};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,
      .enabledExtensionCount=2,.ppEnabledExtensionNames=devext};
   VkDevice dev; CK(vkCreateDevice(pdev,&dci,NULL,&dev));

   /* proprietes annoncees pour un tampon */
   VkPhysicalDeviceExternalBufferInfo ebi={
      .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_BUFFER_INFO,
      .usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
      .handleType=VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT};
   VkExternalBufferProperties ebp={.sType=VK_STRUCTURE_TYPE_EXTERNAL_BUFFER_PROPERTIES};
   vkGetPhysicalDeviceExternalBufferProperties(pdev,&ebi,&ebp);
   printf("tampon : exportable=%d importable=%d\n",
      !!(ebp.externalMemoryProperties.externalMemoryFeatures&VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT),
      !!(ebp.externalMemoryProperties.externalMemoryFeatures&VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT));

   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pdev,&mp);
   uint32_t mt=UINT32_MAX;
   for(uint32_t i=0;i<mp.memoryTypeCount;i++)
      if(mp.memoryTypes[i].propertyFlags&VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT &&
         mp.memoryTypes[i].propertyFlags&VK_MEMORY_PROPERTY_HOST_COHERENT_BIT){mt=i;break;}
   if(mt==UINT32_MAX){printf("pas de type memoire visible hote\n");return 1;}

   const VkDeviceSize SZ = 64*1024;
   VkExportMemoryAllocateInfo emi={.sType=VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO,
      .handleTypes=VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT};
   VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.pNext=&emi,
      .allocationSize=SZ,.memoryTypeIndex=mt};
   VkDeviceMemory m1; CK(vkAllocateMemory(dev,&mai,NULL,&m1));
   printf("allocation exportable : ok\n");

   PFN_vkGetMemoryFdKHR getfd=(PFN_vkGetMemoryFdKHR)vkGetDeviceProcAddr(dev,"vkGetMemoryFdKHR");
   PFN_vkGetMemoryFdPropertiesKHR getprops=
      (PFN_vkGetMemoryFdPropertiesKHR)vkGetDeviceProcAddr(dev,"vkGetMemoryFdPropertiesKHR");
   if(!getfd||!getprops){printf("ECHEC: points d'entree absents\n");return 1;}

   VkMemoryGetFdInfoKHR gfi={.sType=VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR,
      .memory=m1,.handleType=VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT};
   int fd=-1; CK(getfd(dev,&gfi,&fd));
   printf("descripteur exporte : fd=%d\n", fd);

   VkMemoryFdPropertiesKHR fdp={.sType=VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR};
   CK(getprops(dev,VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT,fd,&fdp));
   printf("types memoire compatibles : 0x%x\n", fdp.memoryTypeBits);

   VkImportMemoryFdInfoKHR imi={.sType=VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR,
      .handleType=VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT,.fd=fd};
   VkMemoryAllocateInfo mai2={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.pNext=&imi,
      .allocationSize=SZ,.memoryTypeIndex=mt};
   VkDeviceMemory m2; CK(vkAllocateMemory(dev,&mai2,NULL,&m2));
   printf("reimport du descripteur : ok\n");

   void *p1=NULL,*p2=NULL;
   CK(vkMapMemory(dev,m1,0,SZ,0,&p1));
   CK(vkMapMemory(dev,m2,0,SZ,0,&p2));
   printf("projections : %p et %p%s\n", p1, p2, p1==p2?" (identiques)":"");

   const char *motif="partage-verifie-0123456789";
   memcpy(p1,motif,strlen(motif)+1);
   int egal = memcmp(p2,motif,strlen(motif)+1)==0;
   printf("ecrit par m1, relu par m2 : \"%s\"\n", (const char*)p2);

   ((unsigned char*)p2)[100]=0xAB;
   int retour = ((unsigned char*)p1)[100]==0xAB;
   printf("ecrit par m2, relu par m1 : %s\n", retour?"0xAB":"different");

   vkUnmapMemory(dev,m1); vkUnmapMemory(dev,m2);
   vkFreeMemory(dev,m2,NULL); vkFreeMemory(dev,m1,NULL);

   printf("%s\n", (egal&&retour)
      ? "RESULTAT: la memoire est reellement partagee entre les deux allocations"
      : "RESULTAT: les deux vues ne designent pas la meme memoire");
   return (egal&&retour)?0:1;
}
