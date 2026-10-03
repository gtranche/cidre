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

## Résultat honnête de l'opt n°1 (2026-10-03 nuit) : NON concluant

- Banc multi-textures écrit (`bench_frag_multi.c`, NTEX=1..64) pour isoler le
  coût des descripteurs. **Avant ≈ après** (0,077-0,108 ms, bruit), et **plat**
  de 1 à 64 textures. Donc l'opt n°1 est **inerte** sur ce workload.
- **Le banc lui-même est invalide** : 0,077 ms / 40 passes / 1080p / 64 samples
  = ~67 Tsamples/s, impossible → les samples sont **éliminés** (texture non
  initialisée, travail non forcé). Il faut forcer le travail (texture remplie,
  sortie dépendante de tous les samples, dépendance de chaîne) pour un vrai banc.
- **Bilan :** l'hypothèse « les loads de descripteur sont le goulot » n'est ni
  confirmée ni infirmée. Patch 0078 **parqué** (`.parked`, hors série), driver
  remis au connu-bon.

## La vraie prochaine étape

Localiser où partent les ~45 ms/frame de VT2 au niveau GPU, par une **capture de
frame Metal** (Xcode GPU trace via `MTL_CAPTURE_ENABLED=1` + MTLCaptureManager,
ou le HUD Metal détaillé), sur un run VT2 stable. Sans ça, on optimise à l'aveugle.
Alternative : un banc qui reproduit fidèlement le motif bindless de NOTES §137
(114 samplings, MSL à la main) et FORCE le travail GPU.

## Profilage GPU (2026-10-03, stats intégrées) : LE vrai levier = les barrières

Variable corrigée : **`MESA_KK_DEBUG`** (pas KK_DEBUG). Flags utiles :
`barrier_stats,pass_stats,draw_stats`. Mesuré sur DREDGE (fiable) et VT2 (resté au
menu, VT2 injouable en auto) :
- **~1 barrière par render pass, ~0 % élidées** (DREDGE 0,3 %, VT2 0,0 %).
- Chaque barrière = **`mtl_barrier_after_stages(MTL_STAGE_ALL, MTL_STAGE_ALL)`**,
  le flush le plus lourd (sérialisation totale du GPU entre passes).
- gâchis pixels = 1,00x, passes partielles 0 % → PAS un problème de pixels gâchés.

**Cause confirmée par le code lui-même** (`kk_cmd_buffer.c` ~l.744,
`kk_CmdPipelineBarrier2`) :
> TODO_KOSMICKRISP Lighten barriers according to the actual requested barrier.
> To take advantage of this we need to remove the chaining of encoders.

Donc KosmicKrisp ignore les stage/access masks précis du jeu et pose un barrier
ALL→ALL par barrier Vulkan. Pour un moteur à N passes/frame, c'est N
sérialisations complètes → GPU 100 % mais débit bas, insensible aux réglages.
**C'est le candidat n°1 pour VT2**, bien mieux étayé que l'opt descripteurs (parquée).

**Chantier (non trivial, architectural) :** alléger les barrières selon le barrier
Vulkan réel (stages/access précis), ce qui demande de **découpler le chaînage
d'encodeurs** (dit par le TODO). Gain attendu : overlap des passes.

**Reste à quantifier sur VT2 EN JEU** (pas le menu) : passes/frame réelles. Blocage
actuel = VT2 ne se lance pas de façon fiable en auto. Voie : capture collaborative
(l'utilisateur amène VT2 au Donjon, on lit les stats MESA_KK_DEBUG + le HUD).

## QUANTIFIÉ en jeu (2026-10-03) : VT2 Forteresse, HUD DXVK + Metal

| Par frame | Valeur |
| --- | --- |
| FPS | 24,3 |
| Temps GPU/frame | 40,8 ms (GPU 100 %) |
| Render passes | **115** |
| Barrières | **262** (chacune ALL→ALL, ~0 % élidée) |
| Draw calls | 1792 (~0,9 ms CPU, négligeable) |
| Pipelines liés | 461 |

262 flushs GPU complets par frame = ~6300/s à 24 fps. Le GPU est à 100 % mais
passe l'essentiel de ses 40 ms à drainer/recharger le pipeline entre passes, pas
à calculer. **Diagnostic confirmé et chiffré : VT2 est barrier/encodeur-bound.**
Comparaison DREDGE (69-84 fps) : bien moins de passes/frame.

=> Le chantier est validé : **alléger les 262 barrières ALL→ALL** vers les stages/
access réellement demandés par le jeu (TODO KosmicKrisp), en découplant le
chaînage d'encodeurs. C'est LE gisement fps pour VT2 et tout moteur à passes
multiples.

## Cibles d'implémentation précises (kk_cmd_buffer.c)

`kk_CmdPipelineBarrier2` + `kk_barrier_requires_encoder_split` — trois sur-
conservatismes, du plus sûr au plus risqué à corriger :

1. **Split par ressource (le gros gain, risque moyen).** `write_available` est un
   booléen collant global : une fois une écriture faite dans la passe, toute
   lecture-texture ultérieure force `cs_end`+`cs_start_render` (store+reload des
   attachements = aller-retour tile↔DRAM). Les images sont nommées dans
   `dep->pImageMemoryBarriers[i].image` → ne splitter que si l'image LUE a bien
   été ÉCRITE dans CETTE passe (suivi par ensemble d'images, ajouté à
   kk_rendering_state). Défaut = splitter (sûr) si incertain.
2. **Barrière de fermeture ALL→ALL (cas render_closing).** Stocker les stages dst
   réels du dependency et émettre une barrière étroite au lieu de MTL_STAGE_ALL→
   MTL_STAGE_ALL. ATTENTION : le TODO dit que ça demande de découpler le chaînage
   d'encodeurs — à comprendre avant de toucher.
3. **MSAA split systématique** (`samples > 1`) : vérifier si on peut l'éviter hors
   vrai hazard résolve.

**Méthode obligatoire (hazard GPU = correction critique) :** une touche à la fois,
rebuild (wrapper arm64), puis TEST CORRECTION sur DREDGE + VT2 (pas d'artefact, pas
de crash, visuel identique) AVANT de mesurer le gain. Un split/barrière retiré à
tort = corruption GPU parfois intermittente. Oracle perf : HUD DXVK barriers +
MTL_HUD GPU-ms, et MESA_KK_DEBUG=barrier_stats,pass_stats pour passes/splits/frame.

## Expérience jetable (splits OFF) : pas de raccourci

Désactiver TOUS les splits (`kk_barrier_requires_encoder_split → false`) + rebuild :
**DREDGE affiche un écran blanc** (rendu cassé, le GPU lit des attachements non
flushés). => Les splits sont fonctionnellement nécessaires ; impossible de mesurer
le « plafond barrières » en les supprimant (le rendu cassé n'est pas une mesure
valide). Driver remis au connu-bon.

**Conclusion :** le gain ne s'obtient QUE par le travail par-ressource (cible n°1 :
ne splitter que si l'image lue a été écrite dans la passe). C'est de l'ingénierie
de hazard GPU à faire avec soin et tests de correction, pas un raccourci. Le
diagnostic (262 barrières ALL→ALL + splits / frame, GPU-bound) reste la base solide.

## Tentative split par-ressource (version naïve) : ÉCHEC correction, leçon précise

Implémenté : ne splitter que si l'image lue est un **attachement courant**. Rebuild,
test DREDGE → **écran blanc** (rendu cassé). Reverté, driver au connu-bon.

**Pourquoi c'est faux (capital) :** KosmicKrisp **chaîne plusieurs sous-passes dans
un même encodeur Metal**. Une image écrite dans une sous-passe PRÉCÉDENTE du même
encodeur n'est plus dans `render->color_att` (les attachements courants) quand une
sous-passe ultérieure l'échantillonne — mais le hazard de mémoire tuilée existe
toujours. Le `write_available` collant d'origine attrapait ces hazards inter-sous-
passes ; ma vérif « attachement courant » les ratait → split nécessaire sauté →
corruption. C'est EXACTEMENT ce que dit le TODO (« remove the chaining of encoders »).

**La version correcte** doit suivre un **ensemble d'images ÉCRITES à l'échelle de
l'encodeur** (accumulé sur toutes les sous-passes chaînées, vidé quand l'encodeur
Metal se termine vraiment), et splitter si la lecture vise une image de cet ensemble.
Plus lourd (hooks sur les écritures/attachements + début/fin d'encodeur réel), mais
c'est le bon modèle. Le test de correction DREDGE (écran blanc = instantané) est un
bon garde-fou rapide à chaque itération.

## CORRECTION (soir, suite) : le « split naïf casse le rendu » était un FAUX diagnostic

Réimplémenté proprement : suivi des images ÉCRITES à l'échelle de l'encodeur
(src des barriers), split si une image LUE y figure, repli prudent. Puis version
DIAGNOSTIC (toujours split + log) : **KK_SKIP = 0 pour DREDGE** → mon optimisation
ne change RIEN au comportement de DREDGE. Or l'écran restait blanc même en
diagnostic (= comportement original). Donc **l'écran blanc n'était PAS la logique
de split** : c'était l'environnement (DREDGE met maintenant ~150 s à rendre contre
60 s plus tôt ; captures prématurées ; fenêtres non-capturables en fin de session).
=> Les conclusions « ma modif casse le rendu » étaient prématurées.

**Statut réel :** l'approche « ensemble d'images écrites par encodeur » est le bon
modèle et est behavioralement NEUTRE pour DREDGE (ne saute aucun split là-bas).
Reste NON validée : il faut un environnement de test fiable + VT2 en jeu (où
l'opti pourrait réellement sauter des splits inter-ressources). Driver remis au
connu-bon ; code de l'opti non conservé en patch (à ré-implémenter proprement au
prochain passage, l'approche est décrite ci-dessus).

**Leçon environnement :** après de longues sessions, le démarrage des jeux et la
capture d'écran deviennent peu fiables (processus résiduels, pression mémoire).
Valider le chantier barrières sur une machine fraîche, DREDGE ET VT2, avec le HUD
Metal + MESA_KK_DEBUG, pas en fin de marathon.
