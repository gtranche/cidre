/* Sonde : Metal applique-t-il vraiment l'alignement qu'il annonce pour une
 * texture en tableau placee dans un tas ? On tente plusieurs offsets. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main(void)
{
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        MTLTextureDescriptor *d = [[MTLTextureDescriptor alloc] init];
        d.textureType = MTLTextureType2DArray;
        d.pixelFormat = MTLPixelFormatBC1_RGBA;
        d.width = 512; d.height = 256;
        d.mipmapLevelCount = 1; d.arrayLength = 2;
        d.storageMode = MTLStorageModePrivate;
        d.usage = MTLTextureUsageShaderRead;

        MTLSizeAndAlign sa = [dev heapTextureSizeAndAlignWithDescriptor:d];
        printf("annonce : taille %lu align %lu\n",
               (unsigned long)sa.size, (unsigned long)sa.align);

        MTLHeapDescriptor *hd = [[MTLHeapDescriptor alloc] init];
        hd.size = sa.size + 65536;
        hd.storageMode = MTLStorageModePrivate;
        hd.type = MTLHeapTypePlacement;
        id<MTLHeap> heap = [dev newHeapWithDescriptor:hd];
        if (!heap) { printf("tas de placement refuse\n"); return 1; }

        NSUInteger offsets[] = { 0, 4096, 8192, 12288, 16384, 128, 512 };
        for (unsigned i = 0; i < sizeof(offsets)/sizeof(*offsets); ++i) {
            id<MTLTexture> t = [heap newTextureWithDescriptor:d offset:offsets[i]];
            printf("  offset %6lu : %s\n", (unsigned long)offsets[i],
                   t ? "accepte" : "REFUSE");
        }
    }
    return 0;
}
