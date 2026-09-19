/* Valide le decoupage : N encodeurs repartis sur des command buffers de CHUNK. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <mach/mach_time.h>
static double ms_now(void){
  static mach_timebase_info_data_t tb; if(tb.denom==0) mach_timebase_info(&tb);
  return (double)mach_absolute_time()*tb.numer/tb.denom/1e6; }
int main(int argc,char**argv){@autoreleasepool{
  uint32_t total = argc>1?(uint32_t)atoi(argv[1]):65536;
  uint32_t chunk = argc>2?(uint32_t)atoi(argv[2]):16384;
  int share_alloc = argc>3?atoi(argv[3]):0;
  id<MTLDevice> dev=[MTLCopyAllDevices() firstObject];
  id<MTL4CommandAllocator> shared=[dev newCommandAllocator];
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  MTLTextureDescriptor *td=[MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB
      width:16 height:16 mipmapped:NO];
  td.usage=MTLTextureUsageRenderTarget; td.storageMode=MTLStorageModePrivate;
  id<MTLTexture> tex=[dev newTextureWithDescriptor:td];

  double t0=ms_now();
  uint32_t done=0, nbuf=0; __block NSError *err=nil;
  while(done<total){
    uint32_t n = (total-done) < chunk ? (total-done) : chunk;
    /* Un allocateur neuf par morceau : c'est lui qui sature. */
    id<MTL4CommandAllocator> alloc = share_alloc ? shared : [dev newCommandAllocator];
    id<MTL4CommandBuffer> cb=[dev newCommandBuffer];
    [cb beginCommandBufferWithAllocator:alloc];
    for(uint32_t i=0;i<n;i++){
      MTL4RenderPassDescriptor *rp=[MTL4RenderPassDescriptor new];
      rp.colorAttachments[0].texture=tex;
      rp.colorAttachments[0].loadAction=MTLLoadActionClear;
      rp.colorAttachments[0].storeAction=MTLStoreActionStore;
      id<MTL4RenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
      [e endEncoding];
    }
    [cb endCommandBuffer];
    dispatch_semaphore_t sem=dispatch_semaphore_create(0);
    MTL4CommitOptions *opt=[MTL4CommitOptions new];
    [opt addFeedbackHandler:^(id<MTL4CommitFeedback> fb){ if(fb.error) err=fb.error;
                                                          dispatch_semaphore_signal(sem); }];
    id<MTL4CommandBuffer> bufs[1]={cb};
    [q commit:bufs count:1 options:opt];
    dispatch_semaphore_wait(sem,DISPATCH_TIME_FOREVER);
    if(err) break;
    done+=n; nbuf++;
  }
  printf("%6u encodeurs, morceaux de %6u (%u cb), allocateur %s : %8.1f ms  %s\n",
         total, chunk, nbuf, share_alloc?"PARTAGE":"par morceau", ms_now()-t0,
         err?[[err localizedDescription] UTF8String]:"OK");
  return err?1:0;
}}
