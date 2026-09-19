#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static NSString *SRC = @"#include <metal_stdlib>\n"
"using namespace metal;\n"
"vertex float4 vmain(uint i [[vertex_id]]) { return float4(0,0,0,1); }\n"
"fragment float4 fmain() { return float4(1,0,0,1); }\n";
static id<MTLRenderPipelineState> mkPipe(id<MTLDevice> dev, id<MTLLibrary> lib,
                                         MTLPixelFormat fmt, NSError **err) {
  MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
  d.vertexFunction = [lib newFunctionWithName:@"vmain"];
  d.fragmentFunction = [lib newFunctionWithName:@"fmain"];
  d.colorAttachments[0].pixelFormat = fmt;
  return [dev newRenderPipelineStateWithDescriptor:d error:err];
}
static void run(const char *label, id<MTLCommandQueue> q,
                id<MTLRenderPipelineState> pso, id<MTLTexture> tex) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  if (tex) {
    rp.colorAttachments[0].texture = tex;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  } else {
    rp.renderTargetWidth = 64; rp.renderTargetHeight = 64;
    rp.defaultRasterSampleCount = 1;
  }
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  if (!e) { printf("%-46s ENCODEUR NIL\n", label); return; }
  [e setRenderPipelineState:pso];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e endEncoding];
  [cb commit];
  [cb waitUntilCompleted];
  printf("%-46s status=%ld err=%s\n", label, (long)cb.status,
         cb.error ? [[cb.error localizedDescription] UTF8String] : "aucune");
}
int main(int argc, char **argv) { @autoreleasepool {
  int only = argc>1 ? atoi(argv[1]) : 0;
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:SRC options:nil error:&err];
  if (!lib) { printf("lib: %s\n", [[err localizedDescription] UTF8String]); return 1; }
  id<MTLCommandQueue> q = [dev newCommandQueue];
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
      width:64 height:64 mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget;
  td.storageMode = MTLStorageModePrivate;
  id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
  id<MTLRenderPipelineState> pWith = mkPipe(dev, lib, MTLPixelFormatBGRA8Unorm, &err);
  printf("pipeline avec format   : %s\n", pWith ? "cree" : [[err localizedDescription] UTF8String]);
  id<MTLRenderPipelineState> pNone = mkPipe(dev, lib, MTLPixelFormatInvalid, &err);
  printf("pipeline format Invalid: %s\n\n", pNone ? "cree" : [[err localizedDescription] UTF8String]);
  if (only==0 || only==1) run("A. pipeline=BGRA8, passe SANS attachement", q, pWith, nil);
  if (only==0 || only==2) run("B. pipeline=Invalid, passe AVEC attachement", q, pNone, tex);
  if (only==0 || only==3) run("C. temoin: pipeline=BGRA8, passe AVEC", q, pWith, tex);
  return 0;
} }
