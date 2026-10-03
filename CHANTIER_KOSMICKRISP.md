# Chantier KosmicKrisp : le coût bindless (fps GPU-bound, ex. Vermintide 2)

## Diagnostic (mesuré, 2026-10-03, M1 Max)

- **VT2 est GPU-bound** : 22 fps à GPU 100 %, frametime plat, déjà en rendu 720p
  interne. Baisser la qualité (volumétrique, ombres, textures high→low) ne gagne
  que +6 % (22→23 fps). Donc le coût n'est PAS les effets ni le fillrate.
- **DREDGE, lui, était présentation/CPU-bound** : vsync-off + TSO-off = 40→84 fps.
  VT2 ne répond ni à la vsync, ni au TSO, ni à la résolution (tous mesurés nuls).
- Coût CPU par draw call : **0,506 µs** (bench_draw_cost, KosmicKrisp arm64) →
  le CPU n'est pas le goulot.
- **Cause : le modèle bindless.** `bench_frag` (NOTES §137) : le motif bindless
  coûte +138,6 % à 114 échantillonnages, croissance **surlinéaire** = pression
  de registres. Le shader réel fait ~7,8 chargements de descripteur par sample.

## Localisation exacte

- `src/mesa/src/kosmickrisp/vulkan/kk_nir_lower_descriptors.c`, `lower_tex`
  (~l.700-920) : pour CHAQUE `nir_tex_instr`, charge séparément lod_bias,
  sampler_index, swizzle, border, sampler_flags, handle... du
  `struct kk_sampled_image_descriptor` (64 octets, champs contigus) via
  `nir_load_global_constant_offset` (même base, offsets différents).
- `msl_optimize_nir` (`compiler/nir_to_msl.c`) lance déjà `nir_opt_cse` ET
  `nir_opt_licm` : les loads IDENTIQUES sont donc déjà factorisés. Le coût
  restant = N champs distincts chargés en N loads étroits + pression de registres.
- **Trou trouvé : `nir_opt_load_store_vectorize` n'était PAS lancé.** Les loads
  adjacents d'un même descripteur (offsets 8-23, 16 octets contigus) ne sont
  jamais fusionnés.

## Optimisation n°1 (codée, à valider)

Ajout de `nir_opt_load_store_vectorize` (modes global|constant) + callback
`kk_mem_vectorize_cb` dans `msl_optimize_nir`, sur le modèle du driver Asahi
(GPU Apple). But : fusionner les ~8 loads étroits par sample en 1-3 loads larges
→ moins de transactions mémoire, moins de pression de registres.
Fichier : `src/mesa/src/kosmickrisp/compiler/nir_to_msl.c`.

## Mesure (reproductible, headless)

- `bench_frag` (bindless vs texture liée) = l'oracle du coût bindless, sans
  lancer de jeu. Mesurer avant/après la modif.
- Valider ensuite sur VT2 (GPU-ms via HUD Metal `MTL_HUD_ENABLED=1` + DXVK
  drawcalls, capture par id de fenêtre, cf. `CIDRE_HUD=1`).

## Bloqueur build (à régler avant de mesurer)

Un `ninja -C build/mesa` nu échoue sur `src/util/blake3/blake3_neon.c`
(« NEON intrinsics not available with the soft-float ABI ») : Mesa compile le
chemin NEON ARMv7 sur arm64. Défaut de config du checkout Mesa, INDÉPENDANT de
la modif (`cc` compile NEON correctement en isolation). À régler : exclure
blake3_neon sur arm64 (ou -Dmesa option), puis `ninja -C build/mesa && install`.

## Pistes suivantes (si la vectorisation ne suffit pas)

1. Réduire le NOMBRE de champs chargés par sample (ex. sauter lod_bias quand nul).
2. Rendre les intrinsics de handle (`nir_load_texture_handle_kk`) factorisables
   entre samples partageant une texture.
3. Argument buffers Metal natifs / ResourceID plutôt que reconstruction manuelle.

## Statut 2026-10-03 (soir)

- **Build débloqué** (ninja x86_64/Rosetta → wrapper `cc -arch arm64` + clean).
  Driver optimisé (patch 0078) **compilé et installé**, `nir_to_msl.c` OK.
- **Validation NON concluante ce jour** : (a) VT2 a planté sur un deadlock de
  chargement (fragile, souci intermittent connu, non attribuable à la modif) ;
  (b) `bench_frag` est mono-texture → le LICM amortit, ne montre pas l'effet ;
  (c) KK_DEBUG=msl/nir n'a rien sorti via le bench.
- **Prochaine étape = l'oracle manquant** : écrire un micro-banc fragment
  **multi-textures** (16+ samplers distincts, le cas que la modif cible) pour
  mesurer avant/après de façon reproductible, SANS dépendre de VT2.
- Le driver optimisé est actuellement installé (non validé). Rebuild sans 0078
  pour revenir au connu-bon si besoin.
