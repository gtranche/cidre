// Banc « vrais vertex shaders » : execute en Metal natif (arm64) les variantes
// fabriquees par banc_vs_reels_variantes.py a partir des vertex shaders AIR
// qu'airconv a produits pour un jeu, sur des maillages synthetiques, et mesure
// le temps GPU de l'etage sommets (shading + decoupage en tuiles) par les
// horodatages de frontiere d'etage (MTLCounterSamplingPointAtStageBoundary),
// la meme grandeur que le canal « Vertex » de xctrace.
//
// Liaisons de DXMT reproduites (airconv_public.h, dxmt_context.cpp) :
//   buffer(0)  table des cbuffers       : une adresse GPU par cbuffer
//   buffer(1)  table d'arguments        : SRV tampon = adresse + longueur ;
//              texture_buffer = identifiant + (elements << 32 | premier) ;
//              texture = identifiant + (tranches << 32 | lod min) ;
//              echantillonneur = identifiant x2 + biais de lod
//   buffer(2)  table des tampons de sommets : { adresse, pas, longueur } par slot
// Ajouts du banc : buffer(30) « banc » (mot de masque nul puis une position
// float4 par sommet, deja en coordonnees de decoupe) et buffer(29) « bancd ».
//
// Chaque mesure : (chauffe + passes) passes de rendu identiques (1920x1080
// RGBA8 + Depth32F), une par tampon de commandes, soumises l'une apres l'autre ;
// on garde la mediane des passes mesurees, puis la mediane des tours, variantes
// entrelacees. Un tour de mise en route precede les tours mesures.
//
// Construction et usage : tests/banc_vs_reels.sh
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { LARGEUR = 1920, HAUTEUR = 1080, NB_VDATA = 4, PAS_VDATA = 16, NB_CB = 16, TAILLE_CB = 65536,
       TAILLE_BRUT = 4 << 20, ELEMENTS_TB = 65536, MAX_VARIANTES = 24, MAX_CONFIGS = 8 };

static id<MTLDevice> dev;
static id<MTLCommandQueue> file;
static id<MTLCounterSet> horodatage;
static id<MTLTexture> cible, profondeur;
static id<MTLDepthStencilState> etat_profondeur;

typedef struct {
    char nom[24];
    int qw, qh;         // quads par dessin
    int indexe;         // 1 : liste de triangles indexee (6 index par quad, sommets partages)
    int dessins, sommets_par_dessin, indices_par_dessin;
    double pas_px;      // cote d'un quad a l'ecran
} Config;

typedef struct {
    Config c;
    id<MTLBuffer> banc, index_face, index_dos;
} Maillage;

typedef struct {
    uint32_t motif;
    id<MTLBuffer> vdata[NB_VDATA], table_vb, cb, brut, bancd, tb_f, tb_u;
    id<MTLTexture> vue_tb_f, vue_tb_u;
    NSMutableDictionary<NSString *, id<MTLTexture>> *textures;
    id<MTLSamplerState> echantillonneur;
} Ressources;

typedef struct {
    id<MTLRenderPipelineState> etat;
    id<MTLBuffer> table_args, table_cb;
    int idx_args, idx_cb, idx_vb, idx_banc, idx_bancd;
    NSMutableArray *residents;
} Pipeline;

static void remplir(void *p, size_t n, uint32_t motif) {
    uint32_t *q = p;
    for (size_t i = 0; i < n / 4; i++) q[i] = motif;
}

static id<MTLBuffer> tampon(size_t n, uint32_t motif) {
    id<MTLBuffer> b = [dev newBufferWithLength:n options:MTLResourceStorageModeShared];
    if (!b) { fprintf(stderr, "allocation de %zu octets refusee\n", n); exit(1); }
    remplir(b.contents, n, motif);
    return b;
}

static Maillage construire_maillage(Config c, long indices_par_passe) {
    Maillage m;
    int nq = c.qw * c.qh;
    c.indices_par_dessin = 6 * nq;
    c.sommets_par_dessin = c.indexe ? (c.qw + 1) * (c.qh + 1) : 6 * nq;
    c.dessins = (int)((indices_par_passe + c.indices_par_dessin / 2) / c.indices_par_dessin);
    if (c.dessins < 1) c.dessins = 1;
    m.c = c;
    size_t nv = (size_t)c.dessins * c.sommets_par_dessin;
    m.banc = tampon(16 + 16 * nv, 0);
    float *pos = (float *)((char *)m.banc.contents + 16);
    int colonnes = (int)(LARGEUR / (c.qw * c.pas_px)), rangees = (int)(HAUTEUR / (c.qh * c.pas_px));
    if (colonnes < 1) colonnes = 1;
    if (rangees < 1) rangees = 1;
    static const int coin[6][2] = {{0, 0}, {1, 0}, {0, 1}, {1, 0}, {1, 1}, {0, 1}};
    for (int d = 0; d < c.dessins; d++) {
        int place = d % (colonnes * rangees), couche = d / (colonnes * rangees);
        double x0 = (place % colonnes) * c.qw * c.pas_px, y0 = (place / colonnes) * c.qh * c.pas_px;
        float z = 0.9f - 0.01f * (couche % 80);
        float *p = pos + 4 * (size_t)d * c.sommets_par_dessin;
        if (c.indexe) {
            for (int j = 0; j <= c.qh; j++)
                for (int i = 0; i <= c.qw; i++, p += 4) {
                    p[0] = (float)((x0 + i * c.pas_px) / LARGEUR * 2 - 1);
                    p[1] = (float)(1 - (y0 + j * c.pas_px) / HAUTEUR * 2);
                    p[2] = z; p[3] = 1;
                }
        } else {
            for (int j = 0; j < c.qh; j++)
                for (int i = 0; i < c.qw; i++)
                    for (int k = 0; k < 6; k++, p += 4) {
                        p[0] = (float)((x0 + (i + coin[k][0]) * c.pas_px) / LARGEUR * 2 - 1);
                        p[1] = (float)(1 - (y0 + (j + coin[k][1]) * c.pas_px) / HAUTEUR * 2);
                        p[2] = z; p[3] = 1;
                    }
        }
    }
    m.index_face = m.index_dos = nil;
    if (c.indexe) {
        m.index_face = tampon(4 * (size_t)c.indices_par_dessin, 0);
        m.index_dos = tampon(4 * (size_t)c.indices_par_dessin, 0);
        uint32_t *a = m.index_face.contents, *b = m.index_dos.contents;
        for (int j = 0; j < c.qh; j++)
            for (int i = 0; i < c.qw; i++)
                for (int k = 0; k < 6; k++) {
                    uint32_t v = (uint32_t)((j + coin[k][1]) * (c.qw + 1) + i + coin[k][0]);
                    *a++ = v;
                    // meme triangle, sens inverse
                    b[(k / 3) * 3 + (k % 3 == 0 ? 0 : 3 - k % 3)] = v;
                    if (k == 5) b += 6;
                }
    }
    return m;
}

static Ressources construire_ressources(uint32_t motif, size_t sommets_max) {
    Ressources r;
    r.motif = motif;
    size_t nv = sommets_max * PAS_VDATA + 4096;
    r.table_vb = tampon(64 * 16, 0);
    uint64_t *t = r.table_vb.contents;
    for (int i = 0; i < NB_VDATA; i++) r.vdata[i] = tampon(nv, motif);
    for (int s = 0; s < 64; s++) {
        t[2 * s] = r.vdata[s % NB_VDATA].gpuAddress;
        t[2 * s + 1] = (uint64_t)PAS_VDATA | ((uint64_t)(uint32_t)nv << 32);
    }
    r.cb = tampon((size_t)NB_CB * TAILLE_CB, motif);
    r.brut = tampon(TAILLE_BRUT, motif);
    r.bancd = tampon(4096 * 16, motif);
    // texture_buffer = vue de texture sur un tampon, comme DXMT (dxmt_buffer.cpp)
    r.tb_f = tampon((size_t)ELEMENTS_TB * 16, motif);
    r.tb_u = tampon((size_t)ELEMENTS_TB * 16, motif);
    MTLTextureDescriptor *d = [MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
        width:ELEMENTS_TB resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];
    r.vue_tb_f = [r.tb_f newTextureWithDescriptor:d offset:0 bytesPerRow:(NSUInteger)ELEMENTS_TB * 16];
    d = [MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:MTLPixelFormatRGBA32Uint
        width:ELEMENTS_TB resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];
    r.vue_tb_u = [r.tb_u newTextureWithDescriptor:d offset:0 bytesPerRow:(NSUInteger)ELEMENTS_TB * 16];
    r.textures = [NSMutableDictionary new];
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.supportArgumentBuffers = YES;
    sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
    r.echantillonneur = [dev newSamplerStateWithDescriptor:sd];
    return r;
}

static id<MTLTexture> texture_pour(Ressources *r, MTLTextureReferenceType *t) {
    BOOL entier = t.textureDataType == MTLDataTypeUInt || t.textureDataType == MTLDataTypeInt;
    if (t.textureType == MTLTextureTypeTextureBuffer) return entier ? r->vue_tb_u : r->vue_tb_f;
    NSString *cle = [NSString stringWithFormat:@"%lu-%d-%d", (unsigned long)t.textureType, entier, t.isDepthTexture];
    id<MTLTexture> x = r->textures[cle];
    if (x) return x;
    MTLTextureDescriptor *d = [MTLTextureDescriptor new];
    d.textureType = t.textureType;
    d.pixelFormat = t.isDepthTexture ? MTLPixelFormatDepth32Float : entier ? MTLPixelFormatRGBA8Uint : MTLPixelFormatRGBA8Unorm;
    d.width = 64; d.height = 64;
    d.depth = t.textureType == MTLTextureType3D ? 16 : 1;
    if (t.textureType == MTLTextureType1D || t.textureType == MTLTextureType1DArray) d.height = 1;
    d.usage = MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModePrivate;
    x = [dev newTextureWithDescriptor:d];
    r->textures[cle] = x;
    return x;
}

// Remplit une table d'arguments d'apres la reflexion Metal du pipeline.
static id<MTLBuffer> table_arguments(Ressources *r, id<MTLBufferBinding> b, NSMutableArray *residents, BOOL cbuffers) {
    MTLStructType *st = b.bufferStructType;
    NSUInteger taille = b.bufferDataSize ? b.bufferDataSize : 8;
    id<MTLBuffer> buf = tampon(taille + 64, 0);
    uint64_t *q = buf.contents;
    int dernier = 0, ncb = 0;  // 1 tampon, 2 texture_buffer, 3 texture, 4 echantillonneur
    for (MTLStructMember *m in st.members) {
        uint64_t v = 0;
        switch (m.dataType) {
        case MTLDataTypePointer:
            if (cbuffers) {
                v = r->cb.gpuAddress + (uint64_t)(ncb++ % NB_CB) * TAILLE_CB;
                [residents addObject:r->cb];
            } else {
                v = r->brut.gpuAddress; dernier = 1;
                [residents addObject:r->brut];
            }
            break;
        case MTLDataTypeTexture: {
            id<MTLTexture> x = texture_pour(r, m.textureReferenceType);
            v = x.gpuResourceID._impl;
            dernier = m.textureReferenceType.textureType == MTLTextureTypeTextureBuffer ? 2 : 3;
            [residents addObject:x];
            if (x.buffer) [residents addObject:x.buffer];
            break;
        }
        case MTLDataTypeSampler:
            v = r->echantillonneur.gpuResourceID._impl; dernier = 4;
            break;
        default:  // mot de metadonnees qui suit la ressource
            v = dernier == 1 ? TAILLE_BRUT : dernier == 2 ? (uint64_t)ELEMENTS_TB << 32 : dernier == 3 ? 1ull << 32 : 0;
            break;
        }
        if (m.offset + 8 <= taille + 64) memcpy((char *)q + m.offset, &v, 8);
    }
    return buf;
}

static NSMutableDictionary<NSString *, id<MTLFunction>> *fragments;
static BOOL enchaine;  // --enchaine : toutes les passes dans un seul tampon de commandes
static BOOL sans_fragment;  // --sans-fragment : profondeur seule, pas de fonction de fragment

static BOOL construire_pipeline(Pipeline *p, Ressources *r, NSString *metallib, NSString *frag, NSString **err) {
    NSError *e = nil;
    id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:metallib] error:&e];
    if (!lib) { *err = e.localizedDescription; return NO; }
    id<MTLFunction> vs = [lib newFunctionWithName:lib.functionNames.firstObject];
    id<MTLFunction> fs = sans_fragment ? nil : fragments[frag];
    if (!fs && !sans_fragment) {
        NSString *src = [NSString stringWithContentsOfFile:frag encoding:NSUTF8StringEncoding error:&e];
        id<MTLLibrary> fl = src ? [dev newLibraryWithSource:src options:nil error:&e] : nil;
        if (!fl) { *err = e.localizedDescription; return NO; }
        fs = [fl newFunctionWithName:@"f"];
        fragments[frag] = fs;
    }
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = vs;
    d.fragmentFunction = fs;
    if (!sans_fragment) d.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    d.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    MTLRenderPipelineReflection *refl = nil;
    p->etat = [dev newRenderPipelineStateWithDescriptor:d
        options:MTLPipelineOptionBindingInfo | MTLPipelineOptionBufferTypeInfo reflection:&refl error:&e];
    if (!p->etat) { *err = e.localizedDescription; return NO; }
    p->idx_args = p->idx_cb = p->idx_vb = p->idx_banc = p->idx_bancd = -1;
    p->table_args = p->table_cb = nil;
    p->residents = [NSMutableArray new];
    for (id<MTLBinding> b in refl.vertexBindings) {
        if (b.type != MTLBindingTypeBuffer) { *err = [NSString stringWithFormat:@"liaison directe %@", b.name]; return NO; }
        id<MTLBufferBinding> bb = (id<MTLBufferBinding>)b;
        if ([b.name isEqualToString:@"vertex_buffers"]) p->idx_vb = (int)b.index;
        else if ([b.name isEqualToString:@"banc"]) p->idx_banc = (int)b.index;
        else if ([b.name isEqualToString:@"bancd"]) p->idx_bancd = (int)b.index;
        else if ([b.name isEqualToString:@"binding_table"]) {
            p->idx_args = (int)b.index;
            p->table_args = table_arguments(r, bb, p->residents, NO);
        } else if ([b.name isEqualToString:@"cbuffer_table"]) {
            p->idx_cb = (int)b.index;
            p->table_cb = table_arguments(r, bb, p->residents, YES);
        } else { *err = [NSString stringWithFormat:@"liaison inconnue %@", b.name]; return NO; }
    }
    if (p->idx_vb >= 0) for (int i = 0; i < NB_VDATA; i++) [p->residents addObject:r->vdata[i]];
    return YES;
}

static int cmp_double(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
static double mediane(double *v, int n) {
    if (n <= 0) return 0;
    qsort(v, n, sizeof(double), cmp_double);
    return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}


static void encoder_passe(id<MTLCommandBuffer> cb, id<MTLCounterSampleBuffer> ech, int k,
                          Pipeline *p, Ressources *r, Maillage *m, int rejet) {
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor new];
    if (!sans_fragment) {
        rp.colorAttachments[0].texture = cible;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionDontCare;
    }
    rp.depthAttachment.texture = profondeur;
    rp.depthAttachment.loadAction = MTLLoadActionClear;
    rp.depthAttachment.clearDepth = 1.0;
    rp.depthAttachment.storeAction = MTLStoreActionDontCare;
    rp.sampleBufferAttachments[0].sampleBuffer = ech;
    rp.sampleBufferAttachments[0].startOfVertexSampleIndex = 4 * k;
    rp.sampleBufferAttachments[0].endOfVertexSampleIndex = 4 * k + 1;
    rp.sampleBufferAttachments[0].startOfFragmentSampleIndex = 4 * k + 2;
    rp.sampleBufferAttachments[0].endOfFragmentSampleIndex = 4 * k + 3;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:p->etat];
    [enc setDepthStencilState:etat_profondeur];
    [enc setFrontFacingWinding:MTLWindingClockwise];
    [enc setCullMode:MTLCullModeBack];
    if (p->idx_vb >= 0) [enc setVertexBuffer:r->table_vb offset:0 atIndex:p->idx_vb];
    if (p->idx_args >= 0) [enc setVertexBuffer:p->table_args offset:0 atIndex:p->idx_args];
    if (p->idx_cb >= 0) [enc setVertexBuffer:p->table_cb offset:0 atIndex:p->idx_cb];
    if (p->idx_banc >= 0) [enc setVertexBuffer:m->banc offset:0 atIndex:p->idx_banc];
    if (p->idx_bancd >= 0) [enc setVertexBuffer:r->bancd offset:0 atIndex:p->idx_bancd];
    for (id<MTLResource> x in p->residents)
        [enc useResource:x usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
    int acc = 0;
    for (int d = 0; d < m->c.dessins; d++) {
        acc += rejet;
        BOOL dos = acc >= 100;
        if (dos) acc -= 100;
        if (m->c.indexe) {
            [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:m->c.indices_par_dessin
                indexType:MTLIndexTypeUInt32 indexBuffer:dos ? m->index_dos : m->index_face indexBufferOffset:0
                instanceCount:1 baseVertex:(NSInteger)d * m->c.sommets_par_dessin baseInstance:0];
        } else {
            // sans index : le rejet par orientation n'est pas simule
            [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:(NSUInteger)d * m->c.sommets_par_dessin
                vertexCount:m->c.sommets_par_dessin];
        }
    }
    [enc endEncoding];
}

// Mode par defaut (isole) : une passe par tampon de commandes, tous encodes
// d'avance puis soumis l'un apres l'autre en attendant la fin de chacun. Rien
// d'autre ne tourne sur le GPU : l'intervalle debut-fin de l'etage sommets est
// son travail propre (shading + tiler), celui de l'etage fragments aussi.
// Mode --enchaine : toutes les passes dans un seul tampon ; les etages sommets
// de passes consecutives se chevauchent et les fragments d'une passe tournent
// pendant les sommets de la suivante, on rapporte alors la periode en regime
// etabli (ecart entre fins d'etage sommets), qui melange les deux etages.
// partiel : une passe a commence ses fragments avant la fin de ses sommets,
// signe d'un rendu partiel (tampon de parametres du tiler sature) ; la mesure
// ne vaut alors rien, Metal agrandit le tampon et il faut recommencer.
typedef struct { double vertex_us, fragment_us, total_us; BOOL ok, partiel; } Mesure;

static Mesure mesurer(Pipeline *p, Ressources *r, Maillage *m, int chauffe, int passes, int rejet) {
    Mesure res = {0, 0, 0, NO, NO};
    int n = chauffe + passes;
    MTLCounterSampleBufferDescriptor *sd = [MTLCounterSampleBufferDescriptor new];
    sd.counterSet = horodatage;
    sd.storageMode = MTLStorageModeShared;
    sd.sampleCount = 4 * n;
    NSError *e = nil;
    id<MTLCounterSampleBuffer> ech = [dev newCounterSampleBufferWithDescriptor:sd error:&e];
    if (!ech) { fprintf(stderr, "tampon d'echantillons : %s\n", e.localizedDescription.UTF8String); return res; }
    double total = 0;
    if (enchaine) {
        id<MTLCommandBuffer> cb = [file commandBuffer];
        for (int k = 0; k < n; k++) encoder_passe(cb, ech, k, p, r, m, rejet);
        [cb commit];
        [cb waitUntilCompleted];
        if (cb.status != MTLCommandBufferStatusCompleted) {
            fprintf(stderr, "tampon de commandes en erreur : %s\n", cb.error.localizedDescription.UTF8String);
            return res;
        }
        total = (cb.GPUEndTime - cb.GPUStartTime) * 1e6 / n;
    } else {
        NSMutableArray<id<MTLCommandBuffer>> *cbs = [NSMutableArray new];
        for (int k = 0; k < n; k++) {
            id<MTLCommandBuffer> cb = [file commandBuffer];
            encoder_passe(cb, ech, k, p, r, m, rejet);
            [cbs addObject:cb];
        }
        for (int k = 0; k < n; k++) {
            [cbs[k] commit];
            [cbs[k] waitUntilCompleted];
            if (cbs[k].status != MTLCommandBufferStatusCompleted) {
                fprintf(stderr, "tampon de commandes en erreur : %s\n", cbs[k].error.localizedDescription.UTF8String);
                return res;
            }
            if (k >= chauffe) total += (cbs[k].GPUEndTime - cbs[k].GPUStartTime) * 1e6 / passes;
        }
    }
    NSData *data = [ech resolveCounterRange:NSMakeRange(0, 4 * n)];
    if (!data) return res;
    const MTLCounterResultTimestamp *t = data.bytes;
    if (getenv("BANC_TRACE")) {
        for (int k = 0; k < n; k++)
            fprintf(stderr, "  passe %d : sommets %8.1f -> %8.1f  fragments %8.1f -> %8.1f us\n", k,
                (t[4 * k].timestamp - t[0].timestamp) / 1e3, (t[4 * k + 1].timestamp - t[0].timestamp) / 1e3,
                (t[4 * k + 2].timestamp - t[0].timestamp) / 1e3, (t[4 * k + 3].timestamp - t[0].timestamp) / 1e3);
    }
    double v[64], f[64];
    int nb = 0;
    for (int k = 0; k < 4 * n; k++)
        if (t[k].timestamp == MTLCounterErrorValue) return res;
    for (int k = chauffe; k < n && nb < 64; k++) {
        v[nb] = (double)(t[4 * k + 1].timestamp - t[4 * k].timestamp) / 1000.0;
        f[nb] = (double)(t[4 * k + 3].timestamp - t[4 * k + 2].timestamp) / 1000.0;
        if (t[4 * k + 2].timestamp < t[4 * k + 1].timestamp) res.partiel = YES;
        nb++;
    }
    res.fragment_us = mediane(f, nb);
    res.vertex_us = enchaine
        ? (double)(t[4 * (n - 1) + 1].timestamp - t[4 * (chauffe - 1) + 1].timestamp) / 1000.0 / passes
        : mediane(v, nb);
    res.total_us = total;
    res.ok = YES;
    return res;
}

static void usage(void) {
    fprintf(stderr,
        "usage : banc_vs_reels_metal manifeste.tsv [options]\n"
        "  --configs LISTE       nom:quadsX:quadsY:indexe, separes par des virgules\n"
        "                        (defaut p50:8:9:1,p90:74:74:1 = 432 et 32 856 index par dessin)\n"
        "  --indices-par-passe N (defaut 4200000)\n"
        "  --pas PX              cote d'un quad a l'ecran (defaut 3)\n"
        "  --remplissages LISTE  mot de 32 bits repete dans toutes les donnees (defaut 0,1)\n"
        "  --rejets LISTE        pourcentages de dessins vus de dos, donc rejetes (defaut 50)\n"
        "  --tours N (5)  --passes N (4)  --chauffe N (1, au moins 1)\n"
        "  --fragment-de V       fragment shader de la variante V pour toutes (b : il ne lit aucun\n"
        "                        varying ; Metal elague-t-il les sorties que le fragment ignore ?)\n"
        "  --sans-fragment       profondeur seule, sans fonction de fragment (passe d'ombres)\n"
        "  --enchaine            toutes les passes dans un seul tampon de commandes (periode en\n"
        "                        regime etabli, etages sommets et fragments en concurrence)\n"
        "  --masque MOT          mot de masque du puits (defaut 0 ; non nul = controle : le puits\n"
        "                        modifie alors la position, la geometrie change)\n"
        "  --seulement MOTIF     ne garder que les shaders dont le nom contient MOTIF\n"
        "  --sortie FICHIER      TSV des mesures (defaut : sortie standard)\n");
    exit(2);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) usage();
        NSString *manifeste = @(argv[1]), *configs = @"p50:8:9:1,p90:74:74:1", *rempl = @"0,1", *rejets = @"50";
        NSString *seulement = nil, *sortie = nil, *fragment_de = nil;
        long indices_par_passe = 4200000;
        double pas = 3;
        int tours = 5, passes = 4, chauffe = 1;
        uint32_t masque = 0;
        for (int i = 2; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqualToString:@"--enchaine"]) { enchaine = YES; continue; }
            if ([a isEqualToString:@"--sans-fragment"]) { sans_fragment = YES; continue; }
            if (i + 1 >= argc) usage();
            NSString *v = @(argv[++i]);
            if ([a isEqualToString:@"--configs"]) configs = v;
            else if ([a isEqualToString:@"--indices-par-passe"]) indices_par_passe = v.longLongValue;
            else if ([a isEqualToString:@"--pas"]) pas = v.doubleValue;
            else if ([a isEqualToString:@"--remplissages"]) rempl = v;
            else if ([a isEqualToString:@"--rejets"]) rejets = v;
            else if ([a isEqualToString:@"--tours"]) tours = v.intValue;
            else if ([a isEqualToString:@"--passes"]) passes = v.intValue;
            else if ([a isEqualToString:@"--chauffe"]) chauffe = v.intValue;
            else if ([a isEqualToString:@"--masque"]) masque = (uint32_t)strtoul(v.UTF8String, NULL, 0);
            else if ([a isEqualToString:@"--fragment-de"]) fragment_de = v;
            else if ([a isEqualToString:@"--seulement"]) seulement = v;
            else if ([a isEqualToString:@"--sortie"]) sortie = v;
            else usage();
        }
        if (tours > 31) tours = 31;
        if (chauffe < 1) chauffe = 1;
        if (passes < 1) passes = 1;
        if (chauffe + passes > 64) passes = 64 - chauffe;
        dev = MTLCreateSystemDefaultDevice();
        file = [dev newCommandQueue];
        for (id<MTLCounterSet> s in dev.counterSets)
            if ([s.name isEqualToString:MTLCommonCounterSetTimestamp]) horodatage = s;
        if (!horodatage || ![dev supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary]) {
            fprintf(stderr, "horodatage de frontiere d'etage indisponible sur %s\n", dev.name.UTF8String);
            return 1;
        }
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:LARGEUR height:HAUTEUR mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget;
        td.storageMode = MTLStorageModePrivate;
        cible = [dev newTextureWithDescriptor:td];
        td.pixelFormat = MTLPixelFormatDepth32Float;
        profondeur = [dev newTextureWithDescriptor:td];
        MTLDepthStencilDescriptor *dd = [MTLDepthStencilDescriptor new];
        dd.depthCompareFunction = MTLCompareFunctionLessEqual;
        dd.depthWriteEnabled = YES;
        etat_profondeur = [dev newDepthStencilStateWithDescriptor:dd];
        fragments = [NSMutableDictionary new];

        Maillage maillages[MAX_CONFIGS];
        int nconf = 0;
        size_t sommets_max = 0;
        for (NSString *c in [configs componentsSeparatedByString:@","]) {
            NSArray<NSString *> *f = [c componentsSeparatedByString:@":"];
            if (f.count != 4 || nconf == MAX_CONFIGS) usage();
            Config cf;
            memset(&cf, 0, sizeof cf);
            strlcpy(cf.nom, f[0].UTF8String, sizeof cf.nom);
            cf.qw = f[1].intValue; cf.qh = f[2].intValue; cf.indexe = f[3].intValue; cf.pas_px = pas;
            maillages[nconf] = construire_maillage(cf, indices_par_passe);
            *(uint32_t *)maillages[nconf].banc.contents = masque;
            size_t nv = (size_t)maillages[nconf].c.dessins * maillages[nconf].c.sommets_par_dessin;
            if (nv > sommets_max) sommets_max = nv;
            nconf++;
        }
        NSArray<NSString *> *lr = [rempl componentsSeparatedByString:@","], *lj = [rejets componentsSeparatedByString:@","];

        NSString *texte = [NSString stringWithContentsOfFile:manifeste encoding:NSUTF8StringEncoding error:nil];
        if (!texte) { fprintf(stderr, "manifeste illisible : %s\n", argv[1]); return 1; }
        NSMutableArray<NSArray<NSString *> *> *lignes = [NSMutableArray new];
        for (NSString *l in [texte componentsSeparatedByString:@"\n"]) {
            NSArray<NSString *> *f = [l componentsSeparatedByString:@"\t"];
            if (f.count < 9 || [f[0] isEqualToString:@"nom"]) continue;
            if (seulement && [f[0] rangeOfString:seulement].location == NSNotFound) continue;
            [lignes addObject:f];
        }
        FILE *out = sortie ? fopen(sortie.UTF8String, "w") : stdout;
        if (!out) { perror("sortie"); return 1; }
        fprintf(out, "nom\tclasse\tvaryings\tvariante\tinstr\tconfig\tremplissage\trejet\tdessins\tsommets\tindices\t"
                     "vertex_us\tvertex_min_us\tvertex_max_us\tfragment_us\ttotal_us\t"
                     "us_par_Msommets\tus_par_Mindices\tpartiels\n");
        fprintf(stderr, "%s ; %d configurations ; %lu lignes de manifeste\n", dev.name.UTF8String, nconf, (unsigned long)lignes.count);
        for (int ir = 0; ir < (int)lr.count; ir++) {
            @autoreleasepool {
                uint32_t motif = (uint32_t)strtoul(lr[ir].UTF8String, NULL, 0);
                Ressources res = construire_ressources(motif, sommets_max);
                NSUInteger i = 0;
                while (i < lignes.count) {
                    @autoreleasepool {
                        NSUInteger j = i;
                        while (j < lignes.count && [lignes[j][0] isEqualToString:lignes[i][0]]) j++;
                        int nv = (int)(j - i);
                        if (nv > MAX_VARIANTES) nv = MAX_VARIANTES;
                        Pipeline pipes[MAX_VARIANTES];
                        BOOL bon[MAX_VARIANTES];
                        NSString *frag_impose = nil;
                        for (int k = 0; k < nv && fragment_de; k++)
                            if ([lignes[i + k][3] isEqualToString:fragment_de]) frag_impose = lignes[i + k][5];
                        for (int k = 0; k < nv; k++) {
                            NSString *err = nil;
                            bon[k] = construire_pipeline(&pipes[k], &res, lignes[i + k][4],
                                                         frag_impose ? frag_impose : lignes[i + k][5], &err);
                            if (!bon[k])
                                fprintf(stderr, "%s.%s : %s\n", lignes[i][0].UTF8String, lignes[i + k][3].UTF8String, err.UTF8String);
                        }
                        for (NSString *rj in lj)
                            for (int c = 0; c < nconf; c++) {
                                static double v[MAX_VARIANTES][32], f[MAX_VARIANTES][32], tt[MAX_VARIANTES][32];
                                int n[MAX_VARIANTES] = {0}, partiels[MAX_VARIANTES] = {0};
                                // tour -1 : mise en route (premiere utilisation du pipeline, tampon de
                                // parametres du tiler a sa taille), repetee tant qu'un rendu partiel apparait
                                for (int t = -1; t < tours; t++)
                                    for (int k = 0; k < nv; k++) {
                                        if (!bon[k]) continue;
                                        for (int essai = 0; essai < 6; essai++) {
                                            @autoreleasepool {
                                                Mesure m = mesurer(&pipes[k], &res, &maillages[c], chauffe, passes, rj.intValue);
                                                if (!m.ok) { bon[k] = NO; break; }
                                                if (m.partiel && essai < 5) continue;
                                                if (t < 0) break;
                                                partiels[k] += m.partiel;
                                                v[k][n[k]] = m.vertex_us; f[k][n[k]] = m.fragment_us; tt[k][n[k]] = m.total_us;
                                                n[k]++;
                                                break;
                                            }
                                        }
                                    }
                                Config *cf = &maillages[c].c;
                                for (int k = 0; k < nv; k++) {
                                    if (!n[k]) continue;
                                    double vm = mediane(v[k], n[k]), vmin = v[k][0];
                                    double sommets = (double)cf->dessins * cf->sommets_par_dessin;
                                    double indices = (double)cf->dessins * cf->indices_par_dessin;
                                    NSArray<NSString *> *l = lignes[i + k];
                                    fprintf(out, "%s\t%s\t%s\t%s\t%s\t%s\t%u\t%d\t%d\t%.0f\t%.0f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%d\n",
                                        l[0].UTF8String, l[1].UTF8String, l[2].UTF8String, l[3].UTF8String, l[6].UTF8String,
                                        cf->nom, motif, rj.intValue, cf->dessins, sommets, indices, vm, vmin, v[k][n[k] - 1],
                                        mediane(f[k], n[k]), mediane(tt[k], n[k]),
                                        vm / sommets * 1e6, vm / indices * 1e6, partiels[k]);
                                }
                                fflush(out);
                            }
                        i = j;
                    }
                }
            }
        }
        if (out != stdout) fclose(out);
    }
    return 0;
}
