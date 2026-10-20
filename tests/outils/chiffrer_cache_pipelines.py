# Chiffre ce que coute la re-serialisation du cache de pipelines KK (0166) : parcourt le VkPipelineCache de Detroit
# (en-tete du jeu, puis cache Vulkan de Mesa), retrouve chaque MSL compresse (zstd) des objets, le decompresse et
# mesure le temps de recompression au niveau de util/compress.c (3), comme le fait kk_msl_serialize a chaque
# vkGetPipelineCacheData pour chaque nuanceur vivant.
#   python3 -I tests/outils/chiffrer_cache_pipelines.py <VkPipelineCache.bin> [echantillon]
import struct, sys, time
import zstandard

chemin = sys.argv[1]
pas = int(sys.argv[2]) if len(sys.argv) > 2 else 1
d = open(chemin, 'rb').read()
base = d.find(struct.pack('<II', 32, 1))
off = base + 32
(count,) = struct.unpack_from('<I', d, off); off += 4
MAGIC = b'\x28\xb5\x2f\xfd'
dctx = zstandard.ZstdDecompressor()
cctx = zstandard.ZstdCompressor(level=3)
objets = msl = 0
brut = paque = 0
t_comp = t_decomp = 0.0
taille_donnees = 0
for i in range(count):
    off = base + (((off - base) + 3) & ~3)   # blob_write_uint32 aligne sur 4
    typ, ks, ds = struct.unpack_from('<iII', d, off); off += 12
    off += ks
    off = base + (((off - base) + 7) & ~7)
    data = d[off:off + ds]; off += ds
    taille_donnees += ds
    objets += 1
    if i % pas: continue
    p = 0
    while True:
        m = data.find(MAGIC, p)
        if m < 0: break
        p = m + 4
        for L in range(1, 256):
            h = m - L - 12
            if h < 0: break
            el, cl, pl = struct.unpack_from('<III', data, h)
            if el == L and data[m - 1] == 0 and 0 < pl < cl and m + pl <= len(data):
                t0 = time.perf_counter()
                code = dctx.decompress(data[m:m + pl], max_output_size=cl)
                t1 = time.perf_counter()
                cctx.compress(code)
                t2 = time.perf_counter()
                t_decomp += t1 - t0; t_comp += t2 - t1
                msl += 1; brut += cl; paque += pl
                p = m + pl
                break
print(f"objets {objets} (donnees {taille_donnees/1e6:.0f} Mo), echantillon 1/{pas} : {msl} MSL, "
      f"brut {brut/1e6:.0f} Mo -> {paque/1e6:.0f} Mo")
print(f"recompression zstd-3 : {t_comp:.2f} s ({brut/1e6/max(t_comp,1e-9):.0f} Mo/s) ; decompression {t_decomp:.2f} s")
print(f"extrapole au cache entier : recompression {t_comp*pas:.1f} s par serialisation, "
      f"x2 par sauvegarde (taille puis donnees) = {2*t_comp*pas:.1f} s sous le verrou du cache")
