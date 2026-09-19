/* Reproduit le chemin Metal 4 de KosmicKrisp pour tester la tolerance
 * aux formats d'attachement discordants. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static NSString *SRC = @"#include <metal_stdlib>\nusing namespace metal;\n"
"vertex float4 vmain(uint i [[vertex_id]]) { return float4(0,0,0,1); }\n"
"fragment float4 fmain() { return float4(1,0,0,1); }\n";

int main(int argc, char **argv) { @autoreleasepool {
  int mode = argc > 1 ? atoi(argv[1]) : 0;   /* 1=A 2=B 3=temoin */
  id<MTLDevice> dev = [MTLCopyAllDevices() firstObject];

  NSError *err = nil;
  MTL4CompilerDescriptor *cd = [MTL4CompilerDescriptor new];
  id<MTL4Compiler> comp = [dev newCompilerWithDescriptor:cd error:&err];
  if (!comp) { printf("compiler: %s\n", [[err localizedDescription] UTF8String]); return 1; }

  MTL4LibraryDescriptor *ld = [MTL4LibraryDescriptor new];
  ld.source = SRC;
  id<MTLLibrary> lib = [comp newLibraryWithDescriptor:ld error:&err];
  if (!lib) { printf("library: %s\n", [[err localizedDescription] UTF8String]); return 1; }

  MTL4LibraryFunctionDescriptor *vfd = [MTL4LibraryFunctionDescriptor new];
  vfd.library = lib; vfd.name = @"vmain";
  MTL4LibraryFunctionDescriptor *ffd = [MTL4LibraryFunctionDescriptor new];
  ffd.library = lib; ffd.name = @"fmain";

  /* Le pipeline declare un format sauf en mode B. */
  MTLPixelFormat pipe_fmt = (mode == 2) ? MTLPixelFormatInvalid : MTLPixelFormatBGRA8Unorm;
  MTL4RenderPipelineDescriptor *pd = [MTL4RenderPipelineDescriptor new];
  pd.vertexFunctionDescriptor = vfd;
  pd.fragmentFunctionDescriptor = ffd;
  pd.colorAttachments[0].pixelFormat = pipe_fmt;
  id<MTLRenderPipelineState> pso =
      [comp newRenderPipelineStateWithDescriptor:pd compilerTaskOptions:nil error:&err];
  if (!pso) { printf("pipeline: %s\n", [[err localizedDescription] UTF8String]); return 1; }

  /* La passe a une texture sauf en mode A. */
  id<MTLTexture> tex = nil;
  if (mode != 1) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:64 height:64 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModePrivate;
    tex = [dev newTextureWithDescriptor:td];
  }

  MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new];
  if (tex) {
    rp.colorAttachments[0].texture = tex;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  } else {
    rp.renderTargetWidth = 64; rp.renderTargetHeight = 64;
    rp.defaultRasterSampleCount = 1;
  }

  id<MTL4CommandQueue> q = [dev newMTL4CommandQueue];
  id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
  id<MTL4CommandBuffer> cb = [dev newCommandBuffer];
  [cb beginCommandBufferWithAllocator:alloc];
  id<MTL4RenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
  if (!enc) { printf("mode %d : ENCODEUR NIL\n", mode); return 1; }
  [enc setRenderPipelineState:pso];
  if (mode == 4) {
    /* Test de profondeur actif alors que la passe n'a pas d'attachement depth,
     * exactement ce que fait un pipeline statique de KosmicKrisp sous
     * VK_EXT_dynamic_rendering_unused_attachments. */
    MTLDepthStencilDescriptor *dsd = [MTLDepthStencilDescriptor new];
    dsd.depthCompareFunction = MTLCompareFunctionLess;
    dsd.depthWriteEnabled = YES;
    [enc setDepthStencilState:[dev newDepthStencilStateWithDescriptor:dsd]];
  }
  [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [enc endEncoding];
  [cb endCommandBuffer];
  id<MTL4CommandBuffer> bufs[1] = { cb };
  __block NSError *cmd_err = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MTL4CommitOptions *opt = [MTL4CommitOptions new];
  [opt addFeedbackHandler:^(id<MTL4CommitFeedback> fb) {
     cmd_err = fb.error;
     dispatch_semaphore_signal(sem);
  }];
  [q commit:bufs count:1 options:opt];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (cmd_err) {
     printf("mode %d : ERREUR GPU : %s\n", mode, [[cmd_err localizedDescription] UTF8String]);
     return 1;
  }

  const char *names[] = {"", "A. pipeline=BGRA8 | passe SANS texture",
                             "B. pipeline=Invalid | passe AVEC texture",
                             "C. temoin concordant",
                             "D. depth test actif | passe SANS depth"};
  printf("%-44s PASSE (aucune assertion Metal 4)\n", names[mode]);
  return 0;
} }
