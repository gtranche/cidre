#!/usr/bin/env python3
"""Genere un noyau MSL de 32 lectures de texture par fil, ecrit comme KosmicKrisp ecrit
le MSL d'un filtre de jeu D3D12 (Little Nightmares Enhanced Edition, 2026-10-14).

usage : gen_filtre_textures.py <zero> <bord> <nul> > noyau.metal
  zero : 0 = fmin/fmax simples ; 1 = min/max a zero signe comme KosmicKrisp avant 0135
         (« !isnan && !isnan && a == b ? bits : precise::fmax », en bloc math_mode(safe)) ;
         2 = test entier de 0135 (« ((bits(a)|bits(b))<<1)==0 ? bits : precise::fmax »).
  bord : 1 = couleur de bord emulee (custom_border : seconde lecture conditionnelle,
         melange par composante choisi par un mot de swizzle).
  nul  : 1 = chaque lecture dans « if (descripteur non nul) » (KosmicKrisp avant 0136).
"""
import sys

zero, bord, nul = (int(x) for x in sys.argv[1:4])
o = []
P = o.append
P("#include <metal_stdlib>\nusing namespace metal;")
P("struct Params { float4 w[32]; float4 off[32]; float4 clampv; float4 border; uint swz; uint has_border; };")
P("kernel void k(texture2d<float> tex [[texture(0)]], texture2d<float, access::write> outt [[texture(1)]],")
P("              sampler smp0 [[sampler(0)]], sampler smp1 [[sampler(1)]], constant Params &p [[buffer(0)]],")
P("              uint2 gid [[thread_position_in_grid]]) {")
P("   float2 base = (float2(gid) + 0.5) / float2(outt.get_width(), outt.get_height());")
P("   float4 acc = float4(0);")


def mx(name, a, b, is_min):
    fn = "fmin" if is_min else "fmax"
    if zero == 0:
        P(f"   float {name} = {fn}({a}, {b});")
        return
    op = "|" if is_min else "&"
    if zero == 1:
        test = f"!isnan({a}) && !isnan({b}) && {a} == {b}"
    else:
        test = f"uint((as_type<uint>({a}) | as_type<uint>({b})) << 1) == uint(0)"
    P(f"   float {name};")
    P("   {")
    P("   #pragma METAL fp math_mode(safe)")
    P(f"   {name} = {test} ? as_type<float>(uint(as_type<uint>({a}) {op} as_type<uint>({b}))) : precise::{fn}({a}, {b});")
    P("   }")


for i in range(32):
    P(f"   float2 c{i} = base + p.off[{i}].xy;")
    mx(f"x{i}a", f"c{i}.x", "p.clampv.x", False)
    mx(f"y{i}a", f"c{i}.y", "p.clampv.y", False)
    mx(f"x{i}", f"x{i}a", "p.clampv.z", True)
    mx(f"y{i}", f"y{i}a", "p.clampv.w", True)
    lecture = f"tex.sample(smp0, float2(x{i}, y{i}), level(0.0))"
    if nul:
        P(f"   float4 s{i}; if (p.has_border != 7u) {{ s{i} = {lecture}; }} else {{ s{i} = float4(0); }}")
    else:
        P(f"   float4 s{i} = {lecture};")
    if bord:
        P("   if (p.has_border) {")
        P(f"      float4 t{i} = tex.sample(smp1, float2(x{i}, y{i}), level(0.0));")
        P(f"      float4 m{i};")
        for k, comp in enumerate("xyzw"):
            P(f"      {{ uint q = (p.swz >> {3*k}u) & 7u; float f = q == 1u ? p.border.y : p.border.x;")
            P("        f = q == 2u ? p.border.z : f; f = q == 3u ? p.border.w : f; f = q == 4u ? 0.0 : f; f = q == 5u ? 1.0 : f;")
            P(f"        m{i}.{comp} = mix(t{i}.{comp}, s{i}.{comp}, f); }}")
        P(f"      s{i} = m{i};")
        P("   }")
    P(f"   acc = fma(s{i}, p.w[{i}], acc);")
    mx(f"a{i}", "acc.x", "0.0f", False)
    P(f"   acc.x = a{i};")
P("   outt.write(acc, gid);")
P("}")
print("\n".join(o))
