/* vkGetDeviceProcAddr rend-il vkGetMemoryWin32HandleKHR une fois l'extension activee ? */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

int main(void)
{
   VkApplicationInfo ai = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_3};
   VkInstanceCreateInfo ici = {.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ai};
   VkInstance inst;
   if (vkCreateInstance(&ici,NULL,&inst)) { printf("ECHEC instance\n"); return 1; }

   uint32_t n=1; VkPhysicalDevice pdev;
   if (vkEnumeratePhysicalDevices(inst,&n,&pdev)) { printf("ECHEC peripherique\n"); return 1; }

   uint32_t ec=0; vkEnumerateDeviceExtensionProperties(pdev,NULL,&ec,NULL);
   VkExtensionProperties *ex = calloc(ec,sizeof(*ex));
   vkEnumerateDeviceExtensionProperties(pdev,NULL,&ec,ex);
   int have=0;
   for (uint32_t i=0;i<ec;i++)
      if (!strcmp(ex[i].extensionName,"VK_KHR_external_memory_win32")) have=1;
   printf("VK_KHR_external_memory_win32 annonce : %s\n", have?"oui":"non");
   if (!have) return 1;

   uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,NULL);
   VkQueueFamilyProperties *qp=calloc(qn,sizeof(*qp));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev,&qn,qp);
   uint32_t qf=0; for(uint32_t i=0;i<qn;i++) if(qp[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){qf=i;break;}
   float prio=1.f;
   VkDeviceQueueCreateInfo dqi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex=qf,.queueCount=1,.pQueuePriorities=&prio};
   const char *devext[]={"VK_KHR_external_memory","VK_KHR_external_memory_win32"};
   VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount=1,.pQueueCreateInfos=&dqi,
      .enabledExtensionCount=2,.ppEnabledExtensionNames=devext};
   VkDevice dev;
   VkResult r = vkCreateDevice(pdev,&dci,NULL,&dev);
   printf("creation du peripherique avec l'extension : %s (%d)\n", r?"ECHEC":"ok", r);
   if (r) return 1;

   void *p1 = (void *)vkGetDeviceProcAddr(dev, "vkGetMemoryWin32HandleKHR");
   void *p2 = (void *)vkGetDeviceProcAddr(dev, "vkGetMemoryWin32HandlePropertiesKHR");
   void *p3 = (void *)vkGetDeviceProcAddr(dev, "vkAllocateMemory");
   printf("vkGetMemoryWin32HandleKHR           : %p\n", p1);
   printf("vkGetMemoryWin32HandlePropertiesKHR : %p\n", p2);
   printf("vkAllocateMemory (temoin)           : %p\n", p3);
   printf("%s\n", p1 ? "RESULTAT: resolu" : "RESULTAT: NUL, c'est la cause du plantage");
   return p1 ? 0 : 1;
}
