/* Sonde : alignement et taille que Metal rapporte pour une texture de tas,
 * en faisant varier le nombre de couches. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void mesure(id<MTLDevice> dev, MTLPixelFormat fmt, NSUInteger w, NSUInteger h,
                   NSUInteger levels, NSUInteger layers, const char *nom)
{
    MTLTextureDescriptor *d = [[MTLTextureDescriptor alloc] init];
    d.textureType = layers > 1 ? MTLTextureType2DArray : MTLTextureType2D;
    d.pixelFormat = fmt;
    d.width = w; d.height = h;
    d.mipmapLevelCount = levels;
    d.arrayLength = layers;
    d.storageMode = MTLStorageModePrivate;
    d.usage = MTLTextureUsageShaderRead;

    MTLSizeAndAlign sa = [dev heapTextureSizeAndAlignWithDescriptor:d];
    printf("  %-28s couches %2lu : taille %8lu  align %6lu\n", nom,
           (unsigned long)layers, (unsigned long)sa.size, (unsigned long)sa.align);
}

int main(void)
{
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        printf("peripherique : %s\n\n", [[dev name] UTF8String]);

        printf("BC1 512x256, 1 niveau :\n");
        for (NSUInteger l = 1; l <= 4; ++l)
            mesure(dev, MTLPixelFormatBC1_RGBA, 512, 256, 1, l, "BC1 512x256");

        printf("\nRGBA8 128x128, 1 niveau :\n");
        for (NSUInteger l = 1; l <= 4; ++l)
            mesure(dev, MTLPixelFormatRGBA8Unorm, 128, 128, 1, l, "RGBA8 128x128");

        printf("\nRGBA8 64x64, 1 niveau :\n");
        for (NSUInteger l = 1; l <= 3; ++l)
            mesure(dev, MTLPixelFormatRGBA8Unorm, 64, 64, 1, l, "RGBA8 64x64");
    }
    return 0;
}
