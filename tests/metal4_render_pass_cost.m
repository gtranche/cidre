/* Cout d'un encodeur de rendu Metal 4 vide, pour comparer a KosmicKrisp. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <mach/mach_time.h>

static double ms_now(void){
  static mach_timebase_info_data_t tb; if(tb.denom==0) mach_timebase_info(&tb);
  return (double)mach_absolute_time()*tb.numer/tb.denom/1e6;
}
int main(int argc, char **argv){@autoreleasepool{
  uint32_t passes = argc>1 ? (uint32_t)atoi(argv[1]) : 1024;
  id<MTLDevice> dev=[MTLCopyAllDevices() firstObject];
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  id<MTL4CommandAllocator> alloc=[dev newCommandAllocator];
  id<MTL4CommandBuffer> cb=[dev newCommandBuffer];

  /* Une texture par passe, comme le fait le test (une couche chacune). */
  NSMutableArray *texs=[NSMutableArray array];
  MTLTextureDescriptor *td=[MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB
      width:16 height:16 mipmapped:NO];
  td.usage=MTLTextureUsageRenderTarget; td.storageMode=MTLStorageModePrivate;
  for(uint32_t i=0;i<passes;i++) [texs addObject:[dev newTextureWithDescriptor:td]];

  double t0=ms_now();
  [cb beginCommandBufferWithAllocator:alloc];
  for(uint32_t i=0;i<passes;i++){
    MTL4RenderPassDescriptor *rp=[MTL4RenderPassDescriptor new];
    rp.colorAttachments[0].texture=texs[i];
    rp.colorAttachments[0].loadAction=MTLLoadActionClear;
    rp.colorAttachments[0].storeAction=MTLStoreActionStore;
    rp.colorAttachments[0].clearColor=MTLClearColorMake(1,0,0,1);
    id<MTL4RenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
    [e endEncoding];
  }
  [cb endCommandBuffer];
  double t_rec=ms_now()-t0;

  __block NSError *err=nil;
  dispatch_semaphore_t sem=dispatch_semaphore_create(0);
  MTL4CommitOptions *opt=[MTL4CommitOptions new];
  [opt addFeedbackHandler:^(id<MTL4CommitFeedback> fb){ err=fb.error; dispatch_semaphore_signal(sem); }];
  id<MTL4CommandBuffer> bufs[1]={cb};
  double t1=ms_now();
  [q commit:bufs count:1 options:opt];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  double t_gpu=ms_now()-t1;

  printf("%5u encodeurs Metal 4 purs : enregistrement %7.1f ms | execution %7.1f ms"
         " | %5.1f us/passe  %s\n", passes, t_rec, t_gpu,
         (t_rec+t_gpu)*1000.0/passes, err?[[err localizedDescription] UTF8String]:"OK");
  return 0;
}}
