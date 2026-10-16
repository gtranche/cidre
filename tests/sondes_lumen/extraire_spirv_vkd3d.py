#!/usr/bin/env python3
# Extrait les modules SPIR-V d'un cache d'archive de flux vkd3d-proton (vkd3d-proton.cache[.write]).
#   python3 -I extraire_spirv_vkd3d.py <cache> <dossier de sortie>
# Format (libs/vkd3d/cache.c) : en-tete de 48 octets, puis des entrees {hash u64, checksum u64,
# size u32, type u32, data[size] aligne a 8}. Type 0 = SPIR-V : data = {checksum u32,
# decompressed_size u32, compressed_size u32, varint[compressed_size]}.
import os, struct, sys


def decode_varint(buf, nwords):
    out = []
    off = 0
    for _ in range(nwords):
        w = 0
        shift = 0
        while True:
            b = buf[off]
            off += 1
            w |= (b & 0x7f) << shift
            shift += 7
            if not b & 0x80:
                break
        out.append(w & 0xffffffff)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    d = open(src, 'rb').read()
    off = 48
    n = 0
    while off + 24 <= len(d):
        h, _ck, size, typ = struct.unpack_from('<QQII', d, off)
        data = d[off + 24: off + 24 + size]
        if len(data) < size:
            break
        off += 24 + ((size + 7) & ~7)
        if typ != 0 or size < 12:
            continue
        _c, dec, comp = struct.unpack_from('<III', data, 0)
        try:
            words = decode_varint(data[12:12 + comp], dec // 4)
        except IndexError:
            continue
        if not words or words[0] != 0x07230203:
            continue
        open(os.path.join(dst, '%016x.spv' % h), 'wb').write(struct.pack('<%dI' % len(words), *words))
        n += 1
    print('%d modules SPIR-V' % n)


main()
