// Sonde : forme MSL d'une valeur indefinie scalaire (correctif KosmicKrisp 0131).
// Little Nightmares EE en D3D12 (2026-10-14) : « call to 'insert_bits' is ambiguous »
// sur « insert_bits(uint(1u), 00, int(1), int(31)) » -- le 00 sans type que l'emetteur
// ecrivait pour un indefini laisse Metal hesiter entre les variantes int et uint.
// Compile chaque forme avec Metal et dit laquelle passe.
//   /usr/bin/clang -arch arm64 -fobjc-arc tests/sonde_msl_indefini.m -framework Metal \
//      -framework Foundation -o build/sonde_msl_indefini && build/sonde_msl_indefini
#import <Metal/Metal.h>
#include <stdio.h>
static void essai(id<MTLDevice> dev, const char *nom, const char *expr) {
   NSString *src = [NSString stringWithFormat:@"#include <metal_stdlib>\nusing namespace metal;\n"
      "kernel void k(device uint *o [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
      "   uint t807 = %@;\n   o[i] = t807;\n}\n", [NSString stringWithUTF8String:expr]];
   NSError *e = nil;
   id<MTLLibrary> l = [dev newLibraryWithSource:src options:[MTLCompileOptions new] error:&e];
   printf("%-28s %-50s -> %s\n", nom, expr, l ? "compile" : "ECHEC");
   if (!l) printf("   %s\n", [[[e.localizedDescription componentsSeparatedByString:@"\n"] firstObject] UTF8String]);
}
int main(void) { @autoreleasepool {
   id<MTLDevice> d = MTLCreateSystemDefaultDevice();
   essai(d, "avant (pilote installe)", "insert_bits(uint(1u), 00, int(1), int(31))");
   essai(d, "apres (0131, scalaire uint)", "insert_bits(uint(1u), uint(0), int(1), int(31))");
   essai(d, "apres (0131, int)", "uint(insert_bits(int(1), int(0), int(1), int(31)))");
   essai(d, "extract_bits avant", "extract_bits(00, int(1), int(31))");
   essai(d, "extract_bits apres", "extract_bits(uint(0), int(1), int(31))");
} return 0; }
