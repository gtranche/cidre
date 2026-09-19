#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
struct { MTLPixelFormat f; const char *n; unsigned texel; } F[] = {
  {MTLPixelFormatR8Unorm,"R8Unorm",1}, {MTLPixelFormatRG8Unorm,"RG8Unorm",2},
  {MTLPixelFormatRGBA8Unorm,"RGBA8Unorm",4}, {MTLPixelFormatR16Float,"R16Float",2},
  {MTLPixelFormatRG16Float,"RG16Float",4}, {MTLPixelFormatRGBA16Float,"RGBA16Float",8},
  {MTLPixelFormatR32Float,"R32Float",4}, {MTLPixelFormatRG32Float,"RG32Float",8},
  {MTLPixelFormatRGBA32Float,"RGBA32Float",16}, {MTLPixelFormatR32Uint,"R32Uint",4},
  {MTLPixelFormatRGBA32Uint,"RGBA32Uint",16}, {MTLPixelFormatRG11B10Float,"RG11B10",4},
};
int main(void){@autoreleasepool{
  id<MTLDevice> dev=[MTLCopyAllDevices() firstObject];
  printf("%-14s %6s %10s %10s  %s\n","format","texel","lineaire","buffer","alignement == taille du texel ?");
  int all_single=1;
  for(unsigned i=0;i<sizeof(F)/sizeof(F[0]);i++){
    NSUInteger lin=[dev minimumLinearTextureAlignmentForPixelFormat:F[i].f];
    NSUInteger buf=[dev minimumTextureBufferAlignmentForPixelFormat:F[i].f];
    int single = (buf == F[i].texel);
    if(!single) all_single=0;
    printf("%-14s %6u %10lu %10lu  %s\n",F[i].n,F[i].texel,
           (unsigned long)lin,(unsigned long)buf, single?"oui":"NON");
  }
  printf("\n=> alignement au texel unique sur tous les formats testes : %s\n",
         all_single?"OUI":"NON");
  return 0;
}}
