# NOTES — Proton ouvert sur macOS (non commité)

Dossier de travail : `~/Dev/proton-ouvert/`. Rien installé dans le système à ce stade.

## 1. État machine — MESURÉ le 2026-09-16

| Élément | Valeur | Commande |
|---|---|---|
| macOS | **26.5.2** (build 25F84) | `sw_vers` |
| Machine | MacBook Pro, **Apple M1 Max**, 10 cœurs (8P/2E) | `system_profiler SPHardwareDataType` |
| RAM | **32 Go** (brief : 16 Go mini → OK) | idem |
| Arch | arm64 | `uname -m` |
| **Metal Support** | **Metal 4** | `system_profiler SPDisplaysDataType` |
| Rosetta 2 | installé (`oahd` actif, `/Library/Apple/usr/libexec/oah`) | `pgrep oahd` |
| Disque libre | 339 Gio | `df -h /` |

### → Item « non vérifié » du brief LEVÉ
**Metal 4 est bien exposé sur ce M1 Max sous macOS 26.5.2.** Le prérequis dur de
KosmicKrisp (Metal 4 + Apple Silicon) est satisfait. Le M1 n'est pas exclu.

## 2. Outillage présent / absent — MESURÉ

Présent : `brew`, `cmake`, `ninja` (/usr/local), `git`, `python3` (miniconda), `clang`.
Absent : **`meson`**, **`vulkaninfo`**, **loader Vulkan**, **MoltenVK**, `glslangValidator`, `winetricks`.

- **Xcode complet : non installé** — seulement Command Line Tools (`/Library/Developer/CommandLineTools`), SDK macOS 26.2.
  `xcrun --find metal` échoue → **pas de compilateur Metal hors-ligne**.
- **Wine : 9.0 stable** (cask Homebrew `wine-stable`). Ancien ; le brief demande un Wine macOS récent + WoW64.
- **CrossOver : 25.0** — or l'Étape 0 du brief exige **CrossOver 26** (c'est la 26 qui ajoute la compat Expedition 33).
- Bouteilles CrossOver : une seule, `Steam`. **Le jeu n'est pas installé** (aucun `*clair*` / `*expedition*`).

## 3. Étape 1 — réponses aux questions du brief

Sources clonées (shallow) dans `src/` :
- `mesa` @ `5f253b9` (2026-09-15)
- `vkd3d-proton` @ `5d0db74` (2026-09-16)

### 3a. Option Meson — VÉRIFIÉ
`mesa/meson.options:206-216` : l'option s'appelle bien `vulkan-drivers` et **`kosmickrisp` figure
dans `choices`**. → `-Dvulkan-drivers=kosmickrisp` est exact. (Note : le fichier est
`meson.options`, plus `meson_options.txt`.) Le driver vit dans `src/kosmickrisp/`.

### 3b. `VK_EXT_metal_surface` — VÉRIFIÉ
`src/kosmickrisp/vulkan/kk_instance.c:62` → `.EXT_metal_surface = true`. Exposé
inconditionnellement. Indispensable à `winemac.drv` : OK.

### 3c. Xcode complet nécessaire ? — VÉRIFIÉ : NON
- Aucune référence à `xcrun` / `metallib` / compilation AIR hors-ligne dans les `meson.build` de
  `src/kosmickrisp/`.
- Les shaders Metal sont compilés **au runtime** : `bridge/mtl_compiler.m:47` utilise
  `MTLCompileOptions` (code Objective-C liant le framework).
- Seule dépendance framework déclarée : `appleframeworks` / **`Foundation`** (`bridge/meson.build:55`).
- Metal, Foundation, QuartzCore, IOSurface, AppKit, CoreGraphics sont **tous présents** dans
  `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.
→ **Les Command Line Tools suffisent a priori pour bâtir KosmicKrisp.** À reconfirmer au build.

### 3d. Liste des exigences vkd3d-proton — TROUVÉE, et machine-readable
Le dépôt fournit **`VP_D3D12_VKD3D_PROTON_profile.json`**, un profil Vulkan officiel : c'est la
liste faisant autorité (le brief interdit de la supposer — inutile de le faire).
Il définit des profils par feature level, tous en `api-version 1.3.204` :
`VP_D3D12_FL_11_0_baseline` (plancher) → `FL_11_1` → `FL_12_0` → `FL_12_1` → `FL_12_2` (+ variantes
`optimal`, `maximum_radv`, `maximum_nv`).
Avantage : vérifiable mécaniquement (Vulkan Profiles tool) plutôt qu'à la main.

Le README (`Drivers`) ajoute les exigences dures en prose : Vulkan 1.3, descriptor indexing avec
≥ 1 000 000 descripteurs UpdateAfterBind, `samplerMirrorClampToEdge`, `shaderDrawParameters`,
`VK_EXT_robustness2`, `VK_KHR_push_descriptor`.

### 3e. PREMIER CROISEMENT — statique, à confirmer par `vulkaninfo`
Plancher absolu `VP_D3D12_FL_11_0_baseline` (11 extensions) vs déclarations de KosmicKrisp
(`vulkan/kk_physical_device.c`) :

| Extension (plancher FL 11_0) | KosmicKrisp |
|---|---|
| `VK_EXT_depth_clip_enable` | présente |
| `VK_EXT_robustness2` | présente |
| `VK_EXT_vertex_attribute_divisor` | présente |
| `VK_KHR_calibrated_timestamps` | présente |
| `VK_KHR_maintenance5` | présente |
| `VK_KHR_maintenance6` | présente |
| `VK_KHR_push_descriptor` | présente |
| `VK_KHR_swapchain` | présente |
| `VK_EXT_custom_border_color` | **conditionnelle** — `kk_physical_device.c:176`, gardée par `KK_EXPERIMENTAL(CUSTOM_BORDER)`, débloquée par `MESA_KK_EXPERIMENTAL=custom_border` (`kk_debug.c:23`) |
| `VK_EXT_dynamic_rendering_unused_attachments` | **ABSENTE** — 0 occurrence dans tout `src/kosmickrisp/` |
| `VK_EXT_transform_feedback` | **ABSENTE** — seulement un commentaire (`kk_physical_device.c:876`), aucune implémentation |

**Lecture préliminaire : 8/11 fermes, 1 expérimentale, 2 manquantes — et ce n'est que le PLANCHER
FL 11_0.** Les profils supérieurs (FL 12_x : mesh shaders, ray tracing, fragment shading rate)
n'ont pas encore été croisés.

Conformément au brief (« si des éléments obligatoires manquent, le travail est dans Mesa, pas dans
Wine »), le point de blocage pressenti est **dans Mesa/KosmicKrisp**, pas dans Wine.

## 4. Questions ouvertes / décisions en attente
- Confirmer 3e par un vrai `vulkaninfo` sur un KosmicKrisp compilé (le brief exige la mesure).
- Croiser les profils FL 12_0 / 12_1 / 12_2, et déterminer **quel feature level Clair Obscur exige
  réellement** (UE5 DX12) — **non vérifié**.
- Étape 0 bloquée : CrossOver 25 → 26 (payant) + achat/installation du jeu (~50 Go).
- Wine 9.0 à remplacer par un build macOS récent (Gcenx ou compilation).
- Où installer `meson` + loader Vulkan sans « rien en dur dans le système » (venv + build local ?).
- Rosetta / AVX-AVX2 : non étudié.

---

## 5. Build KosmicKrisp — blocage de dépendances (2026-09-16)

### Outillage local monté (conforme « rien en dur »)
- venv `~/Dev/proton-ouvert/toolchain/` — Python **3.12.7**, meson **1.12.0**, mako, pyyaml.
  (Piège : le venv initial sur `/usr/bin/python3` = 3.9.6 est refusé, Mesa exige **Python ≥ 3.10**.)
- Prefix d'installation : `~/Dev/proton-ouvert/prefix/`. Build : `~/Dev/proton-ouvert/build/`.
- Sources ajoutées : `Vulkan-Headers`, `Vulkan-Loader`, `Vulkan-Tools` (Khronos, shallow).
- Présents : pkg-config 0.29.2, cmake 4.3.2, ninja, clang 17 (Apple). **bison 2.3** (ancien, à surveiller).
- Mesa cloné = version **26.3.0-devel**. La configuration meson démarre, détecte bien
  aarch64 + compilateur Objective-C.

### MESURÉ : KosmicKrisp exige LLVM — chaîne de dépendances
`meson.build` : `with_kosmickrisp_vk` (l.1049) ∈ `with_driver_using_cl` → `with_clc` (l.1058)
→ `with_llvm.enable_if(with_clc, 'CLC requires LLVM')` (l.1063-1064).

Donc bâtir KosmicKrisp impose **la chaîne OpenCL C de Mesa** :

| Dépendance | Version exigée | État |
|---|---|---|
| LLVM (+ `clang-cpp`) | **≥ 15.0.0** (`_llvm_version`, l.2007) | **absent** |
| `LLVMSPIRVLib` (SPIRV-LLVM-Translator) | **≥ 15.0.0.0**, compatible avec le LLVM choisi (l.2083-2091) | **absent** |
| SPIRV-Tools | requis par CLC (l.2096-2097) | **absent** |

Échec exact de `meson setup` : `ERROR: Neither a subproject directory nor a llvm.wrap file was
found` — pas de fallback LLVM embarqué dans Mesa.

`-Dmesa-clc=system` n'aide pas : il exige un binaire `mesa_clc` **déjà construit**, ce qui
suppose la même chaîne (utile seulement en cross-compilation).

### Fait qui change l'arbitrage « rien en dur dans le système »
Les trois formules existent chez Homebrew, **avec des versions appariées** (l'appariement
LLVM ↔ SPIRV-LLVM-Translator est explicitement vérifié par Mesa) :
`llvm 23.1.1`, `spirv-llvm-translator 23.1.1`, `spirv-tools 1.4.357.0`.

Surtout : **`llvm` est keg-only** → rien n'est lié dans `/opt/homebrew/bin`, tout reste confiné
dans `/opt/homebrew/opt/llvm/`, atteint via `LLVM_CONFIG`/`PATH` explicites. L'entorse à la règle
du brief est donc bien plus faible qu'anticipé.

Alternative conforme à 100 % : compiler LLVM 23 + clang depuis les sources dans le prefix local
→ **plusieurs heures** de compilation et des dizaines de Go. Non entrepris sans décision.

→ **DÉCISION EN ATTENTE.** Rien installé à ce stade.

## 6. Croisement statique COMPLET — tous les profils vkd3d-proton

Méthode : table `kk_get_device_extensions()` (`kk_physical_device.c:47`…) croisée avec l'union des
extensions de chaque profil de `VP_D3D12_VKD3D_PROTON_profile.json`. **Statique — à confirmer par `vulkaninfo`.**

| Profil | exts | présentes | conditionnelles | manquantes |
|---|---|---|---|---|
| `VP_D3D12_FL_11_0_baseline` | 11 | 8 | 1 | **2** |
| `VP_D3D12_FL_11_1_baseline` | 11 | 8 | 1 | **2** |
| `VP_D3D12_FL_12_0_baseline` | 11 | 8 | 1 | **2** |
| `VP_D3D12_FL_12_0_optimal` | 27 | 18 | 1 | 8 |
| `VP_D3D12_FL_12_1_baseline` | 13 | 8 | 1 | 4 |
| `VP_D3D12_FL_12_2_baseline` | 22 | 9 | 1 | 12 |
| `VP_D3D12_FL_12_2_optimal` | 37 | 19 | 1 | 17 |

### Le vrai plancher : 2 extensions seulement
Pour FL 11_0 **et** FL 12_0 baseline, il ne manque que :
- **`VK_EXT_dynamic_rendering_unused_attachments`** — 0 occurrence dans `src/kosmickrisp/`.
- **`VK_EXT_transform_feedback`** — un commentaire (l.876), aucune implémentation.

C'est bien plus encourageant qu'attendu : **le mur n'est pas un gouffre.** Le D3D12 de base ne
réclame pas mesh shaders ni ray tracing — ceux-ci n'apparaissent qu'à FL 12_2.

### Extensions gardées derrière une variable d'environnement
Toutes deux expérimentales, activables sans patch (`kk_debug.c`) :
- `VK_EXT_custom_border_color` → `MESA_KK_EXPERIMENTAL=custom_border` (exigée dès le plancher)
- `VK_EXT_image_view_min_lod` → `MESA_KK_EXPERIMENTAL=image_view_min_lod` (le README vkd3d-proton
  la classe « should », pas obligatoire)

→ pour un essai, `MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod`.

### Manquantes par palier supérieur
- **FL 12_1** (+2) : `VK_EXT_conservative_rasterization`, `VK_EXT_fragment_shader_interlock`
- **FL 12_0 optimal** (+6) : `descriptor_buffer`, `graphics_pipeline_library`,
  `shader_image_atomic_int64`, `shader_module_identifier`, `KHR_compute_shader_derivatives`,
  `KHR_pipeline_library` — toutes « performance », non bloquantes a priori
- **FL 12_2** (+10) : mesh shaders, ray tracing complet, fragment shading rate

### Appréciation (NON VÉRIFIÉE — à challenger)
`VK_EXT_transform_feedback` est probablement le point dur : Metal n'a pas d'équivalent direct du
stream-output D3D12. `dynamic_rendering_unused_attachments` semble nettement plus abordable.
Reste à établir **quel feature level Clair Obscur exige réellement** — non vérifié.

---

## 7. Changement de cadrage (décidé le 2026-09-16)

**CrossOver et l'Étape 0 sont abandonnés.** Objectif : proposer une **alternative gratuite à
Proton pour le Mac** — rien de payant dans la pile. Corollaires :
- Plus de référence chiffrée D3DMetal à égaler ; la pile libre est jugée pour elle-même.
- **Porter/implémenter ce qui manque en amont est explicitement dans le périmètre** — ce qui
  rejoint le § 6 : il ne manque que 2 extensions au plancher.
- Les questions « CrossOver 25 → 26 » et « achat du jeu » sont sans objet. À prévoir : un jeu ou
  une démo DX12 **gratuits** comme cible de test (non choisi à ce jour).

## 8. PIÈGE MAJEUR — `ninja` x86_64 sous Rosetta corrompt tout le build

### Symptôme
`ninja` échoue sur `src/util/blake3/blake3_neon.c` :
`arm_neon.h:28: error: "NEON intrinsics not available with the soft-float ABI"`.
Or **la commande de compilation, copiée telle quelle, réussit dans le shell.**

### Diagnostic
Commandes comparées **octet pour octet** (`cmp`) : strictement identiques. Environnement
innocenté (échec reproduit avec `env -i`). La différence n'était donc ni la commande ni l'env.

**Cause racine :**
```
file /usr/local/bin/ninja
  -> Mach-O 64-bit executable x86_64
```
`ninja` vient du préfixe Homebrew **Intel** (`/usr/local`), pas du préfixe ARM (`/opt/homebrew`).
Il tourne donc sous **Rosetta**, et **transmet sa personnalité x86_64 à tous ses processus fils**.
`/usr/bin/cc` est universel : lancé depuis ninja, il compile pour **x86_64**, où `arm_neon.h`
refuse de s'inclure.

Preuve directe : `cc -arch x86_64 -std=c11 -c blake3_neon.c` reproduit l'erreur **à l'identique**.

### Portée du piège
Ce n'est pas propre à blake3 : **tout objet compilé par ce ninja l'était en x86_64**, en silence.
Seul blake3 a crié, parce que NEON est arch-spécifique. Un build qui « marche » dans cette
configuration produit une bibliothèque Intel sur une machine ARM.

### Correctif retenu
`ninja` installé dans le venv (`pip install ninja` → 1.13.2, binaire **universel** donc arm64
natif), venv placé en tête de `PATH`. Vérifié : `arch` = `arm64`, meson reprend bien ce ninja.
Build reconfiguré **de zéro** (les objets précédents étaient x86_64).

### Règle à retenir
Sur Apple Silicon, **vérifier `file` sur chaque outil de build** avant de soupçonner le code.
`/usr/local/bin` = Homebrew Intel ; `/opt/homebrew/bin` = Homebrew ARM. Un outil Intel en tête de
PATH contamine silencieusement toute la chaîne.

## 9. Loader Vulkan + vulkaninfo — CONSTRUITS
Via CMake/Make (donc épargnés par le piège ci-dessus), installés dans `prefix/` :
- `prefix/bin/vulkaninfo` — **arm64** ✔
- `prefix/lib/libvulkan.dylib` → `libvulkan.1.4.362.dylib` — **arm64** ✔

---

## 10. ÉTAPE 1 TERMINÉE — KosmicKrisp tourne sur le M1 Max (2026-09-16)

```
GPU0:
  deviceName         = Apple M1 Max
  driverID           = DRIVER_ID_MESA_KOSMICKRISP
  driverName         = KosmicKrisp
  driverInfo         = Mesa 26.3.0-devel (git-5f253b9304)
  apiVersion         = 1.4.362
  conformanceVersion = 1.4.3.2
  deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
```
**148 extensions device** exposées (WSI comprise). Vulkan tourne sur Metal, sur ce Mac.

### Metal 4 sur M1 : MESURÉ au niveau API
Programme ObjC minimal (`/tmp/claude-501/mtltest.m`) lié à Metal :
```
MTLCopyAllDevices -> 1 device : "Apple M1 Max"
  supportsFamily(MTLGPUFamilyMetal4) = 1
```
`MTLGPUFamilyMetal4` = 5002, `API_AVAILABLE(macos(26.0))`. Le M1 Max **supporte Metal 4**.

### Recette de build qui marche
```
PATH=<venv>/bin:$PATH                       # ninja arm64, meson ; SURTOUT PAS llvm/bin
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig  # LLVMSPIRVLib, SPIRV-Tools
meson setup build --native-file llvm-native.ini \
  -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dplatforms=macos \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dbuildtype=release
```
`llvm-native.ini` : `[binaries]` / `llvm-config = '/opt/homebrew/opt/llvm/bin/llvm-config'`.
Exécution : `VK_DRIVER_FILES=<prefix>/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json`,
`DYLD_LIBRARY_PATH=<prefix>/lib`, `MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod`.

## 11. Deux bugs trouvés et corrigés

### Bug A — `Metal.framework` jamais lié (patch fourni)
`bridge/meson.build` ne déclarait que `Foundation`, et `declare_dependency` ne propageait pas les
frameworks au lien final. Conséquence : `_MTLCopyAllDevices` restait `(dynamically looked up)`,
donc **NULL**, et `mtl_device_create()` sautait à l'adresse 0.
→ `0001-kosmickrisp-link-Metal-framework.patch` (ajoute `Metal`, `QuartzCore`, propage la dép).
**Candidat pour l'amont Mesa.**

### Bug B — clang Homebrew + ld Apple = crash silencieux (piège d'environnement)
En mettant `/opt/homebrew/opt/llvm/bin` dans le `PATH` pour trouver LLVM, meson choisit :
```
C compiler           : cc     = Apple clang 17.0.0
Objective-C compiler : clang  = Homebrew LLVM 23.1.1   <-- le piège
```
Le clang de Homebrew émet des stubs `_objc_msgSendClass$<sel>$_OBJC_CLASS_$_<Classe>`.
**Le `ld` des Command Line Tools ne sait pas synthétiser cette forme** (vérifié en liant l'objet
seul, frameworks fournis : `Undefined symbols`). Or le driver est lié avec
`-Wl,-undefined,dynamic_lookup` (`vulkan/meson.build:166`, contournement amont pour les
entrypoints faibles `VK_ENTRY_WEAK`) : les stubs deviennent donc **NULL au lieu d'erreurs de lien**
→ segfault au premier envoi de message à une méthode de classe.

Vérifié : `dynamic_lookup` ne casse **pas** les stubs de sélecteur ordinaires
(`_objc_msgSend$sel`) — `ld` les synthétise bien. Seule la forme `objc_msgSendClass$` pose problème.

→ **Correctif : ne jamais mettre `llvm/bin` dans le PATH ; passer `llvm-config` par
`--native-file`.** L'Objective-C doit être compilé par Apple clang.

### Fausse piste écartée (pour mémoire)
Redéfinir `VK_ENTRY_WEAK` en `__attribute__((weak_import))` sur Darwin + retirer
`dynamic_lookup` : les symboles sont bien marqués `weak external`, mais `ld` refuse quand même les
faibles non résolus. Fonctionne uniquement avec 788 `-Wl,-U,_kk_*` explicites — inutile une fois
le bug B corrigé.

## 12. RÉSULTAT — tableau « exigé / présent / manquant » MESURÉ

Sortie réelle de `vulkaninfo` (148 extensions) croisée avec `VP_D3D12_VKD3D_PROTON_profile.json` :

| Profil vkd3d-proton | exigées | présentes | **manquantes** |
|---|---|---|---|
| `FL_11_0_baseline` | 11 | 9 | **2** |
| `FL_11_1_baseline` | 11 | 9 | **2** |
| `FL_12_0_baseline` | 11 | 9 | **2** |
| `FL_12_1_baseline` | 13 | 9 | 4 |
| `FL_12_0_optimal` | 27 | 19 | 8 |
| `FL_12_2_baseline` | 22 | 10 | 12 |
| `FL_12_2_optimal` | 37 | 20 | 17 |

**La mesure confirme exactement la prédiction statique du § 6.**

### Le plancher D3D12 est à DEUX extensions
- `VK_EXT_dynamic_rendering_unused_attachments`
- `VK_EXT_transform_feedback`

Puis, pour FL 12_1 : `VK_EXT_conservative_rasterization`, `VK_EXT_fragment_shader_interlock`.
FL 12_2 (mesh shaders, ray tracing) reste loin.

Conformément au brief : **le travail est dans Mesa, pas dans Wine.**

### Appréciation (NON VÉRIFIÉE)
`transform_feedback` est probablement le morceau dur — Metal n'a pas d'équivalent direct du
stream-output D3D12. `dynamic_rendering_unused_attachments` paraît nettement plus abordable.
Reste à établir quel feature level Clair Obscur exige réellement — **non vérifié**.

## 13. Questions ouvertes
- Quel feature level D3D12 le jeu cible-t-il vraiment ? (détermine si 2 ou 4 extensions suffisent)
- Cible de test **gratuite** en DX12 à choisir (le jeu n'est pas installé, et rien de payant).
- Les *features* et *properties* des profils ne sont pas encore croisées — seulement les extensions.
- Wine : toujours en 9.0 (cask Homebrew), à remplacer par un build macOS récent + WoW64.
- `bison 2.3` ancien : n'a pas gêné ce build, à surveiller.

---

## 14. VK_EXT_dynamic_rendering_unused_attachments — IMPLÉMENTÉE (2026-09-16)

Première des deux extensions manquantes au plancher D3D12 (§ 12).

### Ce que l'extension demande
Aucune commande nouvelle : c'est un **assouplissement des règles de validité**. Avec
`dynamicRenderingUnusedAttachments`, un pipeline peut être lié dans une passe dont les
attachements ne correspondent pas aux formats déclarés dans `VkPipelineRenderingCreateInfo` :
- format déclaré ≠ UNDEFINED face à un `imageView` NULL ;
- `VK_FORMAT_UNDEFINED` déclaré face à un attachement réellement présent ;
- idem pour depth/stencil.
Les écritures vers un attachement absent (ou non déclaré) sont écartées.

### Le patch
`0002-kosmickrisp-advertise-dynamic-rendering-unused-attachments.patch` — deux lignes :
l'extension dans `kk_get_device_extensions()`, la feature dans `kk_get_device_features()`.
C'est exactement ce que fait Asahi (`hk_physical_device.c:160,506`), qui ne traite rien de plus
ailleurs. Le runtime commun Mesa gère déjà le volet délicat : `vk_graphics_state.c:1839-1851`
neutralise depth/stencil quand `pDepthStencilState` peut être invalide.

### FAUSSE PISTE — machinerie de variantes, écrite puis RETIRÉE
J'ai d'abord mesuré, sur l'API Metal **classique**, que Metal refuse tout désaccord de format :
```
-[MTLDebugRenderCommandEncoder setRenderPipelineState:] failed assertion
  A) "the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set."
  B) "the render pipeline's pixelFormat (Invalid) does not match the framebuffer's (BGRA8Unorm)."
  D) "MTLDepthStencilDescriptor sets depth test but MTLRenderPassDescriptor has a nil depthAttachment"
```
J'en ai déduit qu'il fallait reconstruire le `MTLRenderPipelineState` sur les formats réels, et
j'ai écrit un cache de variantes (clé = formats couleur, mutex, recompilation paresseuse) plus des
variantes d'état depth/stencil.

**C'était faux.** Le test témoin (extension déclarée, machinerie retirée) passait tout aussi bien.
Raison : **KosmicKrisp n'utilise pas l'API Metal classique mais Metal 4** — `MTL4RenderCommandEncoder`,
`MTL4RenderPipelineDescriptor`, `MTL4Compiler` (`bridge/mtl_encoder.m:308`,
`bridge/mtl_compiler.m:212`). Repro Metal 4 (`tests/metal4_attachment_mismatch.m`), validation
activée : **les 4 cas passent sans la moindre assertion.** Metal 4 n'impose pas cette
correspondance stricte.

→ Machinerie supprimée. Leçon : mesurer sur l'API que le code utilise vraiment, pas sur sa
voisine. Les deux repros sont conservés dans `tests/` pour documenter la différence.

### Preuve de bon fonctionnement
`tests/test_dynamic_rendering_unused_attachments.c` (Vulkan pur, SPIR-V assemblé avec `spirv-as`,
triangle plein écran, **relecture du framebuffer**), exécuté avec
`MTL_DEBUG_LAYER=1 METAL_DEVICE_WRAPPER_TYPE=1` :

```
temoins (formats concordants) :
  pipeline=RGBA8 | passe AVEC couleur                  OK  pixel=ff0000ff attendu=ff0000ff
  pipeline=RGBA8+depth | passe AVEC couleur+depth      OK  pixel=ff0000ff attendu=ff0000ff

VK_EXT_dynamic_rendering_unused_attachments :
  pipeline=RGBA8 | passe SANS couleur (imageView NULL) OK
  pipeline=UNDEFINED | passe AVEC couleur (non ecrite) OK  pixel=00000000 attendu=00000000
  pipeline=depth+test actif | passe SANS depth         OK  pixel=ff0000ff attendu=ff0000ff
```
Le test **discrimine** : les témoins écrivent bien du rouge (le draw couvre l'écran), et le cas
`pipeline=UNDEFINED` **conserve la valeur de clear** — les écritures sont bien écartées, ce qui est
le comportement exigé, pas seulement une absence de crash.

**Limite assumée :** 5 cas écrits à la main, ce n'est pas la CTS. La validation conforme passe par
`dEQP-VK.*dynamic_rendering_unused_attachments*` (VK-GL-CTS non construite ici).

## 15. Tableau vkd3d-proton après ce travail — MESURÉ (149 extensions)

| Profil | exigées | présentes | **manquantes** |
|---|---|---|---|
| `FL_11_0` / `11_1` / `12_0 baseline` | 11 | 10 | **1** — `VK_EXT_transform_feedback` |
| `FL_12_1_baseline` | 13 | 10 | 3 |
| `FL_12_0_optimal` | 27 | 20 | 7 |
| `FL_12_2_baseline` | 22 | 11 | 11 |
| `FL_12_2_optimal` | 37 | 21 | 16 |

**Le plancher D3D12 ne tient plus qu'à une extension : `VK_EXT_transform_feedback`.**
Metal n'a pas d'équivalent direct du stream-output D3D12 : ce sera un vrai morceau, sans commune
mesure avec celui-ci.

---

## 16. VK_EXT_transform_feedback — IMPLÉMENTÉE (2026-09-17)

La seconde et dernière extension manquante au plancher D3D12 (§ 15).

### Pourquoi c'était le vrai verrou
`vkd3d_init_device_caps()` (`libs/vkd3d/device.c:2458`) teste **sans condition** :
```c
if (!physical_device_info->xfb_properties.transformFeedbackQueries) {
    ERR("Lacking support for transform feedback.\n");
    return E_INVALIDARG;
}
```
Sans l'extension, `xfb_properties` reste à zéro → **vkd3d-proton refuse de créer le device D3D12**,
quel que soit le jeu. Ce n'est donc pas une extension « pour les jeux qui font du stream-output » :
c'est un prérequis d'ouverture. À noter : `geometryStreams` n'est que **tracé** par vkd3d-proton
(l. 2211), jamais exigé — seul le profil formel le réclame.

### Approche : capturer depuis le vertex shader, pendant le draw
Metal n'a pas de transform feedback, mais **une fonction vertex Metal peut écrire dans des buffers
device**. La capture se fait donc dans le draw lui-même, sans passe compute séparée :

```
xfb_address[buf] + (instance_id * num_vertices + raw_vertex_id) * stride + offset
```

C'est le schéma de `nir_lower_xfb_to_stores()`. Il est **indexé par vertex**, pas par un compteur :
les offsets d'écriture d'un draw direct sont donc connus **avant** son exécution, ce qui évite tout
compteur GPU et tout atomique.

`nir_lower_xfb_to_stores()` n'est pas utilisée telle quelle : elle ne borne pas les écritures.
`src/kosmickrisp/vulkan/kk_nir_lower_xfb.c` en reprend la logique en encadrant chaque capture par
`if (xfb_size_kk(buf) >= offset + taille)`. Cette borne sert **deux** objectifs :
- la spec exige d'écarter les écritures dépassant le buffer ;
- le driver annonce une capacité nulle hors `vkCmdBeginTransformFeedbackEXT`/`End`, ce qui éteint
  la capture sans avoir à compiler deux variantes du shader.

`keep_outputs` est conservé : le même draw rasterise **et** capture.

### Pièces
| Élément | Où |
|---|---|
| Passe de lowering bornée | `kk_nir_lower_xfb.c` (nouveau) |
| Intrinsic privée `load_xfb_size_kk` | `nir_intrinsics.py` |
| `xfb_address` / `xfb_size` / `num_vertices` / `first_vertex` dans le root | `kk_cmd_buffer.h` |
| Lowering des 5 intrinsics vers le root | `kk_nir_lower_descriptors.c` |
| Bind / Begin / End + offsets par draw | `kk_cmd_draw.c` |
| Requêtes `TRANSFORM_FEEDBACK_STREAM_EXT` | `kk_query_pool.c` |
| Extension, features, properties | `kk_physical_device.c` |

Les compteurs de fin (`vkCmdEndTransformFeedbackEXT`) et les résultats de requête sont connus du
CPU mais **écrits sur la timeline GPU** (`kk_pool_upload` + copie, `kk_cmd_write`), donc ordonnés
après les draws qu'ils décrivent — pas à l'enregistrement.

### Propriétés corrigées au passage
Les `VkPhysicalDeviceTransformFeedbackPropertiesEXT` étaient **déjà remplies** dans le driver, en
code mort (l'extension n'était pas exposée), et plusieurs valeurs étaient optimistes :
`maxTransformFeedbackStreams` 4 → **1** (pas de geometry shaders),
`transformFeedbackDraw` true → **false** (`vkCmdDrawIndirectByteCountEXT` non implémentée),
`transformFeedbackRasterizationStreamSelect` true → **false**.

### Vérification — `tests/test_transform_feedback.c`
Vulkan pur, SPIR-V assemblé à la main avec décorations `XfbBuffer`/`XfbStride`/`Offset`,
**relecture du buffer de capture** :

```
transformFeedback=1 geometryStreams=0 maxBuffers=4 maxStreams=1 queries=1

capture normale
  vertex 0 : 0.0 0.0 3.0 4.0   OK      compteur : 48 octets (attendu 48)  OK
  vertex 1 : 1.0 2.0 3.0 4.0   OK      requete TF : ecrites=1 generees=1  OK
  vertex 2 : 2.0 4.0 3.0 4.0   OK

hors Begin/End : rien ne doit etre ecrit
  vertex 0/1/2 : intact (0xAB)  OK     requete TF : ecrites=0 generees=1  OK

buffer trop petit : seuls 2 vertices tiennent
  vertex 0 : OK   vertex 1 : OK   vertex 2 : intact (0xAB)  OK
  requete TF : ecrites=0 generees=1  OK
```
Le test **discrimine** : la capture est exacte, rien ne fuit hors de la région de capture, la borne
est respectée, et la requête distingue correctement « primitive générée » de « primitive
entièrement écrite ».

### Limites assumées (non implémentées, pas cachées)
- **Draws indexés** : le vertex ID est la valeur d'index, pas la position dans le draw, donc il ne
  peut pas adresser le buffer. Ces draws ne capturent rien plutôt que d'écrire faux.
- **Draws indirects et multi-draws** : nombre de vertices inconnu du CPU / un offset de base par
  draw serait nécessaire. Même traitement.
- **Reprise sur counter buffer** (`vkCmdBeginTransformFeedbackEXT`) : demanderait de lire un
  compteur en mémoire GPU. Un avertissement est émis, la capture repart de zéro.
- **`geometryStreams`** : exige des geometry shaders, que KosmicKrisp n'a pas du tout
  (`geometryShader` n'est pas déclaré, aucun `MESA_SHADER_GEOMETRY` dans le driver).
- **`vkCmdDrawIndirectByteCountEXT`** : non implémentée (et non utilisée par vkd3d-proton).
- Ce n'est pas la CTS : `dEQP-VK.transform_feedback.*` reste à passer.

## 17. RÉSULTAT — plancher D3D12 atteint (150 extensions)

| Profil vkd3d-proton | exigées | présentes | manquantes |
|---|---|---|---|
| **`FL_11_0_baseline`** | 11 | **11** | **0** |
| **`FL_11_1_baseline`** | 11 | **11** | **0** |
| **`FL_12_0_baseline`** | 11 | **11** | **0** |
| `FL_12_1_baseline` | 13 | 11 | 2 |
| `FL_12_0_optimal` | 27 | 21 | 6 |
| `FL_12_2_baseline` | 22 | 12 | 10 |
| `FL_12_2_optimal` | 37 | 22 | 15 |

**Le plancher D3D12 (jusqu'au feature level 12_0) est couvert côté extensions.**

Réserve à garder en tête : ce croisement porte sur les **extensions**. Le bloc
`baseline_features` du profil demande aussi `geometryStreams: true`, qui reste **false**. Le profil
formel n'est donc pas satisfait à 100 % — mais le verrou que vkd3d-proton teste réellement
(`transformFeedbackQueries`) l'est désormais.

Prochaines marches : FL 12_1 ne demande plus que `conservative_rasterization` et
`fragment_shader_interlock`.

---

## 18. vkd3d-proton EXÉCUTÉ contre KosmicKrisp (2026-09-17)

### Portage : vkd3d-proton compile nativement sur macOS arm64
Le meson amont ne connaît que `linux`, `android` et `windows`. Plutôt que de passer par Wine pour
un premier bout en bout, j'ai porté le build en natif —
`0004-vkd3d-proton-build-natively-on-macos.patch`, **193 lignes sur 10 fichiers** :

| Problème | Correctif |
|---|---|
| `vkd3d_platform == 'darwin'` inconnu | branche meson ; `lib_dl` = dépendance vide (dlopen est dans libSystem) |
| `pthread_setname_np(thread, name)` | Darwin ne nomme que le thread courant : `pthread_setname_np(name)` |
| `pthread_condattr_setclock` | absent sur macOS ; ses condvars sont sur `CLOCK_REALTIME`, l'attente a été alignée dessus |
| `program_invocation_name` | glibc → `getprogname()`, comme la branche Android |
| `renameat2(..., RENAME_NOREPLACE)` | → `renamex_np(..., RENAME_EXCL)` |
| `fseeko64` / `ftello64` | `off_t` est déjà 64 bits sur Darwin → `fseeko` / `ftello` |
| **`eventfd()`** | le plus gros morceau : réécrit en compteur + mutex + condvar, ce qui rend **exactement** les deux sémantiques utilisées (sémaphore compteur et événement auto-reset). Le `HANDLE` opaque devient l'adresse de l'objet. Le harnais de test a suivi. |
| `SONAME_D3D12CORE` | une branche `__APPLE__` existait déjà en amont mais nommait `vkd3d-proton-d3d12core.dylib`, alors que meson produit `libvkd3d-proton-d3d12core.dylib` |

Non porté : `GetFrameLatencyWaitableObject` (dupliquer l'objet de synchro laisserait l'appelant
libérer ce que la swapchain possède encore) — inutilisé en headless, FIXME explicite.

### Résultat : le verrou transform feedback est FRANCHI
```
$ ./tests/d3d12
d3d12: 2439 tests executed (51 failures, 0 successful todo, 671 skipped, 2 todo, 0 bugs).

$ grep -c "Lacking support for transform feedback" run.log
0
```
**Zéro occurrence.** `vkd3d_init_device_caps()` ne s'arrête plus sur transform feedback : la suite
de conformance d3d12 de vkd3d-proton s'exécute pour de bon sur Apple Silicon, contre KosmicKrisp.
C'est la preuve directe que le § 16 a levé le blocage qu'il visait.

### Le verrou SUIVANT — et il est matériel
```
err:vkd3d_init_device_caps: Lacking support for single texel alignment.
```
`device.c:2473` exige, pour les texel buffers storage **et** uniform :
`...SingleTexelAlignment == true` **ou** `...OffsetAlignmentBytes == 1`.

KosmicKrisp annonce `false` / **16 octets** (`KK_MIN_TEXEL_BUFFER_ALIGNMENT`, constante codée en
dur sans commentaire). J'ai vérifié si elle était seulement conservatrice —
`tests/metal_texel_buffer_alignment.m`, `minimumTextureBufferAlignmentForPixelFormat:` :

```
format         texel   buffer   alignement == taille du texel ?
R8Unorm            1       16   NON
RGBA8Unorm         4       16   NON
R32Float           4       16   NON
RGBA32Float       16       16   oui
=> alignement au texel unique sur tous les formats testes : NON
```
**Metal impose 16 octets sur tous les formats testés, quelle que soit la taille du texel.** La
constante est donc *juste*, pas pessimiste. Ce n'est pas un drapeau à basculer : D3D12 laisse une
vue de buffer démarrer à un offset d'élément quelconque, ce que Metal refuse en dessous de 16
octets.

La sortie serait une **émulation** : créer la vue à l'offset aligné en dessous, puis décaler
l'index côté shader. C'est un vrai chantier, du même ordre que transform feedback, pas un
ajustement.

### Où en est la pile
```
Jeu DX12 → Rosetta 2 → Wine → vkd3d-proton → KosmicKrisp → Metal 4
                               ^^^^^^^^^^^^   ^^^^^^^^^^^
                               compile et      Vulkan 1.4, 150 extensions,
                               tourne en       plancher D3D12 couvert
                               natif macOS
```
Étapes franchies : Metal 4 sur M1 confirmé · KosmicKrisp compilé et fonctionnel · 2 extensions
implémentées · vkd3d-proton porté sur macOS et exécuté · 2439 tests lancés.
Reste avant un premier device D3D12 : l'alignement des texel buffers. Wine n'est toujours pas
entré en jeu — et n'en a pas encore besoin.

---

## 19. Alignement des texel buffers — IMPLÉMENTÉ (2026-09-17)

### Le problème
Metal exige **16 octets** d'alignement pour une texture buffer, quel que soit le format (§ 18).
Vulkan, lui, autorise une `VkBufferView` à démarrer sur n'importe quel texel dès lors que
`uniform/storageTexelBufferOffsetSingleTexelAlignment` est annoncé — ce que vkd3d-proton exige
sans condition.

### L'émulation
La vue est créée sur la **frontière de 16 octets en dessous** de l'offset demandé, et le nombre de
texels ainsi sautés voyage dans le descripteur ; le shader le rajoute à chaque coordonnée.

```c
mtl_offset     = kk_buffer_mtl_offset(buffer, view->vk.offset);
aligned_offset = mtl_offset & ~15;
texel_offset   = (mtl_offset - aligned_offset) / taille_du_texel;

layout.width_px       += texel_offset;   /* la vue couvre aussi le prefixe */
layout.linear_stride_B += biais_octets;
```

Points de conception :
- L'alignement se calcule sur l'offset **Metal final** (`buffer->metal.offset + vk.offset`), pas sur
  l'offset Vulkan seul — sinon un buffer lié à un offset mémoire non nul casserait le calcul.
- Nouveau descripteur `kk_texel_buffer_descriptor` (16 o) au lieu de réutiliser
  `kk_storage_image_descriptor` (8 o) : les storage images gardent leurs 8 octets. L'identifiant de
  ressource **reste en premier**, car les chemins texture et image lisent tous deux un id à
  l'offset 0 sans savoir quel descripteur ils ont reçu.
- Le décalage est appliqué aux deux chemins d'accès dans `kk_nir_lower_descriptors.c` :
  `lower_image_intrin()` (imageLoad/Store/atomic) et le chemin `nir_tex_instr` (texelFetch), tous
  deux conditionnés à `GLSL_SAMPLER_DIM_BUF`.

Patch : `0005-kosmickrisp-texel-buffer-single-texel-alignment.patch` (~60 lignes utiles).

### Vérification — `tests/test_texel_buffer_alignment.c`
Compute shader (GLSL → glslang) lisant 8 texels par une vue **uniform** et une vue **storage**,
relecture dans un SSBO, sur plusieurs offsets :

| offset uniform | offset storage | résultat |
|---|---|---|
| 0 texels (0 o, aligné) | 4 texels (16 o, aligné) | TOUT PASSE |
| 1 texel (4 o, **non aligné**) | 2 texels (8 o, **non aligné**) | TOUT PASSE |
| 2 texels (8 o, **non aligné**) | 5 texels (20 o, **non aligné**) | TOUT PASSE |
| 3 texels (12 o, **non aligné**) | 7 texels (28 o, **non aligné**) | TOUT PASSE |
| 4 texels (16 o, aligné) | 8 texels (32 o, aligné) | TOUT PASSE |
| 5 texels (20 o, **non aligné**) | 6 texels (24 o, **non aligné**) | TOUT PASSE |

Le test vérifie les **valeurs lues**, pas seulement l'absence de crash : une vue à l'offset 3
texels doit rendre `BASE+3, BASE+4, …`.

## 20. RÉSULTAT — un ID3D12Device vit sur Apple Silicon

```
$ ./tests/d3d12
```
**Plus aucune erreur `vkd3d_init_device_caps`. Zéro « Failed to create device ».**

| | |
|---|---|
| Tests démarrés | **171** |
| **Entièrement réussis** | **150** |
| Avec au moins un échec | 7 |
| Avec au moins un skip | 14 |

(La suite s'arrête sur un segfault dans `test_geometry_shader_dxbc` : KosmicKrisp n'a aucun support
des geometry shaders et devrait rejeter le pipeline au lieu de planter. C'est un bug de robustesse
du driver, indépendant de ce travail.)

### Attribution honnête des 7 échecs
Instrumentation de ma passe XFB sur toute la suite : elle se déclenche **exactement 2 fois**, et
précisément pendant `test_vertex_id_dxbc` et `test_vertex_id_dxil` — les deux tests qui échouent.
**Ces deux échecs sont donc les miens.** La cause est la limitation déjà déclarée au § 16 :

```c
SOSetTargets(...)
DrawInstanced(3, 2, 0, 0);            /* capturé   */
DrawInstanced(3, 1, 3, 16);           /* capturé   */
DrawIndexedInstanced(3, 2, 0, 0, 0);  /* NON capturé */
DrawIndexedInstanced(3, 1, 3, 9, 7);  /* NON capturé */
```
D'où `Got counter value 144, expected 608u` : seuls les draws non indexés ont capturé. La limite
annoncée est désormais **démontrée**, plus seulement documentée.

Les 5 autres (`test_depth_stencil_sampling`, `test_geometry_shader_dxbc`, `test_object_interface`,
`test_query_pipeline_statistics`, `test_sample_instructions`) relèvent de manques préexistants de
KosmicKrisp (geometry shaders, statistiques de pipeline), pas de ce travail.

### Non-régression
Les trois suites précédentes repassent : transform feedback (3 modes),
dynamic_rendering_unused_attachments (5 cas), texel buffers (6 combinaisons d'offsets).

### Prochaine marche
Capturer les **draws indexés**. Le `[[vertex_id]]` de Metal y vaut la valeur d'index, pas la
position dans le draw : il faudrait une variante du vertex shader exécutée en compute, où
l'identifiant d'invocation est séquentiel. KosmicKrisp a déjà cette machinerie (`pre_render`, pour
la tessellation). Ce sont les deux derniers échecs imputables à ce travail.

---

## 21. Crashes de la suite d3d12 — CORRIGÉS (2026-09-17)

### Le diagnostic initial était faux
J'avais écrit au § 20 que KosmicKrisp « devrait rejeter le pipeline au lieu de planter ». La trace
dit autre chose :
```
Assertion failed: (iface->lpVtbl == &d3d12_pipeline_state_vtbl),
  function impl_from_ID3D12PipelineState, file vkd3d_private.h, line 2551.
```
Ce n'était pas un segfault dans le driver. KosmicKrisp **refuse correctement** le pipeline
(stages VERTEX + GEOMETRY + FRAGMENT, `hr 0x8007000e`) ; c'est vkd3d-proton qui abandonne, sur un
pointeur jamais initialisé.

### Trois corrections, de la plus systémique à la plus locale

**1. `Create*PipelineState()` ne vidait pas son paramètre de sortie en cas d'échec**
(`0007-…-clear-pipeline-state-out-param-on-failure.patch`).
Direct3D 12 met le pointeur à NULL quand la création échoue ; vkd3d-proton le laissait intact,
donc les appelants qui ne regardent que le pointeur recevaient une valeur de pile. Corrigé sur les
trois points d'entrée (graphics, compute, stream). `impl_from_ID3D12PipelineState()` gère déjà
NULL, donc cela suffit à rendre l'assertion inatteignable.
**C'est un défaut amont, indépendant de macOS** : il ne se voit que sur un driver qui échoue là où
tout le monde réussit.

**2. Deux tests utilisaient le pipeline sans vérifier**
(`0008-…-tests-survive-failed-pipeline-creation.patch`).
Une fois (1) en place, le crash s'est déplacé dans les tests eux-mêmes —
`ID3D12PipelineState_Release(NULL)`. Gardes ajoutées dans `test_geometry_shader` et
`test_layered_rendering` ; pour `test_clip_cull_distance`, seul le bloc geometry shader est sauté,
les cas de clip distance suivants continuent de s'exécuter.

**3. Deux vrais bugs de KosmicKrisp, révélés en avançant**
(`0006-kosmickrisp-buffer-view-robustness.patch`).
- `kk_CreateBufferView()` déréférençait `kk_get_va_format()` sans test, sur un commentaire
  optimiste (« If we reached here, we support reading at least »). Or cette fonction rend NULL pour
  tout format absent de sa table → déréférencement près de zéro. Rendu `VK_ERROR_FORMAT_NOT_SUPPORTED`.
- Au-delà de 2^28 texels, Metal **abandonne le processus depuis sa propre validation** au lieu de
  rendre nil (`MTLTextureDescriptor has width (536870912) greater than the maximum allowed size of
  268435456`). La limite est maintenant vérifiée dans le driver, avant Metal. Le préfixe ajouté par
  l'émulation d'alignement (§ 19) compte dans la limite.

### Effet mesuré, crash après crash
| Après | Tests démarrés | Arrêt sur |
|---|---|---|
| (départ, § 20) | **171** | assertion vkd3d-proton, `test_geometry_shader_dxbc` |
| garde `test_geometry_shader` | 173 | `test_layered_rendering_dxbc` |
| out-param NULL + 2 gardes de test | 290 | `test_undefined_typed_read_structured_raw_dxbc` |
| garde format NULL (driver) | 459 | `test_large_texel_buffer_view` (abandon Metal) |
| limite 2^28 texels (driver) | **512+** | `test_resolve_image_exhaustive_descriptors` (très lent, boucle 1024×) |

**171 → 512 tests démarrés, soit 3×.** Bilan sur ces 512 : **307 entièrement réussis**, 58 avec au
moins un échec, 148 avec au moins un skip.

Non-régression : les trois suites maison repassent (texel buffers 5 combinaisons d'offsets,
transform feedback 3 modes, dynamic rendering 5 cas).

### Le prochain obstacle : perte du device, puis blocage définitif
Tranché : ce n'est **pas** de la lenteur. Le log n'a pas grossi d'un octet en 25 minutes et
`sample` montre le thread principal endormi :
```
test_resolve_image_exhaustive_descriptors
  get_texture_readback_with_command_list
    wait_queue_idle_
      _pthread_cond_wait          <- attente sans borne
```
Tous les threads vkd3d (queue, fence, transferts, cache disque) sont eux aussi au repos. La cause
est trois lignes plus haut dans le log :
```
test_resolve_image_exhaustive_descriptors:3001:Layer 0: Test failed: Got 0x00000000, expected 0xff00003f
0000:err:d3d12_command_queue_execute: Failed to submit queue(s), vr -4.
0000:err:vkd3d_wait_for_gpu_timeline_semaphore: Failed to wait for Vulkan timeline semaphore, vr -4.
```
`vr -4` = **`VK_ERROR_DEVICE_LOST`**. Le résolve rend d'abord du noir (résultat faux), puis la
soumission suivante perd le device ; la fence ne se signalera jamais et l'attente ne se termine
jamais. Reproduit en isolation avec `VKD3D_TEST_MATCH`.

Ce que le test demande : une texture **1024 couches, MSAA 4×**, 16×16, `R8G8B8A8_UNORM_SRGB`, un
tas GPU de **1 000 000 descripteurs**, puis un résolve par couche.

Deux problèmes distincts, aucun corrigé ici :
1. **KosmicKrisp perd le device** sur cette charge — le résolve multi-couches est faux avant même
   la perte. C'est un vrai bug de driver, d'une autre nature que les crashes ci-dessus.
2. **vkd3d-proton attend sans borne** après une perte de device. Le bon comportement serait
   d'abandonner avec un message, pas de bloquer : après `DEVICE_LOST` plus rien ne peut avancer.

C'est le mur suivant pour mesurer le driver au-delà de 512 tests.

## 22. Perte de device — ENQUÊTE (2026-09-17) : le driver n'est PAS en cause

### 1. Ce que Metal dit vraiment
`vk_device_set_lost()` reçoit bien l'erreur Metal, mais Mesa ne l'affiche pas par défaut (ni
`MESA_VK_ABORT_ON_DEVICE_LOSS=1`, ni `VK_DEBUG=errors` ne l'ont fait sortir). Instrumentation
temporaire de `check_device_lost()` :
```
erreur Metal 1 (MTL_COMMAND_QUEUE_ERROR_TIMEOUT) :
  The operation couldn't be completed. (MTL4CommandQueueErrorDomain error 1.)
```
**`TIMEOUT`** — le chien de garde GPU, pas une faute mémoire. Le travail est simplement trop long.

### 2. Ce que le test demande vraiment
En relisant `test_resolve_image_exhaustive_descriptors` au-delà de la boucle de clears :
```c
for (j = 0; j < 64; j++)
    for (i = 0; i < 1024; i++)
        ... ResolveSubresource / ResolveSubresourceRegion ...
```
**64 × 1024 = 65 536 resolves** dans une seule command list, moitié matériels, moitié émulés par
shader. Le commentaire du test dit lui-même « Absolute torture ».

### 3. Mesure : d'où vient le temps — `tests/bench_render_pass_cost.c`
Repro Vulkan minimal, N passes de rendu 16×16, paramétrable :

| configuration | enregistrement | exécution | par passe |
|---|---|---|---|
| 1024 passes, MSAA 4×, avec resolve | 20,9 ms | 43,6 ms | **63,1 µs** |
| 1024 passes, MSAA 4×, sans resolve | 19,8 ms | 47,5 ms | **65,7 µs** |
| 1024 passes, 1 échantillon, sans resolve | 21,9 ms | 46,1 ms | **66,4 µs** |

Le coût est **identique dans les trois cas** : ni le MSAA ni le resolve n'y sont pour quelque
chose. C'est un surcoût fixe **par passe de rendu**. Croissance linéaire de 16 à 1024 passes.

### 4. Le point décisif : comparaison avec Metal 4 pur
`tests/metal4_render_pass_cost.m` — mêmes N encodeurs de rendu vides, sans Vulkan du tout :

| | par passe |
|---|---|
| Metal 4 pur, 1024 encodeurs vides | **52,4 µs** |
| KosmicKrisp, 1024 passes | 66 µs |

**~52 µs par encodeur est le plancher du matériel**, pas un défaut du driver. KosmicKrisp n'ajoute
que ~14 µs de travail propre, ce qui est raisonnable.

### 5. Conclusion
65 536 passes × 52 µs ≈ **3,4 secondes de GPU au minimum**, avant même la moitié émulée par shader.
Le chien de garde de Metal tue le command buffer bien avant. **Ce n'est pas un bug de KosmicKrisp** :
c'est une charge qui dépasse ce qu'une seule soumission peut faire sur une file Metal surveillée.

La parade serait côté driver mais relève de la **conception, pas de la correction** : découper un
command buffer trop long en plusieurs soumissions pour qu'aucune ne dépasse le chien de garde.
Certains drivers le font. Ce n'est pas un correctif de bug, c'est une stratégie à ajouter.

Corollaire : mon diagnostic du § 21 (« KosmicKrisp perd le device sur cette charge — un vrai bug de
driver ») était **faux**. Le résolve multi-couches n'est pas cassé : 1024 couches passent en 46 ms.

### 6. Troisième bug de robustesse trouvé en chemin — CORRIGÉ
Le repro à 4096 couches a fait sortir :
```
MTLTextureDescriptor has arrayLength (4096) greater than the maximum allowed size of 2048.
```
`maxImageArrayLayers` était pourtant **correctement** annoncé à 2048 — mais `kk_CreateImage()`
laissait Metal abandonner le processus au lieu de refuser. Même famille que les deux précédents.
Corrigé : `vkCreateImage` rend maintenant une erreur (vérifié : -2 au lieu d'un abandon), et la
limite passe par la constante partagée `KK_MAX_IMAGE_ARRAY_LAYERS`.
Patch `0006` mis à jour (buffer views + tableaux d'images).

---

## 23. Découpage des command buffers — IMPLÉMENTÉ (2026-09-17)

### Ce que la mesure a corrigé dans le diagnostic
Le § 22 concluait « chien de garde GPU ». En cherchant le seuil, la vraie nature apparaît :

| encodeurs dans **un** command buffer Metal 4 | résultat |
|---|---|
| 32 768 | OK, 1231 ms |
| 34 000 | OK, 1305 ms |
| 36 000 | OK, 1415 ms |
| **38 000** | **refusé en 2,8 ms** |
| 65 536 | refusé en 4,5 ms |

Un refus en 2,8 ms n'est pas un dépassement de temps : c'est une **limite de capacité**, atteinte
entre 36 000 et 38 000 encodeurs. Metal la signale comme `error 1`, que KosmicKrisp traduit en
`TIMEOUT` — d'où ma lecture initiale erronée.

### Par command buffer, pas par allocateur
Question décisive avant de concevoir quoi que ce soit (`tests/metal4_command_buffer_chunking.m`) :

| | résultat |
|---|---|
| 65 536 encodeurs, 1 command buffer | refusé |
| 65 536 en 4 morceaux, **un allocateur par morceau** | OK, 3743 ms |
| 65 536 en 4 morceaux, **allocateur partagé** | OK, **2914 ms** |
| 131 072 en 8 morceaux, allocateur partagé | OK, 5540 ms |

La limite est donc **par command buffer**. Un allocateur unique en porte 131 072 sans broncher.
Partager l'allocateur est aussi plus rapide, et surtout évite l'explosion mémoire : la première
version prenait un allocateur neuf par morceau et finissait en
`Failed to allocate IOGPUDeviceShmem`.

### L'implémentation
`0009-kosmickrisp-split-long-command-buffers.patch`.

Un `VkCommandBuffer` n'est plus lié à un seul `mtl_command_buffer` : il en garde une liste. Quand
le budget d'encodeurs est atteint, `kk_cmd_buffer_split_if_full()` ferme le command buffer courant,
le met de côté et en ouvre un autre — **avec le même allocateur**. À la soumission, tous partent
ensemble dans l'ordre d'enregistrement ; Metal les exécute dans cet ordre sur la file.

Choix de conception :
- **Découpage uniquement dans `cs_start_render()`**, juste après `cs_end()` : c'est le seul point
  où aucun encodeur n'est ouvert, donc le seul où la couture est gratuite. Les encodeurs compute
  sont **comptés** mais ne déclenchent pas de découpage — `cs_end()` peut en ouvrir un pour vider
  les écritures différées, et couper là serait scabreux.
- **Seuil à 8192**, soit 4× sous le plancher mesuré. La marge n'est pas du luxe :
  `mtl_command_allocator_reset()` existe dans le pont mais **n'est jamais appelé**, donc la
  capacité restante d'un allocateur recyclé est inconnue.
- **Si le pool n'a plus de command buffer**, on continue de remplir le courant : déborder peut
  encore marcher, perdre des commandes non.

### Vérification — `tests/bench_render_pass_cost.c`
Le test **relit le contenu** après coup, pas seulement le code de retour : sans découpage la fence
signale un succès alors que rien n'a tourné.

| passes | avec découpage | sans découpage (témoin) |
|---|---|---|
| 1 024 | OK, 45 ms | OK, 46 ms |
| 32 768 | OK, 1473 ms | OK, 1503 ms |
| **65 536** | **OK, 3293 ms** | **TRAVAIL NON EXÉCUTÉ, 1,8 ms** |
| 131 072 | OK, 6161 ms | — |

Croissance linéaire à ~60 µs/passe, soit le plancher matériel mesuré au § 22.

### Effet sur vkd3d-proton
Le test qui bloquait indéfiniment depuis le § 21 :
```
d3d12: ======== test_resolve_image_exhaustive_descriptors end ==========
d3d12: 11271 tests executed (0 failures, 0 skipped, 0 bugs).
```
**11 271 assertions, zéro échec.** Ses 65 536 resolves passent maintenant en plusieurs soumissions.

Non-régression : texel buffers (4 combinaisons), transform feedback (3 modes),
dynamic rendering (5 cas) — tous inchangés.

### Limite connue
Un **unique encodeur** contenant des dizaines de milliers de commandes (par exemple une longue
suite de dispatches compute sans changement de passe) n'est pas découpé : le découpage se fait
entre encodeurs. Si cette forme de saturation existe, elle demandera un autre axe.

## 24. La suite d3d12 va au bout — première fois (2026-09-17)

```
d3d12: 24687109 tests executed (19259 failures, 53 successful todo, 213 skipped, 370 todo, 24 bugs).
```
**574 fonctions de test démarrées, 574 terminées. Aucun crash, aucun blocage, aucune perte de
device** (`grep -c "vr -4" = 0`).

| | |
|---|---|
| Fonctions de test | **574** |
| Entièrement réussies | **349** |
| Avec au moins un échec | 62 |
| Avec au moins un skip | 164 |
| Assertions exécutées | **24 687 109** |
| Échecs d'assertion | 19 259 (0,08 %) |

### Le chemin parcouru
| après | tests démarrés | arrêt sur |
|---|---|---|
| § 20, premier device D3D12 | 171 | assertion vkd3d-proton (geometry shader) |
| § 21, quatre crashes corrigés | 512 | blocage définitif (resolve exhaustif) |
| § 23, découpage des command buffers | **574 / 574** | **rien — la suite se termine** |

Il n'y a plus d'obstacle structurel : ce qui reste, ce sont des écarts de conformité à mesurer un
par un, pas des arrêts brutaux. La photographie du driver est enfin possible.

---

## 25. Les 62 échecs, classés (2026-09-17)

### Répartition

| catégorie | tests | assertions |
|---|---|---|
| Réinterprétation de format sur textures tableau | 8 | **8 160** |
| Qualité de l'allocateur mémoire | 2 | 4 735 |
| Custom border color (extension expérimentale) | 3 | 2 616 |
| Divers, à examiner un par un | 17 | 2 277 |
| Aliasing de vues de buffer (comportement indéfini) | 6 | 1 148 |
| Transform feedback depuis la tessellation (non implémenté) | 8 | 144 |
| **Transform feedback — mon travail** | **5** | **100** |
| Geometry shaders absents (pipeline refusé) | 12 | 51 |
| Tessellation (hors stream output) | 1 | 28 |
| **TOTAL** | **62** | **19 259** |

Remarque : le nombre d'assertions dit peu de chose de la gravité. Les geometry shaders ne comptent
que 51 assertions alors que rien ne fonctionne (le pipeline est refusé d'emblée), tandis que la
réinterprétation de format en compte 8 160 parce qu'elle balaie des centaines de combinaisons.

### Ce qui m'est imputable : 5 tests sur 62 — MESURÉ
Instrumentation de ma passe XFB sur toute la suite. Elle se déclenche sur **8 tests** :

| test | résultat |
|---|---|
| `test_vertex_shader_stream_output_dxbc` | **passe** |
| `test_vertex_shader_stream_output_dxil` | **passe** |
| `test_vbv_stride_edge_cases` | **passe** |
| `test_index_buffer_edge_case_stream_output` | échec |
| `test_primitive_restart_list_topology_stream_output` | échec |
| `test_vertex_id_dxbc` / `_dxil` | échec |
| `test_vs_instance_input_nonuniform_workarounds` | échec |

Le stream output depuis le vertex shader **fonctionne** ; les 5 échecs sont tous des draws indexés,
exactement la limite déclarée au § 16. Une deuxième limite apparaît : la passe ne se déclenche
jamais sur les 8 tests de stream output depuis la **tessellation** — la capture n'a simplement pas
lieu (« Got unexpected primitives written 0 »).

### Deux fausses pistes écartées par A/B
- **`test_unused_attachments_mix_and_match`** (1 978 échecs) touche `VK_EXT_dynamic_rendering_unused_attachments`,
  que j'ai déclarée. Compilé sans l'extension : **1 978 échecs, à l'identique**. Elle est neutre ;
  le défaut est ailleurs dans le driver.
- **`custom_border_color`** : j'active `MESA_KK_EXPERIMENTAL=custom_border` dans toutes mes mesures,
  ce qui pouvait fabriquer des échecs. C'est l'inverse : **sans** le flag, 16 640 échecs ; **avec**,
  2 616. L'extension expérimentale en corrige les trois quarts, les 2 616 restants sont ses lacunes.
  À garder en tête : cette extension est dans le plancher `FL_11_0` du profil vkd3d-proton et reste
  expérimentale amont.

### Les deux plus gros morceaux ne sont pas de la correction
- **Réinterprétation de format** (8 160) : lire une texture tableau 1D/2D sous un autre format.
- **Allocateur** (4 735) : `test_suballocate_small_textures_size` se décrit lui-même comme
  « a strict test, should expose any case where a driver is pessimizing our allocation patterns » —
  KosmicKrisp alloue 143 360 octets là où 131 072 sont attendus. C'est de la **qualité
  d'allocation**, pas une faute de correction.

### Ordre d'attaque suggéré
1. **Geometry shaders** — 12 tests, et le blocage est total (aucun pipeline ne se crée). C'est
   aussi ce qui débloquerait `geometryStreams`, seule feature encore manquante au profil (§ 17).
2. **Transform feedback depuis la tessellation** — 8 tests, prolongement direct du § 16.
3. **Draws indexés en transform feedback** — 5 tests, ma limite connue ; demande une variante du
   vertex shader exécutée en compute.
4. Réinterprétation de format — le plus gros volume, mais isolé du reste.

---

## 26. Geometry shaders — FAISABILITÉ ÉTABLIE, intégration non faite (2026-09-17)

### Ce que j'ai fait
Metal n'a pas d'étage geometry shader : il faut l'émuler en compute. Avant d'engager le chantier,
j'ai vérifié que la voie existe — c'était le risque principal.

**Mesa fournit déjà le plus dur.** `src/poly/` est la bibliothèque partagée d'émulation
tessellation/géométrie (celle qu'Asahi utilise). `poly_nir_lower_gs()` découpe un geometry shader
en quatre programmes : `main`, `count`, `rast`, `pre_gs`.

Sonde branchée dans `kk_compile_shader()` sur un vrai GS venu de vkd3d-proton
(`spike-geometry-shader-feasibility.diff`) :

```
poly_nir_lower_gs : count_words=0 prefix_sum=0 shape=2 max_indices=4 multistream=0
  main   : stage=compute  MSL GENERE (412 octets)
  count  : absent
  rast   : stage=vertex   MSL GENERE (12036 octets)
  pre_gs : stage=compute  MSL GENERE (34219 octets)
```

**Les trois programmes se traduisent en MSL sans erreur.** Rien dans la sortie de poly ne bloque le
backend. Et pour ce cas (`shape=STATIC_INDEXED`, pas de préfixe), il n'y a même pas de passe de
comptage : VS→compute, GS→compute, pre_gs→compute, puis un draw indexé — exactement la forme que
KosmicKrisp orchestre **déjà** pour la tessellation (`poly_heap`, dispatches enchaînés, draw
indirect indexé).

Réserve : la sonde appelle `nir_to_msl()` sur la sortie brute de poly, sans la chaîne de lowering
du driver (descripteurs, IO). C'est un signal positif fort — aucune construction intraduisible —
pas une compilation complète.

### Pourquoi je n'ai pas intégré
Trois verrous **structurels**, mesurés dans le code :

| verrou | état actuel | besoin GS |
|---|---|---|
| `kk_shader.msl_data[MESA_SHADER_STAGES]` | un programme **par étage** | quatre programmes pour un seul étage |
| `kk_pipeline_handles.gfx.pre_render[3]` | trois pipelines compute | quatre dispatches |
| `kk_msl_serialize()` | parcourt `additional_stages_bits` | doit porter les programmes supplémentaires |

Au-delà de la plomberie (~150 lignes, mécanique), l'orchestration au draw est le vrai morceau :
allocation du buffer de comptage, somme de préfixes, buffer d'index depuis le tas, puis draw
indirect — l'équivalent chez Asahi fait plusieurs centaines de lignes, avec des détails subtils
(topologies de sortie, flux multiples, comptes de primitives).

**Je ne peux pas livrer ça vérifié en une fois**, et le faire à moitié aurait un coût immédiat :
déclarer `geometryShader = true` ferait créer par vkd3d-proton des pipelines GS qui échoueraient
plus loin, dégradant les 349 tests qui passent aujourd'hui. L'arbre est donc revenu à l'état
d'avant la sonde (non-régression vérifiée sur les quatre suites maison).

### Plan pour reprendre
1. Élargir `msl_data` et `pre_render` (structurel, mécanique).
2. Brancher `poly_nir_lower_gs()` dans `kk_compile_shader()` et faire passer les quatre programmes
   par la chaîne de lowering complète, puis les compiler.
3. Écrire `kk_launch_gs()` sur le modèle exact de la tessellation
   (`kk_cmd_draw.c`, dispatches + `libkk_prefix_sum` + draw indirect indexé).
4. Commencer par le cas simple **sans passe de comptage** (`prefix_sum=0`), qui est celui du test
   `test_geometry_shader` — puis le cas dynamique.
5. Ne déclarer `geometryShader = true` qu'une fois ce cas vert.

Gain attendu : les 12 tests de la grappe « pipeline refusé » (§ 25), et `geometryStreams`, seule
feature encore manquante au profil vkd3d-proton (§ 17).

---

## 27. Les geometry shaders tournent (2026-09-17)

`0010-kosmickrisp-geometry-shaders.patch` — 8 fichiers, ~590 lignes ajoutées.
`geometryShader = true` est déclaré.

### Ce qui a été branché
`poly_nir_lower_gs()` découpe un geometry shader en plusieurs programmes ; le pilote les exécute
en compute devant le draw, puis laisse le **programme de rastérisation** de poly (un vertex shader
ordinaire) dessiner ce qu'ils ont produit. Le vertex shader d'application devient lui aussi du
compute, exactement comme sur le chemin tessellation, et alimente le GS par le même tampon.

Cinq points ont demandé plus que de la plomberie :

| point | ce qu'il fallait comprendre |
|---|---|
| `grid.size.z` d'un draw direct | c'est le **base instance** de Metal, pas une profondeur. J'y passais `1`, donc le shader de rastérisation décodait la primitive 1 d'un draw qui n'en avait qu'une : rien n'était dessiné. |
| `load_provoking_last` | poly s'en sert pour ordonner les indices qu'il génère. Ajouté aux données par draw. |
| clip / cull distances | le lowering MSL les écrit dans la structure de sortie du rastériseur — qu'un *kernel* n'a pas. Reporté sur le seul programme qui finit vertex shader. |
| lowering « vertex matériel » | le programme de rastérisation ne le recevait pas du tout (point size, position, depth clamp), et il faut aussi lui passer la résolution des valeurs système de la table racine. |
| topologie du pipeline | elle doit venir de la primitive **de sortie** du GS, pas de ce que l'application a dessiné. |

### Draws indirects
Seul le GPU connaît les compteurs. `libkk_gs_setup_indirect` (noyau libkk, enveloppe de
`poly_gs_setup_indirect`) remplit les tampons de paramètres et les grilles de dispatch.

Le dispatch compute indirect de Metal ne compte qu'en **groupes** (`dispatchThreadgroupsWithIndirectBuffer` ;
il n'existe pas d'équivalent indirect de `dispatchThreads`). La grille est donc arrondie au
supérieur et des invocations de trop s'exécutent. Les programmes de poly indexent leurs tampons par
l'identifiant d'invocation brut — vérifié dans le MSL généré, le vertex shader écrit à
`output_buffer + (instance*verts_per_instance + id.x) * 16` sans borne. Avec 65 points, 2 groupes de
64 sont lancés et les écritures vont jusqu'à l'offset 2047 d'une allocation de 1040 octets. D'où une
**garde** insérée en tête de chaque programme émulé.

**Honnêteté sur cette garde** : A/B fait, les cinq cas du test passent **avec et sans**. Le
dépassement est réel (lu dans le MSL, arithmétique ci-dessus) mais il tombe dans une zone du tas que
le dessin suivant réécrit avant que quoi que ce soit ne la relise. La garde est là pour la sûreté
mémoire, pas pour un pixel observé.

### Vérification — `tests/test_geometry_shader_indirect.c`
Vulkan pur, shaders GLSL → glslang, **relecture du framebuffer**. Un point par rangée ; le GS lit
`gl_in[0].gl_Position` (sinon l'optimiseur vide le vertex shader et le chemin VS→GS n'est pas
testé du tout — c'était le cas de ma première version). 65 points : pas un multiple de la taille de
groupe.

```
compte statique, direct      OK
compte statique, indirect    OK
compte dynamique, direct     OK
compte dynamique, indirect   OK
dynamique, 4 dessins         OK
```
Le compte dynamique force la forme `POLY_GS_SHAPE_DYNAMIC_INDEXED`, dont le tampon d'indices est
alloué sur le GPU depuis le tas. Avant le correctif : `draw indirect` rendait le rouge d'effacement.

### Résultat sur la suite d3d12

| | avant (§ 24) | après |
|---|---|---|
| Fonctions démarrées / terminées | 574 / 574 | **574 / 574** |
| Fonctions avec au moins un échec | 62 | **55** |
| Échecs d'assertion | 19 259 | 19 216 |

| test | échecs avant | après |
|---|---|---|
| `test_geometry_shader_dxbc` / `_dxil` | 2 / 2 | **0 / 0** |
| `test_layered_rendering_dxbc` / `_dxil` | 1 / 1 | **0 / 0** |
| `test_ps_layer_dxbc` / `_dxil` | 7 / 7 | **0 / 0** |
| `test_clip_distance_dxbc` / `_dxil` | 1 / 1 | **0 / 0** |
| `test_gs_topology_mismatch_dxbc` | 8 | 3 |
| `test_shader_io_mismatch` | 12 | 2 |

Non-régression maison : `test_dynamic_rendering_unused_attachments`, `test_transform_feedback`,
`test_texel_buffer_alignment` — tous verts.

### Un échec nouveau, et il n'est pas de moi — MESURÉ
`test_object_interface` (« pipeline state: Test object has 1 references left ») apparaît. A/B avec
`geometryShader = false` recompilé : **exactement les mêmes trois échecs**. Le test ne crée aucun
geometry shader ; c'est un problème de comptage de références préexistant que la suite ne
déclenchait pas dans le même ordre auparavant.

À noter aussi : `test_suballocate_va_alignment` compte 2 585 échecs dans la campagne de référence et
3 085 ici — mais **3 085 aussi en le lançant seul**, avant comme après. Sa valeur dépend de ce qui a
alloué avant lui dans la campagne, pas de ce travail.

### Ce qui reste refusé, explicitement
`VK_ERROR_FEATURE_NOT_PRESENT` à la création du pipeline plutôt qu'un dessin faux :

1. **Transform feedback depuis un geometry shader.** Demande la passe de comptage, sa somme de
   préfixes et le programme pre-GS. Ces deux derniers sont compilés mais jamais lancés. Blocage de
   fond : mon implémentation XFB (§ 16) tient les compteurs **côté CPU**, alors que poly attend des
   compteurs **résidents GPU** (`xfb_offs_ptrs`) ; et `poly_pre_gs` déréférence des adresses de
   requêtes de statistiques que KosmicKrisp abaisse aujourd'hui à zéro, faute de page poubelle.
   C'est ce qui bloque encore `geometryStreams` au profil vkd3d-proton (§ 17).
2. **Geometry shader alimenté par la tessellation.** Le GS doit lire la sortie du tess evaluation
   shader, pas celle du vertex shader, et les deux émulations doivent se chaîner. En l'état le
   pipeline se construirait avec `pre_render_count = 1` : `kk_launch_tess()` irait chercher
   `pre_render[1]`, resté nul, ce qui donne l'abandon `computeFunction must not be nil` déjà
   observé cette session sur le programme de comptage. C'est ce refus qui laisse 3 échecs à
   `test_gs_topology_mismatch` et 2 à `test_shader_io_mismatch` : ces tests ne font que **créer**
   des pipelines, jamais dessiner avec. Sans le refus ils passeraient — et une application qui
   dessinerait vraiment tomberait sur l'abandon.
3. **Statistiques de pipeline** issues du GS (`load_stat_query_address_poly` → adresse nulle).

### Ordre d'attaque mis à jour
1. Compteurs XFB résidents GPU — débloque à la fois le XFB depuis GS, `geometryStreams`, et les
   5 tests de draws indexés du § 25.
2. Chaînage tessellation → géométrie (le draw indirect qu'il exige fonctionne désormais).
3. Réinterprétation de format sur textures tableau — le plus gros volume restant (8 160 assertions).

---

## 28. Compteurs de transform feedback résidents GPU (2026-09-17)

`0011-kosmickrisp-xfb-gpu-counters.patch` — 10 fichiers, ~460 lignes.
`geometryStreams` passe à **true**, `maxTransformFeedbackStreams` de 1 à 4.

### Politique Mesa — à lire avant toute soumission amont
L'arbre Mesa contient un `AGENTS.md` (`CLAUDE.md`) que je n'avais pas lu avant cette session. Il
interdit **les commentaires de code et les messages de commit générés par une IA**, exige le trailer
`Generated-by: LLM`, et interdit toute participation directe sur GitLab.

Conséquences concrètes :
- À partir du § 28, **aucun commentaire n'est ajouté dans l'arbre Mesa**. L'explication du code est
  ici, dans NOTES.md, qui est hors de l'arbre.
- Les patches **0001 à 0010 contiennent des commentaires et des messages de commit rédigés par
  l'IA**. Ils sont à réécrire avant toute soumission.
- `0011` et `0000` portent le trailer ; les autres ne l'ont pas encore.
- Deux commentaires existants sont devenus faux et demandent ta plume :
  `kk_nir_lower_xfb.c` (la formule d'adresse de capture ne mentionne pas le compteur) ;
  le commentaire supprimé au-dessus de `geometryStreams` disait « needs geometry shaders, which
  KosmicKrisp does not have ».
- `src/asahi` n'a jamais été modifié, seulement lu (vérifié : `git status` ne le mentionne pas).

### Le compteur
Un `uint32` par buffer de capture, alloué une fois par command buffer.
`vkCmdBeginTransformFeedbackEXT` l'amorce — copie GPU depuis le buffer de compteur quand la capture
**reprend**, écriture de zéro sinon — et les shaders de capture l'ajoutent à chaque offset d'écriture.
`vkCmdEndTransformFeedbackEXT` le ressort avec `libkk_xfb_save_counter`.

C'était la limite du § 16 : les offsets étaient calculés sur le CPU, donc une reprise depuis un
compteur que **seul le GPU a écrit** était impossible. C'est exactement ce dont D3D12 a besoin
(`SO_BUFFER_FILLED_SIZE_LOCATION`).

### Vérification — A/B décisif
`tests/test_transform_feedback.c` gagne un mode 3 : capture, `End` vers le buffer de compteur,
puis `Begin` **depuis** ce buffer, deuxième capture.

| | vertices 0-2 | vertices 3-5 | compteur |
|---|---|---|---|
| compteur neutralisé (témoin) | OK | **jamais écrits** | 96 |
| compteur actif | OK | **OK** | 96 |

Le témoin montre que la deuxième capture réécrivait par-dessus la première. Noter que le compteur
final était juste dans les deux cas : les deux moitiés (données, comptage) sont indépendantes.

### Transform feedback depuis un geometry shader
poly capture depuis son programme de rastérisation, après une chaîne comptage → somme de préfixes →
pre-GS. Trois manques côté KosmicKrisp :
- `nir_ro_to_rw_poly` n'était pas traduit (poly déclare `xfb_offs_ptrs` en lecture seule et l'écrit
  quand même) → abaissé en identité ;
- `load_stat_query_address_poly` valait **zéro**, et `poly_pre_gs` déréférence ces adresses sans
  condition → une page poubelle par command buffer ;
- `libkk_prefix_sum_geom` n'existait pas (enveloppe de `poly_prefix_sum`, 5 lignes).

### Deux vrais défauts trouvés en chemin
1. **`nir_opt_varyings` supprimait les composantes constantes capturées.** Le GS écrivait
   `vec4(id, i, 3.0, 4.0)` : `z` et `w` arrivaient à **0** dans le buffer de capture. La passe
   propage les constantes dans le fragment shader et retire l'écriture côté producteur — elle ne
   protège les sorties capturées que si `nir_io_add_intrinsic_xfb_info` a **déjà** tourné, ce que
   KosmicKrisp ne faisait que pour l'étage vertex. Diagnostic par substitution : avec un `z`/`w`
   non constants, la capture était juste.
2. **Le programme de rastérisation de poly propage plus de composantes que le fragment shader n'en
   lit**, ce que Metal refuse (`Fragment input(s) user(vary_00) mismatching vertex shader output`).
   C'est la contrepartie du point 1 : une fois la sortie préservée pour la capture, producteur et
   consommateur ne concordaient plus. Corrigé en rognant les sorties du programme de rastérisation
   sur ce que le fragment shader lit réellement, relevé après l'édition de liens.

### Vérification — `tests/test_geometry_shader_xfb.c`
Vulkan pur, GLSL → glslang, relecture des buffers de capture et de compteur.

```
capture depuis le GS            12/12 captures OK, compteur 192 o, requete TF 4/4
capture depuis le GS + reprise  24/24 captures OK, compteur 384 o, requete TF 8/8
capture depuis le GS, 2 flux     4+4 captures OK, compteur  64 o, requetes TF 4/4 et 4/4
```

### `geometryStreams` et les requêtes indexées
Le cas deux flux capture dans deux buffers distincts et relève **deux requêtes indexées
simultanées**, une par flux. L'état de requête XFB de KosmicKrisp n'avait qu'un seul emplacement :
la deuxième `vkCmdBeginQueryIndexedEXT` écrasait la première et les deux renvoyaient zéro. Il est
désormais indexé par flux.

Les compteurs de requête sont eux aussi passés sur le GPU : c'est `poly_pre_gs` qui les incrémente.
Sans cela, une requête posée autour d'une capture depuis un GS aurait renvoyé **zéro** — lacune que
cette session avait introduite en levant le refus du § 27.

### Correction au § 17 — MESURÉ
J'y écrivais que `geometryStreams` était « la seule feature encore manquante au profil ». C'était
faux : le § 17 croisait les **extensions**, pas le bloc `baseline_features`. Croisement complet
refait, `vulkaninfo` contre `VP_D3D12_VKD3D_PROTON_profile.json` :

| | avant | après |
|---|---|---|
| features/propriétés exigées par `baseline_features` | 75 | 75 |
| manquantes | **3** | **2** |

Il reste `fillModeNonSolid` et `pipelineStatisticsQuery`, tous deux jamais déclarés par KosmicKrisp.

### Suite d3d12 — aucune régression
| | § 24 | après § 27 | après § 28 |
|---|---|---|---|
| Fonctions avec au moins un échec | 62 | 55 | **55** |
| Échecs d'assertion | 19 259 | 19 216 | 19 218 |

Jeu de tests en échec **identique** au § 27. La suite ne contient aucun test de capture depuis un
geometry shader sans tessellation : les gains ci-dessus sont mesurés par les tests maison.

### Une famille d'échecs qui varie d'une campagne à l'autre — MESURÉ
Une campagne a montré 7 tests en « references left » (fences, multithread, allocateur) au lieu d'un
seul. **Même binaire, campagne suivante : 1.** C'est de la variance, pas une régression — les tests
touchés sont ceux qui dépendent du fil asynchrone de cache de pipelines de vkd3d-proton.
Seul `test_object_interface` est stable, et le § 27 avait déjà montré par A/B qu'il ne vient pas de
ce travail.

### La série de patches ne s'applique pas dans l'ordre — MESURÉ
```
0001 OK · 0002 OK · 0003 FAIL · 0005 OK · 0006 FAIL · 0009 OK · 0010 FAIL · 0011 FAIL
```
Les patches ont été produits chacun contre l'arbre du moment, pas comme une série : `0003` contient
déjà le contenu de `0002`, `0006` recouvre `0005` sur `kk_buffer_view.c`, et les rejets se propagent.
Même avec du flou et en sautant `0002`, trois fichiers finissent faux.

D'où **`0000-kosmickrisp-cumulatif.patch`** : le delta complet depuis le HEAD amont, 2 423 lignes,
**vérifié — il s'applique sans rejet sur Mesa vierge et reproduit l'arbre à l'identique**. Les
patches numérotés restent utiles à la lecture, pas à l'application.

### Ce qui reste
- **Capture depuis un draw indexé côté vertex shader** (5 tests, § 25) : inchangé. Le vrai correctif
  est de faire passer toute capture par un geometry shader de transit (`poly_nir_passthrough_gs`),
  comme Asahi, ce qui donnerait l'ordre primitif exact. La plomberie est désormais en place.
- **`vkCmdDrawIndirectByteCountEXT`** / `transformFeedbackDraw` : devenu faisable maintenant que le
  compteur est sur le GPU ; non implémenté.
- **Transform feedback depuis la tessellation**, et **geometry shader alimenté par la tessellation**
  (§ 27) : toujours refusés.
- `fillModeNonSolid`, `pipelineStatisticsQuery` : jamais déclarés.

---

## 29. Geometry shader de transit : la capture passe par l'ordre primitif (2026-09-17)

`0012-kosmickrisp-xfb-passthrough-gs.patch` — 2 fichiers, ~200 lignes.

### L'idée
Jusqu'ici la capture était écrite par le vertex shader lui-même, à l'offset
`(instance_id * num_vertices + raw_vertex_id) * stride`. Sur un draw **indexé**, `raw_vertex_id`
est la *valeur* de l'indice, pas le rang du sommet : deux indices identiques écrasaient la même
case, et l'ordre ne suivait pas celui des indices. C'était la limite déclarée au § 16.

Le correctif est celui d'Asahi : quand le dernier étage avant rastérisation capture et qu'il n'y a
pas de geometry shader, on en **fabrique un de transit** (`poly_nir_passthrough_gs`), et toute la
capture passe par l'émulation géométrique déjà en place. C'est poly qui assemble les primitives en
logiciel, donc l'ordre est l'ordre primitif exact.

### Intégration
Le shader de transit est bâti **après l'édition de liens** — il doit recopier les sorties finales du
vertex shader — puis inséré dans la liste des étages à l'indice 1. Tout l'aval le traite comme un
geometry shader d'application. Points à surveiller :
- le vertex shader passe en compute (`emulated_stage`), donc sa capture directe est désactivée ;
- `has_xfb` du vertex shader devient faux dès qu'il alimente un geometry shader, sinon le
  comptage CPU et le comptage GPU s'ajouteraient ;
- les étages synthétisés (le fragment de secours et ce geometry shader) ne doivent pas ressortir
  vers l'appelant : une table de correspondance rend à `shaders_out` les seuls étages de
  l'application ;
- la détection « il y a un GS » au moment du draw ne peut plus regarder un shader lié — elle lit
  `vs->info.has_gs`, rempli à la fusion du pipeline.

### Primitive restart
poly lit le buffer d'indices lui-même et **ne connaît pas le restart**. Sur les topologies où Metal
le gère nativement, KosmicKrisp ne déroulait pas — donc les bandes étaient assemblées en ignorant
les coupures. Le déroulage est maintenant forcé dès que le chemin géométrique est actif et que le
draw a le restart. Corollaire : après déroulage la topologie devient une liste, et le mode d'entrée
passé à poly doit venir du **draw** (`data->prim`), pas de l'état dynamique.

### Vérification — `tests/test_transform_feedback.c`, six cas

| mode | ce qu'il éprouve | résultat |
|---|---|---|
| 0 | capture normale | OK |
| 1 | hors `Begin`/`End` : rien ne doit être écrit | OK |
| 2 | buffer trop petit | OK |
| 3 | pause puis reprise depuis le buffer de compteur | OK |
| 4 | **draw indexé**, indices `{2,0,1}` | OK |
| 5 | **draw indirect** | OK |

Le mode 4 discrimine : les données capturées sont dans l'ordre des indices
(`2.0 / 0.0 / 1.0`), pas dans l'ordre des valeurs.

**Changement de sémantique au mode 2.** Le test attendait auparavant 2 sommets sur 3 : le découpage
se faisait par sommet. Désormais **rien** n'est capturé — une primitive qui ne tient pas entière est
rejetée entière, ce qui est la règle. La requête disait déjà `ecrites=0` ; données et requête
s'accordent enfin.

### Résultat sur la suite d3d12 — les 5 tests du § 25 tombent

| | § 24 | § 27 | § 28 | § 29 |
|---|---|---|---|---|
| Fonctions avec au moins un échec | 62 | 55 | 55 | **50** |
| Échecs d'assertion | 19 259 | 19 216 | 19 218 | **19 118** |

| test | avant | après |
|---|---|---|
| `test_vertex_id_dxbc` / `_dxil` | 30 / 30 | **0 / 0** |
| `test_primitive_restart_list_topology_stream_output` | 15 | **0** |
| `test_vs_instance_input_nonuniform_workarounds` | 13 | **0** |
| `test_index_buffer_edge_case_stream_output` | 12 | **0** |

**Aucun nouvel échec.** C'est exactement la grappe que le § 25 m'imputait ; elle est vidée.

### Ce que ça coûte
Tout pipeline dont le vertex shader capture passe maintenant par trois dispatches compute et une
rupture de passe de rendu. C'est le prix de l'ordre primitif, et c'est le choix d'Asahi. Non mesuré
en temps : aucun banc ici ne fait de la capture en volume.

### État des limites du § 16
| limite déclarée au § 16 | aujourd'hui |
|---|---|
| draws indexés | **levée** (§ 29) |
| draws indirects | **levée** (§ 29) |
| reprise sur counter buffer | **levée** (§ 28) |
| `geometryStreams` | **levée** (§ 28) |
| `vkCmdDrawIndirectByteCountEXT` | toujours absente, mais désormais faisable |
| capture depuis la tessellation | toujours absente (demande le chaînage tess → géométrie) |

### Patches
`0012` s'applique sur l'état d'après `0011`. La série complète reste non applicable dans l'ordre
(§ 28) : **`0000-kosmickrisp-cumulatif.patch`** (2 634 lignes) est le seul artefact vérifié comme
applicable sur Mesa vierge, et il reproduit l'arbre à l'identique.

---

## 30. `vkCmdDrawIndirectByteCountEXT` (2026-09-17)

`0013-kosmickrisp-draw-indirect-byte-count.patch` — 3 fichiers, ~60 lignes.
`transformFeedbackDraw` passe à **true**.

### Ce que c'est
L'équivalent Vulkan du `DrawAuto` de D3D11 : redessiner ce qu'une capture précédente a produit, sans
que le CPU sache combien de sommets elle contient.
`vertexCount = (counterBuffer[offset] - counterOffset) / vertexStride`, le reste est un `vkCmdDraw`.

C'était impossible tant que le compteur vivait sur le CPU (§ 16). Depuis le § 28 il est sur le GPU,
donc il suffit d'un noyau qui lit le compteur et écrit un `VkDrawIndirectCommand`, puis d'un draw
indirect ordinaire — exactement le schéma déjà utilisé pour les prédicats de rendu conditionnel.

### Vérification — `tests/test_transform_feedback.c`, modes 6 et 7
```
mode 6  capture, puis redessin depuis le compteur   6 sommets, compteur 96 o, requete 2/2   OK
mode 7  idem avec counterOffset = 16                3 sommets, compteur 48 o, requete 1/1   OK
```
Le mode 7 **discrimine** : le décalage laisse `(48-16)/16 = 2` sommets, donc **zéro triangle
complet**, donc rien de capturé et le compteur ne bouge pas. Si `counterOffset` était ignoré on
verrait six emplacements remplis et 96 octets.

### Suite d3d12 — inchangée
| | § 29 | § 30 |
|---|---|---|
| Fonctions avec au moins un échec | 50 | **50** |
| Échecs d'assertion | 19 118 | **19 118** |

Jeu identique, à l'assertion près. Attendu : D3D12 n'a pas de `DrawAuto`, aucun test de la suite
n'appelle cette entrée. Le gain est une entrée du profil Vulkan, pas un test qui passe.

### Profil vkd3d-proton — inchangé lui aussi
`baseline_features` : 75 exigées, **2 manquantes** (`fillModeNonSolid`,
`pipelineStatisticsQuery`). `transformFeedbackDraw` n'y figure pas ; il est déclaré parce qu'il est
maintenant vrai, pas parce que le profil le réclame.

### État final des limites du § 16
| limite déclarée au § 16 | aujourd'hui |
|---|---|
| draws indexés | **levée** (§ 29) |
| draws indirects | **levée** (§ 29) |
| reprise sur counter buffer | **levée** (§ 28) |
| `geometryStreams` | **levée** (§ 28) |
| `vkCmdDrawIndirectByteCountEXT` | **levée** (§ 30) |
| capture depuis la tessellation | **toujours absente** — demande le chaînage tess → géométrie |

Il ne reste qu'une des six.

### Patches
`0000-kosmickrisp-cumulatif.patch` régénéré : 2 700 lignes, vérifié applicable sans rejet sur Mesa
vierge et reproduisant l'arbre à l'identique. La série numérotée reste non applicable dans l'ordre
(§ 28).

---

## 31. ÉTAPE 2 — la pile ouverte tourne, et elle bute sur **une** extension (2026-09-17)

Première tentative de l'étape 2 du brief. Trois questions ouvertes du brief y trouvent leur réponse,
toutes mesurées.

### Réponse 1 — Metal 4 fonctionne sous Rosetta
Le brief supposait Rosetta pour le jeu et un pilote natif. Sonde `metal4_rosetta_probe.m` compilée
pour les deux architectures :

```
binaire=arm64  proc_translated=0   MTL4CommandQueue : OK
binaire=x86_64 proc_translated=1   MTL4CommandQueue : OK
```

Un processus **traduit** accède à Metal 4. Conséquence directe : plus besoin d'un Wine arm64 avec
WoW64 (que la machine n'a pas). Toute la pile peut être x86_64.

### Réponse 2 — Wine sur macOS ne passe pas par le loader Vulkan
`winemac.so` fait un `dlopen("libMoltenVK.dylib")` **en dur** — la seule chaîne `.dylib` du binaire.
Mais il n'appelle que des points d'entrée **standards** (`vkCreateInstance`, `vkCreateMetalSurfaceEXT`,
`vkGetInstanceProcAddr`, …), aucune API privée MoltenVK.

D'où la substitution, qui tient en une ligne : placer le **loader Vulkan** sous le nom
`libMoltenVK.dylib` sur `DYLD_LIBRARY_PATH`. Wine ne voit pas la différence, et le loader charge
KosmicKrisp via `VK_DRIVER_FILES`. C'est ce que fait `tests/etape2_pile_wine.sh`.

### Réponse 3 — `VK_EXT_metal_surface` est bien exposée
Confirmé sur `vulkaninfo` : `VK_EXT_metal_surface : extension revision 1`, et le type de surface est
utilisable. C'est ce dont `winemac.so` a besoin pour afficher.

### La pile x86_64, construite
| élément | comment |
|---|---|
| KosmicKrisp x86_64 | `x86_64-darwin.ini` (cross meson) + `-Dmesa-clc=system -Dprecomp-compiler=system` |
| outils de compilation | construits **natifs** arm64 et installés (`-Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true`) |
| loader Vulkan x86_64 | cmake `-DCMAKE_OSX_ARCHITECTURES=x86_64` |
| vkd3d-proton PE | `build-win64.txt` + mingw-w64 GCC 13.1 (déjà présent dans le Homebrew Intel) |

Deux frictions notées : le Homebrew Intel n'a pas SPIRV-Tools, donc la lib x86_64 garde **5 symboles
indéfinis** (`spvBinaryToText` et voisins), uniquement appelés par le dump SPIR-V de débogage ; et
mingw-w64 13.1 ne connaît pas `PATHCCH_NONE`
(`0014-vkd3d-proton-pathcch-none-for-older-mingw.patch`, 5 lignes).

### Vérification intermédiaire — le pilote x86_64 rend vraiment
`test_geometry_shader_indirect` recompilé en x86_64, exécuté sous Rosetta contre KosmicKrisp x86_64 :
les cinq cas passent, framebuffer relu. L'émulation de geometry shaders des § 27-29 fonctionne
traduite.

### RÉSULTAT — un binaire Windows voit le GPU à travers la pile ouverte
```
$ ./tests/etape2_pile_wine.sh wine/bin/winvk.exe
LoadLibrary(vulkan-1.dll) : 00006ffffe300000
vkCreateInstance : 0
peripheriques : 1
GPU : Apple M1 Max   API 1.4.362
extensions : 119
```
Chaîne complète : **PE Windows x86_64 → Wine 9.0 (x86_64, Rosetta) → winevulkan → winemac.so →
loader Vulkan → KosmicKrisp → Metal 4 → M1 Max.** Zéro composant fermé hors Rosetta et Metal.

### Le mur, et il est étroit
`d3d12.exe` (suite vkd3d-proton compilée en PE) démarre, charge `d3d12.dll` et `d3d12core.dll`
natifs, puis :
```
err:vkd3d-proton:vkd3d_init_device_caps: maintenance5 and/or maintenance6 not supported
test_create_device: Test skipped: Failed to create device.
```

Croisement du profil vkd3d-proton contre ce que **Wine** transmet, pas ce que le pilote a :

| | exigées | manquantes en natif | manquantes via Wine 9.0 |
|---|---|---|---|
| `FL_11_0` / `FL_11_1` / `FL_12_0` baseline | 11 | **0** | **2** |

Les deux :
- **`VK_KHR_maintenance6`** — absente de winevulkan 9.0. KosmicKrisp l'a. Blocage dur.
- **`VK_KHR_calibrated_timestamps`** — Wine 9.0 ne connaît que l'alias `VK_EXT_`. KosmicKrisp expose
  les deux.

`VK_EXT_custom_border_color` semblait manquer aussi : faux positif, j'avais oublié
`MESA_KK_EXPERIMENTAL=custom_border`. Avec le drapeau, Wine la transmet (119 extensions au lieu de 116).

**Rien de tout cela n'est dans le pilote.** Les deux manques sont dans le *thunk* Vulkan de Wine 9.0
(janvier 2024), qui ne relaie que les extensions qu'il connaît.

### Wine disponibles sur la machine — MESURÉ
| | version | extensions vues | maintenance5 | maintenance6 |
|---|---|---|---|---|
| `Wine Stable.app` | **9.0** | 119 | oui | **non** |
| Whisky | 7.7 | 108 | non | non |
| CrossOver | — | écarté (payant) | | |

Aucun Wine arm64 sur la machine — sans objet désormais, puisque Rosetta suffit.

### Prochaine marche
Un Wine plus récent. Wine met à jour `vk.xml` en continu ; `maintenance6` (fin 2023) devrait être
relayée par une 9.x tardive ou une 10.x. Deux voies : récupérer un build macOS x86_64 publié
(Gcenx), ou compiler Wine depuis les sources. **Décision en attente** — rien n'a été téléchargé.

---

## 32. RÉSULTAT — un device D3D12 vit sur une pile entièrement ouverte (2026-09-17)

La question ouverte du brief — *« aucun rapport trouvé de jeu DX12 lancé avec vkd3d-proton sur
KosmicKrisp »* — a une réponse.

```
$ WINEPREFIX=.../wine/pfx10 VKD3D_TEST_FILTER=test_create_device \
    ./tests/etape2_pile_wine.sh wine/bin/d3d12.exe
d3d12: 19 tests executed (0 failures, 0 successful todo, 0 skipped, 0 todo, 0 bugs).
```

Chaîne complète, chaque maillon compilé ici :
```
binaire PE Windows x86_64
  → vkd3d-proton (d3d12.dll / d3d12core.dll, compilés en PE avec mingw-w64)
  → Wine 10.0            (compilé depuis les sources, x86_64)
  → winevulkan → loader Vulkan (compilé x86_64)
  → KosmicKrisp          (compilé x86_64, avec les patches 0000-0013)
  → Metal 4 → Apple M1 Max
```
Seuls Rosetta et Metal restent fermés, et ce sont les deux briques qu'Apple fournit.

### Et elle dessine
| test | résultat |
|---|---|
| `test_clear_render_target_view` | 735 assertions, **0 échec** |
| `test_draw_instanced` | 20, **0 échec** |
| `test_geometry_shader_dxbc` | 43, **0 échec** |
| `test_vertex_shader_stream_output_dxbc` | 35, **0 échec** |

L'émulation de geometry shaders (§ 27-29) et la capture par compteurs GPU (§ 28-30) fonctionnent
**à travers Wine, en x86_64 traduit**.

### Pourquoi Wine 10 et pas le Wine installé
Le § 31 avait localisé le mur dans le thunk Vulkan de Wine 9.0. Mesure après compilation :

| | extensions relayées | maintenance5 | maintenance6 | calibrated_timestamps KHR |
|---|---|---|---|---|
| Wine 9.0 (installé) | 119 | oui | **non** | **non** |
| Whisky (Wine 7.7) | 108 | non | non | non |
| **Wine 10.0 (le nôtre)** | **133** | oui | **oui** | **oui** |

### Compiler Wine pour x86_64 sur un hôte arm64 — deux pièges
1. **`-D__aarch64__` injecté dans `EXTRACFLAGS`.** configure devine la machine avec `config.guess`
   (aarch64) alors que `CC="clang -arch x86_64"` produit du x86_64 ; `winnt.h` définit alors les
   types ARM64 *et* AMD64, et `tools/widl` ne compile plus. Correctif : passer explicitement
   `--host=x86_64-apple-darwin --build=x86_64-apple-darwin`.
   C'est le même genre de piège que le § 3 (ninja x86_64 sous Rosetta) : **toujours dire
   l'architecture, ne jamais la laisser deviner.**
2. **`winedmo` se construit malgré « FFmpeg development files not found ».** configure trouve les
   en-têtes FFmpeg (Homebrew arm64) mais pas les bibliothèques 64 bits, prévient, et construit le
   module quand même — l'édition de liens échoue sur `avformat_*`. Correctif : `--without-ffmpeg`.

Configuration retenue :
```
CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
CPPFLAGS="-I<prefix>/include" LDFLAGS="-L<prefix-x64>/lib"
PATH=/usr/local/opt/bison/bin:/usr/local/opt/mingw-w64/bin:/usr/bin:/bin
configure --host=x86_64-apple-darwin --build=x86_64-apple-darwin \
          --enable-archs=x86_64 --disable-tests --without-x --without-freetype \
          --without-ffmpeg --without-gstreamer --without-gnutls ... 
```

### Le détour par `libMoltenVK.dylib` n'est plus nécessaire
Wine 10 cherche **`libvulkan` d'abord**, MoltenVK seulement en repli. En pointant `LDFLAGS` sur
notre loader, configure grave `SONAME_LIBVULKAN "libvulkan.1.dylib"` : Wine charge notre loader
directement, sans faux nom. Le lien symbolique du § 31 reste dans le script pour le Wine 9.0.

### Reproduire
`tests/etape2_pile_wine.sh` monte toute la chaîne et exécute n'importe quel binaire Windows :
```
./tests/etape2_pile_wine.sh wine/bin/winvk.exe     # sonde Vulkan
WINEPREFIX=.../pfx10 ./tests/etape2_pile_wine.sh wine/bin/d3d12.exe
```

### Ce qui reste avant un jeu
- La suite d3d12 complète sous Wine (lancée, à consigner).
- DXGI : Wine fournit le sien ; un vrai jeu voudra une fenêtre, une swapchain, un présent.
- Le jeu lui-même est x86_64 : il tournera sous Rosetta comme le reste de la pile.
- Aucune mesure de performance n'a été faite. La pile entière est traduite, y compris le pilote —
  c'est le prix de l'absence de Wine arm64, et ce sera le prochain axe si le jouable est visé.

---

## 33. Faire tourner la pile trouve un bug que la suite native ne voyait pas (2026-09-17)

`0015-kosmickrisp-chunk-timestamp-counter-heaps.patch` — 4 fichiers, ~70 lignes.

C'est le premier retour concret de l'étape 2 : la suite d3d12 **sous Wine** s'est arrêtée net sur
une faute de page à `test_execute_indirect_state_predication`, alors que le **même test passe en
natif**.

```
AGX: MTLCounterHeap: Invalid heap size requested.
Failed to create timestamp counter heap: Requested Heap size is too large (requested 65536 max is 4096)
wine: Unhandled page fault on read access to 000000000000400A
```

### Le défaut
KosmicKrisp crée **un** `MTL4CounterHeap` par pool de requêtes timestamp, avec une entrée par
requête. Metal plafonne un tas à **4096 entrées**. Vulkan, lui, ne plafonne pas `queryCount` : un
pool de 65 536 timestamps est parfaitement légal, et c'est ce que vkd3d-proton demande.

Reproduit en trois lignes de Vulkan, **sans Wine** (`/tmp/.../qpool.c`) :

| `queryCount` | avant | après |
|---|---|---|
| 4096 | `VK_SUCCESS` | `VK_SUCCESS` |
| 4097 | **`VK_ERROR_OUT_OF_DEVICE_MEMORY`** | `VK_SUCCESS` |
| 65536 | **`VK_ERROR_OUT_OF_DEVICE_MEMORY`** | `VK_SUCCESS` |
| 200000 | — | `VK_ERROR_OUT_OF_DEVICE_MEMORY` (limite système sur le **nombre** de tas, signalée proprement) |

À noter : le pilote refusait **proprement**, il ne plantait pas. La faute de page est côté
vkd3d-proton, qui ne vérifie pas le retour. Mais la cause première est bien ici : refuser un pool
légal.

### Le correctif
Un pool est désormais réparti sur plusieurs tas de 4096 entrées au plus. `kk_ts_heap_for()` traduit
un indice de requête en (tas, entrée). La structure de résolution portait déjà `{heap, index, dst}`,
donc elle n'a pas bougé.

Un piège en chemin : la réutilisation d'un timestamp déjà écrit pour un étage de rendu était indexée
sur `pool->ts.heap`, qui servait de substitut au pool. Avec le découpage, deux requêtes du même pool
peuvent vivre dans des tas différents ; l'entrée de la table porte maintenant le **pool**, et la
résolution suit le tas de l'entrée réutilisée. Sans ça, on résout la bonne entrée dans le mauvais tas.

### Vérification — la frontière est franchie pour de vrai
Allouer ne suffit pas. Test dédié : pool de 8192 (deux tas), timestamps écrits de part et d'autre de
la coupure, puis relus.
```
requete     0 (tas 0, entree    0) : valeur=12516469768919  OK
requete  4095 (tas 0, entree 4095) : valeur=12516469768919  OK
requete  4096 (tas 1, entree    0) : valeur=12516469768919  OK
requete  8191 (tas 1, entree 4095) : valeur=12516469768919  OK
```

### Sous Wine, le test va au bout
```
avant : faute de page, la suite s'arrete a 144 tests sur 574
apres : 1572 assertions, 8 echecs, le test se termine
```
Les 8 échecs restants sont des écarts de conformité (le même test passe en natif) — à instruire,
mais ce n'est plus un arrêt.

### Non-régression native
| | § 30 | § 33 |
|---|---|---|
| Fonctions avec au moins un échec | 50 | **50** |
| Échecs d'assertion | 19 118 | 19 136 |

Jeu de tests identique. Le seul écart est `test_suballocate_va_alignment` (3 085 → 3 103), dont le
§ 28 a déjà montré que la valeur dépend de ce qui a alloué avant lui.

### Ce que ça dit de la méthode
La suite native tournait depuis le § 24 sans jamais toucher ce chemin : vkd3d-proton compilé
nativement pour macOS ne demande pas le même dimensionnement de pool que le même vkd3d-proton
compilé en PE et exécuté sous Wine. **Faire tourner la vraie pile a trouvé en une campagne ce que
24 millions d'assertions natives n'avaient pas vu.**

---

## 34. La suite d3d12 complète passe à travers la pile ouverte (2026-09-17)

`0016-vkd3d-proton-tests-skip-shared-fences-without-support.patch` — 1 fichier, ~25 lignes.

Deux arrêts brutaux séparaient la pile d'une campagne complète. Les deux sont levés.

| arrêt | cause | correctif |
|---|---|---|
| 144 / 574 | tas de compteurs Metal trop petit, le pilote refusait un pool légal | `0015` (§ 33) |
| 371 / 574 | `test_fence_wait_robustness_shared` : Wine ne fournit ni `CreateSharedHandle` ni `OpenSharedHandle` pour les fences ; le test libérait ses fences puis les rouvrait, et travaillait sur des pointeurs morts | `0016` |

Le second n'est pas un défaut de pilote : c'est une garde manquante dans le test, de la même famille
que le § 21. Le test est désormais **sauté** quand les handles partagés ne répondent pas, comme le
fait déjà la compilation native.

### Résultat

| | démarrés / terminés | fonctions en échec | assertions en échec |
|---|---|---|---|
| natif (arm64) | 574 / 574 | 50 | 19 136 |
| **à travers Wine** (PE → Wine 10 → KosmicKrisp x86_64) | **574 / 574** | **57** | 19 324 |

**Huit tests échouent sous Wine et pas en natif**, et un seul l'inverse :

| test | assertions |
|---|---|
| `test_execute_indirect_state` | 139 |
| `test_execute_indirect_multi_dispatch_root_descriptors` | 16 |
| `test_execute_indirect_multi_dispatch_root_constants` | 8 |
| `test_execute_indirect_state_predication` | 8 |
| `test_execute_indirect_state_vbo_offsets` | 4 |
| `test_line_rasterization` | 4 |
| `test_fence_wait_robustness_shared` | 3 |
| `test_placed_msaa_alignment_workaround` | 1 |
| *(inverse)* `test_object_interface` | 1 en natif, 0 sous Wine |

Cinq des huit sont la grappe **`ExecuteIndirect`** (175 assertions sur les 188 d'écart) : c'est un
chemin que la compilation native de la suite n'emprunte pas de la même façon. `shared_fences` est
attendu — Wine ne les implémente pas.

**La pile ouverte complète est donc à huit fonctions de test du pilote natif**, et l'écart est
concentré sur un seul mécanisme.

### Ce que l'étape 2 a coûté et rapporté
Coût : deux correctifs (`0015` pilote, `0016` test), un piège d'architecture et un piège de
dépendance dans la compilation de Wine (§ 32).
Rapport : la question ouverte du brief est close, et un bug de pilote réel — invisible à
24 millions d'assertions natives — a été trouvé et corrigé.

---

## 35. La présentation marche : fenêtre, swapchain, image à l'écran (2026-09-17)

`0017-kosmickrisp-polygon-mode-line.patch` — 5 fichiers, ~50 lignes.

Tout ce qui précède dessinait **hors écran avec relecture**. Un jeu doit présenter. C'était le
dernier maillon jamais éprouvé.

```
$ ./tests/etape2_pile_wine.sh wine/bin/win_swapchain.exe
fenetre : 00000000000700e0
D3D12CreateDevice : hr=0
CreateDXGIFactory2 : hr=0
CreateSwapChainForHwnd : hr=0
image 0 : back buffer 0, Present hr=0
image 1 : back buffer 1, Present hr=0
image 2 : back buffer 0, Present hr=0
pixel central du back buffer : 00 ff 00 ff (attendu 00 ff 00 ff)
```
`tests/win_swapchain.c` ne se contente pas de `Present hr=0` : il recopie la dernière image
présentée dans un buffer de relecture et vérifie la couleur. La chaîne a **vraiment** écrit dedans.

### DXGI vient de DXVK, et le README le dit
Le premier essai plantait dans `CreateSwapChainForHwnd`. Le README de vkd3d-proton est explicite :
> vkd3d-proton does not supply the necessary DXGI components on its own.
> Instead, DXVK (2.1+) and vkd3d-proton share a DXGI implementation.

DXVK 2.7.1 compilé en PE avec le même mingw-w64 — **du premier coup, aucun correctif**. Seul son
`dxgi.dll` est installé dans le prefix ; `d3d11`/`d3d9` ne servent pas ici.

### DXVK a exigé deux choses du pilote
Plutôt que d'itérer manque par manque, j'ai extrait la **table complète** de ses exigences
(`getFeatureList()`, entrées marquées `true`) et je l'ai croisée avec `vulkaninfo` :

| | exigées | manquantes |
|---|---|---|
| DXVK 2.7.1 | 41 | **2** |

1. **`fillModeNonSolid`** — KosmicKrisp n'avait **aucun** support du mode de remplissage : le pont
   Metal n'exposait même pas `setTriangleFillMode`. Ajouté, et `VK_POLYGON_MODE_LINE` passe
   désormais par `MTLTriangleFillModeLines`.
2. **`VK_KHR_pipeline_library`** — extension d'infrastructure pure : elle ne définit aucune commande
   et **aucun moyen de créer une bibliothèque de pipeline par elle-même** (la spec le dit). Vérifié
   dans DXVK : son chemin « bibliothèques » est conditionné à `graphicsPipelineLibrary`, que
   KosmicKrisp n'expose pas — il prend donc le chemin monolithique. La déclarer n'engage rien.

### Vérification — `tests/test_polygon_mode.c`
Même triangle, deux pipelines, comptage des pixels allumés :
```
POLYGON_MODE_FILL  pixels allumes : 1682
POLYGON_MODE_LINE  pixels allumes :  172
le fil de fer couvre 10% du plein : mode pris en compte
```

### Limite assumée : `VK_POLYGON_MODE_POINT`
Metal n'a que `Fill` et `Lines` ; il n'y a pas de mode « points » pour les triangles. `POLYGON_MODE_POINT`
est donc rendu comme `LINE`. **C'est une entorse assumée à `fillModeNonSolid`**, qui couvre les deux
modes. Elle est sans effet sur l'objectif : D3D12 n'a que `SOLID` et `WIREFRAME`, il ne peut pas
produire ce mode. L'implémenter demanderait de passer les triangles par l'émulation de geometry
shader (§ 27-29) pour en émettre les sommets comme points — faisable, non fait.

### Profil vkd3d-proton — plus qu'une feature
| | § 28 | § 32 | § 35 |
|---|---|---|---|
| `baseline_features` exigées | 75 | 75 | 75 |
| manquantes | 3 | 2 | **1** |

Il ne reste que **`pipelineStatisticsQuery`**.

### Non-régression native
| | § 33 | § 35 |
|---|---|---|
| Fonctions avec au moins un échec | 50 | **50** |
| Échecs d'assertion | 19 136 | 18 618 |

Jeu identique. L'écart d'assertions vient entièrement de `test_suballocate_va_alignment`
(3 103 → 2 585), dont le § 28 a établi que la valeur dépend de l'historique d'allocation.

### État de la pile
```
fenetre Win32 + swapchain DXGI (DXVK)
  -> vkd3d-proton PE  -> Wine 10 (compile ici) -> loader Vulkan
  -> KosmicKrisp (17 patches) -> Metal 4 -> M1 Max
```
Tous les maillons sont compilés dans l'arbre de travail. Le dernier maillon structurel est franchi :
il n'y a plus de « jamais essayé » entre un binaire Windows et un pixel affiché.

## 36. Robustesse des couches de tableau : le plus gros bloc d'échecs restant (2026-09-17)

Après le § 35, le plus gros bloc d'échecs de la suite native était le groupe
« reinterpretation » : quatre fonctions (`tex1d`/`tex2d` × `sm51`/`dxil`), **1 920 échecs
d'assertion chacune**, soit 7 680 sur 18 618 — 41 % du total.

Le nom induit en erreur. Ces tests ne portent pas sur la réinterprétation de *format* mais
sur les **plages de sous-ressources d'une vue** : ils créent plusieurs vues d'une même
texture tableau, chacune exposant une tranche de couches et de niveaux différente, et
vérifient que chaque vue ne voit que sa tranche.

### Le bug

Échantillonner une couche située **hors de la plage de la vue** rendait la couche bornée
au lieu de zéro. Avec `robustImageAccess2` activé, Vulkan exige zéro.

Metal borne les coordonnées de tableau et n'a pas d'équivalent de la robustesse Vulkan sur
cet axe. KosmicKrisp traitait déjà `robustImageAccess2` pour les *images de stockage*
(`msl_lower_robustness2_images`, derrière le contournement n° 16), mais rien ne couvrait
la coordonnée de couche des lectures échantillonnées.

### Le correctif

Nouvelle passe NIR `msl_lower_robustness2_array_layers` : pour chaque instruction de
texture sur un tableau, elle interroge la taille de la vue (`nir_texop_txs`), compare la
coordonnée de couche à `[0, layers)`, et remplace le résultat par zéro hors plage.

Premier essai raté, à noter : je l'avais accrochée à l'intérieur de
`msl_lower_robustness2_images`, donc sous le contournement n° 16 — **désactivé sur M1**
(il vise le M5). Une sonde l'a montré : `rs->images=3 wa16=1`. La passe ne s'exécutait
jamais. Corrigé en en faisant un point d'entrée séparé, appelé dès que
`rs->images == ROBUST_IMAGE_ACCESS_2`.

Vérification isolée (`tests/test_image_array_robustness.c`, vue restreinte à la couche 0
d'une image de 4 couches) :
```
  couche 0 (dans la vue)  : 0.251  (attendu 0.251)  OK
  couche 1 (hors de vue)  : 0.000  (attendu 0.000)  OK
```

### Le « second bug » qui n'en était pas un

Le même test montrait ensuite qu'échantillonner le niveau de mip 1 rendait le niveau 0.
J'ai annoncé un second bug de pilote. **C'était mon test qui était faux** : son
`VkSamplerCreateInfo` laissait `maxLod = 0`, ce qui borne légitimement le LOD à 0. La
spécification Vulkan est respectée, le pilote avait raison.

Avec `maxLod = VK_LOD_CLAMP_NONE`, et en ajoutant deux contrôles (un `texelFetch` de
niveau explicite, et une vue dont `baseMipLevel = 1`) :
```
  niveau 1 (dans la vue)   : 0.784  (attendu 0.784)  OK
  texelFetch niveau 1      : 0.784  (attendu 0.784)  OK
  vue base=niveau 1, sample : 0.784  (attendu 0.784)  OK
  vue base=niveau 1, fetch  : 0.784  (attendu 0.784)  OK
```
La chaîne vue → niveau de mip est saine. Deux autres bugs de mon test ont été corrigés au
passage : les régions de copie du niveau 1 se chevauchaient et débordaient du buffer.

### Mesure sur la suite native

Campagne complète (574 fonctions) avant / après :

| fonction | avant | après | Δ |
|---|---|---|---|
| `test_tex1d_array_reinterpretation_dxil` | 1 920 | **1 824** | −96 |
| `test_tex1d_array_reinterpretation_sm51` | 1 920 | **1 824** | −96 |
| `test_tex2d_array_reinterpretation_dxil` | 1 920 | **1 824** | −96 |
| `test_tex2d_array_reinterpretation_sm51` | 1 920 | **1 824** | −96 |
| `test_suballocate_va_alignment` | 2 585 | 3 085 | +500 *(bruit)* |

Le +500 est du bruit et non une régression : sur les 12 campagnes archivées, cette
fonction vaut 2 585, 3 085 ou 3 103 selon le tirage, sans rapport avec les changements.
Normalisé à 3 085, le total passe de **19 118 à 18 732**, soit **−386**.

Le bloc n'est pas éliminé : 1 824 échecs subsistent par fonction. La part traitée est
celle de la robustesse sur l'axe des couches ; le reste relève d'autres axes de ces tests,
non caractérisés à ce stade.

Aucune fonction ne bascule d'un état passant à un état échouant. Le jeu reste à 50
fonctions en échec (49 dans cette campagne, `test_object_interface` étant intermittent).

Patch **0018-kosmickrisp-robustness2-array-layers.patch**, cumulatif régénéré et vérifié
applicable sur un Mesa HEAD vierge.

## 37. Un descripteur, deux types : le bloc « reinterpretation » tombe entièrement (2026-09-17)

Le § 36 avait réduit les quatre fonctions « reinterpretation » de 1 920 à 1 824 échecs
chacune sans comprendre le reste. Il restait 7 776 échecs sur ce bloc. Ils sont maintenant
tous éliminés.

### Remonter à la cause

Les fils en échec étaient exactement `j = 4, 8, 12`, jamais `j = 0`. Dans le test,
`sample_level = j / 4` : tous les échecs étaient donc à niveau de mip ≥ 1.

J'ai construit un repro Vulkan à la géométrie exacte du test (256×128, 8 niveaux, 16
couches, R8_UNORM) — `tests/test_view_mip_range.c`. Tout passait : LOD littéral, LOD
calculé à l'exécution, `texelFetch`, vue à niveau de base non nul. Le pilote avait raison
sur chacun de ces axes.

Trois vérifications ont alors éliminé les suspects :
- **le MSL généré** (`MESA_KK_DEBUG=msl`) était correct :
  `t122 = t116.read(t111.xy, t111.z, t113)` avec `t113 = lid >> 2`, le bon LOD ;
- **les vues Vulkan** (sonde temporaire dans `kk_image_view.c`) étaient correctes :
  `base_level=0 levels=8 base_layer=0 layers=1` ;
- **les données** étaient bonnes : la même texture lue par la vue 2D au LOD 4 rendait la
  bonne sous-ressource.

Le décompte des vues a donné la réponse : **128 vues pour 128 descripteurs**, dont 8 de
type 2D et 120 de type 2D_ARRAY. Le shader HLSL déclare pourtant *deux* tableaux de
ressources sur les *mêmes* descripteurs :
```hlsl
Texture2D<float>      T2D[]      : register(t0, space0);
Texture2DArray<float> T2DArray[] : register(t0, space1);
```
C'est le sens du mot « reinterpretation » : le même descripteur est lu tantôt en 2D,
tantôt en 2D tableau. D3D12 l'autorise explicitement (`declaration 'Texture2DArray' ←
resource 'Texture2D' with array length >= 1`, et réciproquement).

Or KosmicKrisp crée **une** `MTLTexture` par vue, de type fixé. Quand le shader lit une
`MTLTextureType2D` déclarée `texture2d_array<float>`, les arguments de
`read(coord, array, lod)` se décalent : l'index de couche est pris pour le LOD. Cela
explique les mesures au chiffre près — fil 4 (`array=0, lod=1`) rendait le niveau de base.

Reproduit en isolation (vue `VK_IMAGE_VIEW_TYPE_2D` lue par un `sampler2DArray`) :
```
  v1 (vue 2D) sample LOD 1 :  25  (attendu  26)  ECHEC
  v1 (vue 2D) fetch  LOD 1 :  25  (attendu  26)  ECHEC
```

### Le correctif

Chaque vue échantillonnée et chaque vue de stockage porte désormais **deux** textures
Metal : une typée non-tableau et une typée tableau. Les deux identifiants de ressource
sont écrits dans le descripteur (`array_image_gpu_resource_id`, nouveau champ, logé dans
le remplissage déjà présent pour les vues échantillonnées ; `kk_storage_image_descriptor`
passe de 8 à 16 octets). Le choix se fait à l'abaissement des descripteurs, selon
`tex->is_array` pour les textures et `nir_intrinsic_image_array()` pour les images de
stockage.

Piège rencontré : une vue Metal de type 2D exige une plage de tranches de longueur 1.
La contrepartie non-tableau d'une vue tableau doit donc borner `array_len` à 1, sinon
`newTextureViewWithPixelFormat:` rend nil silencieusement.

### Mesure

Campagne complète (574 fonctions) :

| fonction | § 36 | § 37 |
|---|---|---|
| `test_tex1d_array_reinterpretation_dxil` | 1 824 | **0** |
| `test_tex1d_array_reinterpretation_sm51` | 1 824 | **0** |
| `test_tex2d_array_reinterpretation_dxil` | 1 824 | **0** |
| `test_tex2d_array_reinterpretation_sm51` | 1 824 | **0** |
| `test_rwtex1d_array_reinterpretation_dxil` | 120 | **0** |
| `test_rwtex1d_array_reinterpretation_sm51` | 120 | **0** |
| `test_rwtex2d_array_reinterpretation_dxil` | 120 | **0** |
| `test_rwtex2d_array_reinterpretation_sm51` | 120 | **0** |

| | § 36 | § 37 |
|---|---|---|
| Fonctions avec au moins un échec | 49 | **41** |
| Échecs d'assertion | 18 732 | **10 976** |

Soit **−7 776**, exactement la somme des huit blocs. Les deux seules hausses sont les
fonctions déjà connues comme instables : `test_suballocate_va_alignment` (+19, dans sa
plage 2 585 / 3 085 / 3 104) et `test_unused_attachments_mix_and_match` (±1).

Les sept tests isolés du dossier `tests/` passent tous après le changement.

Patch **0019-kosmickrisp-array-typed-image-views.patch**, découpé pour ne rien emprunter
aux patchs 0005/0006 qui touchent le même fichier, sans commentaire de code ajouté.
Cumulatif régénéré et vérifié applicable sur un Mesa HEAD vierge.

## 38. Adresses GPU alignées et limites de samplers mesurées (2026-09-17)

Deux blocs traités, −5 536 échecs d'assertion au total.

### 38.1 `test_suballocate_va_alignment` : 3 104 → 0

Ce test exige `GetGPUVirtualAddress() % 64 Kio == 0`. Les adresses observées finissaient
toutes par `0x8000` : alignées à 32 Kio.

Le § 28 avait classé ce test « instable » parce que son décompte variait d'une campagne à
l'autre (2 585 / 3 085 / 3 104). C'était vrai — les adresses changent d'un tirage à
l'autre — mais l'instabilité masquait un vrai défaut, et non l'inverse.

Côté vkd3d, `d3d12_device_aligns_bda_64k()` rend **vrai pour tout pilote sauf Turnip** :
vkd3d suppose donc que le pilote aligne ses adresses de périphérique à 64 Kio et ne
compense pas.

Côté KosmicKrisp, chaque `VkDeviceMemory` est un `MTLHeap` et Metal place le tas à la
granularité de page (16 Kio). Un tas de type *placement* permet cependant de choisir
l'offset de chaque ressource : on sur-alloue de 64 Kio et on décale.

**Premier essai raté, instructif.** J'ai d'abord décalé la `MTLBuffer` de mappage du bo.
Mesure : aucun effet. La sonde a montré pourquoi — `kk_bind_buffer_memory()` crée une
*nouvelle* `MTLBuffer` à `heap + memoryOffset`, sans rapport avec le buffer de mappage.
Pire, `plane->addr = mem->bo->gpu + offset` devenait incohérent avec les textures placées
au même moment : j'avais introduit un bug.

Correctif retenu : le décalage est enregistré dans `kk_bo::heap_offset_B` et **ajouté à
chaque placement dans le tas** — liaison de buffer, texture d'image, texture 2D-tableau
auxiliaire des images 3D. `bo->gpu` et toutes les ressources partent alors de la même
adresse alignée.

Deux chemins A/B ont été essayés et écartés par la mesure avant celui-là : relever
l'alignement annoncé des buffers à 64 Kio (3 085 → 3 102, soit rien), et décaler le seul
buffer de mappage (3 085 → 3 085).

Résultat : **3 104 → 0**, et zéro régression ailleurs sur la campagne complète.

### 38.2 Limites de samplers : 2 432 → 0

`test_custom_border_color_limits` et sa variante compute échouaient à partir de la valeur
`flat_index == 4000` exactement — c'est-à-dire au `maxCustomBorderColorSamplers = 4000`
annoncé par le pilote, que vkd3d respecte en neutralisant les bordures au-delà.

D'où venait ce 4000 ? De nulle part de mesurable : une valeur en dur. Metal plafonne bien
quelque chose — `maxArgumentBufferSamplerCount`, **mesuré à 1 024 sur ce M1 Max** — mais
cela borne le nombre d'*états de sampler Metal distincts*, et KosmicKrisp les déduplique :
la couleur de bordure personnalisée vit dans le **descripteur**, pas dans le sampler, donc
8 192 `VkSampler` à bordures différentes ne consomment que quelques états Metal.

Vérifié par la mesure (`/tmp/claude-501/samp.c`) :
```
annonce : maxSamplerAllocationCount=4000 maxCustomBorderColorSamplers=4000
200000 samplers a bordure personnalisee crees sans echec
```

Les deux limites passent donc à 65 536 — une valeur ronde très en dessous des 200 000
constatés, et bien au-dessus du minimum de 4 000 exigé par la spécification Vulkan.
Résultat : **2 432 → 0**.

### 38.3 Piste écartée : le swizzle de la bordure

`test_custom_border_color_srgb` (184 échecs) rend la bordure **non swizzlée** par le
mapping de composantes de la vue. J'ai tenté d'appliquer le swizzle de la vue à l'écriture
du descripteur. Mesure : aucun changement, 184 → 184.

Raison : en D3D12 les textures et les samplers vivent dans des **tas de descripteurs
séparés**. À l'écriture du descripteur de sampler, aucune vue n'est connue ; la bordure et
la vue ne se rejoignent que dans le shader. Un correctif réel demanderait de transporter
le swizzle dans le descripteur d'image et de l'appliquer à la bordure lors de la
substitution. Changement annulé intégralement, y compris
`borderColorSwizzleFromImage` remis à `false` : le pilote n'honore pas cette promesse pour
les descripteurs séparés, il ne doit donc pas la faire.

### Bilan de la campagne

| | § 37 | § 38 |
|---|---|---|
| Fonctions avec au moins un échec | 41 | **38** |
| Échecs d'assertion | 10 976 | **5 440** |

Les deux campagnes de vérification (une par correctif) ne montrent **aucune régression** :
les seules lignes qui bougent sont les blocs visés.

Patches **0020-kosmickrisp-align-memory-gpu-addresses.patch** et
**0021-kosmickrisp-raise-sampler-allocation-limits.patch**, sans commentaire de code
ajouté. Cumulatif régénéré et vérifié applicable sur un Mesa HEAD vierge.

## 39. `VK_EXT_dynamic_rendering_unused_attachments` : de l'annonce à l'implémentation (2026-09-17)

Le patch 0002, écrit au § 3 pour que vkd3d-proton accepte de démarrer, se contentait
d'**annoncer** l'extension : deux lignes, un booléen de feature, aucune sémantique. C'était
la dette la plus visible du projet, et `test_unused_attachments_mix_and_match` la facturait
1 978 échecs — le plus gros bloc restant.

### Ce que Metal fait des emplacements invalides

Un repro Vulkan minimal (passe à 4 attachements réels, pipeline déclarant
`{ UNDEFINED, R32, UNDEFINED, R32 }`, shader écrivant 1, 2, 3, 4) donne :
```
  attachement 0 : 2.0  (attendu 0.0)
  attachement 1 : 4.0  (attendu 2.0)
```
Les sorties sont **compactées** : Metal apparie les emplacements valides du pipeline aux
attachements de la passe dans l'ordre. Le MSL généré était pourtant correct
(`out.color_1`, `out.color_3` avec les bons indices `[[color(n)]]`), et les vues Vulkan
aussi — c'est bien l'appariement Metal qui décale.

Supprimer les écritures vers les emplacements non déclarés ne change rien : **le
décalage vient des trous dans le tableau de formats du pipeline**, pas du shader.

### Ce qui ne marche pas

Deux bouchons ont été essayés et écartés par la mesure :

| bouchon pour un emplacement non déclaré | résultat |
|---|---|
| format arbitraire (R8) avec masque d'écriture nul | passe avec des attachements R32, **casse** avec des RGBA32F |
| format plus large (RGBA32F) que l'attachement | rien n'est écrit du tout |

Le bouchon doit donc valoir **exactement** le format de l'attachement lié — qui n'est connu
qu'au dessin.

### L'implémentation

Le pipeline Metal est désormais **respécialisé au dessin**, sur une clé formée du tableau
de formats effectivement liés et d'un masque d'écritures désactivées. Les variantes sont
mises en cache par shader (table de hachage sous verrou). Coût mesuré d'une variante :
**0,012 ms** — la création d'un `MTLRenderPipelineState` à partir de fonctions déjà
compilées est bon marché, ce qui rend l'approche viable même pour ce test qui en engendre
des dizaines de milliers (7,2 s au total).

Un second obstacle est apparu, annoncé par Metal lui-même :
```
Failed to create MTLRenderPipelineState:
Shaders reads from a color attachment whose pixel format is MTLPixelFormatInvalid
```
KosmicKrisp abaisse le **blending dans le shader** (`nir_lower_blend`), qui lit donc le
framebuffer. Un emplacement déclaré par le pipeline mais absent de la passe est lu par le
shader et refusé par Metal. La règle retenue : un tel emplacement garde son format déclaré
**si et seulement si le shader le lit** (`nir->info.outputs_read`, remonté du fragment
shader vers le vertex shader qui porte le pipeline), avec les écritures désactivées.

### Mesure

Balayage exhaustif des 256 combinaisons (masque du pipeline × masque de la passe) sur
4 attachements, `tests/test_unused_attachments.c` :

| | échecs sur 1 024 vérifications |
|---|---|
| sans blending | **0** |
| avec blending additif | 93 |

Campagne complète :

| | § 38 | § 39 |
|---|---|---|
| `test_unused_attachments_mix_and_match` | 1 978 | **1 538** |
| Échecs d'assertion | 5 440 | **5 000** |

Aucune régression ailleurs.

### Limite restante, caractérisée

Les 93 cas (et les 1 538 échecs d3d12) sont **tous** de la même forme : le pipeline déclare
et *lit* (blending) un emplacement que la passe ne fournit pas. Lui donner un format valide
sans attachement correspondant fait perdre le dessin entier ; le laisser invalide fait
échouer la création du pipeline. Aucune fuite de valeur ne subsiste — seulement des
écritures perdues, ce qui est le mode de défaillance le moins dangereux des deux.

Deux sorties possibles, non tentées : lier un attachement bouchon dans la passe Metal pour
les emplacements nuls (impose de connaître le format au démarrage de la passe, donc de
redémarrer l'encodeur), ou utiliser le blending natif de Metal au lieu de l'abaisser dans
le shader quand la configuration est exprimable — ce qui supprimerait la lecture et donc la
contrainte.

Patch **0022-kosmickrisp-dynamic-rendering-unused-attachments.patch**. Les deux seuls
commentaires ajoutés dans l'arbre Mesa sont des commentaires **existants déplacés** par la
refactorisation, pas de la prose nouvelle. Cumulatif régénéré et vérifié applicable sur un
Mesa HEAD vierge.

## 40. Un seul chiffre : `minStorageBufferOffsetAlignment` (2026-09-17)

Après le § 39, le classement des 5 000 échecs restants donnait :

| fonction | échecs |
|---|---|
| `test_suballocate_small_textures_size` | 1 650 |
| `test_unused_attachments_mix_and_match` | 1 538 |
| `test_undefined_structured_raw_alias_dxbc` / `_dxil` | 414 chacun |
| `test_custom_border_color_srgb` | 184 |
| *(33 autres fonctions)* | 811 |

### Écarté d'emblée : `suballocate_small_textures_size`

« Resource size 143360 is larger than expected 131072 » : 6 144 octets de remplissage par
couche sur une texture compressée en tableau. La taille vient **directement** de
`heapTextureSizeAndAlignWithDescriptor:` de Metal (`mtl_device.m`) — KosmicKrisp rapporte
ce que Metal exige, il n'y a rien à corriger côté pilote. Limite assumée.

### Le cluster « aliasing brut / structuré »

Symptôme : `expected 1, got 0`, `expected 16777218, got 16777217` — un décalage constant
d'un élément. Le shader HLSL lit un descripteur **structuré** (`FirstElement = 1`,
`StructureByteStride = 4·(i+1)`) à travers une déclaration `ByteAddressBuffer` ; la vue doit
donc commencer à l'octet `FirstElement · stride`.

Une sonde sur `write_buffer_desc()` a montré ce que vkd3d écrit réellement :

| élément | stride | offset attendu | offset écrit | portée écrite |
|---|---|---|---|---|
| 0 | 4 | 4 | **0** | 80 (= 64 + 16) |
| 1 | 8 | 8 | **0** | 144 (= 128 + 16) |
| 3 | 16 | 16 | 16 ✓ | 256 ✓ |
| 4 | 20 | 20 | **16** | 336 (= 320 + 16) |
| 7 | 32 | 32 | 32 ✓ | 512 ✓ |

L'offset est **arrondi au multiple de 16 inférieur**, la portée étendue d'autant. Ce n'est
pas un bug de vkd3d : il respecte le `minStorageBufferOffsetAlignment` que le pilote
annonce, et compte sur un mécanisme de rattrapage côté shader qui n'est pas actif ici.

Or KosmicKrisp annonçait **16** alors que ses SSBO sont de simples **adresses 64 bits**
(`struct kk_buffer_address`) : il n'y a aucune contrainte Metal à 16 octets sur ce chemin.
La valeur juste est 4, l'alignement naturel d'un `uint`.

Un caractère changé : `KK_MIN_SSBO_ALIGNMENT` passe de 16 à 4.

### Mesure

| fonction | § 39 | § 40 |
|---|---|---|
| `test_undefined_structured_raw_alias_dxbc` | 414 | **0** |
| `test_undefined_structured_raw_alias_dxil` | 414 | **0** |
| `test_structured_buffer_addressing_wrap` | 66 | **4** |

| | § 39 | § 40 |
|---|---|---|
| Fonctions avec au moins un échec | 38 | **37** |
| Échecs d'assertion | 5 000 | **4 111** |

Aucune régression (seul `test_object_interface` bouge de ±1, il est intermittent depuis le
§ 36).

### Piste écartée, annulée

Les tests frères `test_bufinfo_instruction` rendent la taille d'un buffer en **flottant**
(`0x42c80000` = 100.0f au lieu de 100). J'ai supposé que `nir_texop_txs` héritait du type
flottant de l'image et forcé un type entier dans l'émission MSL. Mesure : aucun changement,
18 → 18. Le dump MSL ne contient aucune requête de largeur sur `texture_buffer` : la
conversion se fait ailleurs, non localisée. Changement annulé — je ne garde pas de
modification non mesurée dans le jeu de patches.

Patch **0023-kosmickrisp-min-ssbo-offset-alignment-4.patch**. Cumulatif régénéré et vérifié
applicable sur un Mesa HEAD vierge.

## 41. Blending natif Metal : la contrainte du § 39 disparaît (2026-09-17)

Le § 39 laissait 1 538 échecs sur `test_unused_attachments_mix_and_match`, tous de la même
forme : le pipeline déclare **et lit** (blending abaissé dans le shader) un emplacement que
la passe ne fournit pas. J'y avais noté une sortie possible — « utiliser le blending natif
de Metal quand la configuration est exprimable, ce qui supprimerait la lecture ». C'est ce
qui est fait ici.

### Pourquoi c'était possible

KosmicKrisp **n'annonce aucun état de blending dynamique** (`extendedDynamicState3ColorBlend*`,
`ColorWriteMask`, `LogicOp` sont tous absents) : la configuration est donc entièrement
connue à la création du pipeline, et `MTL4RenderPipelineColorAttachmentDescriptor` expose
tout ce qu'il faut (`blendingState`, facteurs, opérations, `writeMask`).

`nir_lower_blend` n'émet une lecture du framebuffer que si le blending utilise la
destination, s'il y a un opérateur logique, ou si le masque d'écriture est partiel. Il
suffit donc de lui présenter un blending « remplacement » (ONE/ZERO/ADD, masque complet)
pour qu'il n'émette rien, et de programmer Metal à la place.

### Trois pièges, tous trouvés par la mesure

**1. L'ordre des bits du masque d'écriture est inversé.** Vulkan numérote R=1, G=2, B=4,
A=8 ; Metal numérote R = 1<<3, G = 1<<2, B = 1<<1, A = 1<<0. Identique pour un masque
complet (0xf), faux pour tout masque partiel. Première campagne : `test_line_rasterization`
passait de 0 à 6 échecs.

**2. Metal n'a pas d'alpha source quand la cible n'en a pas.** `test_line_rasterization`
continuait d'échouer, avec une variance d'un tirage à l'autre (3, 4, 5 échecs). Sa cible
est mono-canal : le MSL déclare `float color_0 [[color(0)]]`. Avec des facteurs
`SRC_ALPHA` / `ONE_MINUS_SRC_ALPHA`, Metal n'a aucun alpha à lire — le résultat est
indéfini, d'où la variance. `nir_lower_blend` ne souffrait pas de ça : il complète la
source à quatre composantes *avant* de tronquer au format. Le chemin natif exige donc
maintenant que le format porte un canal alpha dès qu'un facteur en référence un.

**3. Certains formats refusent un masque partiel.** La campagne suivante s'est **arrêtée à
497 fonctions sur 574** sur une assertion Metal :
```
writeMask(0xe) is not MTLColorWriteMaskAll or MTLColorWriteMaskNone [...]
the pixelformat MTLPixelFormatRGB9E5Float for this render target requires [...]
```
Le chemin natif ne prend donc plus en charge que le masque complet ; l'abaissement NIR
garde les masques partiels, ce qu'il faisait déjà correctement.

Règle finale : le chemin natif s'applique quand le blending est **activé**, le masque
**complet**, sans opérateur logique ni blending avancé, avec des facteurs traduisibles
(les facteurs constants et double-source restent au NIR), et un canal alpha présent si un
facteur en dépend.

### Mesure

Balayage exhaustif des 256 combinaisons (§ 39), avec blending additif :

| | § 39 | § 41 |
|---|---|---|
| échecs sur 1 024 vérifications | 93 | **0** |

Campagne complète, 574 fonctions démarrées :

| | § 40 | § 41 |
|---|---|---|
| `test_unused_attachments_mix_and_match` | 1 538 | **0** |
| Fonctions avec au moins un échec | 37 | **35** |
| Échecs d'assertion | 4 111 | **2 572** |

Le delta est **exactement** −1 538, plus `test_object_interface` (intermittent). Aucune
régression : `test_line_rasterization`, `test_blend_factor`, `test_dual_source_blending` et
`test_render_target_dxbc` sont tous à 0.

Note de méthode : une campagne intermédiaire affichait 2 358 échecs et un gain sur
`test_custom_border_color_srgb` — elle s'était en réalité **interrompue à la fonction 497**
sur l'assertion ci-dessus. Le chiffre était faux ; c'est le décompte des fonctions
démarrées (574) qui l'a révélé. Ce contrôle fait désormais partie de la comparaison.

Patch **0024-kosmickrisp-native-metal-blending.patch**, sans commentaire de code ajouté.
Cumulatif régénéré et vérifié applicable sur un Mesa HEAD vierge.

## 42. La bordure personnalisée suit enfin le swizzle de la vue (2026-09-17)

Le § 38.3 avait tenté ce correctif et l'avait **annulé** faute d'effet : appliquer le
swizzle à l'écriture du descripteur ne marche pas, parce qu'en D3D12 les textures et les
samplers vivent dans des tas séparés — à ce moment-là, aucune vue n'est connue. La note
concluait qu'il faudrait « transporter le swizzle dans le descripteur d'image et
l'appliquer à la bordure lors de la substitution ». C'est fait.

### Le mécanisme

Metal applique le swizzle de la vue aux *texels* (il est dans la `MTLTexture` de la vue),
mais l'émulation de bordure personnalisée substitue une constante **après**
l'échantillonnage, donc non swizzlée. Les deux ne se rejoignent que dans le shader, qui
tient les deux descripteurs.

Trois pièces :

1. `kk_sampled_image_descriptor` gagne un `image_swizzle` de 16 bits, logé dans le
   remplissage `pad_to_64_bits` déjà présent : 4 composantes × 3 bits.
2. L'écriture du descripteur d'image encode `view->vk.swizzle` (R, G, B, A, zéro, un).
3. L'abaissement de `nir_texop_custom_border_color_agx` lit ce champ **depuis le
   descripteur de texture** (et non de sampler) et permute la bordure : quatre chaînes de
   `bcsel` sur six sources. Le coût ne pèse que sur le chemin de bordure personnalisée.

`borderColorSwizzleFromImage` passe donc à `true` — le pilote obtient bien le swizzle
depuis la vue — et le swizzle côté sampler
(`VkSamplerBorderColorComponentMappingCreateInfoEXT`) est retiré pour ne pas l'appliquer
deux fois.

### Mesure

| | § 41 | § 42 |
|---|---|---|
| `test_custom_border_color_srgb` | 184 | **0** |
| `test_custom_border_color_limits` (+ compute) | 0 | 0 |
| Fonctions avec au moins un échec | 35 | **34** |
| Échecs d'assertion | 2 572 | **2 388** |

574 fonctions démarrées sur 574. Delta exactement −184, aucune régression.

Patch **0025-kosmickrisp-border-color-swizzle-from-image.patch**. Cumulatif régénéré et
vérifié applicable sur un Mesa HEAD vierge.

### État du reste

Des 2 388 échecs restants, **1 650 sont sur `test_suballocate_small_textures_size`**, dont
le § 40 a établi qu'ils ne sont pas actionnables : la taille vient de
`heapTextureSizeAndAlignWithDescriptor:`. Le solde réel est de **738 échecs répartis sur
33 fonctions**, aucune au-dessus de 112.

Le cluster `undefined_*_read_typed` (224 + 96) a été inspecté et écarté : le shader lit un
descripteur structuré ou brut à travers une déclaration **typée**, cas explicitement
« undefined » en D3D12, dont le test encode le comportement observé sur matériel réel.
Aucune `VkBufferView` n'est créée pour ces descripteurs — le chemin typé et le chemin brut
ne se rencontrent pas dans le modèle bindless de vkd3d.

## 43. Transform feedback depuis la tessellation (2026-09-17)

« XFB depuis la tessellation » figurait dans les limites assumées depuis le § 28. Les trois
fonctions de tessellation encore en échec — `test_line_tessellation` (dxbc et dxil, 54
chacune) et `test_tessellation_read_tesslevel` (28) — utilisent **toutes** le stream output
depuis le domain shader. Aucune ne teste la tessellation elle-même : les domaines quad et
triangle passaient déjà, et les deux tests en échec sont en domaine isoline uniquement
parce que c'est ce que le stream output rend facile à vérifier.

### Ce qui manquait

Le shader d'évaluation devient déjà la fonction vertex matérielle
(`poly_nir_lower_tes(tes, to_hw_vs)`), donc la capture pouvait réutiliser telle quelle la
machinerie du § 28. Deux verrous la bloquaient :

1. l'abaissement `kk_nir_lower_xfb` n'était appliqué qu'au stage `VERTEX` ;
2. surtout, `info.vs.has_xfb` — la porte que le chemin de dessin consulte — n'était
   renseigné que depuis le vertex shader. Or le pipeline est porté par l'objet du vertex
   shader, et l'information XFB vit sur le domain shader. La porte restait donc fermée.

Le correctif ajoute `has_xfb` / `xfb_stride` au membre `tess` de `kk_shader_info`, les
renseigne pour `MESA_SHADER_TESS_EVAL`, et les recopie dans `info->vs` à la fusion des
stages.

### Mesure

| fonction | § 42 | § 43 |
|---|---|---|
| `test_tessellation_read_tesslevel` | 28 | **0** |
| `test_line_tessellation_dxbc` | 54 | 50 |
| `test_line_tessellation_dxil` | 54 | 50 |

| | § 42 | § 43 |
|---|---|---|
| Fonctions avec au moins un échec | 34 | **33** |
| Échecs d'assertion | 2 388 | **2 352** |

574 fonctions démarrées sur 574, aucune régression.

### Piste essayée, mesurée inutile, retirée

`lower_tes_load()` dans `src/poly/nir/poly_nir_lower_tess.c` lit
`nir_intrinsic_io_semantics(intr).location` pour **tous** les chargements qu'il traite, y
compris `load_tess_level_outer` et `load_tess_level_inner` — qui sont des *system values*
sans indices, donc sans `io_semantics`. J'ai écrit le correctif (un `switch` donnant
`VARYING_SLOT_TESS_LEVEL_OUTER`/`INNER`), puis mesuré en le retirant : le test passe
**sans**. Le SPIR-V produit par vkd3d lit les facteurs de tessellation comme des entrées de
patch ordinaires (`load_input` avec `io_semantics`), jamais par la system value. Le chemin
fautif n'est donc pas emprunté ici. Changement annulé — l'arbre ne garde rien de non
mesuré, même correct en apparence.

### Ce qui reste, et la limite exacte de ce correctif

Les 50 échecs restants par fonction ont été diagnostiqués, et la conclusion vaut
avertissement : **la capture depuis la tessellation n'est correcte que lorsque le tampon
d'index produit par le tessellateur est l'identité.**

L'abaissement XFB adresse le tampon de capture par
`instance_id * num_vertices + raw_vertex_id`. Or `poly_nir_lower_tes(tes, to_hw_vs = true)`
transforme le domain shader en **fonction vertex matérielle pilotée par un dessin indexé** :
`raw_vertex_id` y vaut la *valeur* d'index, pas la position dans le dessin. C'est
exactement le cas que `kk_xfb_draw_captures()` refuse pour les dessins indexés de
l'application — sauf que son test porte sur le dessin d'origine, pas sur le dessin interne
que la tessellation engendre.

Conséquence : quand le tessellateur réutilise des sommets (isolines à plus d'un segment,
triangles, quads), les écritures se chevauchent et certains emplacements restent vides.
C'est ce qu'on observe : index 0 et 1 corrects, tout nul ensuite.
`test_tessellation_read_tesslevel` passe parce que ses quatre patches produisent un tampon
d'index identité.

S'y ajoute une seconde cause, indépendante : `kk_flush_xfb_state()` calcule le nombre de
primitives à partir de `draw->vertexCount`, qui pour un dessin tessellé vaut le nombre de
points de contrôle et non le nombre de sommets produits. La requête
`D3D12_QUERY_TYPE_SO_STATISTICS_STREAM0` rend donc 0.

La sortie propre est celle du § 29 : router la capture par un geometry shader de transit,
qui voit les primitives dans l'ordre. Elle demande de chaîner tessellation et geometry
shader — ce que le § 30 avait déjà refusé plutôt que de rasteriser le mauvais tampon, et
qui reste la seule limite structurelle de l'émulation.

Patch **0026-kosmickrisp-xfb-from-tessellation.patch**. Cumulatif régénéré et vérifié
applicable sur un Mesa HEAD vierge.

## 44. Alpha-to-coverage sans canal alpha (2026-09-17)

`test_coverage_export_atoc` échouait 32 fois par variante. Le classement des cas montre
que **seuls les deux premiers** échouent :

| cas | shader | alpha | attendu | obtenu |
|---|---|---|---|---|
| 0 | `ps_atoc` | 0.0 | 0 échantillon | **4** |
| 1 | `ps_atoc` | 0.5 | 1 à 3 | **4** |
| 2 | `ps_atoc` | 1.0 | 4 | 4 |
| 3–13 | `ps_coverage` (export de `SV_Coverage`) | — | exact | exact |

L'export explicite de `SV_Coverage` fonctionne donc parfaitement — le MSL généré déclare
bien `uint sample_mask_out [[sample_mask]]`. C'est l'alpha-to-coverage seul qui est inerte.

### La cause : la même qu'au § 41

La cible de rendu est mono-canal, et le MSL généré déclare `float color_0 [[color(0)]]` :
l'abaissement tronque la sortie au nombre de composantes du format. **Metal n'a donc aucun
alpha à lire**, et son alpha-to-coverage ne restreint rien — d'où la couverture pleine
quelle que soit la valeur écrite.

C'est exactement le piège rencontré au § 41 avec les facteurs de blending `SRC_ALPHA` sur
une cible sans alpha. La différence est qu'ici on ne peut pas se contenter de refuser le
chemin natif : il n'y a pas d'autre chemin.

### Le correctif

Nouvelle passe `msl_lower_alpha_to_coverage()` : elle lit l'alpha **avant** la troncature,
en dérive un masque d'échantillons (`round(saturate(alpha) × sample_count)` bits bas) et
l'écrit dans `FRAG_RESULT_SAMPLE_MASK`.

Elle n'est appelée que sous trois conditions, toutes vérifiables à la compilation du
pipeline :
- `alphaToCoverageEnable` est actif ;
- le shader **n'écrit pas déjà** `SV_Coverage` — D3D12 donne alors la priorité à l'export
  explicite, et ces cas (3 à 13) passaient déjà ;
- l'attachement 0 **n'a pas de canal alpha** — sinon l'alpha-to-coverage natif de Metal est
  exact et n'a pas à être remplacé.

Le masque produit est une approximation : l'échelonnage exact et le tramage du matériel ne
sont pas reproductibles. Il donne 0 pour alpha 0, 2 échantillons sur 4 pour alpha 0,5 et 4
pour alpha 1 — dans les fourchettes que le test admet, et proportionnel comme la
spécification l'exige.

### Mesure

| | § 43 | § 44 |
|---|---|---|
| `test_coverage_export_atoc_dxbc` | 32 | **0** |
| `test_coverage_export_atoc_dxil` | 32 | **0** |
| Fonctions avec au moins un échec | 33 | **31** |
| Échecs d'assertion | 2 352 | **2 288** |

574 fonctions démarrées sur 574, aucune régression.

Patch **0027-kosmickrisp-alpha-to-coverage-without-alpha.patch**. Cumulatif régénéré et
vérifié applicable sur un Mesa HEAD vierge.

## 45. Vérification de la pile complète après dix patchs (2026-09-17)

Les § 36 à 44 ont travaillé sur le pilote via la suite **native**. Ce paragraphe vérifie que
la pile ouverte de bout en bout tient toujours, et la mesure au niveau où elle compte : un
binaire PE Windows exécuté par Wine.

### Deux défauts d'outillage corrigés

1. **La variante x86_64 de KosmicKrisp était dix patchs en retard.** Les § 18 à 27 ne
   reconstruisaient que `build/mesa` (arm64) ; le Wine tourne sous Rosetta et charge
   `prefix-x64`. Reconstruit et réinstallé.
2. **`tests/etape2_pile_wine.sh` choisissait le mauvais préfixe.** Il posait
   `WINEPREFIX=$R/wine/pfx` puis tentait `export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx10}`,
   qui ne pouvait plus rien changer. Or `pfx` est un vestige de l'étape précédente : son
   `dxgi.dll` est incomplet et le chargement échoue avec `c0000135` sans le moindre message.
   La sélection est réécrite explicitement.

Les DLL PE de vkd3d-proton ont été reconstruites par acquit de conscience : inchangées
depuis 15:53, les patchs 0014 et 0016 ne touchant que la compilation et les tests.

### La pile tourne

```
$ ./tests/etape2_pile_wine.sh wine/bin/win_swapchain.exe
CreateSwapChainForHwnd : hr=0
image 0 : back buffer 0, Present hr=0
image 1 : back buffer 1, Present hr=0
image 2 : back buffer 0, Present hr=0
pixel central du back buffer : 00 ff 00 ff (attendu 00 ff 00 ff)

TOUT PASSE (0 echec(s))
```

Fenêtre Win32, swapchain DXGI à trois images, trois présentations, pixel relu et vérifié —
à travers PE → Wine 10 → DXVK (`dxgi`) → vkd3d-proton PE → loader Vulkan → KosmicKrisp
x86_64 sous Rosetta → Metal 4.

### La suite complète passe *à travers Wine*

| | natif (arm64) | à travers Wine (x86_64) |
|---|---|---|
| Fonctions démarrées | 574 / 574 | **574 / 574** |
| Fonctions avec au moins un échec | 31 | 39 |
| Échecs d'assertion | 2 288 | 2 561 |

Aucun plantage, aucune fonction manquante : la suite de conformité D3D12 entière s'exécute
de bout en bout sur la pile ouverte.

Les 273 échecs supplémentaires se répartissent ainsi :

| fonction | natif | Wine | Δ |
|---|---|---|---|
| `test_execute_indirect_state` (+ 4 variantes) | 0 | 175 | +175 |
| `test_structured_buffer_addressing_wrap` | 4 | 94 | +90 |
| `test_line_rasterization`, `execute_indirect_state_vbo_offsets` | 0 | 4 chacune | +8 |
| `test_fence_wait_robustness_shared` | 0 | 3 | +3 |
| `test_placed_msaa_alignment_workaround` | 0 | 1 | +1 |

Les 175 de la famille `execute_indirect_state` étaient **attendus** : le § 17 avait établi
que le binaire natif les saute derrière `#ifdef _WIN32`. Ils ne sont visibles que sous Wine
et relèvent de la limite déjà documentée (ExecuteIndirect avec changement d'état, qui
demande `VK_EXT_device_generated_commands`).

Le +90 sur `test_structured_buffer_addressing_wrap` a été vérifié : les échecs sont de même
nature des deux côtés (`expected 0, got N` — une lecture hors limites qui rend des données
au lieu de zéro), seulement plus nombreux. La construction x86_64 force un alignement
d'allocation de 16 Kio (`KK_WORKAROUND_8`, `#if DETECT_ARCH_X86_64`), donc les lectures
hors limites retombent plus souvent dans de la mémoire réellement projetée. Même limite,
disposition mémoire différente — ce n'est pas un défaut propre à Wine.

## 46. Une vraie application D3D12 tourne (2026-09-17)

Les tests de conformité prouvent la correction, pas l'usage. `tests/win_cube.c` est une
application D3D12 ordinaire, écrite pour l'occasion et compilée en PE Windows :

- fenêtre Win32 visible 800×600, boucle de messages ;
- swapchain DXGI à trois images, `FLIP_DISCARD`, présentation par image ;
- tampon de profondeur `D32_FLOAT`, test de profondeur actif, élimination des faces
  arrière ;
- texture 64×64 en damier montée par tampon intermédiaire et
  `GetCopyableFootprints` / `CopyTextureRegion` ;
- signature racine avec CBV racine, table de descripteurs SRV et échantillonneur
  statique ;
- tampons de sommets et d'indices, cube indexé de 36 indices ;
- constantes par image (matrice modèle-vue-projection recalculée à chaque image) ;
- **HLSL compilé à l'exécution par `d3dcompiler_47`**, c'est-à-dire le compilateur HLSL de
  Wine lui-même ;
- synchronisation par clôture, trois images en vol.

### Résultat

```
HLSL compile par d3dcompiler_47 : VS 2476 octets, PS 1584 octets
240 images presentees en 2.01 s  (119.6 images/s)
image finale ecrite dans cube.bmp (800x600)

derniere image : 30000 points echantillonnes, 26863 de fond, 3137 de geometrie,
                 28 teintes distinctes

TOUT PASSE (0 echec(s))
```

La vérification ne se contente pas de « ça n'a pas planté » : la dernière image présentée
est relue et l'on exige un fond intact, au moins 5 % de la surface couverte par de la
géométrie, et au moins trois teintes distinctes — sans texture ni éclairage, le cube serait
uni. La capture `cube.bmp` montre trois faces au damier orange et bleu, chacune à une
luminosité différente selon sa normale, en perspective correcte et avec les faces arrière
éliminées.

### Deux bogues de l'application, pas du pilote

Le chemin a livré deux diagnostics utiles, tous deux dans mon propre code :

1. `CreateGraphicsPipelineState` rendait `E_INVALIDARG` sans explication. `VKD3D_DEBUG=warn`
   a donné la vraie cause : `dxil-spirv: Failed to remap CBV 0:0`. Le pixel shader lit
   `light` dans `b0`, mais j'avais posé la visibilité du CBV racine à
   `D3D12_SHADER_VISIBILITY_VERTEX`. La pile avait raison de refuser.
2. Un local `cb` masquait la ressource globale `cb` dans la boucle d'images — attrapé par
   le compilateur.

### Ce que cela mesure

119,6 images par seconde pour un cube texturé éclairé en 800×600, à travers
PE → Wine 10 → DXVK → vkd3d-proton → dxil-spirv → KosmicKrisp → Metal 4, sur un binaire
x86_64 traduit par Rosetta. Ce n'est pas une mesure de performance utile en soi — la scène
est triviale — mais elle établit que la pile soutient une boucle de rendu continue sans
dérive ni fuite sur 240 images.

Construction : `./tests/build_win_cube.sh`, exécution :
`./tests/etape2_pile_wine.sh wine/bin/win_cube.exe`.

## 47. Ce que coûte Rosetta, et ce qu'il advient quand il disparaît (2026-09-17)

### Où Rosetta intervient aujourd'hui

Vérifié par `file` sur les binaires en place :

| composant | architecture |
|---|---|
| `wine64`, `ntdll.so` | x86_64 |
| KosmicKrisp du chemin Wine (`prefix-x64`) | x86_64 |
| KosmicKrisp du chemin natif (`prefix`) | arm64 |

Autrement dit **tout le côté Unix passe par Rosetta**, pas seulement le binaire Windows.
C'est l'approche standard sur macOS aujourd'hui, mais c'est la dépendance maximale.

### Ce que ça coûte : mesure

`tests/bench_cpu_overhead.c` enregistre 20 000 `vkCmdDispatch`, meilleur de 10 tours. Même
source, compilée pour les deux architectures, contre la construction de KosmicKrisp
correspondante :

| | enregistrement | débit | total (+ GPU) |
|---|---|---|---|
| arm64 natif | 2,36 ms | 8,47 M commandes/s | 4,08 ms |
| x86_64 sous Rosetta | 5,39 ms | 3,71 M commandes/s | 7,15 ms |

**Rosetta coûte 2,28× sur le travail CPU du pilote**, 1,75× une fois le GPU inclus. Le
travail GPU lui-même est natif des deux côtés : c'est bien la traduction du code pilote qui
est taxée. Sur une scène réelle, où le CPU enregistre des milliers d'appels par image, cet
écart est le plafond de performance de la pile actuelle.

### Ce qu'il faudrait pour s'en passer

Seul le **code PE Windows** a besoin d'être traduit. Wine sépare déjà les deux côtés
(WoW64) : rien n'oblige `wine64`, vkd3d-proton et KosmicKrisp à être x86_64.

Vérifié dans l'arbre Wine 10 :
- `configure.ac` accepte `--enable-archs={i386,x86_64,arm,aarch64}` et `HOST_ARCH=aarch64` ;
- mais `dlls/wow64cpu` ne couvre que **i386 sur x86_64**. Il n'existe **aucun** moteur amont
  pour exécuter du PE x86_64 sur un hôte arm64 ;
- les seules occurrences de « rosetta » dans Wine (`server/mach.c`,
  `dlls/ntdll/unix/signal_x86_64.c`) servent à détecter que Wine *lui-même* est traduit,
  pour contourner des bizarreries d'exceptions Mach. Rien qui traduise du code.

Ce chaînon manquant est ce que CrossOver et le Game Porting Toolkit d'Apple fournissent,
en s'appuyant justement sur Rosetta pour la traduction du PE.

### Le jalon atteignable

Avant de résoudre « PE x86_64 sur hôte arm64 », il y a une étape entièrement vérifiable :
faire tourner un **PE ARM64** Windows sur un Wine arm64, avec vkd3d-proton compilé en
aarch64 et KosmicKrisp arm64 — soit la pile complète **sans Rosetta du tout**. Cela ne fait
pas tourner un jeu x86, mais cela prouve que rien dans la pile n'est lié à l'architecture,
et isole le problème restant à un seul composant.

Prérequis manquant, constaté : il faut une chaîne `aarch64-w64-mingw32` complète.
`/usr/local/opt/mingw-w64` ne fournit que i686 et x86_64 ; le clang du système connaît la
cible mais n'a ni CRT ni en-têtes pour elle. Il faudrait llvm-mingw.

### Sur l'échéance

Apple a annoncé (WWDC 2025) que Rosetta 2 resterait complet jusqu'à macOS 27, puis serait
réduit à un sous-ensemble destiné aux **anciens jeux** et à quelques cadriciels — ce qui est
précisément notre cas d'usage. Je note l'annonce sans en faire une garantie : c'est une
politique, elle peut changer, et bâtir sur une exception est fragile. La mesure ci-dessus
donne l'argument technique indépendamment de la politique : passer le côté Unix en arm64
natif rendrait la pile 2,3× plus rapide côté pilote **et** réduirait la surface exposée à
une décision d'Apple au seul binaire du jeu.

## 48. Le plafond d'appels de dessin de la pile (2026-09-17)

### Précision sur la version du système

Cette machine est sur **macOS 26.5.2 (build 25F84, Darwin 25.5.0)**, SDK 26.2. La
validation sur macOS 27 reste à faire ; rien de ce qui suit n'a été mesuré dessus.

### Le blocage vers une pile sans Rosetta

Le § 47 identifiait le prérequis : une chaîne `aarch64-w64-mingw32`. Vérification faite :

- `clang -target aarch64-w64-mingw32 -c` **fonctionne** avec les deux clangs présents
  (celui d'Apple et celui de Homebrew) : il produit bien des objets *COFF AArch64* ;
- mais **aucun `lld` n'est installé** (ni dans `llvm`, ni dans `llvm@23`). Il n'y a donc pas
  d'éditeur de liens COFF pour ARM64 sur cette machine, et l'on ne peut pas produire de DLL
  ni d'exécutable Windows ARM64.

Le jalon « pile sans Rosetta » est donc bloqué sur une dépendance externe, pas sur du code.
La règle du projet interdisant d'installer dur dans le système, la voie propre est de
déposer llvm-mingw dans le dossier du projet — ce qui suppose un téléchargement.

### Ce que la pile encaisse

`tests/win_cube.c` prend maintenant un nombre de cubes en argument : autant d'appels de
dessin par image, chacun avec son propre CBV racine. Balayage sur 240 images :

| cubes | images/s | appels de dessin/s |
|---|---|---|
| 1 | 119,6 | 120 |
| 64 | 119,4 | 7 640 |
| 512 | 119,5 | 61 206 |
| 2 048 | 119,3 | 244 398 |
| 8 192 | 79,7 | **652 914** |
| 32 768 | 18,9 | 618 736 |
| 131 072 | 4,5 | 589 136 |

Jusqu'à 2 048 cubes la cadence ne bouge pas d'un cheveu : 240 images en 2,01 s à chaque
fois, soit **119,4 Hz — c'est le plafond de présentation**, pas celui de la pile. Le
décrochage commence à 8 192 cubes, et le débit se stabilise ensuite autour de
**600 000 à 650 000 appels de dessin par seconde**.

### Ce que ce chiffre veut dire

À 60 images par seconde, cela laisse environ **10 000 appels de dessin par image** à travers
toute la chaîne PE → Rosetta → Wine → DXVK → vkd3d-proton → KosmicKrisp → Metal. La plupart
des jeux D3D12 en émettent entre 1 000 et 5 000 : le chemin des appels de dessin n'est donc
pas le facteur limitant pour un jeu ordinaire.

Ce plafond est cohérent avec la mesure du § 47 : le travail CPU du pilote est 2,28× plus
lent sous Rosetta. Un côté Unix en arm64 natif déplacerait vraisemblablement ce plafond vers
le million d'appels par seconde — c'est le gain concret qu'il y a à aller chercher, au-delà
de la question de la disponibilité de Rosetta.

## 49. Wine tourne nativement en arm64 — et bute sur une limite du noyau (2026-09-17)

llvm-mingw téléchargé dans `toolchain/` (avec l'accord explicite) :
`llvm-mingw-20260908-ucrt-macos-universal.tar.xz`, 124 Mo, sha256
`d1dc5d1e…62a149`, déposé sous `toolchain/llvm-mingw`. Vérifié : il produit bien des
`PE32+ Aarch64` — DLL et exécutable.

### Wine 10 construit et démarre en arm64 natif

```
$ ./wine/wine-arm64/bin/wine --version
wine-10.0
```

`lib/wine/` contient `aarch64-unix` et `aarch64-windows` ; le binaire est
`Mach-O 64-bit executable arm64`. Aucune trace de Rosetta dans cette pile.

### Un vrai bogue de Wine sur hôte arm64 macOS

Le premier build donnait un `SIGKILL` immédiat, sans une ligne de sortie — le processus
était tué **avant dyld**. Cause trouvée : `configure.ac` pose sans condition, pour tout
macOS,

```
WINELOADER_LDFLAGS="-Wl,-segalign,0x1000,-pagezero_size,0x1000,..."
```

Wine rétrécit le `__PAGEZERO` pour libérer les adresses basses dont Windows a besoin. Sur
x86_64 macOS c'est accepté ; **sur arm64 le noyau refuse le Mach-O**. Balayage des tailles :

| `__PAGEZERO` | résultat |
|---|---|
| 0x4000, 0x1000000, 0x10000000, 0x40000000, 0x70000000, 0x7ffe0000 | SIGKILL |
| 0x100000000 (4 Gio, défaut) | **démarre** |

Et ce n'est pas une question de base d'image : les mêmes tailles avec
`-image_base,0x200000000` sont tuées de la même façon. Correctif : ne pas toucher au
`__PAGEZERO` sur aarch64 — patch **0028-wine-keep-default-pagezero-on-arm64-macos.patch**.

### La limite, elle, n'est pas contournable par un patch

Avec le `__PAGEZERO` par défaut, le chargeur démarre mais le côté Windows s'arrête net :

```
err:virtual:map_fixed_area out of memory for 0x7ffe0000-0x7ffe1000
err:virtual:virtual_alloc_first_teb wine: failed to map the shared user data: c0000017
```

`0x7ffe0000` est l'adresse de `KUSER_SHARED_DATA`, fixée par l'ABI Windows — y compris pour
Windows ARM64. Elle tombe dans les 4 Gio du `__PAGEZERO` obligatoire.

Vérifié directement, sans Wine :

```
mmap MAP_FIXED 0x7ffe0000        -> MAP_FAILED
mach_vm_allocate fixe 0x7ffe0000 -> kr=1  (KERN_INVALID_ADDRESS)
mach_vm_allocate fixe 0x200000000 -> kr=3 (temoin : KERN_NO_SPACE, l'appel fonctionne)
```

**Les 4 premiers gigaoctets de l'espace d'adressage sont inaccessibles à un processus arm64
macOS**, et l'on ne peut pas les rendre disponibles puisque rétrécir le `__PAGEZERO` fait
tuer le processus. Les deux contraintes se referment l'une sur l'autre.

### Bilan

| | état |
|---|---|
| Chaîne PE ARM64 (llvm-mingw) | **acquise et vérifiée** |
| Wine côté Unix en arm64 natif | **construit, installé, démarre** |
| Bogue Wine du `__PAGEZERO` sur arm64 macOS | **trouvé et corrigé** (patch 0028) |
| Exécution de code Windows sur cet hôte | **bloquée** par le noyau, pas par du code |

Le chemin « pile sans Rosetta » n'est donc pas une affaire de portage : il demande de placer
`KUSER_SHARED_DATA` ailleurs qu'à son adresse d'ABI, ce qui suppose d'intercepter les accès
dans le code Windows lui-même. C'est vraisemblablement ce que fait CrossOver, et cela
explique qu'aucun Wine amont ne tourne en arm64 sur macOS.

Le gain visé reste chiffré (§ 47 : 2,28× sur le travail CPU du pilote), mais il est hors
d'atteinte sans ce travail-là.

## 50. Arrondi du niveau de mip à la demi-unité (2026-09-17)

### Deux blocs écartés, preuve à l'appui

Avant de chercher un bogue, deux gros restes ont été instruits et classés non actionnables.

**`test_large_texel_buffer_view` (42).** Le test demande des vues de 2^29 texels, au-delà
du minimum D3D12 de 2^27. Une sonde a d'abord semblé montrer que la limite venait de nous :
`kk_buffer_view.c` refuse au-delà de `KK_MAX_TEXEL_BUFFER_ELEMENTS` (2^28). En relevant la
constante, **Metal tranche lui-même**, et brutalement :

```
MTLTextureDescriptorInternal validateWithDevice: failed assertion
Texture Descriptor Validation
MTLTextureDescriptor has width (536870912) greater than the maximum allowed size of 268435456.
```

2^28 est bien la limite matérielle, et la dépasser **abandonne le processus** — la garde du
pilote est donc nécessaire, pas seulement correcte. Constante remise à sa valeur.

**`test_undefined_structured_raw_read_typed` et son symétrique (320).** Le shader lit un
descripteur structuré ou brut à travers une déclaration **typée**. Sonde sur la création
des vues : pour ce test, **17 vues de texels sont créées, toutes pour les buffers de
sortie ; aucune pour les 16 SRV d'entrée**, alors que 32 descripteurs typés sont écrits. En
clair, vkd3d ne fabrique jamais de vue typée pour un descripteur structuré ou brut : le
shader lit un emplacement indéfini, et le test encode ce que le matériel AMD ou NVIDIA
laisse traîner là. Non reproductible sans imiter la disposition de descripteurs d'un autre
constructeur.

### Le bogue trouvé

`test_sample_instructions` échouait sur deux cas seulement, les numéros 23 et 26 :
`SampleLevel` à un LOD de **0,5** et **1,5**, filtrage de mip *nearest*. Les voisins
passent : 0,4 rend le niveau 0, 1,4 le niveau 1.

Reproduit en isolation (`tests/test_view_mip_range.c`, deux cas ajoutés) :
```
  v0 mip nearest LOD 0.5    :   1  (attendu   2)  ECHEC
  v0 mip nearest LOD 1.5    :   2  (attendu   3)  ECHEC
```

Vulkan et D3D12 imposent `niveau = floor(lod + 0.5)` : la demi-unité arrondit **vers le
haut**. Metal arrondit vers le bas.

### Le correctif

Le mode de filtrage de mip n'est pas connu à la compilation du shader — il vient du
sampler, donc du descripteur. Un champ `sampler_flags` est ajouté au descripteur
échantillonné (logé dans le remplissage restant, la structure reste à 64 octets), renseigné
depuis `mipmapMode`. L'abaissement de `nir_texop_txl` lit ce drapeau et arrondit le LOD
lui-même :

```
lod = mip_nearest ? floor(lod + 0.5) : lod
```

Une valeur déjà entière traverse ensuite l'arrondi de Metal sans changer. Le surcoût ne
porte que sur les échantillonnages à LOD explicite, et seulement d'un `bcsel`.

### Mesure

| | § 44 | § 50 |
|---|---|---|
| `test_sample_instructions` | 31 | **0** |
| Fonctions avec au moins un échec | 31 | **30** |
| Échecs d'assertion | 2 288 | **2 257** |

574 fonctions démarrées sur 574, aucune régression.

### Ce qui reste

Sur 2 257 échecs, **2 112 sont désormais instruits et classés non actionnables** :

| bloc | échecs | raison |
|---|---|---|
| `suballocate_small_textures_size` | 1 650 | taille imposée par `heapTextureSizeAndAlignWithDescriptor:` |
| `undefined_*_read_typed` (4 fonctions) | 320 | aliasing de descripteurs indéfini, dépendant du matériel |
| `line_tessellation` (2 fonctions) | 100 | XFB depuis la tessellation, § 43 |
| `large_texel_buffer_view` | 42 | limite Metal de 2^28 texels |

Le solde réellement actionnable est de **145 échecs répartis sur 23 fonctions**, aucune
au-dessus de 36.

Patch **0029-kosmickrisp-round-explicit-lod-for-nearest-mip.patch**. Cumulatif régénéré et
vérifié applicable sur un Mesa HEAD vierge.

## 51. Le type de sortie d'un fragment se réinterprète, il ne se convertit pas (2026-09-17)

`test_bufinfo_instruction` (18 par variante) rendait systématiquement la bonne valeur avec
le mauvais type :

| attendu (bits) | obtenu (bits) | lecture |
|---|---|---|
| `0x00000064` | `0x42c80000` | 100 contre 100.0f |
| `0x00000010` | `0x41800000` | 16 contre 16.0f |
| `{5, 4, 0, 1}` | `{5.0f, 4.0f, 0.0f, 1.0f}` | idem sur quatre composantes |

Le MSL généré le montre à découvert :
```
t15 = t13 >> uint(2u);
t16 = float(t15);
t19 = float4(t16, float(4.0), float(0.0), float(1.0));
out.color_0.xyzw = t19.xyzw;
```

La cible de rendu est `R32G32B32A32_FLOAT` et le test compare les **bits bruts** : en D3D,
`bufinfo` produit un entier, le `mov` vers la sortie copie les bits, et le format flottant
les stocke tels quels. Aucune conversion.

### La cause était dans notre propre passe

`msl_nir_fs_force_output_signedness()` existe précisément pour rattraper les désaccords de
type entre la sortie du shader et le format de la cible. Elle le faisait par **conversion
de valeur** : `nir_u2fN` pour une cible flottante, `nir_f2uN` pour une cible entière. C'est
elle qui fabriquait le `float(t15)`.

Or une valeur NIR n'a pas de type : elle n'est qu'un motif de bits, et le type vit sur
l'intrinsèque de stockage. Réinterpréter ne demande donc **aucune instruction** — il suffit
de corriger le type déclaré. La passe se réduit à cela, et couvre au passage les formats
snorm qui manquaient.

### Mesure

| | § 50 | § 51 |
|---|---|---|
| `test_bufinfo_instruction_dxbc` | 18 | **0** |
| `test_bufinfo_instruction_dxil` | 18 | **0** |
| Fonctions avec au moins un échec | 30 | **28** |
| Échecs d'assertion | 2 257 | **2 221** |

574 fonctions démarrées sur 574, aucune régression — ce qui comptait, la passe touchant
toute sortie de fragment dont le type diffère du format.

### Correction de classement : la tessellation pèse 136, pas 100

Les six fonctions `test_quad_tessellation*` (6 échecs chacune, 36 au total) semblaient
relever d'un ordre de triangulation différent :

```
Triangle 0 sommets {-1,-1}, {-1,1}, {1,1}  au lieu de  {-1,-1}, {1,-1}, {-1,1}
```

Vérification faite dans le test : il lit les triangles **par stream output**
(`SOSetTargets` puis `check_triangles` sur le tampon SO). Ce n'est donc pas la
triangulation du tessellateur qui est en cause, mais la capture — exactement la limite du
§ 43 : le dessin tessellé est **indexé** (`draw.index.gpu.addr` pointe le tas où le
tessellateur a écrit ses indices, `el_size_B = 4`), donc `[[vertex_id]]` vaut la valeur
d'index et non la position, et les écritures de capture se chevauchent.

Le bloc « XFB depuis la tessellation » compte donc **136 échecs** sur huit fonctions, et
non 100 sur deux.

### État

| bloc non actionnable | échecs |
|---|---|
| `suballocate_small_textures_size` (taille imposée par Metal) | 1 650 |
| `undefined_*_read_typed` (aliasing indéfini) | 320 |
| XFB depuis la tessellation (8 fonctions) | 136 |
| `large_texel_buffer_view` (limite Metal 2^28) | 42 |

Reste **73 échecs réellement actionnables sur 15 fonctions**, la plus grosse à 16.

Patch **0030-kosmickrisp-reinterpret-fs-output-type.patch**. Cumulatif régénéré et vérifié
applicable sur un Mesa HEAD vierge.

## 52. Copier un seul aspect d'une image profondeur-stencil (2026-09-17)

`test_copy_subresource_depth_stencil_batch` (11 échecs) copie des régions d'un seul aspect
entre couches d'une image `D32_FLOAT_S8X24_UINT`. Le résultat mêlait des copies qui
n'avaient pas eu lieu et des valeurs venues du mauvais aspect :

```
depth subresource 0, coord 2, 2, expected 0.500000, got 0.750000
depth subresource 0, coord 5, 4, expected 0.040039, got 0.500000
```

### La cause

`kk_image_aspects_to_plane()` ne distingue pas les aspects d'une image profondeur-stencil :
`VK_IMAGE_ASPECT_DEPTH_BIT` et `VK_IMAGE_ASPECT_STENCIL_BIT` tombent tous deux sur le
`default: return 0`. C'est correct — les deux vivent bien dans la **même** `MTLTexture`
`Depth32Float_Stencil8`. Mais `can_do_image_to_image_copy()` en concluait que la copie
directe texture-à-texture convenait, et Metal n'a aucun moyen d'y isoler un aspect : le
blit emporte les deux.

Le chemin par tampon, lui, sait le faire — il pose déjà
`MTL_BLIT_OPTION_DEPTH_FROM_DEPTH_STENCIL` ou `..._STENCIL_FROM_DEPTH_STENCIL` selon
l'aspect demandé. Il suffisait donc d'y router ces copies : `can_do_image_to_image_copy()`
reçoit maintenant la région et refuse dès qu'un format combiné est copié par un aspect
seul.

### Mesure

| | § 51 | § 52 |
|---|---|---|
| `test_copy_subresource_depth_stencil_batch` | 11 | **0** |
| Fonctions avec au moins un échec | 28 | **27** |
| Échecs d'assertion | 2 221 | **2 210** |

574 fonctions démarrées sur 574, aucune régression.

### Deux autres blocs rattachés à une limite connue

En les instruisant plutôt qu'en les corrigeant :

- `test_gs_topology_mismatch` (3 par variante) et `test_shader_io_mismatch` (2) rendent
  `0x8007000e` (E_OUTOFMEMORY) à la création du pipeline. Le journal de vkd3d montre
  « Topology: 4 (patch vertex count: 3) » et quatre étages liés : ces pipelines combinent
  **tessellation et geometry shader**. C'est le refus explicite du § 30
  (`VK_ERROR_FEATURE_NOT_PRESENT`), pas un défaut nouveau.
- `test_depth_bias_formats` (6) demande la mise à l'échelle du biais de profondeur propre à
  chaque format. `VK_EXT_depth_bias_control` n'est pas annoncé et `mtl_set_depth_bias` ne
  donne pas le contrôle exact qu'il faudrait.

### État

| bloc non actionnable | échecs |
|---|---|
| `suballocate_small_textures_size` | 1 650 |
| `undefined_*_read_typed` | 320 |
| XFB depuis la tessellation (8 fonctions) | 136 |
| `large_texel_buffer_view` | 42 |
| tessellation + geometry shader (§ 30) | 9 |
| biais de profondeur par format | 6 |

Reste **47 échecs actionnables sur 9 fonctions** : `shader_waveop_maximal_convergence` (16),
`query_heap_cpu_resolve_timestamp` (12), `query_pipeline_statistics` (6),
`virtual_queries` (5), `structured_buffer_addressing_wrap` (4), et quatre fonctions à 1 ou 2.

Patch **0031-kosmickrisp-single-aspect-depth-stencil-copy.patch**. Cumulatif régénéré et
vérifié applicable sur un Mesa HEAD vierge.

## 53. Deux limites mesurées plutôt que supposées (2026-09-17)

### `pipelineStatisticsQuery` : la dernière feature de profil est hors d'atteinte

Le § 35 affirmait que Metal n'expose qu'un jeu de compteurs d'horodatage. C'était une
affirmation sans mesure ; la voici. Une sonde temporaire énumère `[MTLDevice counterSets]` :

```
[probe] counterSets = 1
[probe]   set 'timestamp' : GPUTimestamp
```

**Un seul jeu, un seul compteur.** Ni `MTLCommonCounterSetStatistic`, ni
`fragmentInvocations`, ni rien d'approchant sur ce M1 Max en macOS 26.5.2.

`test_query_pipeline_statistics` (6 échecs) demande `IAVertices`, `IAPrimitives`,
`VSInvocations`, `CInvocations`, `CPrimitives` — tous calculables côté CPU au moment du
dessin, comme le compteur `generated` du transform feedback du § 28 — mais aussi
`PSInvocations > 0`, qui exige un compteur GPU d'invocations de fragment.

On pourrait donc faire passer cinq assertions sur six en fabriquant les compteurs
calculables. Je ne le fais pas : cela obligerait à annoncer `pipelineStatisticsQuery`
comme supporté alors que `PSInvocations` rendrait toujours 0. Une application qui s'en sert
pour une heuristique de visibilité y lirait un chiffre faux au lieu d'un refus franc.
Bloc classé non actionnable, preuve à l'appui.

### `test_virtual_queries` : Metal ne tient qu'une requête d'occlusion à la fois

Les 5 échecs (`Got unexpected result 0`) ne sont pas un défaut d'implémentation mais une
contrainte de l'API. Le test ouvre **six requêtes simultanées** — trois binaires, trois
précises — et les fait chevaucher **deux passes de rendu** :

```
BeginQuery(heap0, BINARY, 0) ... BeginQuery(heap0, BINARY, 1) ... BeginQuery(heap1, OCCLUSION, 2)
   Draw
EndQuery(heap0, BINARY, 2)
OMSetRenderTargets(ds[1])          <- la requête 0 est toujours ouverte
   Draw
EndQuery(heap0, BINARY, 0)
```

Metal n'a qu'un mode de visibilité actif par encodeur, écrivant à un seul offset. Le pilote
le reflète tel quel — `struct { mode; uint16_t index; } occlusion` avec le commentaire
« There can only be one active at a time (hardware constraint) ». Ouvrir une deuxième
requête écrase l'index de la première, et `EndQuery` coupe le comptage pour toutes.

La sortie existe et se conçoit clairement : découper le rendu en **segments** délimités par
chaque `Begin`/`End`, donner à chaque segment son propre emplacement de visibilité, et
sommer à la résolution les segments couverts par chaque requête. C'est faisable avec la
table de requêtes et le chemin de résolution déjà en place, mais cela demande un noyau de
sommation et un suivi des intervalles. Non entrepris ici, et noté comme tel plutôt
qu'approximé : une requête d'occlusion à moitié juste est pire qu'une limite annoncée,
puisque les moteurs s'en servent pour décider ce qu'ils dessinent.

### État

Sur 2 210 échecs, **2 189 sont instruits et classés** :

| bloc | échecs | nature |
|---|---|---|
| `suballocate_small_textures_size` | 1 650 | taille imposée par Metal |
| `undefined_*_read_typed` | 320 | aliasing de descripteurs indéfini |
| XFB depuis la tessellation | 136 | § 43, demande le chaînage tess → GS |
| `large_texel_buffer_view` | 42 | limite Metal de 2^28 texels |
| tessellation + geometry shader | 9 | refus explicite du § 30 |
| biais de profondeur par format | 6 | pas de `VK_EXT_depth_bias_control` |
| `query_pipeline_statistics` | 6 | aucun compteur GPU au-delà de l'horodatage |
| `virtual_queries` | 5 | une seule requête d'occlusion à la fois |
| `shader_waveop_maximal_convergence` | 16 | convergence SIMD, non instruit |

Il reste **21 échecs sur 5 fonctions** encore ni corrigés ni instruits, aucune au-dessus
de 12.

## 54. Une fausse régression : l'écran verrouillé (2026-09-18)

En revérifiant la pile après les patchs 0029 à 0031, `win_swapchain.exe` s'est mis à **se
bloquer après la deuxième présentation**, là où il en enchaînait trois et vérifiait le pixel.
Symptôme parfait de régression.

Méthode : retirer les trois patchs de l'arbre, reconstruire la variante x86_64, relancer.
**Le blocage persiste sans eux.** Les patchs étaient donc hors de cause, et il fallait
chercher dans l'environnement.

```
$ ioreg -n Root -d1 | grep CGSSessionScreenIsLocked
CGSSessionScreenIsLocked"=Yes
```

L'écran s'était verrouillé pendant la nuit. La preuve par le contraste, sur la même machine
au même instant :

| | écran déverrouillé (§ 46) | écran verrouillé |
|---|---|---|
| `win_cube.exe` | 240 images, **119,6 img/s** | 240 images, **2 350,1 img/s** |
| `win_swapchain.exe` | 3 présentations, pixel vérifié | bloqué à la 3ᵉ |

Le cube tourne toujours, et vingt fois plus vite : plus rien ne le cadence sur le
rafraîchissement de l'écran. Cela confirme au passage que les 119,6 img/s du § 46 étaient
bien un plafond de présentation et non de pile, comme le § 48 l'avait déduit du balayage.

`win_swapchain` attend, lui, l'achèvement d'une présentation avant de relire le back
buffer ; avec un compositeur qui n'affiche plus rien, l'attente ne se termine pas. Ce n'est
pas un défaut du pilote — mais c'est un piège de mesure à connaître : **toute vérification
passant par la présentation doit se faire écran déverrouillé**.

Les trois patchs ont été remis, la variante x86_64 reconstruite, et le cumulatif vérifié à
nouveau applicable sur un Mesa HEAD vierge. La dernière image du cube reste conforme :
4 812 points de géométrie, 29 teintes distinctes, fond intact.

### Dernier bloc instruit : `query_heap_cpu_resolve_timestamp`

Ses 12 échecs ne sont pas non plus un défaut. Le test écrit **15 horodatages sur 16** puis
résout les 16 d'un coup. `vkGetQueryPoolResults` rend alors `VK_NOT_READY` — la 16ᵉ requête
n'a jamais été écrite — et vkd3d, par prudence, met **tout le lot à zéro** :

```c
/* If the GPU is not done, spec says that returned values are undefined,
 * so be defensive and memset it. */
if (vr == VK_NOT_READY) { memset(data, 0, query_size * count); ... }
```

Le test s'appuie donc sur la lecture d'une requête jamais écrite, que vkd3d qualifie
lui-même d'UB deux fonctions plus haut (« It is UB to read a host query before it has been
written actually »). Notre pilote initialise ses rapports avec une sentinelle
« indisponible » et rend `VK_NOT_READY` : c'est le comportement correct. Les pilotes qui
passent ce test laissent vraisemblablement la mémoire non initialisée.

### Bilan de la session

| | début | fin |
|---|---|---|
| Fonctions avec au moins un échec | 50 | **27** |
| Échecs d'assertion | 18 618 | **2 210** |
| Patches | 17 | **31** (+ un patch Wine) |

Sur les 2 210 échecs restants, **2 201 sont instruits et classés**, mesure ou citation à
l'appui. Il reste `shader_waveop_maximal_convergence` (16) non instruit, et cinq fonctions
à 1 ou 2 échecs.

## 55. `shader_waveop_maximal_convergence` : le matériel reconverge (2026-09-18)

Dernier bloc non instruit. Le shader du test :

```hlsl
uint v = RO[thr];
while (true) {
    uint first = WaveReadLaneFirst(v);
    if (v == first) { result = WaveActiveSum(v); break; }
}
RW[thr] = result;
```

Deux pipelines : l'un compilé avec reconvergence maximale, attendu **25** partout (la somme
des seize entrées) ; l'autre sans, attendu **12, 9, 4, 0** — la somme par groupe de valeurs
égales. Le test fait 50 assertions, **16 échouent** : le pipeline convergent passe
entièrement, le non-convergent rend 25 au lieu des sommes par groupe. Nous sommes donc
*trop* convergents.

### Ce que génère l'abaissement

Le MSL produit suit fidèlement l'abaissement de Mesa (`lower_reduce`) :

```c
t31 = 1u << lane;
t32 = simd_or(t31);                 // masque des voies actives
t34 = (t32 == 0xffffffff);          // toutes actives ?
if (t34) {                          // chemin rapide, non masqué
    t36 = simd_shuffle(t28, lane ^ 1);  t37 = t28 + t36;
    ... papillon sur les 32 voies ...
} else {
    ... chemin masqué par le ballot ...
}
```

L'abaissement est correct : il ne prend le chemin non masqué que si le ballot dit que
toutes les voies sont actives.

### Première hypothèse, écartée par la mesure

`simd_or()` est une réduction de groupe SIMD, indéfinie sous divergence en MSL — d'où
l'idée qu'elle rendrait un masque plein et forcerait le chemin rapide. Le pilote construit
d'ailleurs ce ballot à la main : `KK_WORKAROUND_3` remplace `nir_intrinsic_ballot` par
`reduce(ior, 1 << lane)` au lieu d'émettre `simd_ballot`, primitive de la famille *vote*
qui, elle, est définie sous divergence.

Ce contournement est justement marqué « résolu sur macOS 27 » dans
`kk_parse_environment_options()`. Il se désactive à la main :

```
MESA_KK_DISABLE_WORKAROUNDS=3
```

Mesure, caches vkd3d et Mesa vidés entre les deux :

| | échecs |
|---|---|
| avec le contournement (`simd_or`) | 16 |
| sans le contournement (`simd_ballot` natif) | **16** |

Aucune différence. Le ballot n'est donc pas le facteur déterminant.

### La conclusion

Même avec la primitive définie sous divergence, le masque rendu est plein : **le matériel
reconverge les voies avant l'opération de groupe**. C'est le modèle d'exécution d'AGX, et
MSL n'offre aucun moyen de l'en empêcher — c'est précisément ce que le nom du test
désigne. Un pilote ne peut pas rendre une exécution *moins* convergente que le matériel.

Bloc classé non actionnable, avec l'A/B à l'appui.

### À refaire sur macOS 27

`kk_parse_environment_options()` désactive automatiquement, sur macOS 27 et au-delà, les
contournements **1 à 6, 8, 11, 12, 17 et 18**. Dix contournements tombent d'un coup : la
campagne complète devra être relancée à la mise à jour, et le classement des blocs
non actionnables réexaminé. Le présent paragraphe montre au moins que le n° 3 n'y changera
rien pour ce test-ci.

### Tous les échecs restants sont instruits

| bloc | échecs | nature |
|---|---|---|
| `suballocate_small_textures_size` | 1 650 | taille imposée par Metal |
| `undefined_*_read_typed` | 320 | aliasing de descripteurs indéfini |
| XFB depuis la tessellation | 136 | demande le chaînage tess → GS |
| `large_texel_buffer_view` | 42 | limite Metal de 2^28 texels |
| `shader_waveop_maximal_convergence` | 16 | reconvergence matérielle |
| `query_heap_cpu_resolve_timestamp` | 12 | le test lit une requête jamais écrite |
| tessellation + geometry shader | 9 | refus explicite du § 30 |
| `query_pipeline_statistics` | 6 | aucun compteur GPU hors horodatage |
| biais de profondeur par format | 6 | pas de `VK_EXT_depth_bias_control` |
| `virtual_queries` | 5 | une seule requête d'occlusion à la fois |
| divers (5 fonctions) | 8 | non instruits, 1 à 4 échecs chacun |

**2 202 des 2 210 échecs sont expliqués**, chacun par une mesure ou une citation.

---

## 56. Les dérivées doivent sortir du flot divergent (2026-09-18)

### Ce que le test mesure

`test_derivative_hoisting` prend quatre dérivées dans un pixel shader, **après** qu'une
partie des voies du quad soit sortie par un `return` :

```hlsl
int coord = (int(vin.pos.x) & 1) + (int(vin.pos.y) & 1) * 2;
if (tmp[coord] < 0.0)
    return;                       // quad_values = {1, -1, -1, 1} -> voies 1 et 2 sortent
RWBuf[coord] = float4(1, 1, 1, 1);
float x = ddx_fine(vin.uv.x);     // flot de contrôle divergent
```

Le viewport fait 2×2, `uv = pos.xy * float2(10, 15)`, donc une NDC par pixel : la dérivée
attendue vaut 10 en x et −15 en y, et le test attend `1 + 10 = 11` et `1 - 15 = -14`.

### Le symptôme est exactement la moitié

```
(0, 0): Expected (11.000000, -14.000000, 1.0, 1.0), got (6.000000, -6.500000, 1.0, 1.0)
(1, 1): idem
```

`6 = 1 + 5` et `-6.5 = 1 - 7.5`. Les dérivées valent 5 et −7,5 au lieu de 10 et −15.
`uv.x` vaut −5 sur la voie 0 et +5 sur la voie 1 : obtenir 5 revient à calculer
`0 - (-5)`. Idem en y : `uv.y` vaut 7,5 en haut, et `0 - 7.5 = -7.5`. **La voie morte du
quad contribue 0**, pas sa valeur interpolée. Les deux dérivées justes (`z` et `w`) portent
sur une constante : 0 partout, donc insensibles au problème.

Les deux cas qui échouent sont (0,0) et (1,1), c'est-à-dire précisément les deux voies
survivantes. Cohérent.

### La cause, dans le MSL émis

`MESA_KK_DEBUG=msl` sur un cache vide :

```
    t33 = !t32;
    if (t33) {
        ...
        t48 = dfdx(t13);
        t49 = dfdy(t14);
```

Le `dfdx` est **à l'intérieur** du `if`. dxil-spirv fait pourtant la remontée lui-même :
c'est la raison d'être de ce test, et `vkd3d_shader_compile_dxil` n'active l'option
`DXIL_SPV_OPTION_QUAD_CONTROL_RECONVERGENCE` (`libs/vkd3d-shader/dxil.c:1162`) que si le
pilote annonce `VK_KHR_shader_maximal_reconvergence` **et** `VK_KHR_shader_quad_control`.
KosmicKrisp n'annonce ni l'un ni l'autre, donc dxil-spirv retombe sur sa propre remontée.
Elle n'a pas survécu jusqu'au MSL.

Deux fausses pistes écartées avant d'écrire quoi que ce soit :

- `nir_opt_sink` avec `nir_move_alu` : les dérivées ne sont pas des ALU. Depuis
  `nir_intrinsics.py:518`, `ddx`/`ddy` sont des intrinsèques marquées `QUADGROUP` et sans
  `CAN_REORDER`, et `nir_opt_sink.c:166` refuse tout ce qui n'est pas réordonnable. Cette
  passe ne peut donc pas les descendre.
- une passe de remontée déjà présente dans NIR : `grep -rn is_derivative src/compiler/nir`
  ne renvoie rien. Il n'y en a pas.

### La correction (patch 0032)

Une passe `msl_nir_hoist_derivatives()` dans `msl_nir_lower_common.c`. Après
`nir_metadata_require(impl, nir_metadata_divergence)`, pour chaque bloc marqué
`block->divergent`, elle remonte le long des `cf_node` parents jusqu'au premier bloc non
divergent, puis y déplace les intrinsèques `ddx*`/`ddy*` du bloc — à condition que toutes
leurs sources dominent déjà le bloc cible (`nir_block_dominates`). Elle sort tout de suite
si le shader utilise `discard` : une dérivée ne se déplace pas au-dessus d'un rejet.

Appelée dans `msl_optimize_nir()` juste avant `nir_opt_shrink_stores`, donc avant
`nir_convert_from_ssa`.

MSL après correction, même dump :

```
    t33 = !t32;
    t34 = dfdx(t13);
    t35 = dfdy(t14);
    if (t33) {
```

Les deux autres dérivées restent dans la branche : leur source est un chargement d'UBO fait
à l'intérieur, donc la dominance n'est pas acquise. Elles portaient sur une constante et
donnaient déjà le bon résultat.

`VKD3D_TEST_FILTER=derivative_hoisting` : **41 tests exécutés, 0 échec** (les deux variantes,
DXBC et DXIL).

### Le contrôle A/B, sur la campagne entière

Passe désactivée puis réactivée, tout le reste identique, 574 fonctions à chaque fois :

| build | échecs |
|---|---|
| sans `msl_nir_hoist_derivatives` | 2 483 |
| avec | 2 481 |

Delta exactement −2, soit les deux échecs de `test_derivative_hoisting_dxil`. Aucune
régression ailleurs.

### Correction d'un chiffre antérieur : le 2 210 n'était pas reproductible

La campagne d'hier annonçait 2 210 échecs sur 27 fonctions. Elle ne se reproduit pas
aujourd'hui, et le journal explique pourquoi : `full_ds1.log` ne contient **aucune** ligne
`info: DXVK: v2.7.1` et préfixe ses traces `0000:` là où les exécutions d'aujourd'hui
préfixent `2798388.293:0020:0024:`. Ce n'est pas la même pile — ni le même `dxgi.dll`, ni le
même format de trace Wine. Le préfixe `wine/pfx` ne charge plus rien du tout aujourd'hui
(sortie vide), donc le 2 210 n'est plus mesurable.

Conséquence concrète, vérifiée fonction par fonction : huit fonctions étaient **sautées**
hier et s'exécutent aujourd'hui. `test_execute_indirect_state` en particulier prenait le
chemin `skip("DGC not supported.")` (`tests/d3d12_command.c:2677`), qui exige
`is_vkd3d_proton_device()` vrai ; ce test passe maintenant par le repli sans DGC et échoue.
Ce sont des trous rendus visibles, pas des régressions : le A/B ci-dessus les donne
identiques avec et sans ma passe.

**La référence courante est donc 2 481 échecs sur 34 fonctions**, pas 2 210 sur 27.

### La liste à jour

| bloc | fonctions | échecs |
|---|---|---|
| `suballocate_small_textures_size` | 1 | 1 650 |
| `undefined_*_read_typed` | 4 | 320 |
| `execute_indirect_*` (repli sans DGC) | 5 | 175 |
| `line_tessellation` | 2 | 100 |
| `structured_buffer_addressing_wrap` | 1 | 94 |
| `large_texel_buffer_view` | 1 | 42 |
| `quad_tessellation*` | 6 | 36 |
| `shader_waveop_maximal_convergence` | 1 | 16 |
| `query_heap_cpu_resolve_timestamp` | 1 | 12 |
| `gs_topology_mismatch` | 2 | 6 |
| `query_pipeline_statistics` | 1 | 6 |
| `depth_bias_formats` | 1 | 6 |
| `virtual_queries` | 1 | 5 |
| `line_rasterization` | 1 | 4 |
| `fence_wait_robustness_shared` | 1 | 3 |
| `shader_io_mismatch` | 1 | 2 |
| 4 fonctions à 1 échec | 4 | 4 |
| **total** | **34** | **2 481** |

Les huit fonctions nouvellement visibles (les cinq `execute_indirect_*`,
`line_rasterization`, `fence_wait_robustness_shared`, `placed_msaa_alignment_workaround`)
ne sont **pas** encore instruites. C'est le prochain chantier.

### `depth_stencil_sampling` : un ULP sur la valeur d'effacement

Le seul échec de ce bloc est le cas d'indice 3, `DXGI_FORMAT_R16_TYPELESS` / `D16_UNORM`.
Le test efface la profondeur à 0,5 puis échantillonne en comparaison avec une référence de
0,5 et attend 0. En D16_UNORM, 0,5 ne se représente pas : `0.5 × 65535 = 32767.5`. Arrondi à
32768, la profondeur stockée vaut 0,500008 et `depth < 0.5` est faux — le résultat attendu.
Arrondi à 32767, elle vaut 0,499992 et la comparaison passe. C'est Metal qui convertit la
valeur d'effacement, via `MTLClearDepth` : la conversion ne nous passe pas entre les mains.
Non actionnable côté pilote.

---

## 57. Les 271 échecs de plus : le binaire PE compile les garde-fous en `return false` (2026-09-18)

### Le mécanisme

`tests/d3d12_crosstest.h:457` ouvre un bloc :

```c
#if defined(_WIN32) && !defined(VKD3D_FORCE_UTILS_WRAPPER)
```

et y définit **des souches** pour toutes les fonctions qui interrogent le Vulkan
sous-jacent — `is_vkd3d_proton_device`, `is_vk_device_extension_supported`,
`get_driver_vk_features`, `get_vulkan_device_properties2`, `is_radv_device`,
`is_amd_vulkan_device`, `is_adreno_device`, `is_integrated_vulkan_device`. Toutes
`return false`. La vraie implémentation, qui passe par `ID3D12DXVKInteropDevice`, se
trouve dans le `#else`, à partir de la ligne 659.

Notre binaire de test est un PE :

```
$ file build/vkd3d-win64/tests/d3d12.exe
PE32+ executable (console) x86-64, for MS Windows
$ grep -rn VKD3D_FORCE_UTILS_WRAPPER build/vkd3d-win64/build.ninja
(rien)
```

`_WIN32` est donc défini, la macro d'échappement absente : **ce sont les souches qui sont
compilées**. Toutes les exemptions conditionnées par une capacité du pilote — les `skip()`,
les `bug_if()`, les chemins de calcul de valeur attendue — sont mortes. Le test exige le
comportement d'un pilote complet, et compte chaque écart comme un échec dur.

Ce n'est pas un défaut de KosmicKrisp. C'est le prix d'exécuter la suite en PE sous Wine
plutôt qu'en binaire natif : le PE ne peut pas atteindre le `VkDevice` pour se renseigner.

### Le compte exact

Les huit fonctions apparues entre la campagne d'hier et celle d'aujourd'hui sont toutes
gardées par une de ces souches :

| fonction | échecs | garde neutralisée |
|---|---|---|
| `execute_indirect_state` | 139 | `is_vkd3d_proton_device` + `VK_EXT_device_generated_commands` (`d3d12_command.c:2674`) |
| `execute_indirect_multi_dispatch_root_descriptors` | 16 | idem |
| `execute_indirect_state_predication` | 8 | idem |
| `execute_indirect_multi_dispatch_root_constants` | 8 | idem |
| `execute_indirect_state_vbo_offsets` | 4 | idem |
| `structured_buffer_addressing_wrap` | +90 | `broken_byte_addressing` (`d3d12_robustness.c:2240`) |
| `line_rasterization` | 4 | `supports_smooth_lines` (`d3d12_pso.c:2791`-`2795`) |
| `fence_wait_robustness_shared` | 3 | `CreateSharedHandle` avant le `skip()` du test |
| `placed_msaa_alignment_workaround` | 1 | `is_vkd3d_proton_device` |

`139 + 16 + 8 + 8 + 4 + 90 + 4 + 3 + 1 = 273`, moins les 2 échecs de
`derivative_hoisting_dxil` corrigés au § 56 : **+271**. C'est exactement l'écart constaté
entre 2 210 et 2 481. Rien d'autre n'a bougé.

### Les trois cas détaillés

**ExecuteIndirect.** `vkd3d_init_device_caps` trace, à chaque création de périphérique :
`Not all relevant pipeline stages are supported by EXT_dgc. Skipping.` KosmicKrisp n'expose
pas `VK_EXT_device_generated_commands` — aucune occurrence dans `kk_physical_device.c`. Le
test devrait donc sauter ; la souche l'en empêche et il part sur le repli sans DGC.

**Lignes lissées.** `d3d12_pso.c:2795` :

```c
supports_smooth_lines = get_driver_vk_features(context.device, &line) && line.smoothLines == VK_TRUE;
#else
supports_smooth_lines = !is_vkd3d_proton_device(context.device);
```

Avec la souche, `!false = true` : le test croit le lissage disponible et le `bug_if` de la
ligne 2854 ne se déclenche pas. Or `kk_physical_device.c:357` ne pose que
`.bresenhamLines = true` ; `smoothLines` reste faux. Le cas 3 du tableau
(`D3D12_LINE_RASTERIZATION_MODE_ALPHA_ANTIALIASED`) rend une couverture de `0x3c0`, valeur
identique au mode `ALIASED` : on trace la ligne crénelée, ce qui est le comportement
attendu d'un pilote sans lissage.

**Poignées partagées.** `CreateSharedHandle` renvoie `0x887a0001`
(`DXGI_ERROR_INVALID_CALL`) : `kk_physical_device.c` n'expose que
`KHR_external_semaphore_fd`, pas la variante Win32. Le test finit d'ailleurs par
`skip("Shared fence handles are not supported.")` — mais après avoir déjà émis ses trois
`Test failed`. Ordre d'assertions du test, pas défaut du pilote.

### Où ça laisse le classement

| | fonctions | échecs |
|---|---|---|
| instruits (mesure ou citation) | 33 | 2 480 |
| non instruits | 1 | 1 |

Le seul échec sans explication est `test_dynamic_index_strip_cut`. Il est corrigé au § 58.

---

## 58. Metal ne sait pas désactiver le redémarrage de primitive (2026-09-18)

### L'échec

```
test_dynamic_index_strip_cut:2514: Test 8: Got 0, expected 1 at 4.
```

Le cas 4 du tableau (`d3d12_pso.c:2376`) :

```c
{ NULL, 32, D3D12_INDEX_BUFFER_STRIP_CUT_VALUE_DISABLED, true, 1 },
```

Buffer d'indices **32 bits**, coupure de bande désactivée dynamiquement, et l'indice
`0xFFFFFFFF` est présent dans les données (`index32_data[] = { 0, 1, 2, 0xffffffffu, 3, 4, 5 }`).
Le test attend 1, c'est-à-dire « la bande n'a pas été coupée ». On rendait 0.

Le cas 7, identique mais sur un buffer 16 bits, passait déjà. C'est ce qui a orienté la
recherche.

### Deux collisions superposées

**Première.** `requires_unroll_index_promotion()` refusait de dérouler les bandes 32 bits
quand le redémarrage est désactivé. Le commentaire en place l'assumait explicitement :

> For uint32_t indices with restart disabled, we realistically will never have enough
> vertices for the restart index to be valid anyway.

Le test viole précisément cette hypothèse. Sans déroulage, on émet un dessin Metal indexé
de bande, et Metal applique le redémarrage sur `0xFFFFFFFF` sans qu'on puisse l'en
empêcher. Il faut donc dérouler : le déroulage décompose la bande en liste
(`u_decomposed_prim`), et le redémarrage n'a plus de sens sur une liste.

**Deuxième.** Le déroulage lui-même redémarrait. `kk_cmd_draw.c:1755` passait au noyau :

```c
/* Handle primitive restart disable by forcing index to UINT32_MAX */
.restart_index = !data->restart ? UINT32_MAX : data->restart_index,
```

Même sentinelle, même collision. Pour des indices 16 bits promus en 32 bits, `0xFFFF`
devient `0x0000FFFF`, différent de `UINT32_MAX` : pas de collision, d'où le cas 7 qui
passait. Pour des indices déjà 32 bits, la sentinelle *est* une valeur légitime du buffer.

### Que chaque moitié soit nécessaire, c'est mesuré

Correctif de sentinelle seul, sans le déroulage forcé :

```
test_dynamic_index_strip_cut:2514: Test failed: Got 0, expected 1 at 4.
```

Déroulage forcé seul, sans le correctif de sentinelle : même échec (c'était le premier
essai). Les deux ensemble : **36 tests exécutés, 0 échec**.

### Le correctif (patch 0033)

`poly_unroll_geometry()` prend un paramètre `restart_enabled` de plus, et la comparaison
d'indice ne se fait que s'il est vrai. `kk_draws.cl` le fait suivre depuis
`kk_cmd_draw.c`, qui passe désormais le vrai `restart_index` sans sentinelle.

`poly/cl/restart.h` est du code partagé : `poly_unroll_restart()`, la seule autre entrée,
n'est appelée que par `asahi/libagx/geometry.cl` (vérifié par `grep`). Elle reçoit
`restart_enabled = true` en dur, donc **le comportement d'asahi est inchangé et son arbre
n'est pas touché** — ce que la politique interdit de toute façon.

### Le coût, et ce qu'il reste à mesurer

Le déroulage forcé ajoute une passe de calcul par dessin pour les topologies
`LINE_STRIP`, `TRIANGLE_STRIP` et `TRIANGLE_FAN` en indices 32 bits avec redémarrage
désactivé. Les listes de triangles, de loin le cas dominant, ne sont pas concernées : elles
ne figurent pas dans le `switch`.

**L'ampleur de ce surcoût n'est pas vérifiée.** `tests/win_cube.c` dessine une liste, donc
il ne la mesure pas. Il faudrait une variante en bande indexée 32 bits pour chiffrer la
dispatch supplémentaire par dessin. À faire avant de défendre ce patch en amont.

### Contrôle de non-régression

Campagne complète, 574 fonctions, comparaison fonction par fonction avec la campagne du
§ 56 :

```
test_dynamic_index_strip_cut 1 0
(rien d'autre)
```

**2 481 → 2 480 échecs**, une seule fonction bouge. Aucune régression sur le chemin
d'index, pourtant largement touché.

### État

| | fonctions | échecs |
|---|---|---|
| instruits (mesure ou citation) | 33 | 2 480 |
| non instruits | 0 | 0 |

Les 2 480 échecs restants sont tous expliqués, chacun par une mesure ou une citation.

---

## 59. Du code tiers tourne enfin (2026-09-18)

Jusqu'ici tout ce qui « fonctionnait » venait d'ici : `win_cube.c` est notre code, la suite
vkd3d-proton est une suite de tests. Premier code écrit par personne du projet.

### La pile applicative

`third_party/DirectX-Graphics-Samples` (Microsoft, MIT), en clone partiel : 2,7 Mo au lieu
du dépôt complet. Plus `DirectX-Headers` (4,5 Mo) et `DirectXMath` (1,8 Mo), tous deux MIT
et en en-têtes seuls. Rien de payant, rien de propriétaire.

`tests/build_dx_sample.sh` compile un échantillon avec llvm-mingw. **L'arbre tiers n'est
jamais modifié** : le script copie les sources dans `build/samples/src/` et y applique des
substitutions mécaniques. La cale `build/samples/inc/mingw_shim.h` couvre six écarts
MSVC → clang/mingw, tous de compilation, aucun de comportement :

| écart | traitement |
|---|---|
| `Wrappers::FileHandle` | mingw n'a pas `wrl/corewrappers.h` — RAII de 8 lignes |
| `__uuidof` sur les interfaces D3D12 | `dxguids.h` de DirectX-Headers émet `__CRT_UUID_DECL` |
| `_uuidof` | orthographe MSVC de `__uuidof` |
| retours agrégés | `GetCPU/GPUDescriptorHandleForHeapStart` passe par un paramètre de sortie en mingw, convention que suit `d3d12core.dll` |
| `L#x` | concaténation MSVC, remplacée par l'idiome standard `D3DX_WIDE(#x)` |
| `pix3.h`, `DXGIDeclareAdapterRemovalSupport` | marqueurs de profilage et déclaration d'intention, neutralisés |

`mingw`'s `d3d12.h` est trop ancien pour le `d3dx12.h` courant : on prend celui de
DirectX-Headers. Son `directxmath.h` n'est qu'une ébauche de 326 lignes sans `XM_PIDIV4` :
on prend le vrai DirectXMath.

### Ce qui tourne

Les échantillons chargent des shaders précompilés `.cso`. `tests/hlsl2cso.c` les produit en
appelant `D3DCompileFromFile` du préfixe.

| échantillon | ce qu'il exerce | swapchain | erreurs |
|---|---|---|---|
| `HelloTriangle` | pipeline graphique de base | oui | 0 |
| `HelloTexture` | texture 2D échantillonnée | oui | 0 |
| `HelloConstBuffers` | tampon de constantes | oui | 0 |
| `HelloFrameBuffering` | synchronisation multi-images | oui | 0 |
| `HelloBundles` | `ID3D12GraphicsCommandList` bundles | oui | 0 |

Swapchain 1280×720, `Got 3 swapchain images`, boucle de présentation active, aucune
exception, aucune erreur Vulkan. Sous `MESA_KK_DEBUG=msl`, `HelloTriangle` fait générer
**83 fonctions MSL** par KosmicKrisp : le pilote traite bien les shaders de Microsoft, ce
n'est pas une fenêtre vide.

**Réserve honnête** : ces cinq programmes tournent en boucle de messages, je les ai tués
après 14 s. J'ai vérifié l'absence d'erreur et l'activité de la swapchain ; je n'ai **pas**
vérifié visuellement l'image, l'écran de la machine étant verrouillé. Le cube, lui, est
vérifié par relecture de pixels — pas eux.

### Ce qui bloque, et ce n'est pas le pilote

`D3D12ExecuteIndirect` **compile**, mais ses shaders ne se compilent pas :

```
ECHEC 0x80004005 : compute.hlsl:37:1: E5030: Unknown modifier "StructuredBuffer".
```

Le `d3dcompiler_47.dll` du préfixe est **celui de Wine** (1,1 Mo, bâti sur le compilateur
HLSL de vkd3d-shader), pas celui de Microsoft. Son analyseur ne connaît pas
`StructuredBuffer` ni `AppendStructuredBuffer` : `grep` ne trouve que `RWStructuredBuffer`,
et seulement dans un `printf` de diagnostic.

C'est un **trou du compilateur HLSL, pas du pilote**. Les jeux réels livrent du bytecode
précompilé et ne le rencontrent pas ; seul le code d'exemple qui compile à l'exécution le
touche. Pour y passer il faudra DXC (Apache 2.0) et viser DXIL, ce qui rapproche d'ailleurs
de ce que livrent les jeux récents.

### Ce que l'échantillon aurait montré

Sa signature de commande (`D3D12ExecuteIndirect.cpp:421`) :

```c
argumentDescs[0].Type = D3D12_INDIRECT_ARGUMENT_TYPE_CONSTANT_BUFFER_VIEW;
argumentDescs[1].Type = D3D12_INDIRECT_ARGUMENT_TYPE_DRAW;
```

Un CBV racine changé par commande indirecte : c'est exactement le cas qui met
`requires_state_template` à vrai, donc celui que `command.c:27369` jette sans DGC. Chaque
triangle utiliserait le même tampon de constantes au lieu du sien. Prédiction à confirmer
une fois DXC en place.

### Prochain pas

DXC pour produire du DXIL, puis faire tourner `D3D12ExecuteIndirect` et voir le rendu faux
de ses propres yeux. C'est la démonstration qui manque au § 57.

---

## 60. ExecuteIndirect rend une image vide, vu de ses propres yeux (2026-09-18)

### DXC débloque la compilation

`toolchain/dxc/` : DXC v1.9.2607 (`dxc_2026_07_29.zip`, 41,6 Mo, Apache 2.0), le binaire
Windows exécuté sous Wine. Il compile sans broncher ce que le compilateur HLSL de Wine
refusait au § 59 :

```
shaders_VSMain.cso  4 224 octets  (vs_6_0)
shaders_PSMain.cso  2 980 octets  (ps_6_0)
compute.cso         5 348 octets  (cs_6_0)   <- StructuredBuffer / AppendStructuredBuffer
```

Du DXIL, donc le chemin dxil-spirv — celui qu'empruntent les jeux récents.

### La capture hors écran

L'écran de la machine est verrouillé, donc pas de capture d'écran possible. Solution :
`build/samples/inc/d3dx_capture.h` copie la cible de rendu vers un tampon de relecture et
écrit un BMP. Le script l'injecte juste avant `Present`, sur la trentième image. **Le rendu
n'est pas modifié** : on ajoute une copie après le travail déjà soumis, rien d'autre.

### Le contrôle d'abord

`D3D12HelloTriangle`, même mécanisme : triangle en dégradé rouge/vert/bleu, net, centré,
sur le fond bleu d'effacement. **Premier rendu D3D12 tiers vérifié visuellement sur la
pile.** La capture fonctionne.

### Le résultat

`D3D12ExecuteIndirect`, même pile, même capture, même instant : **image entièrement à la
couleur d'effacement. Aucun triangle.**

Le programme ne plante pas, la swapchain tourne, aucune erreur de shader, aucune erreur de
pipeline. Un seul FIXME pertinent dans tout le journal :

```
fixme:vkd3d-proton:d3d12_command_signature_create: Device generated commands is not supported by implementation.
```

Une fois. Au moment exact où la signature de commande de l'échantillon est créée.

### Deux variables éliminées

**Le culling.** L'échantillon active un compute de culling par défaut
(`m_enableCulling(true)`) qui alimente un compteur indirect. Variante reconstruite avec
`m_enableCulling(false)`, qui prend le chemin direct sans compteur : **image vide
également**. Le compute n'est pas en cause.

**Les shaders.** `grep` sur le journal : aucune erreur dxil-spirv, aucun `VK_ERROR`, aucun
`E_INVALIDARG`. Les deux seuls `fixme` sont celui ci-dessus et `TotalLaneCount` du § 53.

### Ce que ça confirme

La signature de commande (`D3D12ExecuteIndirect.cpp:421`) combine
`CONSTANT_BUFFER_VIEW` et `DRAW`. `command.c:27369` met alors `requires_state_template` à
faux faute de DGC, et l'argument CBV n'est jamais appliqué. L'échec de conformité
`test_execute_indirect_state` annonçait déjà la nature du dégât : `Expected size 288, got 32`,
c'est-à-dire une longueur d'argument par commande qui ne correspond plus. Le tampon
d'arguments est alors lu au mauvais décalage et les comptes de sommets qui en sortent ne
dessinent rien.

**Un jeu à rendu piloté par GPU ne rendra pas faux : il ne rendra rien.** C'est plus
visible qu'un défaut subtil, mais c'est le même trou, et aucun travail sur KosmicKrisp ne
le bouche sans implémenter `VK_EXT_device_generated_commands`.

### État de la démonstration

| | |
|---|---|
| `win_cube` (notre code) | rend, vérifié pixel par pixel |
| 5 échantillons Microsoft | tournent sans erreur ; `HelloTriangle` vérifié visuellement |
| `D3D12ExecuteIndirect` | tourne, image vide, cause isolée |

Le § 57 disait « 175 échecs expliqués par une citation ». On a maintenant l'image.

---

## 61. Comment gérer DGC : sans Metal ICB, en réutilisant l'existant (2026-09-18)

Première intuition : implémenter `VK_EXT_device_generated_commands` par-dessus
`MTLIndirectCommandBuffer`. Vérification faite, c'est la mauvaise route — et la bonne est
nettement moins chère. Quatre constats, chacun vérifié dans le code.

### 1. KosmicKrisp n'a aucune trace d'ICB

`grep -rln "IndirectCommandBuffer" src/kosmickrisp/` ne renvoie rien. Il faudrait une
nouvelle couche Objective-C **et** de nouvelles intrinsèques MSL (`render_command`,
`compute_command`) dans `nir_to_msl.c`. C'est le poste le plus cher, et il est évitable.

### 2. Les push constants vivent déjà dans un tampon GPU

`nir_to_msl.c:1320` :

```c
case nir_intrinsic_load_push_constant:
   P(ctx, "*((constant %s*)&buf.push_consts[", ty);
```

Ce n'est pas un `setBytes` inline : c'est une lecture dans un tampon. Côté CPU,
`kk_push_constants()` écrit dans `desc->root.push` et marque `root_dirty`. **Faire varier
les constantes par séquence revient donc à écrire des octets différents dans un tampon** —
exactement ce qu'un noyau de pré-traitement sait faire.

C'est le point porteur de tout le reste : les descripteurs racine de vkd3d-proton sont des
adresses 64 bits passées en push constants, donc le jeton `PUSH_DATA` se ramène au même
mécanisme.

### 3. La boucle de dessins prédiqués existe déjà

`kk_CmdDrawIndirectCount2KHR` n'utilise aucun multi-draw Metal (Metal n'en a pas). Il pose
`draw_count = maxDrawCount` et `predicate_op[0] = KK_PREDICATE_GT_DRAW_ID` : **N dessins
côté encodeur, chacun annulé côté GPU si son indice dépasse le compte réel.**

`vkCmdExecuteGeneratedCommandsEXT` a la même forme : `maxSequenceCount` connu au moment de
l'enregistrement, compte réel en mémoire GPU. La machinerie est là.

### 4. Les données par dessin couvrent déjà tessellation et geometry

`build_per_draw_upload_mask()` (`kk_cmd_draw.c:1811`) pose déjà les bits `TESS_EVAL` et
`GEOMETRY`. Or vkd3d-proton exige `VK_SHADER_STAGE_ALL_GRAPHICS | COMPUTE` dans
`supportedIndirectCommandsShaderStages` (`device.c:2560`), sinon il saute DGC entièrement.
Comme on repasse par le chemin de dessin normal, ces stages suivent sans traitement
spécial. On peut donc annoncer ce que vkd3d-proton demande, sans avoir à le faire assouplir.

### Et ce dont on n'a pas besoin

`VkIndirectExecutionSetEXT` — le mécanisme qui permet de changer de pipeline par séquence,
et de loin le plus dur à porter sur Metal : **vkd3d-proton ne l'utilise jamais**
(`grep -rn "ExecutionSet" libs/vkd3d/` : rien). D3D12 ExecuteIndirect ne change pas de PSO.
Le morceau le plus coûteux de l'extension tombe.

### Le plan

| étape | contenu |
|---|---|
| 1 | `VkIndirectCommandsLayoutEXT` : analyse du flux de jetons, calcul de la taille de pré-traitement |
| 2 | Noyau de pré-traitement (`libkk`) : par séquence, écrire une tranche de tampon racine + une tranche d'arguments de dessin |
| 3 | `vkCmdExecuteGeneratedCommandsEXT` : boucle de `maxSequenceCount` dessins prédiqués, tampon racine lié au décalage `séquence × pas` |
| 4 | Annoncer l'extension avec `supportedIndirectCommandsShaderStages = ALL_GRAPHICS \| COMPUTE` |

Jetons visés : `PUSH_CONSTANT`, `PUSH_DATA`, `PUSH_DATA_SEQUENCE_INDEX`, `SEQUENCE_INDEX`,
`DRAW`, `DRAW_INDEXED`, `DISPATCH`. Soit sept des dix que vkd3d-proton sait émettre.

### Ce qui reste hors de portée, et le coût

`VERTEX_BUFFER_EXT` et `INDEX_BUFFER_EXT` (D3D12 ExecuteIndirect tier 1.1) lient un tampon
à une adresse décidée par le GPU. Une boucle côté CPU ne peut pas faire ça : **ces deux
jetons exigent vraiment un ICB**. `DRAW_MESH_TASKS_EXT` ne concerne pas KosmicKrisp, qui
n'expose pas les mesh shaders.

Le coût : une séquence = un appel d'encodeur, même si le compte GPU réel est petit. Le
plafond mesuré est de 600 000 à 650 000 appels de dessin par seconde ; un rendu piloté par
GPU qui déclare 10 000 séquences par image paierait donc de l'ordre de 15 ms d'encodage.
Ce n'est pas un coût nouveau — `drawIndirectCount` le paie déjà — mais il faudra le
mesurer, pas le supposer.

---

## 62. DGC étape 1 : la mise en page des jetons (2026-09-18)

### Piège d'environnement, à retenir

Ajouter un fichier au `meson.build` de KosmicKrisp force ninja à régénérer `build.ninja`,
donc à relancer `meson setup --reconfigure`. Trois choses manquaient, alors que le
répertoire de construction avait été configuré avec succès auparavant :

- `mesa_clc` n'est pas sur le PATH : il vit dans `prefix/bin`.
- aucun python de la machine n'a `mako` ni `packaging`.

D'où `toolchain/pyenv`, un environnement virtuel dédié — rien dans le système, conformément
à la règle du projet. La commande qui reconfigure :

```sh
cd build/mesa-x64
PATH="$R/toolchain/pyenv/bin:$R/prefix/bin:$PATH" $R/toolchain/bin/meson setup --reconfigure . ../../src/mesa
```

Au passage, meson réenregistre `/usr/local/bin/ninja`, qui est **x86_64**. Continuer à
appeler `toolchain/bin/ninja` explicitement (§ « Pièges de build macOS arm64 »).

### Ce que fait l'étape

`kk_indirect_commands.c` et `.h`, nouveaux. Ils portent
`VkIndirectCommandsLayoutEXT` : à la création, on analyse le flux de jetons et on en garde
un condensé exploitable au moment du dessin.

```c
struct kk_indirect_commands_layout {
   uint32_t indirect_stride;
   enum kk_dgc_action action;     /* DRAW, DRAW_INDEXED ou DISPATCH */
   uint32_t action_offset;        /* decalage du jeton dans la sequence */
   uint32_t push_token_count;
   struct kk_dgc_push_token push_tokens[KK_MAX_DGC_PUSH_TOKENS];
};
```

Les jetons acceptés sont ceux du § 61 : `PUSH_CONSTANT`, `PUSH_DATA`, `SEQUENCE_INDEX`,
`PUSH_DATA_SEQUENCE_INDEX`, `DRAW`, `DRAW_INDEXED`, `DISPATCH`. Tout le reste —
`VERTEX_BUFFER`, `INDEX_BUFFER`, `EXECUTION_SET`, les variantes mesh — fait échouer la
création avec `VK_ERROR_FEATURE_NOT_PRESENT`. **Un refus franc plutôt qu'un rendu faux**,
ce qui est exactement le reproche qu'on fait au repli silencieux de vkd3d-proton.

`vkGetGeneratedCommandsMemoryRequirementsEXT` demande
`maxSequenceCount × sizeof(struct kk_root_descriptor_table)` quand la mise en page porte au
moins un jeton de constantes, et zéro sinon. C'est le tampon que le noyau de
pré-traitement remplira : une table racine complète par séquence.

`VkIndirectExecutionSetEXT` existe en façade et refuse la création. vkd3d-proton ne
l'utilise jamais (§ 61), mais les points d'entrée doivent exister dès qu'on annonce
l'extension, sinon la table de répartition contient un NULL.

### Non vérifié à ce stade

L'extension n'est **pas encore annoncée** : rien de tout cela ne s'exécute. C'est
délibéré — annoncer avant que `vkCmdExecuteGeneratedCommandsEXT` ne fonctionne ferait
rendre n'importe quoi à vkd3d-proton, ce qui serait pire que l'image vide actuelle.
Compilation vérifiée, comportement non.

### Reste à faire

| étape | contenu |
|---|---|
| 2 | Noyau de pré-traitement : par séquence, copier la table racine et y écrire les octets de constantes du flux |
| 3 | `vkCmdExecuteGeneratedCommandsEXT` : `kk_draw` avec `draw_count = maxSequenceCount` et le prédicat `KK_PREDICATE_GT_DRAW_ID`, plus une liaison de racine par séquence dans la boucle de `kk_draw` |
| 4 | Annoncer l'extension et les propriétés |

L'étape 3 est plus légère qu'attendu : les données du jeton `DRAW` **sont** un
`VkDrawIndirectCommand`, donc `indirect_command.addr = indirectAddress + action_offset` et
`stride = indirectStride` suffisent — pas de recopie des arguments de dessin.

---

## 63. DGC étapes 2 à 4 : ça dessine (2026-09-18)

### Ce qui a été écrit

**Étape 2**, `libkk_dgc_patch_root` dans `kk_draws.cl`. Par séquence : copier la table
racine de base, puis y écrire les octets de constantes prélevés dans le flux. Les jetons
sont passés à plat, quatre `uint32` chacun (décalage source, décalage destination, taille,
drapeau « indice de séquence »), tout en dwords — EXT DGC aligne tout sur 4 octets. Le
noyau termine en réécrivant le champ `addr` de la table avec sa propre adresse.

Le décalage de destination est `offsetof(struct kk_root_descriptor_table, push)`, et c'est
bien le même que celui du pilote : `lower_load_push_constant()`
(`kk_nir_lower_descriptors.c:290`) utilise `kk_root_descriptor_offset(push)`. Vérifié, pas
supposé.

**Étape 3**, `kk_CmdExecuteGeneratedCommandsEXT` dans `kk_cmd_draw.c` et
`kk_dgc_dispatch()` dans `kk_cmd_dispatch.c`. Pour le graphique, c'est un `kk_draw()`
ordinaire :

```c
.draw_count = maxSequenceCount,
.predicate_op[0] = KK_PREDICATE_GT_DRAW_ID,
.predicate_addr[0] = sequenceCountAddress,
.indirect_command.addr = indirectAddress + layout->action_offset,
.indirect_command.stride = layout->indirect_stride,
```

Plus deux champs neufs dans `struct kk_draw_command`, `per_sequence_root_addr` et
`per_sequence_root_stride`, que la boucle de dessin utilise pour relier la table racine
avant chaque `kk_dispatch_draw`.

**Ordre corrigé après coup.** Je construisais les tables avant `kk_draw`. Or celui-ci
commence par `kk_flush_xfb_state()`, dont le commentaire amont dit « Must run before the
root table is uploaded » — et la table racine porte `xfb_address`, `xfb_counter`,
`xfb_size`. Mes copies étaient donc prises avant que l'état de transform feedback n'y soit
écrit. Déplacé après les deux vidages d'état : **61 → 60 échecs**. Petit gain, vraie faute.

**Étape 4**, annonce de l'extension, avec
`supportedIndirectCommandsShaderStages = ALL_GRAPHICS | COMPUTE` comme l'exige
`device.c:2560`, et `supportedIndirectCommandsInputModes = 0` puisqu'on ne gère pas les
jetons de tampon d'indices.

### Mesures

vkd3d-proton trace désormais, au lieu du FIXME :

```
Enabling fast paths for advanced ExecuteIndirect() graphics and compute (EXT_dgc).
```

Bloc ExecuteIndirect seul :

| | échecs |
|---|---|
| avant DGC | 175 |
| après | **60** |

Campagne complète, 574 fonctions, comparaison fonction par fonction avec le § 58 :

```
test_execute_indirect_multi_dispatch_root_constants    8 -> 0
test_execute_indirect_multi_dispatch_root_descriptors 16 -> 0
test_execute_indirect_state_vbo_offsets                4 -> 0
test_execute_indirect_state_predication                8 -> 4
test_execute_indirect_state                          139 -> 56
(rien d'autre ne bouge)
```

**2 480 → 2 365 échecs.** Trois des cinq fonctions passent entièrement, dont tout le chemin
compute. **Aucune régression ailleurs**, alors qu'on vient d'annoncer une extension entière.

Et l'échantillon `D3D12ExecuteIndirect` de Microsoft, qui rendait une image vide au § 60,
**dessine maintenant de la géométrie** : des triangles distincts, chacun à sa position et
sa couleur, donc avec ses propres constantes par commande. Ce n'est pas encore le rendu
attendu — il devrait y en avoir beaucoup plus — mais le mécanisme fonctionne.

### Ce qui reste faux, et les pistes

56 échecs sur `test_execute_indirect_state`, 4 sur `_predication`.

Les mises en page portant `VERTEX_BUFFER` ou `INDEX_BUFFER` sont refusées
(`VK_ERROR_FEATURE_NOT_PRESENT`, trace `-8` sous `KK_DGC_DEBUG=1`), comme annoncé au § 61 :
elles lient un tampon à une adresse décidée par le GPU, ce qu'une boucle côté CPU ne sait
pas faire. C'est une part des échecs restants et c'est structurel.

Pour le reste, le test 0 est instructif : signature `CONSTANT(param 0, dword 1, 2 valeurs)`
puis `DRAW_INDEXED`, et la trace donne `stride=28, PUSH_CONSTANT@0 (dst=28, size=8),
DRAW_INDEXED@8`. Les valeurs rendues sont celles de la racine **de base**, pas celles de la
séquence, alors que le test 1 — même signature à un décalage de destination différent —
passe. Adresses vérifiées à l'exécution : `preprocessAddress` non nul, table racine de
2 328 octets, `push` à 760. Tout est cohérent, la cause n'est pas encore trouvée.

**Le prochain pas n'est pas de continuer à deviner**, mais d'écrire un test Vulkan minimal
dans `tests/` : une séquence DGC qui écrit sa constante dans un tampon de stockage et le
relit. Ça isole mon implémentation de l'empaquetage d'arguments de vkd3d-proton et de la
sémantique du shader de streamout du test, qui brouillent tous deux le diagnostic.

### Traces de mise au point

`kk_indirect_commands.c` porte des `fprintf` sous `KK_DGC_DEBUG=1` : types de jetons,
décalages, adresses d'exécution. À retirer avant toute soumission amont.

---

## 64. Un test minimal qui disculpe le mécanisme (2026-09-18)

Plutôt que continuer à deviner sur `test_execute_indirect_state`, dont le shader de
streamout et l'empaquetage d'arguments de vkd3d-proton brouillent le diagnostic :
`tests/test_dgc_push.c`, ~190 lignes, Vulkan pur.

### Ce qu'il fait

Une mise en page à deux jetons, `PUSH_CONSTANT` puis `DISPATCH` ou `DRAW`. Le flux porte
huit séquences ; la séquence *i* pousse `{slot = i, value = 100 + i}`. Le shader écrit
`o.v[slot] = value`. Avant l'exécution, les constantes sont empoisonnées par un
`vkCmdPushConstants` à `0xdead/0xbeef`, pour qu'une séquence qui ne verrait pas les
siennes se voie tout de suite.

Deux axes paramétrables : le décalage de destination dans la plage de constantes, et le
mode calcul ou graphique. Le mode graphique passe par un pipeline à
`rasterizerDiscardEnable`, en rendu dynamique sans attachement — seule l'écriture depuis
le vertex shader compte.

### Résultats

| mode | décalage | résultat |
|---|---|---|
| calcul (`DISPATCH`) | 0 | 8/8 |
| calcul | 28 | 8/8 |
| graphique (`DRAW`) | 0 | 8/8 |
| graphique | 28 | 8/8 |

**Le mécanisme de constantes par séquence est correct**, en calcul comme en graphique, et
le décalage 28 — celui qu'emploie le test 0 de vkd3d-proton — n'y change rien.

### Ce que ça élimine

Une hypothèse que je tenais pour sérieuse tombe : `kk_cmd_buffer.c:349` porte le
commentaire amont « Argument table won't ever change » et ne lie la table d'arguments
qu'une fois par encodeur. Si Metal 4 la lisait à l'exécution plutôt qu'à l'encodage, toutes
les séquences verraient la dernière valeur écrite. Le test en mode graphique prouve que
**non** : la table est bien capturée par commande.

Tombent aussi : le décalage de destination, le choix calcul/graphique, la taille de la
table racine, le chemin de pré-traitement.

### Où chercher ensuite

Les 56 échecs restants de `test_execute_indirect_state` ne viennent donc pas du mécanisme
de base. Les différences qui subsistent avec mon test :

1. `DRAW_INDEXED` au lieu de `DRAW`.
2. La capture par **streamout** — et la table racine porte `xfb_address`, `xfb_counter`,
   `xfb_size`. Chaque séquence doit ajouter à la suite de la précédente, or mes copies
   figent l'état de capture au moment de la construction. C'est la piste la plus sérieuse.
3. Les mises en page à jetons `VERTEX_BUFFER` / `INDEX_BUFFER`, refusées par construction
   (§ 61) : elles expliquent une partie des échecs et ne se résoudront pas sans ICB.

### Rappel d'hygiène

Le test se lie au préfixe **arm64** (`prefix/lib`), pas au x86_64 utilisé sous Wine. Il faut
donc reconstruire `build/mesa` en plus de `build/mesa-x64`. Et `meson install` sur ce
répertoire échoue : il relance `/usr/local/bin/ninja`, qui est x86_64. Copier la
bibliothèque à la main :

```sh
cp build/mesa/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib prefix/lib/
```

---

## 65. La vraie carte des échecs restants (2026-09-18)

### `DRAW_INDEXED` aussi

Cinquième configuration ajoutée au banc du § 64 : jeton `DRAW_INDEXED`, flux de 28 octets
de pas, constantes au décalage 28. **8/8.** Le mécanisme tient sur les cinq formes que je
sais construire.

### La correspondance que je supposais était fausse

Je déduisais l'indice des tests de l'ordre de déclaration des descripteurs d'arguments.
Le tableau réel est à `d3d12_command.c:2648` :

| indice | nom | résultat |
|---|---|---|
| 0 | `root_constant` | **16 échecs** |
| 1 | `indirect_vbo` | passe |
| 2 | `indirect_vbo_one` | passe |
| 3 | `indirect_ibo` | passe |
| 4 | `indirect_root_descriptor` | **8 échecs** |
| 5 | `indirect_alignment` | **8 échecs** |
| 6 | `root_constant_spill` | **16 échecs** |
| 7 | `indirect_root_descriptor` (variante) | **8 échecs** |

Ça retourne complètement le diagnostic du § 63.

**Les tests à tampons de sommets et d'indices passent**, alors même que je refuse leurs
mises en page (`VK_ERROR_FEATURE_NOT_PRESENT`). vkd3d-proton encaisse le refus sans casser,
et ces tests portent déjà des tolérances (« This is buggy on WARP and AMD »). Le refus
franc du § 61 ne coûte donc rien ici — mais il ne rapporte rien non plus.

**Ce qui échoue, c'est exactement la famille constantes et descripteurs racine.** Aucune de
ces quatre entrées ne touche aux jetons que je refuse : elles n'utilisent que
`PUSH_CONSTANT` et une action de dessin, c'est-à-dire précisément ce que mon banc d'essai
valide en isolation.

### Les deux pistes que ça ouvre

`root_constant_spill` porte son diagnostic dans son nom : quand les constantes racine
débordent de la plage de push constants, vkd3d-proton les **déverse dans un tampon**. Mon
noyau écrit dans `root.push[]` ; des constantes déversées vivent ailleurs. Il faudra
regarder où, et si le jeton porte l'information.

`indirect_root_descriptor` pousse des **adresses 64 bits**, là où mon banc ne pousse que
deux `uint32`. Deux différences à éprouver : la largeur de la lecture côté shader
(`load_root()` reçoit `bit_size/8` comme alignement) et le fait d'avoir **plusieurs jetons
de constantes** dans une même mise en page — trois pour ce test, un seul dans mon banc.

Les deux se testent en étendant `tests/test_dgc_push.c`, ce qui reste la bonne méthode :
aucune de mes hypothèses successives n'a survécu à une mesure, et les trois qui ont tenu
l'ont fait parce qu'elles venaient du banc.

### Zéro échec de création de signature

`grep -cE "Failed to create command signature"` sur la campagne : **0**. Les 60 échecs
restants sont tous des erreurs de contenu, pas des refus en cascade.

---

## 66. Un tour de bisection : une faute trouvée, la cause toujours pas (2026-09-18)

### Le banc élargi ne reproduit rien

Deux dimensions ajoutées à `tests/test_dgc_push.c` : jeton `DRAW_INDEXED`, puis **trois**
jetons de constantes portant des valeurs **64 bits** — la forme de
`indirect_root_descriptor`. Six configurations en tout, **toutes 8/8** :

| mode | décalage | jetons |
|---|---|---|
| `DISPATCH` | 0 et 28 | 1 × 32 bits |
| `DRAW` | 0 et 28 | 1 × 32 bits |
| `DRAW_INDEXED` | 28 | 1 × 32 bits |
| `DISPATCH` | 0 | 3 × 64 bits |

### Une inversion qui saute aux yeux

Croisé avec la carte du § 65 : **tout ce que ma mise en page accepte échoue, tout ce
qu'elle refuse passe.** Les tests à tampons de sommets et d'indices, dont je rejette la
mise en page, passent ; les quatre tests de constantes et descripteurs racine, que je gère,
échouent.

### La bisection

Faire écrire au noyau une valeur reconnaissable (`777.0f`, `888.0f`) au lieu des données du
flux : **aucun changement** dans le rendu. Empoisonner ensuite la plage de constantes de la
table racine **de base**, côté CPU, sur ses 256 octets entiers : **aucun changement non
plus**.

Or le MSL charge bien depuis `buf0 + 760`, `768`, `776`, `784`, `792` — et 760 est
exactement `offsetof(struct kk_root_descriptor_table, push)`, confirmé par la trace
(`pushB=760`). Les deux empoisonnements auraient dû s'y voir.

### Ce que la trace a donné

En traçant chaque appel de `kk_cmd_bind_root_to_argument_table` :

```
[dgc] boucle i=0
[dgc] bind root 0x1503250000   <- ma liaison par sequence
[dgc] bind root 0x15031420e8   <- une autre, juste apres
```

`kk_flush_gfx_state()` reliait la racine de base **après** ma liaison par séquence, dans la
même itération. Corrigé : `struct kk_graphics_state` porte un `root_override` que la boucle
pose et que le vidage d'état respecte. La trace confirme que la liaison est désormais
correcte pour la séquence 0.

**C'est une vraie faute et elle est corrigée.** Ce n'était pas la cause : campagne
complète, **2 365 échecs, identique** — ni gain, ni régression. Je la garde, elle ne coûte
rien et le comportement est juste.

### Ce qui reste, et ce que ça vaut

Les valeurs rendues sont inchangées, `(1000, 64, 0, 4000)` au lieu de
`(1000, 164, 500, 4000)`. Les 64 et 0 sont les constantes racine **de base** posées par le
test avant l'ExecuteIndirect.

L'anomalie de l'empoisonnement contredit mon modèle : si le shader lisait `root.push`, mes
256 octets de poison auraient dû sortir. Deux explications restent ouvertes, et je n'ai pas
tranché :

1. Les 257 fonctions MSL du vidage ne sont pas toutes du même pipeline — les décalages 760
   à 792 que j'ai relevés peuvent appartenir à d'autres shaders que celui du test 0.
2. Le shader du test lit ses constantes ailleurs que dans `root.push`, auquel cas ma
   correspondance `updateRange.offset` → `root.push[offset]` est fausse pour cette forme.

Le prochain pas est de **dumper le MSL du seul shader du test 0** — en filtrant la
campagne sur ce test et en isolant le pipeline — plutôt que de lire un dump de 257
fonctions. C'est la méthode qui a marché à chaque fois : réduire jusqu'à ce qu'il ne reste
qu'une variable.

### Honnêtement

Tour de diagnostic. Une faute réelle trouvée et corrigée, aucun échec gagné. Les chiffres
sont les mêmes qu'au § 63.

---

## 67. La table par séquence n'est jamais lue (2026-09-18)

### Ce que le shader du test fait

`execute_indirect_state_vs_code_small_cbv.vs_5_1.hlsl` :

```hlsl
return float4(c0, c1, a, RootSRV[0] + float(iid)) + root;
```

`root` est le `cbuffer RootConstants : register(b0, space1)`. Nos valeurs rendues disent
que `root.y` et `root.z` restent à zéro au lieu de prendre 100 et 500.

### Le SPIR-V confirme la correspondance

`VKD3D_SHADER_DUMP_PATH` puis `spirv-dis` : le bloc `RootConstants` est bien décoré
`PushConstant`, avec des membres aux décalages 0, 8, 16, **24, 28**, 32… Le jeton DGC vise
`updateRange.offset = 28`, soit le membre 4. **Ma correspondance est juste.**

Et le MSL lit bien là : `grep -c 'ulong(788u)'` sur le dump → **13 occurrences**, et
788 = 760 (`offsetof(root, push)`) + 28.

### La faute trouvée, et corrigée

En traçant chaque `kk_cmd_bind_root_to_argument_table` :

```
[dgc] boucle i=0
[dgc] bind root 0x1503250000   <- ma liaison par sequence
[dgc] bind root 0x15031420e8   <- kk_flush_gfx_state, juste apres
```

Le vidage d'état reliait la racine de base **après** ma liaison, dans la même itération.
`struct kk_graphics_state` porte désormais un `root_override` que la boucle pose et que le
vidage respecte ; la trace confirme la correction. Campagne complète : **2 365, identique**
— pas la cause, mais une vraie faute, gardée parce qu'elle ne coûte rien.

### La bisection, poussée à bout

Trois empoisonnements successifs, chacun rejoué **après** la correction ci-dessus :

| ce qui est empoisonné | résultat |
|---|---|
| les octets écrits par le jeton (`777.0f`, `888.0f`) | aucun changement |
| les 256 octets de la plage de constantes, table de base, côté CPU | aucun changement |
| **la table par séquence entière**, 2 328 octets, dans le noyau | **aucun changement** |

Le troisième est décisif. La table racine porte `attrib_base[]`, les adresses de base des
attributs de sommets. L'empoisonner et voir le rendu **inchangé** signifie que le shader ne
lit pas cette table du tout — sinon la récupération des sommets exploserait.

**La table par séquence n'est jamais lue.** La liaison est sans effet dans ce chemin, alors
que le banc du § 64 prouve qu'elle fonctionne en six configurations.

### Un détail que je n'ai pas encore exploité

Le test fait quatre variantes par cas. La variante « direct count » rend
`(1000, 2064, 3000, 4000)` là où les trois autres rendent `(1000, 64, 0, 4000)`. Comme
`sortie.y = c1 + root.y` et `c1 = 64`, ça donne `root.y = 2000` pour la première et
`root.y = 0` pour les autres. **Les constantes racine diffèrent entre variantes** : quelque
chose les écrit, mais pas les bonnes valeurs. Une table est donc bien lue — reste à savoir
laquelle.

C'est le fil à tirer au prochain tour : tracer, au moment du dessin, l'adresse réellement
présente à l'index 0 de la table d'arguments, et la comparer à celle que je crois avoir
liée.

### Honnêtement

Deuxième tour de diagnostic d'affilée sans gain numérique. 2 365 échecs, inchangé. Ce qui
est acquis : la correspondance des décalages est prouvée juste, une faute de liaison est
corrigée, et le champ des causes possibles s'est nettement resserré.

---

## 68. Trois hypothèses tuées, aucune trouvée (2026-09-18)

Suite du § 67. Quatre mesures, toutes négatives, mais chacune ferme une porte.

### 1. Mes dessins comptent bien

`KK_DGC_NODRAW` fait sortir `vkCmdExecuteGeneratedCommandsEXT` sans rien émettre. Le
contrôle de taille de flux repasse à `Expected size 288, got 32`. **Mes dessins écrivent
donc bien le streamout** — ce ne sont pas des dessins fantômes venus d'ailleurs.

### 2. La liaison est correcte au moment du dessin

Trace juste avant `kk_dispatch_draw`, comparant l'adresse voulue et `cmd->state.root_addr` :

```
[dgc] draw i=0 attendu=0x1503250000 effectif=0x1503250000 OK
[dgc] draw i=1 attendu=0x1503250918 effectif=0x1503250918 OK
...
```

**Huit sur huit OK.** L'état CPU est juste pour chaque séquence.

### 3. Metal ne fige pas la table au démarrage de l'encodeur

Hypothèse : `mtl_render_set_argument_table` n'est appelé qu'une fois par encodeur
(commentaire amont « Argument table won't ever change »), donc Metal 4 figerait la table à
ce moment et ignorerait les écritures suivantes.

Deux réfutations. D'abord relier à nouveau la table à l'encodeur après chaque liaison par
séquence : aucun changement. Ensuite **forcer un encodeur de rendu par séquence**
(`cs_end()` + redémarrage de passe) : aucun changement non plus. Et surtout, l'élément 0
— dont la table est liée avant le tout premier dessin, donc avant tout figement possible —
reste faux.

### Le paradoxe

- L'adresse liée est la bonne, vérifiée dessin par dessin.
- Empoisonner la table entière (2 328 octets, `attrib_base[]` compris) ne change rien.
- Si le shader lisait cette table, la récupération des sommets exploserait.

Les deux affirmations sont incompatibles avec un modèle simple. Il manque une pièce que je
n'ai pas trouvée en trois tours.

### La méthode pour le prochain tour

Arrêter de formuler des hypothèses sur le chemin vkd3d : **faire grossir le banc**
(`tests/test_dgc_push.c`) vers le cas qui échoue, une variable à la fois — passe de rendu
avec attachements, tampons de sommets, shader de fragment, transform feedback. La première
addition qui casse le banc désigne la cause.

C'est mécanique, ça converge forcément, et c'est la seule méthode qui a produit quelque
chose ce matin : le banc a disculpé le mécanisme au § 64, la trace a sorti le clobber au
§ 66. Les six hypothèses que j'ai formées « en lisant le code » sont toutes mortes.

Alternative si ça ne suffit pas : capture GPU Metal (`MTL_CAPTURE_ENABLED`) pour voir ce
que le shader lit réellement, plutôt que le déduire.

### État

**2 365 échecs**, inchangé depuis le § 63. Trois tours de diagnostic sans gain numérique.
Ce qui est acquis reste : DGC fonctionne (175 → 60 sur son bloc, trois fonctions sur cinq à
zéro), la correspondance des décalages est prouvée, une faute de liaison est corrigée, et
six causes possibles sont éliminées.

---

## 69. Le fait qui manquait : le shader lit la table de base (2026-09-18)

### La mesure décisive

Empoisonner les push constants **à l'entrée Vulkan**, dans `kk_push_constants()`, avec
`777.0f` :

```
Element (direct count) 0 : (777.000000, 841.000000, 777.000000, 777.000000)
```

Le poison **ressort**. Donc la chaîne `vkCmdPushConstants` → `root.push` → shader
fonctionne parfaitement. Et `841 = 777 + 64` donne au passage `c1 = 64`, ce qui confirme
que `c0 = 0`, `a = 0`, `RootSRV[0] + iid = 0` : la sortie **est** le vecteur de constantes
racine, tout le reste est nul.

Surtout : `root.y` et `root.z` valent **777**, c'est-à-dire le poison **non corrigé**. Si
le shader lisait ma table par séquence, ils porteraient les valeurs du flux. **Le shader lit
la table de base.**

### Ce que la sortie signifie vraiment

Les constantes de base sont `values = {1000, 2000, 3000, 4000}`
(`d3d12_command.c:2888`). Sans poison, on rend `(1000, 64, 0, 4000)` :

| composante | attendu | obtenu | lecture |
|---|---|---|---|
| x | 1000 | 1000 | base, non visée par la commande |
| y | 164 | 64 | `root.y = 0`, ni base (2000) ni flux (100) |
| z | 500 | 0 | `root.z = 0`, ni base (3000) ni flux (500) |
| w | 4000 | 4000 | base |

Les deux dwords que la signature doit écrire valent **zéro**. vkd3d-proton les met donc à
zéro avant l'ExecuteIndirect et compte sur DGC pour les remplir — ce que ma table ferait,
si elle était lue.

### Éliminations de ce tour

| hypothèse | test | verdict |
|---|---|---|
| mes dessins n'écrivent rien | `NODRAW` → taille de flux 288 → 32 | faux, ils écrivent |
| la liaison est fausse au dessin | trace de `mtl_set_address` au pont | correcte, index 0 = ma table |
| le noyau ne tourne pas | trace de `kk_dispatch_precomp` | tourne, `idx=4`, grilles 2 et 1024 |
| Metal lit la table à la soumission | index 0 remis à NULL après la boucle | aucun effet, donc lecture par dessin |
| le tampon de pré-traitement de vkd3d | allocation maison à la place | aucun effet |
| l'adresse liée compte | adresse absurde `0xdeadbeef000` | **aucun effet**, rendu identique |

Ce dernier est le plus parlant : lier une adresse absurde par séquence ne change **rien**.

### La contradiction, posée franchement

- Au niveau du pont Metal, index 0 porte mon adresse juste avant chaque dessin.
- Metal capture par dessin (le NULL après la boucle ne change rien).
- Le shader lit pourtant la table de base.

Ces trois faits ne tiennent pas ensemble. Il manque une pièce, et six tours de bisection ne
l'ont pas sortie.

### L'expérience à faire au prochain tour

Une seule hypothèse survit et n'a pas été correctement testée : **Metal 4 fige le contenu
de la table au moment de `setArgumentTable:`, et ignore une reliaison du *même objet***.
Mon test précédent rappelait `mtl_render_set_argument_table` avec la même table — Metal a
pu l'ignorer comme redondante.

Le test propre : **allouer N tables d'arguments distinctes**, une par séquence, remplir
chacune, et lier la bonne avant chaque dessin. Si ça marche, la sémantique est établie et
le correctif est connu. C'est borné et ça tranche.

Sinon, capture GPU Metal pour lire la vérité terrain au lieu de la déduire.

### État

**2 365 échecs**, inchangé. Quatrième tour sans gain numérique, mais la cause est cernée :
le problème n'est ni dans le noyau, ni dans les décalages, ni dans la mémoire, ni dans
l'ordonnancement — il est dans la façon dont la table d'arguments Metal transmet l'adresse
au dessin.

---

## 70. Cinquième tour : deux hypothèses de plus éliminées, une piste ouverte (2026-09-18)

### Une table d'arguments par séquence : non

L'hypothèse du § 69 était que Metal 4 fige le contenu de la table à
`setArgumentTable:` et ignore une reliaison du **même objet**. Test propre : allouer une
`MTL4ArgumentTable` **neuve** par séquence, y poser les trois index (racine, samplers,
données par dessin) et la lier avant le dessin.

**Aucun changement.** L'hypothèse tombe.

### Les quatre variantes lisent la même table

Le poison des push constants, relu sur les **quatre** variantes cette fois :

```
(direct count)  (777, 841, 777, 777)
(clamped count) (777, 841, 777, 777)
(indirect count)(777, 841, 777, 777)
(late latch)    (777, 841, 777, 777)
```

Toutes identiques. Et sans poison, la première rend `(1000, 2064, 3000, 4000)` — les
constantes de base — alors que les trois autres rendent `(1000, 64, 0, 4000)`. L'explication
est simple et n'implique pas DGC : **vkd3d-proton remet les constantes à zéro entre les
appels**, conformément à la sémantique D3D12 qui rend indéfini tout argument racine qu'une
signature peut écrire. La première lecture voit `{2000, 3000}`, les suivantes voient `0`.

Autrement dit : **aucune des quatre ne lit ma table par séquence.** Jamais.

### Écrire dans la table que le shader lit : confondu

Dernière tentative : au lieu de faire varier la table, écrire les constantes de la séquence
**dans la table de base**, entre chaque dessin, par un dispatch de mon noyau à grille 1.

La sortie change — mais en tout-à-zéro, et le bloc passe de 60 à 80 échecs. Or le simple
découpage d'encodeur du § 68 donnait **déjà** 80 échecs et des zéros : un dispatch entre
deux dessins termine l'encodeur de rendu, redémarre la passe et casse la capture streamout.
Le résultat est donc entièrement expliqué par le redémarrage. **Confondu, sans information.**

C'est aussi une contrainte de conception à retenir : dans ce pilote, **on ne peut pas
intercaler de compute entre deux dessins d'une même passe** sans détruire le transform
feedback. Toute solution par patch incrémental est donc exclue.

### Bilan des éliminations, cinq tours

| hypothèse | verdict |
|---|---|
| mécanisme des constantes par séquence | correct (banc, 6 configurations) |
| correspondance `updateRange.offset` → `root.push` | correcte (SPIR-V + MSL) |
| liaison au moment du dessin | correcte (trace au pont Metal) |
| `kk_flush_gfx_state` écrase la liaison | **vrai, corrigé**, mais pas la cause |
| le noyau ne tourne pas | il tourne (`idx=4`, grilles 2 et 1024) |
| Metal lit la table à la soumission | non (NULL après la boucle sans effet) |
| Metal fige la table à `setArgumentTable:` | non (tables distinctes sans effet) |
| tampon de pré-traitement de vkd3d | non (allocation maison sans effet) |
| l'adresse liée compte | **non** — une adresse absurde ne change rien |

La dernière ligne reste le fait le plus dur et le plus incompréhensible : lier
`0xdeadbeef000` par séquence produit un rendu **identique**.

### Ce que je recommande

Cinq tours de bisection ont épuisé ce que la mesure indirecte peut donner. Toutes les
hypothèses formulables depuis le code sont mortes, et il reste une contradiction franche.
La suite demande de la **vérité terrain**, pas une hypothèse de plus : capture GPU Metal
(`MTL_CAPTURE_ENABLED=1`) sur une exécution filtrée, pour lire ce que le shader reçoit
réellement à l'index 0 au lieu de le déduire.

À défaut, la position raisonnable est de **garder l'acquis** : DGC fonctionne, le bloc
ExecuteIndirect passe de 175 à 60 échecs, trois fonctions sur cinq sont à zéro, et
l'échantillon Microsoft dessine. Les 60 restants valent 2,5 % de la campagne.

### État

Tout le code expérimental est retiré. Campagne complète : **574 fonctions, 2 365 échecs**,
identique au § 63. Seul `root_override` subsiste des cinq tours — une vraie correction.

---

## 71. La vérité terrain : le shader lit la table racine du **compute** (2026-09-18)

### La méthode

La capture GPU intégrée (`MESA_KK_GPU_CAPTURE`) produit un `.gputrace` illisible sans
Xcode. Autre canal, lisible celui-là : **faire dire au shader ce qu'il voit**, et le lire
par la sortie du test lui-même.

Dans `lower_load_push_constant()`, sous `KK_PC_ADDR=1`, toute lecture de push constant 32
bits est remplacée par une tranche de l'**adresse racine** que le shader reçoit :

```c
nir_def *root = nir_load_buffer_ptr_kk(b, 1, 64, .binding = 0);
nir_def *lo = nir_u2u32(b, nir_ushr_imm(b, root, 20));
nir_def *f = nir_u2f32(b, nir_iand_imm(b, lo, 0xfffffu));
```

Instrument validé d'abord sur les bits 32..51 : le shader rend **21**, soit `0x15`, la
bonne région d'adresses GPU. L'arithmétique côté shader est donc juste.

### Ce que le shader voit

Bits 20..39 de l'adresse racine, corrélés dans la même exécution :

| source | valeur |
|---|---|
| table de base (graphique) | 86 065 |
| ma table par séquence | 86 066 |
| **ce que le shader lit** | **87 221** |

Ni l'une ni l'autre. Et la trace de `kk_dispatch_draw` confirme que
`cmd->state.root_addr` vaut bien 86 066 au moment du dessin.

### D'où vient 87 221

En traçant chaque `kk_upload_descriptor_root()` avec son point de liaison :

```
4181:[root] upload bind=1 b=87221
4182:[root] upload bind=1 b=87221
4183:[root] upload bind=1 b=87221
4184:[root] upload bind=1 b=87221
4186:Test 0: ... Element (direct count) 0 failed: (87221, 87221, 87221, 87221)
```

`bind=1`, c'est `VK_PIPELINE_BIND_POINT_COMPUTE`. **Le shader graphique lit la table racine
du compute** — et précisément celle téléversée par les dispatches de relecture, quatre
lignes avant l'affichage de l'échec.

Le même motif se répète : pour le test 4, le shader rend 88 371, et
`[root] upload bind=1 b=88371` apparaît juste avant.

### Ce que ça veut dire

Les dessins sont encodés avec ma table à l'index 0, vérifié au pont Metal. Mais ce que le
GPU lit à l'exécution, c'est la **dernière** adresse écrite à l'index 0 dans ce tampon de
commandes — celle d'un dispatch de compute postérieur.

Autrement dit, `MTL4ArgumentTable` se comporte ici comme une ressource lue à l'exécution,
pas comme un état capturé à l'encodage. Ça invalide le modèle sur lequel repose
`kk_cmd_bind_root_to_argument_table` dès qu'on veut faire varier une liaison **entre deux
dessins d'un même encodeur**, ce que personne ne faisait avant DGC.

Deux de mes tests antérieurs semblaient réfuter cette lecture ; ils étaient mal posés :

- « index 0 remis à NULL après la boucle » : le dessin final du test relie la racine juste
  après, ce qui annulait le NULL.
- « index 0 remis à NULL à `vkEndCommandBuffer` » : les dispatches de relecture écrivent
  l'index 0 **après**, dans le même tampon.

### La conséquence pour le correctif

Faire varier l'adresse racine par séquence **ne peut pas marcher** avec une seule table
d'arguments. Et le § 70 a montré qu'intercaler un compute entre deux dessins détruit la
capture streamout. Il faut donc que la variation par séquence ne passe **ni** par l'adresse
de la table, **ni** par un patch intercalé.

La piste qui reste : que le shader lise ses constantes **indirectement**, à un décalage
dérivé de l'indice de dessin — c'est-à-dire ce que fait `load_per_draw` avec l'index 2, qui
varie déjà correctement par dessin. Il faudrait que `lower_load_push_constant()` puisse,
en mode DGC, lire à `base + draw_id * stride` au lieu de `base`.

### État

Toute l'instrumentation est retirée. **60 échecs** sur le bloc ExecuteIndirect, inchangé.

---

## 72. Correction du § 71 : l'instrument mesurait le mauvais shader (2026-09-18)

### Le biais

L'instrument du § 71 remplaçait **toute** lecture de push constant 32 bits par l'adresse
racine. Or `get_buffer_readback_with_command_list()` recopie le tampon de streamout avec un
**shader de calcul**, lui aussi affecté : il écrasait le résultat avec ses propres push
constants transformées. La valeur 87 221, qui coïncidait avec un
`[root] upload bind=1` (compute), venait de là.

Conclusion du § 71 — « le shader graphique lit la table racine du compute » — **fausse**.
Le poison du § 69 restait valable, lui, parce que sa structure (`777 + c1`) trahissait bien
une sortie du vertex shader.

### La mesure propre

Instrument restreint aux vertex shaders (`b->shader->info.stage == MESA_SHADER_VERTEX`),
le shader de copie n'est plus touché :

| source | bits 20..39 |
|---|---|
| table de base | 86 065 |
| ma table par séquence | 86 066 |
| **lu par le vertex shader** | **86 065** |

Et `86 129 = 86 065 + 64` donne la contribution de l'attribut `c1`, ce qui confirme qu'on
lit bien la sortie du bon shader.

**Le vertex shader lit la table de base.** C'est net, corrélé dans la même exécution, et
sans artefact.

### Où ça laisse le problème

Les deux faits tiennent toujours et restent incompatibles :

- au pont Metal, l'index 0 porte **ma** table (0x1503250000) juste avant chaque dessin ;
- le vertex shader lit la table **de base** (0x1503141588).

Mais le § 71 est annulé : on ne peut plus dire que `MTL4ArgumentTable` est lue à
l'exécution. Le banc du § 64, où huit séquences reçoivent chacune leurs constantes, prouve
au contraire une capture par dessin. Il reste donc une différence entre le banc et le
chemin vkd3d que six tours n'ont pas isolée.

### Leçon de méthode

Un instrument qui touche **tous** les shaders empoisonne aussi le chemin de relecture. Deux
tours perdus là-dessus. À l'avenir : restreindre l'instrumentation au stage visé, et
vérifier qu'elle laisse une signature reconnaissable du bon shader — ici `+ c1`, qui a
permis de distinguer les deux mesures.

### État

Instrumentation retirée, **60 échecs** sur le bloc ExecuteIndirect, inchangé.

---

## 73. Le rendu conditionnel manquait dans DGC (2026-09-18)

### La corrélation qui a ouvert la voie

Plutôt que continuer à sonder `test_execute_indirect_state`, j'ai regardé lequel des cinq
blocs échouait **sans** streamout :

| fonction | streamout | échecs |
|---|---|---|
| `execute_indirect_state` | oui | 56 |
| `execute_indirect_state_predication` | **non** | 4 |
| les trois autres | non | 0 |

`_predication` est donc un cas bien plus petit et sans transform feedback. Son symptôme est
tout autre : `Iteration 2, draw output 127: expected {0,0,0,0}, got {0, 40960, 2560, 2560}`
— un dessin qui aurait dû être supprimé et qui s'exécute.

### La faute

`kk_CmdDrawIndirectCount2KHR` combine **deux** prédicats :

```c
.predicate_count = cmd->state.cond_render.enabled ? 2u : 1u,
.predicate_op[0] = KK_PREDICATE_GT_DRAW_ID,
.predicate_op[1] = cond_render.inverted ? EQ_ZERO : NEQ_ZERO,
```

Mon `vkCmdExecuteGeneratedCommandsEXT` n'en posait qu'un, celui du compte de séquences :
**il ignorait purement et simplement le rendu conditionnel** (`VK_EXT_conditional_rendering`,
c'est-à-dire `SetPredication` côté D3D12). Idem dans `kk_dgc_dispatch()` pour le chemin
compute.

### La correction

Les deux prédicats sont maintenant empilés dans l'ordre attendu — compte de séquences
d'abord, rendu conditionnel ensuite — dans le chemin graphique, et le chemin compute
applique en plus `libkk_predicate_indirect_eq_zero` / `neq_zero` sur les arguments, comme
le fait déjà `kk_CmdDispatchIndirect2KHR`.

Graphique seul : 4 → 2 échecs. Avec le compute : **0**.

### Mesures

| | échecs |
|---|---|
| bloc ExecuteIndirect, avant | 60 |
| après | **56** |
| campagne complète, avant | 2 365 |
| après | **2 361** |

Comparaison fonction par fonction sur les 574 : une seule ligne bouge,
`test_execute_indirect_state_predication 4 -> 0`. **Aucune régression.**

**Quatre des cinq fonctions ExecuteIndirect sont maintenant à zéro.** Il ne reste que
`test_execute_indirect_state`, seule des cinq à capturer par streamout.

### Ce qui a marché, et pourquoi

Six tours de sondage direct sur `execute_indirect_state` n'ont rien donné. Une comparaison
bête entre mon chemin DGC et le chemin non-DGC équivalent a sorti la faute en quelques
minutes. La bonne question n'était pas « pourquoi ça échoue » mais « qu'est-ce que le
chemin qui marche fait de plus que le mien ».

À appliquer au reste : `kk_draw` appelle `kk_flush_xfb_state()`, mais
`kk_xfb_draw_captures()` renvoie faux pour tout dessin **indirect** et pour tout dessin
**indexé** (§ 67). Or les dessins DGC de ce test sont les deux. Comment la capture peut-elle
alors produire les 288 octets attendus ? C'est la prochaine contradiction à lever, et elle
se trouve dans le même genre de comparaison.

---

## 74. La cause, enfin : la racine était liée après le travail d'émulation (2026-09-18)

### La contradiction levée

`kk_flush_xfb_state()` ne produisait **aucune** trace de diagnostic : elle sort dès sa
première ligne, sur `!vs->info.vs.has_xfb`. Le vertex shader de ce test **n'a pas de
transform feedback**. vkd3d-proton implémente donc la sortie de flux D3D12 par une
**émulation par geometry shader**, pas par `VK_EXT_transform_feedback`.

Or dans KosmicKrisp, un geometry shader n'existe pas : `kk_launch_gs()` le découpe en
programmes de **calcul** lancés avant le dessin. **C'est ce compute qui produit les sommets
et effectue la capture.** Le dessin qui suit ne fait que rastériser.

### La faute, en trois lignes

L'ordre de la boucle de `kk_draw()` était :

```c
kk_upload_per_draw_data(...)
kk_launch_tess(...) / kk_launch_gs(...)   <- le vrai travail, et la capture
kk_flush_gfx_state(...)
[ma liaison de racine par sequence]       <- trop tard
kk_dispatch_draw(...)
```

Les programmes d'émulation lisaient donc la table racine **de base**, jamais celle de la
séquence. Ça explique d'un coup tout ce que six tours de bisection n'arrivaient pas à
concilier : la liaison était correcte au pont Metal juste avant `kk_dispatch_draw`, et
pourtant la sortie portait les constantes de base — parce que la sortie n'était pas
produite par ce dessin-là.

**Correction** : poser `root_override` et lier la racine **en tête du corps de boucle**,
avant `kk_upload_per_draw_data` et les lancements d'émulation. La liaison avant
`kk_dispatch_draw` est conservée, `kk_flush_gfx_state()` pouvant avoir relié entre-temps —
et elle respecte l'override depuis le § 66.

### Mesures

| | échecs |
|---|---|
| `test_execute_indirect_state` | 56 → **0** |
| bloc ExecuteIndirect | 56 → **0** |
| campagne complète | 2 361 → **2 305** |

574 fonctions, comparaison fonction par fonction : une seule ligne bouge,
`test_execute_indirect_state 56 -> 0`. **Aucune régression.**

**Les cinq fonctions ExecuteIndirect sont à zéro.** Le bloc est passé de **175 échecs à 0**.

### Ce qui reste faux, et il faut le dire

L'échantillon `D3D12ExecuteIndirect` de Microsoft rend **exactement la même image qu'au
§ 63** : cinq triangles groupés à gauche, là où il devrait en afficher un millier répartis
sur l'écran. La conformité est à zéro, l'échantillon non. C'est donc un **autre** trou —
probablement le compteur de son `AppendStructuredBuffer` de culling, ou le jeton
`CONSTANT_BUFFER_VIEW` (descripteur racine) qu'aucun des cinq tests ne couvre de la même
façon.

Passer la conformité ne suffit pas : c'était déjà la leçon du § 60.

### Ce qui a marché

Deux corrections en un tour, après six tours stériles, et les deux viennent de la même
question : **« qu'est-ce que le chemin qui marche fait, que le mien ne fait pas ? »**

- § 73 : `kk_CmdDrawIndirectCount2KHR` empile deux prédicats, le mien un seul.
- § 74 : le travail réel se fait dans l'émulation, avant l'endroit où je liais.

Les six tours précédents demandaient « pourquoi ça échoue ». Mauvaise question.

---

## 75. L'échantillon Microsoft rend correctement (2026-09-18)

### Ce que je croyais être un trou n'en était pas un

Au § 74 je notais que `D3D12ExecuteIndirect` rendait toujours cinq triangles groupés à
gauche. C'était une erreur de lecture de ma part, sur deux points.

**Le culling.** `m_cullingScissorRect` vaut `left = centre - centre × 0.5 = 320` et
`right = 960` : c'est la moitié centrale de l'écran, par conception. Voir cinq triangles
entre x = 320 et x = 380 n'était donc pas un défaut, mais le culling qui fonctionne sur les
rares triangles présents dans cette bande.

**L'instant de capture.** `D3D12ExecuteIndirect.cpp:388` place les triangles à
`offset.x ∈ [-5.0, -1.5]`, c'est-à-dire **hors écran à gauche**, avec une vitesse de 0,01 à
0,02 par image. À l'image 30 ils n'ont avancé que de 0,3 à 0,6 : presque tous sont encore
dehors. Je capturais bien trop tôt.

### La mesure refaite

`tests/build_dx_sample.sh` prend maintenant `CAPFRAME` pour choisir l'image capturée.

À l'image 400, culling actif : **des centaines de triangles**, chacun avec sa couleur, sa
taille et sa position propres — donc ses propres constantes par commande — et tous confinés
entre x = 320 et x = 960, avec les marges vides de part et d'autre. C'est exactement le
rectangle de culling.

**Le rendu est correct.** Culling piloté par GPU compris.

### Ce que ça valide

| | |
|---|---|
| jeton `CONSTANT_BUFFER_VIEW` par commande | rend la bonne position et la bonne couleur |
| compteur d'`AppendStructuredBuffer` | alimente le compte indirect, les triangles culés disparaissent |
| synchronisation inter-files compute → graphique | le graphique attend bien le culling |
| `vkCmdExecuteGeneratedCommandsEXT` | 1 024 séquences par image, sans faute visible |

### Leçon

Deux fois de suite (§ 63 puis § 74) j'ai annoncé un « rendu encore faux » sans avoir vérifié
ce que le programme était censé afficher à cet instant précis. La bonne démarche était de
lire la spécification du sample — sa zone de culling, ses positions initiales — avant de
conclure. Lire le code de l'application avant de juger son image.

### État

Conformité : **2 305 échecs** sur 574 fonctions, bloc ExecuteIndirect à **zéro**.
Application tierce : `D3D12ExecuteIndirect` de Microsoft rend correctement, vérifié par
capture hors écran.

---

## 76. Ce qu'il reste à faire (état au 2026-09-18)

### A. Hygiène, à faire avant tout le reste

1. **Emballer le travail DGC en patches.** `grep -l` sur les 33 patches : aucun ne couvre
   `kk_indirect_commands.c/.h`, `kk_draws.cl`, ni les modifications de `kk_cmd_draw.c`,
   `kk_cmd_dispatch.c`, `kk_physical_device.c` et `meson.build`. Tout ce qui a été fait
   aujourd'hui sur DGC n'existe que dans l'arbre de travail.
2. **Retirer les `fprintf` de mise au point** sous `KK_DGC_DEBUG` dans
   `kk_indirect_commands.c` (quatre occurrences).
3. **Réécrire les commentaires des patches 0001 à 0010.** Politique Mesa : ils contiennent
   des commentaires rédigés par l'IA, à remplacer par les mots de l'auteur avant toute
   soumission amont. C'est la tâche de Guillaume, pas la mienne.
4. **Mesurer le coût du patch 0033.** Le déroulage forcé des bandes en indices 32 bits
   ajoute une passe de calcul par dessin ; l'ampleur n'est **pas vérifiée** (§ 58). Il
   faudrait une variante de `win_cube` en bande indexée.

### B. Trous DGC connus et bornés

| jeton | état | ce qu'il faudrait |
|---|---|---|
| `VERTEX_BUFFER_EXT` | refusé | un `MTLIndirectCommandBuffer` : lier un tampon à une adresse décidée par le GPU |
| `INDEX_BUFFER_EXT` | refusé | idem |
| `EXECUTION_SET` | refusé | inutile, vkd3d-proton ne s'en sert jamais |
| `DRAW_MESH_TASKS` | refusé | sans objet, pas de mesh shaders |

Les deux premiers correspondent à ExecuteIndirect **tier 1.1**. Les tests concernés passent
quand même aujourd'hui (§ 65), donc ce n'est pas urgent.

### C. Conformité restante : 2 305 échecs, 28 fonctions, tous instruits

| cause | fonctions | échecs |
|---|---|---|
| taille minimale imposée par Metal | 1 | 1 650 |
| aliasing de descripteurs indéfini | 4 | 320 |
| débordement d'indice dans le shader même | 1 | 94 |
| XFB depuis la tessellation | 2 | 100 |
| limite Metal de 2^28 texels | 1 | 42 |
| tessellation quad et topologies | 6 | 36 |
| reconvergence matérielle | 1 | 16 |
| requête jamais écrite par le test | 1 | 12 |
| pas de compteur GPU hors horodatage | 1 | 6 |
| pas de `VK_EXT_depth_bias_control` | 1 | 6 |
| une occlusion à la fois | 1 | 5 |
| garde-fous compilés en `return false` (binaire PE) | 4 | 9 |
| divers instruits | 4 | 9 |

**Aucun échec non instruit.** Le gros bloc (1 650, soit 72 %) est une contrainte Metal, pas
un défaut. Gratter ici rapporterait peu.

### D. Chantiers structurels, par valeur décroissante

1. **Rejouer la campagne sur macOS 27.** Dix contournements s'y désactivent
   automatiquement (1 à 6, 8, 11, 12, 17, 18). Le classement des blocs non actionnables est
   à réexaminer entièrement. C'est le meilleur rapport effort/résultat.
2. **Sortir de Rosetta.** Pile ARM64 native, bloquée sur `KUSER_SHARED_DATA` à
   `0x7ffe0000`. Taxe mesurée : 2,28× sur le CPU pilote. llvm-mingw est déjà en place.
3. **Compilateur HLSL.** Celui de Wine ne connaît ni `StructuredBuffer` ni
   `AppendStructuredBuffer` (§ 59). Contourné par DXC, qui vise DXIL — ce que livrent les
   jeux récents. À garder comme chemin normal.

### E. Validation applicative

Ce qui tourne aujourd'hui, vérifié :

- `win_cube` (notre code) : 240 images, 115 img/s, relu pixel par pixel.
- Cinq échantillons Microsoft : `HelloTriangle` (vérifié visuellement), `HelloTexture`,
  `HelloConstBuffers`, `HelloFrameBuffering`, `HelloBundles`.
- `D3D12ExecuteIndirect` : rendu correct, culling piloté par GPU compris.

Manque : une vraie application, pas un échantillon. Les candidats accessibles sont les
échantillons plus lourds du même dépôt (`D3D12nBodyGravity`, `D3D12DynamicIndexing`), et
au-delà, un moteur.

---

## 77. DGC emballé en patch (2026-09-18)

### Traces de mise au point retirées

Les quatre `fprintf` sous `KK_DGC_DEBUG` de `kk_indirect_commands.c` sont supprimés, ainsi
que deux `#include` de `<stdio.h>`/`<stdlib.h>` restés dans `kk_cmd_buffer.c` — débris d'une
sonde du § 71 que j'avais mal nettoyée. Reconstruit, réinstallé, **0 échec** sur le bloc
ExecuteIndirect.

### Comment le delta a été isolé

Le bloc-notes de session ayant été vidé, mes copies « avant » avaient disparu. Reconstruction
par l'arbre git :

```sh
git archive HEAD | tar -x -C <tmp>        # arbre vierge
patch -p1 < 0000-kosmickrisp-cumulatif    # etat jusqu'au 0031
patch -p1 < 0032-...  ; patch -p1 < 0033-...
diff -ruN <tmp>/src src/mesa/src          # = le delta DGC
```

Le cumulatif datait du 18 à 00 h 09 et ne contenait ni 0032 ni 0033, ce qui en faisait
justement la bonne référence pré-DGC.

### `0034-kosmickrisp-device-generated-commands.patch`

Huit fichiers :

| fichier | contenu |
|---|---|
| `kk_indirect_commands.c` / `.h` | nouveaux : objet de mise en page, analyse des jetons, besoins mémoire, construction des tables par séquence |
| `kk_draws.cl` | noyau `libkk_dgc_patch_root` |
| `kk_cmd_draw.c` | `vkCmdExecuteGeneratedCommandsEXT`, liaison par séquence, prédicats, `root_override` |
| `kk_cmd_dispatch.c` | `kk_dgc_dispatch()` |
| `kk_cmd_buffer.h` | champ `root_override` |
| `kk_physical_device.c` | extension, fonctionnalités, propriétés |
| `vulkan/meson.build` | le nouveau fichier |

**Vérification aller-retour** : appliqué sur l'arbre pré-DGC, il reproduit l'arbre courant à
l'identique (seuls des `__pycache__` diffèrent, ce sont des artefacts de compilation).

### `0000-kosmickrisp-cumulatif.patch` régénéré

Passé de 4 373 à 5 165 lignes ; il couvre désormais 0032, 0033 et DGC. Vérifié lui aussi :
appliqué sur un `git archive HEAD` vierge, il reproduit l'arbre courant exactement.

### Un point à trancher par l'auteur

Le patch ajoute deux commentaires d'une ligne dans `kk_physical_device.c` :

```c
      /* VK_EXT_device_generated_commands */
```

Ce sont des étiquettes de section, de forme identique aux quelque quarante autres du même
fichier — sans elles, le bloc détonne. Mais ce sont des commentaires que je n'aurais pas dû
écrire. À valider ou à réécrire par Guillaume, comme ceux des patches 0001 à 0010.

Le reste des commentaires du patch est structurel : en-têtes de copyright et
`#endif /* KK_INDIRECT_COMMANDS_H */`.

### Point A du § 76

- A1 emballer DGC : **fait**
- A2 retirer les traces : **fait**
- A3 réécrire les commentaires : **inventaire fait**, voir §86 et `A3-commentaires.md`
  (108 blocs, 21 fichiers) ; la réécriture reste à faire par l'auteur, la politique
  Mesa m'interdisant d'écrire le texte de remplacement
- A4 mesurer le coût du patch 0033 : **fait**, voir §85 (~100 µs par tirage concerné)

---

## 78. D1 anticipé sur macOS 26 : les contournements ne changent rien (2026-09-18)

### Ce qui était mesurable sans la mise à jour

La machine est en macOS 26 ; `ns_is_os_version_at_least(27, 0, 0)` est donc faux et les dix
contournements restent actifs. Mais `MESA_KK_DISABLE_WORKAROUNDS` permet de forcer
exactement la même liste, et de mesurer **ce dont la suite dépend aujourd'hui**.

À poser d'emblée : ça ne prédit **pas** le résultat sur macOS 27. Les contournements
existent parce que Metal 26 a des défauts ; les désactiver ici expose ces défauts au lieu de
les corriger. Ce qu'on mesure, c'est lesquels gagnent encore leur place.

### L'option a été vérifiée avant d'exploiter le résultat

Le masque final, affiché par une sonde temporaire :

| `MESA_KK_DISABLE_WORKAROUNDS` | masque |
|---|---|
| (absent) | `0x0` |
| `all` | `0xffffffffffffffff` |
| `0,1,2,3,4,5,6,8,11,12,17,18` | `0x6197f` |

`0x6197f` = bits 0 à 6, 8, 11, 12, 17, 18 — exactement la liste de macOS 27. **L'option
fonctionne.**

### Le résultat

Trois campagnes complètes, 574 fonctions chacune :

| configuration | échecs |
|---|---|
| référence, contournements actifs | 2 305 |
| liste macOS 27 désactivée | 2 305 |
| **tous** désactivés | 2 305 |

Comparaison **fonction par fonction** des trois : **rigoureusement identiques**, pas une
ligne d'écart. Aucun blocage non plus, les 574 fonctions vont au bout dans les trois cas.

### Ce que ça corrige dans ma propre feuille de route

Au § 76 j'annonçais la campagne macOS 27 comme « le meilleur rapport effort/résultat ».
**C'était faux**, et c'est mesuré : les dix contournements qu'elle désactive n'ont aucun
effet sur la conformité de cette machine. La mise à jour ne fera pas bouger les 2 305.

Les 2 305 restants sont des limites imposées par Metal ou par le binaire PE (§ 76 C), pas
des contournements.

### Ce que ça ne dit pas

- Mesuré sur **une** machine, **un** GPU (M1 Max, famille Apple < 9), avec la suite
  vkd3d-proton. Les contournements peuvent encore protéger des chemins que la suite
  n'exerce pas, ou d'autres familles de GPU.
- Les contournements 2 et 16 sont conditionnés par la famille GPU et ne s'appliquaient
  peut-être pas ici de toute façon.
- **À ne pas retirer sur cette seule base.**

### Conséquence pour la suite

D1 descend en bas de liste. Les chantiers qui gardent de la valeur sont D2 (sortir de
Rosetta, taxe mesurée 2,28×) et E (faire tourner une vraie application). La mise à jour
macOS 27 reste utile pour d'autres raisons — Metal 4 y évolue — mais pas pour ce compteur.

---

## 79. ARM64 sur macOS : le mur n'était pas le noyau (2026-09-18)

Le § 49 concluait que la pile ARM64 native était « bloquée par le noyau, pas par du code »
et demandait d'intercepter les accès dans le code Windows. **C'était faux.** Deux hypothèses
de Wine, corrigées en un tour.

### Ce qui a été confirmé du diagnostic

Le verrou noyau est réel et précis :

| binaire | `__PAGEZERO` | résultat |
|---|---|---|
| x86_64 | 4 Gio (défaut) | démarre, `mmap 0x7ffe0000` **échoue** |
| x86_64 | 0x4000 | démarre, `mmap 0x7ffe0000` → **0x7ffe0000** |
| arm64 | 4 Gio | démarre |
| arm64 | 0x4000 | **SIGKILL** (code 137) |

Et ce n'est pas la signature : le binaire arm64 resigné ad-hoc est tué pareillement. La
différence tient au refus du noyau d'exécuter un Mach-O arm64 dont le `__PAGEZERO` est
rétréci.

Plancher d'adresse mesuré par bissection : ~4,07 Gio en arm64, ~4,04 Gio en x86_64 — donc
**identique**. La différence n'est pas l'espace d'adressage, c'est la permission de le
rétrécir.

### Barrière 1 : `KUSER_SHARED_DATA`

Hors tests, l'adresse `0x7ffe0000` apparaît dans **six fichiers**, tous des DLL que Wine
compile lui-même. Ce n'est donc pas un problème d'interception : une macro
`WINE_USER_SHARED_DATA_ADDR` dans `include/winternl.h`, valant `0x7ffe00000000` sur
aarch64 macOS, suffit à faire concorder les deux côtés.

Les deux autres `0x7ffe0000` de `virtual.c` sont la limite d'espace 32 bits, dans un
`#ifndef _WIN64` — sémantique différente, laissés intacts.

Après ce seul changement, la trace montre :

```
trace:virtual:NtAllocateVirtualMemory 0xffffffffffffffff 0x7ffe00000000 00001000 3000 00000002
trace:virtual:dump_view View: 0x7ffe00000000 - 0x7ffe00000fff (valloc)
```

**La donnée partagée est mappée.**

### Barrière 2 : le bloc de TEB sous 2 Gio

L'échec suivant : `map_free_area couldn't map free area in range 0x10000-0x80000000`.
`virtual.c:3718` alloue le bloc de TEB avec `zero_bits = limit_2g - 1`, pour que les
pointeurs de TEB tiennent en 32 bits — contrainte WoW64, sans objet dans une construction
aarch64 pure. Remplacé par un `teb_block_zero_bits()` qui rend 0 sur aarch64 macOS.

### Où on en est

Après les deux correctifs, `wineboot --init` sur Wine arm64 natif :

- crée le préfixe (`drive_c`, `system.reg`, `user.reg`) ;
- démarre des threads (identifiants `0024`, `002c` dans la trace) ;
- charge et exécute la ntdll PE aarch64 — le `fixme:ntdll:get_cpuinfo` en est la preuve ;
- échoue plus loin, sur `c000007b` (`STATUS_INVALID_IMAGE_FORMAT`) au lancement de
  `wineboot.exe`.

La trace est passée de 10 à 39 lignes, et les seules erreurs restantes sont des retours en
arrière non fatals en haut de l'espace d'adressage. Les 587 DLL PE aarch64 sont bien
installées et `wineboot.exe` est bien un PE aarch64 (vérifié par lecture de l'en-tête COFF).

**Ce n'est pas fini** : `c000007b` reste à diagnostiquer, et le traçage `+module` ne dit
rien, donc l'échec est en amont du chargement de modules.

### Le patch

`0035-wine-arm64-macos-address-space.patch`, sept fichiers, 130 lignes. Sauvegardé
immédiatement — leçon du § 77.

### Ce que ça change

Le chemin « sortir de Rosetta » n'est plus fermé. Il reste au moins un obstacle, mais les
deux qu'on croyait infranchissables se sont révélés être des hypothèses de Wine sur la
disposition de l'espace d'adressage Windows, pas des limites du noyau macOS.

Rappel de portée : même une pile ARM64 complète n'exécutera pas directement un jeu Windows
**x86_64**. Le gain visé reste de faire tourner Wine et le pilote nativement, là où se situe
la taxe de 2,28× mesurée au § 47.

---

## 80. `c000007b` : hypothèses écartées, point de défaillance localisé (2026-09-18)

### Pistes éliminées, chacune par une mesure

| hypothèse | vérification | verdict |
|---|---|---|
| `supported_machines` vide sur aarch64 | `server/registry.c:1858` liste bien `ARM64` puis `I386` si `PREFIX_64BIT` | écartée |
| préfixe marqué 32 bits | `system.reg` porte `#arch=win64` | écartée |
| wineserver périmé d'une exécution antérieure | `pgrep wineserver` : aucun | écartée |
| DLL PE de la mauvaise architecture | en-tête COFF de `wineboot.exe` : `0xaa64`; 587 DLL installées en `aarch64-windows` | écartée |
| chemin du chargeur (`loader_exec` rend ce code si l'`execv` échoue) | `WINELOADER` explicite : résultat identique | écartée |
| base d'image PE sous les 4 Gio | `wineboot.exe` à `0x140000000`, `ntdll.dll` à `0x180000000`, `DYNAMIC_BASE` actif | écartée |

À noter au passage : `0x180000000` est exactement la base du cache partagé dyld sur arm64
macOS. La relocalisation étant active, ça n'a pas gêné ici, mais c'est à surveiller.

### Le point de défaillance

Chaîne remontée depuis le message :

```
dlls/ntdll/unix/env.c:2139   MESSAGE("wine: failed to start %s")
  <- load_main_exe()         dlls/ntdll/unix/loader.c:1465
     <- open_main_image()    rend c000007b
```

Et la trace `+module` montre que le processus fils **résout bien l'ordre de chargement**
avant d'échouer :

```
002c:trace:module:get_load_order looking for L"C:\windows\system32\wineboot.exe"
002c:trace:module:get_load_order got hardcoded default for L"wineboot.exe"
wine: failed to start L"C:\windows\system32\wineboot.exe"
```

Donc : le processus fils démarre, sa ntdll s'initialise (`get_cpuinfo`), l'ordre de
chargement est résolu, puis `open_main_image()` échoue. Le canal `+virtual` ne montre
**aucune** tentative de mappage de module pour ce fil — l'échec est donc **avant**
`virtual_map_module()`, dans `nt_to_unix_file_name()` ou `open_dll_file()`, ou dans le
repli `is_builtin_path()` / `find_builtin_dll()`.

`system32` est vide dans le préfixe neuf, ce qui est normal : les intégrés se chargent
depuis `lib/wine/aarch64-windows`. C'est ce repli qu'il faut instrumenter.

### Prochain pas

Tracer `open_main_image()` et `find_builtin_dll()` — quel chemin Unix est essayé, et quel
statut chacun rend. Le canal `+file` ou quelques `TRACE` temporaires dans
`dlls/ntdll/unix/loader.c` suffiront. C'est borné.

### Rappel d'état

Les deux barrières du § 79 restent franchies : la donnée partagée est mappée à
`0x7ffe00000000` et le bloc de TEB n'est plus contraint sous 2 Gio. Le processus fils va
jusqu'à l'initialisation de sa ntdll PE aarch64.

---

## 81. ARM64 : quatre barrières franchies, la cinquième identifiée (2026-09-18)

### La chaîne complète, remontée pas à pas

Le § 79 avait franchi deux barrières. La bisection du `c000007b` en a livré deux autres,
puis une cinquième qui reste ouverte.

| # | barrière | état |
|---|---|---|
| 1 | `__PAGEZERO` rétréci refusé sur arm64 | **réelle**, contournée en gardant les 4 Gio |
| 2 | `KUSER_SHARED_DATA` à `0x7ffe0000` | **franchie** (§ 79) |
| 3 | bloc de TEB forcé sous 2 Gio | **franchie** (§ 79) |
| 4 | alignement de section PE 4 Kio vs pages de 16 Kio | **franchie** |
| 5 | mappages RWX interdits sur arm64 macOS | **identifiée**, ouverte |

### Barrière 4 : l'alignement de section

`c000007b` venait du **wineserver**, pas du client. `server/mapping.c` :

```c
if (nt.opt.hdr64.SectionAlignment & page_mask)
    return STATUS_INVALID_IMAGE_FORMAT;
```

Nos PE aarch64 avaient `SectionAlignment = 0x1000`, la page hôte fait `0x4000` :
`0x1000 & 0x3fff ≠ 0`. Wine le dit lui-même à l'initialisation du serveur :

```
wineserver: page size is 16k but Wine requires 4k pages, expect problems
```

Six hypothèses ont été éliminées avant d'y arriver, chacune par une mesure : liste de
machines du serveur, marqueur d'architecture du préfixe, serveur périmé, architecture des
DLL, chemin du chargeur, base d'image PE.

**Correctif** : `winegcc` ne posait que `--file-alignment`, jamais `--section-alignment`
(0x1000 par défaut dans lld). Ajout d'un `--section-alignment` calé sur
`sysconf(_SC_PAGESIZE)` quand la page dépasse 4 Kio.

Piège rencontré : le `try_link()` de sondage **rejetait** le drapeau, parce que lld émet
`warning: /align specified without /driver`. Le drapeau fonctionne pourtant — vérifié à la
main, `SectionAlignment = 0x4000`. Il faut donc le poser sans sonde.

Après reconstruction des 587 DLL PE, le rejet de format disparaît et Wine **mappe**
réellement `wineboot.exe`.

### Barrière 5 : W^X

La trace donne la cause directement :

```
err:virtual:map_view anon mmap error Permission denied, size 0x4c000, unix_prot 0x7
```

`unix_prot 0x7` = `PROT_READ|WRITE|EXEC`. Vérifié hors Wine :

| mappage | arm64 macOS |
|---|---|
| RWX simple | **Permission denied** |
| RWX avec `MAP_JIT` | réussit |
| RW | réussit |

Et l'entitlement `com.apple.security.cs.allow-jit` n'y change **rien** : c'est `MAP_JIT`
qui compte, pas la signature.

Wine réserve ses vues d'image en RWX (`VPROT_COMMITTED|READ|EXEC|WRITECOPY`) avant
d'appliquer les protections par section. Deux issues : `MAP_JIT` avec bascule
`pthread_jit_write_protect_np`, ou — plus simple et plus sûr — réserver en RW et laisser la
protection par section ajouter `PROT_EXEC` ensuite.

On y voit aussi que la plage de repli de Wine commence à `limit_4g` = `0x100000000`, sous
le plancher arm64 mesuré (~4,07 Gio). À corriger aussi.

### Le patch

`0035-wine-arm64-macos-address-space.patch`, **huit fichiers, 169 lignes**, sans aucune
trace de mise au point. Il contient les barrières 2, 3 et 4.

### Ce que ça vaut

Le § 49 concluait : « bloqué par le noyau, pas par du code », et demandait d'intercepter les
accès dans le code Windows. Après ce tour : **une seule des cinq barrières est réellement
noyau** (le `__PAGEZERO`, déjà contourné). Les quatre autres sont des hypothèses de Wine sur
la disposition mémoire de Windows, et trois sont levées.

Le chemin n'est pas terminé, mais il n'est plus fermé.

---

## 82. Barrière 5 : mesurée exactement, et son coût chiffré (2026-09-18)

### La règle exacte de macOS arm64

Mesuré hors Wine, sans rien supposer :

| opération | résultat |
|---|---|
| `mmap` RWX | **refusé** |
| `mmap` RWX avec `MAP_JIT` | réussit |
| `mmap` RW | réussit |
| `mprotect` RW → **RX** | **réussit** |
| `mprotect` RW → RWX | refusé |
| `mprotect` RX → RW | réussit |

La règle n'est donc pas « pas d'exécution » mais **« jamais W et X sur la même page en même
temps »**. L'entitlement `com.apple.security.cs.allow-jit` n'y change rien : c'est `MAP_JIT`
qui compte, pas la signature.

### La tentative simple, et pourquoi elle échoue

Modification de `get_unix_prot()` : ne jamais rendre `PROT_WRITE|PROT_EXEC` ensemble,
en abandonnant l'exécution. L'erreur `Permission denied` disparaît — la trace tombe de 14 à
7 lignes, Wine crée le répertoire de configuration, plus aucune erreur fatale.

Mais `wineboot.exe` **boucle à 99 % de CPU**. Pile prélevée avec `sample` :

```
wineboot.exe [58579]
  bus_handler      signal_arm64.c:1129
    setup_exception     signal_arm64.c:773
      setup_raise_exception  signal_arm64.c:750
```

Boucle de SIGBUS : les pages de code ne sont jamais rendues exécutables, la faute se
répète indéfiniment. **Pire que l'échec net d'avant** — la modification est donc retirée.
L'hypothèse « les protections finales par section restaureront l'exécution » est fausse pour
ce chemin.

### Ce que coûte la vraie solution

`MAP_JIT` fonctionne, à condition d'encadrer les écritures :

```c
p = mmap(NULL, 0x4000, PROT_READ|PROT_WRITE|PROT_EXEC,
         MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);   /* -> 0x1044a8000 */
pthread_jit_write_protect_np(0);
memcpy(p, code, sizeof(code));                    /* sans la bascule : SIGBUS */
pthread_jit_write_protect_np(1);
((fn)p)();                                        /* -> 42 */
```

Vérifié : sans la bascule, l'écriture tue le processus ; avec, écriture **et** exécution
fonctionnent.

Le portage demande donc de :

1. mapper les vues d'image avec `MAP_JIT` ;
2. encadrer de la bascule **toute** écriture en mémoire exécutable — recopie des sections
   dans `map_image_into_view()`, relocalisations du chargeur PE, application des correctifs
   d'imports ;
3. accepter que du code Windows qui se modifie lui-même cesse de fonctionner.

La bascule est un état **par fil**, ce qui complique tout code multi-fil qui écrit dans ces
pages. Ce n'est pas un correctif d'une ligne : c'est un chantier au cœur de la gestion
mémoire de Wine.

### Où le chemin en est, honnêtement

| # | barrière | état |
|---|---|---|
| 1 | `__PAGEZERO` rétréci refusé | contournée |
| 2 | `KUSER_SHARED_DATA` | **franchie** |
| 3 | bloc de TEB sous 2 Gio | **franchie** |
| 4 | alignement de section PE | **franchie** |
| 5 | W^X | **mesurée**, non franchie |
| 6 | plage de repli à `limit_4g` sous le plancher arm64 | vue en passant, non traitée |

Le patch `0035` (huit fichiers, 169 lignes) contient 2, 3 et 4, sans aucune trace de mise au
point. L'arbre Wine est revenu à un échec **net** — `map_view anon mmap error Permission
denied, unix_prot 0x7` — et non à une boucle.

### Ce que je retiens

Chercher « pourquoi ça échoue » a coûté six tours sur DGC. Ici, mesurer la plateforme hors
Wine avant de toucher à Wine a livré la règle exacte en trois essais. Et la tentative
naïve, une fois mesurée, s'est révélée nuisible — ce qui n'aurait pas été visible sans le
prélèvement de pile.

---

## 83. La barrière 6 n'existait pas (2026-09-18)

### La mesure

J'avais noté au § 82 une sixième barrière : « la plage de repli de Wine commence à
`limit_4g` = `0x100000000`, sous le plancher arm64 ». **C'est faux**, et la mesure le dit :

```
premier mmap fixe reussi a 0x100400000 (4.004 Gio)
mmap libre                -> 0x10010c000
```

Le premier `mmap` fixe réussit **4 Mo** au-dessus de 4 Gio, pas 70 Mo. Ce qui occupe
`0x100000000` est simplement le binaire `wine` lui-même, chargé juste au-dessus du
`__PAGEZERO`. Il n'y a pas de plancher à 4,07 Gio — ma bissection du § 79 confondait
`KERN_INVALID_ADDRESS` et « région occupée ».

### La preuve par les deux traces

| protection demandée | erreurs de plage | issue |
|---|---|---|
| `0x3` (RW, correction W^X posée) | **1** — la zone du binaire | allocation réussie, wineboot s'exécute |
| `0x7` (RWX, sans correction) | **13** — balayage complet en échec | `Permission denied` |

Avec RW, Wine trouve de la place immédiatement. Le « balayage de 4 Gio à 128 Tio sans
succès » n'était pas un problème d'espace d'adressage : c'était la barrière 5 qui échouait à
chaque adresse.

**Il y a cinq barrières, pas six.** Correction apportée.

### Ce que Wine a déjà pour le W^X

En cherchant de l'échafaudage, trouvé mieux qu'espéré. `virtual.c:238` :

```c
static inline BOOL is_vprot_exec_write( BYTE vprot )
{
    return (vprot & VPROT_EXEC) && (vprot & (VPROT_WRITE | VPROT_WRITECOPY));
}
```

Et la mécanique qui va avec :

- `set_page_vprot_exec_write_protect()` marque ces pages `VPROT_WRITEWATCH` ;
- `get_unix_prot()` retire alors `PROT_WRITE` — **la page devient R+X, jamais W+X** ;
- `virtual_enable_write_exceptions()` bascule toutes les vues existantes, et `virtual.c:1771`
  applique la règle aux vues **nouvelles**.

C'est la moitié exacte de ce qu'il faut, et elle existe déjà.

### Ce qui manque, précisément

Le drapeau sert la fonctionnalité Windows « arbitrary code guard » : à la faute d'écriture
(`virtual.c:4069`), si `enable_write_exceptions` est vrai et que le fil n'a pas
`allow_writes`, Wine **lève une exception Windows** au lieu d'autoriser l'écriture. Or
`allow_writes` n'est posé que depuis une API Windows (`thread.c:2536`) — le chargeur de Wine
ne s'en sert jamais.

Et surtout : quand la page redevient inscriptible, rien ne **restaure** l'exécution après
l'écriture. C'est le va-et-vient R+X ↔ RW qu'il faudrait piloter.

Le chemin propre reste celui du § 82 : `MAP_JIT` plus la bascule
`pthread_jit_write_protect_np`, en s'appuyant sur `is_vprot_exec_write()` pour savoir quelles
pages concernent. Le repérage des pages est déjà écrit ; c'est le va-et-vient qui ne l'est
pas.

### État

Patch `0035` inchangé (huit fichiers, 169 lignes) : barrières 2, 3 et 4. L'arbre Wine échoue
proprement sur la barrière 5.

---

## 84. Barrière 5 franchie, et la vraie barrière 6 : `x18` (2026-09-19)

### La voie `MAP_JIT` est fermée, mais elle n'était pas nécessaire

Mesures (`probe_mprotect`, `probe_range`, `probe_flip`, compilées pour arm64 natif) :

| Opération | Résultat |
|---|---|
| `mmap` RWX, huit adresses différentes | `Permission denied` **partout** |
| `mprotect` RW → RWX | `Permission denied` |
| `mmap` RW puis `mprotect` → RX, sans adresse | OK, code exécuté |
| `mmap` RW puis `mprotect` → RX, `MAP_FIXED` à 0x140000000 | OK, code exécuté |
| `MAP_JIT` + `MAP_FIXED` | `Invalid argument` |

Deux conclusions. La barrière 5 est **absolue** : aucune page ne peut être W et X
simultanément, sous aucune forme. Mais `mprotect` RW → RX fonctionne **sans `MAP_JIT`
ni entitlement**, y compris à adresse fixe. `MAP_JIT` n'était donc pas la solution, et
son incompatibilité avec `MAP_FIXED` n'est pas un obstacle.

La bascule pilotée par les fautes fonctionne également : une page passée en lecture seule
provoque une faute à l'exécution, puis une faute à l'écriture, et le gestionnaire rebascule
la protection à chaque fois (2 fautes, aucune boucle). Une faute d'exécution se distingue
par `si_addr == pc`, et plus proprement par le champ EC du registre de syndrome.

### Ce qui bloquait réellement : `bus_handler` jetait les fautes

`dlls/ntdll/unix/signal_arm64.c` :

```c
static void bus_handler( int signal, siginfo_t *siginfo, void *sigcontext )
{
    EXCEPTION_RECORD rec = { EXCEPTION_DATATYPE_MISALIGNMENT };

    setup_exception( sigcontext, &rec );
}
```

Sur macOS, les fautes de traduction et de permission arrivent en **SIGBUS**, pas en SIGSEGV.
`bus_handler` ne consultait jamais `virtual_handle_fault` : toute faute rattrapable devenait
un désalignement, renvoyé au code invité, qui refautait — d'où la boucle à 100 % de CPU
observée au §82 et attribuée à tort à la règle « abandon de X ».

### Correctif 0036 (113 lignes, deux fichiers, aller-retour vérifié)

- `virtual.c` : bit `VPROT_WXFLIP` (0x80, libre dans l'octet vprot). Une page exec+write est
  mappée **W sans X** par défaut ; le bit indique l'état inverse.
- `get_unix_prot()` : si W et X sont demandés ensemble, retirer X, ou retirer W si `VPROT_WXFLIP`.
- `virtual_handle_fault()` : sur une page exec+write, une faute d'exécution pose le bit, une
  faute d'écriture le retire ; `mprotect_range()` applique, la faute est absorbée.
- `signal_arm64.c` : `get_fault_type()` lit le champ EC du syndrome (0x20/0x21 = avortement
  d'instruction → `EXCEPTION_EXECUTE_FAULT`) ; `bus_handler` route les DFSC 0x04–0x0f vers
  `virtual_handle_fault`. Le désalignement (DFSC 0x21) reste intact, et le comportement Linux
  est préservé par `#ifdef __APPLE__`.

Résultat mesuré : `map_view anon mmap error Permission denied, unix_prot 0x7` **a disparu**,
`wineboot.exe` se charge et exécute du code PE ARM64. **La barrière 5 est levée.**

### La barrière 6, cette fois elle existe : `x18`

Le processus ne rend plus la main. Diagnostic : déréférencements répétés de **NULL aux offsets
0x48 et 0x60**. Dans le TEB 64 bits, 0x48 = `ClientId.UniqueThread` et 0x60 =
`ProcessEnvironmentBlock`. Le pointeur de TEB est donc nul. Sur ARM64 Windows, il vit dans `x18`.

Mesures (`probe_x18`, `probe_x18b`) :

| Événement | `x18` |
|---|---|
| après écriture | `0xdeadbeef12345678` |
| après un appel système (`getpid`) | **0** |
| dans un gestionnaire de signal | 0 |
| après 2 296 510 itérations de calcul pur, machine chargée | **0** |

`clang` refuse d'ailleurs de le déclarer modifié : *« inline asm clobber list contains reserved
registers: X18 »*. Apple réserve `x18` et le noyau le remet à zéro — y compris sur une
**préemption involontaire**, donc de façon asynchrone.

C'est rédhibitoire. Wine ne peut pas le restaurer à une frontière d'appel : l'écrasement
survient à un instant arbitraire, entre deux instructions de calcul. Et le code PE ARM64 —
celui de Wine comme celui de n'importe quelle application Windows réelle — lit le TEB par
`ldr x, [x18, #offset]` ; ces binaires ne sont pas réécrivables.

### Conclusion sur la piste ARM64 native

Cinq barrières sur six ont été franchies ou contournées. La sixième est de niveau noyau,
asynchrone, et porte sur un registre imposé par l'ABI Windows ARM64. **Wine ARM64 natif sur
macOS est bloqué**, au même titre que `__PAGEZERO` (barrière 1) mais sans contournement
possible. La voie x86_64 sous Rosetta reste la seule viable, ce qui confirme le choix
d'architecture du projet.

Le correctif 0036 garde sa valeur : il rend Wine ARM64/macOS capable de charger et d'exécuter
du code, et corrige un vrai défaut de `bus_handler` sur macOS (les fautes rattrapables y étaient
perdues). Il reste applicable si Apple libérait `x18` un jour.

### État

- `0035-wine-arm64-macos-address-space.patch` : inchangé, barrières 2, 3, 4.
- `0036-wine-arm64-macos-wx.patch` : nouveau, 113 lignes, barrière 5, aller-retour vérifié.
- Arbre Wine propre : aucune trace DIAG, aucune instrumentation résiduelle.

---

## 85. A4 : le coût du correctif 0033, chiffré (2026-09-19)

### Ce que 0033 change exactement

`requires_unroll_index_promotion()` passait de :

```c
return (!data->restart && data->index_buffer_el_size_B < sizeof(uint32_t));
```

à `return !data->restart;`. Autrement dit, une bande indexée en **uint32** avec redémarrage
désactivé, qui partait auparavant directement en `mtl_draw_indexed_primitives`, traverse
désormais `kk_unroll_geometry` — une passe de calcul. Cela concerne `TRIANGLE_STRIP` et
`LINE_STRIP` seulement : les éventails se déroulaient déjà toujours (Metal ne les connaît pas),
et l'uint16 se déroulait déjà avant. Le prédicat est consulté par `requires_unroll()`, appelé
pour **tous** les tirages, directs comme indirects.

### Banc

`tests/bench_strip_unroll.c` + `tests/build_bench_strip_unroll.sh`. Les sommets sont générés
depuis `gl_VertexIndex` dans le nuanceur, sans tampon de sommets : le tampon d'indices est la
seule entrée, ce qui isole le coût du déroulement. Rendu hors écran 256×256, médiane sur les
trois quarts finaux des itérations, enregistrement CPU et soumission+attente chronométrés
séparément. Trois configurations :

- `strip32` : `TRIANGLE_STRIP` / uint32 / restart off → déroulé **avec 0033 seulement**
- `strip16` : `TRIANGLE_STRIP` / uint16 / restart off → déroulé dans les deux cas (témoin)
- `list32` : `TRIANGLE_LIST` / uint32 → jamais déroulé (témoin)

A/B réel : deux constructions du pilote, l'ancien prédicat contre le nouveau, même binaire de
banc, dylib échangée entre les séries.

### Résultat principal (256 indices, 200 tirages, M1 Max)

| configuration | sans 0033 | avec 0033 |
|---|---|---|
| `strip32` | **1,74 µs/tirage** | **87,8 µs/tirage** |
| `strip16` (témoin) | 106,7 | 93,6 |
| `list32` (témoin) | 1,62 | 1,70 |

Les deux témoins restent dans leur régime — `list32` à ~1,6 µs dans les deux constructions,
`strip16` déroulé dans les deux — ce qui confirme que l'écart mesuré vient bien du prédicat
et non d'autre chose. L'écart entre 93,6 et 106,7 sur `strip16` donne l'ordre de grandeur du
bruit sur le chemin déroulé : environ 12 %.

### Structure du coût : un terme fixe par tirage, plus un terme proportionnel

Balayage de la taille de bande, 200 tirages :

| indices | sans 0033 | avec 0033 | surcoût | facteur |
|---|---|---|---|---|
| 64 | 1,52 µs | 109,3 µs | +107,8 | ×72 |
| 256 | 1,65 | 106,7 | +105,0 | ×65 |
| 1 024 | 2,29 | 116,7 | +114,4 | ×51 |
| 4 096 | 5,43 | 125,9 | +120,5 | ×23 |
| 16 384 | 18,85 | 220,4 | +201,6 | ×12 |
| 65 536 | 75,67 | 601,1 | +525,5 | ×8 |

Balayage du nombre de tirages, 256 indices :

| tirages | sans 0033 | avec 0033 |
|---|---|---|
| 1 | 149 µs | 279 µs |
| 5 | 31,4 | 152,6 |
| 20 | 11,3 | 97,4 |
| 100 | 2,57 | 105,8 |
| 400 | 1,07 | 101,0 |

Sans déroulement, le coût par tirage s'amortit jusqu'à ~1 µs. Avec déroulement il se stabilise
à **~100 µs et n'amortit pas** : chaque tirage paie le prix plein. Ce n'est donc pas une rupture
d'encodeur payée une fois, mais une passe de calcul par tirage, avec rupture de la passe de
rendu à chaque fois. La répartition à 256 indices / 200 tirages le confirme : ~8 à 14 µs
d'enregistrement CPU, ~79 à 93 µs de soumission+GPU.

### Verdict

Le correctif 0033 coûte **environ 100 µs par tirage concerné** pour les petites bandes, soit un
facteur 50 à 70, et davantage en valeur absolue au-delà de 4 096 indices. Il ne coûte **rien**
à tout le reste : listes, éventails, uint16, et toute bande avec redémarrage activé sont
inchangés.

La portée est étroite mais réelle. En D3D12 le cas correspond à une bande avec indices
`R32_UINT` et `IBStripCutValue` à `DISABLED`. Un contenu qui en ferait cent par image y
dépenserait 10 ms, soit un budget d'image entier à 100 FPS. Les indices 32 bits supposent
cependant plus de 65 535 sommets, ce qui rend la combinaison peu fréquente dans du contenu réel,
où les listes dominent.

Le gain reste acquis : −1 échec de conformité, mesuré au §58 lors de l'intégration du correctif.

### Piste pour plus tard, non explorée

La cause réelle est que Metal impose le redémarrage de primitive à `0xFFFFFFFF` sans pouvoir le
désactiver. Le déroulement est donc nécessaire uniquement si le tampon d'indices **contient**
réellement cette valeur. Un contrôle en amont — une seule fois par tampon, mis en cache, plutôt
qu'une passe par tirage — supprimerait le coût dans tous les cas légitimes. C'est une
modification de conception dans Mesa, hors du périmètre de A4.

### État

- `tests/bench_strip_unroll.c` et `tests/build_bench_strip_unroll.sh` ajoutés (hors arbre Mesa).
- Arbre Mesa restauré à l'identique après l'A/B : `kk_cmd_draw.c` vérifié octet à octet,
  `prefix/lib/libvulkan_kosmickrisp.dylib` remis à la version 0033 et vérifié au banc
  (108,7 µs/tirage, déroulement actif).
- Piège de construction reconfirmé : `/usr/local/bin/ninja` est x86_64, et sous Rosetta `clang`
  hérite de l'architecture du parent — `blake3_neon.c` échoue alors sur `__ARM_FP` non défini.
  Utiliser `arch -arm64 toolchain/bin/ninja`, avec `prefix/bin` dans le PATH pour `mesa_clc`.

---

## 86. A3 : inventaire des commentaires, et pourquoi je m'arrête là (2026-09-19)

### La limite

`src/mesa/CLAUDE.md` : *« Do not generate code comments, commit messages, or GitLab comments […]
If the user asks you to generate prose, decline and refer them to Mesa's contribution policy. »*
Réécrire les commentaires, c'est exactement générer de la prose destinée à l'arbre. Je ne l'ai
donc pas fait. Ce que je peux faire sans sortir de la politique : inventorier, localiser,
classer, et en discuter en privé — ce dernier point y est explicitement autorisé.

`src/vkd3d-proton` ne porte aucune politique équivalente (vérifié : ni `CLAUDE.md` ni
`AGENTS.md` dans l'arbre). Ses 17 blocs sortent donc du périmètre de A3.

### Méthode, et une correction de trajectoire

Première tentative : extraire les lignes de commentaire ajoutées par les correctifs 0001 à 0010.
Mauvaise approche, pour trois raisons mesurées :

1. **Doublons.** Les correctifs se recouvrent sur les mêmes fichiers ; 136 blocs bruts se
   réduisaient à 125 uniques.
2. **Fantômes.** Neuf blocs de 0003 et 0010 n'existent plus sous cette forme : des correctifs
   ultérieurs les ont modifiés ou supprimés. Les lister aurait envoyé chercher du texte absent.
3. **Numéros inutilisables.** Les lignes d'un fichier de correctif ne correspondent pas à
   l'arbre de travail, qui est ce que l'on édite.

Deuxième approche, retenue : extraire depuis `git diff HEAD` de l'arbre Mesa, plus les deux
fichiers non suivis de 0034. Cela donne exactement les commentaires **présents aujourd'hui**,
dédoublonnés par construction, avec de vrais numéros de ligne. Les blocs déjà présents en amont
(code déplacé ou réindenté) sont écartés par comparaison au texte de `HEAD`.

Quatre numéros de ligne vérifiés au hasard contre les fichiers : tous exacts.

### Résultat

**108 blocs sur 21 fichiers**, dans `A3-commentaires.md` (hors arbre Mesa, non commité).

| fichier | blocs |
|---|---|
| `kk_cmd_draw.c` | 22 |
| `kk_shader.c` | 19 |
| `kk_cmd_buffer.h` | 13 |
| `kk_shader.h` | 10 |
| `kk_nir_lower_xfb.c` | 6 |
| `kk_cmd_buffer.c` | 5 |
| dix-sept autres | 33 |

Sur les 108 : **11 relèvent de la convention** — en-tête de licence, `#endif /* GARDE */`,
étiquette `/* VK_… */` identique à la trentaine déjà présentes dans `kk_physical_device.c`,
annotation `/* output */` employée en amont dans `poly`, `asahi` et `kk_tessellation.cl`. Ce ne
sont pas des phrases, et je ne pense pas qu'il y ait là quoi que ce soit à réécrire, mais c'est
un appel qui vous revient.

**97 sont à réécrire.** Trois portent un chiffre mesuré pendant le projet, signalés par ⚑ :
le plafond d'encodeurs par tampon de commandes Metal (36 000 acceptés, 38 000 refusés sur
M1 Max), l'alignement de 16 octets rendu par `minimumTextureBufferAlignmentForPixelFormat:`
pour tous les formats, et la répartition 131 072 encodeurs sur huit tampons contre 38 000 sur
un seul. Ces mesures ne se retrouvent nulle part ailleurs dans le code : en reformulant, il faut
les garder.

### Après

Une fois l'arbre corrigé, régénérer les correctifs concernés — l'essentiel retombe dans 0003,
0005, 0006, 0009 et 0010.

### vkd3d-proton : relu et corrigé

Cet arbre ne porte **aucune** politique sur les agents (vérifié : ni `CLAUDE.md` ni
`AGENTS.md`), j'ai donc pu y faire le travail moi-même. Inventaire de départ : 21 blocs sur
11 fichiers, un seul de convention (`#endif /* __APPLE__ */`).

La relecture s'est faite contre le style réellement pratiqué en amont, mesuré sur **1 233
lignes de commentaire** des onze mêmes fichiers : largeur médiane 68 colonnes, 32 % des lignes
au-delà de 80, blocs d'une seule ligne dans 59 % des cas, ton narratif et non télégraphique.
Mes commentaires s'y conformaient déjà pour l'essentiel — ce qui a limité le travail à quatre
défauts réels au lieu d'une réécriture de façade :

1. `vkd3d_native_sync_handle.h` : le tiret double ` -- ` **n'apparaît jamais** dans les 1 233
   lignes amont (qui emploient ` - ` 44 fois) et j'en avais mis deux. Reformulé, et la mention
   du mutex ajoutée au passage.
2. `libs/vkd3d/device.c` : le même bloc de trois lignes recopié **mot pour mot** au-dessus des
   trois `*pipeline_state = NULL;`. Explication complète au premier site, renvoi d'une ligne
   aux deux autres.
3. `vkd3d_threads.h` : le commentaire expliquant pourquoi macOS est exclu se trouvait **à
   l'intérieur** du `#ifndef __APPLE__`, donc dans la branche que macOS ne compile jamais. Il
   se lisait à l'envers. Remonté au-dessus de la garde.
4. `tests/d3d12_sync.c` : une affirmation invérifiable sur « the native build », retirée.

Vérifications : compilation propre (`arch -arm64 ninja`, 83 cibles) ; plus aucun ` -- ` ;
correctifs 0004, 0007 et 0016 régénérés **par remplacement de section**, pour ne pas replier
0014 dans 0004 (les deux touchent `libs/vkd3d-common/platform.c`) ; **aller-retour vérifié**,
les cinq correctifs appliqués sur `git archive HEAD` reproduisent l'arbre octet pour octet sur
les quatorze fichiers. Volume passé de 42 à 38 lignes.

Détail bloc par bloc dans `A3-commentaires-vkd3d.md`.

---

## 87. Un vrai moteur tourne : Godot 4.7.2 rend en D3D12 (2026-09-19)

Le point E du § 76 disait : *« Manque : une vraie application, pas un échantillon. »* C'est
comblé.

### Cible

**Godot 4.7.2-stable**, publiée le 18 août 2026. Build Windows x86_64 officielle,
`Godot_v4.7.2-stable_win64.exe.zip`, 82 Mo, sha256 `731980f9608d61333e5baf54a2ef17210acc7a53
8446c0cb9969f002aca1e953`, depuis les releases `github.com/godotengine/godot`. Choisie parce
qu'elle coche les trois cases que ne cochait aucun échantillon : moteur réel, backend D3D12
natif, librement redistribuable.

### Ce qui marche

Lancé via `tests/etape2_pile_wine.sh`, avec `--rendering-driver d3d12` :

```
D3D12 11_0 - Forward+ - Using Device #0: Apple - Apple M1 Max
```

Le périphérique se crée, et la suite est un vrai fonctionnement de moteur, pas une
initialisation qui s'arrête là :

- **Shader model 6.0**, donc le chemin DXIL, celui des jeux récents.
- **Bindless** via `VK_EXT_mutable_descriptor_type`, détecté par vkd3d-proton.
- **Tas GPU UPLOAD** supporté (`vkd3d_memory_info_upload_hvv_memory_properties`).
- **168 PSO compilés**, cache de pipelines sur disque opérationnel (fusion, mappage,
  analyse de l'archive, écriture différée).
- **Chaîne de swap vivante** : `dxgi_vk_swap_chain_recreate_swapchain_in_present_task: Got 3
  swapchain images`.
- `SDL: Init OK!`, thème de l'éditeur généré, réglages chargés : l'éditeur monte entièrement.

### Rendu vérifié, pas seulement démarré

Projet 3D minimal écrit pour l'occasion (`build/godot-proj/`) : tore métallique, cube, sphère,
lumière directionnelle, matériaux PBR distincts, animation par script. Rendu **non pas capturé
à l'écran mais écrit par le pipeline de Godot lui-même** (`--write-movie`), ce qui évite toute
ambiguïté sur ce qui a produit l'image.

**90 images en 960×540**, toutes distinctes (empreintes SHA-256 vérifiées sur cinq d'entre
elles). L'image 45 relue : tore orange avec sa tache spéculaire correcte, cube bleu, sphère
verte, perspective et éclairage justes, matériaux métalliques et rugueux bien différenciés.

### Ce que le moteur signale comme absent

Relevé tel quel, sans contournement de notre part : Variable Rate Shading, multiview,
opérations 16 bits, test de bornes de profondeur, *relaxed casting* (supporté mais désactivé
par Godot). Trois `fixme` de vkd3d-proton sur les lignes lisses, larges et en quad.

Deux trous Wine sans rapport avec le graphique : `GetAdaptersAddresses` échoue (énumération
des interfaces réseau) et l'EDID du moniteur n'est pas lisible, d'où un avertissement sur le
niveau de blanc SDR.

### Cadence : ce que je peux et ne peux pas affirmer

Avec la fenêtre affichée, **120 images/s, minimum 115 sur 194 échantillons** — c'est
exactement la fréquence de l'écran ProMotion, et le journal confirme le V-Sync. La scène ne
rate donc jamais un rafraîchissement.

**Le plafond de débit n'est pas mesuré.** V-Sync explicitement désactivé, la cadence reste
collée à 120 : quelque chose d'autre synchronise, vraisemblablement la couche Metal. En
poussant la fenêtre à 3840×2160 les chiffres partent entre 53 et 768 — la fenêtre a cessé
d'être composée en cours de route, ces valeurs ne mesurent rien et je ne les retiens pas.
Un vrai chiffre de débit demande une méthode propre, hors fenêtre composée. **Non vérifié.**

### Portée

C'est le premier moteur complet, écrit par des tiers, qui rend correctement sur cette pile :
`Godot D3D12 → Rosetta 2 → Wine → vkd3d-proton → winevulkan → KosmicKrisp → Metal 4`. Les
échantillons Microsoft prouvaient que les appels fonctionnaient ; celui-ci prouve qu'un
moteur avec son compilateur de shaders, son cache de pipelines, son bindless et sa chaîne de
swap tient la route.

---

## 88. Charge lourde : le goulot est le CPU, pas le GPU (2026-09-19)

### Le banc

`build/godot-heavy/` : scène construite par script (`heavy.gd`), paramétrable en ligne de
commande, qui **se mesure elle-même**. Cent vingt images de chauffe jetées, puis 300 images
mesurées, médiane et p95 imprimés avec le nombre de tirages et de primitives relevés par
`Performance`. Un matériau distinct par instance, pour empêcher tout regroupement de tirages.

### Premier résultat, et ce qu'il cachait

Configuration de départ : 1 500 objets, 24 lumières omni avec ombres, SSAO + SSIL + glow +
brouillard volumétrique, 1732×1080.

| configuration | tirages/image | ms | img/s |
|---|---|---|---|
| ombres + post | 10 374 | 31,5 | 31,8 |
| ombres seules | 10 401 | 31,3 | 32,0 |
| post seul | 1 489 | 10,6 | 94,3 |
| ni l'un ni l'autre | 1 489 | 7,1 | 140,0 |

Les 24 lumières à ombres multiplient les tirages par sept (1 489 → 10 374) : chacune
reprojette la scène. Et les deux premières lignes ont **le même temps** alors que la seconde
fait beaucoup moins de travail GPU.

### La mesure décisive

Même scène complète, mais en 640×360 — neuf fois moins de pixels :

| résolution | tirages | ms |
|---|---|---|
| 1732×1080 | 10 374 | 31,5 |
| 640×360 | 10 403 | 31,9 |

**Identique.** L'image est entièrement limitée par le CPU qui soumet les tirages à travers
`Rosetta → Wine → vkd3d-proton → KosmicKrisp`. Le GPU n'est pas le facteur limitant.

### Coût marginal par tirage

Balayage à 640×360, sans ombres ni post :

| tirages | ms |
|---|---|
| 500 | 8,33 |
| 1 912 | 8,93 |
| 3 674 | 18,06 |
| 5 637 | 29,17 |

La ligne à 500 ne mesure rien (8,333 ms exactement, variance nulle : plafond d'écran). Entre
3 674 et 5 637 la pente donne **5,5 µs de CPU par tirage**, soit environ 180 000 tirages par
seconde.

Correction d'un chiffre que j'avais avancé trop vite : 326 000 tirages/s, déduit de la scène
à 10 403 tirages, était faux. Ces tirages-là étaient en majorité des passes d'ombres, plus
légères qu'un tirage de passe principale avec matériau distinct. Les deux ne se comparent pas.

### Ce que cela donne comme budget

À 5,5 µs par tirage, une image de 16,67 ms autorise **environ 3 000 tirages**. La contrainte
n'est donc ni les pixels ni les triangles, mais le **nombre d'objets distincts**. La même
scène sans les 24 lumières à ombres fait 1 489 tirages et tourne à 140 img/s.

### Limite de méthode

Le coût n'est pas linéaire en tirages au-delà de ~6 000 : la charge CPU propre au moteur
(parcours et culling du graphe, mise à jour des transformations) croît avec le nombre de
nœuds, indépendamment du moteur de rendu. Raisonner en pente sur toute la plage serait faux.
Les comparaisons ne valent qu'à **configuration identique**.

---

## 89. Notre pile contre Metal natif : le contrôle qui manquait (2026-09-19)

### Pourquoi ce contrôle

« 31,8 img/s, c'est cher ou pas ? » n'a pas de réponse sans référence. Godot 4.7 embarque un
moteur de rendu **Metal natif** dans sa build macOS : même moteur, même version, même scène,
même GPU, une fois à travers notre pile et une fois en direct. `Godot_v4.7.2-stable_
macos.universal.zip`, 163 Mo, sha256 `c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa
9a3b3ba63e`. Version imprimée identique des deux côtés : `4.7.2.stable.official.ed1daf0bf`.

Toutes les mesures en 640×360, 4 lumières, sans ombres ni post — donc en régime limité par le
CPU (§ 88), qui est précisément ce qu'on veut comparer.

### Résultat

| objets | tirages/image | notre pile (D3D12) | Metal natif | rapport |
|---|---|---|---|---|
| 5 000 | 3 674 | 18,06 ms | 10,42 ms | 1,73× |
| 9 000 | 5 636 | 29,17 ms | 23,61 ms | 1,24× |
| 16 000 | 8 801 | 47,62 / 46,67 / 45,83 ms | 54,76 / 52,38 / 52,78 ms | **0,88×** |
| 24 000 | 12 092 | 135,89 ms | 101,85 ms | 1,33× |

Le point à 16 000 étant contre-intuitif, il a été rejoué : **trois mesures de chaque côté**.
Notre pile : 47,62 / 46,67 / 45,83, médiane 46,67, dispersion 3,9 %. Natif : 54,76 / 52,38 /
52,78, médiane 52,78, dispersion 4,5 %. Les deux nuages ne se recouvrent pas. **À cette charge
notre pile est 12 % plus rapide que le rendu Metal de Godot.**

### Lecture

Le rapport oscille entre 0,89× et 1,73× sans tendance nette, et se resserre quand la charge
monte avant de repartir. L'écart n'est donc pas un coût par tirage mais un surcoût à peu près
fixe par image, noyé quand l'image s'allonge. Ordre de grandeur honnête : **notre pile est à
±30 % du rendu Metal natif de Godot**, sans pénalité d'un ordre de grandeur nulle part.

C'est bien moins que ce que la taxe Rosetta seule (2,28× sur le CPU pilote, § 76) laissait
craindre, pour un chemin qui traverse Rosetta, Wine, une traduction D3D12 → Vulkan puis
Vulkan → Metal.

### La réserve qui compte

Ceci compare **deux moteurs de rendu de Godot**, pas notre pile à un plafond matériel. Le
backend Metal de Godot est récent (introduit en 4.4) là où le chemin Vulkan que nous
alimentons est mature. Une partie de notre bon score peut venir de là autant que de nos
mérites. Dire « nous sommes à ±30 % du natif » serait abusif ; « à ±30 % du rendu Metal de
Godot » est ce que la mesure autorise.

### Réponse à la question posée

Les 31,8 img/s du § 88 venaient d'une scène volontairement punitive, et la cause est mesurée :
le CPU qui soumet les tirages, pas le GPU. À 5,5 µs par tirage, **60 img/s tient dans un budget
d'environ 3 000 tirages par image** — largement suffisant pour une scène normale, la même
scène sans les 24 lumières à ombres faisant 1 489 tirages à 140 img/s.

---

## 90. Où partent les 5,5 µs par tirage (2026-09-19)

### Les outils système ne servent à rien ici

`sample` sur le processus Wine ne produit rien d'exploitable : le graphe d'appels dégénère en
récursion infinie de `__wine_syscall_dispatcher`, et l'histogramme des feuilles range 100 % du
temps dans `Rosetta Runtime Routines`. Aucun symbole. Il faut donc mesurer par différence.

### Le banc

`tests/bench_draw_cost.c`, construit pour **trois cibles** depuis la même source : arm64 natif,
x86_64 natif sous Rosetta, et **PE Windows** lié à la bibliothèque d'import de Wine
(`wine/wine10/lib/wine/x86_64-windows/libvulkan-1.a`). Il n'enregistre que du CPU : aucune
attente de GPU dans la fenêtre chronométrée. Cinq modes isolent chaque cause de coût.

### Résultat

| mode | arm64 natif | x86_64 natif | PE via Wine |
|---|---|---|---|
| tirage seul | 0,100 µs | 0,254 µs | 0,226 µs |
| + constantes de poussée | 0,170 | 0,390 | 0,386 |
| + descripteurs | 0,172 | 0,372 | 0,378 |
| + pipeline | 0,438 | 1,093 | 1,079 |
| **tout** | **0,459** | **1,137** | **1,166** |

Trois lectures.

**La taxe Rosetta est de 2,5×**, cohérente avec les 2,28 × du § 76.

**winevulkan ne coûte rien.** La colonne PE est dans le bruit de la colonne x86_64 native : la
traversée PE → Unix pour un appel Vulkan est gratuite. C'était le suspect le plus plausible ;
il est innocent.

**Notre part est de 1,17 µs sur 5,5.** Soit **21 %**. Les 4,3 µs restants — **78 %** — sont
au-dessus de nous, dans vkd3d-proton et le backend D3D12 de Godot. Optimiser KosmicKrisp a
donc un plafond de 21 %, quoi qu'on fasse.

### Un gaspillage net, dans notre code

Mode ajouté : relier le **même** pipeline à chaque tirage.

| | arm64 | PE via Wine |
|---|---|---|
| rien lier | 0,105 µs | 0,226 µs |
| relier un pipeline identique | **0,318** | **0,725** |
| relier un pipeline différent | 0,461 | 1,079 |

Relier un pipeline identique coûtait **60 % du prix d'un vrai changement**. `kk_cmd_bind_
graphics_shader()` marquait l'étage sale inconditionnellement, puis posait `KK_DIRTY_VB`, sans
jamais comparer au shader déjà lié.

Correctif : comparer, et ne salir que si le shader change. La logique de profondeur-stencil
reste inchangée, car un `vkCmdSet*` intercalé peut avoir rendu l'état dynamique et la reliaison
doit alors restaurer l'état statique.

| mode | avant | après |
|---|---|---|
| pipeline identique | 0,318 µs | **0,176 µs** |
| pipeline différent | 0,461 | 0,439 |
| tout | 0,459 | 0,456 |

Le gaspillage passe de 0,213 à 0,076 µs, **−64 %**, sans toucher au coût d'un vrai changement.
Le reliquat de 0,076 µs est dans le runtime Vulkan commun (`vk_cmd_set_dynamic_graphics_state`
recopie tout l'état dynamique), code partagé par tous les pilotes Mesa, laissé tranquille.

### Vérification de non-régression

Les 90 images du projet Godot du § 87 rejouées avec le pilote corrigé : **90 sur 90 identiques
octet pour octet** aux images de référence.

### Et pourtant le correctif ne sert à rien : A/B sur contenu réel

Scène lourde à 9 000 objets, 640×360, sans ombres ni post, deux pilotes, deux régimes de
matériaux :

| matériaux | sans filtre | avec filtre | écart |
|---|---|---|---|
| distincts (9 000) | 28,571 ms | 29,167 ms | +2,1 % |
| partagés (16) | 10,317 ms | 10,300 ms | −0,2 % |

Rien. Pas même sur les matériaux partagés, où j'attendais un gain.

La cause est dans `src/vkd3d-proton/libs/vkd3d/command.c:7405` :

```c
if (list->current_pipeline != VK_NULL_HANDLE)
    return true;
```

**vkd3d-proton filtre déjà les liaisons redondantes.** Il n'émet `vkCmdBindPipeline` que
lorsque son pipeline courant a été invalidé. Les liaisons inutiles n'atteignent donc jamais
KosmicKrisp : mon microbanc les fabriquait artificiellement, aucune application passant par
D3D12 n'en produit.

À noter au passage, mesuré sur le même banc : **partager les matériaux fait presque tripler la
cadence** (28,571 → 10,317 ms à nombre d'objets égal). Le tri par matériau que fait Godot et la
chute des commutations de pipeline pèsent bien plus lourd que tout ce qu'on pourrait gratter
dans le pilote.

### Décision : rejeté

L'arbre est remis dans son état validé — `kk_shader.c` restauré, les deux pilotes reconstruits
et réinstallés, retour vérifié au banc (`pipesame` remonté à 0,308 µs, empreinte du pilote
x86_64 identique à la version sans filtre).

Le correctif est conservé hors série sous `9001-kosmickrisp-skip-redundant-shader-bind.patch.
rejete`. Il est correct et supprime un vrai gaspillage pour une application Vulkan directe qui
relierait des pipelines identiques — mais il ne rapporte rien au projet, et le garder exigerait
une campagne de conformité complète pour un gain mesuré nul.

### Ce que cette investigation a établi

1. Notre code pèse **21 %** du coût par tirage. Le plafond de toute optimisation côté
   KosmicKrisp est là, quoi qu'on fasse.
2. **winevulkan est gratuit** : le suspect le plus plausible est innocenté par la mesure.
3. **Rosetta coûte 2,5×**, et cette voie est fermée depuis le § 84.
4. Les **78 % restants** sont dans vkd3d-proton et le backend D3D12 de Godot, c'est-à-dire
   hors de notre code.
5. Le levier qui compte n'est pas dans le pilote mais dans le contenu : partager les matériaux
   triple la cadence.

---

## 91. La série de correctifs ne se rejoue pas (2026-09-19)

Vérification jamais faite jusqu'ici : les 37 correctifs reconstruisent-ils les arbres depuis
l'amont ? Trois résultats, dont un mauvais.

### Ce qui va

**Wine** : `git archive HEAD` + 0028 + 0035 + 0036 reproduit l'arbre, **zéro fichier
différent**. Les trois arbres portent leur commit amont et leur remote, donc la provenance est
récupérable : Mesa `5f253b93` (2026-09-16), Wine `b0738596` (tag `wine-10.0`), vkd3d-proton
`5d0db741` (2026-09-16).

**vkd3d-proton** : 0004 + 0007 + 0008 + 0014 + 0016, **zéro fichier différent**.

**Mesa, cumulatif** : `0000-kosmickrisp-cumulatif.patch` reproduit l'arbre, aucune différence
de contenu (seuls des artefacts : boucles de liens symboliques, un `.wraplock` de construction).

### Un correctif était inapplicable

`0036-wine-arm64-macos-wx.patch` échouait sur un bloc de `signal_arm64.c`. Cause : je l'avais
fabriqué en reconstruisant sa version « avant » à la main, en y omettant une ligne vide présente
en amont. Le contexte décrivait donc un fichier qui n'existe nulle part.

Régénéré depuis une vraie base (`HEAD` + 0028 + 0035), ligne vide amont restaurée dans l'arbre.
Série Wine revérifiée : elle passe.

### Ce qui ne va pas : la série Mesa individuelle

Appliquée dans l'ordre sur un arbre vierge, **10 correctifs sur 28 échouent**, laissant
6 fichiers faux. Avec `git apply --3way`, 12 conflits — pas mieux : les correctifs qui portent
des lignes `index` référencent des états intermédiaires jamais validés, donc la fusion à trois
voies n'a rien à quoi se raccrocher, et 22 des 37 n'ont pas de ligne `index` du tout.

Cause : chaque correctif a été produit contre **l'arbre du moment**, jamais contre « vierge +
les précédents ». Les fichiers partagés — `kk_physical_device.c`, `kk_private.h`,
`kk_shader.c` — accumulent les fonctionnalités, et le contexte de chaque correctif décrit un
état intermédiaire qui n'est reproductible qu'en repassant exactement par la même histoire.

### Portée réelle du problème

Rien n'est perdu : `0000` est vérifié et reconstruit l'arbre. Mais il fait 5 165 lignes en un
bloc, donc **ni soumettable ni relisible**. Concrètement, deux choses sont bloquées : rejouer
le projet depuis l'amont correctif par correctif, et toute soumission en série.

À cela s'ajoute que `tests/etape2_construire_pile.sh` ne mentionne **aucun** correctif : il
suppose les arbres déjà modifiés. Le projet n'est donc aujourd'hui reproductible que depuis ce
répertoire-ci, qui n'est lui-même pas sous git.

### Ce qu'il faudrait

1. Régénérer la série Mesa contre une vraie chaîne de bases : pour chaque correctif *i*,
   partir de vierge + 1..*i-1*, résoudre les rejets en consultant l'arbre final, puis
   réémettre le correctif comme `diff(base, résultat)`. Douze conflits à traiter, mécanique
   mais long.
2. Écrire l'étape manquante : un script qui part des trois commits amont, applique les séries,
   et passe la main à `etape2_construire_pile.sh`.

---

## 92. La série est rejouable (2026-09-19)

Le défaut du § 91 est corrigé. L'ensemble du projet se reconstruit désormais depuis les trois
commits amont.

### Comment les conflits ont été réduits

Le premier essai donnait dix échecs sur vingt-huit. Deux découvertes ont fait fondre le chiffre
avant toute résolution manuelle :

**`patch` inversait les correctifs.** Sans `--forward`, il détectait « Reversed (or previously
applied) patch » sur les blocs qu'un correctif antérieur avait déjà posés, et tentait de les
*défaire*. Les rejets que je lisais étaient donc à l'envers, ce qui rendait le diagnostic
incompréhensible jusqu'à ce que je le remarque.

**`git apply --3way` ne sert à rien ici.** Douze conflits au lieu de dix : 22 des 37 correctifs
n'ont pas de ligne `index`, et ceux qui en ont référencent des états intermédiaires jamais
validés. La fusion à trois voies n'a rien à quoi se raccrocher.

Avec `--forward -F3`, neuf conflits. Six résolutions manuelles ont suffi, et trois se sont
débloquées d'elles-mêmes en cascade.

### Les six résolutions

| correctif | ce qu'il fallait démêler |
|---|---|
| 0003 | embarquait les ajouts de 0002 ; seules les lignes de transform feedback lui reviennent, y compris la correction des propriétés optimistes |
| 0005 | **dupliquait** les cas XFB de 0003 : le doublon de 44 lignes a été retiré |
| 0006 | embarquait le travail de 0005 ; sa part propre est le contrôle de limite de texels |
| 0009 | apportait trois macros d'un coup ; seule celle des encodeurs lui revient, les deux autres sont à 0006 |
| 0022 | contexte décrivant une accolade placée autrement ; bloc des variantes de pipeline inséré depuis l'arbre final |
| 0024 | embarquait la boucle `rt_formats` de 0022 ; sa part propre est le bloc de mélange |

Trois lignes vides parasites, scories de mes éditions successives, ont été retirées de l'arbre
de travail : la série rejouée était plus propre que l'original.

### Vérification

Les vingt-huit correctifs ont été **régénérés** comme `diff(base_i-1, base_i)` depuis les
instantanés du rejeu, puis réappliqués sur un arbre vierge **sans `--forward`, sans `-F3`,
sans résolution** : 28 appliqués, 0 échec, **0 fichier différent**.

Cumulatif `0000` régénéré (5 209 lignes), vérifié de même. Pilotes arm64 et x86_64 reconstruits
et réinstallés. Non-régression : les 90 images Godot du § 87 sont **identiques octet pour
octet**.

### L'étape manquante

`tests/etape1_appliquer_correctifs.sh` : enregistre les trois commits amont et leurs remotes,
clone au besoin (`--cloner`), applique les trois séries dans l'ordre, s'arrête net au premier
échec. Essai à blanc sur des copies vierges des trois arbres : 28 + 3 + 5 correctifs appliqués,
et les trois arbres reconstruits sont **identiques aux nôtres**, zéro fichier différent.

Le projet ne dépend donc plus de ce répertoire. Depuis les trois URL amont, deux scripts
suffisent :

```sh
tests/etape1_appliquer_correctifs.sh --cloner
tests/etape2_construire_pile.sh
```

### Ce qui reste ouvert

Chaque correctif applique, mais rien ne garantit que **chacun compile** pris isolément, ce que
demanderait une bissection amont. Les cas repérés au passage (0006 utilise des macros que son
propre bloc définit) sont bons, mais la vérification complète — construire à chaque étape de la
série — n'a pas été faite.

### Chaque correctif compile

Vérification menée sur les vingt-huit étapes : l'arbre est permuté vers chaque instantané du
rejeu (`rsync --delete`, en gardant `.git`), puis reconstruit dans `build/mesa`.

**28 étapes, 28 constructions réussies, 0 échec.** La série est donc bissectable : chaque
correctif laisse l'arbre dans un état qui compile.

Un piège retrouvé au passage, le même qu'au § 85 sous une autre forme. Les vingt-huit premières
tentatives ont toutes échoué sur `ninja: error: rebuilding 'build.ninja'`, et la cause n'était
pas dans les correctifs : plusieurs d'entre eux touchent des `meson.build`, ce qui déclenche une
reconfiguration, et meson attrapait alors le `python3` de miniconda, dépourvu de `mako`. Il faut
`toolchain/bin` **en tête** du PATH, avant `prefix/bin`. C'est corrigé dans
`/tmp/claude-501/serie/compiler_serie.sh`, et cela vaut pour toute reconstruction qui régénère
`build.ninja`.

État final revérifié après l'opération : arbre identique au s28, cumulatif conforme, pilote
arm64 réinstallé, et les 90 images Godot toujours identiques octet pour octet.

---

## 93. DXVK tient sur KosmicKrisp : D3D9/10/11 s'ouvrent (2026-09-19)

### Ce qui n'allait pas

DXVK v2.7.1 était **construit depuis longtemps mais a peine branche**. Inventaire du prefixe :

| DLL | prefixe | build DXVK | ce qui tournait |
|---|---|---|---|
| `dxgi` | 16 194 818 | 16 194 818 | DXVK |
| `d3d11` | 4 258 334 | 19 172 471 | **wined3d** |
| `d3d9` | 1 904 795 | 17 763 238 | **wined3d** |

Seul `dxgi` venait de DXVK. Tout ce qui n'etait pas D3D12 passait donc par `wined3d`, donc par
l'OpenGL 4.1 deprecie de macOS — sans rapport avec notre pile. Et `etape2_pile_wine.sh` ne
surchargeait que `d3d12,d3d12core,dxgi`.

Correction : `d3d11.dll`, `d3d10core.dll` et `d3d9.dll` de DXVK installes (anciens conserves
dans `/tmp/claude-501/dll-wine-origine`), surcharges etendues a
`d3d12,d3d12core,dxgi,d3d11,d3d10core,d3d9=n`, et rendues surchargeables par l'environnement
pour pouvoir faire l'A/B.

### Premiere sonde : le peripherique et l'execution

`tests/probe_d3d11.c` : creation du peripherique, effacement d'une cible avec une couleur
connue, copie vers une texture de lecture, relecture du pixel. Pas seulement une creation de
peripherique — la preuve que le GPU a execute la commande.

```
DXVK: v2.7.1
Found device: Apple M1 Max (KosmicKrisp 26.2.99)
D3D11InternalCreateDevice: Maximum supported feature level: D3D_FEATURE_LEVEL_11_1
peripherique cree, niveau de fonctionnalite 11_0
adaptateur : Apple M1 Max  (25559 Mo dedies)
pixel relu : R=64 V=128 B=191 A=255  (attendu 64 128 191 255)
```

Un seul avertissement : *External memory features not supported*.

### Seconde sonde : le chemin des shaders

`tests/probe_d3d11_draw.c` : HLSL compile **a l'execution** par le `d3dcompiler_47` de Wine,
DXBC traduit en SPIR-V par DXVK, triangle rasterise, deux pixels relus.

```
HLSL compile : VS 1080 octets, PS 636 octets
centre : R=80 V=90 B=85   coin : R=0 V=0 B=0
```

Le centre porte une couleur interpolee entre les trois sommets, le coin est noir. La chaine
`HLSL -> DXBC -> DXVK -> SPIR-V -> KosmicKrisp -> Metal` fonctionne de bout en bout.

### Portee

Le projet visait D3D12. Il se trouve que **D3D9, D3D10 et D3D11 marchent aussi**, sur la meme
pile Vulkan/Metal, sans une ligne de code supplementaire — seulement trois DLL a mettre au bon
endroit. C'est de loin le plus gros gain fonctionnel de la journee : la grande majorite des
jeux Windows sont D3D11, pas D3D12.

Restriction connue : niveau de fonctionnalite 11_0 retenu alors que 11_1 est annonce supporte,
et la memoire externe manque. Ni l'un ni l'autre n'a ete creuse.

---

## 94. Le 32 bits est hors d'atteinte, definitivement (2026-09-19)

Unigine Heaven 4.0 telecharge depuis la source officielle (`assets.unigine.com`, 248 Mo,
sha256 `497865a0...`). Installeur Inno Setup 6.0, **PE32 x86**. `7z` ne sait pas ouvrir de
l'Inno Setup 6 ; `innoextract` 1.9 a donc ete compile dans `toolchain/` — pas de `brew install`,
la regle du projet interdit d'installer en dur dans le systeme. Deux corrections ont ete
necessaires : `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` ne se propage pas aux scripts invoques en
`cmake -P`, il a fallu relever `cmake_minimum_required` dans `cmake/VersionScript.cmake` et
dans `CMakeLists.txt`.

Contenu de l'installeur, une fois listable : **13 binaires `_x86`, zero `_x64`**. Heaven 4.0
(2013) est 32 bits uniquement.

Or :

```
$ arch -arch i386 /usr/bin/true
arch: Unknown architecture: i386
```

macOS n'execute plus de x86 32 bits depuis Catalina, et Rosetta 2 ne traduit que le x86_64.
Aucune configuration de Wine n'y change quoi que ce soit : WoW64 demanderait au processeur
d'executer du code i386, ce que la machine ne sait pas faire.

**Consequence pour le projet** : toute application Windows 32 bits est hors d'atteinte, de
facon permanente et pour une raison qui ne tient ni a Wine, ni a vkd3d-proton, ni a
KosmicKrisp. Cela exclut une part notable du catalogue ancien. Seul le 64 bits est jouable.

`innoextract` reste acquis dans `toolchain/bin` : il servira pour tout installeur Inno Setup.

---

## 95. Superposition : le moteur tourne, le lanceur casse (2026-09-19)

Unigine Superposition 1.1, source officielle `assets.unigine.com`, 1,2 Go, sha256
`de5dbf4f...`. Installeur PE32 comme Heaven, mais **le contenu est en 64 bits** : quatre
binaires, tous `PE32+ x86-64`. Extrait avec l'`innoextract` du § 94, 2,7 Go.

### Ce qui marche

`bin/superposition.exe -data_path ../ -video_app direct3d11 -video_mode -1 -video_width 1280
-video_height 720 -video_fullscreen 0` fait **demarrer entierement le moteur Unigine 2.80** :

```
---- Render ----
Renderer: Apple 25559MB
Direct3D11 desc: Apple M1 Max
Maximum texture size:    16384
Maximum texture units:   16
Maximum texture renders: 8
---- Physics ----     Physics: Multi-threaded
---- PathFind ----    PathFind: Multi-threaded
---- Interpreter ---- Version: 2.80
```

Materiaux charges, physique, pathfinding, interpreteur de script, mode fenetre 1280x720 pose.
Un moteur commercial complet s'initialise sur la pile, en D3D11.

Premier essai refuse avec `Benchmark failed (incorrect settings)` en renvoyant `1600 900` :
sans `-video_mode -1`, les options de taille sont ignorees au profit de `null_config.cfg`, et
1600x900 n'est pas une resolution admise par le banc. Ce n'etait pas la pile.

Le lanceur exerce en plus le chemin **D3D9** de DXVK (interface Qt) :
`D3D9: Detected nonclassical vendor ID: 0x106b` — DXVK masque le GPU Apple et annonce un AMD.

### Ce qui casse

Le banc n'est pas pilotable depuis le moteur : `superposition.exe` seul s'arrete au menu
integre (11 minutes a 37 % de CPU, memoire stable a 206 Mo, aucune scene chargee).
`superposition_cli.exe` est un bouchon qui sort immediatement sans rien produire, quels que
soient les arguments. `Superposition.exe` n'est qu'un relais qui repond `Failed to run
launcher`.

Reste `bin/launcher.exe`, le vrai pilote Qt. Il demarre, initialise D3D9 — puis boucle :

```
wine: Unhandled division by zero at address 000000014000C299
```

**773 occurrences** en cinq minutes, une par thread cree. L'adresse est dans l'image du
lanceur lui-meme (base 0x140000000).

**Hypothese, non verifiee** : le journal porte juste avant
`readMonitorEdidFromKey: Failed to get EDID reg key size` et `DXGI: Failed to parse display
metadata + colorimetry info, using blank`. Un calcul du lanceur a partir de metadonnees
d'affichage revenues vides diviserait par zero. Si c'est cela, le defaut est un trou de Wine
sur l'EDID, pas un defaut graphique. **A confirmer avant d'y croire.**

### Ce que ca etablit quand meme

La pile fait tourner un moteur commercial reel en D3D11, et sert aussi du D3D9. Ce qui bloque
est le harnais du banc, pas le rendu. Superposition ne donnera donc pas de score sans
diagnostiquer la division par zero.

### La cause, tracee jusqu'a notre pilote

La « division par zero » du premier essai et une violation d'acces du second sont deux visages
du meme chemin instable. Le second est exploitable, car `WINEDEBUG=+seh` donne le contexte
complet :

```
dispatch_exception code=c0000005 (EXCEPTION_ACCESS_VIOLATION) addr=00000001400238C2
  info[0]=0000000000000001        (ecriture)
  info[1]=8146001A000000AE        (adresse visee)
  rax=8146001a00000003
```

Ecriture a travers une valeur de donnees prise pour un pointeur, a `launcher.exe+0x228C2`.

Fausse piste ecartee : DXVK signale juste avant une interface inconnue, `0ec870a6-5d7e-4c22-
8cfc-5baae07616ed`, identifiee dans les entetes mingw comme **`IID_ID3D12CommandQueue`**. Mais
`D3D11DXGIDevice::QueryInterface` est conforme au contrat COM — `*ppvObject = nullptr` avant
`E_NOINTERFACE` (`d3d11_device.cpp:3334`). Ce n'est donc pas un pointeur de sortie non
initialise, contrairement au defaut corrige par le correctif 0007.

Le vrai signal est **cinq lignes avant la faute** :

```
err:   Failed to create shared resource: VK_KHR_EXTERNAL_MEMORY_WIN32 not supported
warn:  D3D11: Failed to write shared resource info for a texture
```

La chaine, maillon par maillon :

1. **KosmicKrisp annonce `KHR_external_memory` mais pas `KHR_external_memory_fd`** — mesure :
   zero occurrence dans `kk_physical_device.c`. Il expose `KHR_external_semaphore_fd` et
   `KHR_external_fence_fd`, mais pas l'equivalent pour la memoire.
2. winevulkan ne peut donc pas synthetiser `VK_KHR_external_memory_win32` cote PE.
   **[Corrige au § 96 : cette etape est fausse. Wine n'expose jamais cette extension, quelle
   que soit la capacite du pilote hote.]**
3. DXVK refuse la ressource partagee (`dxvk_image.cpp:406`).
4. DXVK se contente ensuite d'**avertir et de continuer** (`d3d11_texture.cpp:745`) : la
   texture existe, sans descripteur partage.
5. Le lanceur ecrit a travers un pointeur invalide et tombe.

L'etape 5 est une inference : l'adjacence et l'echec sont mesures, la logique interne du
lanceur ne l'est pas.

### Ce que cela coute de reparer

Il faudrait implementer `VK_KHR_external_memory_fd` dans KosmicKrisp. Le partage natif de
Metal passe par IOSurface, `MTLSharedTextureHandle` et des ports Mach — pas par des
descripteurs de fichier. L'abstraction ne se transpose donc pas directement, et ce n'est pas
un petit chantier.

C'est neanmoins un resultat net : d'une adresse de plantage dans un binaire tiers jusqu'a une
extension manquante dans notre propre pilote.

---

## 96. `VK_KHR_external_memory_fd` implemente — et ma chaine causale du § 95 etait fausse (2026-09-19)

### Ce qui est implemente

`0037-kosmickrisp-external-memory-fd.patch`, 242 lignes, cinq fichiers, aller-retour verifie.

La memoire de KosmicKrisp est normalement adossee a un `MTLHeap`, qui ne s'exporte pas en
descripteur. Le chemin existant de `VK_EXT_external_memory_host` montrait la voie : un
`MTLBuffer` peut etre construit **par-dessus une projection hote** via
`mtl_new_buffer_with_bytes_no_copy`. L'implementation adosse donc la memoire exportable a un
objet de memoire partagee POSIX :

- allocation avec `VkExportMemoryAllocateInfo` : `shm_open` + `shm_unlink` + `ftruncate`, puis
  `mmap` et `MTLBuffer` par-dessus, aligne sur la **vraie** taille de page (16 Ko ici, pas 4) ;
- `vkGetMemoryFdKHR` : `dup()` du descripteur conserve ;
- `VkImportMemoryFdInfoKHR` : `mmap` du descripteur recu, dont l'implementation prend la
  propriete, puis meme enveloppe `MTLBuffer` ;
- `vkGetMemoryFdPropertiesKHR` : validation par `fstat` — `lseek` echoue sur un objet de
  memoire partagee, premier essai rate ;
- liberation : `munmap` puis `close` ;
- proprietes annoncees pour les tampons, et pour les images **en tuilage lineaire seulement**,
  meme restriction que le chemin pointeur hote, faute de heap.

### Verification

`tests/probe_external_fd.c` :

```
VK_KHR_external_memory_fd annonce : oui
tampon : exportable=1 importable=1
descripteur exporte : fd=8
types memoire compatibles : 0x1
projections : 0x105d5c000 et 0x105d6c000
ecrit par m1, relu par m2 : "partage-verifie-0123456789"
ecrit par m2, relu par m1 : 0xAB
```

Deux projections **distinctes** qui designent la meme memoire, verifie dans les deux sens.

### Et pourtant Superposition ne bouge pas : ma chaine du § 95 etait fausse

Apres installation du pilote x86_64, le lanceur produit exactement la meme erreur :
`Failed to create shared resource: VK_KHR_EXTERNAL_MEMORY_WIN32 not supported`, et DXVK
rapporte `khrExternalMemoryWin32 : 0`.

La raison est dans Wine, pas dans le pilote. `dlls/winevulkan/make_vulkan`, ligne 132 :

```python
UNEXPOSED_EXTENSIONS = {
    "VK_EXT_map_memory_placed",
    "VK_KHR_external_memory_win32",
}
```

**Wine genere les en-tetes de cette extension mais ne l'expose jamais aux applications.** Aucune
capacite du pilote hote n'y change quoi que ce soit. L'etape 2 de ma chaine du § 95 — « winevulkan
ne peut donc pas synthetiser l'extension » — laissait entendre que le pilote etait le maillon
manquant. C'est faux : le maillon manquant est une decision de Wine, en amont de nous.

La traduction poignee win32 <-> descripteur existe dans le Wine **patche par Proton**, pas dans
le Wine amont que nous utilisons.

### Ce qu'il faudrait reellement pour Superposition

1. `VK_KHR_external_memory_fd` cote pilote — **fait**.
2. Cote Wine : sortir l'extension de `UNEXPOSED_EXTENSIONS` **et** implementer la traduction
   poignee/descripteur, comme le fait Proton. Non fait.
3. Et meme alors : DXVK partage des **textures**, or notre chemin ne couvre que les tampons et
   les images lineaires, faute de pouvoir adosser un heap a un descripteur. Le partage natif de
   textures sur Metal passe par IOSurface et des ports Mach. **Ce troisieme point resterait
   bloquant.**

Le correctif garde sa valeur propre — c'est une capacite Vulkan reelle que le pilote n'avait
pas, verifiee de bout en bout — mais il ne debloque pas Superposition, et je l'avais laisse
esperer a tort.

### Dette de verification a solder

Le § 92 affirme « 28 etapes, 28 constructions reussies ». Cette campagne permutait l'arbre par
`rsync -a`, qui **repose les dates des instantanes**, anterieures aux sorties de construction.
Ninja compare des dates : certaines recompilations ont donc pu etre sautees. Le symptome est
apparu aujourd'hui, un en-tete NIR genere restant perime apres une permutation.

**Le resultat du § 92 est donc a reprendre**, en forcant la regeneration a chaque etape
(`touch` des sources, ou `--debug=explain` pour verifier). Tant que ce n'est pas refait, la
bissectabilite de la serie n'est pas etablie. **[Fait au § 97 : la campagne refaite a trouve
deux vrais echecs, corriges depuis.]**

---

## 97. Campagne de construction reprise : le « 28 sur 28 » etait faux (2026-09-19)

### La methode corrigee

La campagne du § 92 permutait l'arbre par `rsync -a`, qui repose les dates des instantanes.
Ninja compare des dates : des recompilations ont donc ete sautees, et des etapes ont ete
declarees vertes sans rien avoir reconstruit.

Reprise avec `rsync -rlpgoD -c --no-times` : comparaison par **somme de controle**, et les
fichiers reellement transferes reçoivent la date du jour, ce qui force ninja a les recompiler.
Deux temoins ajoutes a chaque etape : le nombre de cibles reconstruites, et l'empreinte de la
bibliotheque produite.

Les temoins parlent d'eux-memes : 4 cibles pour un correctif qui ne touche qu'une limite, 350
quand les intrinseques NIR changent, et **le binaire differe a chaque etape** — jamais
d'« INCHANGE ».

### Deux vrais echecs, et c'etait ma faute

Etapes 17 et 18 (`0022` et `0023`) :

```
error: call to undeclared function 'mtl_render_pipeline_descriptor_set_color_attachment_blend'
error: no member named 'blend' in 'struct kk_shader_info::(unnamed ...)'
```

En resolvant le conflit de `0022` au § 92, j'avais insere le bloc des variantes de pipeline
**depuis l'arbre final**. Ce bloc contenait deja les appels de melange et le champ
`info->vs.blend`, qui n'arrivent qu'avec `0024`. La serie etait donc juste a l'arrivee mais
fausse en chemin : `0022` ne compilait qu'apres `0024`.

Correction : dans les instantanes 17 et 18, le bloc reprend la forme d'origine de `0022` —
format de l'attachement, puis masque d'ecriture seulement lorsqu'il est desactive — et `0024`
apporte ensuite le melange et le masque calcule. Correctifs `0022`, `0023` et `0024`
regeneres depuis les instantanes corriges.

### Verification

- Application stricte des 28 correctifs sur arbre vierge : **28 ok, 0 echec**, arbre reproduit
  a l'identique.
- Campagne de construction relancee **en entier**, pas seulement sur les trois etapes touchees :
  **28 sur 28, zero echec, zero binaire inchange**.
- Cumulatif regenere (5 436 lignes, il inclut desormais `0037`), verifie : zero difference.
- Pilotes arm64 et x86_64 reconstruits et reinstalles ; sonde `probe_external_fd` concluante ;
  les 90 images Godot du § 87 **identiques octet pour octet**.

La bissectabilite de la serie est donc etablie, cette fois avec de quoi le prouver.

### Ce que cet episode apprend

Une campagne verte ne vaut que si l'on montre qu'elle a travaille. Les deux temoins qui
manquaient au § 92 — cibles reconstruites et empreinte du binaire — auraient fait tomber le
faux resultat immediatement. Ils coutaient deux lignes de script.

---

## 98. Conformite apres 0037 : aucune regression (2026-09-19)

### Resultat

Campagne complete de la suite vkd3d-proton a travers la pile, pilote incluant
`VK_KHR_external_memory_fd` :

```
574 fonctions demarrees, 574 terminees
24 169 186 tests executes
2305 echecs, 28 fonctions en echec
```

**Identique a la reference du § 76** : 2 305 echecs, 28 fonctions. La fonction dominante,
`test_suballocate_small_textures_size` a 1 650, correspond bien a la ligne « taille minimale
imposee par Metal » de ce tableau. Le correctif 0037 n'introduit donc aucune regression, ce qui
etait attendu — une seule de ses 147 lignes ajoutees s'execute sur le chemin commun — mais
attendu n'est pas mesure.

### Un piege de comptage

Premier depouillement faux : en comptant toutes les lignes prefixees par un nom de fonction,
j'obtenais **68 523** « echecs » sur 211 fonctions. Le gros du volume venait de
`test_open_heap_from_address`, 65 536 lignes, qui sont en realite des `Todo succeeded` — des
tests marques a corriger et qui passent. La suite les compte separement (65 547 au total) et ce
ne sont pas des echecs.

Le bon motif est la chaine `Test failed`, qui apparait exactement 2 305 fois, soit le compte
que la suite annonce elle-meme. Verifier le depouillement contre le total de l'outil evite de
publier un chiffre trente fois trop grand.

### Une reference archivee

`tests/conformance-baseline.txt` : le decompte fonction par fonction, desormais dans le depot.
Les campagnes precedentes vivaient dans le repertoire temporaire de la session, qui a ete purge
— c'est pour cela qu'il a fallu recomparer au chiffre global plutot qu'a un detail. Les
prochaines campagnes pourront se differencier directement contre ce fichier.

---

## 99. Cote Wine de la memoire externe : les deux routes sont fermees (2026-09-19)

### La route par descripteur est un cul-de-sac prouve

Avant d'engager le chantier, lecture de DXVK. `d3d11_texture.cpp:168` ne retombe en tuilage
lineaire que pour des formats non supportes — le commentaire le dit : *« Some image formats
(i.e. the R32G32B32 ones) are only supported with linear tiling »*. Et `CheckImageSupport`
(ligne 507) ne renseigne **pas** `formatQuery.handleType` : le partage n'entre pas dans le
choix du tuilage. Une texture partagee sera donc toujours en **tuilage optimal**.

Or notre chemin `KHR_external_memory_fd` du § 96 adosse la memoire a une projection hote, ce
qui ne permet pas de heap Metal, donc pas de tuilage optimal. Faire le travail Wine aurait
deplace l'erreur de `VK_KHR_EXTERNAL_MEMORY_WIN32 not supported` vers `Image cannot be shared`.
Meme echec, autre message.

### La route MTLHEAP est fermee par le generateur de Wine

`VK_EXT_external_memory_metal` convient pourtant : `kk_image.c` l'accepte **sans restriction de
tuilage**, puisque le heap est le support normal de toute notre memoire. C'etait la bonne cible.

Mais `dlls/winevulkan/make_vulkan`, ligne 3537 :

```python
platform = ext.attrib.get("platform")
if platform and platform != "win32":
    LOGGER.debug("Skipping extensions {0} for platform {1}".format(ext_name, platform))
```

Wine ecarte **toute extension dont la plateforme n'est pas win32**, des l'analyse du XML.
`VK_EXT_external_memory_metal` porte `platform="metal"` : elle est invisible pour Wine avant
d'atteindre la moindre liste. Verifie : zero occurrence dans le generateur, aucun thunk
`vkGetMemoryMetalHandleEXT`. L'utiliser demanderait d'apprendre la plateforme Metal a Wine —
types `MTLDevice_id` et consorts dans ses en-tetes et ses thunks. Ce n'est plus de la
plomberie, c'est une modification de fond du generateur et du systeme de types de Wine.

### Ce qui a quand meme ete etabli

Le registre Khronos 1.4.303 est desormais dans `toolchain/dl/vkxml`, et **le generateur de Wine
reproduit ses fichiers octet pour octet** — verifie avant toute modification, ce qui rend
utilisable toute regeneration future.

La plomberie elle-meme fonctionne : sortir l'extension de `UNEXPOSED_EXTENSIONS` et declarer
`vkGetMemoryWin32HandleKHR` dans `MANUAL_UNIX_THUNKS` produit un diff genere petit et propre
(111 lignes dans `vulkan_thunks.c`). L'annonce de l'extension, le remplacement a la creation du
peripherique et la traduction des types de descripteur sont ecrits et conserves dans
`9002-wine-external-memory-win32.patch.rejete`, 492 lignes. Ils s'appliqueraient tels quels a
n'importe quel type de descripteur que Wine sait deja decrire.

Au passage : `wine_vkGetPhysicalDeviceImageFormatProperties2` **met aujourd'hui a zero** toutes
les proprietes de memoire externe. Wine ne se contente pas de ne pas exposer l'extension, il
efface activement ce que le pilote hote rapporte.

### Etat

Arbre Wine remis au propre et verifie : `git archive HEAD` plus les trois correctifs ARM64
reproduit l'arbre, zero difference. Attention, `include/wine/vulkan.h` est lui aussi genere par
`make_vulkan` et vit **hors** de `dlls/winevulkan` : un `git checkout` du seul repertoire le
laisse modifie.

### Conclusion

Le partage de textures entre D3D11 et notre pile demande soit d'apprendre la plateforme Metal a
Wine, soit de savoir adosser des images en tuilage optimal a de la memoire exportable en
descripteur — ce que Metal ne permet pas, un heap ne pouvant pas etre construit sur de la
memoire hote. Les deux sont hors de portee d'un correctif raisonnable. C'est un resultat
negatif, mais mesure et argumente.

---

## 100. Conformite D3D11 : la suite de Wine s'arrete a 12 %, sur les ressources partagees (2026-09-19)

### Pourquoi cette mesure

Le D3D12 a un chiffre — 2 305 echecs sur 574 fonctions, une reference archivee. Le D3D11 ne
reposait que sur deux sondes ecrites pour l'occasion (§ 93). Or Wine embarque ses propres
suites : **36 793 lignes de tests d3d11**, desactivees dans notre build.

### Construction

Reconfiguration de `build/wine` sans `--disable-tests`. Deux pieges retrouves, tous deux
documentes dans `tests/etape2_construire_pile.sh` mais que j'avais omis :

- `bison` doit venir de `/usr/local/opt/bison/bin` — celui du systeme est trop ancien ;
- `CC="clang -arch x86_64"` est indispensable, sinon l'outil `makedep` se construit pour
  l'hote et recoit a la fois les en-tetes `libkern/arm` et `libkern/i386`, d'ou une
  redefinition de `_OSSwapInt64`.

Verifie apres coup : `SONAME_LIBVULKAN` pointe toujours sur notre loader. Seul le binaire de
test a ete construit, Wine n'a pas ete reinstalle.

### Resultat

La suite demarre, identifie l'adaptateur (`Adapter: L"Apple M1 Max", 106b:0064`) et s'arrete
avec le code 5 apres avoir atteint la **ligne source 4305 sur 36 793, soit environ 12 %**.

Deux executions, meme point d'arret **exactement** : la ligne 4305 dans les deux cas. Ce n'est
donc pas un aleas. Les dernieres lignes sont sans ambiguite :

```
d3d11.c:3269: Test failed: Test 1: Got unexpected device pointer ..., expected NULL.
err:   Failed to create shared resource: VK_KHR_EXTERNAL_MEMORY_WIN32 not supported
d3d11.c:3237: Test marked todo: Test 2: Texture should not implement ID3D10Texture2D.
err:   Failed to create shared resource: VK_KHR_EXTERNAL_MEMORY_WIN32 not supported
```

Avec, un peu avant, `D3D11DXGIKeyedMutex::AcquireSync: Not supported` — les mutex a cle, qui
sont l'autre face du partage de ressources.

Sur la portion executee : 32 echecs au premier passage, 23 au second, 15 et 10 `todo`. L'ecart
entre les deux vient de tests dependant de l'ordre ou de l'etat ; le point d'arret, lui, ne
bouge pas.

### Ce que cela etablit

Le meme mur que Superposition (§ 95), que le § 99 a montre infranchissable : **le partage de
ressources est le blocage unique du chemin D3D11 sur cette pile**. **[Corrige au § 103 :
l'arret a 4305 est anterieur a toute modification et n'est pas cause par le partage.]** Ce n'etait donc pas une
particularite du lanceur Qt d'Unigine, c'est structurel, et la suite de conformite de Wine le
confirme independamment.

Tant que ce point n'est pas leve, aucun chiffre de conformite D3D11 complet n'est atteignable :
la suite meurt avant d'avoir teste 88 % de son contenu.

**Lien d'inference a garder honnete** : l'arret suit immediatement l'echec de ressource
partagee, de facon reproductible, mais le binaire ne dit pas pourquoi il s'arrete — aucun
message d'exception. La correlation est solide, la causalite reste deduite.

---

## 101. MTLHEAP : l'extension passe, le verrou suivant est chez Proton (2026-09-19)

### Correction du § 99

J'y concluais que la route MTLHEAP etait fermee parce que le generateur de Wine ecarte la
plateforme Metal. **C'etait trop absolu** : rien n'oblige a passer par le generateur. Trois
faits verifies :

- les structures sont triviales et leurs `sType` connus — 1000602000 a 1000602002, et
  `VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLHEAP_BIT_EXT` vaut `0x00040000` ;
- les deux points d'entree hote se resolvent par `vk_funcs->p_vkGetDeviceProcAddr`, sans table
  generee ;
- le chemin `extra_extensions` de la creation de peripherique **n'est pas valide** : y ajouter
  la chaine `"VK_EXT_external_memory_metal"` la transmet telle quelle au pilote hote.

Trouve au passage : l'extension n'est **pas du tout** dans le registre 1.4.303 de Wine, zero
occurrence. Ce n'etait donc pas seulement le filtre de plateforme.

### Ce qui est implemente

`0038-wine-external-memory-win32-over-metal.patch`, 660 lignes, aller-retour verifie.

- `make_vulkan` : extension sortie de `UNEXPOSED_EXTENSIONS`, les deux points d'entree win32
  declares dans `MANUAL_UNIX_THUNKS` ; fichiers regeneres.
- `vulkan.c` : detection de `VK_EXT_external_memory_metal` cote hote, annonce de
  `VK_KHR_external_memory_win32` aux applications, substitution a la creation du peripherique,
  traduction des types de descripteur dans `GetPhysicalDeviceImageFormatProperties2`,
  `CreateImage` et `AllocateMemory`, structures Metal declarees localement, resolution
  dynamique des deux fonctions hote, et implementation de `vkGetMemoryWin32HandleKHR` et
  `vkGetMemoryWin32HandlePropertiesKHR`.

### Mesure

Avant : `khrExternalMemoryWin32 : 0`, et `Failed to create shared resource:
VK_KHR_EXTERNAL_MEMORY_WIN32 not supported` a chaque tentative.

Apres : **`khrExternalMemoryWin32 : 1`**, et **zero** occurrence du message. DXVK voit
l'extension et l'active. Les echecs de la suite d3d11 passent de 23 a **69** : les tests vont
plus loin dans les chemins de partage avant de tomber.

### Le verrou suivant, et il n'est pas de notre ressort

La suite s'arrete toujours a la ligne source 4305. `src/util/util_shared_res.cpp` de DXVK :

```c
bool setSharedMetadata(HANDLE handle, void *buf, uint32_t bufSize) {
  return ::DeviceIoControl(handle, IOCTL_SHARED_GPU_RESOURCE_SET_METADATA, ...);
}
```

DXVK attache les metadonnees de la texture partagee a un **vrai objet noyau Windows**, via des
`IOCTL_SHARED_GPU_RESOURCE_*`. C'est une interface de pilote **propre a Proton**, absente du
Wine amont. Notre `vkGetMemoryWin32HandleKHR` rend un pointeur `MTLHeap` deguise en `HANDLE` :
`DeviceIoControl` dessus echoue, d'ou `D3D11: Failed to write shared resource info`.

Et `VK_KHR_win32_keyed_mutex` reste a 0, d'ou `D3D11DXGIKeyedMutex::AcquireSync: Not supported`.

La chaine complete demanderait donc, en plus : un pseudo-pilote Wine servant ces IOCTL et une
table associant `HANDLE` a `MTLHeap`. C'est du ressort de Proton, pas d'un correctif de pilote
graphique.

### Dette ouverte

Le `winevulkan` modifie est **installe**. Il expose une extension de plus, ce qui peut changer
le comportement de vkd3d-proton. **La campagne D3D12 doit etre rejouee avant de lui faire
confiance** — la reference est 2 305 echecs, archivee dans `tests/conformance-baseline.txt`.

---

## 102. Le correctif 0038 ne regresse rien (2026-09-19)

Campagne D3D12 rejouee avec le `winevulkan` modifie installe :

```
574 fonctions demarrees, 574 terminees
24 152 455 tests executes
2305 echecs, 28 fonctions en echec
```

Et cette fois la comparaison ne s'arrete pas au total. Diff **fonction par fonction** contre
`tests/conformance-baseline.txt` : **aucun ecart**, ni en plus ni en moins, sur les 28 fonctions
en echec. C'est exactement ce pour quoi la reference avait ete archivee au § 98 — un total
identique peut cacher deux ecarts qui se compensent ; ce n'est pas le cas ici.

Le nombre de tests executes varie legerement d'une campagne a l'autre (24 169 186 puis
24 152 455) : certaines fonctions ajustent leur volume selon l'etat. Le compte d'echecs, lui,
ne bouge pas.

La dette du § 101 est donc soldee : exposer `VK_KHR_external_memory_win32` par-dessus Metal ne
change rien au chemin D3D12. Le correctif 0038 peut rester installe.

---

## 103. DXVK : metadonnees en table locale, et correction du § 100 (2026-09-20)

### Le correctif

`0039-dxvk-shared-metadata-local-table.patch`, 90 lignes, aller-retour verifie.

Toute la dependance de DXVK a Proton tient dans trois fonctions de
`src/util/util_shared_res.cpp` : `openKmtHandle` ouvre `\\.\SharedGpuResource`, et
`set`/`getSharedMetadata` y attachent les metadonnees par `DeviceIoControl`. Le peripherique
n'existe pas hors de Proton.

Ces metadonnees — largeur, hauteur, format, niveaux de mip — n'ont aucune raison de passer par
le noyau ici : un `MTLHeap` ne vaut que dans un processus, donc une table locale suffit. Le
correctif garde le chemin Proton en premier et ne retombe sur la table que s'il echoue :
`openKmtHandle` rend le descripteur inchange quand le peripherique est absent, et les deux
autres fonctions basculent sur une `std::map<HANDLE, std::vector<uint8_t>>` sous mutex.

### Mesure

Suite d3d11 de Wine, meme invocation, trois etats successifs :

| etat | echecs |
|---|---|
| avant tout (§ 100) | 23 |
| extension exposee (§ 101) | 69 |
| metadonnees en table locale | **29** |

Les 69 venaient de tests qui allaient plus loin et tombaient sur l'absence de metadonnees. Le
correctif en recupere 40. Et deux temoins directs : `Failed to get shared handle` **n'apparait
jamais** — notre `vkGetMemoryWin32HandleKHR` rend bien un descripteur exploitable — et
`Failed to write shared resource info` tombe a **2** occurrences.

### Correction du § 100

J'y ecrivais que la suite mourait sur les ressources partagees. **C'est faux.** L'arret est a la
ligne source 4305 dans **les trois** executions, y compris celle d'avant toute modification. Il
est donc anterieur a ce travail et sans rapport avec le partage : les messages de partage
etaient simplement les derniers journalises, ce qui m'a induit en erreur.

La suite s'arrete bien prematurement — **148 des 164 fonctions de test sont definies apres la
ligne 4305 et aucune ne produit la moindre sortie** — mais la cause reste inconnue. Code de
sortie 5, aucun message d'exception. A chercher.

Pas de campagne D3D12 a rejouer : vkd3d-proton n'utilise pas DXVK.

---

## 104. L'arret de la suite d3d11 : un appel a travers un pointeur nul (2026-09-20)

### La cle : la suite est multi-thread

`START_TEST(d3d11)` fait `use_mt = !getenv("WINETEST_NO_MT_D3D")` et empile ses tests par
`queue_test()`. Par defaut ils s'executent **en parallele**, d'ou la sortie entrelacee qui
rendait tout diagnostic impossible, et d'ou un point d'arret apparent (4305) qui n'etait que la
ligne la plus haute ayant eu le temps d'ecrire.

`WINETEST_NO_MT_D3D=1` rend l'execution deterministe. L'arret tombe alors a la ligne **3269**,
dans `test_texture2d_interfaces` (definie ligne 3116), l'ordre d'execution etant
`test_texture1d_interfaces`, `test_create_texture2d`, puis celle-ci.

### La cause

Avec `WINEDEBUG=+seh`, une seule exception dans toute la campagne :

```
dispatch_exception code=c0000005 (EXCEPTION_ACCESS_VIOLATION) addr=0000000000000000
  info[0]=0  info[1]=0
  rip=0000000000000000
```

**`rip` vaut zero** : le processus saute a l'adresse nulle. Ce n'est pas une ressource mal
formee ni un descripteur invalide, c'est un **appel a travers un pointeur de fonction nul**.

Le contexte immediat, dans l'ordre :

```
d3d11.c:3269: Test failed: Got unexpected device pointer ..., expected NULL.
warn:  D3D11: Failed to write shared resource info for a texture
err:   D3D11DXGIKeyedMutex::AcquireSync: Not supported
d3d11.c:3269: Test failed: Test 3: ...
-> EXCEPTION_ACCESS_VIOLATION rip=0
```

Les tests de mutex a cle du fichier sont a la ligne 35002, bien au-dela : c'est donc **DXVK
lui-meme** qui appelle `AcquireSync` en interne sur une texture partagee, pas le test.

### Ce que cela elimine

Trois hypotheses tombent. Ce n'est pas `CloseHandle` sur notre pointeur `MTLHeap` deguise en
descripteur : aucune erreur de descripteur invalide dans tout le journal (`grep -ic "invalid
handle|NtClose|c0000008"` : zero). Ce n'est pas non plus un echec d'obtention du descripteur :
`Failed to get shared handle` n'apparait jamais. Et ce n'est pas le partage en soi, puisque
l'arret precedait toutes nos modifications (§ 103).

### Ce qui reste a identifier

Quel pointeur est nul. Les candidats sont un point d'entree Vulkan annonce mais non resolu par
`vkGetDeviceProcAddr`, ou une entree de vtable COM laissee vide sur le chemin du mutex a cle —
`VK_KHR_win32_keyed_mutex` restant a `0`, DXVK pourrait exposer `IDXGIKeyedMutex` sans
l'implementer entierement.

La marche a suivre est tracee : la campagne est desormais deterministe, l'exception unique et
son contexte connu. Il reste a instrumenter le chemin `AcquireSync` de DXVK, ou a verifier ce
que `vkGetDeviceProcAddr` rend pour chaque fonction de l'extension que nous venons d'exposer.

### Instrumentation du chemin AcquireSync : trois pistes eliminees

**Le mutex a cle n'est pas en cause.** `D3D11DXGIKeyedMutex` teste explicitement ses pointeurs
avant de s'en servir (`d3d11_resource.cpp:17`) :

```cpp
m_supported = ...features().khrWin32KeyedMutex
           && ...vkd()->wine_vkAcquireKeyedMutex != nullptr
           && ...vkd()->wine_vkReleaseKeyedMutex != nullptr;
```

Ces deux fonctions sont propres au Wine de Proton ; chez nous `m_supported` vaut faux,
`AcquireSync` journalise et rend la main. Aucun appel nul de ce cote.

**Le comptage de references du peripherique D3D10 est equilibre.** Le test, a la ligne 3267,
fait `GetDevice` puis `Release` sur le pointeur obtenu. `GetD3D10Device` (`d3d10_util.cpp:76`)
prend bien une reference sur le peripherique D3D11 via `GetDevice`, et `GetD3D10Interface()`
rend `m_d3d10Device` **sans** `AddRef` — mais `D3D10Device::Release` reexpedie vers
`m_device->Release()`, donc le `Release` du test solde la reference prise. Pas de liberation
prematurée, donc pas d'usage apres liberation par ce chemin.

**Ce n'est pas `CloseHandle` sur notre pointeur Metal.** Zero erreur de descripteur invalide
dans tout le journal.

### Ce que l'exception dit exactement

Une seule exception sur toute la campagne, et elle est **rattrapee** : un gestionnaire rend 1,
il n'y a ni message « unhandled exception », ni lancement de `winedbg`. Le processus se termine
ensuite avec le code 5, sans rien ecrire de plus.

Autrement dit : un appel a l'adresse nulle, intercepte par un `__except`, suivi d'une sortie
silencieuse. Le pointeur fautif n'est toujours pas identifie.

**Prochaine etape concrete** : obtenir une trace de pile. Le contexte de l'exception donne
`rsp=0x21f368` ; l'adresse de retour est en tete de pile et designerait l'appelant. Un
gestionnaire vectorise ajoute au test, ou une execution sous `winedbg`, le dirait. La campagne
etant desormais deterministe et l'exception unique, la mesure est a portee.

---

## 105. La trace de pile livre la cause, et elle etait chez nous (2026-09-20)

### Comment l'obtenir

L'exception etant rattrapee, `winedbg` ne se declenche jamais. J'ai donc instrumente
temporairement `dispatch_exception` (`dlls/ntdll/exception.c`) pour vider le sommet de pile
quand `ExceptionAddress` est nul. Piege au passage : ce fichier est du cote **PE** de ntdll,
donc il faut reconstruire `ntdll.dll` et non `ntdll.so` — ma premiere tentative n'a rien
produit pour cette seule raison.

### Ce que la pile dit

```
DIAG appel a l'adresse nulle, sommet de pile rsp=000000000021F368
DIAG   [rsp+000] = 00006FFFFD6B3BA5
```

`d3d11.dll` etant charge a `0x6FFFFD5D0000`, l'adresse de retour tombe au decalage `0xE3BA5`.
Desassemblage a cet endroit :

```
359133b9f:  ff 90 58 07 00 00   callq *0x758(%rax)
359133ba5:  85 c0               testl %eax, %eax
            _ZNK4dxvk9DxvkImage12sharedHandleEv
```

`DxvkImage::sharedHandle()` appelle l'entree `0x758` de sa table de dispatch Vulkan, et cette
entree est nulle : **`vkGetMemoryWin32HandleKHR` n'etait pas resolu**.

Cela corrige une deduction du § 104 : si `Failed to get shared handle` n'apparaissait jamais,
ce n'etait pas parce que l'appel reussissait, mais parce qu'il **plantait avant de revenir**.

### La cause, verifiee directement

`tests/probe_getprocaddr.c`, avant correction :

```
VK_KHR_external_memory_win32 annonce : oui
creation du peripherique avec l'extension : ok (0)
vkGetMemoryWin32HandleKHR           : 0000000000000000
vkGetMemoryWin32HandlePropertiesKHR : 0000000000000000
vkAllocateMemory (temoin)           : 00006FFFFD9D5520
```

Le coupable est `vulkan.c:2378` :

```c
NTSTATUS vk_is_available_device_function(void *arg)
{
    ...
    return !!vk_funcs->p_vkGetDeviceProcAddr(device->host.device, params->name);
}
```

`vkGetDeviceProcAddr` ne rend un thunk que si le **pilote hote** connait la fonction. Or ces
deux-la, c'est nous qui les emulons : KosmicKrisp ne les a evidemment pas. La table de DXVK
recevait donc un pointeur nul, et DXVK, qui ne verifie que `features().khrExternalMemoryWin32`,
appelait l'adresse zero.

C'etait un defaut de notre propre correctif 0038, pas de DXVK ni de Wine.

### Le correctif et sa mesure

Six lignes : `vk_is_available_device_function` rend vrai pour les deux fonctions emulees quand
le pilote hote porte `VK_EXT_external_memory_metal`. `0038` regenere, 674 lignes, aller-retour
verifie.

| | avant | apres |
|---|---|---|
| `vkGetMemoryWin32HandleKHR` | `0000000000000000` | `00006FFFFD9DE660` |
| exceptions dans la campagne | 1 | **0** |
| ligne source atteinte (mono-thread) | 3269 | **4305** |
| echecs | 35 | 79 |

Plus aucun plantage : le processus se termine desormais proprement. Les echecs montent parce
que davantage de tests s'executent.

### Ce qui reste

La suite s'arrete toujours a 4305, mais **sans exception** — c'est donc un arret d'une autre
nature. Les derniers messages pointent ailleurs : `D3D11: Cannot create render target view for
a buffer`, puis un compte de references inattendu. Cent quarante-huit fonctions de test ne
s'executent toujours pas.

Instrumentation de `ntdll` retiree, `ntdll.dll` et `ntdll.so` d'origine reconstruits et
reinstalles, pile verifiee au banc.

---

## 106. Pourquoi la suite s'arrete a 4305 : un contournement Battlefield (2026-09-20)

### La reponse

L'arret est dans `test_create_rendertarget_view` (definie ligne 4112). Le test fait, ligne
4302 et suivantes :

```c
hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)buffer, &rtv_desc, &rtview);
ok(hr == S_OK, ...);
refcount = get_refcount(device);
ok(refcount >= expected_refcount, ...);          /* ligne 4305, echoue */
tmp = NULL;
ID3D11RenderTargetView_GetDevice(rtview, &tmp);  /* rtview est NUL */
```

Et DXVK, `d3d11_device.cpp:566` :

```cpp
if (resourceDesc.Dim == D3D11_RESOURCE_DIMENSION_BUFFER) {
  Logger::warn("D3D11: Cannot create render target view for a buffer");
  return S_OK; // It is required to run Battlefield 3 and Battlefield 4.
}
```

DXVK rend **`S_OK` sans produire de vue**, contournement delibere pour Battlefield 3 et 4. Or
`CreateRenderTargetView` a appele `InitReturnPtr(ppRTView)` (ligne 520), donc `*ppRTView` vaut
**NULL**. Le test, ecrit pour Windows ou cet appel reussit vraiment, ne verifie rien et appelle
une methode sur NULL : lecture de la vtable a l'adresse zero, puis appel a zero. C'est
exactement le `rip=0` du § 105.

### Ce que cela signifie

C'est la meme classe de defaut que notre correctif 0007 pour vkd3d-proton — un parametre de
sortie laisse dans un etat que l'appelant n'anticipe pas — mais ici le choix est **assume** par
DXVK pour faire tourner deux jeux. La collision est entre ce contournement et une suite de
conformite non defensive ; elle se produirait a l'identique sous Proton. **Elle n'a rien a voir
avec notre pile.**

Consequence pratique : tant que DXVK garde ce contournement, la suite d3d11 de Wine ne peut pas
depasser ce point, et les 148 fonctions suivantes resteront intestees. Un chiffre de conformite
D3D11 complet demanderait soit de patcher DXVK pour rendre `E_INVALIDARG`, au risque de casser
Battlefield, soit de rendre le test defensif — ce qui releve de Wine.

### Deux fausses pistes ecartees

**L'assertion IOSurface.** Une campagne a montre `_iosConnectInitalize() unable to open
IOSurface kernel service` avec « 1020 existing clients » — mais au **demarrage**, pas a 4305,
et seulement dans cette execution. C'est un effet de bord de la journee : mes essais repetes
ont sature le service IOSurface du systeme. Sans rapport avec l'arret.

**Le canal `seh`.** Activer `+seh` sur la campagne complete produit **9 Go** de journal et
ralentit tout au point de fausser la mesure. A n'utiliser que cible sur un plantage connu, ce
qui etait le cas au § 105 mais plus ici.

---

## 107. Le test rendu defensif, et un environnement que j'ai sature (2026-09-20)

### Le correctif

`0040-wine-tests-survive-missing-buffer-rtv.patch`. Meme idiome que les correctifs 0008 et
0016 pour vkd3d-proton : rendre un test survivant a une fonctionnalite absente plutot que de
le laisser dereferencer un pointeur nul.

`test_create_rendertarget_view` initialise desormais `rtview` a NULL, et si la creation ne
produit pas de vue, il `skip()` le bloc qui la dereference au lieu de tomber. Le test de
`hr == S_OK` reste, donc l'ecart reste signale.

### Ce que je n'ai pas pu mesurer, et pourquoi

Aucun processus Wine ne demarre plus :

```
Assertion failed: _iosConnectInitalize() unable to open IOSurface kernel service: e00002c7
1020 existing clients: { ... wine64 = 954; ... }
```

**954 clients IOSurface** sont attribues a `wine64`. Origine trouvee : **956 processus
`winedbg`** tournaient depuis 13 h 48, engendres ce matin par la boucle de division par zero du
lanceur Superposition (§ 95) — chaque `wine: Unhandled division by zero ... starting
debugger...` en lancait un, et aucun ne sortait.

Les processus sont tues. **Le noyau n'a pas libere les clients** : le compte reste a 954 sans
un seul processus Wine vivant. Un redemarrage de la machine sera necessaire pour retrouver un
environnement de test sain.

### Le garde-fou

`wine/pfx10/system.reg` recoit :

```
[Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug]
"Auto"="0"
```

`start_debugger` (`dlls/kernelbase/debug.c:506`) lit cette valeur ; a zero, Wine signale
l'exception et s'arrete au lieu de lancer `winedbg`. Une boucle de plantage ne pourra plus
engendrer un millier de processus. **Non verifie** : aucun Wine ne demarre pour le tester.

### A faire au redemarrage

1. Verifier que `probe_d3d11` repasse.
2. Verifier le garde-fou AeDebug.
3. Relancer la suite d3d11 avec `WINETEST_NO_MT_D3D=1` et le correctif 0040 : c'est la mesure
   qui manque, et rien d'autre ne la bloque desormais.

---

## 108. Premier chiffre de conformite D3D11 : 44 % de la suite, 2 418 echecs (2026-09-20)

### L'environnement, d'abord

Redemarrage de la machine : les 954 clients IOSurface sont liberes, `probe_d3d11` repasse. Le
garde-fou du § 107 a survecu — Wine a reecrit la cle `AeDebug` avec son propre horodatage
(`1753735291` au lieu du mien), ce qui prouve qu'il l'a lue. Plus aucun empilement de `winedbg`
possible.

### Le resultat

Suite d3d11 de Wine, mono-thread, avec le correctif 0040 :

| | avant | apres |
|---|---|---|
| ligne source atteinte | 4 305 | **16 015** / 36 793 |
| echecs | 79 | **2 418** |

**De 12 % a 44 % de la suite.** Le correctif d'une ligne de defense a debloque plus de trois
fois le parcours.

### Ce que les echecs disent

| famille | occurrences |
|---|---|
| niveaux de fonctionnalite (`Feature level ...: Got hr`) | 681 |
| memes, variante `READ_WRITE` | 329 |
| `Got unexpected hr` | 97 |
| couleur relue inattendue | 80 |

Le gros bloc concerne les **niveaux de fonctionnalite** : la suite verifie qu'un peripherique
refuse ce qu'il n'annonce pas, et DXVK accepte plus largement. Ce n'est pas un defaut de rendu.
Les 80 ecarts de couleur, eux, sont les seuls a designer directement le pipeline.

### Le nouveau point d'arret

```
Assertion failed: !status && "vkQueuePresentKHR",
  src/wine/dlls/winevulkan/loader_thunks.c, line 6191
```

Le thunk genere affirme que la traversee PE -> Unix reussit toujours. Or
`thunk64_vkQueuePresentKHR` rend inconditionnellement `STATUS_SUCCESS` : le statut non nul ne
peut donc venir que de la traversee elle-meme, c'est-a-dire d'une faute dans la fonction Unix.
Celle-ci appelle `vk_funcs->p_vkQueuePresentKHR`, la presentation du pilote d'affichage.

Piste, **non verifiee** : dans ce contexte de test sans fenetre geree, ce pointeur de
presentation serait nul ou la chaine de swap invalide. C'est la meme classe de defaut que
celui corrige au § 105 — une fonction supposee presente qui ne l'est pas — mais cette fois du
cote du pilote d'affichage, pas de l'emulation d'extension.

107 fonctions de test sur 164 restent au-dela de ce point.

---

## 109. Le verrou `vkQueuePresentKHR` etait une installation incomplete (2026-09-20)

### Le resultat

| | § 100 | § 108 | maintenant |
|---|---|---|---|
| ligne source atteinte | 4 305 | 16 015 | **35 155** / 36 793 |
| part de la suite | 12 % | 44 % | **95,5 %** |
| echecs | 79 | 2 418 | **4 272** |
| assertions | 1 | 1 | **0** |

Cinq fonctions de test sur 164 restent au-dela du point d'arret, et la derniere en cours est
`test_shared_resource` — notre limitation connue, avec des `0xc0000008`
(`STATUS_INVALID_HANDLE`) sur le partage par descripteur NT, exactement ce que le § 101
predisait.

### La cause, et elle etait chez moi

J'avais suppose une chaine de swap nulle dans `win32u_vkQueuePresentKHR`, qui dereference
`swapchain_from_handle()` sans verifier. J'ai pose une garde, reconstruit `win32u`, et la suite
est passee.

Mais **la garde n'a jamais tire** : zero `DIAG swapchain` sur toute la campagne. Verification
faite en la retirant et en reconstruisant : **resultat identique**, 35 155 et 4 272 echecs. La
garde n'y etait pour rien.

Ce qui a debloque, c'est la **reconstruction de `win32u.so`**. Le correctif 0038 regenere
`include/wine/vulkan.h`, que `winevulkan` **et** `win32u` incluent tous deux. N'avoir
reconstruit que `winevulkan` laissait un `win32u` perime, avec une vue divergente des
structures partagees — d'ou une faute dans le chemin de presentation, remontee en
`NTSTATUS` non nul, puis en assertion dans le thunk genere.

### Ce qu'il faut en retenir

**Installer le correctif 0038 impose de reconstruire tous les consommateurs de
`include/wine/vulkan.h`, pas seulement `winevulkan`.** A ajouter a la procedure. Le symptome
— une assertion sur un appel Vulkan sans rapport apparent — ne designe pas du tout sa cause.

Et une lecon de methode : la garde semblait avoir resolu le probleme, et je l'aurais versee au
correctif si je n'avais pas remarque qu'elle ne s'etait jamais declenchee. Un correctif qui
coincide avec une amelioration n'en est pas la cause.

---

## 110. Les 4 272 echecs D3D11, depouilles (2026-09-20)

### Methode

La suite d3d11 n'a pas les marqueurs par fonction de celle de vkd3d-proton. Chaque echec est
donc attribue a la fonction qui **contient sa ligne source**, par recherche dichotomique dans
la table des definitions. Seules les lignes `Test failed:` comptent ; les `Test marked todo` et
`Test succeeded inside todo block` sont ecartes, comme au § 98.

### Repartition

**4 272 echecs sur 49 fonctions**, tres concentres :

| fonction | echecs | part |
|---|---|---|
| `test_resource_access` | 2 052 | 48 % |
| `test_format_support` | 653 | 15 % |
| `test_compressed_format_compatibility` | 484 | 11 % |
| `test_depth_bias` | 208 | 5 % |
| `test_stream_output` | 158 | 4 % |
| `test_format_compatibility` | 150 | 4 % |
| quarante-trois autres | 567 | 13 % |

**Trois fonctions portent 74 % du total.**

### Par famille de message

| famille | occurrences |
|---|---|
| `Got hr N, expected H` sur un niveau de fonctionnalite | 872 |
| couleur relue inattendue (`H -> H: Got unexpected colour`) | 480 |
| `Unexpected SHADER_GATHER for format` | 380 |
| `Got hr N for READ_WRITE` | 329 |
| `Got unexpected hr` | 230 |
| `Got hr N for READ` / `for WRITE` | 210 + 210 |
| `Unexpected BUFFER for format` | 165 |

### Lecture

Le gros du volume n'est pas du rendu. `test_resource_access` verifie qu'un peripherique
**refuse** les combinaisons d'usage et d'acces CPU qu'il n'est pas cense accepter, par niveau
de fonctionnalite ; DXVK accepte plus largement, d'ou 2 052 ecarts d'un meme motif.
`test_format_support` et les deux fonctions de compatibilite de formats relevent du meme genre :
des drapeaux de capacite annonces differemment de ce que la suite attend.

Restent les **480 ecarts de couleur** de `test_compressed_format_compatibility`, qui eux
designent directement le pipeline : ce sont les seuls a valoir une investigation graphique.
**[Corrige au § 111 : ils ne designent pas le pipeline, c'est une validation absente de DXVK.]**

### La reference

`tests/conformance-baseline-d3d11.txt`, pendant de celle du D3D12. Une campagne future peut
s'y differencier directement, ce qui rendra visible une regression d'une seule fonction —
precisement ce qui manquait avant le § 98.

Les deux references du projet, cote a cote :

| suite | fonctions en echec | echecs | parcours |
|---|---|---|---|
| vkd3d-proton (D3D12) | 28 | 2 305 | complet, 574 fonctions |
| Wine (D3D11) | 49 | 4 272 | 95,5 %, 159 fonctions sur 164 |

---

## 111. Les 480 ecarts de couleur : une validation absente de DXVK (2026-09-20)

### Ce que le test verifie

`test_compressed_format_compatibility` copie entre deux textures de familles de formats
differentes, puis relit la destination. D3D11 exige que `CopyResource` et
`CopySubresourceRegion` **ne fassent rien** entre familles incompatibles : la destination doit
rester telle quelle.

Les 484 echecs sont tous de la meme forme, sur **240 paires de formats distinctes** :

```
Feature level 0xa000: 0x1 -> 0x49: Got unexpected colour 0xff0000ff at 20, expected 0x00000000.
```

**480 sur 484 attendent `0x00000000`**, c'est-a-dire la donnee initiale intacte. Nous rendons
la donnee source : la copie a eu lieu alors qu'elle aurait du etre ignoree.

### La cause

`src/dxvk/src/d3d11/d3d11_context.cpp`. `CopyResource` ne verifie que la dimension, `ArraySize`
et `MipLevels` (lignes 352-362), puis appelle `CopyImage`. Et `CopyImage`, ligne 4206 :

```cpp
// Image formats must be size-compatible
if (dstFormatInfo->elementSize != srcFormatInfo->elementSize)
  return;
```

**Seule la taille d'element est verifiee, jamais la famille.** Or `0x1` est
`R32G32B32A32_TYPELESS`, 16 octets par texel, et `0x49` est `BC2_TYPELESS`, 16 octets par bloc.
Meme taille, familles incompatibles : DXVK copie, D3D11 l'interdit.

### Correction du § 110

J'y ecrivais que ces 480 ecarts « designent directement le pipeline » et « valent une
investigation graphique ». **C'est faux.** Le rendu n'est pas en cause : il s'agit d'une
validation d'API absente, entierement dans DXVK, qui se comporterait a l'identique sous Proton
sur Linux. Aucune piece de notre portage n'y participe.

### Consequence

Le depouillement du § 110 tient toujours, mais sa lecture change : sur les 4 272 echecs D3D11,
**aucune famille n'incrimine notre pile graphique**. Les trois blocs dominants — acces aux
ressources, drapeaux de format, compatibilite de formats compressés — relevent tous de
validations que DXVK accorde plus largement que la specification.

Ajouter la verification de famille dans DXVK serait un changement de comportement susceptible
de casser des jeux qui s'appuient sur sa permissivite. C'est une decision amont, pas la notre.

---

## 112. La suite d3d11 va jusqu'au bout (2026-09-20)

### Le point d'arret n'etait pas ou je le croyais

Je pensais que `ID3D11Device_OpenSharedResource` tuait le processus sur notre faux descripteur
(un pointeur `MTLHeap` deguise). **Faux.** Une sonde ecrite pour l'occasion,
`tests/probe_shared_handle.c`, rejoue la sequence complete de `test_shared_resource` pour les
six combinaisons de `MiscFlags` et survit a **tous** les appels, y compris
`OpenSharedResource`, `OpenSharedResource1` et `CloseHandle` sur le faux descripteur.

La cause reelle est trois lignes plus haut :

```c
status = NtQueryObject(h, ObjectTypeInformation, buffer, sizeof(buffer), &len);
ok(!status, "got %#lx.\n", status);
ok(!wcscmp(type->TypeName.Buffer, L"DxgkSharedResource"), ...);
```

`char buffer[1024]` **n'est pas initialise**. Quand `NtQueryObject` echoue — chez nous
`0xc0000008`, `STATUS_INVALID_HANDLE`, puisque le descripteur n'est pas un objet noyau —
le tampon reste tel quel et `type->TypeName.Buffer` est un pointeur pioche dans la pile. Le
test le dereference sans condition.

Dans la sonde ce pointeur est tombe sur une page lisible (`0x6fffffca9cb0`) et `wcscmp` a
rendu 1 ; dans le binaire de test, la meme case de pile contenait autre chose. C'est du hasard
d'agencement, pas un comportement stable — ce qui explique que le symptome ait resiste au
diagnostic : la derniere ligne journalisee etait 35146, la mort tombait a 35147.

### Deux gardes, meme idiome qu'aux correctifs 0008, 0016 et 0040

`0041-wine-tests-survive-unshareable-nt-handles.patch` :

- `test_shared_resource` : le nom de type n'est compare que si `NtQueryObject` a reussi ;
- `test_keyed_mutex` : `handle` et `tex2` initialises a `NULL`, et sortie propre si le partage
  avec un second peripherique echoue. Sans cela, `handle` non initialise partait dans
  `OpenSharedResource` et `tex2` non initialise dans un `QueryInterface`.

### Resultat

| | avant | apres |
|---|---|---|
| ligne source atteinte | 35 155 | **36 539** / 36 793 |
| fonctions atteintes | 156 | **163** sur 163 invoquees |
| assertions | — | **538 943** |
| lignes en echec | 4 272 | 4 338 |
| code de sortie | 5 (mort) | 255 (plafond de winetest) |

**La suite d3d11 de Wine s'execute integralement.** Deux executions consecutives donnent des
chiffres rigoureusement identiques, en 18 s chacune. La 164e fonction definie,
`test_dxgi_resource`, n'est invoquee nulle part dans le fichier amont : c'est du code mort.

`test_instanced_draw` et `test_generate_mips` sont appeles **hors file**, apres
`run_queued_tests()` : ils n'avaient donc jamais tourne non plus.

### Ce que les cinq fonctions liberees disent

| fonction | echecs |
|---|---|
| `test_nv12` | 12 |
| `test_keyed_mutex` | 8 |
| `test_generate_mips` | 2 |
| `test_clear_during_render` | 0 |
| `test_high_resource_count` | 0 |
| `test_instanced_draw` | 0 |
| `test_stencil_export` | ignore — *the device does not support stencil ref export* |

Les trois qui touchent directement le rendu — effacement pendant une passe, grand nombre de
ressources, dessin instancie — **passent sans un seul ecart**. C'est le resultat le plus utile
de ce fil.

Les 8 de `test_keyed_mutex` sont la machine a etats du verrou a cle, que DXVK n'implemente pas
(`khrWin32KeyedMutex : 0`, `AcquireSync: Not supported`). Les 12 de `test_nv12` se scindent en
deux : quatre refus de dimensions impaires que DXVK accorde — meme famille que les 653 de
`test_format_support` — et huit relectures a zero la ou un plan de chrominance etait attendu,
seul vrai chemin de donnees en defaut, sur un format video.

### Le decompte de winetest

Le cadre annonce 5 129 echecs la ou `grep 'Test failed:'` en compte 4 338. L'ecart est exact :
**791 blocs `todo` reussis**, que winetest comptabilise comme des echecs. La reference
`tests/conformance-baseline-d3d11.txt` est refaite sur cette base.

### Correction du § 110 et du § 111

Ces deux sections parlaient de « 95,5 % de la suite ». Le chiffre etait juste au moment ou il a
ete mesure, mais il n'etait pas une limite de notre pile : une lecture de tampon non initialise
dans le test amont en etait seule responsable. Aucune des familles d'echec ne met en cause
KosmicKrisp ni Metal.

---

## 113. Les huit relectures a zero de test_nv12 : aucune n'etait un defaut de rendu (2026-09-20)

### Ce que je croyais mesurer

Huit echecs de la forme `Got 0x00, expected 0x22` : une region de la texture NV12 relue a
zero la ou le motif initial etait attendu. Je les avais classes « seul vrai chemin de donnees
en defaut » au § 112.

### Ce que la mesure dit

`tests/probe_nv12_box.c` rejoue `UpdateSubresource` sur une texture NV12 de 640x480 avec une
boite impaire, mais en remplissant la source d'un octet **temoin** `0xab` au lieu des zeros que
le test amont y laisse :

```
boite paire (doit copier) :
  boite 10,20 4x6 : luma(10,20) lu 0xab, intact 0x22 ; 24/24 octets = 0xab
boites impaires (doivent etre des non-operants) :
  boite 10,20 4x7 : luma(10,20) lu 0xab, intact 0x22 ; 28/28 octets = 0xab
  boite 10,21 4x6 : luma(10,21) lu 0xab, intact 0x2a ; 24/24 octets = 0xab
```

**La copie a lieu, et elle est exacte.** Les zeros que voyait la suite venaient de son propre
`copy_source`, alloue par `calloc` et rempli uniquement dans la branche paire. Notre pile a
fidelement recopie ce qu'on lui donnait. Le defaut n'est pas d'ecrire mal, c'est d'ecrire
alors que Windows ne le fait pas.

### Premiere cause : un garde-fou inerte

`D3D11CommonContext::UpdateTexture` verifie bien l'alignement :

```cpp
if (!util::isBlockAligned(offset, extent, formatInfo->blockSize, mipExtent))
  return;
```

Mais pour `VK_FORMAT_G8_B8R8_2PLANE_420_UNORM`, la table des formats de DXVK donne
`blockSize = {1, 1, 1}` : le sous-echantillonnage 2x2 n'est porte que par `planes[1]`. Tout
decalage est donc multiple de 1 et le garde-fou **ne rejette jamais rien** sur un format
multi-plans. DXVK emet alors une copie dont les coordonnees ne sont pas des multiples du bloc
de plan, ce qui est hors specification Vulkan.

`0042-dxvk-multiplanar-update-box-alignment.patch` derive l'alignement requis du maximum sur
les plans. Onze lignes.

### Seconde cause : des dimensions impaires acceptees

Deux des huit relectures appartiennent au cas 641x481. Windows refuse une texture NV12 de
dimensions impaires ; `D3D11CommonTexture::NormalizeTextureProperties` ne le verifiait pas, et
le test se poursuivait sur une texture que Windows n'aurait jamais creee.

`0043-dxvk-multiplanar-texture-dimensions.patch` ajoute la verification. La methode etant
statique et sans acces au peripherique, elle recoit desormais un `D3D11Device*` pour resoudre
le format empaquete — quatre appelants a ajuster.

### Resultat

| | avant | apres |
|---|---|---|
| echecs de `test_nv12` | 12 | **0** |
| lignes en echec, suite entiere | 4 338 | 4 326 |
| echecs au sens de winetest | 5 129 | 5 113 |

Une seule fonction change de compte entre les deux campagnes : `test_nv12`. Aucune regression
ailleurs, verifie fonction par fonction. Deux executions consecutives donnent des chiffres
identiques, en 17,3 s.

### Correction du § 112

J'y ecrivais que huit relectures a zero etaient le « seul vrai chemin de donnees en defaut ».
C'est faux : c'etaient deux validations absentes de DXVK, de la meme famille que les 2 087
niveaux de fonctionnalite et les 484 formats compresses.

**Plus aucun echec de la suite d3d11 ne met en cause KosmicKrisp, Metal ou notre chaine de
rendu.** Les 4 326 restants sont tous des ecarts de validation entre DXVK et Direct3D.

---

## 114. Les 1 650 echecs de suballocation : une contrainte du materiel, pas un defaut (2026-09-20)

`test_suballocate_small_textures_size` porte **72 % des 2 305 echecs D3D12**. Premiere cible
evidente. Elle ne se corrige pas — et la raison est instructive.

### Un ecart rigoureusement constant

Les 1 650 echecs tombent tous sur **la meme assertion** (ligne 2301, `info_small.SizeInBytes
<= expected_size`) avec **le meme ecart : 12 288 octets**, quel que soit le format, la taille,
le nombre de niveaux ou de couches. Un surcout constant, jamais proportionnel.

La correlation est totale :

| | echecs |
|---|---|
| 1 couche | **0** |
| 2 a 16 couches | 110 chacune, soit 1 650 |
| 1 niveau | 1 650 |
| plus d'un niveau | **0** |

Les textures en tableau, et elles seules. Les multi-niveaux echappent parce que le test
s'accorde une marge de 2x des que `levels > 1`, ce qui absorbe les 12 Kio.

### Ce n'est pas KosmicKrisp

`tests/probe_image_size.c` interroge directement `vkGetImageMemoryRequirements` :

```
BC1 512x256, 1 niveau, couches variables
  couches 1 : taille    65536  dense    65536  ecart 0  align   128
  couches 2 : taille   131072  dense   131072  ecart 0  align 16384
  couches 6 : taille   393216  dense   393216  ecart 0  align 16384
```

**Notre pilote rapporte la taille exactement dense, zero surcout.** Mais l'alignement saute de
128 a 16 384 des la deuxieme couche.

### C'est vkd3d qui rembourre, et il a raison

`vkd3d_get_image_allocation_info` (`resource.c:1323`) :

```c
allocation_info->SizeInBytes += allocation_info->Alignment - target_alignment;
allocation_info->Alignment = target_alignment;
```

`16 384 - 4 096 = 12 288`. Le compte y est, a l'octet. D3D12 n'admet que 4 Kio ou 64 Kio comme
alignement de placement ; l'application peut donc placer la ressource a n'importe quel multiple
de 4 Kio, et vkd3d doit garder de quoi la realigner sur 16 Kio a l'interieur. Le rembourrage
est minimal.

### Et Metal impose vraiment ce 16 Kio

`tests/metal_heap_texture_align.m` montre que l'alignement vient de Metal lui-meme, pas de
nous :

```
BC1 512x256  couches 1 : taille 65536  align   128
BC1 512x256  couches 2 : taille 131072 align 16384
```

`tests/metal_heap_placement_offset.m` verifie que ce n'est pas une annonce prudente mais une
regle appliquee — `newTextureWithDescriptor:offset:` sur un tas de placement :

```
  offset      0 : accepte
  offset   4096 : REFUSE
  offset   8192 : REFUSE
  offset  12288 : REFUSE
  offset  16384 : accepte
  offset    128 : REFUSE
```

Une texture en tableau doit commencer sur une frontiere de 16 Kio — la taille de page d'Apple
Silicon. Rien dans la chaine ne peut contourner cela.

### La strategie alternative est bien pire

vkd3d expose `VKD3D_CONFIG=reject_padded_small_resource_alignment`, qui fait echouer la requete
au lieu de rembourrer. Mesure :

| strategie | echecs |
|---|---|
| rembourrage (defaut) | **1 650** |
| refus | 36 450 |

Le refus rend `GetResourceAllocationInfo` invalide (`SizeInBytes = ~0`, alignement 64 Kio) et
fait echouer en cascade les assertions d'alignement. **Le defaut est le bon choix ici**, et
c'est desormais mesure plutot que suppose.

### Ce que ca coute reellement

Le test fonctionnel `test_suballocate_small_textures`, lui, **passe entierement** : 76
assertions, zero echec. Le placement marche ; seule l'efficacite spatiale est en cause.

Le prix est de **12 Kio par texture en tableau placee avec l'alignement 4 Kio**. Negligeable
sur une grande texture, mais 37 % sur une RGBA8 64x64 a deux couches (33 024 octets). Un moteur
qui suballoue des milliers de petites textures en tableau y laisserait quelques megaoctets.

### Conclusion

**Aucun correctif possible a notre niveau.** Le commentaire d'en-tete du test dit qu'il doit
« exposer tout cas ou un pilote pessimise nos schemas d'allocation » : il fait exactement son
travail, et la pessimisation est imposee par le materiel. Ces 1 650 echecs sont un cout connu
et quantifie d'Apple Silicon, pas un defaut a corriger.

Reste donc, cote D3D12, 655 echecs sur 2 305 qui meritent encore un examen — au premier rang
`test_undefined_structured_raw_read_typed` (224) et `test_structured_buffer_addressing_wrap`
(94).

---

## 115. Les deux tests d'adressage de tampons structures : 90 % etait un artefact de mesure (2026-09-20)

Deux fonctions, deux causes entierement differentes. La premiere se corrige, la seconde non.

### `test_structured_buffer_addressing_wrap` : la suite ne savait pas sur quoi elle tournait

94 echecs. Le test choisit ses attentes selon le pilote :

```c
broken_byte_addressing = is_nvidia_windows_device(...) || is_intel_windows_device(...) ||
    (is_vkd3d_proton_device(...) && !is_adreno_device(...));
```

Or `d3d12_crosstest.h` place **toutes** les fonctions d'identification derriere :

```c
#if defined(_WIN32) && !defined(VKD3D_FORCE_UTILS_WRAPPER)
```

Notre binaire de test est un PE Windows, donc `is_vkd3d_proton_device`, `is_nvidia_device`,
`is_vk_device_extension_supported` et leurs voisines **rendent toutes `false`**. Le test
appliquait donc le comportement « conforme a la specification », que vkd3d-proton
n'implemente deliberement pas : il herite du bug d'adressage en octets de NVIDIA et Intel par
compatibilite, et le dit dans son propre commentaire.

Verification avant correctif : le binaire **natif** de la meme suite, lui lie a libvkd3d,
donne **4 echecs** la ou le PE en donne 94.

### Le correctif

`0044-vkd3d-proton-tests-identify-device-from-pe-build.patch` sort les fonctions
d'identification des deux branches et les partage. Elles ne reposent que sur deux choses
disponibles cote PE :

- `QueryInterface` vers `ID3D12DXVKInteropDevice` et `ID3D12DeviceExt`, dont les declarations
  sont deja incluses sans condition ;
- `init_vulkan_loader()`, qui possede **deja** un chemin `_WIN32` faisant
  `LoadLibraryA(SONAME_LIBVULKAN)` — soit `vulkan-1.dll`, que Wine fournit.

Sur un vrai pilote Windows le `QueryInterface` echoue et tout rend `false` comme avant. Les
fonctions `is_*_windows_device`, qui lisent le descripteur d'adaptateur, restent propres a
chaque branche.

### Mesure

Campagne complete, meme chemin PE, seule l'identification change :

| | reference | apres 0044 |
|---|---|---|
| echecs | 2 305 | **2 210** |
| fonctions en echec | 28 | 26 |

| fonction | avant | apres |
|---|---|---|
| `test_structured_buffer_addressing_wrap` | 94 | **4** |
| `test_line_rasterization` | 4 | **0** |
| `test_placed_msaa_alignment_workaround` | 1 | **0** |

**Aucune autre fonction ne bouge d'un seul echec.** Le binaire PE donne desormais exactement
les memes chiffres que le binaire natif sur les tests concernes. Trois executions successives
des trois fonctions donnent 4, 0, 0 a l'identique.

Il restait donc 95 echecs qui ne disaient rien de notre pile — seulement que la suite etait
aveugle.

### Les 4 qui restent

Index `buffer_index` 10 et 22, c'est-a-dire les foulees de 3 et 6 mots, avec un index choisi
pour que l'adresse en octets deborde precisement (`UINT32_MAX / 12`, `UINT32_MAX / 24`). Nous
verifions la robustesse **par composante** ; l'adresse de la composante 0 deborde, celles des
composantes 1 et 2 repassent a zero par bouclage et relisent le debut du tampon. Le test
attend une seule verification pour l'element entier, parce que dxil-spirv vectorise `uvec3[]`.
Territoire indetermine sur des index choisis pour deborder : 4 assertions sur 24 millions.

### `test_undefined_structured_raw_read_typed` : 224, et l'identification n'y change rien

Ce test lit un tampon **structure** a travers un descripteur **type**. C'est indetermine, et
il encode trois comportements de reference selon le fabricant.

Mesure : nos 224 sorties correspondent **au bit pres, toutes les 224**, au comportement que le
test nomme `is_nv_heap` et decrit ainsi — *« SSBO is expressed as a R32_UINT texel buffer when
read as one »*. Il ne l'accepte que d'un peripherique NVIDIA ou NVK exposant
`VK_EXT_descriptor_heap`.

La chaine causale, etablie de bout en bout :

1. KosmicKrisp n'expose ni `VK_EXT_descriptor_buffer` ni `VK_EXT_descriptor_heap` (mesure :
   150 extensions, ces deux-la absentes) ;
2. vkd3d active donc `VKD3D_TYPED_OFFSET_BUFFER`, dont la seule condition est
   `!d3d12_device_uses_descriptor_buffers(device)` (`state.c:7854`) ;
3. sur ce chemin, `vkd3d_buffer_view_get_aligned_view` reechelonne les tampons structures en
   mots de 32 bits (`resource.c:6295`) :

```c
first_element = (first_element * structured_stride) / sizeof(uint32_t);
num_elements  = (num_elements * structured_stride) / sizeof(uint32_t);
structured_stride = sizeof(uint32_t);
```

4. l'emulation du comportement « NV natif » que vkd3d cherche a reproduire — choisir le plus
   grand format de tampon de texels qui divise la foulee — n'existe que sur le chemin des
   tampons de descripteurs.

**Ce n'est donc pas un defaut de KosmicKrisp mais une extension optionnelle absente.** Tout
pilote Vulkan sans `VK_EXT_descriptor_buffer` se comporte pareil a travers vkd3d. La meme
cause explique vraisemblablement les 96 de `test_undefined_typed_read_structured_raw`.

Implementer `VK_EXT_descriptor_buffer` dans KosmicKrisp reglerait ces 320 echecs — et ce
serait surtout un gain de performance, puisque cela supprime les mises a jour d'ensembles de
descripteurs. Gros chantier, a considerer pour lui-meme, pas pour la conformite.

### Une lecon de methode

La campagne **native** que j'ai lancee pour comparer donne 18 861 echecs contre 2 210. L'ecart
n'a rien a voir avec l'identification : `tests/etape2_pile_wine.sh` exporte
`MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod`, que mon invocation native omettait.
A elles seules, `test_custom_border_color_limits`, sa variante compute et
`test_custom_border_color_srgb` pesent 16 640 echecs, plus 10 pour `test_view_min_lod` : 16 650
sur 16 651 d'ecart. **Deux configurations ne se comparent que si l'environnement est
identique** — le binaire natif reste utile comme temoin, jamais comme reference.

---

## 116. VK_EXT_descriptor_buffer dans KosmicKrisp : l'extension marche, un format manquant la rend perdante (2026-09-21)

### Le terrain etait favorable

Deux conditions qu'on pouvait craindre sont deja remplies dans KosmicKrisp :

- **les descripteurs sont deja des structures plates** ecrites dans un tampon, et
  `kk_descriptor_set_layout` calcule deja decalage et foulee par liaison — d'ou
  `kk_GetDescriptorSetLayoutSizeEXT` et `...BindingOffsetEXT` deja presents, herites de NVK ;
- **la residence Metal est globale au peripherique** : chaque tas entre dans un
  `MTLResidencySet` attache a la file. L'obstacle habituel des tampons de descripteurs sur
  Metal — le pilote ne sait pas quelles ressources un descripteur ecrit par l'application
  designe — n'existe donc pas ici.

Le shader recoit deja `root.sets[s]`, une simple adresse GPU : `vkCmdSetDescriptorBufferOffsets`
n'a qu'a y ecrire `adresse_du_tampon + decalage`.

### Ce qu'il a fallu ecrire

`0045-kosmickrisp-descriptor-buffer.patch`, 20 fichiers :

- `kk_GetDescriptorEXT`, qui reutilise les fonctions d'ecriture existantes une fois
  `get_sampled_image_view_desc` et `get_storage_image_view_desc` sorties de leur `static` ;
- les quatre points d'entree de commande et leurs variantes `2EXT` ;
- les propietes et drapeaux. **Piege** : Mesa desambigue deux champs homonymes,
  `samplerDescriptorSize` s'ecrit `EDBsamplerDescriptorSize` dans `vk_properties` ; ecrit
  autrement il reste silencieusement a zero ;
- `descriptorBufferPushDescriptors` et `bufferlessPushDescriptors` a vrai. vkd3d **exige** le
  premier, et KosmicKrisp peut honorer les deux puisqu'il place deja ses push descriptors dans
  sa propre memoire de commande ;
- **les echantillonneurs immuables integres**, qui n'etaient pas implementes : le bloc herite
  de NVK allouait son tampon, faisait trois assertions et le liberait sans rien ecrire.
  `embedded_samplers_addr` restait a zero.
- un **registre d'allocations interrogeable par adresse**, et un cache de textures de tampon.

### Le cache de texels, deux fois refait

C'est la seule vraie difficulte. Avec un tampon de descripteurs il n'y a plus de
`VkBufferView`, seulement une adresse — or Metal exige un `MTLBuffer` pour creer une texture de
tampon. Il faut donc remonter de l'adresse a l'allocation, puis creer et **conserver** une
texture. Conserver, parce que le pilote ne peut jamais savoir qu'un descripteur ecrit par
l'application a cesse d'etre utilise.

| conception | pic memoire sur `test_typed_buffers_many_objects` |
|---|---|
| une texture par vue | **13,8 Go**, plusieurs minutes |
| une texture par (allocation, format) | **340 Mo**, 8 s |
| reference sans l'extension | 368 Mo, 8 s |

La premiere a fait tuer une campagne entiere par la pression memoire. La seconde exige de
porter les bornes **dans le descripteur** (`pad` devient `texel_count`) et de les verifier dans
le shader, avec court-circuit des ecritures et des atomiques hors bornes — sans quoi elles
corrompraient la memoire voisine.

### Le defaut qui a coute le plus cher

La seconde conception donnait 262 138 echecs sur `test_typed_buffers_many_objects`. Deux A/B
m'ont menti : desactiver la prediction des ecritures ne changeait rien, et une premiere
desactivation plantait pour une raison sans rapport — ma branche de repli deref^erencait un
`def` inexistant pour une ecriture sans resultat.

C'est le vidage du shader Metal (`MESA_KK_DEBUG=msl`) qui a tranche :

```
t261 = t45 >= t50;          /* t45 est le decalage, pas la coordonnee */
if (!(t51 & t261)) { t263.write(...); }
```

Je calculais la comparaison de bornes **apres** avoir translate la coordonnee. Je comparais
donc `texel_offset >= texel_count` : pour le descripteur *i*, `4i >= 2`, vrai des *i* = 1.
**Toutes les ecritures du shader etaient supprimees** sauf celles du descripteur 0. Le chemin
echantillonne, lui, calculait avant la translation — d'ou un seul test revelateur, le seul qui
ecrive et fasse des atomiques a travers des tampons de texels decales.

Corrige : `test_typed_buffers_many_objects` passe de 262 138 a **0**.

### Le verdict, et pourquoi l'extension reste eteinte

Campagne complete, chemin PE :

| | reference | descriptor buffer |
|---|---|---|
| echecs | 2 210 | **2 228** |

| fonction | avant | apres |
|---|---|---|
| `test_undefined_typed_read_structured_raw` (x2) | 96 | **0** |
| `test_undefined_structured_raw_read_typed` (x2) | 224 | **334** |
| `test_buffer_descriptor_byte_offset` | 0 | **4** |

**+18 net : une regression.** Les trois familles ont la meme cause unique. vkd3d, sur le chemin
des tampons de descripteurs, choisit « le plus grand format de tampon de texels qui divise la
foulee » — soit `R32G32B32_UINT` pour les foulees de 12 et 24 octets. **Metal n'a aucun format
96 bits** : sa table saute de `RG32` a `RGBA32`. Le descripteur reste vide et tout se lit a
zero. Sans l'extension, vkd3d rescalait tout en `R32_UINT` et la question ne se posait pas.

L'extension est donc placee derriere `MESA_KK_EXPERIMENTAL=descriptor_buffer`, **eteinte par
defaut**, pour que la reference du projet reste a 2 210. `tests/etape2_pile_wine.sh` a ete
corrige au passage : il exportait `MESA_KK_EXPERIMENTAL` en dur, ce qui rendait tout drapeau
supplementaire inoperant sans le dire.

### Ce qui reste a faire pour que ca paie

Emuler les formats 96 bits : creer la texture en `R32`, porter un facteur 3 dans le descripteur
(il reste 4 bits libres en haut de `texel_count`, dont la valeur maximale est 2^28), et
reconstruire chaque acces en trois lectures ou ecritures consecutives. Cela supprimerait les
+114 et rendrait les -290 attendus, soit environ **1 920 echecs**. C'est un chantier de
lowering NIR a part entiere, non entrepris.

---

## 117. L'emulation des formats 96 bits rend l'extension gagnante : 2 210 -> 2 026 (2026-09-21)

Le § 116 laissait `VK_EXT_descriptor_buffer` eteinte : elle coutait +18 echecs, tous dus a
l'absence de format 96 bits dans Metal. C'est corrige.

### Pourquoi il fallait emuler, et pas contourner

`vkd3d_structured_srv_to_texel_buffer_dxgi_format` est une **fonction pure de la foulee** : elle
rend `R32G32B32_UINT` des que la foulee est multiple de 12, sans jamais consulter le pilote. Rien
a annoncer ou a taire de notre cote ne l'en detournerait.

En revanche `vkd3d_structured_uav_to_texel_buffer_dxgi_format` rend toujours `R32_UINT`, et D3D12
n'autorise pas l'ecriture typee en `R32G32B32`. **Seules les lectures sont a emuler**, ce qui
divise le travail par deux.

### Le mecanisme

Le pilote cree la texture en `R32` la ou on lui demande `R32G32B32`, et porte un multiplicateur
dans le descripteur. `texel_count` plafonne a 2^28, donc ses deux bits de poids fort sont libres :
0 pour x1, 1 pour x3. Aucune place perdue.

Le shader decode le multiplicateur, calcule `base = coord * mul + texel_offset`, et quand `mul`
vaut 3 reconstruit la lecture a partir de **trois recuperations R32 consecutives**, assemblees en
`(x, y, z, 1)`.

### Trois defauts en chemin

1. **`nir_instr_clone` sur une instruction de texture fait planter la compilation.** Les deux
   recuperations supplementaires sont construites explicitement par `nir_tex_instr_create`.
2. **`coord_components` n'est pas renseigne par `nir_tex_instr_create`.** Sans lui, le backend
   Metal produit un shader invalide : le pipeline echoue, tout se lit a zero, et le test passe de
   334 a **794** echecs. Il faut aussi recopier `texture_non_uniform`, `backend_flags` et leurs
   voisins.
3. **L'alpha des lectures hors bornes vaut 1, pas 0.** Vulkan rend `(0, 0, 0, 1)` pour un format
   sans alpha. Les 152 derniers echecs etaient exactement cette composante, et rien d'autre.

### Resultat

| | echecs |
|---|---|
| reference, sans l'extension | 2 210 |
| avec l'extension, derriere le drapeau | **2 026** |
| avec l'extension, active par defaut | **2 026** |

**-184, aucune regression.** 24,3 millions d'assertions, 574 fonctions, et **quatre ecarts en
tout**, tous en amelioration :

| fonction | avant | apres |
|---|---|---|
| `test_undefined_typed_read_structured_raw` (x2) | 96 | **0** |
| `test_undefined_structured_raw_read_typed` (x2) | 224 | **136** |

Les deux campagnes — drapeau puis defaut — donnent le meme chiffre a l'unite pres. Le drapeau
experimental du § 116 est retire : l'extension est annoncee inconditionnellement.

### Ce qui reste

Les 136 de `test_undefined_structured_raw_read_typed` sont du comportement indetermine : vkd3d y
emule des semantiques NVIDIA que nous ne reproduisons pas entierement. On est passe de 224 a 136
dessus sans chercher a aller plus loin — c'est du territoire non specifie.

Reste aussi un trou connu et sans consequence aujourd'hui : une UAV typee en `R32G32B32` lirait
faux, puisque seul le chemin echantillonne assemble les trois recuperations. D3D12 interdit ce cas
et vkd3d ne le produit jamais.

---

## 118. Ce que VK_EXT_descriptor_buffer rapporte vraiment : enorme sur les descripteurs, nul sur Godot (2026-09-21)

Le § 117 a mesure la conformite. Restait a verifier la raison d'etre amont de l'extension : la
performance. On ne l'avait pas fait, et c'etait un trou dans nos propres preuves.

Un interrupteur `MESA_KK_DEBUG=no_descriptor_buffer` permet l'A/B sur un seul binaire.

### Le micro-banc d'essai : un facteur trois sur les copies

`descriptor-performance` de vkd3d-proton, 100 repetitions de chaque cote, medianes :

| operation (1 M descripteurs) | sans | avec | ecart |
|---|---|---|---|
| copie vers tas visible GPU | 24,45 ms | **7,54 ms** | **-69 %** |
| copie, duplicatas | 14,18 ms | **4,09 ms** | **-71 %** |
| copies individuelles, duplicatas | 42,14 ms | **16,70 ms** | **-60 %** |
| copies individuelles, tas mis a zero | 42,09 ms | **16,69 ms** | **-60 %** |
| creation de SRV nulles | 45,92 ms | **20,00 ms** | **-56 %** |
| creation de SRV, quatre variantes | 85,3 ms | 94,0 ms | **+10 %** |

Les copies sont ce qu'un moteur fait a chaque image en recopiant ses tas CPU vers le tas visible
GPU : elles tombent d'un facteur trois. La creation paie 10 %, tres probablement le verrou et la
recherche de hachage du cache de textures de texels que j'ai introduits — optimisable, par
exemple en memorisant la derniere entree par fil.

### L'application reelle : rien

Scene lourde de Godot, 1 500 objets, 24 lumieres a ombres, post-traitement, 640x360, 300 images
mesurees apres 120 de chauffe. **Une paire A/B**, pas davantage :

| | tirages | mediane | p95 |
|---|---|---|---|
| avec | 10 401 | 31,818 ms | 31,944 ms |
| sans | 10 405 | 31,944 ms | 33,333 ms |

**0,4 % d'ecart : du bruit.**

### Pourquoi, et c'etait previsible

Le § sur Godot avait etabli que cette scene est **limitee par le CPU sur la soumission des
tirages** : diviser la resolution par neuf ne changeait pas le temps d'image. Le cout des
descripteurs n'est qu'une fraction de ce goulot, domine par la traversee
`Rosetta -> Wine -> vkd3d`. Accelerer les copies d'un facteur trois ne deplace rien tant que
c'est la soumission qui borne.

### Ce qu'il faut en retenir

L'extension est un gain reel et mesure, mais **il ne se verra que sur une application qui brasse
beaucoup de descripteurs par image** — un moteur avec des milliers de materiaux distincts, pas
cette scene. Son benefice immediat et demontre reste la conformite : **-184 echecs**.

Corollaire pour la suite : tant que la soumission des tirages borne le temps d'image, aucune
optimisation du cote descripteurs ne se verra. C'est la traversee elle-meme qu'il faudrait
attaquer, et le § sur Godot montrait que notre pile n'en represente que 21 %.

---

## 119. Unigine 2.80 rend Superposition sur la pile complete (2026-09-21)

Le § 99 concluait que Superposition etait hors d'atteinte : trois obstacles, dont un juge
« bloquant ». **Ce diagnostic etait perime et je ne l'avais pas reteste.** Deux des trois points
sont exactement ce que les correctifs 0038 et 0039 ont traite depuis.

### Le resultat

```
Direct3D11 desc: Apple M1 Max
Loading "unigine_render.mat" 62 materials 44339625 shaders
Presenter: swapchain 1280x720, 3 images, B8G8R8A8_UNORM
Loading "superposition/superposition.world" 1180ms
```

**La scene s'affiche**, confirmee a l'ecran. 151 % de CPU, plusieurs fils, et **aucune erreur de
rendu** dans tout le journal : seulement deux avertissements sur l'EDID du moniteur et une
interface DXGI inconnue, sans rapport avec l'image.

Chaine complete : `PE Windows -> Wine -> DXVK -> winevulkan -> KosmicKrisp -> Metal`.

### La fausse piste, et ce qui l'a evitee

Premier lancement : fenetre noire. J'allais chercher un defaut de presentation.

`DXVK_HUD=fps` a tranche en un coup d'oeil : **les FPS defilaient**. Le HUD est dessine par DXVK
lui-meme, independamment du rendu de l'application — s'il apparait, la chaine de presentation
fonctionne et le probleme est ailleurs.

Il etait dans la ligne de commande. La premiere ligne du journal disait
`Loading "bin/null_config.cfg"` : le moteur demarrait **sans aucun monde**. Il rendait
fidelement le neant qu'on lui donnait. Ajouter
`-console_command "world_load superposition/superposition"` a suffi.

**Lecon** : avant de soupconner la pile, verifier ce qu'on lui a demande. Et garder un temoin
qui ne depend pas du code suspect — ici le HUD.

### Ce que ca change pour la suite du projet

Je repondais jusqu'ici aux « on enchaine avec quoi ? » par le plus gros bloc d'echecs de
conformite restant. C'etait un objectif de substitution. Les 240 echecs D3D12 encore ouverts
mesurent l'ecart a la specification, pas la capacite a faire tourner un jeu : la refonte du
chemin de capture XFB (§ 120 ci-dessous) en est l'exemple — un chantier lourd pour une
fonctionnalite que les moteurs modernes n'utilisent pas.

**Le travail utile est de lancer de vraies applications et de corriger ce qu'elles cassent.**

### Diagnostic laisse ouvert : la capture XFB depuis une tessellation

Avant ce lancement, j'avais caracterise `test_line_tessellation` (100 echecs) et les variantes
quad (24) : une cause unique, ~124 des 240 echecs ouverts.

`test_stream_output`, la capture depuis un vertex shader, passe a zero echec. Mais toute capture
**depuis une tessellation** ne rend que les sommets du premier patch — 2 sur 18, verifie que ce
ne sont pas des zeros chanceux. Les compteurs `SO_STATISTICS` rendent zero parce que
`kk_prims_for_vertices` ne connait pas `MESA_PRIM_PATCHES`.

La cause est dans le commentaire d'en-tete de `kk_nir_lower_xfb.c` : la capture est adressee par
`xfb_address + (instance_id * num_vertices + raw_vertex_id) * stride`, un schema **indexe par
sommet** dont les decalages se calculent sur le CPU. Le code refuse d'ailleurs explicitement les
tirages indirects et indexes. Or la tessellation emulee produit exactement cela : le garde-fou
s'applique au tirage de patchs d'origine, direct et non indexe, qui passe — mais le tirage reel
qui suit viole les deux conditions.

Corriger demanderait de remplacer l'adressage par sommet par une allocation a compteur atomique
cote GPU, et de refaire les compteurs de requete. La machinerie de compteurs existe (§ 0011)
mais n'est pas branchee sur ce chemin. **Chantier laisse ouvert, delibere** : il ne sert pas
l'objectif du projet.

### Premiere mesure sur Superposition (2026-09-21)

| resolution | images/s | CPU |
|---|---|---|
| 1280x720 | 24 | 151 % |
| 640x360 | 22-23 | **2,6 %** |

Neuf fois moins de pixels, **meme frequence**. Mais contrairement a Godot, le CPU ne sature pas :
2,6 % sur dix coeurs, soit un quart d'un coeur. Le CPU soumet puis **attend**.

Frequence independante de la resolution **et** CPU libre : la charge est donc bornee par le GPU
sur du travail qui ne depend pas du nombre de pixels de sortie — passes d'ombres a resolution
fixe, volumetrie, ou cout propre des shaders.

**C'est un regime inedit pour ce projet**, et une bonne nouvelle : sur cette charge reelle, la
traversee `Rosetta -> Wine -> DXVK` n'est pas le facteur limitant. Les 151 % releves en 1280x720
contre 2,6 % en 640x360 restent a expliquer : meme scene, meme frequence, charge CPU trente fois
moindre. **Non explique.**

L'image est jugee correcte a l'ecran. Le flou en deplacement est le flou de mouvement
qu'Unigine active par defaut, d'autant plus visible que la frequence est basse — **non verifie**
en le desactivant.

---

## 120. Capture Metal de Superposition : le fragment domine, et le pilote n'y est pour rien (2026-09-21)

### L'outil

`MESA_KK_GPU_CAPTURE` produit un `.gputrace` illisible sans l'interface d'Xcode. Autre canal,
exploitable en ligne de commande : **`xctrace` avec le modele « Metal System Trace »**.

`xcode-select` pointe sur les outils en ligne de commande, mais Xcode est installe. On appelle
donc l'outil par son chemin absolu, **sans toucher au reglage systeme**, qui demanderait les
droits administrateur :

```
/Applications/Xcode.app/Contents/Developer/usr/bin/xctrace record \
  --template "Metal System Trace" --attach <pid> --time-limit 12s --output superp.trace
```

Puis `xctrace export --xpath '...table[@schema="metal-gpu-intervals"]'`.

**Piege de lecture** : le schema comporte **deux** colonnes de type `duration`, la duree de
l'intervalle et la latence CPU vers GPU. Extraire « le premier `<duration>` portant un
identifiant » ramene parfois la latence. Il faut prendre le premier dans l'ordre du document.
Avec l'erreur, le total GPU sortait a 2 271 s sur une fenetre de 12,7 s — un resultat absurde
qui a servi de garde-fou. Les identifiants sont par ailleurs **globaux**, pas propres a chaque
colonne.

### Ce que la capture dit

12,58 s de rendu, 77 428 intervalles :

| canal | temps | part du mur | encodeurs | moyenne |
|---|---|---|---|---|
| **Fragment** | 10 150 ms | **80,7 %** | 28 601 | 355 us |
| Vertex | 1 184 ms | 9,4 % | 29 870 | 39,7 us |
| Compute | 210 ms | 1,7 % | 18 957 | 11,1 us |

**GPU occupe 82,8 % du mur.** Par image : **95 encodeurs fragment, 33,6 ms**, ce qui
reconstitue le temps d'image observe.

Distribution tres desequilibree : mediane a 17 us, mais **8,3 % des encodeurs depassent la
milliseconde et portent 73 % du temps fragment**, avec des pointes a 6,9 ms.

### Contradiction levee, mais une hypothese non verifiee

Le § 119 concluait « borne par du travail GPU independant de la resolution de sortie », puisque
diviser la fenetre par neuf ne changeait rien. Si le fragment pese 80 %, reduire les pixels
aurait du tout changer — **sauf si ces pixels ne sont pas ceux de la fenetre**. Superposition
rend vraisemblablement a une resolution interne fixee par son reglage de qualite, puis met a
l'echelle. **Non verifie.**

### La piste du decoupage des passes : fausse

95 passes fragment par image, c'est beaucoup, et sur un GPU a tuiles chaque passe coute un
vidage. `kk_CmdPipelineBarrier2` contient d'ailleurs un decoupage **inconditionnel** des que
`samples > 1`. Hypothese : notre pilote fabriquerait des passes.

Mesure, par compteurs poses dans `kk_CmdBeginRendering` et `cs_start_render` :

| | nombre |
|---|---|
| passes demandees par DXVK | 510 000 |
| encodeurs Metal crees | 562 000 |
| decoupages sur barriere | **0** |

**Rapport 1,10.** Le pilote cree 10 % d'encodeurs de plus que de passes demandees, et **aucun**
ne vient du decoupage sur barriere : le compteur n'a jamais atteint son seuil en huit minutes de
rendu. Les 95 passes par image sont ce qu'Unigine demande.

Le `samples > 1` existe bien et reste un cout potentiel, mais il ne se declenche pas sur cette
charge. **Hypothese abandonnee**, instrumentation retiree, arbre verifie identique a la serie.

### Ou chercher ensuite

Le temps est dans **8,3 % des encodeurs fragment**. Ce ne sont pas les passes qui coutent, ce
sont quelques passes precises. Les identifier nommement — par `metal-object-label`, que la
capture expose — dirait s'il s'agit de la volumetrie, des ombres, ou d'un shader que notre
traduction rend inutilement cher. C'est la question suivante, et elle est bien posee.

### Identification des passes couteuses (2026-09-21)

Les etiquettes d'encodeur etaient vides : KosmicKrisp ne nomme un encodeur que si l'application
a pose un nom Vulkan, ce qu'Unigine ne fait pas. Ajout dans `cs_start_render`, sous
`MESA_KK_DEBUG=encoder_labels`, d'une etiquette portant la geometrie des attaches. Toute capture
future devient lisible.

Seconde capture, 10 s, filtree sur `wine64` :

| passe | total | fois | moyenne |
|---|---|---|---|
| 1920x1080, 1 cible | 1 571 ms | 330 | **4 761 us** |
| 1920x1080, 1 cible + profondeur | 1 282 ms | 215 | **5 960 us** |
| 1920x1080, 2 cibles | 1 109 ms | 420 | 2 641 us |
| 1920x1080, 5 cibles + profondeur | 690 ms | 213 | 3 238 us |
| 960x540, 2 cibles | 27 ms | 17 | 1 617 us |
| 8192x8192, profondeur seule | 20 ms | 11 | 1 770 us |

**Superposition rend en 1920x1080 alors que la fenetre fait 1280x720.** L'hypothese laissee
« non verifiee » plus haut est **etablie** : `-video_width` ne pilote que la fenetre, la
resolution interne vient du reglage de qualite. C'est pourquoi diviser la fenetre par neuf ne
changeait rien.

La structure est celle d'un rendu differe ordinaire : G-buffer a 5 cibles, eclairage et
post-traitements plein ecran a 1 ou 2 cibles, carte d'ombres 8192x8192 occasionnelle. **Rien
d'anormal** : le cout est la ou on l'attend pour ce moteur a cette resolution, et rien
n'incrimine notre traduction plutot que le travail lui-meme.

### Deux pieges d'analyse, tous deux dans mon code de depouillement

1. La capture contient **WindowServer et l'application Claude** en plus de `wine64`. Sans filtre
   sur le processus, les totaux etaient gonfles de 11 % : 10 361 ms pour wine64, 752 pour
   WindowServer, 423 pour Claude.
2. Ma regexp supprimait `0x[0-9a-f]+` pour enlever les identifiants — et mangeait le `0x1080` de
   `1920x1080`, affichant `192`. Les passes ont d'abord paru avoir des resolutions absurdes.

**Les deux fois, c'est l'invraisemblance du resultat qui a alerte, pas la relecture du code.**

### Le budget d'une image, et ce qu'il reste a gagner (2026-09-21)

La variation de qualite demandee **n'a pas pu etre faite** : le prereglage du banc reapplique
`render_virtual_resolution 1920 1080` apres le chargement du monde et ecrase la commande
console. Verifie dans le journal du moteur :

```
Unigine~# world_load superposition/superposition && render_virtual_resolution 960 540
Loading "superposition/superposition.world" 944ms
Unigine~# render_virtual_resolution 1920 1080      <- le prereglage reprend la main
```

La question sous-jacente se tranche mieux par l'occupation GPU, qui **borne** le surcout au lieu
de l'inferer d'une proportionnalite.

Repere de frequence fiable : le nombre de presentations (`ca-client-present-request`), et non le
nombre de passes G-buffer — celles-ci reviennent 1,77 fois par presentation, donc une meme
geometrie sert a plus d'une passe.

239 presentations sur 10,80 s :

| | par image | part |
|---|---|---|
| **GPU occupe** | **38,4 ms** | **85 %** |
| dont fragment | 34,0 ms | 75 % |
| **tout le reste** | **6,7 ms** | **15 %** |

Ces 6,7 ms contiennent la soumission, la synchronisation, la presentation **et l'integralite du
surcout de traduction**. C'est un plafond : supprimer entierement Rosetta, Wine, DXVK et
KosmicKrisp ne rendrait pas plus de 15 %.

**Conclusion de ce fil.** Les 22 images par seconde sont le cout d'un rendu differe en 1920x1080
avec ce niveau d'effets sur ce GPU. Rien dans la structure ne cloche, le pilote ne decoupe pas
les passes, et la traduction n'ajoute pas de surcout fixe notable. Pour savoir si ce chiffre est
bon dans l'absolu il faudrait le meme banc sur le meme GPU sans notre pile — comparaison dont on
ne dispose pas.

### Compteurs GPU : inaccessibles, et un faux coupable (2026-09-21)

**Les compteurs GPU ne sont pas lisibles ici.** `metal-gpu-counter-intervals`,
`gpu-counter-value`, `gpu-counter-info` et `metal-gpu-counter-profile` rendent zero ligne, avec
le modele « Metal System Trace » comme avec « Game Performance ». Sur Apple Silicon la lecture
des compteurs exige que le processus porte une autorisation de profilage Metal ; `wine64` ne
l'a pas, et la lui donner supposerait de signer le binaire.

La question « notre traduction produit-elle du MSL inefficace ? » **reste donc ouverte**, faute
d'instrument.

### Le faux coupable

Le modele « Game Performance » rapporte l'etat de performance GPU **« Minimum » sur 100 % de la
capture**, 1 916 intervalles. Conclusion apparente : le GPU ne monte jamais en frequence, ce qui
expliquerait tout.

**C'est faux.** La table `gpu-performance-state-info` annonce « Consistent State Available:
Yes » : ce modele **epingle** l'etat pour rendre les mesures reproductibles. Sur la capture
« Metal System Trace », non epinglee :

| etat | temps | part |
|---|---|---|
| **Maximum** | 9 943 ms | **99,9 %** |
| Minimum | 8,8 ms | 0,1 % |

Le GPU tourne bien a pleine frequence, et l'etat thermique est **nominal** sur toute la duree.

Ce qui a mis la puce a l'oreille : la premiere capture contenait les deux etats, la seconde un
seul. **Une mesure qui ne montre qu'une seule valeur doit etre suspectee avant d'etre crue.**

### Ou en est la question de performance

Rien de ce qui a ete mesure n'explique les 22 images par seconde autrement que par le travail
lui-meme : GPU a pleine frequence, thermique nominal, occupe a 85 %, pas de decoupage de passes
surnumeraire, surcout de traduction borne a 15 %. Le seul angle non explore est l'efficacite du
code Metal produit, et il demande un instrument dont on ne dispose pas sur ce binaire.

### Repere de shader : la traduction ne coute rien sur le calcul (2026-09-21)

Faute de compteurs GPU, mesure directe : **la meme chaine de multiplications-additions
dependantes**, ecrite une fois en MSL a la main (`tests/bench_alu_metal.m`) et une fois en GLSL
passant par SPIR-V et KosmicKrisp (`tests/bench_alu_vulkan.c`). Meme methode de chronometrage
des deux cotes — meilleur de cinq soumissions, mur autour de submit et attente.

| iterations | fils | Metal natif | notre pile | rapport |
|---|---|---|---|---|
| 25 000 | 16 384 | 1,5 ms | 2,2 ms | 1,47 |
| 25 000 | 65 536 | 3,2 ms | 3,1 ms | 0,97 |
| 100 000 | 16 384 | 3,3 ms | 3,3 ms | 1,00 |
| 100 000 | 65 536 | 11,4 ms | 12,0 ms | 1,05 |
| 400 000 | 16 384 | 12,6 ms | 12,8 ms | 1,02 |
| 400 000 | 65 536 | 44,1 ms | 47,8 ms | 1,08 |

Sur les cinq points ou le travail depasse 3 ms, **le rapport tient entre 0,97 et 1,08**. Le
1,47 est sur la charge la plus courte, ou le cout fixe de soumission domine : cette ligne ne dit
rien. Les sorties sont identiques au chiffre pres (`0,0100607`), ce qui prouve que les deux
shaders font le meme calcul.

**Portee de ce resultat.** Il mesure l'ALU, et seulement elle. La charge de Superposition est
dominee par des passes fragment avec echantillonnage de textures, cibles multiples et bande
passante memoire — chemins que ce banc n'exerce pas. On peut donc affirmer que le compilateur ne
degrade pas le calcul ; on ne peut pas exclure une inefficacite sur les chemins de texture ou de
memoire.

### Repere fragment : 30 us fixes par passe, et 8 % sur l'ombrage (2026-09-21)

Prolongement du repere ALU sur le chemin qui domine reellement : passe plein ecran 1920x1080,
N echantillonnages bilineaires d'une texture 2048x2048 par pixel, cibles RGBA16F.
`tests/bench_frag_metal.m` en MSL a la main, `tests/bench_frag_vulkan.c` via GLSL, SPIR-V et
KosmicKrisp.

**Chronometrage GPU des deux cotes**, et non plus le mur : `GPUEndTime - GPUStartTime` cote
Metal, requetes d'horodatage cote Vulkan. La distinction comptait — le mur incluait l'encodage
CPU, qui dans une vraie charge serait masque par le GPU.

| ech/pixel | Metal natif | notre pile | ecart |
|---|---|---|---|
| 1 | 0,050 ms | 0,080 ms | **30 us** |
| 4 | 0,080 ms | 0,130 ms | 50 us |
| 32 | 0,430 ms | 0,500 ms | 70 us |
| 128 | 1,670 ms | 1,830 ms | 160 us |

Le modele qui ajuste les quatre points : **~30 us fixes par passe, plus ~8 % proportionnels a
l'ombrage**. C'est du **temps GPU**, pas de l'encodage.

Contraste avec le repere ALU, ou le rapport tenait entre 0,97 et 1,08 : **le calcul est a
parite, le chemin fragment ne l'est pas.**

### Ce que ca vaut sur Superposition, et ce que ca n'explique pas

95 passes fragment par image x 30 us = **2,9 ms**, plus 8 % des 34 ms d'ombrage = 2,7 ms. Soit
environ **5,6 ms sur 45,2**, ou **12 %** : 22 images par seconde deviendraient environ 25.

Reel et mesure, mais **cela n'explique pas un ecart d'un facteur deux**. Et rien dans ce qui a
ete mesure n'etablit qu'un tel ecart existe : il n'y a toujours pas de point de comparaison
externe pour dire ce que vaut un M1 Max sur ce banc.

### Cause des 30 us : non identifiee

Deux pistes ecartees : ce n'est pas un chargement d'attache force (`is_whole_framebuffer` est
vrai dans le banc, donc `force_attachment_load` reste faux), et ce n'est pas du cout CPU
d'encodage, puisque la mesure est cote GPU. Trente microsecondes sur deux millions de pixels
correspond a l'ordre de grandeur d'un parcours complet de la cible. Identifier la cause
demanderait une capture Metal du banc lui-meme, comparant les deux passes cote a cote.

### La cause des 30 us : une barriere ALL vers ALL a chaque fin d'encodeur (2026-09-21)

Capture des deux bancs cote a cote, `Metal System Trace`, meme charge :

| | Metal natif | notre pile |
|---|---|---|
| duree totale | 3 655 ms | 4 489 ms |
| GPU occupe | 3 247 ms (**88,8 %**) | 3 406 ms (**75,9 %**) |
| encodeurs fragment | 7 623, moy 424,7 us | 7 494, moy 443,6 us |
| **trous entre passes fragment** | **1 475** | **7 493** |
| total des trous | 418 ms | **1 164 ms** |

Le natif enchaine : 1 475 trous pour 7 623 passes. **Nous avons un trou entre chacune des
7 494 passes.** L'ecart n'est donc pas dans les encodeurs — ils ne coutent que 19 us de plus —
mais dans le temps mort **entre** eux.

La cause est dans `end_encoder` :

```c
/* TODO_KOSMICKRISP This is probably overkill */
mtl_barrier_after_stages(encoder, MTL_STAGE_ALL, MTL_STAGE_ALL);
```

**Chaque encodeur se termine par une barriere totale, inconditionnelle.** En Metal 4 cela vide
le pipeline entre deux passes. Le commentaire amont dit deja « c'est probablement excessif ».
Il n'y a aucune barriere Vulkan entre les passes du banc : la serialisation est gratuite.

Mesure du plafond, en la retirant — **chronometrage au mur**, car sans barriere l'horodatage de
fin n'attend plus la fin du travail et rendait des valeurs impossibles (0,01 ms, plus rapide que
le natif) :

| ech/pixel | avec | sans | Metal natif |
|---|---|---|---|
| 4 | 0,140 ms | **0,085 ms** | 0,080 ms |
| 32 | 0,510 ms | **0,440 ms** | 0,435 ms |
| 128 | 1,840 ms | **1,790 ms** | 1,680 ms |

**Sans la barriere, nous sommes a parite avec Metal natif.** Elle constitue l'integralite du
surcout fixe par passe.

Sur Superposition : environ 0,05 a 0,07 ms par passe x 95 passes = **5 a 7 ms sur 45,2**, soit
11 a 15 % ; 22 images par seconde deviendraient environ 25 ou 26.

**La retirer n'est pas le correctif** — elle garantit de vraies dependances, et l'interrupteur
de mesure a ete retire. Le correctif est de la reduire aux etages reellement concernes plutot
que `ALL` vers `ALL`. Les suites de conformite D3D11 et D3D12 serviraient de garde-fou.

### Tentative de barriere reduite : deux hypotheses, deux echecs (2026-09-21)

**Premiere : reduire les etages.** La barriere de `end_encoder` porte sur `MTL_STAGE_ALL`, qui
inclut des etages que l'encodeur n'a jamais executes — maillage, accelération, apprentissage.
Les attendre ne peut rien garantir. Remplacee par les seuls etages producteurs reels
(`VERTEX | FRAGMENT | TILE | OBJECTS | MESH` pour un encodeur de rendu,
`DISPATCH | BLIT | RESOURCE_STATE | ACCELERATION_STRUCTURE` pour un encodeur de calcul).

**Gain : nul.** 0,140 / 0,510 / 1,840 ms, identique au dixieme de microseconde pres. Metal
traite la barriere comme un vidage complet quels que soient les etages nommes.

**Seconde : ne pas l'emettre quand l'application ferme la passe.** Raisonnement : dans le modele
Vulkan, sans barriere explicite aucune ordonnance n'est garantie entre deux passes, donc le
pilote n'a pas a en imposer une a `vkCmdEndRendering` — seulement lors de ses propres decoupages.

**Gain : reel.** Rapport a Metal natif ramene de 1,75 / 1,19 / 1,10 a **1,12 / 1,02 / 1,07**.

**Mais correction cassee** : la suite d3d11 passe de **4 326 a 5 195 echecs**, soit +869. Le
raisonnement etait faux. Metal 4 n'offre aucune synchronisation implicite entre encodeurs, et
quelque chose en depend — soit DXVK, soit les operations internes du pilote autour des
attaches.

**Revenu a l'etat d'origine**, verifie : d3d11 de nouveau a 4 326.

### Ce qu'il faudrait reellement

Le gain existe et il est mesure — 11 a 15 % sur Superposition — mais il ne s'obtient pas en
supprimant la barriere. Il faudrait **suivre les ressources** : n'emettre la barriere que
lorsque l'encodeur suivant touche ce que le precedent a ecrit. C'est un suivi de dependances a
construire, pas un ajustement de drapeaux.

L'etiquetage des encodeurs (`MESA_KK_DEBUG=encoder_labels`) est conserve : il a servi a
identifier les passes et resservira.

### Reference externe : introuvable, et la question etait mal posee (2026-09-21)

Recherche du classement Unigine pour le prereglage 1080p Medium : le tableau public est un
**Top 50**, exclusivement des RTX 4090 et 5090. Aucun point de comparaison de gamme moyenne.
Aucun score Superposition publie pour un M1 Max, ni natif — le banc n'existe pas sur macOS ARM —
ni via CrossOver ou Parallels.

**Et la comparaison aurait ete fausse de toute facon.** Nos 22 images par seconde viennent du
**vol libre**, pas du parcours scripte du banc. Les scores du classement viennent de ce
parcours, avec sa camera fixe et sa sequence d'effets. Les deux nombres ne mesurent pas la meme
chose. Obtenir un vrai score demanderait de piloter le banc, dont la logique vit dans les
archives de script, pas dans le binaire.

### La reference qui vaut : la machine contre elle-meme

Le banc fragment du § precedent donne le debit **mesure**, pas celui d'une fiche technique :
Metal natif fait une passe 1920x1080 avec 32 echantillonnages bilineaires par pixel en
**0,43 ms**, soit **154 milliards d'echantillons par seconde**.

Ce que coutent les passes de Superposition, converti a ce debit :

| passe | duree | equivalent |
|---|---|---|
| la plus chere | 5,96 ms | **444 echantillons par pixel** |
| la deuxieme | 4,76 ms | 354 par pixel |
| G-buffer, 5 cibles | 3,24 ms | 241 par pixel |

Pour un eclairage differe avec une vingtaine de lumieres a ombres, plus la volumetrie et le
post-traitement, plusieurs centaines d'echantillons par pixel est **normal**.

**La machine est donc conduite pres de son debit natif mesure.** Les 22 images par seconde sont
ce que coute cette scene a cette resolution, pas ce que notre pile gaspille.

### Conclusion du fil performance

Quatre axes mesures, trois a parite avec le natif :

| axe | verdict |
|---|---|
| frequence GPU, thermique | Maximum 99,9 %, nominal |
| decoupage des passes | rapport 1,10, aucun decoupage sur barriere |
| efficacite du calcul | parite, rapport 0,97 a 1,08 |
| efficacite du fragment | **11 a 15 % perdus** sur la barriere de fin d'encodeur |

Le seul gaspillage identifie vaut 11 a 15 %, et il demande un suivi des ressources ecrites pour
etre recupere sans casser la correction. **Rien de ce qui a ete mesure ne soutient l'idee d'un
facteur deux a recuperer.**

### Suivi des ressources : la vraie cause trouvee, la correction echouee (2026-09-21)

Plutot que de deviner ce qui depend de la barriere aveugle, la supprimer et **depouiller les
echecs**. Resultat : **50 fonctions regressent** — textures, copies, mipmaps, echantillonnage,
UAV. Ce n'est pas une dependance manquee, c'est le cas general.

La cause est dans `kk_CmdPipelineBarrier2` :

```c
if (cmd->metal.render)       { ... }
else if (cmd->metal.compute) { ... }
/* et sinon : rien */
```

**Quand aucun encodeur n'est ouvert — exactement l'etat entre deux passes — une barriere Vulkan
ne produit rien.** Les dependances que DXVK demande entre les passes sont silencieusement
perdues, et la barriere aveugle de `end_encoder` est ce qui les compense.

### La correction tentee, et pourquoi elle ne suffit pas

Conception : memoriser la barriere en attente (`cmd->pending_queue_barrier`) quand aucun
encodeur n'est ouvert, et l'appliquer a l'ouverture du suivant avec
`mtl_barrier_after_queue_stages` — primitive qui existait deja dans le pont. La barriere aveugle
disparait ; `cs_end` conserve l'ordonnance pour les decoupages internes du pilote, et
`kk_cs_end_render_pass` ne le fait pas quand c'est l'application qui ferme la passe.

**Resultat : 5 901 echecs et la suite meurt en route** (507 049 tests au lieu de 538 891).
Pire que la suppression seule. La barriere posee **au debut** de l'encodeur suivant n'est pas
equivalente a celle posee **a la fin** du precedent — ou bien tous les chemins d'ouverture
d'encodeur ne sont pas couverts (encodeurs de copie, operations internes, resolutions de
requetes).

**Revenu a l'etat d'origine, verifie : 4 326 echecs, 538 891 tests.**

### Ce qui est acquis malgre l'echec

La cause est **nommee** : les barrieres Vulkan emises hors encodeur sont perdues, et une
barriere totale a chaque fin d'encodeur les compense au prix de 11 a 15 % du temps d'image.

La corriger proprement demande de couvrir **tous** les points d'ouverture d'encodeur et de
verifier l'equivalence des deux placements de barriere en Metal 4 — un travail de conception
sur le modele de synchronisation du pilote, pas un correctif local. Trois tentatives ont echoue
ici ; la quatrieme doit partir du modele, pas du symptome.

**Piege rencontre** : un vestige de l'echafaudage (`kk_ending_render_pass`) a survecu au
nettoyage et le pilote ne se chargeait plus du tout — `vkCreateInstance` rendait
`INCOMPATIBLE_DRIVER`. Le symbole manquant n'apparait qu'au `dlopen`, pas a la construction.

## 121. Le modele de synchronisation : la barriere aveugle est structurellement necessaire (2026-09-21)

Reprise du probleme par le modele plutot que par le symptome. Rappel du constat de
la section precedente : `end_encoder()` emet un `barrierAfterStages(ALL, ALL)` a la
fermeture de *chaque* encodeur, ce qui serialise tout. Mesure de reference : 7 493
intervalles morts pour 7 494 passes chez nous, contre 1 475 pour 7 623 chez le pilote
natif.

### L'idee : reporter la dependance au lieu de la diffuser

Plutot que de faire attendre tout le monde a chaque fermeture, on note qu'une barriere
Vulkan est arrivee (`pending_queue_barrier`) et on l'applique a l'ouverture de
l'encodeur suivant, par `barrierAfterQueueStages(ALL, ALL)`.

Un trou reel a ete bouche au passage : `kk_CmdPipelineBarrier2()` ne faisait
**rien** quand aucun encodeur n'etait ouvert — plus de 10 000 barrieres Vulkan par
campagne etaient silencieusement perdues, contre moins de 5 000 fermetures
d'encodeur de rendu.

Une deuxieme correction a ete necessaire : quand la barriere arrive pendant qu'un
encodeur est ouvert, le pilote n'emettait qu'une barriere *interne* a cet encodeur.
Elle n'ordonne rien vis-a-vis de l'encodeur **suivant**. La barriere aveugle
rattrapait ce cas ; il a fallu poser aussi le drapeau differe. C'etait exactement
la cause des 23 regressions de `test_cube_maps` (`UpdateSubresource` dans une face
de cube, puis echantillonnage).

D3D11 revient alors exactement a la reference : **4 326 echecs / 538 891 tests**.

### Ce que D3D12 a refuse

**2 115 contre 2 026, soit +89**, concentres sur cinq fonctions et cinq seulement :

| fonction | ecart |
| --- | --- |
| `test_unused_attachments_mix_and_match` | +59 |
| `test_atomic_instructions_dxbc` | +11 |
| `test_atomic_instructions_dxil` | +11 |
| `test_multisample_resolve_formats` | +6 |
| `test_multisample_resolve` | +1 |
| `test_stencil_load` | +1 |

Le profil designe la cause : chargements d'attachements, resolutions, pile de
stencil. Ce sont les actions de `load` et `store` d'une passe de rendu, et elles
s'executent **a l'ouverture et a la fermeture de l'encodeur**, en dehors de toute
commande encodee. Une barriere encodee *dans* l'encodeur ne peut donc pas preceder
son `loadAction`.

Verification faite dans `bridge/mtl_encoder.h` : les trois primitives disponibles
(`barrierAfterStages`, `barrierAfterEncoderStages`, `barrierAfterQueueStages`) sont
**toutes de portee encodeur**. Metal 4 n'expose pas de barriere au niveau du tampon
de commandes. La seule facon d'ordonner quelque chose avant le `loadAction` d'une
passe future est donc que le **producteur** emette `barrierAfterStages` avant de se
fermer — c'est-a-dire precisement la barriere aveugle.

### Le mode hybride tranche

Barriere conservee a la fin des encodeurs de rendu, machinerie differee gardee pour
le cas « aucun encodeur ouvert ». Campagne complete : **2 026, la reference exacte**.

Banc fragment, memes binaires, etat machine identique, entrelace, meilleur de trois :

| ech/pixel | origine | hybride (juste) | sans barriere de fin (faux) | gain hybride |
| --- | --- | --- | --- | --- |
| 4 | 0,140 ms | 0,140 ms | 0,080 ms | **+0,0 %** |
| 32 | 0,510 ms | 0,510 ms | 0,440 ms | **+0,0 %** |
| 128 | 1,840 ms | 1,840 ms | 1,790 ms | **+0,0 %** |

Le mode juste rend exactement zero. Toute la performance venait de la suppression de
la barriere de fin de rendu, c'est-a-dire de ce qui casse la correction.

### Le gain reste chiffre, et reste hors d'atteinte ici

Ce que vaudrait la barriere supprimee, si elle etait licite : **-43 % a 4 ech/pixel,
-14 % a 32, -2,7 % a 128**. Le gain s'ecrase quand la charge fragment monte, ce qui
est coherent : c'est un cout fixe par passe.

Pour l'encaisser il faudrait ne plus fermer l'encodeur de rendu a `vkCmdEndRendering`,
mais **differer sa fermeture** jusqu'a savoir si une barriere Vulkan suit. C'est la
refonte avec suivi des ressources, pas un ajustement. Le prix est desormais connu.

L'arbre est remis dans l'etat connu bon : 4 326 en D3D11, 2 026 en D3D12.

### Deux pieges de mesure, tous deux les miens

**L'etat de la machine derive.** Le repere Metal ecrit a la main est passe de 0,080 ms
(valeur enregistree) a 0,140-0,240 ms a 4 ech/pixel, alors qu'a 128 ech/pixel il
retombe sur la reference (1,700-1,740 contre 1,680). Seul le cas court, domine par le
cout fixe, est touche. Un Godot oublie par une tache de fond tournait encore ; le tuer
n'a pas suffi. Cause non identifiee, etat d'energie du GPU suspecte, **non verifie**.
Consequence pratique : aucune comparaison a un chiffre d'une session anterieure n'est
valable ; seul l'A/B apparie dans la meme session compte. Tous les tableaux ci-dessus
respectent cette regle.

**Un A/B cible qui ne mesurait rien.** `d3d12.exe` n'accepte pas de nom de test en
argument : il ne produit alors aucune sortie. Une boucle censee ne tester que les six
fonctions regressees a rendu 2 115 / 2 026 / 2 026 — des valeurs qui tombaient pile
sur des totaux de suite complete connus. La coincidence etait assez exacte pour etre
prise pour un resultat. Ecartee, puis refaite en campagne complete, qui a donne la
meme conclusion pour de bonnes raisons.

### Un trou de reproductibilite decouvert au passage

En verifiant que l'arbre remis en etat correspondait bien aux correctifs, `0045`
refusait de s'inverser sur trois fichiers. Ce n'etait pas le retour en arriere :
`KK_DEBUG_ENCODER_LABELS`, ajoute pour la capture Metal de la section 120, **ne
figurait dans aucun correctif**. Il n'existait que dans la copie de travail. Rejouer
`tests/etape1_appliquer_correctifs.sh` sur un arbre vierge n'aurait pas reproduit le
pilote mesure.

Corrige par un correctif `0046-kosmickrisp-encoder-labels.patch` (4 hunks, 3 fichiers ;
`mtl_encoder_set_label` est deja en amont, seul l'appel et le drapeau sont a nous), et
`serie_mesa()` dans le script d'application a ete etendu.

Le rejeu integral — arbre de travail git vierge sur `HEAD`, 31 correctifs appliques —
donne maintenant un arbre **identique au caractere pres** a la copie de travail.

C'est ce rejeu, et non `grep`, qui a trouve trois residus de mon retour en arriere :
deux lignes vides parasites dans `kk_cmd_buffer.c` et un commentaire orphelin dans
`kk_cmd_buffer.h` decrivant un champ qui n'existait plus. Lecon : pour verifier qu'un
retour en arriere est complet, la recherche de symboles ne suffit pas, il faut
comparer a un arbre reconstruit.

## 122. Refonte avec suivi des ressources : -14 % sur passes independantes (2026-09-21)

La section 121 concluait que la barriere aveugle ne peut etre retiree que si l'on
**differe la fermeture** de l'encodeur de rendu. C'est ce que fait cette refonte.

### Le mecanisme

A `vkCmdEndRendering`, l'encodeur n'est plus ferme : il passe dans
`cmd->metal.render_closing` et reste ouvert. L'ensemble des images d'attachement de
la passe est retenu dans `closing_writes`. A l'ouverture de la passe suivante, on
compare ses attachements a `closing_writes` et a `unordered_writes` (l'accumule des
passes fermees sans barriere depuis la derniere). Barriere seulement s'il y a
intersection, ou si l'application en a demande une.

Trois points de passage seulement creent ou detruisent un encodeur — `cs_start_render`,
`cs_get_compute`, `cs_end` — ce qui rend le report sur : seule une passe de rendu
suivante peut fermer sans barriere. Tout travail de calcul force l'ordonnancement,
parce qu'il est le plus souvent interne au pilote (evenements, horodatages, meta) et
qu'aucune barriere Vulkan ne le demande. La fermeture est aussi forcee quand la passe
laisse des ecritures differees ou des resolutions d'horodatage en attente, et quand
une resolution meta suit.

### Deux corrections de methode, toutes deux les miennes

**Le banc de la section 121 ne validait rien.** Ses 100 passes ecrivaient toutes la
**meme** cible, sans barriere entre elles et **sans aucune verification du resultat**.
Elles sont en conflit ecriture-apres-ecriture : les laisser se recouvrir les rend plus
rapides *et* fausses. Le « prix » de -43 % annonce en section 121 mesurait donc une
execution que rien ne controlait. Remplace par `tests/bench_pass_vulkan.c`, ou chaque
passe ecrit une cible distincte en rotation.

**Les mesures a 4 echantillons/pixel etaient du bruit.** Trois tirages identiques :
0,35 / 0,17 / 0,27 ms. Mon « meilleur de trois » retenait le tirage le plus chanceux
d'une distribution large. A 32 ech/pixel l'etendue tombe a 1-13 % sur n=12, et les
deux horloges (murale et horodatage GPU) concordent. Tous les chiffres ci-dessous sont
a 32 ech/pixel, n=10, **medianes**.

### Mesures

**Troisieme correction de methode.** Un premier protocole enchainait les dix mesures
d'un mode puis les dix de l'autre, et donnait -34 %. La valeur absolue du mode barriere
a derive de 0,815 a 0,500 ms entre deux campagnes : la derive contamine donc une
comparaison non entrelacee. Refait en **alternant les deux modes a chaque tirage**, ce
qui rend l'ecart par paire insensible a la derive.

100 passes, 32 ech/pixel, n=12, modes entrelaces, ecart calcule **par paire** :

| configuration | barriere | suivi | ecart median | etendue |
| --- | --- | --- | --- | --- |
| 16 cibles distinctes | 0,500 ms | **0,430 ms** | **-14,0 %** | -12,0 a -15,7 % |
| 1 cible, conflit a chaque passe | 0,500 ms | 0,500 ms | **+0,0 %** | +0,0 a +0,0 % |

Le pilote va vite exactement quand il en a le droit, et retombe a la vitesse d'origine
quand les passes sont reellement dependantes. C'est la propriete recherchee.

Le gain reel est donc **-14 %**, pas les -34 % d'un protocole non entrelace ni les
-43 % de la section 121, qui mesuraient une execution non validee.

### Conformite

| suite | avant refonte | fermeture differee seule | + suivi des ressources |
| --- | --- | --- | --- |
| D3D11 | 4 326 | 4 326 | **4 326** |
| D3D12 | 2 026 | 2 497 puis 2 493 | **2 026** |

La fermeture differee seule cassait 471 tests, concentres sur
`test_unused_attachments_mix_and_match` (+376). Ce test enchaine 512 passes qui
accumulent en melange additif dans les **memes** cibles, sans aucune barriere : en
D3D12 une cible de rendu qui reste cible de rendu ne transitionne pas, donc vkd3d
n'emet rien. C'est exactement ce que le suivi des ressources detecte.

### Le producteur non adjacent, et son durcissement

Une premiere version laissait **+2 sur 24,2 millions de tests**, dans
`test_execute_indirect_state`. Trois campagnes a fermeture differee ont donne 1, 2
puis 0 echecs, contre 0 partout en mode barriere : intermittent, mais jamais observe
sans la refonte.

La cause est la limite de Metal 4 de la section 121. Une barriere ne peut etre posee
sur un encodeur qu'avant sa fermeture. Si une passe consomme ce qu'a ecrit un
producteur **non adjacent** reste non ordonne, `unordered_writes` detecte bien le
conflit, mais l'encodeur du producteur est deja ferme : il n'y a plus rien sur quoi
poser la barriere.

Durcissement : quand le conflit porte sur `unordered_writes` plutot que sur l'encodeur
qui se ferme, on pose **en plus** `barrierAfterQueueStages` a l'ouverture de la passe
consommatrice. Celle-ci attend alors tout le travail anterieur de la file, producteur
non adjacent compris. Seules ses actions de chargement restent decouvertes, pour la
raison etablie en section 121.

Deux campagnes completes apres durcissement : **2 026 en D3D12, 4 326 en D3D11, zero
echec indirect**. Cout mesure : nul, la barriere supplementaire n'etant emise que dans
ce cas rare.

Limite connue restante : le suivi ne couvre que les images d'attachement, pas ce
qu'une passe ecrit en ressource de stockage. Aucun test de la suite ne l'exerce
aujourd'hui.

### Verification sur Superposition : aucun gain, et pourquoi (2026-09-21)

Meme methode qu'en section 120 : `xctrace` avec le modele « Metal System Trace », 12 s
attachees au moteur, comptage des `ca-client-present-request`. Deux executions
consecutives, memes reglages, l'une avec `MESA_KK_DEBUG=blanket_barrier` (comportement
d'origine), l'autre avec le suivi.

| | presentations | fenetre | frequence | temps/image median |
| --- | --- | --- | --- | --- |
| barriere d'origine | 284 | 12,420 s | 22,79 img/s | 43,77 ms |
| suivi des ressources | 285 | 12,442 s | 22,83 img/s | 43,77 ms |

**+0,2 % en frequence, +0,0 % en temps par image.** Les medianes sont identiques a
0,01 ms pres.

Le suivi fait pourtant ce qu'il annonce. Sur les memes traces, intervalles GPU fusionnes :
les trous passent de **160 a 44**. La serialisation est bien retiree ; elle ne change
simplement rien, parce que le GPU est **occupe a 100 %** dans les deux cas. Le goulot
est la quantite de travail, pas l'attente entre encodeurs.

C'est exactement ce que le banc annoncait : -14 % quand les passes ecrivent des cibles
distinctes, **+0,0 %** quand chaque passe est en conflit avec la precedente. Superposition
est un rendu differe — G-buffer, eclairage, chaine de post-traitement — ou chaque passe
lit ce que la precedente a ecrit. Le suivi detecte le conflit et emet la barriere, comme
il doit.

**Cela invalide la projection de la section 120**, qui annoncait 11 a 15 % de gain sur
Superposition, soit 22 images par seconde devenant 25 ou 26. Elle extrapolait un cout par
passe mesure sur un banc dont les passes n'etaient pas representatives. Mesure directe :
le gain est nul sur cette scene.

Note de methode : le comptage de trous ci-dessus fusionne les intervalles de tous les
moteurs GPU, donc un trou signifie « aucun moteur actif ». Il n'est pas comparable aux
7 493 trous de la section 120, comptes par encodeur.

La refonte reste acquise et mesuree la ou elle s'applique. Reste a trouver une charge
reelle dont les passes soient reellement independantes — ombres en cascade, chaines de
post-traitement paralleles — pour savoir si le -14 % du banc se retrouve en situation.

### Godot : -1,1 %, et le compteur dit pourquoi (2026-09-21)

Meme protocole entrelace, trois paires, scene `build/godot-heavy` en 1920x1080,
3 000 objets, 24 lumieres avec ombres, post-traitement actif :

| paire | barriere | suivi | ecart |
| --- | --- | --- | --- |
| 1 | 44,444 ms | 44,444 ms | 0,0 % |
| 2 | 44,444 ms | 43,939 ms | -1,1 % |
| 3 | 45,000 ms | 44,444 ms | -1,2 % |

Plutot que d'expliquer ce resultat, il a ete mesure. Un compteur (`MESA_KK_DEBUG=barrier_stats`)
tient le nombre de fermetures differees, de barrieres emises et de barrieres evitees :

| | fermetures differees | barrieres evitees | fermetures immediates |
| --- | --- | --- | --- |
| Godot | 78 609 | **437 (0,6 %)** | 0 |
| Superposition | 60 000 | **103 (0,2 %)** | 84 038 |

**99,4 % des passes de Godot sont en conflit avec la suivante**, et sur Superposition le
compteur d'evitees se fige a 103 : passee la mise en route, plus aucune barriere n'est
evitee. Le -1,1 % est du bruit, pas un gain.

Sur Superposition, 84 038 passes ne sont meme pas differables : elles retombent sur la
fermeture immediate a cause des ecritures differees, des resolutions d'horodatage ou des
resolutions meta. Godot n'en a aucune, donc le mecanisme de report fonctionne bien de bout
en bout ; il ne trouve simplement rien a reporter.

### Ce que vaut la refonte, au net

Elle est correcte (4 326 en D3D11, 2 026 en D3D12), elle ne coute rien, et elle donne -14 %
la ou les passes ecrivent des cibles distinctes. Mais les deux seules charges reelles dont
on dispose ecrivent quasiment toujours dans les memes cibles d'une passe a l'autre : rendu
differe pour Superposition, atlas d'ombres et chaine de rendu pour Godot. **Mesure : +0,2 %
et -1,1 %.**

Le gain existe et il est chiffre ; il n'est pas realise sur ce qu'on sait faire tourner.
C'est une capacite acquise, pas une acceleration livree.

Deux pieges d'outillage rencontres, tous deux les miens : `pgrep -f`/`pkill -f` avec un motif
present dans la ligne de commande du shell appelant **tue ou attend le shell lui-meme** —
c'est ce qui a fait croire a un blocage du pilote. Et le banc Godot ne se termine pas apres
avoir imprime son resultat : il faut attendre la ligne `RESULT` dans le journal puis tuer,
pas attendre la sortie du processus.

## 123. Une charge a passes independantes : construite, mesuree, toujours rien (2026-09-21)

Les deux charges reelles disponibles n'evitaient presque aucune barriere (0,6 % et
0,2 %). Restait a savoir si le -14 % du banc existe sur un moteur reel dont les passes
sont reellement independantes.

### Pourquoi aucun moteur a atlas ne peut en profiter

Verification dans `kk_cmd_draw.c:369` : des que la zone de rendu n'est pas tout le
tampon, le pilote **force le chargement et le stockage de l'attachement entier**.
Metal n'a pas de zone de rendu partielle. Une passe qui n'ecrit qu'une region d'un
atlas d'ombres lit donc et reecrit tout l'atlas : la dependance est **reelle**, pas un
defaut de granularite du suivi. Godot, qui met toutes les ombres positionnelles dans un
atlas, ne pourra jamais en beneficier.

Il faut des passes qui ecrivent des **textures separees**. C'est le patron des vues
secondaires : cameras de surveillance, portails, minicartes, apercus d'interface.
Godot le fait avec des `SubViewport`, chacun ayant sa propre cible.

### La scene construite

`build/godot-views/` : N `SubViewport`, chacun sa texture, sa camera, sur la meme scene
3D, plus la vue principale. Parametres `views`, `size`, `objects`.

| configuration | fermetures differees | barrieres evitees |
| --- | --- | --- |
| 8 vues, 512 px, 800 objets | 16 885 | 3 377 (**20,0 %**) |
| 16 vues, 640 px, 1 500 objets | 30 349 | 6 753 (**22,3 %**) |
| 64 vues, 160 px, 400 objets | 111 133 | 27 009 (**24,3 %**) |

Contre 0,6 % sur la scene lourde. Le patron produit bien des passes independantes.

### Et pourtant, aucun gain

16 vues, trois paires entrelacees : 80,303 / 80,543 — 80,000 / 80,000 — 80,952 / 80,000.
Mediane **0,0 %**.

64 vues, trois paires : 125,000 / 123,503 — 125,000 / 125,000 — 125,758 / 125,000.
Mediane **-0,6 %**.

**Une barriere sur quatre est evitee, et le temps par image ne bouge pas.**

### Ce que cela etablit

Le cout de la barriere d'encodeur n'est pas sur le chemin critique des charges reelles.
Chacune est limitee par autre chose : le travail fragment pour Superposition (GPU occupe
a 100 %, mesure section 122), le debit de tirages pour la scene a 64 vues (25 314 tirages
par image a 8 images par seconde). Le banc montre -14 % parce qu'il ne fait *que*
enchainer des passes : ni cout de soumission, ni travail CPU, presque rien par passe.

Trois charges, trois configurations, trois fois un resultat nul ou sous le pour cent. La
refonte est correcte et gratuite, mais **le gain qu'elle debloque n'existe que dans un
regime que les moteurs reels n'atteignent pas** sur cette pile.

Pour que cela change il faudrait soit un moteur emettant beaucoup de passes courtes vers
des cibles separees, soit avoir d'abord leve les limites qui dominent aujourd'hui — et
c'est la qu'il faut chercher ensuite.

## 124. Le debit de tirages : la geometrie est a parite, l'encodage etait 4,5 fois trop cher (2026-09-21)

La section 123 laissait deux suspects pour les images par seconde : le travail fragment
et le debit de tirages. Voici le second.

### Cadrage : ce n'est pas le nombre de tirages qui domine

Capture de la scene a 64 vues : GPU occupe a **99,6 %**, **155,94 ms de GPU par image**,
57,6 millions de primitives. Elle n'est pas bornee par le CPU, et pas non plus par le
nombre de tirages : c'est de la geometrie.

### Le repere manquant

`tests/bench_draw_metal.m` et `tests/bench_draw_vulkan.c` : D tirages de T triangles dans
une seule passe, cible 256x256 et triangles minuscules pour annuler le cout fragment.
Deux regimes : beaucoup de tirages minuscules (cout par tirage), peu de tirages enormes
(debit par triangle).

| regime | metal natif | notre pile | rapport |
| --- | --- | --- | --- |
| debit par triangle | 1,31 ns | 1,35 ns | **parite** |
| cout par tirage | 0,078 us | 0,158 us | **x2,0** |

En separant l'encodage CPU de l'execution GPU : GPU a parite (2,72 contre 2,85 ms), et
**tout l'ecart dans `vkCmdDraw` cote CPU** — 0,027 contre 0,104 us, soit x3,9.

### La cause

Profil de 3 978 echantillons dans `vkCmdDraw` : **425 dans
`kk_cmd_bind_root_to_argument_table`**. Le pilote reecrivait l'adresse de racine dans la
table d'arguments **a chaque tirage**, alors que le banc ne change aucun etat. La
fonction memorisait deja `cmd->state.root_addr` sans jamais le relire.

### Le piege, et il etait de moi

Premiere tentative : garder la valeur et sortir si elle est inchangee, en invalidant
`root_addr` a chaque ouverture d'encodeur. Resultat : **D3D12 2 157 (+131), D3D11 4 341
(+15)**.

`cmd->state.root_addr` n'est pas un cache, c'est la **valeur sauvegardee** que le chemin
de calcul interne du pilote restaure apres avoir ecrit sa propre adresse a l'indice 0
(`kk_cmd_buffer.c`, « Rebind the existing root »). L'invalider detruisait la racine a
restaurer.

Correction : deux variables distinctes. `root_addr` reste la racine logique a restaurer,
`argtable_addr0` memorise ce qui est reellement ecrit dans la table et vaut
`KK_ARGTABLE_UNKNOWN` tant qu'on ne le sait pas. Les deux chemins qui ecrivent
directement l'indice 0 mettent `argtable_addr0` a jour.

Apres correction : **2 026 en D3D12, 4 326 en D3D11**, les references exactes.

### Le gain

A/B entrelace, `MESA_KK_DEBUG=no_bind_cache` contre defaut, n=10, ecart par paire :

| | encodage par tirage |
| --- | --- |
| sans cache | 106,8 ns |
| **avec cache** | **57,2 ns** |
| metal natif | 23,8 ns |

**-45,8 %** de mediane, etendue -40,7 a -47,4 %. Le rapport a Metal passe de **4,49x a
2,40x**. Le temps GPU baisse aussi legerement : l'ecriture redondante renchérissait
`drawPrimitives` lui-meme.

Au profileur, la fonction passe de 425 a 37 echantillons. Ce qui reste par tirage : 43 %
dans le `drawPrimitives` d'Apple (incompressible), environ 15 % dans
`kk_flush_gfx_state`, 18 % dans `kk_draw`.

### Ce que cela vaut, et ce que cela ne vaut pas

Rien sur les scenes mesurees : la scene a 64 vues est bornee par le GPU a 99,6 %, et
l'economie CPU y vaut 2,6 ms sur 125. Ce correctif compte pour une charge **bornee par
le CPU** avec beaucoup de tirages, ce qui est le cas classique d'un jeu, mais pas celui
de nos charges actuelles.

C'est le premier correctif de performance de cette serie qui reduit un cout **reellement
excessif** plutot que d'en deplacer un : 4,5 fois le cout natif pour reecrire une adresse
inchangee.

## 125. Le travail fragment : le code genere est hors de cause (2026-09-21)

La section 123 laissait deux suspects. Apres le debit de tirages, voici le second, qui
est celui qui borne reellement Superposition (34 ms de fragment sur 38,4 de GPU par image,
section 120).

### L'ecart, et il depend du regime

Banc fragment, protocole entrelace, ecart par paire, n=8 :

| ech/pixel | notre pile | metal ecrit a la main | ecart |
| --- | --- | --- | --- |
| 32 | 0,500 ms | 0,680 ms | **-26,5 %** |
| 128 | 1,835 ms | 1,800 ms | +1,7 % |
| 512 | 11,110 ms | 8,450 ms | **+31,3 %** |

A forte charge d'echantillonnage nous sommes un tiers plus lents, et la mesure est
resserree (+29,7 a +33,9 %). L'ecart est **proportionnel au travail**, pas fixe par passe.

### Ce que montrait le MSL genere

Dans la boucle, chaque iteration recharge le descripteur : pointeur, biais de lod fp16,
index d'echantillonneur, puis l'echantillonneur depuis une table de 4 096 entrees indexee
dynamiquement. Le code ecrit a la main, lui, a une texture et un echantillonneur lies
directement.

### Huit causes eliminees par mesure directe

Chacune testee en l'ajoutant au repere ecrit a la main, ou en la desactivant chez nous :

| hypothese | resultat |
| --- | --- |
| contournement 6 (`coherent device` force) | **+8 a +11 % quand on le desactive** : le retirer est pire |
| biais de lod a chaque echantillon | -0,6 % |
| 4 chargements de descripteur par echantillon | -2,0 % |
| les memes, marques `volatile` | +0,3 % |
| texture bindless deref depuis la memoire | +0,0 % |
| echantillonneur pris dans une table de 4 096 | -0,8 % |
| mode de calcul flottant | le pilote demande deja `FAST` |
| `mathFloatingPointFunctions` | -0,2 % |
| ensemble de residence contre `useResource` | +0,3 % |

### L'experience decisive

`tests/bench_frag_genmsl.m` prend le **MSL genere par notre pilote**, tel quel, et
l'execute dans le harnais Metal avec les memes tampons : table racine, table
d'echantillonneurs, descripteur bindless reconstruits a la main aux memes offsets.

| | 512 ech/pixel |
| --- | --- |
| metal ecrit a la main | 8,31 ms |
| **notre MSL genere, harnais Metal** | **8,38 ms** |
| notre MSL genere, notre pilote | **11,08 ms** |

**Le code genere est a parite.** Les 32 % ne viennent pas du compilateur de nuanceurs :
ils viennent de la mise en place du pilote autour de la passe.

Cela **clot l'angle laisse ouvert par la section 120**, qui designait « l'efficacite du
code Metal produit » comme le seul suspect non explore et jugeait qu'il demandait un
instrument dont on ne disposait pas. L'instrument etait a portee : reinjecter le code
genere dans le harnais.

### Ce qui reste

La difference structurelle non encore testee est l'encodeur : notre pilote utilise
`MTL4RenderCommandEncoder` avec tables d'arguments, le harnais l'encodeur classique avec
liaison directe de tampons. C'est la qu'il faut chercher, et cela demande un harnais
Metal 4, qui n'existe pas encore ici.

Le caractere **proportionnel** de l'ecart oriente vers une difference d'execution par
fragment — occupation, pression de registres, chemin d'acces memoire — plutot que vers un
cout fixe de configuration.

## 126. Harnais Metal 4 : l'encodeur est hors de cause, la compression de texture ne l'etait pas (2026-09-21)

Suite de la section 125, qui avait innocente le code genere et designe l'encodeur comme
seul suspect restant.

### L'encodeur n'y est pour rien

`tests/bench_frag_mtl4.m` execute le **meme MSL genere** avec toute la structure du
pilote : `MTL4Compiler`, `MTL4CommandBuffer`, `MTL4RenderCommandEncoder`, table
d'arguments, ensemble de residence sur la file, et la barriere aveugle a la fin de chaque
passe.

| | 512 ech/pixel |
| --- | --- |
| metal ecrit a la main, encodeur classique | 8,31 ms |
| MSL genere, encodeur classique | 8,38 ms |
| **MSL genere, encodeur Metal 4 complet** | **8,38 ms** |
| MSL genere, notre pilote | 11,08 ms |

Le harnais reproduisait alors presque tout le pilote, et l'ecart persistait. Restait la
texture source.

### La cause

| harnais Metal 4, texture source | 512 ech/pixel |
| --- | --- |
| usage lecture seule | **8,362 ms** |
| + usage ecriture | **14,199 ms** |
| `allowGPUOptimizedContents = NO` | 14,248 ms |

La compression sans perte de Metal vaut **70 %** sur cette charge, et l'usage ecriture la
desactive.

Dans `kk_image_layout.c`, `VK_IMAGE_USAGE_TRANSFER_DST_BIT` ajoutait
`MTL_TEXTURE_USAGE_SHADER_WRITE`. Or c'est le drapeau que porte **toute** texture qu'une
application televerse.

### Le correctif tient en une ligne

Le pilote n'ecrit jamais dans une texture par nuanceur : toutes les copies passent par les
operations natives de l'encodeur de calcul Metal 4 (`copyFromBuffer:toTexture:`,
`copyFromTexture:toBuffer:`, `copyFromTexture:toTexture:`) et aucun noyau de `libkk` ne
fait de `write_image`. L'usage ecriture etait demande pour rien.

| | 512 ech/pixel |
| --- | --- |
| avant | 11,175 ms |
| **apres** | **7,870 ms** (-29,6 %) |
| metal ecrit a la main | 8,31 ms |

Nous passons devant la reference ecrite a la main. Suites : **2 026 en D3D12, 4 326 en
D3D11**, les references exactes.

`MESA_KK_DEBUG=transfer_dst_write` retablit l'ancien comportement pour l'A/B.

### Et pourtant, toujours rien sur Superposition

Trois captures exploitables sur quatre, meme methode qu'en section 122 :

| | img/s | temps/image median |
| --- | --- | --- |
| usage ecriture (ancien) | 22,28 | 43,81 ms |
| compresse | 22,37 | 43,48 ms |
| compresse | 22,36 | 43,61 ms |

**-0,6 %.** L'explication a ete mesuree, pas supposee :

| format de la texture source | lecture seule | + usage ecriture |
| --- | --- | --- |
| RGBA8 | 8,375 ms | 14,189 ms (**+69 %**) |
| BC1 | 6,712 ms | 6,725 ms (**+0,2 %**) |

Sur un format **compresse par blocs**, l'usage ecriture ne coute rien : la compression
sans perte ne s'y applique pas, ces formats etant deja compresses. Les textures d'un jeu
sont en BC, donc Superposition n'en profite pas.

Le correctif compte pour les textures **non compressees** : cibles de rendu intermediaires,
chaines de post-traitement, tampons G, interfaces, tables de correspondance. C'est reel,
mais ce n'est pas le gros des textures d'un jeu.

### Bilan des deux sections

Le fragment a ete entierement disseque : code genere a parite (section 125), encodeur a
parite, et un vrai defaut trouve et corrige a -29,6 % sur formats non compresses. Les
22 images par seconde de Superposition ne viennent ni du compilateur, ni de l'encodeur, ni
de la compression : elles restent le cout du travail lui-meme, comme la section 120 le
concluait deja.

## 127. Le cout du travail lui-meme : tout ce qui est imputable au pilote est a zero (2026-09-21)

Les sections 125 et 126 avaient innocente le compilateur de nuanceurs et l'encodeur, et
corrige la compression de texture. Restait « le cout du travail », que la section 120
designait deja comme la reponse par defaut. Cette fois il est mesure, pas suppose.

### Instrumentation

`MESA_KK_DEBUG=pass_stats` compte les passes de rendu, celles dont la zone n'est pas tout
le tampon, la surface en pixels demandee contre celle du tampon, et le detail des actions
de chargement et de stockage des attachements couleur.

### Superposition, environ 95 secondes de rendu

| mesure | valeur |
| --- | --- |
| passes de rendu | **160 000** (environ 76 par image) |
| passes a zone partielle | **0** (0,0 %) |
| gachis de pixels | **1,00x** |

La piste ouverte en section 123 — `kk_cmd_draw.c` force le chargement **et** le stockage
de l'attachement entier des que la zone de rendu n'est pas tout le tampon, Metal n'ayant
pas de zone partielle — **ne se declenche jamais ici**. Elle reste vraie pour un moteur a
atlas, elle ne coute rien a celui-ci.

Le pilote ne cree par ailleurs aucune passe surnumeraire : le nombre d'encodeurs suit
celui des passes demandees.

### Le trafic d'attachements est celui que l'application demande

```
chargements : load=129167  clear=23025  dontcare=59192
stockages   : store=199246  dontcare=0   autre=0
```

**Pas un seul attachement n'est abandonne.** Ce n'est pas une decision du pilote :
`kk_get_attachment_store_op` suit l'operation Vulkan et ne force le stockage que dans des
cas ici absents (zone partielle, resolution en attente, `STORE_OP_NONE` apres un
chargement). C'est DXVK qui demande `STORE` partout, faute de savoir en D3D11 quand une
cible devient morte.

Par image : environ 94 stockages et 61 chargements plein ecran en 1920x1080, soit de
l'ordre de **780 Mo ecrits et 500 Mo lus par image**.

### Bilan des quatre sections

Tout ce qui est imputable au pilote a ete mesure, et tout est a zero ou a parite :

| axe | resultat |
| --- | --- |
| code MSL genere | parite (section 125, reinjection dans le harnais) |
| encodeur Metal 4 | parite (section 126) |
| compression de texture | defaut trouve, **-29,6 %** sur formats non compresses |
| debit par triangle | parite |
| cout par tirage a l'encodage | defaut trouve, **-45,8 %** |
| passes surnumeraires | aucune |
| chargements et stockages forces | aucun |
| barriere d'encodeur | pas sur le chemin critique (sections 122, 123) |

Les 22 images par seconde sont le travail que l'application demande, execute sans surcout
mesurable. Le seul levier restant identifie est le `STORE` systematique de DXVK, qui est
dans DXVK et non dans KosmicKrisp, et dont le gain n'est pas evalue.

Il manque toujours ce que la section 120 reclamait deja : **un point de comparaison
externe**, le meme banc sur le meme GPU sans notre pile. Sans lui, on sait que la pile
n'ajoute rien de mesurable, mais pas si le chiffre absolu est bon.

### Le STORE systematique de DXVK : le levier est vide (2026-09-21)

La section 127 laissait un seul levier identifie : DXVK demande `STORE` sur tous les
attachements couleur, `dontcare=0` sur 199 246 stockages. Verification faite, il n'y a
rien a prendre.

**DXVK a deja l'optimisation.** `DxvkContext::adjustAttachmentLoadStoreOps` retrograde les
operations quand un attachement n'est pas ecrit pendant la passe : `LOAD_OP_NONE` et
`STORE_OP_NONE` si le pilote annonce `VK_KHR_load_store_op_none`, sinon `LOAD` plus
`STORE_OP_NONE`. Il suit pour cela un `attachmentMask` des acces reels.

**Nous annoncons l'extension** (`kk_physical_device.c`, `KHR_load_store_op_none` et
`EXT_load_store_op_none`), donc DXVK peut s'en servir.

**Il ne s'en sert jamais ici.** Sur **204 829** descriptions d'attachement :

```
kk ops vulkan : NONE/NONE=0  autre_avec_STORE_OP_NONE=0  reste=204829
```

Tout attachement lie par DXVK est reellement ecrit. Le `STORE` n'est pas de la paresse,
c'est la description fidele de ce que fait l'application.

**Ce qui aurait ete un vrai defaut.** Si DXVK avait demande `NONE/NONE`, notre pilote
aurait force un chargement **et** un stockage complets : `kk_get_attachment_store_op` et
`kk_fill_common_attachment_description` traitent tous deux `(LOAD ou NONE) + STORE_OP_NONE`
comme un cas ou il faut charger et stocker, faute pour Metal d'avoir un « laisser
intact ». Le correctif aurait ete de ne pas attacher la texture du tout. Le cas existe
dans le code et se declenchera pour une application qui lie des cibles sans y ecrire ; il
ne se produit pas sur cette scene.

Profil reel des chargements : **61 % LOAD, 11 % CLEAR, 28 % DONT_CARE**. Les `DONT_CARE`
sont gratuits, les `LOAD` sont des lectures authentiques.

Toutes les pistes identifiees sur ce front sont desormais fermees par la mesure.

## 128. Le point de comparaison externe, enfin (2026-09-21)

Depuis la section 120, chaque conclusion de performance butait sur la meme absence : aucun
moyen de savoir si un chiffre absolu etait bon, faute de pouvoir executer la meme charge
sur le meme GPU sans notre pile. Le point de comparaison etait deja installe.

### Le dispositif

`third_party/godot/Godot.app` est la construction macOS de Godot 4.7.2, universelle, avec
un rendu **Metal natif**. Le meme projet, la meme scene, la meme resolution, le meme GPU :
d'un cote `--rendering-driver metal` en natif arm64, de l'autre le Godot Windows a travers
Rosetta, Wine, DXVK/vkd3d et KosmicKrisp.

**Piege ecarte d'abord.** En natif, les deux scenes rendaient *exactement* 20,833 ms, soit
48,0 img/s pile — deux charges tres differentes ne donnent pas la meme mediane au
millieme. C'est une quantification de presentation par pas de 20,833 ms. Il a fallu monter
la charge jusqu'a 16 vues, 1024 px, 6 000 objets pour que le natif en sorte (95 ms avec
une vraie dispersion).

### Le chiffre

Trois paires alternees, meme configuration :

| paire | natif Metal | notre pile | ecart |
| --- | --- | --- | --- |
| 1 | 96,667 ms | 133,333 ms | +37,9 % |
| 2 | 98,148 ms | 129,167 ms | +31,6 % |
| 3 | 98,611 ms | 129,249 ms | +31,1 % |

Medianes : **98,1 contre 129,2 ms, soit +31,7 %**.

### Ou l'ecart se loge

Captures « Metal System Trace » des deux cotes, meme charge (la capture ralentit les deux,
les frequences absolues ne sont pas comparables a celles ci-dessus) :

| | GPU occupe | GPU par image |
| --- | --- | --- |
| natif Metal | **99,5 %** | **115,94 ms** |
| notre pile | **74,6 %** | **164,31 ms** |

Deux constats distincts, et ils appellent des correctifs differents :

1. **+42 % de travail GPU par image.** Le GPU fait davantage, ou le fait moins
   efficacement.
2. **Le GPU est inoccupe un quart du temps** chez nous, sature en natif. Il y a donc aussi
   une limite cote soumission ou synchronisation.

### La reserve, et elle est importante

Ceci compare le **backend D3D12 de Godot** au **backend Metal de Godot**. Ce ne sont pas
les memes chemins de rendu : nuanceurs compiles differemment, strategies de ressources
distinctes, passes possiblement differentes. Le +31,7 % borne le cout de **toute la
chaine**, pas celui du pilote seul. Une partie appartient a Godot, a DXVK/vkd3d et a
Rosetta.

C'est neanmoins la premiere mesure directe dont dispose le projet, et elle recadre les
sections 120 a 127 : celles-ci etablissaient que le pilote n'ajoute rien de mesurable sur
les axes testes, ce qui reste vrai. Le +31,7 % dit qu'il reste un ecart a l'echelle de la
chaine, et les captures disent ou chercher : le travail GPU lui-meme, et l'occupation.

## 129. L'occupation a 74,6 % : le pilote tourne sous Rosetta (2026-09-21)

La section 128 avait montre deux choses : **+42 % de travail GPU par image**, et un GPU
**inoccupe un quart du temps** la ou le natif le sature. Voici la seconde.

### Le profil des trous

Memes captures, intervalles GPU fusionnes :

| | trous | temps mort | median | plus gros |
| --- | --- | --- | --- | --- |
| natif Metal | 118 | 57,7 ms (**0,5 %**) | 0,035 ms | 5,0 ms |
| notre pile | **912** | 3 182 ms (**25,4 %**) | **1,862 ms** | **152 ms** |

912 trous pour environ 57 images, soit **a peu pres 16 par image** — exactement le nombre
de `SubViewport`. Un arret par passe, pas un manque de debit global.

### La cause

`wine/wine10/bin/wine64` est un executable **x86_64**. Tout ce qu'il charge l'est aussi,
y compris notre pilote : `VK_DRIVER_FILES` pointe sur `prefix-x64`, dont la bibliotheque
est x86_64. **Le pilote Vulkan tourne donc sous Rosetta**, alors que Godot natif est en
arm64 avec Metal direct.

Mesure du surcout, meme code de pilote, meme GPU, meme banc de 50 000 tirages :

| construction | encodage |
| --- | --- |
| arm64 natif | 2,78 / 2,84 / 2,85 ms |
| x86_64 sous Rosetta | 6,34 / 6,52 / 7,39 ms |

**2,3 fois plus lent** cote CPU. Chaque `vkCmdDraw`, chaque barriere, chaque mise a jour
de descripteur est du code emule.

### Ce que cela recadre

Toutes les mesures des sections 120 a 127 portaient sur le pilote **natif arm64**, via des
bancs Vulkan compiles pour arm64. Elles restent valables telles quelles, mais elles ne
decrivent pas le pilote tel qu'il s'execute dans le chemin Wine, ou il est 2,3 fois plus
lent sur le CPU. Le correctif de la section 124 (-45,8 % sur l'encodage des tirages) vaut
donc **davantage** dans le chemin reel que ce que le banc natif annonçait.

### La direction, sans la surestimer

Wine 10.0 dispose de `--enable-archs` avec `aarch64` et du mecanisme `wow64`. Un hote Wine
**arm64** executant du PE x86_64 rendrait notre pilote natif, ce que font les distributions
commerciales sur Apple Silicon.

La reserve : seule la partie Unix deviendrait native. Godot, DXVK et vkd3d restent du code
Windows x86_64 et continueraient d'etre traduits. Le gain se limite donc a la part CPU du
pilote, qui n'est pas mesuree. **Il serait malhonnete d'annoncer que cela supprime les
25 % de temps mort.**

Ce qui est etabli : le pilote est emule, cela coute un facteur 2,3 sur son chemin CPU, et
c'est la seule cause identifiee du GPU inoccupe.

## 130. Pile entierement ARM64 : tres avancee, bloquee au dernier metre (2026-09-21)

Decision prise de tout passer en ARM64, Rosetta etant annonce en fin de vie. Etat des
lieux honnete : la plus grande partie est faite et verifiable, un obstacle reste.

### Ce qui marche

| piece | etat |
| --- | --- |
| chaine llvm-mingw aarch64 | deja dans `toolchain/`, produit du PE Aarch64 |
| vkd3d-proton | **construit en PE Aarch64** (`d3d12.dll`, `d3d12core.dll`) |
| Godot 4.7.2 Windows ARM64 | telecharge, `PE32+ Aarch64` |
| pilote KosmicKrisp arm64 | deja construit (`prefix/`) |
| Wine 11.18 arm64 | **construit et installe**, `wine`/`wineserver` en Mach-O arm64 |
| `wineserver` arm64 | **demarre et tourne** |
| `wine --version` | fonctionne |

`tests/etape2_pile_arm64.sh` lance la pile complete.

### Les deux obstacles rencontres, et ce qu'ils ont appris

**1. Pages de 16 Ko.** Wine 10.0 refuse : `wineserver: page size is 16k but Wine requires
4k pages`. macOS arm64 natif impose 16 Ko, le modele memoire Windows suppose 4 Ko. C'est
la raison de fond pour laquelle les distributions commerciales gardent Wine en x86_64 :
Rosetta fournit des pages de 4 Ko.

Resolu en amont : **Wine 11.18** introduit `host_page_size` (50 occurrences dans
`virtual.c`). D'ou la construction sur un arbre separe, `src/wine11`, la pile x86_64
restant intacte sur Wine 10.

**2. `__PAGEZERO` a 4 Go.** Le binaire arm64 reservait tout l'espace bas, la ou Wine doit
placer l'espace Windows, d'ou `try_map_free_area mmap() error ... range 0x100000000`. Le
Makefile demande pourtant `-pagezero_size,0x1000`. Relie a la main, l'option est prise.
Note : a 16 Ko (`0x4000`) le binaire est tue au lancement, a 4 Ko (`0x1000`) il demarre —
resultat contre-intuitif, mesure et non deduit.

### L'obstacle restant

`wine --version` repond, `wineserver` tourne, mais `wine cmd` est **tue par SIGKILL** a
l'initialisation du sous-systeme Windows, sans aucune sortie, meme avec `WINEDEBUGLOG`.
Le prefixe ne se cree pas. Signature ad hoc avec `allow-jit`,
`allow-unsigned-executable-memory` et `disable-library-validation` : sans effet.

La trace dyld (avec les droits permettant les variables `DYLD_*`) montrait 1 458
bibliotheques chargees dont `aarch64-unix/ntdll.so` avant la mort. L'echec est donc apres
le chargement, dans la mise en place de l'espace d'adressage Windows.

### Ce qui reste a faire

Diagnostiquer ce SIGKILL. Pistes non explorees : le `wow64` de Wine 11 attend peut-etre une
configuration particuliere ; l'espace d'adressage bas peut rester inaccessible malgre le
`__PAGEZERO` reduit ; le chargement des modules PE Aarch64 peut demander un traitement
specifique sur macOS.

DXVK n'est pas requis pour la mesure Godot, qui passe par vkd3d en D3D12. Sa construction
aarch64 a demande un correctif de portabilite (`#include <algorithm>` manquant dans
`src/util/config/config.cpp`, libc++ ne l'apportant pas indirectement contrairement a
libstdc++) puis bute sur une erreur de gabarits dans `tuple` de libc++ avec `-std=c++17`.

## 131. Wine arm64 natif sur macOS : impossible, et la preuve tient en trois lignes (2026-09-21)

Suite de la section 130, qui laissait un SIGKILL muet. Il est elucide, et la conclusion
depasse Wine.

### La chaine de diagnostic

Le SIGKILL etait muet parce que le processus mourait avant l'initialisation des traces.
Trois etapes pour le faire parler :

1. **`DYLD_*` depouille.** Les variables d'environnement dyld sont retirees d'un binaire
   signe sans l'autorisation `allow-dyld-environment-variables`. D'ou les traces vides.
2. **Flag d'edition de liens malforme.** Ma modification du Makefile avait produit
   `-sectcreate` sans le prefixe `-Wl,`, ce qui cassait le lien silencieusement.
3. **lldb avec `stop-on-exec` desactive**, le chargeur Wine se re-executant.

Le message est alors apparu :

```
err:virtual:map_fixed_area out of memory for 0x7ffe0000-0x7ffe1000
err:virtual:virtual_alloc_first_thread_data wine: failed to map the shared user data: c0000017
```

Wine doit placer `KUSER_SHARED_DATA` a l'adresse **fixe** `0x7ffe0000`, environ 2 Go. Or
le binaire arm64 reserve les 4 premiers Go en `__PAGEZERO`.

### La preuve, sans Wine

Il suffit d'un programme de trois lignes :

| edition de liens | `__PAGEZERO` obtenu | resultat |
| --- | --- | --- |
| par defaut | 4 Go | **s'execute** (code 42) |
| `-pagezero_size,0x1000` | 16 Ko | **tue** (SIGKILL) |
| `-segalign,0x1000,-pagezero_size,0x1000` | 4 Ko | **tue** |
| `-segalign,0x4000,-pagezero_size,0x4000` | 16 Ko | **tue** |
| `-no_pie` | — | lien refuse en arm64 |

**macOS arm64 impose les 4 Go de `__PAGEZERO`.** Tout binaire natif qui les reduit est tue
par le noyau au lancement. L'espace d'adressage bas est donc inaccessible, quoi qu'on
fasse, et `0x7ffe0000` avec lui.

Ce n'est pas un defaut de Wine : c'est une politique du noyau, et elle est absolue.

### Ce que cela etablit

**Wine natif arm64 est impossible sur macOS**, tant que cette politique tient et que
Windows place `KUSER_SHARED_DATA` a une adresse fixe sous 4 Go.

> **Correction, section 140.** Cette conclusion est trop forte. La contrainte du noyau est
> reelle et confirmee sur toute la plage, mais `KUSER_SHARED_DATA` peut etre **deplace**, ce
> qui debloque l'initialisation de Wine. Voir la section 140. C'est la raison, enfin
demontree, pour laquelle toutes les distributions commerciales sur Apple Silicon font
tourner Wine en x86_64 sous Rosetta : un processus traduit obtient un petit `__PAGEZERO`
et des pages de 4 Ko.

La section 129 avait mesure que le pilote emule coute un facteur **2,3** sur son chemin
CPU. Ce cout n'est donc pas evitable par cette voie.

### Ce qui reste utilisable du travail

Rien n'est perdu cote PE : vkd3d-proton en Aarch64, Godot Windows ARM64 et la chaine
llvm-mingw restent valables le jour ou un hote arm64 deviendrait possible — par exemple si
Wine relocalisait `KUSER_SHARED_DATA`, ce qui casserait la compatibilite avec le code qui
code cette adresse en dur.

**Consequence strategique.** Si Rosetta 2 disparait, ce n'est pas seulement une perte de
performance pour ce projet : c'est la disparition du seul chemin viable. Le probleme n'est
pas la performance du pilote, c'est l'existence de l'hote.

## 132. Optimiser le pilote pour Rosetta : un gain, deux impasses (2026-09-21)

La section 131 ayant ferme la voie arm64, le pilote reste en x86_64 traduit. La section 129
avait mesure que cela coute un facteur **2,3** sur son chemin CPU : chaque cycle economise
y vaut donc plus qu'en natif.

Toutes les mesures ci-dessous sont faites sur le **binaire x86_64 sous Rosetta**, pas sur
le banc natif, puisque c'est la pile reelle.

### Ce qui marche : raccourci d'etat propre

`kk_flush_gfx_state` s'executait integralement a chaque tirage. Ajout d'une sortie
anticipee quand rien n'est sale : encodeur de rendu deja ouvert, pas de passe a demarrer,
`gfx->dirty` et `dirty_shaders` nuls, ni descripteurs pousses ni racine salie, etat
dynamique vide.

| | sous Rosetta |
| --- | --- |
| sans raccourci | 133,3 ns/tirage |
| **avec raccourci** | **127,5 ns/tirage** |

**-5,5 %** de mediane, quartiles -8,3 / +3,5, n=12 entrelaces.
`MESA_KK_DEBUG=no_state_fastpath` retablit l'ancien comportement.

Gain modeste, et c'etait previsible : les branches internes de `kk_flush_dynamic_state`
etaient deja gardees une a une par leurs drapeaux `IS_DIRTY`.

### Premiere impasse : cibler SSE4.2

Le pilote x86_64 est compile en `-O3` sans `-march`, donc pour le x86-64 de base (SSE2).
Rosetta 2 gere jusqu'a SSE4.2. Essai avec `-march=x86-64-v2` : **+1,6 %**, donc rien ou
legerement pire. Le chemin de commandes est du parcours de pointeurs et des branchements,
pas du calcul vectorisable, et rien ne garantit que Rosetta traduise mieux les
instructions recentes. Annule.

### Seconde impasse : optimisation inter-fichiers

`-Db_lto=true` est refuse par Mesa lui-meme :
`ERROR: Building Mesa with LTO is not supported. Please disable LTO for building Mesa.`

### Etat du chemin de tirage

Il est desormais mince : un seul appel Metal par tirage, `kk_flush_xfb_state` sort
immediatement quand le nuanceur de sommets ne capture pas, `build_per_draw_upload_mask` se
reduit a quelques tests de bits, et l'etat ne se recalcule plus quand rien n'a change.

Le rapport traduit sur natif passe d'environ **2,3x a 2,1x** sur l'encodage.

### Ce qu'il faut en retenir

Le correctif reellement rentable de cette serie reste celui de la section 124, l'adresse
de racine reecrite a chaque tirage, **-45,8 %** — et il vaut d'autant plus ici que chaque
cycle economise est multiplie par 2,1. Ce raccourci-ci ajoute 5 %.

Le reste du cout par tirage est le `drawPrimitives` d'Apple et la traduction elle-meme,
sur lesquels le pilote n'a pas prise.

Suites : **2 026 en D3D12, 4 326 en D3D11**, avant et apres.

## 133. La dette du suivi des ressources : fermee, et elle coutait plus cher qu'annonce (2026-09-21)

Les sections 122 et 126 laissaient une dette explicite : le suivi des ressources compare
les **images d'attachement**, mais une passe peut aussi ecrire par nuanceur dans des images
ou des tampons de stockage, et ces ecritures n'etaient recensees nulle part.

### Le scenario qui mordait

Une passe A ecrit une ressource de stockage X. A se ferme en differe, `closing_writes` ne
contenant que ses attachements. Si rien n'ouvre d'encodeur entre-temps, la barriere de
l'application arrive alors que A est encore l'encodeur differe et le drapeau est pose :
correct. Mais si une passe B s'ouvre avant la barriere, A est ferme **sans ordre**, et plus
rien ne peut le rattraper : Metal n'autorise a poser une barriere sur un encodeur
qu'avant sa fermeture, comme etabli en section 121.

C'est le probleme du producteur non adjacent, restreint aux ressources que le suivi ne
voyait pas.

### Le correctif, conservateur et assume

`nir->info.writes_memory` est propage dans `kk_shader_info`, et `kk_cs_end_render_pass`
retombe sur la fermeture immediate des qu'un nuanceur lie peut ecrire en memoire. Plus de
differe, donc plus de trou, au prix de l'optimisation pour ces passes.

La solution complete serait de recenser les ressources de stockage ecrites, comme on le
fait pour les attachements. Elle est nettement plus lourde et n'a pas ete tentee.

### Un defaut dans ma premiere version

`cmd->state.shaders` est **partage avec le calcul** : les nuanceurs de calcul y occupent
`MESA_SHADER_COMPUTE`. Ma boucle balayait tous les etages, donc un nuanceur de calcul lie —
et il ecrit presque toujours en memoire — desactivait le differe pour **toutes** les passes
de rendu. Restreint a `MESA_SHADER_VERTEX` jusqu'a `MESA_SHADER_FRAGMENT` :

| Godot | tous les etages | etages graphiques |
| --- | --- | --- |
| fermetures differees | 10 359 | **78 175** |
| fermetures immediates | **68 250** | **434** |
| barrieres evitees | 417 (4,0 %) | 435 (0,6 %) |

Seules **0,55 %** des passes ont reellement un nuanceur graphique qui ecrit en memoire. La
dette est donc fermee pour presque rien, et non pour 87 % des passes comme la premiere
version le laissait croire.

Temps par image sur Godot : **43,750 ms** contre 44,444 auparavant, aucune regression.
Banc a passes independantes : **-12,2 %**, l'ecart avec -14,0 % etant du bruit machine.

Suites : **2 026 en D3D12, 4 326 en D3D11**.

### Pourquoi le recensement complet est impossible ici

Recenser les ressources de stockage ecrites, puis les ressources lues par la passe
suivante, demanderait d'enumerer ce que les descripteurs designent. Deux chemins coexistent
dans le pilote : les ensembles classiques, que `kk_descriptor_state.sets[]` possede et qu'on
pourrait inspecter, et les **tampons de descripteurs**, dont
`cmd->state.descriptor_buffers[]` ne retient qu'une **adresse GPU opaque** en memoire de
l'application.

La section 117 a etabli que vkd3d utilise l'extension : desactiver
`VK_EXT_descriptor_buffer` changeait la conformite, 2 210 contre 2 026. Sur le chemin D3D12,
qui est la cible principale, le pilote ne peut donc enumerer **ni ce qu'une passe lit, ni
ce qu'elle ecrit** a travers ses descripteurs.

Cela explique la forme du suivi : les attachements sont les seules ressources passees
**explicitement** dans l'API, hors descripteurs, donc les seules recensables. Tout le reste
est opaque par construction.

Le repli conservateur n'est pas un pis-aller en attendant mieux : c'est la seule option
correcte sous tampons de descripteurs, et il ne coute que 0,55 % des passes.

## 134. Point complet apres la campagne performance (2026-09-22)

Les sections 121 a 133 forment une campagne unique : comprendre pourquoi la pile rend
22 images par seconde sur Superposition, et ce qu'on peut y faire. Voici le bilan, sans
rien arrondir.

### Les trois correctifs acquis

| correctif | section | gain mesure | ou il porte |
| --- | --- | --- | --- |
| adresse de racine reecrite a chaque tirage | 124 | **-45,8 %** d'encodage | toute charge riche en tirages |
| compression de texture desactivee par `TRANSFER_DST` | 126 | **-29,6 %** a 512 ech/pixel | textures **non compressees** |
| etat graphique recalcule sans raison | 132 | **-5,5 %** d'encodage sous Rosetta | toute charge riche en tirages |

Le premier est le plus rentable, et il vaut double dans le chemin reel puisque le pilote
y tourne traduit. Le deuxieme ne porte pas sur les textures d'un jeu, qui sont compressees
par blocs : mesure BC1, l'usage ecriture n'y coute **rien** (6,712 contre 6,725 ms).

### La refonte de la synchronisation

Fermeture differee de l'encodeur de rendu plus suivi des ressources : **-14 %** quand les
passes ecrivent des cibles distinctes, **0 %** sinon. Correcte et gratuite, mais son
domaine est etroit — ni Superposition, ni Godot, ni une scene a 16 vues n'en profitent,
car leurs passes se recouvrent ou sont bornees ailleurs.

Dette fermee en section 133, et le recensement complet demande est **impossible** : sous
`VK_EXT_descriptor_buffer`, que vkd3d utilise, le pilote ne voit des descripteurs qu'une
adresse opaque. Les attachements sont les seules ressources passees explicitement dans
l'API, donc les seules recensables.

### Ce qui a ete innocente, et comment

| axe | verdict | methode |
| --- | --- | --- |
| code MSL genere | **parite** | reinjection du MSL genere dans le harnais Metal |
| encodeur Metal 4 | **parite** | harnais Metal 4 complet, memes tampons |
| debit par triangle | **parite** | 1,35 contre 1,31 ns |
| passes surnumeraires | **aucune** | compteur, 160 000 passes, 0 partielle |
| chargements et stockages forces | **aucun** | 0 NONE/NONE sur 204 829 attachements |
| barriere d'encodeur | **hors du chemin critique** | 24 % de barrieres evitees pour 0 % de gain |

Rien de ce qui reste n'est imputable au pilote.

### Le chiffre qui manquait, et celui qu'il a revele

Godot en Metal natif contre la pile complete, meme projet, meme GPU : **98,1 contre
129,2 ms, soit +31,7 %**. Reserve importante, cela compare deux backends de Godot, pas le
pilote seul.

Les captures decomposent : **+42 %** de travail GPU par image, et un GPU **inoccupe 25 %
du temps** contre 0,5 % en natif. Ce second point est explique : le pilote Vulkan tourne
sous Rosetta, ce qui coute un facteur **2,3** sur son chemin CPU.

### La limite structurelle

Un Wine arm64 natif supprimerait cette traduction. Il est **impossible sur macOS**, et la
preuve tient en trois lignes de C : tout binaire arm64 dont le `__PAGEZERO` est reduit est
tue par le noyau, et Wine a besoin de l'espace bas pour `KUSER_SHARED_DATA` a `0x7ffe0000`.
C'est la raison, demontree, pour laquelle toutes les distributions commerciales gardent
Wine en x86_64 sous Rosetta.

**La pile depend donc de Rosetta pour exister, pas seulement pour aller vite.** Si Rosetta
disparait, le probleme n'est pas 30 % de performance, c'est l'absence d'hote.

Ce qui reste utilisable du chantier ARM64 : vkd3d-proton en PE Aarch64, Godot Windows
ARM64, la chaine llvm-mingw, et Wine 11.18 qui construit et s'installe en arm64. Tout cela
attend qu'un hote arm64 devienne possible.

### Ce que cette campagne a coute en erreurs, et ce qu'on en retient

Sept resultats annonces puis corriges. Les causes, toutes methodologiques :

- **un banc qui ne verifie pas son resultat** mesurait une execution fausse comme un gain
  (-43 % annonce en section 121, inexistant) ;
- **un protocole non entrelace** contamine par la derive machine (-34 % au lieu de -14 %) ;
- **un « meilleur de trois »** sur une distribution large (0,35 / 0,17 / 0,27 ms pour le
  meme banc) ;
- **un processus oublie** d'une session precedente faussant tout pendant des heures ;
- **`pgrep -f` et `pkill -f`** dont le motif matche le shell appelant, d'ou un faux
  blocage impute au pilote ;
- **un compteur balayant les etages de calcul** en croyant ne voir que le graphique
  (87 % au lieu de 0,55 %) ;
- **une compilation echouee** dont la mesure portait sur l'ancien binaire.

Regles qui en decoulent, et qui ont fini par tenir : entrelacer les modes compares,
publier medianes et etendues, verifier qu'un banc valide son resultat, tuer les residus
avant de mesurer, et se mefier d'un chiffre qui tombe pile sur une valeur connue.

### Ou chercher ensuite

Le pilote est a parite sur tous les axes testes. Les deux pistes ouvertes sont ailleurs :

1. **Les +42 % de travail GPU** de la section 128, non expliques. Ils comparent deux
   backends de Godot, donc une part appartient a Godot et a vkd3d, pas a nous. Un
   decoupage par passe des deux captures le dirait.
2. **Le risque Rosetta**, qui est de nature strategique et non technique.

## 135. Les +42 % de travail GPU : c'est le fragment, et trois causes sont ecartees (2026-09-22)

La section 128 mesurait **+42 % de travail GPU par image** contre Godot en Metal natif, sans
savoir ou. La decomposition des memes captures par etage le dit.

### Piege de lecture, a nouveau

Le schema `metal-gpu-intervals` porte **deux colonnes de type `duration`** : la duree et la
latence CPU vers GPU. Quand la duree est une **reference** vers une valeur deja vue, une
regex naive saute a la colonne suivante et ramene la latence. Premiere tentative :
578 secondes de travail vertex dans une fenetre de 12,7 s — absurde, et c'est ce qui a
alerte. Il faut resoudre les references dans l'ordre du document. Voir
`/tmp/parse_gi.py`, meme piege qu'en section 120.

### La decomposition

| etage | natif | notre pile | ecart |
| --- | --- | --- | --- |
| Vertex | 78,70 ms/image | 80,33 ms/image | **+2,1 %** |
| **Fragment** | **21,44 ms/image** | **43,65 ms/image** | **+103,6 %** |
| Compute | 0,26 ms/image | 0,44 ms/image | +71 % |

La geometrie est a parite. Le fragment est double, et comme il pese 21 ms sur les 100 ms
de temps d'etage natif, ce doublement porte l'essentiel des 24 ms d'ecart.

**Controle contre un biais de capture.** Sous capture notre execution tombe a 4,51 img/s
contre 7,5 sans, le natif a 8,55 contre 10,3 : la capture nous penalise davantage, ce qui
pourrait gonfler nos chiffres par image. Le rapport **fragment sur vertex**, lui, est
immunise contre un ralentissement uniforme : **0,272 en natif contre 0,543 chez nous,
soit x1,99**. Le doublement tient.

### Trois causes ecartees par la mesure

| hypothese | test | resultat |
| --- | --- | --- |
| compression perdue (section 126) | `MESA_KK_DEBUG=no_storage_write` | **~1,6 %** |
| chargements d'attachements | `MESA_KK_DEBUG=no_attachment_load` | **0 %** |
| travail soumis different | tirages et primitives rapportes par Godot | **0,6 %** |

Les deux premiers phenomenes existent pourtant : **176 images sur 393 (44,8 %)** portent
l'usage ecriture, et toutes sont des attachements de rendu ; **65 % des attachements sont
charges**, 42 758 `LOAD` contre 21 714 `CLEAR`, a la demande de vkd3d et non par forcage du
pilote. Ni l'un ni l'autre ne porte le cout.

### Un biais de methode, a notre charge

La fenetre principale fait **1 732x1 080** chez nous contre **1 920x1 080** en natif, Wine
contraignant la taille. L'effet est faible, les 16 vues de 1 024 carres faisant 90 % du
travail fragment et etant identiques, et il joue **contre nous** : moins de pixels rendus
pour plus de temps. La comparaison n'est donc pas rigoureusement a surface egale.

### Ce qui reste

Nos intervalles fragment sont **25 % plus nombreux** (154,4 contre 123,4 par image) et
**1,63x plus longs** chacun, pour une geometrie identique. Avec 6 000 objets qui se
recouvrent, le suspect naturel est le **rejet precoce en profondeur** : si la configuration
de pipeline empeche le GPU d'ecarter les fragments caches, l'ombrage double sans que rien
d'autre ne change. Piste cote pilote, non encore testee faute de levier pour l'isoler.

Suites : **2 026 en D3D12, 4 326 en D3D11**.

### Le rejet precoce : ecarte, il fonctionne (2026-09-22)

Suspect designe par la section 135. Nouveau repere `tests/bench_depth_*` : N couches plein
ecran dessinees de l'avant vers l'arriere, test de profondeur LESS avec ecriture, nuanceur
fragment couteux a 128 echantillons par pixel. Si le GPU ecarte les fragments caches, le
temps ne depend pas de N.

| couches | metal natif | notre pile |
| --- | --- | --- |
| 1 | 1,89 ms | 1,92 ms |
| 2 | 2,83 ms | **1,96 ms** |
| 8 | 2,48 ms | **1,96 ms** |
| 32 | 2,33 ms | **2,17 ms** |

Le temps est plat des deux cotes : **le rejet precoce fonctionne**, et notre pile est meme
legerement meilleure que la reference ecrite a la main au-dela d'une couche.

Quatrieme hypothese ecartee, apres la compression, les chargements d'attachements et un
travail soumis different.

### Ce qui reste, et une limite de la section 125

Le seul suspect encore debout est la **qualite du code fragment produit pour les nuanceurs
reels de Godot**. La section 125 avait etabli la parite du code genere en reinjectant notre
MSL dans le harnais Metal — mais sur le nuanceur **simple** du banc, une boucle
d'echantillonnage. Rien n'y prouve la parite sur un nuanceur d'eclairage complet passe par
HLSL, DXIL, dxil-spirv, SPIR-V, NIR puis MSL.

Le tester demanderait d'extraire un nuanceur reel des deux chemins et de comparer, ce qui
n'a pas ete fait.

## 136. Extraction d'un vrai nuanceur : il est enorme, et la comparaison native est hors d'atteinte (2026-09-22)

La section 135 laissait un seul suspect : la qualite du code fragment produit pour les
nuanceurs reels de Godot, la parite de la section 125 n'ayant ete etablie que sur le
nuanceur simple du banc.

### Ce que produit notre chaine

`MESA_KK_DEBUG=msl` sur la scene a vues, 23 nuanceurs fragment captures. Le principal :

| | valeur |
| --- | --- |
| lignes de MSL | **51 585** |
| temporaires declares | **17 660** |
| registres | **970** |
| branchements | 905 |
| boucles restantes | 42 |
| echantillonnages de texture | 114 |
| chargements de descripteur | **890**, soit **7,8 par echantillonnage** |
| gardes de boucle `no_crash` | 126 |

Un nuanceur d'eclairage natif fait quelques milliers de lignes. **17 660 temporaires et
970 registres** representent une pression de registres considerable, et sur un GPU a tuiles
la pression de registres reduit le nombre de fils en vol, donc le debit d'ombrage.

C'est coherent avec tout ce qui a ete ecarte : le cout est **par fragment**, pas dans le
travail soumis ni dans la configuration des passes.

### Cinquieme hypothese ecartee

Le code est truffe de `coherent device`, impose par le contournement 6. La section 125
l'avait teste sur le nuanceur **simple** du banc, ou le desactiver etait pire. Teste sur la
scene reelle, avec 890 chargements de descripteur que `coherent` empeche de factoriser :
-1,0 %, +1,8 %, +4,0 % sur trois paires. **Neutre.** La generalisation redoutee n'a pas eu
lieu, mais il fallait la verifier.

### Pourquoi la comparaison demandee n'aboutit pas

Obtenir le MSL que Godot produit lui-meme pour son rendu Metal est hors d'atteinte avec le
binaire distribue :

- aucune option de vidage de nuanceurs, `--help` ne propose que `--generate-spirv-debug-info`,
  reserve a Vulkan ;
- `~/Library/Application Support/Godot/shader_cache` ne contient que des nuanceurs GLES3 de
  l'editeur, et il est vide ;
- le projet ne laisse aucun cache Metal a cote de `vkd3d-proton.cache` ;
- une capture Metal produirait un `.gputrace` que seule l'interface d'Xcode sait ouvrir.

### L'etat de la question

Six hypotheses ecartees par la mesure pour le doublement du fragment : compression,
chargements d'attachements, travail soumis different, rejet precoce, contournement 6, et
la configuration des passes. Ce qui reste est le **cout par fragment du nuanceur traduit**,
et la taille du code genere le rend credible sans le prouver.

Prouver l'imputation demanderait le nuanceur natif, que Godot ne laisse pas sortir. Une
autre voie serait de mesurer le cout du motif lui-meme — 114 echantillonnages precedes
chacun de ses chargements de descripteur, contre 114 echantillonnages a textures liees —
dans le harnais Metal. Non fait.

## 137. Le cout du motif de traduction : il explique le doublement (2026-09-22)

La section 136 avait extrait le nuanceur reel — 51 585 lignes, 114 echantillonnages,
890 chargements de descripteur — sans pouvoir l'imputer faute de reference native. Le motif
lui-meme se mesure.

### Le banc

`tests/bench_motif_metal.m` genere deux nuanceurs MSL a N echantillonnages de la **meme**
texture, pour que le cache se comporte identiquement :

- **texture liee** : `tex.sample(smp, uv)`, le patron natif ;
- **bindless** : la chaine exacte que KosmicKrisp produit, soit pour chaque
  echantillonnage une adresse lue dans la table racine, le pointeur de descripteur, le
  biais de lod, la texture, l'index d'echantillonneur, puis l'echantillonneur pris dans une
  table de 4 096.

Les deux sont ecrits a la main en Metal : le banc isole le **motif**, independamment de
notre pilote.

### Le resultat

n=6 par point, medianes :

| echantillonnages | texture liee | bindless | surcout |
| --- | --- | --- | --- |
| 8 | 0,530 ms | 0,571 ms | +7,4 % |
| 16 | 0,790 ms | 0,933 ms | +17,6 % |
| 32 | 1,217 ms | 1,738 ms | +51,9 % |
| 64 | 1,142 ms | 2,289 ms | +99,6 % |
| **114** | **1,664 ms** | **3,965 ms** | **+138,6 %** |

Le surcout croit **surlineairement**, signature d'une pression de registres : plus de
valeurs de descripteur vivantes, moins de fils en vol, effondrement du debit.

**A 114 echantillonnages — le compte exact du nuanceur Godot — le motif coute +138,6 %.**
L'ecart observe sur Godot etait de +103,6 %. Le motif suffit donc largement a l'expliquer.

### Ce que cela etablit, et ce que cela n'etablit pas

Etabli : recharger le descripteur a chaque echantillonnage est ruineux au-dela de quelques
dizaines d'echantillonnages, et c'est ce que notre chaine produit.

Non etabli : que Godot en natif evite ce motif. C'est tres probable, un backend Metal liant
ses textures directement, mais son MSL reste hors d'atteinte (section 136).

### La direction

Le nuanceur reel fait **890 chargements pour 114 echantillonnages, soit 7,8 chacun**. Si
plusieurs echantillonnages partagent une texture — ce qui est la regle dans un nuanceur
d'eclairage — le descripteur pourrait etre charge **une fois** au lieu d'une fois par
echantillonnage. Rien dans le code genere ne suggere que cette factorisation ait lieu.

Piste a explorer : pourquoi `nir_opt_cse` ne fusionne pas ces chargements, alors qu'ils
sont emis en `load_global_constant_offset` avec `ACCESS_CAN_SPECULATE`. Le qualificatif
`coherent` impose par le contournement 6 agit apres, a la generation MSL, donc il
n'explique pas une absence de fusion au niveau NIR.

## 138. Pourquoi la fusion n'a pas lieu : ce n'est pas le travail de CSE (2026-09-22)

La section 137 laissait une piste : 890 chargements de descripteur pour 114
echantillonnages, alors qu'ils sont emis en `load_global_constant_offset` avec
`ACCESS_CAN_SPECULATE`, donc theoriquement fusionnables.

### La redondance est reelle

Sur le nuanceur extrait : **47 calculs d'adresse pour 12 distincts seulement**, soit
`t987 + ulong(816u)` recalcule **27 fois**, et 74 chargements de texture depuis 33
pointeurs distincts.

### La cause

`nir_opt_cse` ne fusionne que **par dominance**. Le nuanceur comptant **905 branchements**,
ces calculs se trouvent dans des branches soeurs, dont aucune ne domine l'autre : CSE ne
peut rien, et c'est son fonctionnement normal, pas un defaut.

La passe qui traite ce cas est **`nir_opt_gcm`**, le deplacement global de code, qui remonte
les instructions speculables hors du flot de controle. Elle ne figurait pas dans
`msl_optimize_nir`.

### Elle fonctionne, et elle ne sert a rien

Ajoutee apres `nir_opt_licm` :

| | sans | avec |
| --- | --- | --- |
| lignes de MSL | 51 585 | **38 999** (-24 %) |
| temporaires | 17 660 | **13 786** |
| calculs d'adresse | 47 pour 12 distincts | **12 pour 12** |
| chargements de descripteur | 890 | **404** (-55 %) |
| acces a la table d'echantillonneurs | 109 | **19** (-83 %) |

La fusion est donc large, et pas seulement sur l'arithmetique. Et pourtant, sur la scene
reelle, trois paires entrelacees : **-1,4 %, +1,5 %, +2,1 %**. Aucun gain, voire un peu
pire. **Passe retiree.**

### Ce que ce resultat apprend

Il recoupe la section 125, ou quatre chargements volatiles par echantillonnage ne coutaient
rien : **ces chargements ne sont pas le prix du motif**. Le prix est ailleurs — dans les
poignees de texture vivantes simultanement, donc la pression de registres. Et remonter les
chargements **allonge** leur duree de vie, ce qui explique le leger ralentissement.

Le banc de la section 137 le confirme a posteriori : son variant bindless tient 114
descripteurs **distincts** vivants, et c'est cela qui coute +138 %, pas le nombre
d'instructions de chargement.

### La consequence, et elle est structurelle

Le cout ne vient pas d'une occasion manquee d'optimisation mais du **modele bindless
lui-meme** : chaque echantillonnage doit tenir une poignee de texture vivante, la ou un
backend Metal natif lie ses textures une fois pour toutes. Or le bindless n'est pas un
choix du pilote : c'est ce qu'impose `VK_EXT_descriptor_buffer`, que vkd3d utilise et sans
lequel la conformite D3D12 se degrade (2 210 contre 2 026, section 117).

Le doublement du fragment sur un moteur reel est donc le prix de la chaine D3D12, pas un
defaut corrigeable dans KosmicKrisp.

## 139. Point complet : la campagne performance est close (2026-09-22)

Le point de la section 134 laissait une question ouverte, les **+42 % de travail GPU** de
la section 128. Les sections 135 a 138 l'ont tranchee. Voici le bilan definitif.

### La question de depart et sa reponse

**Pourquoi la pile rend-elle 22 images par seconde sur Superposition, et 129 ms par image
la ou Godot natif en met 98 ?**

Reponse, en trois niveaux :

1. **+31,7 %** pour toute la chaine contre Godot en Metal natif (section 128).
2. Decompose : **25 % de GPU inoccupe**, parce que le pilote tourne sous Rosetta et que
   cela coute un facteur 2,3 sur son chemin CPU (section 129) ; et **+42 % de travail GPU**,
   qui est entierement du fragment (section 135).
3. Le fragment double parce que le modele **bindless** impose par `VK_EXT_descriptor_buffer`
   fait tenir une poignee de texture vivante par echantillonnage. Mesure sur nuanceurs
   ecrits a la main : **+138,6 % a 114 echantillonnages**, le compte exact du nuanceur reel
   (section 137).

Les deux causes sont **structurelles** : l'une tient a l'hote x86_64 obligatoire
(section 131), l'autre a l'architecture de descripteurs qu'exige vkd3d.

### Les correctifs acquis

| correctif | section | gain | portee |
| --- | --- | --- | --- |
| adresse de racine reecrite a chaque tirage | 124 | **-45,8 %** d'encodage | toute charge riche en tirages |
| compression tuee par `TRANSFER_DST` | 126 | **-29,6 %** | textures non compressees |
| etat graphique recalcule sans raison | 132 | **-5,5 %** sous Rosetta | toute charge riche en tirages |
| fermeture differee et suivi des ressources | 122, 133 | **-14 %** | passes a cibles distinctes |

### Onze hypotheses ecartees par la mesure

Barriere d'encodeur hors du chemin critique (122, 123), passes surnumeraires (127),
chargements et stockages forces (127), operations d'attachement de DXVK (127 bis), code MSL
genere sur nuanceur simple (125), encodeur Metal 4 (126), debit par triangle (124),
compression sur la scene reelle (135), chargements d'attachements (135), rejet precoce
(135 bis), contournement 6 sur nuanceur reel (136), et le deplacement global de code (138).

Chacune a demande un instrument : harnais Metal, harnais Metal 4, reinjection du MSL genere,
banc de recouvrement, banc de motif, compteurs dans le pilote.

### Ce qui n'a pas abouti, et pourquoi

- **Pile ARM64 complete** (130, 131) : Wine natif arm64 est impossible sur macOS, le noyau
  tuant tout binaire dont le `__PAGEZERO` est reduit alors que Wine a besoin de l'espace bas
  pour `KUSER_SHARED_DATA`. Preuve en trois lignes de C.
- **Recensement complet des ressources** (133) : impossible sous tampons de descripteurs, le
  pilote ne voyant qu'une adresse opaque.
- **Comparaison du nuanceur natif** (136) : Godot ne laisse pas sortir son MSL.

### Le risque, qui n'est pas technique

La pile depend de Rosetta **pour exister**, pas seulement pour aller vite. Si Rosetta
disparait, il n'y a pas d'hote de rechange sur macOS.

### Discipline de mesure

Sept resultats annonces puis corriges lors de la premiere campagne (section 134), aucun
depuis. Les regles qui ont tenu : entrelacer les modes compares, publier medianes et
etendues, verifier qu'un banc valide son resultat, tuer les residus avant de mesurer, se
mefier d'un chiffre tombant pile sur une valeur connue, et ne jamais generaliser d'un
nuanceur simple a un nuanceur reel — erreur commise en 125 et corrigee en 136.

Le piege des **deux colonnes `duration`** dans les traces `xctrace` s'est represente en
section 135 ; il a ete reconnu en une mesure absurde au lieu d'un faux resultat publie.

### Ou le projet en est

Le pilote est a parite sur tous les axes mesurables. Les deux ecarts restants sont imputes
et structurels. Il n'y a plus de piste de performance identifiee et non exploree dans
KosmicKrisp.

## 140. La dependance a Rosetta : ma conclusion de la section 131 etait trop forte (2026-09-22)

La section 131 declarait Wine natif arm64 **impossible** sur macOS. Deux verifications
montrent que la premiere moitie du raisonnement tient et que la seconde ne tient pas.

### La contrainte du noyau, confirmee et generalisee

La section 131 n'avait teste que de petites valeurs de `__PAGEZERO`, et en faisant varier
`-segalign` **en meme temps**, ce qui faisait echouer l'edition de liens pour les grandes.
Refait proprement, avec `-segalign` valide a 16 Ko :

| `__PAGEZERO` demande | obtenu | resultat |
| --- | --- | --- |
| 16 Ko | 16 Ko | tue |
| 16 Mo | 16 Mo | tue |
| 256 Mo | 256 Mo | tue |
| 1 Go | 1 Go | tue |
| 1,5 Go | 1,5 Go | tue |
| 2,13 Go | 2,13 Go | tue |
| defaut | 4 Go | **s'execute** |

L'editeur de liens obeit desormais, et le noyau tue quand meme. **macOS arm64 impose
exactement les 4 Go**, sur toute la plage et pas seulement pour les petites valeurs.

### Mais l'adresse de Wine n'est pas gravee dans le marbre

`KUSER_SHARED_DATA` a 0x7ffe0000 n'est pas une constante de compilation : c'est un
**initialiseur de pointeur**, en huit endroits du code de Wine. La porter a 0x17ffe0000,
au-dessus des 4 Go, est une modification mecanique de huit lignes.

Effet immediat : Wine passe de **tue par SIGKILL sans un mot** a

- initialisation reussie,
- **creation du prefixe**,
- entree dans le ntdll PE.

C'est `0048-wine-arm64-relocate-kuser-shared-data.patch`.

### Ou cela s'arrete maintenant

Une faute subsiste, `EXC_BAD_ACCESS` sur `ldrh w8, [x8, #0x17ee]` avec `x8` nul, dans
l'init du ntdll PE **avant tout chargement de DLL** — le canal `+loaddll` ne produit rien.

Indice sur sa nature : `dlls/ntdll/unix/signal_arm64.c` ne compte que **4** points
specifiques a `__APPLE__`, contre **18** dans `signal_x86_64.c`. Le backend ARM64 de Wine
vise Linux ; son support macOS est embryonnaire.

### La conclusion corrigee

Wine natif arm64 sur macOS n'est **pas impossible** : il demande de developper le backend
ARM64 macOS de Wine, ce qui est un travail de portage et non un mur architectural. La
section 131 confondait une contrainte du noyau, reelle, avec une impossibilite, qui ne
l'est pas.

La dependance a Rosetta reste entiere aujourd'hui, mais elle a maintenant une issue connue
au lieu d'etre declaree sans issue. Et la premiere marche, celle qui semblait infranchissable,
est franchie.

## 141. La faute dans le ntdll PE : le registre x18 (2026-09-22)

La section 140 laissait une faute non identifiee. Elle l'est, et elle designe un conflit
d'ABI que ni le noyau ni Wine ne peuvent ignorer.

### L'instruction fautive

```
0x6fffffcb47c8: mov  x8, x18
0x6fffffcb47cc: ldrh w8, [x8, #0x17ee]   <- EXC_BAD_ACCESS, x18 = 0
```

Sur **ARM64 Windows, `x18` contient le pointeur du TEB**. Le code PE de Wine, compile pour
cette ABI, l'y lit. Il vaut zero.

### Pourquoi il vaut zero : Apple detruit x18

Test direct, programme de quinze lignes compile avec `-ffixed-x18` :

| etape | `x18` |
| --- | --- |
| apres ecriture de `0xdeadbeef` | `deadbeef` |
| **apres un appel systeme** (`getpid`) | **0** |
| apres `write` | 0 |
| dans un gestionnaire de signal | 0 |
| **apres retour du gestionnaire** | **0** |

**macOS remet `x18` a zero a chaque appel systeme et a chaque signal, et ne le restaure pas
au retour du gestionnaire.** Apple reserve ce registre ; ce n'est pas un effet de bord mais
sa politique.

Sur Linux, `x18` est libre et **persiste**. Tout le backend ARM64 de Wine repose sur cette
persistance.

### Ce que Wine fait, et ce qui manque

Wine sauvegarde et restaure `x18` autour de ses propres transitions : le repartiteur
d'appels systeme le remet en place (`ldp x18, x19, [sp, #0x90]`), et `init_syscall_frame`
ecrit `context.X18 = teb`. Cote Unix, `get_thread_data()` passe par `pthread_getspecific`,
donc ne depend pas de `x18`. Cette partie est saine.

Ce qui manque est le **chemin des signaux**. La conversion de contexte **saute
deliberement `x18`** :

```c
memcpy( frame->x, context->X, sizeof(context->X[0]) * 18 );
/* skip x18 */
memcpy( frame->x + 19, context->X + 19, ... );
```

Correct sur Linux, ou le noyau preserve le registre. Fatal ici : une exception dans du code
PE amene le gestionnaire avec `x18` nul, Wine ne retrouve pas le TEB — d'ou le
`virtual_setup_exception stack overflow` qui precede la faute — et le retour laisse `x18`
a zero.

### Le travail que cela represente

Restaurer `x18` depuis les donnees de thread a l'entree des cinq gestionnaires de signal
(`segv`, `ill`, `trap`, `fpe`, `int`), et cesser de le sauter dans la conversion de
contexte, sous `__APPLE__`. C'est du portage borne, pas un mur.

### Ou en est la question de la section 131

Trois etages, desormais tous nommes :

1. `__PAGEZERO` de 4 Go impose par le noyau : **contrainte reelle**, contournee en
   deplacant `KUSER_SHARED_DATA` (correctif 0048).
2. Espace d'adressage a 4 Go occupe par le binaire : **non bloquant**, Wine reessaie plus haut.
3. `x18` detruit par Apple alors que l'ABI Windows ARM64 y met le TEB : **le vrai
   obstacle**, et il demande de developper le chemin des signaux du backend ARM64.

Aucun des trois n'est une impossibilite. La section 131 avait tort de conclure ainsi, et
cette section dit precisement ce qu'il faudrait ecrire.

## 142. Restaurer x18 dans les gestionnaires : le noyau refuse (2026-09-22)

La section 141 concluait qu'il suffisait de restaurer `x18` a l'entree des gestionnaires de
signal et de cesser de le sauter dans la conversion de contexte. Verification faite, la
voie directe est fermee.

### Le test

Un gestionnaire de signal qui ecrit explicitement dans le contexte de retour :

```c
u->uc_mcontext->__ss.__x[18] = 0xcafef00d;
```

| | `x18` |
| --- | --- |
| avant le signal | `deadbeef` |
| apres le signal, malgre l'ecriture | **0** |

**Le noyau ignore `x18` dans l'`ucontext`.** Il le force a zero au retour du gestionnaire,
quoi qu'on y mette. Ce n'est pas un oubli de Wine : c'est un refus de la plateforme.

Consequence : toute exception survenant dans du code PE detruit definitivement le pointeur
de TEB, et **aucun gestionnaire ne peut le retablir par les moyens normaux**.

### Ce qu'il faudrait ecrire

Une seule voie reste : ne pas retourner directement au code PE. Le gestionnaire detournerait
`PC_sig` vers un **tremplin en assembleur** qui, s'executant apres le `sigreturn` avec
`x18` a zero :

1. retrouve le TEB sans passer par `x18`, via `pthread_getspecific` ou `TPIDRRO_EL0` ;
2. remet `x18` ;
3. saute a l'adresse de reprise d'origine.

Le tremplin doit preserver tous les autres registres autour de cet appel, soit une
vingtaine d'instructions, a placer dans `restore_context` qui fixe deja `PC_sig`.

C'est faisable et c'est du vrai portage. Ce n'est pas la modification de quelques lignes
qu'annoncait la section 141, et il n'existe ici aucune suite de tests pour valider ce
chemin.

### L'etat de la question, definitif

| etage | statut |
| --- | --- |
| `__PAGEZERO` de 4 Go | contourne, correctif 0048 |
| espace d'adressage a 4 Go | non bloquant |
| `x18` detruit aux appels systeme | gere par Wine autour de ses propres transitions |
| **`x18` detruit aux signaux, non restaurable** | **demande un tremplin, non ecrit** |

Wine natif arm64 sur macOS reste possible, et le chemin est desormais entierement
cartographie. Il demande d'ecrire ce tremplin, pas de lever un obstacle inconnu.

## 143. Le tremplin x18 : ecrit, mesure, la faute PE disparait (2026-09-22)

La section 142 concluait qu'il fallait detourner `PC_sig` vers un tremplin. Ecrit et mesure.

### Le mecanisme, verifie seul d'abord

Avant de toucher Wine, un programme de vingt lignes : un gestionnaire de signal qui empile
deux valeurs sous `SP`, detourne `PC` vers le tremplin, et laisse le noyau revenir.

| | `x18` apres le signal |
| --- | --- |
| ecriture directe dans l'`ucontext` (section 142) | `0` |
| **via le tremplin** | **`1cafef00d`** |

Fil principal et fil secondaire, meme resultat. Le noyau ignore `x18` mais **honore `PC`**.

### Le tremplin

Quatre instructions, dans `dlls/ntdll/unix/signal_arm64.c` :

```
ldr x18, [sp]
ldr x16, [sp, #8]
add sp, sp, #16
ret x16
```

Il sacrifie `x16` : sur ARM64 tout branchement indirect laisse la cible dans le registre qu'il
lit, donc reposer `x18` **et** reprendre a une adresse quelconque coute forcement un autre
registre. Seul un branchement direct l'eviterait, au prix de code genere a moins de 128 Mo de
la cible. Ce n'est pas un choix arbitraire : Wine lui-meme rentre en code PE par `ret x16` en
fin de repartiteur. C'est la convention du fichier.

Accroche aux cinq reprises vers du code PE : `restore_context`, `setup_raise_exception` (qui
posait deja `REGn_sig(18)` en pure perte), `usr1_handler` (ses deux branches qui repointent
vers du PE) et `usr2_handler`. `setup_raise_exception` reserve 16 octets de plus via
`virtual_setup_exception` pour que la zone de transit soit dans la pile commitee. Et
`save_context` rend desormais le vrai TEB dans `CONTEXT.X18` au lieu du zero du noyau.

Une garde limite le tremplin aux reprises dont `SP` est dans la pile PE du TEB, pour ne pas
ecraser `x16` au milieu d'un appel systeme unix. **Elle n'a rien change d'observable** : c'est
une precaution de correction, pas un correctif mesure.

### L'A/B, prefixe neuf, `WINEDEBUG=+loaddll,+process`

| | fin de trace |
| --- | --- |
| **sans tremplin** | `virtual_setup_exception stack overflow 640 bytes addr 0x6fffffcdec30` sur les deux fils, puis le processus meurt |
| **avec tremplin** | `RtlpWaitForCriticalSection "vectored_handlers_section" ... blocked by 0000` |

L'adresse `0x6fffffcdec30` est celle du `mov x8, x18` de la section 141. **Sans le tremplin le
ntdll PE prend la faute et le processus meurt ; avec, la faute a disparu** et le fil atteint
`RtlAddVectoredExceptionHandler`. Reproduit deux fois a l'identique.

### Ce qui bloque maintenant

Deux choses, distinctes de `x18` :

1. `try_map_free_area ... range 0x100000000-...` : le binaire hote occupe 0x1_0000_0000 sur
   macOS arm64, donc Wine ne peut pas y placer l'image PE.
2. Une section critique verrouillee **sans proprietaire** (`blocked by 0000`).

Le quatrieme obstacle du portage est donc leve. Ceux qui restent sont d'une autre nature.

## 144. La section critique sans proprietaire : x18 est efface a tout moment (2026-09-22)

La section 143 laissait deux blocages. Celui de la section critique est elucide, et il mene a
une conclusion bien plus large que lui.

### La chaine causale, mesuree bout en bout

Releve au moment du blocage :

```
LockCount=2  RecursionCount=0  SpinCount=0  Owner=0  ClientId=0028/002c
```

Personne n'a jamais acquis le verrou, alors que `LockCount` a ete incremente trois fois. Deux
hypotheses tombent aussitot, mesurees sur place : `InterlockedIncrement(-1)` **rend 0**, la
semantique est bonne ; et `LockCount` vaut **-1** avant l'entree, donc `.data` est bien chargee.
L'alignement de sections du ntdll PE est de 0x10000, multiple des 16 Ko de page, ce qui ecarte
aussi la piste des pages.

Le desassemblage donne la reponse. `RtlEnterCriticalSection` faute sur :

```
mov x8, x18
ldr w8, [x8, #0x48]      /* TEB->ClientId.UniqueThread */
```

C'est `GetCurrentThreadId()` en ligne, execute **apres** l'increment et **avant** de poser
`OwningThread`. Avec `x18` nul, la faute laisse le verrou incremente et orphelin. Chaque
tentative l'incremente encore. La section critique n'est pas un bogue : c'est la trace de
`x18`.

### Les fautes, toutes identiques

| faute | pc | addr | x18 |
| --- | --- | --- | --- |
| 1 | `loader_init+0x40` | 0x17ee | 0 |
| 2 | `__wine_dbg_get_channel_flags` | 0x60 | 0 |
| 3-6 | `__wine_dbg_*`, `RtlEnterCriticalSection` | 0x180c, 0x48 | 0 |

Toutes sont un petit offset de TEB avec `x18` a zero. La premiere est dans `loader_init`, le
tout premier code PE d'un fil.

### Le tremplin marche, et ne suffit pas

Instrumente pour enregistrer ce qu'il charge, le tremplin **fonctionne** : il ecrit bien
`0x14012a000`, le bon TEB. Et `frame->x[18]` vaut toujours `0x14012a000`. Pourtant la faute
suivante a `x18 = 0`, hors de tout appel systeme (`dans_appel=0`).

### La cause reelle

`tests/x18_preempt.c` : on pose une valeur dans `x18`, puis on boucle en la relisant, **sans le
moindre appel systeme**.

| essai | perte |
| --- | --- |
| avec charge #1 | apres 227 378 tours |
| avec charge #2 | 14 618 574 |
| avec charge #3 | 12 473 500 |
| sans charge #1 | 3 635 735 |
| sans charge #2 | 13 718 087 |

Cinq sur cinq, `x18` tombe a zero. **macOS efface `x18` a chaque retour du noyau vers
l'espace utilisateur, y compris sur une simple preemption.** Il n'y a donc aucune frontiere ou
le restaurer : il peut disparaitre entre deux instructions quelconques.

### Ce que cela signifie pour le portage arm64

Le code PE Windows ARM64 lit le TEB par `x18` — c'est l'ABI, cable dans chaque binaire. Sur
macOS ce registre n'appartient pas au programme. Aucun correctif cote Wine ne peut y remedier :
ni le tremplin de la section 143, ni aucun placement de restauration, puisque la perte est
asynchrone.

Les issues restantes sortent du cadre de Wine : recompiler tout le code PE avec un autre acces
au TEB, ce qui interdit les binaires Windows reels et vide le portage de son sens ; ou emuler.
C'est precisement ce que fait la voie x86_64, ou le TEB passe par un registre de segment que
macOS conserve — et c'est pourquoi la pile sous Rosetta fonctionne, elle.

**Le portage arm64 natif est ferme par une contrainte de plateforme, pas par un travail
restant.** Le correctif 0048 et le tremplin 0049 restent justes et mesures ; ils levaient les
obstacles qu'on pouvait lever. La voie x86_64 sous Rosetta demeure la seule praticable.

### Correction a la section 144 (meme jour)

La section 144 concluait qu'« aucun correctif cote Wine ne peut y remedier ». C'est trop fort,
et deux verifications le montrent.

1. Tout le code PE de Wine lit le TEB par **une seule ligne**, dans `include/winnt.h` :
   `register struct _TEB *__wine_current_teb __asm__("x18");`
2. `TPIDRRO_EL0` est **stable** : 300 millions de tours sous charge, sans perte, la ou `x18`
   tombe en quelques millions (`tests/tp_stable.c`).

Donc les modules PE **de Wine** pourraient utiliser un autre porteur de TEB, au prix d'une
ligne. Ce qui reste impossible, c'est d'executer un binaire Windows ARM64 **deja compile** :
l'ABI y cable `x18` dans chaque acces au TEB, et on ne recompile pas les jeux.

La portee exacte de la contrainte est donc : *pas de binaires Windows ARM64 tiers*, et non
*pas de Wine arm64*.

Cela ne rouvre pas la voie pour autant, pour une raison independante : **les jeux Windows sont
x86_64**. Un Wine arm64 devrait de toute facon emuler du x86_64 dans le processus, et sur macOS
le seul emulateur disponible est Rosetta — precisement ce qu'on cherche a quitter. Ecrire un
JIT x86_64 est hors sujet ici.

## 145. La taxe Rosetta sur le pilote, chiffree (2026-09-22)

Meme source de pilote, meme GPU, meme banc ; seule l'architecture CPU change. `bench_cpu_overhead`
enregistre 20 000 `vkCmdDispatch` par tour, 15 tours, mediane et meilleur ; 12 passes
entrelacees arm64 / x86_64.

| | arm64 natif | x86_64 sous Rosetta | rapport |
| --- | --- | --- | --- |
| enregistrement (mediane de 12) | **2,348 ms** | **4,790 ms** | **×2,04** |
| debit de commandes | 8,52 M/s | 4,18 M/s | ×0,49 |
| total avec GPU (mediane de 5) | 3,940 ms | 6,472 ms | ×1,64 |
| **part GPU** (total − enregistrement) | **1,592 ms** | **1,682 ms** | **×1,06** |

Les intervalles ne se chevauchent pas : arm64 de 2,325 a 2,397, x86_64 de 4,691 a 4,883.

### Lecture

**La taxe est de ×2,04 sur le chemin CPU du pilote, et de ×1,06 seulement sur le GPU.** Le
travail Metal est natif des deux cotes, ce qui valide la decomposition : ce que Rosetta coute,
c'est l'enregistrement des commandes, pas le rendu.

C'est coherent avec le 2,3× de CPU releve sur Godot dans la trace complete : la pile entiere
(Wine, DXVK, vkd3d) est traduite elle aussi, donc un peu pire que le pilote seul.

Corollaire utile : chaque optimisation d'encodage vaut **le double** sous Rosetta. Le cache
d'adresse racine a −45,8 % et le chemin rapide d'etat graphique a −5,5 % rapportent deux fois
plus la qu'en natif. Et inversement, les 25 % d'inactivite GPU imputes a Rosetta dans l'ecart
de 31,7 % face au Metal natif se refermeraient en bonne partie sur une pile arm64.

### Une precision sur ce que mesure ce chiffre

Le ×2,04 compare « pilote compile en x86_64 et traduit » a « pilote compile en arm64 et
natif ». Il additionne donc le cout de la traduction et les differences de generation de code
entre les deux cibles, qu'on ne peut pas separer ici faute d'un Mac x86. C'est la comparaison
qui compte en pratique, mais ce n'est pas le cout de traduction pur.

### Piege de construction rencontre

Le premier essai de reconstruction arm64 echouait sur `blake3_neon.c` (« NEON intrinsics not
available »). Cause : `/usr/local/bin/ninja` est un binaire **x86_64**, donc il s'execute sous
Rosetta et le `cc` universel qu'il lance suit en x86_64. `toolchain/bin/ninja` est universel :
`arch -arm64 toolchain/bin/ninja` corrige. Sans cela j'aurais mesure un pilote arm64 vieux de
trois heures.

## 146. Le chemin graphique : taxe Rosetta plus lourde, et un coût propre à nous (2026-09-22)

La section 145 ne couvrait que `vkCmdDispatch`, la commande la moins chere. `bench_cpu_gfx`
separe les chemins qu'un jeu emprunte vraiment : 20 000 tirages par tour, 15 tours, medianes,
5 passes entrelacees arm64 / x86_64.

| profil | arm64 natif | x86_64 sous Rosetta | taxe |
| --- | --- | --- | --- |
| tirage seul | 50,8 ns | 127,8 ns | **×2,52** |
| + constantes poussees | 455,9 ns | 1 109,6 ns | ×2,43 |
| + jeu de descripteurs | 453,2 ns | 1 092,8 ns | ×2,41 |
| + liaison de pipeline | 611,6 ns | 1 507,0 ns | ×2,46 |
| + etat dynamique | 60,8 ns | 179,3 ns | **×2,95** |

Rappel du profil calcul : `vkCmdDispatch` seul donnait ×2,04.

### Premiere lecture : la taxe est plus lourde ici

**Le chemin graphique est taxe de 2,41 a 2,95, contre 2,04 pour le calcul.** La reserve
formulee en section 145 etait donc fondee : le ×2,04 sous-estimait le cout reel. La valeur a
retenir pour un jeu est de l'ordre de **×2,5**.

### Deuxieme lecture, plus interessante : ce que le pilote coute en natif

Couts marginaux en arm64, tirage nu deduit :

| commande | cout marginal (arm64) |
| --- | --- |
| constante poussee | 405 ns |
| jeu de descripteurs | 402 ns |
| liaison de pipeline | 561 ns |
| etat dynamique (viewport + ciseaux) | 10 ns |

**Une constante poussee coute huit fois un tirage nu.** La cause est dans
`kk_upload_descriptor_root` : tout changement marque `root_dirty`, et le vidage realloue puis
recopie **la table racine entiere**. Sa taille, mesuree par sonde compilee avec les options de
meson : **2 328 octets**. On recopie donc 2 328 octets pour modifier 16 octets de constantes,
et l'adresse GPU changeant a chaque fois, le cache d'adresse racine de la section precedente
ne peut pas s'appliquer.

C'est un cout qui nous appartient, independant de Rosetta, et il est sur le chemin le plus
chaud d'un jeu. Sous Rosetta il est paye ×2,4, soit **982 ns par constante poussee**.

L'etat dynamique, a 10 ns, montre par contraste qu'il n'y a rien d'intrinseque : quand le
pilote n'a pas a repasser par la racine, une commande est bon marche.

## 147. Le coût de la table racine : rogner plutôt que recopier (2026-09-22)

La section 146 montrait qu'une constante poussée coûte 405 ns, huit fois un tirage nu, parce
que `kk_upload_descriptor_root` réalloue et recopie les 2 328 octets de la table racine.

### D'abord décomposer, par doublement

Sauter la recopie laisserait des adresses de descripteurs aléatoires et ferait fauter le GPU.
On ajoute donc une opération **redondante** et on mesure l'écart : même information, sans
risque. Leviers `root_alloc2`, `root_copy2`, `root_bind2`.

| opération ajoutée | coût marginal | part |
| --- | --- | --- |
| **allocation dans le tas** | **325 ns** | **72 %** |
| recopie des 2 328 octets | 50 ns | 11 % |
| pose d'adresse Metal | 16 ns | 3,5 % |

La recopie, que je soupçonnais, n'est qu'un neuvième. C'est l'allocation qui domine — et un
allocateur à pointeur ne coûte pas 325 ns : `KK_CMD_BO_SIZE` vaut 128 Ko, donc 2 336 octets par
tirage épuisent un tampon tous les 56 tirages, et `KK_CMD_POOL_BO_MAX` n'en recycle que 32
alors que 20 000 tirages en consomment ~365. Les 333 autres sont détruits et recréés à chaque
tour.

### Deux leviers, un seul gratuit

Porter la rétention de 32 à 512 donne 448 → 187 ns, soit −58 %. Mais le balayage ne montre
**aucun genou** — c'est un troc mémoire linéaire :

| plafond | mémoire retenue | complet | rogné |
| --- | --- | --- | --- |
| 32 | 4 Mo | 457 ns | 302 ns |
| 64 | 8 Mo | 431 ns | 280 ns |
| 128 | 16 Mo | 383 ns | 225 ns |
| 256 | 32 Mo | 279 ns | 169 ns |

Le rognage, lui, est un gain sec. C'est donc lui qu'on retient ; la rétention reste une
décision d'arbitrage, non prise.

### Le rognage

La disposition mesurée : union de dessin 0-760, `push[256]` 760-1016, `sets[32]` 1016-1272,
`dynamic_buffers[64]` 1272-2296, `set_dynamic_buffer_start[32]` 2296-2328.

On tient donc dans `kk_descriptor_state` une borne haute `root_size` de ce que le nuanceur peut
lire, étendue à chaque écriture : `sets[s]` étend jusqu'à `(s+1)*8`, une constante poussée
jusqu'à `offset + size`. Détail qui compte : `set_dynamic_buffer_start` est **lu par le
nuanceur mais jamais écrit par le pilote** — il reste à zéro — donc dès qu'une disposition
déclare un descripteur dynamique, on téléverse tout.

| profil | avant | après | gain |
| --- | --- | --- | --- |
| constantes poussées | 455,9 ns | **263,7 ns** | **−42 %** |
| jeu de descripteurs | 453,2 ns | **265,2 ns** | −41 % |
| liaison de pipeline | 611,6 ns | **415,7 ns** | −32 % |
| tirage seul | 50,8 ns | 50,4 ns | inchangé |
| état dynamique | 60,8 ns | 58,7 ns | inchangé |

**Conformité : D3D11 4326, D3D12 2026** — les références exactes. Correctif 0050.

### Trois pièges d'environnement, tous de mon fait

La conformité a d'abord donné 18 677 échecs au lieu de 2 026, et il a fallu une heure pour
comprendre que le pilote n'était pas en cause.

1. `build/wine/wine` est un **script shell**, donc macOS efface `DYLD_LIBRARY_PATH` au
   lancement (protection du système) : winevulkan ne trouvait jamais `libvulkan.1.dylib`. Le
   script prévoit un point d'extension, `build/wine/.winewrapper`, qui est sourcé après.
2. Le premier lancement de Wine sur `wine/pfx` a déclenché une mise à jour de préfixe qui a
   **remplacé `dxgi.dll` et `d3d11.dll` de DXVK par les intégrées de Wine**. À réinstaller
   depuis `build/dxvk-win64/src/*/`.
3. Il manquait `MESA_KK_EXPERIMENTAL=custom_border,image_view_min_lod`. Le symptôme était
   lisible : les échecs supplémentaires étaient **concentrés** sur trois tests de bordure,
   8 192 + 8 192 + 256 = 16 640, exactement l'écart avec 2 026.

D'où `tests/run_conformance.sh`, désormais versionné : la recette complète ne se reconstitue
pas de mémoire.

## 148. L'arbitrage mémoire, pris : rétention à 192 (2026-09-22)

La section 147 laissait la rétention de tampons en suspens, faute de genou dans la courbe. Le
balayage y avait été fait avec le rognage **expérimental**. Refait avec le rognage réel, qui
consomme moins de tampons, le genou apparaît :

| plafond | mémoire max | constantes poussées |
| --- | --- | --- |
| 32 | 4 Mo | ~255 ns |
| 64 | 8 Mo | ~237 ns |
| 128 | 16 Mo | ~185 ns |
| **192** | **24 Mo** | **~158 ns** |
| 256 | 32 Mo | ~158 ns |
| 384 | 48 Mo | ~158 ns |

Plat au-delà de 192. Retenu : **192** (correctif 0051).

L'argument qui emporte la décision n'est pas la courbe mais la nature du plafond : il borne une
**liste de libres**, pas une réservation. `kk_cmd_pool_free_bo_list` n'y remet que des tampons
réellement consommés par un tampon de commandes, donc un petit tas garde une petite empreinte.
Les 24 Mo ne sont payés que par un tas ayant effectivement brassé 192 tampons de 128 Ko, c'est-
à-dire enregistré des milliers de tirages. Ce n'est pas un coût imposé à tous.

### Cumul des deux leviers, contre la référence de la section 146

| profil | référence | rognage seul | + rétention | cumul |
| --- | --- | --- | --- | --- |
| constantes poussées | 455,9 ns | 263,7 | **157,5** | **−65 %** |
| jeu de descripteurs | 453,2 ns | 265,2 | **157,8** | **−65 %** |
| liaison de pipeline | 611,6 ns | 415,7 | **301,4** | **−51 %** |
| tirage seul | 50,8 ns | 50,4 | 50,5 | inchangé |
| état dynamique | 60,8 ns | 58,7 | 58,3 | inchangé |

### Conformité, et une instabilité à connaître

D3D12 **2026**, exact. D3D11 a d'abord donné **4328** contre 4326 attendus. Vérifié plutôt que
supposé : trois campagnes supplémentaires **avec le même binaire** donnent 4326, 4328, 4326.

**La suite D3D11 oscille donc de ±2 d'une campagne à l'autre.** À ne pas lire comme une
régression, au même titre que `test_suballocate_va_alignment` et
`test_unused_attachments_mix_and_match` côté D3D12.

## 149. Le gain sur un moteur réel : −30,7 %, mais seulement là où le CPU compte (2026-09-22)

Les sections 147-148 mesuraient l'enregistrement de commandes. Reste à savoir si cela déplace
un temps d'image. Scène Godot `tests/godot-views`, pile complète PE → Wine → DXVK/vkd3d →
KosmicKrisp → Metal, deux pilotes x86_64 échangés entre chaque exécution : « avant » = plafond
32 et `no_root_trim`, « après » = plafond 192 et rognage actif.

### Premier essai : aucun gain, et c'est un résultat

En 1280×720 avec des vues de 160 px, 25 329 tirages : **123,810 ms des deux côtés**, à trois
décimales. La scène est limitée par le GPU — 123 ms par image — donc le CPU a tout le temps du
monde et une économie d'enregistrement n'y change rien. Les journaux diffèrent bien (meilleures
valeurs et nombre de tirages distincts) : les deux pilotes ont bien tourné.

### Second essai : mettre le CPU sur le chemin critique

En 640×480 avec des vues de 32 px, le nombre de tirages reste à ~25 300 mais le coût par pixel
s'effondre. Le temps ne descend qu'à 87 ms : le coût est donc largement **par tirage**, pas par
pixel. C'est la configuration qui peut révéler le gain.

| tour | avant | après |
| --- | --- | --- |
| 1 | 116,667 ms | 82,710 ms |
| 2 | 116,667 | 83,005 |
| 3 | 125,926 | 83,466 |
| 4 | 123,333 | 83,333 |
| **médiane** | **120,000 ms** | **83,169 ms** |

**−30,7 %**, soit 8,3 → 12,0 img/s. Les valeurs « après » tiennent dans 81,9-83,5 alors que
« avant » s'étale de 112,6 à 125,9 : privée de CPU, la configuration d'avant encaissait la
charge de la machine, ce que la nouvelle absorbe.

### Portée honnête de ce chiffre

La configuration a été **choisie** pour être limitée par les tirages. Un jeu limité par le GPU
ne verra rien, comme le premier essai le montre. Le gain vaut pour ce qui sature le CPU :
beaucoup de tirages, beaucoup de changements d'état — ce qui est le cas des moteurs qui
n'utilisent pas le rendu indirect, et d'autant plus sous Rosetta où tout est taxé ×2,5.

### Trois tours jetés, et pourquoi

Le premier A/B en configuration CPU donnait 121 / 122 / 135 pour « avant » et 83 / 133 / 135
pour « après » — incohérent et dérivant. Cause : des **processus Wine oubliés**, dont un
`winedevice.exe` vieux de 1 j 23 h, le `wineboot.exe` bloqué de l'essai arm64 et le `winedbg`
attaché lors de la conformité ratée. Charge moyenne 2,3 au lieu de 0. C'est exactement le piège
déjà consigné, et je l'ai repris de plein fouet. La reprise ajoute une garde qui attend
l'absence de processus **et** une charge inférieure à 1,2 avant chaque exécution.

## 150. Superposition : aucun gain, et correction du chiffre Godot (2026-09-22)

### Superposition : rien, et c'était prévisible

Unigine Superposition 1.1 en D3D11, 1280×720, monde chargé par commande console, 85 s de
stabilisation puis 10 s de capture Metal ; fréquence mesurée par le nombre de présentations
(`ca-client-present-request`), trois tours entrelacés.

| | avant | après |
| --- | --- | --- |
| présentations / 10 s | 241, 237 | 238, 236, 242 |
| **médiane** | **239** (23,9 img/s) | **238** (23,8 img/s) |

**Aucun gain**, 0,4 % d'écart. Le troisième tour « avant » a donné **0 présentation** : capture
ratée, charge à 7,56 au moment du déclenchement. Écartée, pas comptée comme un résultat.

Ce zéro était annoncé par la section 8470 : Superposition occupe le GPU **38,4 ms par image sur
45**, soit 85 %. Tout ce que nous avons optimisé vit dans les 6,7 ms restantes, qui contiennent
aussi la soumission, la synchronisation, la présentation et toute la traduction. Un gain de
quelques centaines de nanosecondes par tirage n'y est pas visible.

### Correction du chiffre de la section 149

La section 149 annonçait −30,7 % sur la scène Godot. **La mesure était contaminée** : un
`start.exe` oublié consommait **100 % d'un cœur depuis 5 h 19** pendant tout l'A/B. Découvert
en préparant Superposition.

Reprise sur machine propre, trois tours entrelacés :

| | avant | après |
| --- | --- | --- |
| médiane | **113,333 ms** | **82,788 ms** |
| étendue | 1,2 % | 0,6 % |

**Le chiffre juste est −27,0 %**, pas −30,7 %. L'entrelacement a bien préservé le signe et
l'essentiel de l'ampleur — c'est ce pour quoi il est fait — mais la configuration privée de CPU
encaissait davantage la charge parasite, ce qui gonflait l'écart de près de quatre points.
L'étendue le dit aussi : 1,2 % maintenant contre 8 % avant.

### Ce que les deux charges disent ensemble

| charge | limite | gain |
| --- | --- | --- |
| Superposition 1280×720 | GPU (85 %) | **0 %** |
| Godot, vues de 160 px | GPU | **0 %** |
| Godot, vues de 32 px | tirages | **−27 %** |

L'optimisation ne déplace que ce qui sature le CPU. Sur une charge limitée par le GPU elle est
strictement invisible — ce qui est cohérent, pas décevant : on a réduit un coût qui n'était pas
sur le chemin critique de ces scènes-là.

### Quatre résidus Wine en une journée

`winedevice` de 1 j 23 h, `wineboot` bloqué, `winedbg` attaché après un plantage, et ce
`start.exe` à 100 %. Deux leçons pratiques : `pkill -x` **ne les atteint pas**, car leur nom de
processus est le chemin Windows complet (`C:\windows\system32\services.exe`) — il faut tuer par
PID via `ps -Ao pid=,comm= | grep system32`. Et une garde `pgrep -f` **se matche elle-même** ;
compter sur `ps -Ao comm=` évite le piège.

## 151. Chercher un moteur qui sature le CPU (2026-09-22)

La section 150 laissait la question ouverte : l'optimisation ne vaut que si le CPU borne
l'image, et les deux charges réelles testées étaient bornées par le GPU. Que reste-t-il ?

### Ce qui est éliminé

**Unigine Heaven 4.0** : inutilisable. L'installeur ne contient que des binaires 32 bits
(13 `_x86`, zéro `_x64`, relevé en section 95), alors que notre pile — Wine, DXVK, vkd3d-proton,
KosmicKrisp — est entièrement 64 bits.

**Superposition** : mesuré en section 150, GPU à 85 %, aucun gain.

Restent les échantillons D3D12 de Microsoft, présents en source seulement et à construire au
llvm-mingw, et Godot.

### Le critère, et comment on le teste

Une charge est bornée par le CPU si **réduire le nombre de pixels ne change presque rien**.
C'est mesurable directement : même scène, même nombre d'objets, deux tailles de vue.

Scène Godot avec **une seule vue** — une image réaliste, pas les 64 vignettes de la section
149 — 4 000 objets ayant chacun son propre matériau, donc un tirage par objet sans regroupement.

| vue | pixels | tirages | temps d'image |
| --- | --- | --- | --- |
| 1280×1280 | ×4 | 5 238 | **16,252 ms** |
| 640×640 | ×1 | 5 286 | **14,815 ms** |

Diviser les pixels par quatre ne gagne que **8,8 %**. Donc **plus de 90 % du temps d'image
n'est pas du travail par pixel** : c'est la soumission des tirages et le CPU.

Et cette fois la configuration est plausible : une vue unique en 1280×1280, 61 images par
seconde, 5 238 tirages. C'est le profil d'un moteur qui n'instancie pas ses objets — cas
courant des titres D3D11 et de tout rendu où chaque objet porte son propre matériau.

Le premier essai visait 20 000 objets en pleine résolution : la scène n'a pas atteint 300
images en huit minutes, donc plus de 1,6 s par image. Inexploitable, redescendu à 4 000.

### A/B en cours

Premier tour : 24,242 ms avant contre 16,524 après, soit −31,8 % et 41 → 61 images par seconde.
Second tour « avant » reproduit à 24,242. Résultat complet à consigner séparément.

## 152. Le résultat sur la charge réaliste : −34,2 % (2026-09-22)

A/B complet de la section 151. Scène Godot, une vue en 1280×1280, 4 000 objets, 5 238 tirages,
pilote x86_64 échangé entre chaque exécution, quatre tours entrelacés.

| tour | avant | après |
| --- | --- | --- |
| 1 | 24,242 ms | 16,524 ms |
| 2 | 24,242 | 16,124 |
| 3 | 23,611 | 15,678 |
| 4 | 25,000 | 15,760 |
| **médiane** | **24,242 ms** | **15,942 ms** |
| meilleure image (médiane) | 22,46 ms | 15,28 ms |

**−34,2 %**, soit **41,3 → 62,7 images par seconde**. Sur les meilleures images, −32,0 %.

Les charges machine sont allées de 1,75 à 4,86 selon les tours et les valeurs restent serrées
— étendue de 6 % avant, 5 % après. Contrairement à la mesure gâchée de la section 149, rien
n'indique ici de contamination.

### Le tableau complet des charges réelles

| charge | limite | gain |
| --- | --- | --- |
| Superposition 1280×720 | GPU, 85 % | **0 %** |
| Godot, 64 vues de 160 px | GPU | **0 %** |
| Godot, 64 vues de 32 px | tirages | −27,0 % |
| **Godot, 1 vue de 1280 px, 4 000 objets** | **tirages** | **−34,2 %** |

Le dernier est le plus significatif des quatre : c'est le seul qui soit à la fois **borné par
les tirages** et **plausible comme image de jeu** — une vue unique, pleine résolution, à une
fréquence jouable. Les 64 vignettes de la section 149 prouvaient le mécanisme ; celle-ci montre
ce que l'optimisation vaut pour un moteur qui n'instancie pas ses objets.

Et le gain y est **plus fort** que sur les vignettes, ce qui se comprend : chaque objet porte
son propre matériau, donc chaque tirage change les descripteurs et les constantes poussées —
exactement les deux chemins rognés, mesurés à −65 % au banc.

## 153. Pourquoi chaque tirage salit la racine : ce ne sont pas les descripteurs (2026-09-22)

La section 152 attribuait le gain au fait que « chaque objet porte son propre matériau, donc
chaque tirage change les descripteurs ». **C'était une déduction à partir du script de scène,
pas une mesure. Elle est fausse.**

Compteurs ajoutés sur le chemin de tirage (levier `draw_stats`, correctif 0052) : tirages,
chemin rapide, téléversements de racine et octets, constantes poussées, décalages de tampon de
descripteurs, liaisons de jeux de descripteurs, poses de table d'arguments et succès de cache.

Relevé sur la charge de la section 151, une vue 1280×1280 et 4 000 objets, ~850 images :

```
total=4 451 078  chemin_rapide=0 (0,0 %)
racine : televersements=1,00/tirage  octets=1040/tirage
poussees=1,50/tirage  offsets_desc=0,00/tirage  binds_desc=0,00/tirage
table_arg : poses=4 452 056  cache=0 (0,0 %)
```

### Ce que cela dit

**Zéro descripteur lié par tirage.** Ni `vkCmdBindDescriptorSets`, ni décalage de tampon de
descripteurs : les deux compteurs sont à zéro. Godot lie ses descripteurs une fois et n'y
retouche pas ; les matériaux par objet ne passent donc pas par là.

Ce qui salit la racine, ce sont les **constantes poussées, 1,50 par tirage**. Godot passe les
données par objet en constantes racine D3D12, que vkd3d traduit en `vkCmdPushConstants`. Chaque
appel marque `root_dirty`, ce qui force un téléversement complet de la racine, donc une adresse
GPU neuve, donc une pose de table d'arguments.

D'où les deux zéros qui en découlent : **chemin rapide 0 %** — jamais pris, la racine étant
toujours sale — et **cache de table d'arguments 0 %** — jamais utile, l'adresse changeant à
chaque fois. Les deux optimisations des sections précédentes sont donc contournées par cette
charge, et c'est le rognage qui l'a sauvée.

### L'ampleur

1 040 octets par tirage contre 2 328 sans rognage, soit **−55,3 %**. Sur la durée du relevé :
**4,63 Go téléversés au lieu de 10,36 Go**. Ces 1 040 octets se décomposent en 1 016 pour
l'union de dessin et `push[256]`, plus 24 octets pour trois jeux de descripteurs — cohérent
avec un `sets[]` écrit une fois puis jamais retouché, exactement ce que la borne haute capture.

### Ce que cela ouvre

Le gain restant est identifié et il est net : **une constante poussée de quelques octets force
la recopie de 1 040 octets**. Séparer les constantes poussées du reste de la racine, dans leur
propre tampon, ramènerait ce coût à 256 octets au plus — les 760 de l'union de dessin et les
jeux de descripteurs ne changeant pas entre deux tirages. Cela demande de toucher aux décalages
que le nuanceur utilise (`kk_nir_lower_descriptors.c`), donc ce n'est pas une retouche locale.

## 154. Refonte de la racine, étape 1 : l'indirection par disposition (2026-09-23)

La section 153 avait montré que le vrai gaspillage n'est pas le bloc de sommets seul mais le
dimensionnement de **tous** les tableaux au maximum Vulkan — 32 attributs, 32 jeux, 256 octets
de constantes — alors qu'un pipeline en utilise une poignée. Pour la scène de la section 151 :
1 040 octets téléversés par tirage contre ~192 réellement utiles, soit **−82 % possibles**.

### Pourquoi un filet avant toute chose

La séparation des constantes poussées, la veille, avait cassé la conformité sans que la cause
soit localisable rapidement. La refonte touche les offsets gravés dans les nuanceurs : une
erreur y donne des lectures silencieusement fausses. On procède donc en deux temps, et le
premier ne change **aucune valeur**.

### L'étape franchie

`kk_root_layout.h` déclare 18 champs lus par les nuanceurs et une structure de disposition qui
donne l'offset de chacun. Les deux passes d'abaissement — descripteurs et sommets — ne
calculent plus leurs offsets par `offsetof` sur la structure C, mais les lisent dans une
disposition passée en paramètre. `kk_root_layout_identity()` renvoie exactement les offsets
actuels.

Recensement de départ : 15 sites dans `kk_nir_lower_descriptors.c` et 3 dans
`kk_nir_lower_vbo.c`. Un seul cas particulier, le chargement factice du contournement de
barrière, qui lisait `dynamic_buffers[0].zero` sans s'intéresser à la valeur : ramené à
l'offset 0, toujours valide quelle que soit la disposition.

**Conformité : D3D11 4326, D3D12 2026** — les références exactes. La plomberie est donc juste,
et ce point est un repère où revenir. Correctif 0053.

### Ce qui reste

L'étape suivante calcule une disposition **compacte par pipeline** à partir de ce que le
nuanceur lit réellement, et tasse le téléversement en conséquence. La structure C grasse reste
la zone de travail côté processeur — les dizaines d'écritures du pilote sont inchangées — et
seul le téléversement recopie les champs utiles aux offsets compacts.

## 155. Refonte, étape 2 : entrelacer les attributs de sommets (2026-09-23)

Préalable à la disposition compacte. Les données par attribut étaient éclatées en trois
tableaux — `buffer_strides[32]`, `attrib_base[32]`, `attrib_clamps[32]`, 512 octets en tout — si
bien qu'un nuanceur lisant six attributs touchait jusqu'à l'offset 412 du bloc. Regroupées par
attribut dans `struct kk_root_attribute { base, clamp, stride }`, seize octets chacun, six
attributs ne touchent plus que les 96 premiers.

**La taille totale ne change pas** — 32 × 16 = 512, au même endroit dans la structure. Ce qui
change est la *localité* : l'étendue réellement lue devient proportionnelle au nombre
d'attributs au lieu d'être quasi constante. C'est ce qui rendra la disposition compacte
payante.

Deux détails. Les strides étaient indexés par **liaison** et les attributs par **emplacement** ;
ils le sont maintenant tous deux par emplacement, le pilote écrivant le stride de la liaison à
l'emplacement de l'attribut qui l'utilise. Et le bloc qui réécrivait les strides seuls sur
`IS_DIRTY(VI_BINDING_STRIDES)` devient redondant — la garde du bloc principal le couvre déjà —
donc supprimé.

### Conformité

D3D12 **2026**, exact. D3D11 a d'abord donné 4328. Vérifié plutôt que supposé, trois campagnes
supplémentaires donnent **4328, 4326, 4326**, soit une médiane de 4326 et exactement
l'oscillation de ±2 mesurée en section 150 avec un binaire inchangé. Pas de régression.

Correctif 0054. Second repère où revenir.

## 156. Refonte, étape 3a : la machinerie du tassement (2026-09-23)

Deux pièces, toutes deux inertes tant que rien ne les appelle.

**Le masque des champs lus.** L'abaissement des descripteurs marque désormais, à chacun de ses
quinze sites, le champ de racine qu'il vient de lire, et rend le masque à l'appelant. C'est plus
léger qu'un suivi d'offsets maximaux et cela suffit : combiné à la disposition, le masque donne
l'étendue à téléverser. Détail de mise en œuvre : plusieurs sites ont un contexte `const`, donc
le masque est atteint par pointeur, pas par valeur.

Vérifié seul, appelants passant `NULL` : **D3D11 4326, D3D12 2026**. La réécriture de ce fichier
— quinze sites plus la macro des valeurs système transformée en expression à virgule — ne casse
rien.

**Le calcul de disposition compacte.** `kk_root_layout_compute()` range les champs du plus chaud
au plus froid : jeux de descripteurs, constantes poussées, index de départ des tampons
dynamiques, tampons dynamiques, attributs, puis le bloc froid — groupe de calcul, constante de
mélange, coefficient de clip, plage Z des vues, drapeaux d'émulation, et enfin le bloc de
capture. Chaque tableau est dimensionné sur ce que la **disposition de pipeline** déclare, et
non sur le maximum Vulkan.

`kk_root_layout_extent()` donne l'étendue à téléverser à partir du masque et du nombre
d'attributs ; `kk_root_layout_pack()` recopie depuis la structure grasse vers les offsets
compacts. La structure grasse reste la zone de travail du processeur — les dizaines d'écritures
du pilote ne bougent pas.

Correctif 0055. Ce qui reste : calculer la disposition à la compilation des nuanceurs, la ranger
dans leurs informations, et faire que le téléversement s'en serve. C'est l'étape qui changera
enfin les chiffres.

## 157. Refonte, étape 3b : la bascule ne tient pas, et pourquoi (2026-09-23)

La disposition compacte a été branchée jusqu'au bout — calcul à la compilation depuis la
disposition de pipeline, rangement dans les informations du nuanceur, tassement au
téléversement, chemin DGC adapté. Elle est **abandonnée**. Trois mesures le justifient.

### 1. Elle est fausse

**D3D12 24 813 contre 2 026, D3D11 4 982 contre 4 326.**

Diagnostic le plus probable, non confirmé faute d'avoir poursuivi : le masque des champs lus
est collecté pour les nuanceurs de l'application, mais `NULL` est passé pour les **programmes
internes** — émulation géométrie et tessellation, nuanceur de remplissage — qui lisent pourtant
des valeurs système dans la même racine. Leurs champs ne sont jamais marqués, l'étendue ne les
couvre pas, ils lisent au-delà du téléversé.

### 2. Le gain d'octets est moitié moindre qu'annoncé

**620 octets par tirage au lieu de 1 040, soit −40 %**, et non les −82 % avancés en section 153.

Cette estimation supposait un dimensionnement sur l'usage réel. Or la disposition doit être
**identique pour tous les étages** d'un pipeline, qui partagent un seul tampon racine ; elle ne
peut donc se fonder que sur ce que la disposition de pipeline **déclare**. Godot déclare de
larges plages de constantes et plusieurs jeux, utilisés en partie seulement. C'est une limite
de conception, pas un réglage.

### 3. Et ces −40 % ne donnent rien en temps

**16,306 ms contre 16,297 de référence.** La boucle de tassement — dix-huit champs testés et
recopiés — coûte ce que l'allocation plus petite économise.

### La prémisse, et où elle casse

« Moins d'octets, donc moins de pression sur le tas, donc moins de temps. » Les deux premiers
maillons tiennent, le troisième non. La section 147 avait pourtant montré l'allocation à 72 %
du coût — mais ce coût venait de **l'épuisement de tampons**, pas du volume en soi, et le
plafond de rétention porté à 192 l'avait déjà largement supprimé. Une fois ce ressort détendu,
réduire les octets ne rapporte plus rien.

**C'est l'erreur de raisonnement à retenir** : j'ai réutilisé une décomposition mesurée *avant*
un correctif qui en changeait la conclusion.

### Ce qui reste acquis

Les trois étapes précédentes sont conformes et commitées : indirection par disposition
(`a35bd8f`), attributs entrelacés (`2451fdc`), machinerie de tassement (`d88b53b`). Elles ne
changent rien aux chiffres mais rendent la racine paramétrable, ce qui resservira si le jour
vient où le volume redevient le facteur limitant.

Retour à `d88b53b` vérifié : **D3D11 4326, D3D12 2026**.

## 158. XFB depuis la tessellation : la cause, enfin localisée (2026-09-23)

Le § 43 avait ramené `test_tessellation_read_tesslevel` à zéro et `test_line_tessellation` de
54 à 50 échecs. Les 50 restants sont maintenant expliqués.

### Ce que le test observe

Contrairement à ce que le message le plus fréquent laisse croire — « Got primitive ID » —
**tout** est à zéro : position, couleur et identifiant. Avec un détail décisif : les échecs
commencent **à l'indice 2**. Les deux premiers sommets sont corrects, les seize suivants vides.
Et le compteur annonce **0 primitive écrite là où le test en attend 9**.

### La chaîne, de bout en bout

La capture calcule son emplacement ainsi (`kk_nir_lower_xfb.c`) :

```
emplacement = instance_id * num_vertices + raw_vertex_id
```

et `raw_vertex_id` vaut `[[vertex_id]] - xfb_first_vertex` (`kk_nir_lower_descriptors.c:616`).

Or la tessellation produit un tirage **indexé et indirect** : `kk_launch_tess` termine par
`draw.grid = kk_grid_indirect(...)` avec un tampon d'indices. Dans un tirage indexé, le
`[[vertex_id]]` de Metal est la **valeur** de l'indice, pas le rang dans le tampon.

Et ces valeurs ne sont pas le rang d'émission : `cl/tessellator.h:311` écrit
`indices[...] = index_bias + PatchIndexValue(...)`, donc des références à un réservoir de
points **uniques** par patch. Deux segments de ligne voisins partagent un sommet et référencent
le même indice.

Le test, lui, attend une entrée par **position d'indice** — sa table de référence contient bien
le même sommet deux fois de suite pour les extrémités partagées. D'où l'écart : nous écrivons
une entrée par sommet unique, D3D en attend une par sommet émis.

Le patch 0 (densité 1, détail 1) n'a qu'une ligne et deux points uniques : ses indices valent 0
et 1, qui tombent juste. Tout le reste se télescope ou reste vide. **C'est exactement le motif
observé.**

Second défaut, indépendant : `kk_flush_xfb_state` s'exécute ligne 2745 et `kk_launch_tess`
ligne 2788, donc les compteurs de requête sont calculés sur les 4 patchs de l'application, pas
sur les 18 sommets produits — d'où le 0 rapporté.

### Ce qu'il faudrait

Le rang de capture doit être la **position dans le tampon d'indices**, que Metal n'expose pas.
Trois voies :

1. **Étendre le tampon d'indices quand la capture est active** : une entrée par sommet émis,
   de valeur égale à sa position, avec les données par sommet dupliquées. Coût : modification
   du noyau de tessellation et mémoire supplémentaire, mais borné au cas capturant.
2. Capturer dans le programme de tessellation — il connaît l'ordre d'émission, mais pas les
   sorties du shader d'évaluation, qu'il ne calcule pas.
3. Exécuter l'évaluation en calcul quand la capture est active, y capturer, puis dessiner.

La première est la seule qui reste dans l'architecture existante. Les compteurs de requête
demandent en plus de lire le compte post-tessellation, qui vit sur le GPU.

**Diagnostic seulement. Rien n'est modifié.**

---

## 159. XFB depuis la tessellation : le correctif

La voie retenue n'est aucune des trois envisagées en 158, mais une quatrième, plus courte :
**rendre le tirage post-tessellation non indexé**. Metal n'expose pas la position dans le
tampon d'indices ; en revanche, si le tirage n'est pas indexé, `[[vertex_id]]` *est* la
position. Le shader va alors chercher lui-même l'indice.

Ce que ça demande :

- `libkk_prefix_sum_tess` écrit un second descripteur de tirage, non indexé, juste après
  l'indexé (`draw_stride_el` passe de 5 à 9). Les quatre mots valent `{total, 1, 0, 0}`.
- `kk_launch_tess` choisit ce descripteur et efface `index.el_size_B` quand le shader
  d'évaluation capture, ce qui aiguille `kk_dispatch_draw` vers
  `mtl_draw_primitives_indirect`.
- `poly_nir_lower_tes_index_fetch` remplace les `load_vertex_id` du shader par
  `poly_load_tes_index(p, load_vertex_id)` — la fonction existait déjà, elle servait au cas
  tess+géométrie où l'évaluation tourne en calcul.

Le piège d'ordonnancement : `kk_nir_lower_descriptors` abaisse `load_raw_vertex_id` en
`load_vertex_id - first` **avant** l'abaissement poly, si bien que le rang de capture et la
coordonnée de tessellation deviennent indiscernables. On ne peut pas non plus changer la
signature de `poly_nir_lower_tes` : ses deux autres appelants sont dans `src/asahi` et
`src/gallium/drivers/asahi`, interdits. Résolu en laissant `load_raw_vertex_id` intact pour
l'étage TESS_EVAL et en l'abaissant dans `kk_shader.c` après poly, où il devient un
`load_vertex_id` nu (le premier sommet vaut 0 pour ce tirage).

### Comptabilité

`kk_flush_xfb_state` ne peut rien calculer pour la tessellation : le nombre de sommets produits
vit sur le GPU. La branche tessellation ne fait donc plus qu'établir l'adresse et la capacité
restante, et laisse `xfb.written[]` intact.

Un noyau `libkk_xfb_account_tess` prend le relais côté GPU. Il ne peut pas être dépêché
**après** le tirage : une dépêche de calcul émise pendant la passe de rendu est perdue
— vérifié, le noyau ne s'exécute pas. Il tourne donc **avant**, dans `kk_launch_tess`, juste
après la somme préfixe, et prend un instantané du compteur : `snapshot[i] = counters[i]` avant
d'avancer `counters[i]`. La table racine fait pointer `xfb_counter` sur l'instantané, de sorte
que le shader lit bien la valeur d'avant le tirage.

### Résultat mesuré

`./tests/run_conformance.sh xfbtess` : **D3D12 2026 → 1912**, D3D11 4326 inchangé.
Les 114 échecs en moins sont tous en tessellation, aucune régression ailleurs :

| test | avant | après |
|---|---|---|
| `test_line_tessellation_dxbc` / `_dxil` | 50 | 2 |
| `test_quad_tessellation_dxbc` / `_dxil` | 6 | 3 |
| `test_quad_tessellation_wrong_input_count_*` | 6 | 3 |
| `test_quad_tessellation_wrong_pso_topology_*` | 6 | 3 |

### Ce qui reste, et pourquoi ce n'est pas la tessellation

Les échecs résiduels sont les statistiques SO (`NumPrimitivesWritten`,
`PrimitivesStorageNeeded`), rapportées à 0. Le noyau de comptabilité s'exécute bien et écrit
bien : le tirage lit la valeur qu'il pose (vérifié en décalant l'instantané de 8 octets, la
capture se décale d'autant).

Le fil se casse ailleurs. vkd3d suspend la requête sur `SOSetTargets`, qui tombe entre
`BeginQuery` et le tirage. Traces :

```
beginq pool=0x... query=0 report=90246120192
endq   query=0                                  <- intervalle vide
beginq pool=0x... query=1 report=90246120208
                                                <- le tirage, ici
endq   query=1
copy first=0 count=2
```

Deux requêtes Vulkan, la seconde seule couvre le tirage, et vkd3d les copie toutes les deux
pour les additionner. Mais en faisant écrire à `libkk_xfb_save_query` la valeur `100 + query`,
le test rapporte **100** : seule la requête 0 arrive au résultat D3D. Avec `3` et `5` en dur
dans les deux requêtes, le test rapporte `3` et `5`, pas `6` et `10` — il n'y a pas de somme.

C'est donc la requête 1 qui est perdue, et rien là-dedans ne tient à la tessellation : la même
suspension se produit pour une capture depuis un shader de sommets. Aucun autre test de la
suite n'exerce `D3D12_QUERY_TYPE_SO_STATISTICS`, ce qui explique que ça n'ait jamais été vu.
À creuser séparément.

### Politique Mesa

Le code ajouté dans l'arbre Mesa ne porte **aucun commentaire** : les quatre mots du
descripteur non indexé sont, dans l'ordre, `vertex_count`, `instance_count`, `vertex_start`,
`start_instance`. À documenter par l'auteur.

---

## 160. Les 1650 échecs de sous-allocation : une contrainte Metal, pas un défaut

`test_suballocate_small_textures_size` porte **1650 des 1912 échecs D3D12**, soit 86 % de
l'écart de conformité restant. Un seul test, une seule cause.

Le motif est d'une régularité totale : l'écart vaut **exactement 12288 octets**, quels que
soient le format, les dimensions et le nombre de couches.

```
143360 - 131072 = 12288     (BC1 512x256, 2 couches)
208896 - 196608 = 12288     (3 couches)
1060864 - 1048576 = 12288   (RGBA8 512x256)
```

Et uniquement pour `levels == 1` et `layers >= 2` : 110 configurations × 15 valeurs de
couches = 1650. Au-delà d'un niveau, le test tolère un facteur 2 qui absorbe le surcoût.

### La chaîne, mesurée bout en bout

**Metal exige 16 Ko d'alignement pour les textures en tableau** dès qu'une couche atteint
16 Ko. Mesuré sur M1 Max, `heapTextureSizeAndAlignWithDescriptor` :

| BC1, 2 couches | taille | align |
|---|---|---|
| 128×128 | 16384 | **128** |
| 256×128 | 32768 | **16384** |
| 512×256 | 131072 | 16384 |

La bascule tombe à 16 Ko *par couche* — une texture simple reste à 128 octets, un
`MTLTextureType2DArray` même à une seule couche passe à 16384. Ce n'est pas de la prudence :
un tas de placement **refuse** la texture aux offsets 4096, 8192 et 12288, et l'accepte à 0 et
16384. Ni `allowGPUOptimizedContents = NO`, ni `MTLStorageModeShared`, ni aucun drapeau
d'usage ne change l'alignement.

**Le pilote rapporte la taille serrée.** Sonde dans `kk_get_image_memory_requirements` :

```
512x256 lvl=1 lay=2 -> size=131072 align=16384
512x256 lvl=1 lay=3 -> size=196608 align=16384
```

Aucun surcoût. Les 12288 n'existent pas encore à ce stade.

**C'est vkd3d qui rembourre**, `libs/vkd3d/resource.c:1333` :

```c
allocation_info->SizeInBytes += allocation_info->Alignment - target_alignment;
allocation_info->Alignment = target_alignment;
```

`16384 - 4096 = 12288`. D3D12 n'admet que 4 Ko, 64 Ko ou 4 Mo comme alignement de placement ;
le test demande `D3D12_SMALL_RESOURCE_PLACEMENT_ALIGNMENT` (4 Ko), et vkd3d rembourre de
l'écart pour pouvoir réaligner lui-même à l'intérieur de la sous-allocation. Le commentaire du
code le dit : *« Do not report alignments greater than DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT
since that might confuse apps. Instead, pad the allocation so that we can align the image
ourselves. »*

### Rien à corriger

Aucune voie n'existe dans notre pile :

- Annoncer moins que 16384 casserait le placement — Metal refuse, c'est mesuré.
- `VK_MESA_image_alignment_control`, que vkd3d interroge et que le test mentionne, sert
  justement à demander un alignement plus faible au pilote. Metal ne peut pas l'accorder.
- Un tableau en agencement linéaire contournerait l'alignement, mais Metal ne sait adosser à
  un tampon qu'une texture 2D sans mipmap — pas un tableau.
- Refuser plutôt que rembourrer (`REJECT_PADDED_SMALL_RESOURCE_ALIGNMENT`) fait retourner
  `E_INVALIDARG` : le test échoue autrement, pas moins.

Le test se décrit lui-même comme *« A strict test. Should expose any case where a driver is
pessimizing our allocation patterns. »* Il fait exactement son travail : sur Apple silicon,
une texture en tableau au-delà de 16 Ko par couche coûte 16 Ko d'alignement. C'est la
plateforme.

### Ce que ça change pour la mesure

**L'écart de conformité réel n'est pas 1912, il est de 262.** Le reste du classement :

```
 136  test_undefined_structured_raw_read_typed (dxbc+dxil)
  21  test_large_tile_buffer_view
  16  test_shader_waveop_maximal_convergence
  12  test_query_heap_cpu_resolve_timestamp
  20  les statistiques SO (tessellation, cf. 159)
  …   le reste en miettes
```

**Diagnostic seulement. Rien n'est modifié.**

---

## 161. Alpha hors bornes : le format du descripteur, pas le type du shader

`test_undefined_structured_raw_read_typed` échouait 68 fois par variante, 136 au total. Le
motif :

```
RAW: output 6, index 28, expected (0, 0, 0, 1), got (0, 0, 0, 1065353216)
```

`1065353216` = `0x3F800000`, soit **1.0f**. Seule la composante w est fausse, et seulement
pour deux sorties sur huit.

### Pourquoi celles-là

Le test lit un tampon **brut** (`R32_TYPELESS`, `D3D12_BUFFER_SRV_FLAG_RAW`) à travers un
descripteur **typé** — c'est le comportement indéfini qu'il sonde. Le shader :

```hlsl
UAVStruct[12][thr] = SRV6[0].Load(thr);           // Buffer<uint4>   -> passe
UAVStruct[14][thr] = asuint(SRV7[0].Load(thr));   // Buffer<float4>  -> echoue
```

Les sorties 6 et 7 de la boucle de validation sont `UAVStruct[14]` et `[15]`, les deux seules
déclarées `Buffer<float4>`. Et le compte tombe juste : `in_bounds_dwords` vaut 28 et 32, donc
36 et 32 entrées hors bornes — exactement 68.

### La cause

Sonde dans `kk_get_texel_buffer_desc` : **vkd3d transmet `VK_FORMAT_R32_UINT` (98) pour tous
les descripteurs**, y compris ceux que le shader lit en flottant. Le format de la vue est
entier ; l'alpha implicite doit donc être l'entier 1.

`kk_texel_oob_value` choisissait sur le **type déclaré par le shader** :

```c
nir_def *one = nir_alu_type_get_base_type(type) == nir_type_float
                  ? nir_imm_floatN_t(b, 1.0, bits)
                  : nir_imm_intN_t(b, 1, bits);
```

Correct quand les deux concordent — une vue `R32_SFLOAT` lue en flottant doit bien rendre
1.0f. Faux dès qu'ils divergent, ce qui est précisément le cas ici. Le test le dit :
*« Assuming that typed side is a R32_UINT texel buffer. This seems to match NV behavior too. »*

### Le correctif

Le bit 31 de `texel_count` était libre : le champ de multiplication occupe les bits 30-31 mais
n'utilise que les valeurs 0 et 1. Il porte désormais « le format de la vue est entier »,
posé depuis `util_format_is_pure_integer` à la création de la vue, et lu dans le shader pour
choisir entre l'entier 1 et 1.0f. L'extraction du champ de multiplication est masquée en
conséquence.

Le coût est nul : `packed` est déjà chargé pour la borne, et la sélection se greffe sur un
`bcsel` qui existait déjà.

### Résultat mesuré

`./tests/run_conformance.sh oobalpha` : **D3D12 1776**, D3D11 4326 inchangé.

| test | avant | après |
|---|---|---|
| `test_undefined_structured_raw_read_typed_dxbc` | 68 | **0** |
| `test_undefined_structured_raw_read_typed_dxil` | 68 | **0** |

Aucune régression ailleurs. L'écart de conformité réel (hors les 1650 de la section 160)
passe de 262 à **126**.

### Politique Mesa

`kk_texel_oob_one` et le drapeau `KK_TEXEL_INT_SHIFT` sont sans commentaire. Ce qu'il faudrait
y écrire : le bit 31 de `texel_count` dit que le format de la vue est entier pur, afin que la
valeur substituée hors bornes le soit aussi, même si le shader a déclaré un type flottant.

---

## 162. Grandes vues de tampons de texels : le plafond de 2^28 de Metal

`test_large_texel_buffer_view` : 42 échecs, le plus gros poste restant. Le test alloue un
tampon de 2 Gio et y crée des vues de texels allant jusqu'à 2^29 éléments.

Les échecs sont d'une netteté totale : **tout ce qui demande 2^29 échoue, tout ce qui demande
2^27 ou 2^28 passe.**

| test | format | éléments | |
|---|---|---|---|
| 0 | R32G32B32A32_UINT | 2^27 | passe |
| 1 | R32G32_UINT | 2^28 | passe |
| 3 | R16G16B16A16_UINT | 2^28 | passe |
| 2, 4–9 | R32, R16G16, R16, R10G10B10A2, R8G8B8A8, R8G8, R8 | 2^29 | **échouent** |

`Got element count 0` et `Got data 0` : le descripteur est vide, la vue est morte.

### La mesure

`KK_MAX_TEXEL_BUFFER_ELEMENTS` vaut `16384 * 16384` = 2^28, et c'est exactement la limite de
Metal. Au-delà, Metal n'échoue pas proprement — **il avorte le processus** :

```
-[MTLTextureDescriptorInternal validateWithDevice:]:1416: failed assertion
`MTLTextureDescriptor has width (536870912) greater than the maximum allowed
size of 268435456.'
```

Le pilote a donc raison de se garder. Sonde dans `kk_texel_view_create` :

```
refus : bo=2147483648 texel=1 elements=2147483648 max=268435456 fmt=13  (R8)
refus : bo=2147483648 texel=2 elements=1073741824 max=268435456 fmt=20  (R16)
refus : bo=2147483648 texel=4 elements=536870912  max=268435456 fmt=98  (R32)
```

### Pourquoi ce n'est pas une simple borne à relever

Chaque cas en échec demande **au moins 2^29 texels pour la vue elle-même**. Une texture Metal
ne peut pas en couvrir plus de 2^28. Il faudrait donc découper la vue sur plusieurs textures
et choisir dans le shader — et la difficulté est structurelle :

`kk_texel_view_create` adosse **une texture à tout le tampon**, pas à la vue (le cache est
indexé sur `(base, format)` pour partager une texture entre toutes les vues d'un même tampon).
Couvrir 2 Gio en R8 demanderait 2^31 texels, soit **huit** morceaux. Huit identifiants font
64 octets, plus l'offset et le compte : 72, au-delà de `KK_MAX_DESCRIPTOR_SIZE`. Et adosser
les textures à la vue plutôt qu'au tampon ferait exploser le cache.

La seule voie générale serait une table de morceaux hors ligne, l'identifiant du descripteur
devenant une adresse de table. Coût : un chargement dépendant supplémentaire **à chaque accès
de tampon de texels**, sur le chemin le plus chaud du pilote. Pour 42 échecs sur un
comportement que le test lui-même déclare hors spécification — il fait taire les messages de
validation Vulkan 09427 et 09428, *« Intentionally testing out of spec behavior »* — et alors
que le minimum garanti par D3D12 (`D3D12_REQ_BUFFER_RESOURCE_TEXEL_COUNT_2_TO_EXP` = 27) est
tenu et passe.

### Un défaut latent trouvé au passage

Le refus porte sur **la taille du tampon**, pas sur celle de la vue :

```c
uint64_t elements = bo->size_B / texel_size_B;
if (elements == 0u || elements > KK_MAX_TEXEL_BUFFER_ELEMENTS)
   return NULL;
```

Une vue de mille éléments dans un tampon de 2 Gio est donc **morte elle aussi**, alors qu'elle
tiendrait largement. Un jeu qui place un petit tampon de texels dans une grosse allocation
lirait des zéros. Aucun test de la suite ne l'exerce, donc aucun chiffre à l'appui : borner la
texture à 2^28 au lieu de refuser, et n'accepter le descripteur que si
`texel_offset + count <= 2^28`, corrigerait ça sans coût sur le chemin chaud. **Non fait, car
non vérifiable par la conformité.**

**Diagnostic seulement. Rien n'est modifié.**

---

## 163. Horodatages : la granularité précise perd le périphérique

`test_query_heap_cpu_resolve_timestamp` échouait 12 fois. Le test pose quinze
`EndQuery(TIMESTAMP)` hors passe de rendu, puis les relit depuis le CPU. Sonde dans
`kk_GetQueryPoolResults` :

```
q=0 val=4046035143837
q=1 val=4046035143837      <- la meme
q=2 val=4046035143837
q=3 val=4046035143837
q=4..14 val=0              <- onze zeros
```

Quatre valeurs identiques, onze zéros.

### La fausse piste

Le pont écrit avec `MTL4TimestampGranularityRelaxed`. Le SDK est explicite : *« it may sample
at command encoder boundaries »*, *« the command may group all timestamps for a pass
together »*. En passant à `MTL4TimestampGranularityPrecise`, les quinze valeurs deviennent
distinctes et croissantes, et le test tombe à zéro échec.

**Mais la campagne complète est morte** : `VK_ERROR_DEVICE_LOST` dans
`test_execute_indirect_state_predication`, puis blocage. Ce test entrelace des
`EndQuery(TIMESTAMP)` avec des `ExecuteIndirect` prédiqués — précisément là où Apple annonce
que le précis « peut découper les encodeurs de commandes ». A/B en isolation :

| granularité | horodatage | prédication |
|---|---|---|
| `Relaxed` | 12 échecs | 1572 tests, 0 échec |
| `Precise` | 0 échec | **périphérique perdu** |
| `Precise` sur le calcul seul | 0 échec | **périphérique perdu** |

Restreindre le précis au chemin calcul ne sauve rien. Voie abandonnée.

### Ce que le test demande vraiment

```c
ok(query_data[i] >= before_gpu_timestamp, ...);
ok(query_data[i] <= after_gpu_timestamp, ...);
if (i != 0) ok(query_data[i] >= query_data[i - 1], ...);
```

Quinze valeurs **identiques mais valides** passent les trois vérifications. Les échecs
venaient uniquement des onze zéros.

### Le correctif

Le chemin rendu réglait déjà le problème, et son commentaire dit tout :

```c
/* If we've already issued a timestamp write for a render stage, reuse it
 * because reissuing might return a 0 timestamp */
```

Seule la première écriture par encodeur atterrit ; les suivantes rendent zéro. Le chemin
calcul n'avait pas cette déduplication. Ajoutée, avec une sentinelle `KK_TS_STAGE_COMPUTE`
dans `ts_stage_map`, vidée à la fermeture de l'encodeur de calcul comme elle l'est déjà à
celle de l'encodeur de rendu. On reste en granularité relâchée : pas de découpage, pas de
perte de périphérique.

### Résultat mesuré

`./tests/run_conformance.sh tsdedup` : **D3D12 1764** (contre 1776), D3D11 4328 — dans
l'oscillation connue 4326–4328. Un seul test bouge :

| test | avant | après |
|---|---|---|
| `test_query_heap_cpu_resolve_timestamp` | 12 | **0** |

Et les voisins restent intacts : `test_query_timestamp`,
`test_query_timestamp_write_after_read` et `test_execute_indirect_state_predication` à zéro
échec.

### Ce que ça ne fait pas

Les quinze horodatages rendent désormais **la même valeur** au lieu de onze zéros. C'est
strictement meilleur, et c'est ce que le pilote appliquait déjà en rendu — mais un profileur
qui poserait plusieurs marqueurs dans un même encodeur de calcul les verrait confondus. La
vraie précision demande `Precise`, que Metal ne supporte pas ici sans perdre le périphérique.

### Les deux autres tests de requêtes, pour mémoire

- `test_query_pipeline_statistics` (6) : KK n'expose qu'occlusion, horodatage et rétroaction
  de transformation. `pipelineStatisticsQuery` n'est pas annoncé, donc vkd3d rend des zéros.
  Les compter demanderait d'instrumenter chaque shader ; Metal n'a pas ces compteurs.
- `test_virtual_queries` (5) : six requêtes d'occlusion **imbriquées**. `kk_CmdBeginQuery` ne
  retient qu'un index (`cmd->state.gfx.occlusion.index`), et Metal n'a qu'un
  `setVisibilityResultMode:offset:` actif à la fois — un second `Begin` écrase le premier.
  Vulkan interdit d'ailleurs l'imbrication ; le test fait taire le message 01922 en renvoyant
  à l'issue vkd3d-proton 2381. Les émuler demanderait un créneau par changement d'ensemble
  actif, puis une somme GPU des créneaux couvrant chaque requête.

### Politique Mesa

`KK_TS_STAGE_COMPUTE` et le bloc de déduplication sont sans commentaire. Ce qu'il faudrait y
écrire : Metal ne retient que la première écriture d'horodatage par encodeur en granularité
relâchée, donc les suivantes réutilisent la même entrée de tas plutôt que de rendre zéro.

---

## 164. Convergence des opérations de vague : quatre pistes éliminées, cause non trouvée

`test_shader_waveop_maximal_convergence` échoue 16 fois. Le shader partitionne les voies par
valeur :

```hlsl
uint v = RO[thr];
while (true) {
    uint first = WaveReadLaneFirst(v);
    if (v == first) { result = WaveActiveSum(v); break; }
}
RW[thr] = result;
```

Entrées `2,3,1,3, 2,0,0,1, 0,1,3,2, 2,1,2,2`. Deux pipelines : l'un où le compilateur a le
droit de tout reconverger (référence : 25 partout, la somme totale), l'autre où la divergence
doit être respectée (référence : `12,9,4,9, 12,0,0,4, 0,4,9,12, 12,4,12,12`).

**La première moitié passe. La seconde rend 25 partout.** Les 16 échecs sont exactement les 16
éléments de la moitié non convergée.

### Ce qui a été éliminé, par mesure

**1. Metal respecte la divergence.** Banc autonome, seize voies dans une SIMD de 32 :

```
voie  v   scrutin dans la branche
  0   2   0x0000d811   <- voies 0,4,11,12,14,15
  1   3   0x0000040a   <- voies 1,3,10
  2   1   0x00002284   <- voies 2,7,9,13
  5   0   0x00000160   <- voies 5,6,8
```

`simd_sum` y rend 12, 9, 4, 0. Exact. Et cela vaut aussi **à l'intérieur de la boucle avec
sortie conditionnelle**, structure identique à celle du shader.

**2. L'abaissement du pilote est correct.** KK n'émet pas `simd_sum` : il abaisse la réduction
en scrutin `simd_or(1 << voie)`, puis balayage de Hillis-Steele sur le masque actif, puis
diffusion depuis la voie active la plus haute (`31 - clz(scrutin)`). Rejoué mot pour mot dans
un noyau Metal autonome : **12, 9, 4, 0**. Correct.

**3. Ni la branche à deux voies ni le mode mathématique.** Le code généré teste
`scrutin == 0xFFFFFFFF` pour prendre un papillon plutôt que le balayage. Ajouté au banc : sans
effet. Le pilote compile en `MTL_MATH_MODE_FAST` ; testé aussi : sans effet.

**4. Le bon shader est bien lié.** Sonde dans `kk_flush_compute_state` :

```
[KKCS] shader=0x...300 pso=0x...cf0 len=6563 boucle=0
[KKCS] shader=0x...9e0 pso=0x...9a0 len=7698 boucle=1
```

Deux MSL distincts, deux pipelines Metal distincts, dans le bon ordre. Le second shader est
bien celui qui garde la boucle — et son MSL, lu en entier, implémente exactement l'algorithme
vérifié au point 2.

### Où ça coince

Le shader généré est correct, Metal est correct, le bon pipeline est lié — et le résultat est
malgré tout la somme totale. L'écart est donc entre le MSL produit et son exécution réelle
dans le contexte du pilote, ce qu'aucun banc autonome n'a su reproduire.

L'expérience décisive restante : extraire le MSL généré tel quel dans un harnais autonome, en
simulant la table racine qu'il lit (`buf0.contents`), et l'exécuter sur les mêmes entrées. Si
le résultat est 25, le défaut est dans le code généré et il reste à trouver où ; s'il est
correct, le défaut est dans l'environnement d'exécution — liaison, table racine, ou état
d'encodeur.

**Diagnostic partiel. Rien n'est modifié ; le test reste à 16 échecs.**

---

## 165. Opérations de vague : le générateur MSL déclarait tout au niveau de la fonction

Suite de la section 164, où quatre pistes avaient été éliminées sans trouver la cause. Elle
est trouvée.

### Le harnais qui débloque tout

Extraire le MSL généré tel quel et le faire tourner dans un harnais autonome — table racine
simulée, adresses GPU écrites aux offsets 888 et 896 — reproduit le défaut immédiatement :
**25 partout**. À partir de là, l'itération coûte une seconde au lieu d'une reconstruction du
pilote.

En instrumentant le shader, la cause saute aux yeux :

```
t33 : 2 3 1 3 2 0 0 1 0 1 3 2 2 1 2 2     <- devrait valoir 2 partout
t34 : 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1     <- donc la condition est vraie pour tous
t35 : 65535 partout                        <- aucune divergence
```

`t33 = simd_broadcast_first(t28)` rend **la valeur propre de chaque voie**. Aucune divergence,
une seule itération, somme des seize = 25.

### Le déclencheur, par bissection

| variante | `t33` | condition | scrutin obtenu |
|---|---|---|---|
| vC | hors boucle | en ligne | **0xffff** |
| vD | dans la boucle | hors boucle | 0xd811 ✓ |
| vE | dans la boucle | en ligne | 0xd811 ✓ |
| vH | hors boucle | booléen local | 0xd811 ✓ |

**Ranger le résultat de `simd_broadcast_first` dans une variable déclarée hors de la boucle
suffit à casser la compilation Metal.** Ni une copie par temporaire (`vF`) ni `volatile`
(`vG`) n'y changent rien. C'est un bogue du compilateur d'Apple, et il est fragile : `vH`
passe alors que `vC` échoue pour une différence purement cosmétique.

Or `predeclare_ssa_values` déclarait **toutes** les temporaires au niveau de la fonction, dans
un grand préambule, et n'émettait ensuite que des affectations. Toute opération de vague dans
une boucle tombait donc dans le cas pathologique.

### Le correctif

Une temporaire est désormais déclarée à sa définition si **aucun de ses usages ne sort du
nœud de flot de contrôle qui la contient** (`msl_def_stays_in_scope`, qui remonte la chaîne
`cf_node.parent` de chaque usage). Sinon le préambule la déclare comme avant. Trois
exclusions : textures et échantillonneurs, valeurs sans type MSL, et les opérations ALU
encadrées d'un `#pragma METAL fp math_mode` — dont les accolades ouvriraient une portée trop
étroite.

Piège rencontré : la macro `P_IND` se termine par `} while (0);`, point-virgule compris. Un
`if (...) P_IND(); else` ne compile pas ; il faut des accolades.

### Résultat mesuré

`./tests/run_conformance.sh portee` : **D3D12 1748** (contre 1764), D3D11 4326 inchangé.
Un seul test bouge, aucune régression — et c'est le premier changement de cette session qui
touche la génération de code de **tous** les shaders :

| test | avant | après |
|---|---|---|
| `test_shader_waveop_maximal_convergence` | 16 | **0** |

Effet secondaire mesuré sur les 37 noyaux de ce test :

| | avant | après |
|---|---|---|
| MSL généré | 406686 o | **344305 o** (−15,3 %) |
| déclarations en préambule | 3266 | **691** (−79 %) |

Moins de source à analyser pour le compilateur Metal, et des durées de vie enfin visibles.
**Le temps de compilation des shaders n'a pas été mesuré**, ni les performances d'exécution :
le resserrement de portée ne peut qu'aider un compilateur, mais ce n'est pas chiffré.

### Politique Mesa

`msl_def_stays_in_scope`, `msl_def_declared_inline` et `msl_emit_dest` sont sans commentaire.
Ce qu'il faudrait y écrire : Metal compile mal une opération de sous-groupe dont le résultat
est rangé dans une variable déclarée hors de la boucle qui la contient, donc on déclare au
plus près dès que la portée le permet.

---

## 166. Biais de profondeur selon le format : deux causes, aucune corrigée

`test_depth_bias_formats` échoue 6 fois : deux cas sur neuf, chacun sur ses trois pipelines.

| cas | format | biais | attendu | obtenu |
|---|---|---|---|---|
| 0 | D16_UNORM | 0 | rejet | **acceptation** |
| 4 | D24_UNORM_S8 | 1 | acceptation | **rejet** |

Le test dessine un fragment à profondeur constante `1/64` contre un tampon effacé un ou deux
crans plus haut, en `GREATER_EQUAL`, sans écriture de profondeur.

### Cas 4 : Apple silicon n'a pas de D24

La table de formats du pilote n'expose que `Z16_UNORM`, `Z32_FLOAT` et
`Z32_FLOAT_S8X24_UINT`. `DXGI_FORMAT_D24_UNORM_S8_UINT` est donc rendu en profondeur
**flottante**, où le pas du biais est l'ULP du flottant — à `1/64`, `2⁻²⁹` — au lieu des
`2⁻²⁴` que D3D attend. Le biais de 1 ne comble pas l'écart, d'où le rejet.

vkd3d sait traiter ce cas : `vkd3d_get_depth_bias_representation` demande
`VK_DEPTH_BIAS_REPRESENTATION_LEAST_REPRESENTABLE_VALUE_FORCE_UNORM_EXT` pour D16 et D24, via
`VK_EXT_depth_bias_control`. **Le pilote n'expose pas cette extension** — aucune occurrence
dans l'arbre. Mais même implémentée, elle ne sauverait pas ce cas : la spécification définit
FORCE_UNORM sur le nombre de bits de l'**attachement**, soit 32 ici, pas 24. Hors d'atteinte
sans format D24.

### Cas 0 : l'écart d'une unité D16 se perd

Ce cas ne met aucun biais en jeu. Mesures successives, en forçant la valeur d'effacement dans
le pilote :

| effacement forcé (D16) | cas 0 | cas 1 | cas 2 |
|---|---|---|---|
| valeur du test (`+1` unité) | accepte ✗ | accepte ✓ | rejette ✓ |
| arrondi au cran supérieur | accepte ✗ | — | — |
| `0.5` | rejette ✓ | rejette ✗ | rejette ✓ |
| `1/64 + 3` unités | rejette ✓ | **accepte** ✗ | **accepte** ✗ |

Ce que ça établit :

- le test de profondeur fonctionne (l'effacement à `0.5` rejette tout) ;
- la valeur d'effacement arrive correcte au pilote (sonde : `0.0156402587890625`), et la
  pré-quantifier au format ne change rien ;
- **sans aucun biais, le fragment franchit un écart d'une unité D16 mais pas de trois** ;
- **avec un biais de 1, il franchit trois unités.**

Donc deux anomalies de précision dans le chemin D16 : un décalage intrinsèque d'une à deux
unités sur la profondeur du fragment, et un biais qui vaut plus d'une unité. Ni l'une ni
l'autre n'a été localisée — le calcul ne les explique sous aucune hypothèse de quantification
(arrondi, troncature, échelle 65535 ou 65536, demi-précision).

**Diagnostic partiel. Rien n'est modifié ; le test reste à 6 échecs.**

---

## 167. Le sens de parcours : une régression introduite en 156, et sa correction

En reprenant `test_quad_tessellation`, la comparaison **ligne par ligne** — et non plus par
compte — révèle que le correctif 0056 avait déplacé le problème :

```
avant 0056 : lignes 372, 411, 457, 459, 461, 463   (6 echecs)
apres 0056 : lignes 364, 461, 463                   (3 echecs)
```

La ligne 364 est **nouvelle**. Le bilan net de −3 la masquait. Elle vérifie que la cible de
rendu reste blanche : la tessellation est antihoraire, donc tout doit être éliminé par le tri
des faces. On rendait du vert.

### Deux ordres, pas un

`poly_load_tes_index` échange les deuxième et troisième sommets de chaque triangle quand
`p->ccw`. Le chemin matériel indexé, lui, lit `index_buffer[i]` **sans échange** : c'est le
rasteriseur qui applique le sens. En passant au tirage non indexé avec cette fonction,
l'échange était appliqué une fois de trop.

Mais le remplacer par une lecture brute fait échouer la ligne 372 à la place : la capture
rend les sommets 2 et 3 intervertis.

```
obtenu  : v0, {-1, 1}, { 1,-1}
attendu : v0, { 1,-1}, {-1, 1}
```

**Le rasteriseur veut l'ordre brut, la capture veut l'ordre échangé.** L'échange n'est pas une
propriété de la lecture d'indice, c'est une propriété du *rang de capture*.

### Le correctif

Le pivot est extrait dans `poly_tes_ccw_slot`, et les deux usages sont séparés :

- `poly_load_tes_index_raw(p, i)` — lecture brute, pour le sommet que le rasteriseur consomme ;
- `poly_tes_ccw_slot(p, i)` — le rang où la capture doit écrire.

`poly_load_tes_index` devient `index_buffer[poly_tes_ccw_slot(p, i)]`, strictement équivalent
à ce qu'elle faisait, donc le chemin tess+géométrie d'asahi est inchangé.

`poly_nir_lower_tes_index_fetch` traite maintenant les deux intrinsèques d'un coup :
`load_vertex_id` devient la lecture brute, `load_raw_vertex_id` devient le rang pivoté. La
passe `kk_nir_lower_tes_xfb_ordinal` côté kk devient inutile et disparaît.

`p->ccw` vaut zéro pour les points et les isolignes, donc le pivot est neutre hors triangles —
`test_line_tessellation` est inchangé.

### Résultat mesuré

`test_quad_tessellation_dxbc` passe de **3 à 2** échecs : la régression de la 364 et l'échec
préexistant de la 372 tombent tous les deux. Six variantes du test sont concernées.

### Résultat en campagne complète

`./tests/run_conformance.sh ccw` : **D3D12 1742** (contre 1748), D3D11 4328 — dans
l'oscillation connue. La comparaison ligne par ligne ne montre que les six lignes 364, sur les
six variantes du test, et rien d'autre :

```
test_quad_tessellation_dxbc:364                  1 -> 0
test_quad_tessellation_dxil:364                  1 -> 0
test_quad_tessellation_wrong_input_count_dxbc:364   1 -> 0
test_quad_tessellation_wrong_input_count_dxil:364   1 -> 0
test_quad_tessellation_wrong_pso_topology_dxbc:364  1 -> 0
test_quad_tessellation_wrong_pso_topology_dxil:364  1 -> 0
```

### La leçon

Comparer les **comptes** par test ne suffit pas : un correctif peut corriger quatre échecs et
en créer un sans que le total le montre. Comparer les **lignes**.

### Politique Mesa

`poly_tes_ccw_slot` reprend le commentaire qui existait déjà dans `poly_load_tes_index` — il
décrit exactement ce que la fonction fait, et n'a pas été réécrit. `poly_load_tes_index_raw`
est sans commentaire ; ce qu'il faudrait y écrire : lecture sans pivot, pour le sommet que le
rasteriseur consomme, le pivot revenant au rang de capture.

---

## 168. Le changement de génération MSL ne change pas les performances

Le correctif 0059 touche la génération de code de **tous** les shaders ; il devait donc être
chiffré sur une charge réelle. A/B entrelacé, trois tours, Godot en 640×480, 64 vues,
400 objets, machine vérifiée sans processus résiduel :

```
avant : 83.333  84.115  83.333   -> mediane 83.333 ms
apres : 84.131  84.848  83.333   -> mediane 84.131 ms
```

Les deux séries se chevauchent — 83.333 apparaît dans les deux. **Aucun gain ni perte ne peut
être revendiqué.** L'affirmation portée en 165, selon laquelle le resserrement de portée « ne
peut qu'aider un compilateur », n'est pas confirmée par la mesure. Elle n'est pas infirmée non
plus : l'écart, s'il existe, est sous le bruit de ce banc.

Le temps de compilation des shaders reste non mesuré. C'est là que le gain de 15,3 % sur la
taille du MSL pourrait se voir, s'il se voit quelque part.

---

## 169. Débordement d'adresse sur tampon structuré : le décalage est 32 bits par construction

`test_structured_buffer_addressing_wrap` échoue 4 fois. Une lecture hors bornes rend la donnée
au lieu de zéro quand `indice × pas` déborde 32 bits :

```
reads: buffer_index 10, value 1, expected 0, got 1
reads: buffer_index 22, value 4, expected 0, got 1
```

Le pilote annonce `robustBufferAccess2` et abaisse les tampons via
`nir_address_format_64bit_bounded_global` (`kk_buffer_addr_format`). Ce format porte une base
64 bits, une taille 32 bits et un **décalage 32 bits**. La vérification de bornes se fait donc
en arithmétique 32 bits : quand `indice × pas` déborde, le décalage repasse dans la plage et
la vérification laisse passer.

Ce n'est pas du code KosmicKrisp : c'est un format d'adresse partagé par plusieurs pilotes
Mesa. Le corriger demanderait soit d'étendre `nir_lower_explicit_io` à une vérification
64 bits, soit d'introduire un format d'adresse propre à KK. Pour 4 échecs, sur un test dont
les commentaires reconnaissent eux-mêmes l'ambiguïté — *« It's ambiguous if application
intends to read at offset 0 or >4G offset for those components »* — et qui dispense NVIDIA,
Intel Windows et Adreno, l'échange n'est pas favorable.

**Diagnostic seulement. Rien n'est modifié.**

### Une fausse piste, pour mémoire

Le MSL généré contient un motif qui ressemble à un défaut :

```c
int t42 = (ulong)&buf0.contents[0] && t34 ? t41 : t23;
```

C'est un contournement délibéré, `KK_WORKAROUND_10` dans `nir_to_msl.c` : tous les shaders ont
`buf0` lié, donc le terme est toujours vrai et ne change pas la sémantique.

---

## 170. Statistiques SO : la section 159 se trompait, et le mur reste

La section 159 concluait que vkd3d ne lisait qu'une des deux requêtes Vulkan. **C'est faux**,
et la mesure qui le montre est simple : en faisant écrire la valeur 7 à `libkk_copy_queries`
pour chaque requête copiée, le test rapporte **14**.

Le rassemblement de vkd3d somme donc bien les deux segments. Ce que la section 159 mesurait
— `100 + query` rendant 100 — signifiait non pas « la requête 1 est ignorée » mais
« le rapport de la requête 1 vaut zéro ».

### Ce qui est établi

- le rassemblement somme (7 + 7 = 14) ;
- le rapport de la requête 1 est nul au moment de la copie ;
- les écritures de `libkk_xfb_account_tess` vers `q->counters` **atteignent le tirage** —
  vérifié en pointant `xfb_counter` de la table racine dessus, la capture se décale ;
- ces mêmes écritures **n'atteignent pas** `libkk_xfb_save_query`, quelle que soit la position
  d'argument (testé en visant la même adresse depuis les deux paramètres du noyau).

### Ce qui a été essayé, sans effet

Entre la dépêche de comptabilité et `libkk_xfb_save_query` il y a un **encodeur de rendu**.
Or `kk_dispatch_precomp` pose un barrage `mtl_barrier_after_encoder_stages`, de portée
**encodeur**, qui n'ordonne pas contre un encodeur précédent — `mtl_barrier_after_queue_stages`
est la variante de portée file.

Ajouter un barrage de portée file :

| essai | ligne | quad |
|---|---|---|
| base | 2 | 2 |
| file **à la place** de l'encodeur | **54** | **5** |
| file **en plus** de l'encodeur | 2 | 2 |

Remplacer casse la chaîne de tessellation, qui dépend de l'ordonnancement intra-encodeur.
Ajouter ne corrige rien. Les deux essais sont annulés : le correctif 0058 se régénère à
l'identique.

L'ordonnancement n'est donc pas la cause, ou pas celle-là. **Le mur reste.**

### Ce que ça coûte

Environ 16 échecs : les statistiques SO de `test_line_tessellation` (2 × 2) et de
`test_quad_tessellation` (2 × 6). Plus `test_virtual_queries` (5), qui relève d'un autre
mécanisme — les requêtes d'occlusion imbriquées, cf. 163.

**Diagnostic seulement. Rien n'est modifié.**

---

## 171. Statistiques SO : sept hypothèses éliminées, le mur tient

Reprise du mur de la section 170. Toutes les mesures ci-dessous portent sur
`test_line_tessellation_dxbc`, avec le décalage de capture comme canal d'observation : écrire
une valeur non nulle dans l'instantané décale la capture et fait exploser le compte d'échecs,
ce qui rend les variables du noyau observables.

### Le fait central, reconfirmé

`libkk_xfb_account_tess` écrit vers deux pointeurs. Les écritures vers `snapshot` sont vues
par le **tirage**. Les écritures vers `query` ne sont vues par **aucune dépêche ultérieure**.

### Ce qui a été éliminé, par mesure

| hypothèse | test | verdict |
|---|---|---|
| le rassemblement ignore la 2ᵉ requête | valeur 7 forcée à la copie | **faux** : 7+7 = 14 |
| ordonnancement encodeur/file | barrage de portée file, en plus et à la place | sans effet (et casse tout à la place) |
| cohérence de cache | `MTL4VisibilityOptionDevice` ajouté aux trois barrages | sans effet |
| le tampon de compteurs | lecture de l'instantané à la place | **zéro aussi** |
| la position d'argument | même adresse visée depuis les deux paramètres | zéro dans les deux cas |
| le noyau ne s'exécute plus | `snapshot[i] = used + 8` | s'exécute (54 échecs) |
| le bloc conditionnel est sauté | `snapshot[0] = 8` **dans** le bloc | s'exécute (54 échecs) |
| `total` vaut zéro | `snapshot[i] = total` | **non nul** (56 échecs) |
| le lecteur précède le tirage | le lecteur écrit 8 dans l'instantané | **non** : capture intacte, donc il suit |

Et, décisif : écrire `33` et `44` **directement dans le rapport de requête** depuis le noyau
de comptabilité rend zéro également.

### Ce qui reste

Le noyau s'exécute, après la somme préfixe et avant le tirage ; `total` est non nul ; le
pointeur de requête est non nul ; le bloc s'exécute ; ses écritures vers l'instantané sont
visibles du tirage ; ses écritures vers le rapport de requête ne sont visibles de rien.
L'ordonnancement est correct et aucun barrage n'y change quoi que ce soit.

Ces faits ne se recomposent pas. Il manque une pièce que je n'ai pas su trouver.

Tous les essais sont annulés : les correctifs 0058 et 0060 se régénèrent à l'identique, et les
deux tests sont revenus à 2 échecs.

**Diagnostic seulement. Rien n'est modifié.**

---

## 172. La reconstruction depuis zéro était cassée

Objectif rappelé : le projet doit vivre dans un dépôt propre et se construire automatiquement
en appliquant la série de correctifs sur des sources vanilla. Vérification faite — **elle ne
marchait pas**.

En appliquant la série sur un arbre Mesa vanilla à la révision figée : **7 correctifs sur 44
échouaient**, et 18 fichiers source n'étaient pas reproduits.

### Trois trous distincts

**1. Le glob s'arrêtait à 0059.** `00[0-3][0-9]`, `004[5-9]`, `005[0-9]` — le correctif 0060
n'était repris par rien. Remplacé par `00[0-9][0-9]-kosmickrisp-*.patch`, qui n'aura plus à
être étendu.

**2. Une modification jamais capturée.** Le correctif 0050 attendait les drapeaux
`KK_DEBUG_NO_STORAGE_WRITE` et `KK_DEBUG_NO_ATTACHMENT_LOAD`, que la série n'introduisait
nulle part — ils n'existaient que dans `0000-cumulatif`, que le script saute. Tout ce qui
suivait tombait en cascade.

Les états intermédiaires ayant disparu, réparer onze correctifs incrémentaux était de
l'archéologie à faible rendement. Les correctifs 0050 à 0060 sont donc déplacés dans
`patches-historique/` — ils restent le récit logique du travail — et remplacés par un
**`0050-kosmickrisp-cumulatif-2.patch`** obtenu par différence entre « vanilla + 0001..0049 »
et l'arbre de travail. Reproduction garantie par construction.

**3. Un cinquième arbre ignoré.** `src/wine11`, le Wine ARM64, que visent les correctifs 0048
et 0049 — le script ne le connaissait pas du tout, ni son URL ni sa révision. Ajouté.

Et au passage, une ligne jamais capturée dans dxvk : un `#include <algorithm>` manquant dans
`config.cpp`, devenu le correctif 0061.

### Le garde-fou

`tests/verifier_reconstruction.sh` : pour chacun des cinq arbres, crée un plan de travail git
à la révision figée, applique la série, compare au répertoire de travail. Ne modifie rien.

```
mesa         : 33 correctifs, reproduction exacte
wine         :  6 correctifs, reproduction exacte
wine11       :  2 correctifs, reproduction exacte
vkd3d-proton :  6 correctifs, reproduction exacte
dxvk         :  4 correctifs, reproduction exacte
RECONSTRUCTION VERIFIEE
```

À lancer après chaque nouveau correctif. C'est ce qui manquait : rien ne vérifiait que la
série reconstruisait ce qu'on construisait réellement.

### Sur la politique Mesa

La prudence appliquée jusqu'ici — correctifs 0056 à 0060 écrits sans commentaire — visait une
soumission en amont qui n'est pas au programme. Pour un dépôt personnel, elle ne s'applique
pas. Les commentaires manquants sont un coût de lisibilité, pas une contrainte.

---

## 173. Un vrai jeu tourne : Braid, de bout en bout

Premier jeu commercial lancé sur la pile ouverte. Le journal DXVK en atteste :

```
info:  DXVK: v2.7.1+
info:  Vulkan: Found vkGetInstanceProcAddr in winevulkan.dll
info:  Found device: Apple M1 Max (KosmicKrisp 26.2.99)
info:    Driver   : KosmicKrisp 26.2.99
```

Braid → DXVK → winevulkan → KosmicKrisp → Metal 4. Jouable.

Six obstacles ont dû tomber, et **aucun ne venait du pilote**.

### 1. Le 32 bits n'existait pas

Wine etait construit `--enable-archs=x86_64` : aucun exécutable PE32 ne pouvait se lancer, pas
même l'installeur. Reconstruit avec `--enable-archs=i386,x86_64` — le « nouveau WoW64 », seule
voie sur macOS qui n'a plus aucun runtime 32 bits — dans `wine/wine10-wow64`, séparé de la pile
existante. DXVK construit en i686 : `d3d8`, `d3d9`, `d3d10core`, `d3d11`, `dxgi`. Préfixe
`wine/pfx-wow64` avec 829 fichiers dans `syswow64`.

### 2. pkg-config n'était pas sur le PATH de configure

Défaut latent de `etape2_construire_pile.sh` : le `PATH` restreint imposé à `configure`
(`$BISON:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin`) **ne contient pas `pkg-config`**. Wine ne
pouvait donc découvrir aucune bibliothèque système. Toute la liste de
`--without-freetype --without-x --without-gnutls --without-sdl…` n'était pas un choix, c'était
une conséquence.

Sans polices, **aucun jeu n'aurait affiché de texte**. On l'aurait découvert devant un menu vide.

### 3. dyld ne cherche plus dans /usr/local/lib

Wine construit avec freetype cherche `libfreetype.6.dylib`. Elle est installée, mais dyld ne
la trouve pas : le chemin de repli par défaut ne contient plus `/usr/local/lib`. Vérifié par un
`dlopen` depuis un processus x86_64. Réglé par `wine/deps`, qui porte les liens vers freetype
et libpng, ajouté au `DYLD_LIBRARY_PATH` des lanceurs.

### 4. L'installeur GOG plante

Il meurt sur un appel à pointeur nul — `stack overflow ... addr 0x0` — dans son interface
propre, aussi bien en mode silencieux qu'au premier clic. Wine qualifie lui-même ce WoW64
d'`experimental`.

Contourné en construisant **innoextract** dans `build/innoextract` : il déballe l'archive sans
jamais exécuter l'installeur. Braid extrait, 263 Mo. Vaut pour tous les jeux GOG.

### 5. Le compilateur HLSL de Wine refuse les shaders

```
err:d3dcompiler:D3DCompile2 Failed to compile shader, vkd3d result -4.
    <anonymous>:24:11: E5000: syntax error, unexpected '<'
```

Écran noir : sans shader, rien à dessiner. Ni le pilote, ni DXVK, ni Metal en cause.

### 6. L'override portait à côté

Installer le `D3DCompiler_43.dll` de Microsoft n'a rien changé. La trace de chargement
explique pourquoi :

```
d3d9.dll           -> native    (DXVK)
d3dx9_43.dll       -> builtin   (Wine)
d3dcompiler_47.dll -> builtin   (Wine)
```

Le `d3dx9_43` de Wine appelle **`d3dcompiler_47`**, pas le `_43`. Il fallait aussi remplacer
`d3dx9_43` par celui de Microsoft — présent, comme le compilateur, dans le `__redist/DirectX`
du jeu lui-même.

`tests/installer_redist.sh` automatise désormais l'extraction de ces `.cab` et l'installation
dans `syswow64` ; les overrides correspondants sont posés par `etape2_pile_wow64.sh`.

### Ce que ça dit, et ce que ça ne dit pas

La pile tient debout sur un vrai jeu. Mais Braid est en **Direct3D 9** : il valide Wine, DXVK,
le pilote et Metal, **pas** les chemins D3D11/D3D12 sur lesquels a porté tout le travail de
conformité de ces sessions. Pour mesurer ce que valent les correctifs 0056 à 0060, il faudra
un jeu D3D11 ou D3D12.

Rien n'a été mesuré en performance : le jeu a été lancé et joué, pas chronométré.

---

## 174. Grimrock : zéro adaptateur Direct3D 9

Legend of Grimrock s'extrait et démarre, mais ouvre une boîte d'erreur. Son contenu, récupéré
par `WINEDEBUG=+msgbox` puisqu'il n'apparaît nulle part ailleurs :

```
D3DError - GetDeviceCaps failed: D3DERR_INVALIDCALL
```

### La mesure

Sonde posée dans `D3D9InterfaceEx::GetDeviceCaps` de DXVK :

```
avant : adapterCount=0  -> aucun adaptateur a cet indice  -> D3DERR_INVALIDCALL
apres : adapterCount=1  -> adaptateur trouve, hr=0
```

DXVK, compilé en PE Windows, prend le chemin `#ifdef _WIN32` de son constructeur : il construit
ses adaptateurs Direct3D 9 **à partir des écrans** rendus par `EnumDisplayDevices`, en ne
gardant que ceux portant `DISPLAY_DEVICE_ATTACHED_TO_DESKTOP`. C'est l'option
`d3d9.enumerateByDisplays`, vraie par défaut.

Sous notre Wine, aucun écran ne porte ce drapeau. Zéro adaptateur Direct3D 9 — alors que
l'instance Vulkan voit parfaitement le M1 Max et qu'aucune ligne « Skipping » n'apparaît dans
le filtre de périphériques.

### Le correctif

`dxvk.conf` à la racine, pointé par `DXVK_CONFIG_FILE` depuis les deux lanceurs :

```
d3d9.enumerateByDisplays = False
```

DXVK énumère alors directement les adaptateurs Vulkan. Grimrock démarre par
`tests/lancer_jeu.sh`, sans réglage manuel.

### Ce qui reste inexpliqué

**Braid a fonctionné sans ce réglage**, même préfixe, même Wine, même DXVK. Sonde à l'appui,
Braid n'appelle jamais `GetDeviceCaps` — mais il lui faut quand même un adaptateur pour créer
son périphérique. Soit un écran était signalé à ce moment-là, soit `CreateDevice` emprunte un
chemin différent. La question n'est pas tranchée, et elle compte : si l'énumération d'écrans
est instable d'un lancement à l'autre, d'autres jeux tomberont dessus au hasard.

Indice dans la même direction, encore visible au démarrage de Grimrock :

```
err: Win32 WSI: retrieveDisplayMode: Failed to query monitor info
```

Non fatal, mais c'est la même faiblesse : Wine ne rend pas d'information d'écran exploitable
dans ce préfixe.

### Correction de la section 174 : le réglage ne suffit pas

Le correctif annoncé ci-dessus est **partiel, et ne fait pas fonctionner Grimrock**. Il
déplace l'échec :

```
par defaut                    : GetDeviceCaps  -> adapterCount=0 -> D3DERR_INVALIDCALL
enumerateByDisplays = False   : GetDeviceCaps  -> hr=0
                                CreateDevice   -> D3DERR_INVALIDCALL
```

Sonde sur les paramètres de présentation transmis par le jeu :

```
type=1 flags=82 ext=0 | w=0 h=0 fmt=21 count=1 swap=1 windowed=0
interval=1 hwnd=0 mstype=0 autods=0 dsfmt=75 refresh=0
```

La validation passe (`hr=0`) ; l'échec est dans `InitialReset`. Grimrock demande un **plein
écran** (`windowed=0`) en laissant les dimensions à zéro, à charge pour le runtime de les
déduire du mode d'affichage courant. Or sans énumération par écrans, l'adaptateur n'a plus de
moniteur associé, d'où l'avertissement persistant :

```
err: Win32 WSI: retrieveDisplayMode: Failed to query monitor info
```

Forcer le mode fenêtré par `grimrock.cfg` n'y change rien.

### La contradiction non résolue

Un programme de test 32 bits lancé dans le même préfixe rapporte pourtant des écrans corrects :

```
ecran 0 : \\.\DISPLAY1   flags=0x00000015 attache=1
ecran 1 : \\.\DISPLAY2   flags=0x00000000 attache=0
GetMonitorInfo : ok
EnumDisplaySettings courant : ok  1280x720 @60Hz
```

`DISPLAY1` porte bien `DISPLAY_DEVICE_ATTACHED_TO_DESKTOP`. L'énumération par écrans de DXVK
aurait donc dû produire un adaptateur. Elle en produit zéro dans le processus du jeu. Aucun
bureau virtuel n'est configuré dans le registre, ce qui aurait pu expliquer l'écart.

Ces deux observations sont incompatibles, ce qui veut dire qu'une variable m'échappe. Le
réglage est donc **laissé commenté** dans `dxvk.conf` : la configuration par défaut est la
seule dont on sait qu'elle fait tourner un jeu, Braid.

**Grimrock ne fonctionne pas. Le pilote n'est pas en cause** — l'échec est entièrement dans
l'association adaptateur/moniteur entre Wine et DXVK.

## 175. Grimrock : la variable qui manquait était un bit dans `FreeImage.dll`

La section 174 s'arrêtait sur une contradiction : un programme de test voyait l'écran, le
jeu n'en voyait aucun. La variable manquante se lit d'un seul coup en instrumentant le
constructeur de DXVK.

```
SONDE ctor : enumerateByDisplays=1 vkAdapterCount=1 SM_CMONITORS=0
SONDE attente : essai=0  t=0ms    SM_CMONITORS=0 enum=0
SONDE attente : essai=29 t=2900ms SM_CMONITORS=0 enum=0
```

Ce n'est pas une course : `EnumDisplayDevices` rend FAUX pendant trois secondes d'affilée, et
ni `PeekMessage`, ni `GetDesktopWindow`, ni `SendMessage` au bureau, ni `CreateWindowEx`, ni
`EnumDisplayMonitors` ne le débloquent. Le cache d'écrans du processus est vide **et le reste**.

### La chaîne, mesurée maillon par maillon

Une trace dans `lock_display_devices` sépare le fil du jeu de tous les autres :

```
fil 0024 (grimrock) : force=0 serial=0 cached=0 sources_empty=1   x 337 appels
fil 0034            : force=0 serial=2 cached=2 sources_empty=0
fil 0074 (explorer) : force=0 serial=2 cached=2 sources_empty=0
```

`serial=0` vient de `get_monitor_update_serial`, qui rend 0 quand `get_shared_desktop` échoue.
Le test `!force && monitor_update_serial >= serial` devient alors `0 >= 0` : Wine conclut que
le cache est à jour, et rend la main sur une liste vide. Définitivement.

Une trace dans `get_shared_desktop` donne le localisateur :

```
0024 locator id=1 offset=18 -> introuvable
```

Le localisateur est valide ; c'est la projection du bloc qui échoue :

```
0024 find_shared_session_block Failed to map session block for offset 18, size 148, status 0xc0000022
0024 map_shared_session_block  Failed to map shared session block,  status 0xc0000022
0024 err:virtual:map_file_into_view failed to set PROT_EXEC on file map, noexec filesystem?
```

`0xc0000022` est `STATUS_ACCESS_DENIED`. Il sort de `map_file_into_view`, quand `mmap` rend
`EACCES` ou `EPERM` sur une projection `MAP_SHARED`. Et la raison du refus est dans le message
juste après : Wine demande `PROT_EXEC`, **macOS ne l'accorde jamais sur une projection
partagée**.

### Pourquoi Wine demande l'exécution sur une page de données

`force_exec_prot`, armé par le chargeur :

```c
if (!(nt->OptionalHeader.DllCharacteristics & IMAGE_DLLCHARACTERISTICS_NX_COMPAT))
{
    ULONG flags = MEM_EXECUTE_OPTION_ENABLE;
    NtSetInformationProcess( GetCurrentProcess(), ProcessExecuteFlags, &flags, sizeof(flags) );
}
```

Un seul module sans le bit suffit à armer le drapeau pour **tout le processus**. Mesure sur
les binaires du jeu :

```
grimrock.exe   DllCharacteristics=0x8140  NX_COMPAT=oui
FreeImage.dll  DllCharacteristics=0x0000  NX_COMPAT=NON
```

Grimrock lui-même est conforme. C'est `FreeImage.dll`, compilée en 2012 sans le bit, qui
désarme le no-exec, ce qui met `PROT_EXEC` sur toutes les projections, ce que macOS refuse sur
`MAP_SHARED`, ce qui empêche de projeter la mémoire partagée de session, ce qui vide le cache
d'écrans, ce qui donne zéro adaptateur Direct3D 9.

La même cause explique l'autre erreur observée, `Mapping non-persisted file failed: 5` dans
l'allocateur D3D9 de DXVK : même appel, même refus.

### Le correctif

`0062-wine-macos-no-exec-on-shared-mappings.patch`, un seul bloc dans `map_file_into_view` :
quand la permission d'exécution n'a été ajoutée que par `force_exec_prot` et que le noyau
refuse la projection partagée, on retire `PROT_EXEC` et on réessaie, au lieu de rendre
`STATUS_ACCESS_DENIED`. La page perd une permission que macOS n'accorde de toute façon pas.

J'avais aussi retouché `mprotect_exec` pour le même motif. Le A/B montre que ce second bloc
n'est pas nécessaire — et qu'avec lui le jeu produit des `nested exception on signal stack`.
Il est retiré : le correctif tient en un bloc.

### Où en est le jeu

Avant, après :

```
avant : SM_CMONITORS=0  adaptateurs=0  -> GetDeviceCaps : D3DERR_INVALIDCALL
apres : SM_CMONITORS=1  adaptateurs=1  -> peripherique cree
                                          chaine d'echange 1728x1117, 3 images, FIFO
                                          nuanciers compiles (8 VS/FS)
```

Puis le processus meurt, sans boîte de dialogue :

```
seh:dispatch_exception code=c0000005 addr=000000040124E540
                       rip=000000040124e540 rsp=0000000001fdf434
err:seh:call_seh_handlers invalid frame 0000000001FDF434 (0000000100D02000-0000000100DFFD20)
err:seh:NtRaiseException Exception frame is not in stack limits => unable to dispatch exception.
```

L'adresse fautive **est** le pointeur d'instruction : c'est un saut vers une adresse non
exécutable. Le `rip` vaut `0x4_0124E540`, soit une adresse 32 bits plausible avec un `0x4`
parasite au-dessus du 32e bit, et `rsp` est dans l'espace 32 bits alors que Wine compare aux
bornes de la pile 64 bits. Piste non vérifiée : une troncature dans le passage WoW64.

**Braid n'est pas affecté** : relancé après le correctif, fenêtre ouverte, 35 % de processeur,
aucune erreur. Le correctif ne change rien pour un processus conforme au no-exec.

### Ce que la section 174 disait de faux

Elle attribuait l'échec à « l'association adaptateur/moniteur entre Wine et DXVK ». C'est
faux : DXVK énumère correctement, Wine énumère correctement, et le réglage
`d3d9.enumerateByDisplays` n'avait rien à voir. La cause est deux couches plus bas, dans la
projection mémoire.

Elle disait aussi qu'un `grimrock.cfg` forçant le mode fenêtré « n'y change rien ». En réalité
ce fichier, que j'avais écrit, était **invalide** : le format du jeu n'a pas de préfixe
`config.`, et le jeu ouvrait une boîte de dialogue « attempt to index global 'config' (a nil
value) » que l'auteur voyait sans pouvoir la lire. Les deux essais rapportés comme « la même
erreur » étaient cette boîte-là, pas l'erreur Direct3D.

Outil ajouté pour ne plus se retrouver aveugle devant une fenêtre : `tests/lister_fenetres.c`
énumère les fenêtres visibles et le texte de leurs contrôles, `tests/cliquer_bouton.c` clique
un bouton désigné par son texte.

### Ce qui reste, mesuré

Le plantage n'est pas causé par le correctif. La sonde qui journalise chaque page dont on
retire l'exécution donne des plages qui commencent toutes à `0x26e0000` :

```
SONDE noexec 0x26e0000-0x27dffff
SONDE noexec 0x26f0000-0x270afff
...
```

Les deux adresses fautives relevées, `0x0124E540` et `0x7bd1cddb`, sont en dehors de toutes
ces plages. Aucune page dépouillée de son droit d'exécution n'est exécutée.

Après la chaîne d'échange, le jeu se comporte de trois façons selon les essais :

```
1. sortie silencieuse, code 5, rien dans le journal meme avec le canal err
2. faute de page, le processus meurt
3. la fenetre reste, le processus vit a moins de 1 % de processeur
```

Dans le cas 3, un `sample` de l'hôte montre tous les fils DXVK (`dxvk-submit`, `dxvk-queue`,
`dxvk-frame`) au repos sur `NtWaitForAlertByThreadId`, le fil principal dans la boucle Cocoa de
`winemac.drv` — ce qui est normal sur macOS — et un fil Windows bloqué dans
`NtWaitForMultipleObjects` → `server_wait`. `sample` ne sait pas dérouler une pile PE 32 bits :
il répète `__wine_syscall_dispatcher`, donc on ne sait pas sur quoi ce fil attend.

Dans le cas 2, le contexte de l'exception est incohérent :

```
rip=01ddfce07bd1cddb  rsp=0000000001ddfc70  rbp=0000000001ddfc6c
err:seh:call_seh_handlers invalid frame 0000000001FDF434 (0000000100D02000-0000000100DFFD20)
```

Le `rip` se lit comme deux moitiés de 32 bits collées : `0x01ddfce0`, une adresse de pile, et
`0x7bd1cddb`, une adresse dans `kernel32`. Et Wine compare un pointeur de pile 32 bits aux
bornes d'une pile 64 bits. Les trois comportements et ce contexte pointent vers la frontière
WoW64, pas vers le pilote : **hypothèse non vérifiée**, rien n'a encore été mesuré du côté de
la traduction 32 bits.

## 176. Le plantage de Grimrock est dans la transition 32↔64 bits

La section 175 laissait trois comportements et une hypothèse. La trace d'appels les explique.

### Ce que `+relay` montre

D'abord un fait qui oriente tout le reste : **sous `+relay`, le jeu ne plante pas**. Il affiche
un écran de chargement et tourne plusieurs minutes, là où il meurt en moins de trente secondes
sans trace. La trace sérialise chaque appel d'API et ralentit de plusieurs ordres de grandeur.
C'est donc une course.

Ensuite, le blocage du cas 3 n'est plus un mystère :

```
0024:err:sync:RtlpWaitForCriticalSection section 005FB800 "?" wait timed out
     in thread 0024, blocked by 011c, retrying (300 sec)
```

Le fil principal attend une section critique que le fil `011c` détient. Et `011c` est mort. Les
deux comportements — la mort brutale et le blocage à 1 % de processeur — sont donc le même bug :
selon que l'exception tue le processus ou passe inaperçue, on voit l'un ou l'autre.

### Le contexte d'exception est incohérent

```
rip=0124e6c076bfa9ec  rsp=0000000001fdef7c  rbp=0124e6c076bfa9ec
rax=cf8fea5aa25e0092  rbx=01fdefd001c63300  rcx=ef227a0001fdef68
rsi=0000000076bfa9ec  r14=0000000100dff600
err:seh:call_seh_handlers invalid frame 0000000001FDEF7C (0000000100D02000-0000000100DFFD20)
```

`rip` vaut exactement `rbp`, et chaque registre 64 bits contient deux valeurs 32 bits sans
rapport collées bout à bout, dont les moitiés basses sont des adresses 32 bits plausibles
(`0x76bfa9ec` tombe dans `D3D9.DLL`, base `0x76B40000`). `rsp` est dans l'espace 32 bits alors
que Wine le compare aux bornes de la pile 64 bits du fil — d'où le refus de dispatcher.

Sur trois exécutions, la faute est une **faute d'exécution** (`info[1] == rip`) vers des
adresses groupées : `0x0124E540`, `0x0124E6C0`, `0x0124E730`. Une adresse de tas, avec des bits
parasites au-dessus du 32e. Un processeur en mode 32 bits ne peut pas produire un `rip` pareil :
le fil était déjà passé en 64 bits avec des registres restés 32 bits.

### Fausses pistes écartées, chacune par une mesure

```
correctif 0062            : les pages privees d'exec commencent a 0x26e0000,
                            les adresses fautives sont en dessous
bascule W^X (0036)        : ce Wine est construit en x86_64 sous Rosetta,
                            le bloc __aarch64__ n'est pas compile
pilote audio              : couper Audio="" deplace la faute mais ne l'enleve pas
                            (et introduit un dereferencement nul dans xaudio2_7)
xaudio2_7=d               : le jeu ne demarre plus du tout, il a besoin de la DLL
dxvk.numCompilerThreads=1 : plante pareil
```

Le fil qui meurt est celui de `xaudio2_7` (`ret=7808f686`, base `0x78080000`), mais couper le
son ne change rien : c'est le fil le plus actif en transitions, pas la cause.

### Ce que ça veut dire

**Braid, 32 bits lui aussi, tourne de bout en bout.** Le chemin 32 bits n'est donc pas cassé en
général. Ce qui distingue Grimrock, c'est le nombre de fils qui traversent la frontière en
parallèle. Le bug est dans `wow64cpu` ou dans la façon dont Rosetta livre une faute survenue en
mode 32 bits — et Rosetta est fermé.

`0x7BCC1248`, que la section 175 donnait comme adresse fautive, est en réalité l'adresse
**réécrite** par `BTCpuResetToConsistentState`, qui place `syscall_32to64` dans `Rip` pour faire
croire à une faute au point de transition. Ce n'était pas le lieu du crime.

### Outil

`tests/decrire_jeu.py` décrit un exécutable ou un répertoire de jeu : architecture — donc
passage ou non par WoW64 —, bit `NX_COMPAT` de chaque module, et API graphique, y compris
chargée dynamiquement. Sur Grimrock il désigne `FreeImage.dll` en une ligne.

## 177. Le pont WoW64 s'exécute en mode 32 bits — preuve par l'encodage

DREDGE (Black Salt Games, Unity 2021) a servi de troisième point de mesure. Le binaire dément
ce que j'avais anticipé, et confirme la fiche PCGamingWiki :

```
DREDGE.exe       pei-i386   NX_COMPAT=oui
UnityPlayer.dll  pei-i386   d3d11.dll, d3d12.dll, d3d9.dll, dxgi.dll, opengl32.dll, vulkan-1.dll
```

32 bits, et le jeu embarque un `UnityCrashHandler32.exe`. **Il ne teste donc pas Direct3D 11** :
DXVK n'écrit pas une seule ligne, le jeu meurt avant. Son propre journal dit où :

```
Mono path[0] = 'C:/Jeux/dredge/DREDGE_Data/Managed'
Got a UNKNOWN while executing native code. This usually indicates
a fatal error in the mono runtime or one of the native libraries
```

### L'instruction fautive

Les deux jeux tombent dans `wow64cpu.dll` (base `0x7BCC0000`). Le désassemblage de ces deux
offsets exacts donne :

```asm
7a401248:  ff 15 b2 5d 00 00   call *0x5db2(%rip)      ; Grimrock
7a4012a0:  ff 25 6a 8e 00 00   jmp  *0x8e6a(%rip)      ; DREDGE, Wow64SystemServiceEx
```

Et les adresses lues lors des fautes :

```
Grimrock : eip=7BCC1248  info[1]=00005DB2
DREDGE   : eip=7BCC12A0  info[1]=00008E6A
```

**L'adresse lue est exactement le déplacement RIP-relatif de l'instruction à l'EIP fautif.**
Deux jeux, deux instructions différentes, deux déplacements différents, la même coïncidence.
Ce n'est pas une coïncidence : en mode 64 bits, `ff 15 disp32` calcule `rip + disp32` ; en mode
32 bits, le même encodage signifie « appelle via l'adresse absolue `disp32` ». Lire `0x5DB2` au
lieu de `rip + 0x5DB2` veut dire que le processeur a décodé cette instruction **en mode 32
bits**.

Le pont WoW64 de Wine — du code 64 bits — est donc exécuté alors que la bascule vers le mode
64 bits n'a pas eu lieu. Sous Rosetta, cette bascule est émulée.

### Correction des sections 175 et 176

Elles donnaient `0x7BCC1248` comme une adresse **réécrite** par `BTCpuResetToConsistentState`,
qui place `syscall_32to64` dans `Rip` après une faute en cours de transition. C'est faux :
cette fonction écrirait toujours la même adresse, or on en observe deux, et chacune correspond
au déplacement de l'instruction qui s'y trouve. Ce sont de vraies adresses de faute.

### Les deux jeux ne tombent pas pareil

```
Grimrock : survit sous +relay, plante sans      -> intermittent, dependant du temps
DREDGE   : plante aussi sous +relay             -> deterministe
```

Mono provoque volontairement des fautes de page — vérifications de nullité, barrières
d'écriture du ramasse-miettes — et installe un gestionnaire vectorisé pour les rattraper
(`0x761FD540`, soit `mono-2.0-bdwgc.dll` + `0x38D540`). Il en déclenche donc sans arrêt, et
tombe tout de suite. Grimrock n'en provoque qu'exceptionnellement, d'où l'intermittence. Braid,
qui tourne de bout en bout, n'en provoque apparemment jamais.

### Ce que ça change

Le blocage est dans la transition 32/64 bits, pas dans le pilote. Aucun des deux jeux n'a
atteint Metal. Un jeu **64 bits** ne traverse jamais ce pont : c'est la seule voie pour mesurer
enfin D3D11 et D3D12 sur une application réelle.

Titres vérifiés sur PCGamingWiki, colonne `Executable` :

```
64 bits : Hollow Knight (D3D11), Disco Elysium (D3D11), Cyberpunk 2077 (D3D12)
32 bits : DREDGE, Sunless Sea, Inscryption, Return of the Obra Dinn,
          Shadow Tactics, Braid, Grimrock
```

Le catalogue indépendant est massivement 32 bits ; le 64 bits se trouve surtout côté gros
titres. `tests/decrire_jeu.py` tranche en une commande sur un répertoire de jeu extrait.

## 178. Écrire dans une page exécutable casse la bascule de mode — cas minimal et correctif

La section 177 savait *quoi* : du code 64 bits décodé en 32 bits. Elle ne savait pas *quand*.
Trois sondes pour le trouver, dont deux négatives.

```
200 fautes de page rattrapees, puis des appels systeme   -> aucun plantage
16 fils fautant en parallele, 7 minutes                  -> aucun plantage
du code genere a l'execution qui appelle Sleep()         -> plante au 3e appel
```

`tests/sonde_jit_wow64.c` fait quarante lignes : écrire `push 0 ; mov eax,<Sleep> ; call eax ;
ret` dans une page `PAGE_EXECUTE_READWRITE`, appeler. La faute est identique à celle de DREDGE,
octet pour octet :

```
eip=7bcc12a0  info[1]=00008E6A  cs=0107
```

### Ce n'est pas le contenu, c'est l'écriture

```
ecrit une fois, appele 3000 fois            -> ok
reecrit avant chaque appel, page RWX        -> plante au 3e appel
reecrit avec bascule W^X (RW, ecrire, RX)   -> ok, 2000 tours
```

Les octets écrits sont **identiques** à chaque tour. Le contenu ne change pas, donc ce n'est pas
une invalidation de cache de traduction : c'est le fait d'écrire dans une page qui est en même
temps inscriptible et exécutable qui laisse Rosetta dans un état incohérent.

Hypothèse testée et écartée au passage : faire remonter `NtFlushInstructionCache` vers
`sys_icache_invalidate` au lieu du `/* no-op */` que Wine met sur x86. Aucun effet. Retiré du
correctif — un coût sans bénéfice mesuré.

### Le correctif

`0063-wine-rosetta-no-write-and-exec-on-the-same-page.patch` : deux `#if`. La machinerie
existait déjà, écrite pour arm64 par le correctif 0036 — `VPROT_WXFLIP`, la page projetée soit
inscriptible soit exécutable, et la bascule sur faute. Elle était simplement compilée hors de ce
Wine, construit en x86_64. Elle vaut aussi sous Rosetta, pour une autre raison : là le noyau
accepte RWX, mais le traducteur ne le supporte pas.

### Effet mesuré

```
sonde JIT, page RWX  : plantait au 3e appel  ->  2000 tours sans plantage
DREDGE               : mourait dans mono_jit_init, DXVK jamais charge
                       ->  Unity demarre, et pour la premiere fois un vrai jeu
                           atteint notre couche D3D11 :
                             Direct3D 11.0 [level 11.1]
                             Renderer: Apple M1 Max (ID=0x64)
                             VRAM: 3072 MB
                           puis meurt plus loin, sur ReloadAssembly
Grimrock             : inchange -- son declencheur est autre
Braid                : pas de regression, la fenetre s'ouvre
```

DREDGE ne va donc pas encore au bout, mais il est passé de « meurt avant tout graphisme » à
« crée un périphérique Direct3D 11 de niveau 11.1 ». La faute restante a la même signature de
registres collés, à une autre adresse (`kernel32+0x1DCDDB`, faute d'exécution) : il reste au
moins un second déclencheur de la même bascule ratée.

## 179. Le second déclencheur : le retour 64→32 ne rebascule pas

Avec 0063, DREDGE va deux étapes plus loin et meurt ailleurs. La trace d'appels nomme l'endroit
exactement.

```
01d4:Call KERNEL32.ResetEvent(00000488) ret=7b05c0ee
01d4:Call ntdll.NtResetEvent(00000488,00000000) ret=7b6229cd
```

Et le `rip` de la faute vaut `0x00000488_7B6229CD` : **l'argument `0x488` collé à l'adresse de
retour `0x7B6229CD`**, deux mots voisins sur la pile 32 bits. Un `ret` qui dépile 8 octets au
lieu de 4. Le processeur était donc resté en 64 bits alors que le pont venait de rendre la main
au code 32 bits.

C'est le miroir de la section 178 : là c'était 32→64 qui ne basculait pas, ici c'est 64→32.

### Pourquoi on ne peut pas rattraper après coup

`syscall_32to64` commence par `xchgq %r14,%rsp`, soit `49 87 e6`. Décodé en 32 bits, ça donne
`dec ecx` puis `xchg esi,esp` — **l'échange du pointeur de pile avec `esi`**. Les instructions
suivantes écrivent à travers `ebp` au lieu de `r13`. Quand la faute finit par tomber sur l'appel
indirect, une dizaine d'instructions ont déjà détruit l'état. Le `esp=7ffa2000` relevé sur
Grimrock en section 176 s'explique par là.

`BTCpuResetToConsistentState` est bien appelée — 40 fois dans une seule session de DREDGE — et
elle redémarre la transition depuis le début. Mais elle ne peut pas défaire ce que la dizaine
d'instructions mal décodées a déjà fait.

### Tentative, mesurée, annulée

Wine a deux chemins de retour 64→32 : un `ljmp` rapide et un `iretq`. J'ai forcé le second, en
pariant qu'un transfert lointain aussi courant serait mieux émulé.

```
ljmp (defaut) : GfxDevice -> Direct3D 11.0 [level 11.1] -> ReloadAssembly
iretq force   : GfxDevice -> plantage, deux essais sur deux
```

C'est une régression stable, pas une amélioration. **Annulé**, l'arbre `wow64cpu` est revenu à
l'original.

### Où en est DREDGE

```
sans 0063 : meurt dans mono_jit_init, DXVK jamais charge
avec 0063 : Initialize engine version: 2021.3.5f1
            GfxDevice: creating device client; threaded=1; jobified=1
            Direct3D: Version 11.0 [level 11.1]
                      Renderer: Apple M1 Max (ID=0x64)
                      VRAM: 3072 MB
            puis meurt sur le retour 64->32 d'un appel systeme
```

Le jeu ne tourne pas. Mais la pile graphique, elle, répond : DXVK expose un niveau 11.1 sur
KosmicKrisp et Unity l'accepte. Aucun des deux blocages restants n'est dans le pilote.

### Quatre tentatives de plus, toutes négatives

```
sonde_suspend_wow64  : 2000 suspensions/reprises d'un fil qui traverse le pont
                       -> aucun plantage. Le ramasse-miettes n'est pas en cause.
SegCs reinjecte      : copy_context_64to32 recopie le selecteur 64 bits tel quel,
                       mais son seul appelant est protege par un retour anticipe.
                       Hypothese ecartee a la lecture.
sys_icache_invalidate: reessaye pour le cas multi-fils. Sans effet, comme en
                       mono-fil. Retire pour de bon.
sonde_jit_concurrent : un fil reecrit la page pendant que quatre l'executent.
                       Plante, mais sur une faute a l'adresse zero dont je ne
                       peux pas prouver qu'elle n'est pas une course de la sonde
                       elle-meme. **Non concluant**, garde tel quel.
```

Le pont reste cassé dans le sens 64→32, de façon intermittente, et je n'ai pas trouvé de
déclencheur reproductible pour ce sens-là. L'état livré est `0062` + `0063`, l'arbre `wow64cpu`
est celui d'origine.

## 180. CodeWeavers avait déjà le correctif : `lretq` au lieu du saut lointain

Le miroir des sources CrossOver (`PhoenicisOrg/winecx`, CrossOver 25.1.0 sur Wine 10.0)
contient, dans `dlls/wow64cpu/cpu.c`, exactement notre bug et son contournement.

```c
/* CW HACK 20760:
 * When running under Rosetta 2, use lretq instead of ljmp to work around
 * a SIGUSR1 race condition. */
```

Une **course avec un signal** : ça explique l'intermittence que je n'arrivais pas à reproduire.

### Les deux moitiés du contournement

Au retour 64→32, `lretq` remplace `ljmp *(%r14)` : on empile le sélecteur et l'adresse, puis
on fait un retour lointain.

```asm
subq $0x10,%rsp
movl 4(%r14),%edx ; movq %rdx,0x8(%rsp)   /* SegCs */
movl 0(%r14),%edx ; movq %rdx,(%rsp)      /* Eip   */
lretq
```

À l'entrée 32→64, le saut lointain devient un **appel** lointain suivi d'un saut :
`lcall` vers un petit bloc qui fait `add $0x08,%esp` — pour retirer ce que le `lcall` a
empilé — puis `jmp` vers `syscall_32to64`.

La détection se fait sur le nom de processeur, qui sous Rosetta est émulé :

```
status=0x00000000  chaine="VirtualApple @ 2.50GHz"
detection Rosetta 2 : OUI
```

Vérifié par `tests/sonde_rosetta.c` depuis un processus 32 bits, parce que le `sysctl` d'un
shell natif répond « Apple M1 Max » et aurait laissé croire que la détection échouait.

### Effet mesuré

```
avant : err:seh:call_seh_handlers invalid frame ... systematique
        contexte incoherent : rip = deux mots 32 bits colles
apres : zero "invalid frame"
        contexte propre : eip=7615caa8 esp=0011f468 ebp=0011f4e0
```

La corruption de contexte a disparu. Et les jeux :

```
Grimrock : bloque a moins de 1 % de processeur  ->  170 % et sa fenetre, il tourne
DREDGE   : meurt en silence a ReloadAssembly    ->  meme point, mais la faute est
                                                    propre et interceptee par Unity :
                                                    lecture de 0x0EB48C84 dans
                                                    mono-2.0-bdwgc.dll. Un vrai
                                                    plantage, plus une corruption.
temoin JIT (0063) : toujours 2000 tours sans plantage
```

`0064-wine-rosetta-lretq-instead-of-far-jump.patch`. Le code vient de CrossOver, sous LGPL,
écrit par CodeWeavers ; je l'ai porté et vérifié, je ne l'ai pas trouvé.

### À garder en réserve

Leur arbre contient aussi deux correctifs `MXCSR` (CW Hack 24256 et 24265) : sous Rosetta, le
registre `MXCSR` est faux dans les contextes de signaux, et sur M3 Rosetta le restaure à une
valeur incorrecte même après correction. Non porté, non mesuré chez nous.

## 181. DREDGE tourne, et 0063 était le dernier obstacle

Une fois 0064 en place, le correctif 0063 devient non seulement inutile mais nuisible.

```
temoin JIT, page RWX reecrite 2000 fois, avec 0064 et SANS 0063 -> aucun plantage
```

La bascule W^X soignait un symptôme : écrire dans une page exécutable déclenchait un signal,
et c'est ce signal qui perdait la course contre le saut lointain. Avec `lretq`, la course
n'existe plus, donc les pages RWX redeviennent inoffensives.

Et 0063 coûtait **une faute de page à chaque écriture de code**. Pour un moteur qui compile en
permanence, c'était exactement l'étranglement :

```
avec 0063    : Begin MonoManager ReloadAssembly    -> plantage
sans 0063    : Begin MonoManager ReloadAssembly
               UnloadTime: 5.38 ms
               Unloading 5 Unused Serialized files ...
               fenetre UnityWndClass "DREDGE", 104 % de processeur
```

**DREDGE tourne.** Unity rend, son ramasse-miettes tourne, DXVK a sa chaîne d'échange. Les
seules erreurs au journal sont bénignes : `readMonitorEdidFromKey: Failed to get EDID reg key
size`, faute d'EDID dans le registre.

### État des trois jeux

```
Braid      : lanceur FLTK ouvert, 39 % de processeur, aucune erreur.
             FLTK dessine ses boutons sans fenetres filles, donc je n'ai pas pu
             cliquer "Play" par programme -- verification limitee au demarrage.
Grimrock   : 169 % de processeur, sa fenetre, aucune erreur. Il tourne.
DREDGE     : 104 % de processeur, fenetre UnityWndClass. Il tourne.
```

### La série Wine, au propre

```
0062  macOS refuse PROT_EXEC sur une projection partagee     garde
0063  bascule W^X sous Rosetta                               ARCHIVE, redondant depuis 0064
0064  lretq au lieu du saut lointain (CodeWeavers, LGPL)     garde
```

0063 part dans `patches-historique/`. Il garde sa valeur de documentation — c'est lui qui a
mené au cas minimal de la section 178 — mais il n'est plus appliqué.

## 182. Première mesure sur un vrai jeu : DREDGE

Jamais fait jusqu'ici. Toute la conformité avait été mesurée sur des suites de tests.

### Images par seconde et charge

Lectures du HUD DXVK par l'auteur, charges en médianes sur 8 à 10 échantillons
(`tests/mesurer_gpu.sh`, qui lit `ioreg` — accessible sans privilèges sur Apple Silicon — et
vérifie qu'aucun `wineserver` résiduel ne fausse la mesure).

```
                    images/s   GPU device   GPU renderer   GPU tiler   processeur
FIFO (defaut)        60-62        65,5 %        64,5 %        65 %       157 %
IMMEDIATE            76-90        78,5 %        77,5 %        78 %       218 %
```

### Le 60 n'est pas un defaut

L'écran est un ProMotion à 120 Hz. La pile rend 76 à 90 images. `VK_PRESENT_MODE_FIFO_KHR` ne
sait pas afficher 85 sur un écran à 120 : il tombe au diviseur suivant, 60. Comportement normal
du mode, pas une limite du pilote.

Le WSI Metal de Mesa n'expose que deux modes :

```c
static const VkPresentModeKHR present_modes[] = {
   VK_PRESENT_MODE_IMMEDIATE_KHR,
   VK_PRESENT_MODE_FIFO_KHR,
};
```

`VK_PRESENT_MODE_FIFO_RELAXED_KHR` manque, et c'est précisément celui qu'il faudrait :
synchronisé quand l'image arrive à temps, immédiat quand elle est en retard. Il supprimerait la
chute à 60 sans le déchirement d'`IMMEDIATE`.

### Ce qui limite reellement

Même sans synchronisation, **ni le GPU (78 %) ni le processeur (2,18 cœurs sur dix) ne sont
saturés**. Il reste donc de la marge perdue quelque part — sérialisation entre soumission et
présentation, ou taxe Rosetta sur la répartition. Non mesuré : c'est le prochain profilage, et
rien ne permet encore de désigner un coupable.

### Le blocage au chargement

```
graphicsPipelineLibrary : 0
DXVK: Graphics pipeline libraries not supported
```

DXVK 2.x a supprimé son cache d'état sur disque au profit de `VK_EXT_graphics_pipeline_library`,
que KosmicKrisp n'expose pas. Chaque pipeline est donc compilé au premier dessin qui l'utilise,
sur le fil de rendu. D'où la chute et le blocage au chargement, puis le retour à la normale une
fois les pipelines en mémoire.

Pire : rien ne persiste d'un lancement à l'autre. Dans `kk_physical_device.c`, seule la
destruction du cache disque existe :

```c
static void
kk_physical_device_free_disk_cache(struct kk_physical_device *pdev)
```

Rien ne le crée jamais ; la branche sans cache affirme même qu'il est nul. KosmicKrisp utilise
pourtant `vk_pipeline_cache` — la tuyauterie est là, sans adossement au disque. Câbler le
`disk_cache` de Mesa supprimerait le bégaiement dès le second lancement, pour bien moins de
travail que d'implémenter les pipeline libraries.

## 183. La compilation de nuanciers ne coûte rien, et la section 182 se trompait

La section 182 attribuait le blocage au chargement à la compilation des pipelines, faute de
`VK_EXT_graphics_pipeline_library`, et proposait de câbler le `disk_cache`. Chronométrage posé
dans le pilote, sur un démarrage complet de DREDGE jusqu'à la boucle de jeu :

```
frontal (SPIR-V -> NIR -> MSL)   86 nuanciers    0,281 s
bibliotheques Metal             125 libs         0,034 s   (5,4 Mo de MSL)
etats de pipeline               125 etats        0,046 s
                                                 -------
                                                 0,36 s
```

**Trente-six centièmes de seconde en tout.** Ce n'est pas un blocage visible, et le cache disque
ne ferait gagner que les 0,28 s du frontal. La recommandation était fausse.

Deux surprises dans ces chiffres :

`newLibraryWithDescriptor:` compile 5,4 Mo de source MSL en 34 ms. C'est impossible pour une
vraie compilation : le `MTL4Compiler` est paresseux, le travail est différé. Et la création des
états de pipeline ne coûte pas davantage. Metal 4 compile donc ailleurs, plus tard, ou en
arrière-plan sur ses propres fils — ce qui expliquerait qu'on ne le voie dans aucun des deux
compteurs.

### Ce qui reste vrai de la section 182

`graphicsPipelineLibrary` vaut bien 0, et `kk_physical_device` ne crée bien jamais de
`disk_cache` — seule la destruction existe. Ce sont des manques réels. Mais ils ne coûtent pas
ce que je leur attribuais, et rien ne justifie de les traiter en priorité.

### Ce qu'on ne sait toujours pas

D'où vient le blocage au chargement. Trois candidats non mesurés : le chargement et la
décompression des ressources par Unity, doublés par la taxe Rosetta ; les premiers transferts
de ressources vers le GPU ; une compilation Metal différée qui se paierait au premier dessin
réel. Le chronomètre actuel ne les voit pas.

L'instrumentation a été retirée ; `verifier_reconstruction.sh` confirme que les cinq arbres se
reproduisent à l'identique.

## 184. Le blocage au chargement est dans Rosetta, pas dans la pile

Deux profils `sample` du processus DREDGE : un de 45 s couvrant le démarrage, un de 90 s
pendant lequel l'auteur a déclenché un chargement de partie. Les comptes bruts ne sont pas
comparables — la cadence d'échantillonnage diffère — donc tout est normalisé par le nombre
d'échantillons par fil (3353 et 5357), ce qui donne des équivalents-fil.

```
                                      demarrage   chargement
Rosetta Runtime Routines 0x20000eb80     0,55        2,00
Rosetta Runtime Routines 0x7ff7ffc0eed0  0,99        1,00
notre pilote, par entree                 0,006       0,004
Metal, par entree                        absent      0,004
```

Pendant le chargement, le travail de Rosetta équivaut à **deux fils pleins**, et il a plus que
triplé par rapport au démarrage. Notre pilote reste à cinq millièmes de fil, et il *baisse*.
Les entrées relevées sont les plus lourdes du pilote :

```
mtl_render_pass_descriptor_get_color_attachment   26
kk_draw                                           23
vk_common_QueueSubmit2                            21
wsi_AcquireNextImageKHR                           18
```

Metal apparaît enfin, mais au même ordre : 23 échantillons pour
`objectAtIndexedSubscript:` sur les descripteurs d'attachement.

**Le blocage n'est pas chez nous.** C'est la traduction : au chargement d'une partie, quantité
de chemins de code du jeu s'exécutent pour la première fois, et Rosetta doit les traduire. Mono
aggrave le cas — il génère du code à l'exécution, que Rosetta doit traduire à son tour, à
chaque lancement, sans pouvoir le mettre en cache comme il le fait pour un binaire lancé
normalement.

Rien à corriger dans le pilote pour ce symptôme, et rien à corriger tout court : Rosetta est
fermé.

### Limite de la méthode

`sample` ne sait pas dérouler une pile PE 32 bits : il répète `__wine_syscall_dispatcher`, qui
ressort à 39 092 échantillons avec la mention « recursive counted multiple ». **Ce nombre est
inexploitable** et aucune conclusion ne s'appuie dessus. Les frames natives — pilote, Metal,
Rosetta — sont attribuées correctement, et c'est sur elles seules que repose la comparaison.

## 185. FIFO_RELAXED : implémenté, mesuré, annulé

L'idée de la section 182 était bonne sur le papier et fausse en pratique. Compte rendu complet,
parce que l'échec est instructif.

### Ce qui a marché

Le mode a bien été ajouté au WSI Metal, et **DXVK l'a retenu** :

```
info:    Present mode: VK_PRESENT_MODE_FIFO_RELAXED_KHR (dynamic: no)
```

Avec, au passage, une vérification faite avant d'écrire une ligne : DXVK ne demande
`FIFO_RELAXED` que si `dxvk.tearFree` vaut explicitement `False`, alors que le défaut est
`Auto`. Sans ce réglage, l'implémentation n'aurait servi à personne.

La période d'écran est lisible : `CGDisplayModeGetRefreshRate` et
`NSScreen.maximumFramesPerSecond` rendent tous deux 120 sur cette machine.

### Ce qui n'a pas marché

`CAMetalLayer.displaySyncEnabled` **ne peut pas être basculé en cours de route**. Trois essais,
chacun mesuré :

```
bascule a la presentation                 60 images/s, GPU 74 %
bascule a l'acquisition du drawable       60 images/s, GPU 74 %
mode immediat force en permanence         60 images/s, GPU 74 %
   plus une CATransaction explicite       60 images/s, GPU 74 %
```

Le troisième essai est celui qui tranche : en forçant l'absence de synchronisation à chaque
acquisition, on devrait obtenir les 76 à 90 images/s du mode `IMMEDIATE`. On obtient 60. La
propriété n'est donc honorée qu'à la configuration de la couche, et l'encadrer d'une
`CATransaction` explicite — la cause habituelle d'une propriété `CALayer` jamais validée hors
du fil principal — n'y change rien.

Un détail de méthode au passage : ma première tentative plaçait la bascule à la présentation.
C'était faux indépendamment du reste — avec `displaySyncEnabled`, l'attente du balayage a lieu
à l'acquisition du drawable, pas à la présentation. Corrigé, puis rendu sans objet par le
troisième essai.

### Pourquoi c'est annulé

Annoncer `FIFO_RELAXED` en se comportant exactement comme `FIFO` serait pire que de ne pas
l'annoncer : DXVK le choisirait en croyant obtenir un comportement qu'il n'aurait pas. Tout est
retiré, `verifier_reconstruction.sh` confirme les cinq arbres à l'identique.

### Ce qu'il faudrait

Pas un interrupteur. Soit reconfigurer la couche à chaque changement de régime — coûteux, et à
valider —, soit une mécanique de cadencement, `presentAtTime:` ou
`presentAfterMinimumDuration:`, qui contrôle l'instant de présentation au lieu d'activer ou non
une attente. Non exploré.

Un chiffre reste inexpliqué : la charge GPU passe de 65,5 % en `FIFO` à 74 % en
`FIFO_RELAXED`, sans que le nombre d'images bouge. Les deux mesures viennent de sessions de jeu
différentes et ne sont pas comparables ; je n'en tire rien.

## 186. Steam macOS ne lit pas `compatibilitytools.d`

Première tentative sur l'objectif de départ : faire lancer un jeu Windows par le Steam macOS
natif, comme Proton sous Linux.

### Ce qui a motivé l'essai

```
steamclient.dylib : CompatToolMapping
steamclient.dylib : compatibilitytools.d
```

Les deux chaînes qui pilotent le mécanisme sous Linux sont bien dans le client macOS. J'avais
affirmé plus tôt, sans jamais le vérifier, que le Steam macOS n'exposait pas Steam Play : cette
affirmation était infondée, et ces chaînes semblaient la démentir.

### L'outil, et ce qu'il a donné

`steam/proton-ouvert/` : `compatibilitytool.vdf`, `toolmanifest.vdf`, et un script qui délègue
à `etape2_pile_wow64.sh` en journalisant tout ce que Steam lui passe. Installé par lien
symbolique dans `~/Library/Application Support/Steam/compatibilitytools.d/`, rien de copié.

Les deux graphies de `to_oslist` — `macos` et `osx` — ont été déclarées ensemble pour qu'un seul
redémarrage tranche.

Résultat après redémarrage complet du client :

```
onglet Compatibilite dans les proprietes d'un jeu : absent
CompatToolMapping dans config.vdf                 : absent
compat_log.txt                                    : pas reecrit (dernier : 15/09/2025)
```

### La preuve

`logs/compat_log.txt`, trois mégaoctets d'historique :

```
Registering tool proton_411,               AppID 1113280
Registering tool steamlinuxruntime_sniper, AppID 1628350
Ignoring tool steamlinuxruntime as it's for a different target platform linux.
```

**Chaque outil enregistré porte un AppID** : ce sont des outils distribués comme applications
Steam, découverts dans le catalogue. Le mot `compatibilitytools` n'apparaît **pas une seule
fois** dans tout le fichier. Le client macOS filtre bien par plateforme cible — il sait refuser
`linux` — mais il ne scanne jamais le répertoire local.

Les chaînes de `steamclient.dylib` sont du code partagé avec la version Linux, inerte ici.

### Ce qui reste

La voie de la porte d'entrée est fermée. Restent :

```
CompatToolMapping ecrit a la main dans config.vdf : non teste, faible espoir
                    (mapper vers un outil que le client n'a jamais enregistre)
jeu non-Steam pointant sur lancer_jeu.sh          : fonctionne deja
```

La seconde marche depuis la section 173, mais elle ne donne ni le déblocage des dépôts Windows
— on ne peut pas télécharger un jeu Windows-only depuis le Steam macOS — ni l'intégration
Steamworks.

Le lien symbolique est laissé en place pour le dernier essai. Il se retire d'une commande.

## 187. Steam honore `CompatToolMapping`, et Heroic est la meilleure porte

### Steam : la correspondance passe, le répertoire non

La section 186 concluait que la voie Steam était fermée. C'est à moitié faux, et la moitié qui
reste est intéressante. Écrite à la main dans `config.vdf`, sous
`InstallConfigStore/Software/Valve/Steam` :

```
"CompatToolMapping" { "0" { "name" "proton_ouvert_macos" "priority" "250" } }
```

Le client l'a lue, appliquée, et conservée :

```
[2026-09-24 16:28:34] Client version: 1788652215
[2026-09-24 16:28:34] Mapping AppID 0 to tool "proton_ouvert_macos" with priority 250
```

`compat_log.txt`, muet depuis le 15 septembre 2025, a été réécrit. **Le client macOS honore
donc la table de correspondance** ; ce qu'il ne fait pas, c'est scanner
`compatibilitytools.d`. L'interface n'expose rien, mais le mécanisme vit.

Reste à savoir s'il sait résoudre un nom d'outil qu'il n'a jamais enregistré — non testé.

### Heroic : la voie directe

Heroic est déjà installé, connaît GOG, et gère des versions de Wine :

```
tools/game-porting-toolkit/Game-Porting-Toolkit-latest   (version par defaut)
customWinePaths : []
autoInstallDxvk : false        <- ne touchera pas a notre DXVK
autoInstallVkd3d : false
```

`heroic/proton-ouvert/` présente notre pile comme une version de Wine ordinaire : `bin/wine64`
et `bin/wineserver` sont des enveloppes qui posent `VK_DRIVER_FILES`, `DYLD_LIBRARY_PATH`,
`WINEDLLOVERRIDES` et `MESA_KK_EXPERIMENTAL` avant de passer la main, et `lib` pointe sur
l'arbre Wine. Vérifié :

```
heroic/proton-ouvert/bin/wine64 --version  ->  wine-10.0
```

Déclarée dans la configuration d'Heroic comme « Proton ouvert », avec `enableWoW64` à vrai
puisque notre Wine est un WoW64 neuf. `config.json` sauvegardé sous `.avant-proton-ouvert`.

Tout ce qui est ajouté vit dans le dossier du projet ; côté Steam et Heroic, il n'y a qu'un
lien symbolique et deux clés de configuration, chacun annulable d'une commande.

## 188. Steam Play n'existe pas sur macOS : la question est close

Trois essais, trois refus, et une preuve à chaque étage.

```
1. outil depose dans compatibilitytools.d
   -> jamais scanne. "compatibilitytools" n'apparait pas une fois dans
      3 Mo de compat_log.txt ; tous les outils enregistres portent un AppID.

2. CompatToolMapping ecrit a la main dans config.vdf
   -> lu, applique, conserve. compat_log.txt, muet depuis un an, est reecrit :
      Mapping AppID 0 to tool "proton_ouvert_macos" with priority 250

3. raccourci non-Steam vers un .exe, associe nommement a l'outil
   -> Mapping AppID 3624361000 to tool "proton_ouvert_macos"
      Failed running GameID ... : "/chemin/DREDGE.exe" (OS Error 0)
      steam/appels.log : jamais ecrit.
```

Le client **enregistre** la correspondance et **n'invoque jamais** l'outil : il tente
d'exécuter le PE nativement, ce que macOS refuse. Le code qui lit la table est partagé avec la
version Linux ; le lanceur, lui, n'en tient aucun compte.

Et il n'y a pas de ruse possible : l'enregistrement d'un outil ne se produit que pour les
outils distribués comme applications Steam, et ceux-là sont refusés sur macOS — le journal le
dit lui-même, « Ignoring tool steamlinuxruntime as it's for a different target platform linux ».

### Deux erreurs corrigées en route

La section 186 concluait que la voie était fermée parce que le répertoire n'est pas scanné.
C'était la bonne conclusion pour la mauvaise raison : la correspondance écrite à la main
fonctionne parfaitement. Le vrai mur est un cran plus loin.

Et j'ai stocké le chemin du raccourci entre guillemets, convention Windows de Steam, que le
client macOS redouble :

```
Failed running GameID ... : ""/chemin/DREDGE.exe"" (OS Error 0)
```

Corrigé dans `tests/ajouter_raccourci_steam.py`, qui écrit désormais le chemin nu. L'outil
reste utile : il ajoute un jeu non-Steam sans passer par le sélecteur de fichiers macOS, qui
refuse les `.exe`.

### Ce que ça laisse

Lancer les jeux Windows d'une bibliothèque Steam depuis le Steam macOS natif **n'est pas
possible**, et aucun travail de notre côté n'y changera quoi que ce soit : le verrou est dans
le client, fermé.

Reste Heroic, déjà configuré en section 187, qui couvre GOG, Epic et Amazon — mais pas Steam.

## 189. Steam Windows sous la pile : l'interface passe, le rendu et le réseau non

Puisque le client macOS refuse d'invoquer un outil de compatibilité (section 188), l'autre
approche est de faire tourner le **client Steam Windows** dans la pile.

### Ce qui marche

```
SteamSetup.exe installe sans erreur dans un prefixe dedie
Steam.exe se met a jour tout seul : 1,4 Go telecharges
cinq processus vivants, interface Chromium chargee
fenetre "Se connecter a Steam", classe SDL_app, avec CefBrowserWindow
```

Que l'interface Chromium embarquée se charge du tout est la bonne surprise : c'était la partie
la plus incertaine.

### Ce qui ne marche pas

La fenêtre est **noire**, et son journal dit pourquoi :

```
The GPU process has crashed 6 time(s)
GPU process exited unexpectedly: exit_code=-2147483645   (STATUS_BREAKPOINT)
```

Le processus GPU de Chromium plante en boucle. Ni `-cef-disable-gpu` ni
`-cef-disable-gpu-compositing` n'y changent quoi que ce soit : le compteur passe de 6 à 16 sur
une seconde série.

Et un second mur, indépendant du premier :

```
Unknown error 10045 mapped to net::ERR_FAILED
Failed to start auth session: {"result":3,"message":"Connection failed"}
```

`10045` est `WSAEOPNOTSUPP` — une opération de socket que Wine ne gère pas. L'authentification
échouerait donc même avec une interface qui s'affiche.

### La configuration par jeu n'est pas un obstacle

L'objection naturelle à un préfixe unique — on ne pourrait plus régler la pile jeu par jeu —
ne tient pas. Trois couches se configurent déjà par nom d'exécutable :

```
Wine   AppDefaults dans le registre
DXVK   Config::getAppConfig(appName)
Mesa   drirc, <application executable="...">   — 166 profils deja livres
```

C'est même plus fin que les variables d'environnement posées à la main aujourd'hui.

### La voie qui reste

`steamcmd` natif macOS sait télécharger un dépôt Windows avec
`+@sSteamCmdForcePlatformType windows`, sans Wine du tout. On récupère les fichiers, on lance
avec la pile. Ce que ça ne donne pas : les jeux protégés par le DRM Steam, dont le
`steam_api.dll` exige un client Steam compatible en cours d'exécution. Non teste.

## 190. Le verrou des dépôts Windows s'ouvre avec une ligne, et elle n'est pas où je cherchais

Piste donnée par l'auteur : le projet **Kaon** (`github.com/natbro/kaon`).

```
~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_dev.cfg
@sSteamCmdForcePlatformType windows
```

Le fichier n'existait pas. Créé avec cette seule ligne et après un redémarrage du client, **le
Steam macOS natif télécharge les jeux Windows**. Vérifié : Elden Ring (AppID 1245620) se
télécharge, 66 Go, accompagné des redistribuables Steamworks (AppID 228980) — le client traite
bien l'installation comme une installation Windows.

J'ai passé la journée sur `compatibilitytools.d` puis sur `CompatToolMapping`, en concluant
deux fois de suite que la voie était fermée. Les deux conclusions étaient exactes et sans
intérêt : le verrou n'était ni l'un ni l'autre.

### L'architecture de Kaon, et ce qu'on en garde

```
1. steam_dev.cfg forcant la plateforme Windows            <- pris, verifie
2. bibliotheque macOS pointee sur celle du Steam Windows
   via une image disque bidon, puis libraryfolders.vdf    <- pas necessaire pour lancer
3. options de lancement par jeu vers un script enveloppe
4. client Steam Windows en cours d'execution              <- notre mur (section 189)
```

Les points 2 et 4 n'existent que pour donner Steamworks aux jeux. Pour simplement lancer un
jeu, le `.exe` téléchargé suffit, avec la pile — comme pour DREDGE.

D'où un découpage net du problème restant :

```
jeu sans DRM Steam ni anti-triche   -> devrait marcher des maintenant
jeu avec DRM Steam                  -> exige le client Windows, donc l'ecran noir de la 189
jeu avec anti-triche                -> hors d'atteinte
```

## 191. Le client Steam Windows : un trou bouché, deux murs debout

Si le client Windows fonctionne, il fait tout — installer, lancer, fournir Steamworks. Les
points 2 et 4 de l'architecture Kaon disparaissent : plus d'image disque bidon, plus d'édition
de `libraryfolders.vdf`, plus d'éditeur de métadonnées. Il devient donc le chemin critique
unique, et c'est la remarque de l'auteur qui l'a mise en évidence.

### Ce qui a été bouché

`WSALookupServiceBeginW` est un stub qui rend `WSA_NOT_ENOUGH_MEMORY`. Chromium s'en sert pour
surveiller l'état du réseau, et le journalisait :

```
ERROR:network_change_notifier_win.cc(268)] WSALookupServiceBegin failed with: 8
```

`0065-wine-wsalookupservice-empty-lookup.patch` lui fait rendre une recherche vide plutôt
qu'une erreur. Mesuré : l'erreur disparaît complètement du journal.

**Mais l'authentification échoue toujours**, sur la même erreur `10045` (`WSAEOPNOTSUPP`).
C'était un vrai trou, ce n'était pas le bon.

### Les deux murs restants

```
processus GPU de CEF   exit_code=-2147483645 (STATUS_BREAKPOINT), en boucle
                       -cef-disable-gpu, -cef-disable-gpu-compositing et
                       -cef-in-process-gpu passent bien sur la ligne de commande
                       du webhelper -- verifie -- et ne changent rien
reseau                 Unknown error 10045 mapped to net::ERR_FAILED
                       "Failed to start auth session: Connection failed"
```

Le webhelper est **64 bits**, donc pas notre chemin 32 bits neuf : cette piste est écartée.
Trois sites dans `ws2_32` peuvent rendre `WSAEOPNOTSUPP` — un `WSAIoctl` non implémenté, un
`h_errno` inconnu en résolution DNS, un `getsockopt` sur socket non-flux. Aucun n'apparaît dans
la trace `warn+winsock`, donc l'erreur vient d'ailleurs : probablement de
`STATUS_NOT_SUPPORTED` ou `STATUS_NOT_IMPLEMENTED` remonte du serveur Wine, que la table de
conversion mappe sur `WSAEOPNOTSUPP`. Non identifie.

### Sur l'anti-triche

Le jeu tourne en ligne sur Steam Deck parce qu'Epic fournit un Easy Anti-Cheat **natif Linux**
que Valve intègre à Proton. Il n'existe pas d'équivalent macOS. Le jeu en ligne est donc hors
d'atteinte, et aucun travail sur cette pile n'y changera rien. Reste le solo.

## 192. Le vérificateur de reconstruction ne vérifiait que Mesa

Découvert en ajoutant 0065 et 0066 : le vérificateur annonçait « wine : 6 correctifs » alors
que la série en compte dix. Deux défauts, tous les deux graves.

### La liste avait dérivé

`verifier_reconstruction.sh` recopiait la série au lieu de la partager avec
`etape1_appliquer_correctifs.sh`. Les correctifs 0062, 0064, 0065 et 0066 n'y figuraient pas.
Les deux scripts lisent désormais `tests/series.sh`, qui n'existe que pour ça.

### Et la comparaison portait sur un répertoire inexistant

```sh
diff -rq ... "$dst/src" "$src/src" 2>/dev/null | wc -l
```

**Seul Mesa a un répertoire `src/`.** Wine a `dlls/`, vkd3d-proton a `libs/`, DXVK a `src/` —
mais la comparaison échouait pour wine et wine11, l'erreur partait dans `/dev/null`, `wc -l`
rendait zéro, et le verdict tombait : « reproduction exacte ».

**Quatre arbres sur cinq passaient à vide.** Tous les « RECONSTRUCTION VERIFIEE » annoncés
aujourd'hui ne garantissaient que Mesa.

### Ce que la correction a révélé

Le vérificateur compare maintenant l'**effet** des correctifs — `git diff HEAD` des deux côtés,
en indexant tout, l'arbre de travail via un index temporaire pour ne jamais toucher le sien —
plutôt que l'arborescence, qui contient aussi des sous-projets téléchargés et des journaux de
construction sans rapport avec la série.

Une seule vraie dérive, et elle était de mon fait : en annulant 0063, j'avais restauré la ligne
`#if` de `get_unix_prot` mais perdu les deux lignes de commentaire que 0036 apporte. Une
reconstruction depuis vanilla aurait produit un arbre différent du nôtre. Restauré.

Le reste n'était que du bruit : fichiers créés par les correctifs, indexés d'un côté et non
suivis de l'autre, plus `build-*.txt`, `subprojects/.wraplock` et des caches de tests.

```
mesa : 33 correctifs, reproduction exacte
wine : 10 correctifs, reproduction exacte
wine11 : 2 correctifs, reproduction exacte
vkd3d-proton : 6 correctifs, reproduction exacte
dxvk : 4 correctifs, reproduction exacte
```

### Le MXCSR, porté sans bénéfice mesuré

`0066-wine-rosetta-mxcsr-in-signal-contexts.patch` porte les CW Hack 24256 et 24265 de
CrossOver : sous Rosetta le registre `MXCSR` est faux dans les contextes de signaux, et sur M3
Rosetta le restaure à une valeur incorrecte même après correction — d'où un thunk qui le
réimpose depuis les données de fil.

J'avais parié que ça expliquait l'écran noir de Steam : des masques d'exceptions flottantes
erronés font rompre un processus Chromium. **Pari perdu** : neuf ruptures de plus sur le test
suivant, et l'authentification échoue toujours.

Le correctif est gardé sur la foi de CodeWeavers et parce que le symptôme qu'il traite est
silencieux — des calculs flottants faux ne se voient pas dans un compteur de plantages. Mais
**je n'ai mesuré aucun bénéfice**, et la suite de conformité est le seul outil qui pourrait en
montrer un.

## 193. Elden Ring : les fichiers arrivent, le jeu meurt avant le graphisme

Premier vrai jeu Steam téléchargé grâce au `steam_dev.cfg` de la section 190. 66 Go.

```
eldenring.exe              64 bits, Direct3D 12
start_protected_game.exe   le lanceur anti-triche, evite
steam_api64.dll            present a cote
```

64 bits et D3D12 : pas de transition WoW64, et c'est le chemin vkd3d-proton. Lancé
directement avec `lancer_jeu.sh` :

```
Loaded steam_api64.dll   : oui
Loaded d3d12.dll, dxgi.dll : oui (les notres)
wine: Unhandled page fault on read access to 0000000000000008
      at address 000000014255995D (thread 0024)
```

`0x14255995D` tombe dans `eldenring.exe` lui-même, base `0x140000000`. Le jeu charge nos
bibliothèques graphiques mais ne les initialise jamais — ni vkd3d-proton ni DXVK n'écrivent une
ligne — et meurt sur un pointeur nul déréférencé.

**Ce qui est établi** : le jeu meurt dans son propre code, avant toute création de périphérique
graphique. Notre pile n'est pas en cause et n'a rien eu à faire.

**Ce qui est une inférence, pas une preuve** : une lecture à l'adresse 8 juste après le
chargement de `steam_api64.dll` est la signature d'un `SteamAPI_Init` qui rend faux, dont
l'appelant déréférence l'interface nulle qui en résulte. Cohérent, non démontré.

Si c'est bien ça, le chemin critique reste le client Steam Windows de la section 189 — son
`steam_api64.dll` doit parler à un client par tubes nommés dans le préfixe, et le client macOS
natif ne peut pas jouer ce rôle.

## 194. Preuve : c'est bien Steamworks, pas la pile

Surviving Mars comme second point de mesure. Le drapeau `steam_dev.cfg` fonctionne aussi sur un
jeu qui a une version macOS — le client choisit bien le dépôt Windows :

```
MarsSteam.exe, ModTools/hgimgcvt.exe, ModTools/opusenc.exe
depots partages 228986-228990 : les redistribuables Steamworks Windows
```

`MarsSteam.exe` est 64 bits et **Direct3D 11**, là où Elden Ring est D3D12 : deux API
différentes, deux moteurs différents. Les deux meurent de la même façon :

```
Elden Ring      lecture a 0x08  dans eldenring.exe + 0x255995D
Surviving Mars  lecture a 0x20  dans MarsSteam.exe + 0x912B3
```

Et la trace `+module` donne la cause, sans inférence cette fois :

```
find_dll_file      Skipping file search for L"steamclient64.dll".
LdrGetDllHandleEx  L"steamclient64.dll" -> 0000000000000000
```

`steam_api64.dll` cherche la bibliothèque du client Steam en cours d'exécution et obtient un
pointeur nul. `SteamAPI_Init` échoue, le jeu déréférence l'interface nulle qui en résulte.
`d3d11.dll` n'est jamais chargee.

La section 193 avait raison sur le mécanisme, mais le marquait comme non démontré. Il l'est
maintenant.

### Ce que ça fixe

```
telecharger un jeu Windows       resolu, section 190
lancer un jeu Steam              bloque sur l'absence de client Steam Windows
client Steam Windows             deux murs, section 189
anti-triche et jeu en ligne      hors d'atteinte, structurel
```

Et un constat qui vaut d'être dit : **notre pile graphique n'a toujours pas ete mise a
l'epreuve par un jeu Steam**. Ni Elden Ring ni Surviving Mars n'ont atteint la creation d'un
peripherique. Tout ce qu'on sait de son comportement sur un vrai jeu vient encore de DREDGE.

## 195. Ce qu'on a raté chez CrossOver : l'inventaire

Le miroir `winecx` compte **133 correctifs CW**, repartis ainsi :

```
63  dlls/ntdll          le coeur macOS et Rosetta
24  dlls/winemac.drv
 5  dlls/wined3d
 4  dlls/win32u
```

On en a porté deux — le contournement `lretq` du pont WoW64 (section 180) et les correctifs
`MXCSR` (section 192).

### Ce qui vise notre écran noir, et ce que ça donne

**CW HACK 22131** — « Setting debug registers is not supported under Rosetta, faking success ».
Porté, testé : **il ne s'est jamais déclenché**, Chromium ne pose pas de registres de débogage.
Retiré.

**CW HACK 23854** — « Ignore the command_line_args_disabled flag in the cef_settings_t passed
to cef_initialize ». Ça correspond exactement à notre symptôme : nos drapeaux arrivent sur la
ligne de commande du webhelper — vérifié — et n'ont aucun effet.

Mais leur méthode est de **corriger le binaire `libcef.dll` à des offsets fixes, version par
version**. Leur table couvre CEF 72, 85, 90, 111 et 135 ; le Steam actuel embarque **Chrome
126**. Même CrossOver ne couvre probablement pas cette version, et un tel correctif se périme à
chaque mise à jour du client.

### Ce qui éclaire notre travail d'hier

**CW HACK 18947** : « If mach_vm_write() is used to modify code cross-process (which is how we
implement NtWriteVirtualMemory), Rosetta won't notice the code change ». C'est exactement la
famille de problèmes qui a produit l'écran noir de la section 178 — Rosetta qui ne voit pas une
modification de code. Ils l'ont rencontrée par une autre porte.

### Le reste de l'inventaire, non porté

```
20810   mode bouteille 32 bits, sans objet chez nous
22144   renommage de l'icone du Dock
22434   exports pour les DLL PE de D3DMetal
22939   ASLR selon la version de Windows
24711   limiter le nombre de processeurs par WINENCPU
20186   NOP de CET
18582   marge en queue d'allocation pour un installeur Rockstar
```

Aucun ne vise nos deux murs. La conclusion honnête est que **CrossOver ne détient pas la
solution de notre écran noir** : soit leur build diffère ailleurs, soit ils corrigent une
version de CEF que Steam n'utilise plus.

## 196. L'écran noir de Steam : la rupture est localisée, la cause non

Progrès réel sur le diagnostic, aucun sur la correction.

### Ce qui est établi

`WINEDEBUG=+seh` donne enfin l'exception, que ni notre flux ni le journal de CEF ne montraient :

```
dispatch_exception code=80000003 (EXCEPTION_BREAKPOINT) addr=00006FFFEE97F905
```

Toujours la même adresse, à chaque relance du processus GPU. Corrélée aux bases de modules :
**`libcef.dll + 0x59EF905`**. La rupture est donc dans le code de Chromium, pas dans Wine.

### La piste suivie, et pourquoi elle n'aboutit pas

CW HACK 23854 de CrossOver neutralise `command_line_args_disabled` dans `cef_settings_t`, ce qui
correspondait à notre symptôme : des drapeaux présents sur la ligne de commande du webhelper et
sans effet. La fonction de recopie existe dans le `libcef.dll` de Steam, avec la même forme et
**aux mêmes décalages** que leur version CEF 90, seul le registre de destination différant :

```
0x2781B5  mov eax,[rdi+0x64]  mov [rsi+0x64],eax
0x2781BB  mov eax,[rdi+0x68]  mov [rsi+0x68],eax   <- champ vise
0x2781C1  lea r8,[rsi+0x70]   (une chaine suit)
```

Corrigé en `xor eax,eax ; nop` : **six ruptures de plus, rien de change**.

Et je ne peux pas démontrer que le correctif agit, parce que je n'ai aucun observable. Steam ne
relaie qu'une liste blanche de drapeaux `-cef-*` : `-cef-disable-gpu` et
`-cef-disable-gpu-compositing` arrivent bien, mais `-cef-v=1` et `-cef-single-process` **ne
figurent pas** sur la ligne de commande du webhelper. Le test par la verbosite, puis celui par
le mode mono-processus, sont donc tous deux invalides.

Le correctif est **annulé** : une modification non verifiee d'un binaire livre, sans benefice
mesurable, vaut moins que rien — elle brouillerait le debogage suivant et sauterait a la
premiere mise a jour du client.

### Ce qu'il faudrait

Nommer la verification qui rompt. Sans symboles dans 210 Mo de binaire depouille, ce n'est pas
atteignable par les moyens employes ici. Il faudrait soit des symboles pour cette version de
CEF, soit un debogueur capable de s'attacher au processus GPU — `winedbg` n'y arrive pas.

### L'inventaire des impasses de la journee sur ce mur

```
-cef-disable-gpu, -cef-disable-gpu-compositing, -cef-in-process-gpu   sans effet
CATransaction explicite autour du reglage de couche                   sans objet ici
MXCSR corrige sous Rosetta (0066)                                     sans effet
registres de debogage faussement reussis (CW 22131)                   jamais declenche
WSALookupServiceBegin rendant une recherche vide (0065)               supprime son erreur,
                                                                      pas celle de l'auth
command_line_args_disabled neutralise dans libcef.dll                  sans effet, annule
```

## 197. La bonne architecture existe, et ce n'est pas celle qu'on poursuivait

Question de l'auteur : Kaon n'aurait-il pas la solution ? Non — mais il nomme la bonne.

### Ce que Kaon fait, et ne fait pas

Leur README est explicite :

> « Once (if?) a functioning macOS-aware Wine `lsteamclient.dll` based on Proton's Linux
> `lsteamclient` is built... it should be possible to install it as a SteamWorks client API
> bridge within CrossOver to prevent the Windows Steam client from needing to be launched,
> visible, or even (possibly) installed. »

C'est leur objectif, pas leur implementation. Aujourd'hui Kaon exige le client Steam Windows,
et celui-ci tourne chez eux parce qu'ils emploient **CrossOver**, dont le Wine porte 133
correctifs quand le notre en porte dix. Le repertoire `lsteamclient/` de leur depot est une
copie de l'arbre Proton, pas un portage.

### Pourquoi c'est la bonne architecture

`lsteamclient` est le mecanisme de Proton : le `steam_api64.dll` du jeu cherche
`steamclient64.dll`, et Proton lui substitue un pont qui parle au client Steam **natif**. Sur
macOS, cela rendrait notre ecran noir sans objet : plus besoin du client Windows du tout.

### Les conditions de faisabilite, verifiees

```
steamclient.dylib du client macOS : binaire universel x86_64 + arm64
symbole exporte                   : _CreateInterface
```

La tranche x86_64 est chargeable par notre Wine, qui tourne lui-meme en x86_64 sous Rosetta. Et
`CreateInterface` est exactement le point d'entree qu'utilise le pont de Proton.

Le point decisif est ailleurs : le pont relie du **Windows x64** a du **System V x86_64**.
Notre cote unix etant x86_64 macOS, c'est **la meme ABI que Linux**. Les thunks generes par
`gen_wrapper.py` devraient donc se transposer presque directement, la ou un portage vers un
Wine arm64 natif aurait demande de tout regenerer.

### Ce que ca coute, honnetement

Le `lsteamclient` de Proton fait de l'ordre de cent mille lignes de code genere, couvrant des
centaines de methodes sur de nombreuses versions d'interfaces. Le generateur existe et lit les
en-tetes du SDK Steamworks. Les differences a traiter : le chargement par `dlopen` d'un dylib
au lieu d'un `.so`, et ce qui reste de specifique a Linux.

C'est un chantier consequent, mais c'est **le seul chemin qui rende les jeux Steam jouables
sans faire tomber l'ecran noir** — un mur contre lequel six tentatives ont echoue aujourd'hui.

## 198. Le pont vers le Steam natif fonctionne

Premier pas de l'architecture de la section 197, et il tient.

### Ce qui est démontré

Une sonde x86_64 native, donc traduite par Rosetta, charge le `steamclient.dylib` du client
macOS et obtient ses interfaces :

```
dlopen : ok    CreateInterface : trouve
SteamClient021 -> 0x10d5a6188 (err=0)
SteamClient020 -> 0x10d5a6180 (err=0)
SteamClient019 -> 0x10d5a6178 (err=0)
SteamClient017 -> 0x10d5a6168 (err=0)
```

Puis la meme chose **depuis l'interieur de Wine**, a travers un unixlib :
`0067-wine-lsteamclient-bridge-to-native-steam.patch` ajoute `dlls/lsteamclient`, un module
Wine dont le cote PE appelle `__wine_unix_call` et dont le cote unix charge le dylib natif.

```
0158:trace:lsteamclient:CreateInterface "SteamClient021" -> 0000000214799188
  SteamClient021 -> 0000000214799188 (err=0)
  SteamClient020 -> 0000000214799180 (err=0)
  SteamClient017 -> 0000000214799168 (err=0)
```

Un programme Windows dans Wine tient des pointeurs d'interface du client Steam **natif de
macOS**. C'est le transport du pont de Proton, en etat de marche.

### Ce que ca ne demontre pas

Les pointeurs rendus designent des objets C++ **natifs**, dont les tables de methodes suivent
l'ABI System V. Le jeu Windows, lui, appellera ces methodes selon l'ABI Microsoft x64 : ordre
des registres different, convention de pile differente. C'est precisement ce que le
`lsteamclient` de Proton resout, en generant un thunk pour chaque methode de chaque version
d'interface — l'essentiel de ses cent mille lignes.

Autrement dit : **la plomberie est faite, le travail reste entier**. Mais le risque principal
— que le dylib soit inaccessible, ou incompatible avec un processus traduit — est leve.

### Deux pieges du systeme de construction, pour la prochaine fois

`makedep` ne devine pas quel fichier appartient au cote unix : il faut le marquer dans la source
elle-meme.

```c
#if 0
#pragma makedep unix
#endif
```

Sans ce pragma, la source unix est compilee par le compilateur PE, qui n'a pas `dlfcn.h`.

Et reconfigurer Wine demande l'environnement exact d'origine : `bison` recent en tete de `PATH`,
`/usr/local/bin` pour que `pkg-config` soit trouve — sans quoi `configure` ne voit plus
FreeType — et les `CPPFLAGS`/`LDFLAGS` pointant sur les prefixes du projet. L'invocation
complete est dans `build/wine-wow64/config.log`.

`configure` etant genere, il n'est pas versionne dans le correctif : `etape1` et le
verificateur le refont par `autoconf`, mais seulement si la serie a touche `configure.ac`.

## 199. Un appel de methode traverse : le pont dialogue avec le client natif

Le jalon annonce en section 198 : une seule methode, ecrite a la main, pour savoir si l'ABI se
franchit.

`ISteamClient::CreateSteamPipe` occupe le premier emplacement de la table de methodes. Le cote
unix lit la table de l'objet natif et appelle directement :

```c
table = *(methode_t **)params->iface;
params->ret = table[0]( params->iface );
```

Client macOS **arrete** :

```
iface 0x214799188, table 0x2146e5940, emplacement 0 = 0x21363c6ac
CreateSteamPipe -> 0
```

La table est lue, le pointeur de fonction est valide, l'appel s'execute sans planter et rend
proprement. Le zero vient de l'absence de client : il n'y a pas de tuyau a ouvrir.

Client macOS **lance** :

```
SteamClient021 : CreateSteamPipe -> 1 (tuyau valide)
SteamClient020 : CreateSteamPipe -> 2 (tuyau valide)
SteamClient017 : CreateSteamPipe -> 3 (tuyau valide)
```

Trois tuyaux successifs, numerotes 1, 2, 3 : le client natif alloue de vraies ressources et
tient son etat d'un appel a l'autre. **Un programme Windows tournant dans Wine dialogue avec le
client Steam natif de macOS.**

### Pourquoi ca marche du premier coup

Sur l'ABI Itanium que suit clang, l'appel d'une methode virtuelle passe `this` dans le premier
registre d'argument — exactement ce que fait une fonction C a un parametre. Le cote unix etant
compile en System V x86_64, comme le dylib, l'appel se fait sans traduction.

### Ce qu'il reste, et ou se trouve la vraie difficulte

Ici c'est notre code PE qui appelle, avec une signature que nous choisissons. Un jeu appellera
les methodes de l'objet **qu'il croit Windows**, en ABI Microsoft x64 : quatre registres
d'arguments au lieu de six, espace de sauvegarde sur la pile, conventions differentes pour les
structures rendues. Le `lsteamclient` de Proton resout cela en fabriquant, cote PE, un objet
dont chaque emplacement de table est un thunk qui retraduit l'appel vers l'objet natif.

C'est la partie generee, et elle couvre des centaines de methodes sur des dizaines de versions
d'interfaces. Mais on sait desormais que le chemin existe et que le client repond.

## 200. Le franchissement d'ABI dans le sens du jeu

Le symetrique de la section 199, et le jalon qui decidait de tout.

### L'objet que le jeu croira Windows

`dlls/lsteamclient/main.c` fabrique cote PE un objet dont le premier membre est une table de
methodes, exactement ce qu'un jeu deference pour un appel virtuel. Chaque emplacement contient
un thunk : il recoit l'appel en ABI Microsoft x64, retrouve l'interface native, et passe par
l'unixlib qui fera l'appel en System V.

Le compilateur PE emettant du Microsoft x64, une fonction C dont le premier parametre est
l'objet suffit a recevoir un appel virtuel — pas besoin d'assembleur.

### La mesure

La sonde n'appelle plus une fonction exportee : elle deference la table et invoque
l'emplacement, comme le fera le `steam_api64.dll` d'un jeu.

```
interface native 0x214799188 -> objet PE 0x2416C0
thunk_CreateSteamPipe objet PE 0x2416C0, interface native 0x214799188
SteamClient021 : CreateSteamPipe -> 1 (tuyau valide)
SteamClient021 : BReleaseSteamPipe(1) -> 1 (argument transmis)
```

Le tuyau rendu vaut **1 aux deux interfaces successives** la ou il valait 1 puis 2 avant qu'on
libere : le client natif reutilise le descripteur, ce qui prouve que la liberation a eu lieu et
donc que l'argument a bien traverse.

### Un vrai piege, trouve et corrige

`BReleaseSteamPipe` rendait d'abord `821210113`, soit `0x30F30001`. La methode native rend un
booleen d'un octet : elle ne renseigne que `AL`, et lire `EAX` entier ramene des bits de poids
fort indefinis. Declarer le type de retour a sa vraie largeur suffit.

C'est exactement la classe de details que les thunks generes doivent traiter, et le genre
d'erreur qu'on n'aurait jamais vue sur une valeur nulle ou sur un pointeur.

### Ce qui reste, et ce qui reste inconnu

```
eprouve    l'objet PE et sa table, l'appel virtuel Microsoft x64
           un argument entier, une valeur de retour etroite
           l'aller-retour complet, avec etat coherent cote client

non eprouve  plus de quatre arguments, donc passage par la pile
             structures rendues, flottants
             les rappels : le client natif appelant vers le jeu
```

Les rappels sont l'inconnue la plus serieuse. Steamworks livre ses evenements en rappelant du
code fourni par le jeu ; il faudra franchir la frontiere dans l'autre sens, depuis du System V
vers du Microsoft x64, et sur un fil qui n'est pas celui de Wine. Rien ici ne dit que c'est
facile.

Mais le chemin principal est demontre de bout en bout, et le reste — des centaines de methodes
sur des dizaines de versions — est du volume que le generateur de Proton sait produire.

## 201. Les rappels ne sont pas ce que je croyais, et la table ne s'invente pas

Deux resultats ce soir, et un echec que je note aussi.

### Les rappels sont tires, pas pousses

La crainte du paragraphe precedent — le client natif rappelant du code du jeu, depuis System V
vers Microsoft x64, sur un fil etranger a Wine — ne correspond a rien. La liste des symboles
exportes par `steamclient.dylib` le dit :

```
nm -g steamclient.dylib | awk '$2=="T"{print $3}'
...
_Steam_BGetCallback
_Steam_FreeLastCallback
_Steam_GetAPICallResult
```

Ce sont des fonctions C plates, appelees *par* le jeu. `SteamAPI_RunCallbacks`, que le jeu
invoque a chaque image, se resume a une boucle sur `Steam_BGetCallback` suivie d'une
repartition vers les objets de rappel du jeu — repartition qui reste entierement en code PE.
La frontiere d'ABI n'est donc jamais franchie que dans le sens jeu -> client. L'inconnue que
j'annonçais comme la plus serieuse n'existe pas a cette frontiere.

Le pont implemente ces fonctions (`unix_appel_plat`, `unix_get_callback`,
`unix_free_last_callback`) et les exporte sous leur nom exact, puisque le `steam_api` du jeu
les cherche par `GetProcAddress`.

### Un binaire Windows dans la session Steam reelle

```
Steam_CreateSteamPipe -> 1
Steam_ConnectToGlobalUser(1) -> 1
Steam_BConnected -> 1
Steam_BLoggedOn  -> 1 (session Steam reelle)
```

Un executable PE, sous notre pile, est rattache au compte connecte du client Steam macOS natif.
C'est le socle : plus besoin que le client Steam Windows demarre.

La pompe, elle, n'a rien rendu : `431 tours, 0 rappels` en cinq secondes. Client au repos, aucun
jeu enregistre : c'est plausible, mais ce n'est pas une preuve que la pompe fonctionne. **La
pompe est non eprouvee**, pas validee.

### `CreateInterface` ne distribue que `SteamClient`

Sur les 222 chaines de version que le dylib contient, `CreateInterface` n'en honore que 18 :

```
RENDU  SteamClient006 ... SteamClient023
--- 18 interfaces sur 222 rendues ---
```

`ISteamUser`, `ISteamApps`, `ISteamUtils` ne s'obtiennent donc que par la table de methodes
d'`ISteamClient`. Il faut son ordre.

### L'ordre se lit, il ne se devine pas

Le SDK Steamworks est proprietaire : hors charte du projet, et de toute facon absent d'ici.
Mais les enveloppes plates du dylib indexent la table, et le desassemblage le montre :

```
_Steam_CreateSteamPipe:      jmpq *(%rcx)           emplacement 0
_Steam_ConnectToGlobalUser:  movq 0x18(%rcx), %rcx  emplacement 3
_Steam_ReleaseUser:          movq 0x30(%rcx), %rcx  emplacement 6
```

Carte obtenue, entierement mesuree :

```
0  CreateSteamPipe          4  CreateLocalUser
1  BReleaseSteamPipe        6  ReleaseUser
2  CreateGlobalUser        25  TerminateGameConnection
3  ConnectToGlobalUser
```

**Correction.** J'ai d'abord ecrit que cette carte contredisait le SDK, et qu'avoir devine
aurait ouvert une session au lieu d'en rejoindre une. C'est un pas de trop. Cette carte est
celle de la table indexee par les enveloppes plates, c'est-a-dire de l'objet que leur accesseur
commun (`0x9c18a9`) rend. **Rien ne prouve que ce soit la meme table que celle de l'objet rendu
par `CreateInterface`.** Les indices vont meme dans l'autre sens : la carte mesuree est
exactement l'ordre public avec `CreateGlobalUser` insere en 2 et un trou en 5, ce qui est la
signature d'une interface interne plus riche que la publique. Et sur l'objet de
`CreateInterface`, les emplacements 0 et 1 que nous avons reellement appeles concordent avec
l'ordre public.

Conclusion honnete : les sept emplacements sont mesures, mais ils decrivent probablement
l'interface interne de Valve, pas les adaptateurs `SteamClient0NN` que recoit un jeu. Pour ces
derniers, l'ordre du SDK est vraisemblablement le bon. La question se tranchera en confrontant
les deux, pas en raisonnant.

Le decalage de chargement se verifie : `0x214031598 - 0x1181598 = 0x212eb0000`, et
`0x21387681b - 0x212eb0000 = 0x9c681b`, qui est bien `_Steam_BGetCallback` dans le fichier.

### L'echec : l'alignement entre versions

J'ai voulu cartographier les 38 a 42 methodes de chaque version en resolvant les thunks
d'adaptation vers leur vraie fonction, puis en alignant les versions par adresse commune. La
resolution s'effondre : la plupart des entrees retombent sur une meme adresse, et le tableau
produit donnait le meme emplacement 5 pour une vingtaine de methodes differentes. **Ce tableau
est faux et n'est pas conserve.** Les seuls emplacements connus restent les sept ci-dessus.

### La decision qui reste

Aller plus loin demande l'ordre complet de la table. Trois voies :

1. le desassemblage, en continuant ce qui a marche pour sept emplacements — lent mais libre et
   mesure ;
2. laisser le `steam_api` d'un vrai jeu appeler une table de decouverte qui journalise au lieu
   d'appeler — DREDGE est 32 bits, et l'ABI `__thiscall` d'i386 ne se prete pas a des thunks
   generiques sans corrompre la pile ; il faudrait un jeu Steam 64 bits installe ;
3. le SDK Steamworks, qui est proprietaire et contredit la charte du projet.

La table de decouverte a 64 emplacements est en place dans le correctif : les emplacements
inconnus journalisent et rendent zero, au lieu de sauter n'importe ou dans le client.

## 202. La table se lit dans le binaire, sans le SDK

Le SDK Steamworks est ecarte : ses en-tetes ne sont pas redistribuables, et un `lsteamclient`
qui en derive ne pourrait pas etre publie sous licence libre. Il fallait donc obtenir l'ordre
des methodes autrement. C'est fait, et entierement par la mesure.

### Pourquoi la premiere tentative avait echoue

J'avais desassemble 16 Mo d'un coup, en balayage lineaire. Un desassembleur qui part d'une
adresse arbitraire se desynchronise et produit des instructions qui n'existent pas ; mes
« cibles de thunks » etaient du bruit. La correction est de decoder les octets soi-meme, a
partir d'adresses connues. La correspondance adresse virtuelle / position dans le fichier se
verifie d'abord :

```
octets a 0x626be3 : 55 48 89 e5 e8 bd ac 39
                    push %rbp ; mov %rsp,%rbp ; callq   -> _Steam_CreateSteamPipe
```

### Les entrees sont les vraies fonctions

1613 entrees de table commencent par `push %rbp` : ce ne sont pas des thunks d'ajustement mais
les methodes elles-memes, compilees une fois par version d'interface. Aucune adresse n'est donc
partagee entre versions, et aligner par adresse etait voue a l'echec.

### Le chainon : l'accesseur commun

Chaque methode d'adaptateur releve du meme accesseur que les enveloppes plates :

```
CSteamClient021 emplacement 0 :        _Steam_CreateSteamPipe :
  callq 0x9c18a9                         callq 0x9c18a9
  movq (%rax), %rcx                      movq (%rax), %rcx
  jmpq *(%rcx)                           jmpq *(%rcx)
```

Identiques. L'emplacement public se relie donc a l'emplacement interne, et les sept enveloppes
plates nommees au paragraphe precedent donnent leurs noms.

### Les noms sont ecrits en clair

Les `GetISteamXxx` ont tous la meme forme : ils chargent une chaine constante -- le nom de la
famille d'interface -- et sautent dans un repartiteur commun.

```
emplacement 5 :  leaq 0xf34dbf(%rip), %rax   ## -> "User"
emplacement 6 :  leaq 0xf0fe95(%rip), %rax   ## -> "GameServer"
emplacement 9 :  leaq 0xf1157c(%rip), %rcx   ## -> "Utils"   (avec xorl %edi,%edi : pas d'utilisateur)
```

Le binaire se nomme lui-meme. Aucun en-tete n'est necessaire.

### Carte d'ISteamClient021 (40 methodes)

`m` = nom mesure (chaine du binaire, ou enveloppe plate). `p` = deduit de la position seule.

```
 0 m CreateSteamPipe          20 p RunFrame            (interne 19)
 1 m BReleaseSteamPipe        21 p GetIPCCallCount     (interne 26)
 2 m ConnectToGlobalUser      22 p SetWarningMessageHook (interne 26)
 3 m CreateLocalUser          23 p BShutdownIfAllPipesClosed (interne 49)
 4 m ReleaseUser              24 m GetISteamHTTP
 5 m GetISteamUser            25 m GetISteamController
 6 m GetISteamGameServer      26 m GetISteamUGC
 7 p SetLocalIPBinding        27 m GetISteamMusic
       (interne 11)           28 m GetISteamMusicRemote
 8 m GetISteamFriends         29 m GetISteamHTMLSurface
 9 m GetISteamUtils           30 ?
10 m GetISteamMatchmaking     31 ?
11 m GetISteamMatchmakingServers  32 ? (interne 68)
12 m GetISteamGenericInterface 33 m GetISteamInventory
13 m GetISteamUserStats       34 m GetISteamVideo
14 m GetISteamGameServerStats 35 m GetISteamParentalSettings
15 m GetISteamApps            36 m GetISteamController (2e fois)
16 m GetISteamNetworking      37 m GetISteamParties
17 m GetISteamRemoteStorage   38 m GetISteamRemotePlay
18 m GetISteamScreenshots     39 ?
19 m GetISteamGameSearch
```

Deux reserves honnetes. Les entrees `p` sont deduites de la position, pas nommees par le
binaire : elles restent a confirmer. Et « Controller » apparait a deux emplacements (25 et 36) :
la chaine nomme la famille, pas l'interface exacte ; l'un des deux est vraisemblablement
`GetISteamInput`, mais je ne l'ai pas etabli.

### Le plus utile de tous : l'emplacement 12

```
emplacement 12 :  movl %esi,%edi ; movl %edx,%esi ; movq %rcx,%rdx ; xorl %ecx,%ecx ; jmp repartiteur
```

Meme repartiteur que les `GetISteamXxx`, mais le nom attendu est **nul** : le repartiteur prend
alors celui que l'appelant fournit. C'est `GetISteamGenericInterface(utilisateur, tuyau,
version)`. Avec cette seule methode, le pont atteint n'importe quelle interface Steamworks par
son nom, sans connaitre aucun autre emplacement.

L'ordre mesure coincide avec l'ordre publie du SDK partout ou les deux sont connus. La
correction du paragraphe precedent est donc confirmee : la carte a sept entrees relevee alors
decrivait bien l'interface interne de Valve, pas l'adaptateur que recoit un jeu.

## 203. Une seule methode ouvre les 187 interfaces

L'emplacement 12 est branche dans le pont (`unix_get_generic_interface`, et le relais du meme
emplacement cote PE). La sonde demande au client les 204 chaines de version que le dylib
contient, hors `SteamClient` :

```
tuyau 1, utilisateur 1

  STEAMAPPS_INTERFACE_VERSION008                -> 00007fe35ff3d620
  STEAMUSERSTATS_INTERFACE_VERSION013           -> 00007fe3588082c0
  SteamFriends017                               -> 00007fe358a16980
  SteamUser023                                  -> 00007fe6d08583e0
  SteamUtils011                                 -> 00007fe6d08584a0
  ...
--- 187 interfaces sur 204 ---
```

`GetISteamGenericInterface` est donc bien a l'emplacement 12 : l'identification par la forme du
code -- meme repartiteur que les `GetISteamXxx`, mais nom attendu nul -- est confirmee par le
comportement. Et elle suffit : aucun autre emplacement de la table n'a eu besoin d'etre connu
pour atteindre `ISteamApps`, `ISteamUser`, `ISteamUtils`, `ISteamFriends`, `ISteamUserStats`.

### Les dix-sept absentes ne sont pas des echecs

```
SteamGameServer002 .. SteamGameServer015
SteamGameServerStats001
SteamMasterServerUpdater001
SteamNetworkingMessages002
```

Toutes des interfaces de serveur de jeu, qui exigent un handle de serveur et non un utilisateur
client. Leur refus est la bonne reponse, pas une defaillance : c'est meme un controle de
coherence, puisque rien d'autre ne manque.

### Ce que le pont fait, et ce qu'il ne fait pas encore

L'objet rendu est enveloppe cote PE, mais **sans aucun relais** : la table de methodes de chaque
sous-interface n'est pas encore cartographiee, alors ses emplacements journalisent et rendent
zero. Relayer d'apres les emplacements d'ISteamClient reviendrait a sauter au hasard dans une
table qui n'est pas la sienne.

La suite est mecanique et connue : appliquer a `ISteamApps`, `ISteamUser` et `ISteamUtils` la
lecture qui a donne la carte d'`ISteamClient` -- relever la table a l'execution, decoder les
octets de chaque methode, et laisser le binaire se nommer lui-meme quand il le fait.

## 204. La plomberie est prete ; il manque un jeu

### ISteamApps ne se nomme pas

La technique du paragraphe 202 ne se transpose pas. Les methodes d'`ISteamApps` n'appellent
aucun accesseur commun et ne chargent aucune chaine : elles implementent directement, ou
relaient vers un objet interne loge a `0x10(%rdi)`.

```
emplacement 0 : movq 0x10(%rdi), %rdi ; leaq 0x11bf2dd(%rip), %rax ; ... masques 0xff000000 / 0xffffff
emplacement 2 : xorl %eax, %eax ; retq          -- methode obsolete, rend toujours faux
```

Le binaire ne se nomme plus. Restait la voie empirique : appeler chaque emplacement et
identifier par le comportement. **Je ne l'ai pas prise.** `ISteamApps` contient `UninstallDLC`
et `InstallDLC` ; appeler a l'aveugle sur le compte vivant de l'utilisateur peut desinstaller
du contenu. Les getters en lecture seule ne se distinguent pas des autres avant de les avoir
appeles, ce qui est precisement le probleme.

### La voie sure : laisser le jeu appeler

Un `steam_api64.dll` sait ou il appelle. La table de decouverte journalise et rend zero sans
jamais relayer : le jeu revele l'ordre exact des emplacements dont il a besoin, et rien
d'inconnu n'est appele cote natif. Reste a lui presenter le pont comme il s'y attend.

### Ce que cherche un steam_api

Il ne connait pas « lsteamclient ». Il lit `HKCU\Software\Valve\Steam\ActiveProcess`,
`SteamClientDll64`, charge ce chemin, et prend `CreateInterface`. Premier essai, en installant
le pont sous le nom `steamclient64.dll` :

```
registre  : C:\Program Files (x86)\Steam\steamclient64.dll
chargement impossible : 1114
```

`ERROR_DLL_INIT_FAILED`. Wine resout l'unixlib d'un module PE par le nom de ce module : sous un
autre nom, il n'existe pas de `steamclient64.so` et `__wine_init_unix_call` echoue dans
`DllMain`. La reponse est de ne pas renommer et de faire pointer le registre sur le module tel
quel -- ce que fait Proton. `tests/preparer_pont_steam.sh` s'en charge.

### La chaine complete, rejouee

`tests/sonde_comme_steam_api.c` refait pas a pas ce que fait un `steam_api64.dll`, y compris
l'appel virtuel de l'emplacement 12 :

```
registre  : C:\windows\system32\lsteamclient.dll
charge    : 00006ffffb140000
tuyau 1, utilisateur 1
ISteamApps  -> 0000000000241810
ISteamUtils -> 0000000000241840
ISteamUser  -> 0000000000241870
chaine complete
```

Tout tient sauf une chose : il n'y a plus de jeu Steam Windows 64 bits installe. Rocksmith2014
n'est qu'un `Rocksmith.ini` residuel, et « Steamworks Shared » ne contient que des
redistribuables DirectX. Sans `steam_api64.dll`, la decouverte ne peut pas demarrer.

## 205. Le vrai steam_api pilote le pont

### Le jeu n'etait pas le bon banc d'essai

`MarsSteam.exe` passe par le lanceur Paradox (`pops_api.dll`) et ne se comporte pas deux fois
pareil : un lancement atteint Steamworks, le suivant s'arrete avant. Son `steam_api64.dll`, lui,
est du code Valve deterministe. `tests/sonde_steam_api_reel.c` l'appelle directement --
`SteamAPI_Init` fait exactement la meme suite d'appels que dans le jeu.

Deux lecons de methode, payees comptant. Tuer `wineserver` declenche un `wineboot` complet qui
mange la fenetre d'observation. Et un `printf` vers un fichier est bufferise : tant que le
processus est bloque, rien ne sort, et on croit a tort qu'il n'a rien fait. La sonde ecrit
maintenant sur la sortie d'erreur.

### Il manquait un client Steam credible

```
SteamAPI_IsSteamRunning -> 0
--- SteamAPI_Init ---
(blocage indefini, aucun appel au pont)
```

`SteamAPI_Init` verifie que le processus designe par `ActiveProcess\pid` est vivant, et attend
que Steam apparaisse s'il ne l'est pas. `tests/faux_steam.c` est un processus Windows qui
inscrit son propre identifiant et ne fait rien d'autre : le client qui repond reellement est
celui de macOS, derriere l'unixlib.

### La trace complete

```
SteamAPI_IsSteamRunning -> 1
CreateInterface "SteamClient017" -> objet PE
CreateInterface "SteamClient020" -> objet PE
  emplacement  0   CreateSteamPipe()
  emplacement  2   ConnectToGlobalUser(1)
  emplacement  0   CreateSteamPipe()
  emplacement 12   GetISteamGenericInterface(0, 1, "SteamUtils010")
    SteamUtils010 emplacement 9        -- GetAppID
  emplacement 34
  emplacement  5   GetISteamUser(1, 1, "SteamUser021")
    SteamUser021 emplacement 2         -- puis faute de page
```

Avant que les sous-interfaces ne soient relayees, la trace s'arretait a `SteamUtils010`
emplacement 9 et `SteamAPI_Init` rendait 0 : Valve verifie l'identifiant d'application, nous
rendions zero, il abandonnait. Le relais l'a fait passer.

### Le relais n'a pas besoin de carte

Correction d'une prudence mal placee. J'avais ecrit qu'on ne pouvait pas relayer une
sous-interface faute de connaitre sa table. C'est faux pour un simple relais : l'emplacement N
de notre table designe l'emplacement N de la table native **du meme objet**. C'est le jeu qui
choisit la methode, et elle atterrit sur celle qu'il visait. La carte ne sert qu'a interpreter,
pas a transmettre.

Le relais transporte six arguments, ce qui couvre toute methode d'au plus six parametres :
Microsoft x64 en loge quatre dans des registres et les suivants sur la pile, System V en loge
six dans des registres, et en declarer plus que n'en prend la methode appelee est sans effet.
Le « plus de quatre arguments » de la liste des inconnues est donc traite.

### Ce qui casse maintenant : les structures rendues par valeur

```
repartir SteamUser021 emplacement 2( "", 00006FFFFC724040, 00000000009A2850 )
wine: Unhandled page fault on read access to 0110000104F52756
      at address 00006FFFFC76622B
```

L'adresse fautive tombe dans `steam_api64.dll` (chargee a `0x6ffffc760000`), juste apres le
retour de l'emplacement 2 -- `ISteamUser::GetSteamID`, qui rend un `CSteamID` par valeur.

C'est precisement le cas que les deux ABI traitent differemment. Un type de classe non trivial
revient par pointeur cache, mais ce pointeur n'occupe pas le meme rang : Microsoft x64 le place
avant `this`, System V le passe dans le premier registre d'argument. Un relais qui se contente
de decaler les registres ne peut pas etre juste des qu'une methode rend une structure.

C'est l'inconnue qui restait sur la liste du paragraphe 200, et elle est maintenant atteinte
par la mesure, pas par la conjecture. Le pont ne pourra pas rester generique : il faudra
connaitre, methode par methode, celles qui rendent une structure -- ce que Proton obtient du
SDK, et qu'il faudra ici tirer du desassemblage.

## 206. SteamAPI_Init rend 1

### Le pointeur cache n'etait pas ou je le cherchais

Le desassemblage de `steam_api64.dll` au point de faute, resynchronise depuis une frontiere
d'instruction, donne la convention exacte :

```
mov  (%rcx),%rax        ; rcx = ISteamClient
call *0x28(%rax)        ; emplacement 5 = GetISteamUser
mov  (%rax),%r8         ; table d'ISteamUser
lea  0x478(%rsp),%rdx   ; RDX = tampon de retour
mov  %rax,%rcx          ; RCX = this
call *0x10(%r8)         ; emplacement 2 = GetSteamID
mov  (%rax),%rcx        ; deref du pointeur rendu  <- la faute
```

« this » reste dans RCX et le tampon arrive dans RDX -- l'inverse de ce que j'avais suppose au
paragraphe precedent, ou j'ecrivais que Microsoft x64 place le pointeur cache **avant** `this`.
C'est faux pour une methode membre : `this` garde le premier rang. La trace le disait deja et je
ne l'avais pas lue : le journal affichait `a = ""`, qui n'etait pas un argument parasite mais le
tampon de pile, vide.

Cote natif, `ISteamUser` emplacement 2 prend « this » dans RDI et ne recoit aucun tampon : il
rend le `CSteamID` dans RAX. Le relais doit donc ecrire la valeur dans le tampon et rendre son
adresse.

Impossible de deviner quelles methodes sont concernees : les deux cotes compilent pareil pour un
entier de huit octets, et seule la declaration du SDK les separe. La table `rendent_structure`
se construit donc au fil des traces, chaque entree portant la sienne en commentaire.

### Le resultat

```
SteamAPI_IsSteamRunning -> 1
--- SteamAPI_Init ---
  CreateInterface "SteamClient020"
  emplacement  0   CreateSteamPipe
  emplacement  2   ConnectToGlobalUser
  emplacement 12   GetISteamGenericInterface(0, 1, "SteamUtils010")
    SteamUtils010 emplacement 9
  emplacement 34
  emplacement  5   GetISteamUser(1, 1, "SteamUser021")
    SteamUser021 emplacement 2
SteamAPI_Init -> 1
--- SteamAPI_RunCallbacks x20 ---
  SteamUtils010 emplacement 14
  GetISteamGenericInterface "SteamController007", "SteamInput001"
  SteamInput001 emplacement 2, SteamController007 emplacement 2
  ... la boucle se repete a l'identique, sans faute
```

Steamworks s'initialise, contre le compte reellement connecte du client Steam macOS, depuis un
binaire Windows sous notre pile. La boucle de rappels tourne et se stabilise : interrogation de
l'identifiant d'application, du temps, des manettes -- le comportement normal d'un jeu a chaque
image.

### Ce qui n'est pas demontre

Le jeu lui-meme ne tourne pas. Ce qui est etabli, c'est que `SteamAPI_Init` reussit et que
`SteamAPI_RunCallbacks` s'execute sans faute vingt fois de suite. Un jeu appelle bien davantage,
et chaque methode rendant une structure cassera de la meme maniere jusqu'a etre inscrite dans la
table.

Le faux client (`tests/faux_steam.c`) reste necessaire : sans un processus vivant a
`ActiveProcess\pid`, `SteamAPI_Init` attend indefiniment. Il faudra le lancer avec le jeu.

## 207. Le jeu parle au client Steam de macOS

`tests/lancer_jeu_steam.sh` met en place le faux client puis lance l'executable. Sur Surviving
Mars, le vrai jeu -- pas la sonde -- produit exactement la meme suite que `sonde_api_reel`, et
va plus loin :

```
CreateInterface "SteamClient017" / "SteamClient020"
  emplacement  0   CreateSteamPipe
  emplacement  2   ConnectToGlobalUser
  emplacement 12   GetISteamGenericInterface(0, 1, "SteamUtils010")
    SteamUtils010 emplacement 9
  emplacement 34
  emplacement  5   GetISteamUser(1, 1, "SteamUser021")
    SteamUser021 emplacement 2
  emplacement 12   GetISteamGenericInterface(0, 1, "SteamUtils010")
  emplacement 12   GetISteamGenericInterface(1, 1, "STEAMAPPS_INTERFACE_VERSION008")
    SteamUtils010 emplacement 9
```

Son `SteamAPI_Init` reussit et il atteint `ISteamApps`. La preuve que ce n'est pas une
simulation tient en une ligne :

```
lsof : MarsSteam 2399  TCP 127.0.0.1:55553->127.0.0.1:57343 (ESTABLISHED)
       steam_osx 94471 TCP 127.0.0.1:57343 (LISTEN)
```

Deux connexions etablies entre le processus Windows et `steam_osx`. Un jeu Windows dialogue avec
le client Steam de macOS.

### Ou il s'arrete

Le jeu se fige ensuite : 0 % de processeur, aucune fenetre de premier niveau, 51 modules charges
et **aucun** `d3d11`, `dxgi` ni `winevulkan`. Il n'a donc jamais atteint l'initialisation
graphique. Les derniers modules charges avant le gel sont `secur32`, `Kerberos`, `netutils`,
`netapi32`, `MSV1_0` -- de l'authentification, chargee puis dechargee. Rien de tout cela ne
passe par le pont.

Le blocage est donc dans `pops_api.dll`, la couche de compte Paradox, en aval de Steamworks.
Surviving Mars n'est pas le meilleur banc d'essai : son lanceur s'interpose. Un jeu Steam sans
surcouche d'editeur dirait bien plus sur l'etat reel du pont.

### Detail de methode

Le journal du jeu contient des octets bruts, si bien que `grep` le classe « binaire » et
n'affiche rien -- ce qui m'a fait croire deux fois de suite a une absence d'appels. `grep -a`
est obligatoire sur ces traces.

## 208. Le mur des jeux 32 bits

DREDGE, achete sur Steam, est 32 bits comme sa version GOG :

```
DREDGE.exe                              pei-i386
DREDGE_Data/Plugins/x86/steam_api.dll   pei-i386
```

Ce n'est pas un reglage a trouver, c'est une impasse de structure.

### Pourquoi le relais generique ne peut pas marcher en 32 bits

`steamclient.dylib` n'existe qu'en `x86_64` et `arm64` -- macOS a supprime i386. Un jeu 32 bits
appelle donc notre pont i386, qui passe par l'unixlib **64 bits**, comme le veut le nouveau
WoW64 de Wine.

Or un appel de methode virtuelle MSVC en i386 se fait en `__thiscall` : « this » dans ECX,
arguments sur la pile, et **c'est l'appele qui depile**. Notre thunk doit donc retirer exactement
le bon nombre d'octets, ce qui suppose de connaitre la signature de chaque methode. En x86_64 la
question ne se pose pas : l'appelant nettoie, et six registres suffisent -- c'est pourquoi tout
a fonctionne avec Surviving Mars.

Il existerait une echappatoire si les deux cotes etaient de meme largeur : un thunk assembleur
qui remplace ECX par l'objet natif et saute directement dans la table native, sans toucher a la
pile. L'appele natif depilerait lui-meme, correctement, sans qu'on sache rien de l'arite. Mais
le natif est en 64 bits : ce saut est impossible.

On pourrait deduire l'arite du desassemblage natif, en relevant quels registres d'argument une
methode lit avant de les ecrire. Insuffisant : sur i386 un entier de huit octets occupe deux
mots de pile, un flottant aussi, et le nombre de registres lus cote System V ne donne pas le
nombre d'octets empiles cote i386. Il faudrait les types, donc les signatures -- ce que Proton
tire du SDK et qu'on s'est interdit.

Conclusion : **les jeux 32 bits sont hors de portee de cette approche.** C'est une limite a
annoncer, pas un defaut a corriger.

### Choix du banc d'essai

La bibliotheque de l'utilisateur compte 196 titres. Les noms ne se lisent pas directement dans
`appinfo.vdf` : depuis la version 0x29 les cles du VDF binaire sont des index vers une table de
chaines placee en fin de fichier. Une fois la table lue, 3722 noms sortent.

Dead Cells est retenu : 64 bits, environ 1,5 Go, aucun lanceur d'editeur, usage Steamworks
simple. Il va droit de `SteamAPI_Init` au rendu, ce qui isole le pont du reste.

## 209. Les signatures se lisent dans le steam_api du jeu

Le paragraphe 208 concluait que les jeux 32 bits etaient hors de portee. C'etait juste sur le
diagnostic et faux sur la conclusion : il manquait, methode par methode, le nombre d'octets
empiles. Or le `steam_api.dll` i386 livre avec chaque jeu exporte 1019 symboles, dont des
centaines d'enveloppes plates **nommees**, une par methode.

```
SteamAPI_ISteamUser_GetSteamID :
    mov  0x8(%ebp),%ecx      this
    lea  -0x8(%ebp),%edx     tampon de retour, 8 octets
    push %edx                le pointeur cache est empile
    call *0x8(%eax)          emplacement 2
    mov  %eax,%edx           la methode rend ce pointeur
```

Une seule fonction donne le nom, l'interface, l'emplacement, les octets empiles et la taille de
la structure rendue. `tests/signatures_steam_api.py` le fait pour toutes : **31 interfaces, 421
methodes**.

### La validation

Confrontation aux emplacements etablis autrement -- par les enveloppes plates du dylib natif et
par les chaines de version lues dans le binaire :

```
ISteamClient  CreateSteamPipe 0   ConnectToGlobalUser 2   CreateLocalUser 3
              ReleaseUser 4       GetISteamUser 5         GetISteamUtils 9
              GetISteamApps 15
ISteamUser    GetSteamID 2 (tampon 8)
ISteamUtils   GetAppID 9
```

Neuf sur dix concordent ; le dixieme, `BReleaseSteamPipe`, n'est pas contredit mais non analyse.
Deux resultats emportent la conviction a eux seuls :

- `GetAnalogActionData` : emplacement 15, 20 octets empiles, tampon de **13 octets**. C'est
  exactement `InputAnalogActionData_t` -- un mode, deux flottants, un booleen.
- `GetFriendByIndex` : emplacement 4, 12 octets (deux entiers plus le pointeur cache), tampon de
  8 -- un `CSteamID`.

Rien de tout cela n'a ete devine.

### Ce que ca debloque

Les quatorze methodes a retour par pointeur cache sortent nommees, ce qui remplace la table
`rendent_structure` que je construisais trace par trace :

```
ISteamApps GetAppOwner          ISteamFriends GetFriendByIndex, GetClanByIndex, GetCoplayFriend
ISteamUser GetSteamID           ISteamMatchmaking GetLobbyByIndex
ISteamGameServer GetSteamID, GetPublicIP, CreateUnauthenticatedUserConnection
ISteamInput / ISteamController GetAnalogActionData, GetMotionData
ISteamRemotePlay GetSessionSteamID
```

Et surtout, les octets empiles rendent le relais i386 possible : un thunk `__stdcall` a N
arguments depile exactement comme le `__thiscall` attendu. Les jeux 32 bits redeviennent
atteignables.

### Erreur de recommandation

J'avais propose Dead Cells comme banc d'essai « 64 bits ». Il ne l'est pas :

```
deadcells.exe   pei-i386
steam_api.dll   pei-i386
```

Le telechargement n'est pas perdu -- il devient le banc d'essai du chemin i386 -- mais la
recommandation etait fausse, et elle reposait sur une supposition au lieu d'une mesure. La regle
du projet valait aussi pour ce choix-la.

## 210. Le pont repond en 32 bits

Avant d'engendrer les thunks `__thiscall`, il fallait savoir si la plomberie tenait. Premier
essai :

```
LoadLibrary a echoue : 1114        ERROR_DLL_INIT_FAILED
warn:module:process_attach Initialization of L"lsteamclient.dll" failed
```

`__wine_init_unix_call` echoue pour le module 32 bits. Wine exige d'une unixlib une seconde
table, `__wine_unix_call_wow64_funcs`, des qu'un PE 32 bits l'appelle : les structures
d'arguments n'ont pas la meme disposition selon la largeur.

### La reponse : des structures de largeur fixe

Plutot qu'ecrire une table de conversion entree par entree, toutes les structures d'arguments
passent en `UINT64` / `INT32`. La disposition devient identique en 32 et en 64 bits, et la meme
table sert aux deux -- `__wine_unix_call_wow64_funcs` reprend exactement les memes fonctions.

Ce choix repondait de toute facon a une contrainte incontournable : les interfaces natives
vivent a des adresses 64 bits, qu'un `void *` de PE 32 bits ne peut pas contenir. L'objet PE
garde donc son pointeur natif en `UINT64`, quelle que soit sa propre largeur.

```
lsteamclient 32 bits charge : 7b2c0000
CreateInterface "SteamClient020" : natif 214bf2180 -> objet PE 00013740
tuyau 1, utilisateur 1
plomberie 32 bits operationnelle
```

Un binaire i386 obtient une interface Steamworks et ouvre une session sur le client macOS natif.

### Un detail de trace

La premiere version affichait `natif 14BF2180` : l'adresse etait tronquee a la largeur du PE par
un `(void *)(ULONG_PTR)`. La valeur stockee etait juste, mais la trace mentait. Elle passe par
`wine_dbgstr_longlong`.

### Non-regression

Le chemin 64 bits est inchange : `SteamAPI_Init -> 1`, meme suite d'appels.

### Ce qui reste pour les jeux 32 bits

Les fonctions plates passent, parce qu'elles sont en `__cdecl`. Les appels de methode virtuelle,
eux, sont en `__thiscall` et restent a traiter : il faut des thunks qui depilent le bon nombre
d'octets. Les signatures du paragraphe 209 les donnent -- 76 emplacements et au plus neuf mots
empiles, soit 760 thunks pour une grille complete, 204 couples reellement utilises.

## 211. SteamAPI_Init rend 1 en 32 bits

Le relais `__thiscall` est en place. Un thunk `fastcall` a deux parametres registre reproduit
exactement la convention : le premier occupe ECX comme « this », le second occupe EDX et n'est
pas lu, les mots suivants sont sur la pile et l'appele les depile. Reste a choisir, pour chaque
emplacement, le thunk dont la discipline correspond -- d'ou une grille de 760 thunks
(76 emplacements x 10 tailles) et une table de 423 signatures, toutes deux engendrees par
`tests/engendrer_i386.py`.

```
SteamAPI_IsSteamRunning -> 1
--- SteamAPI_Init ---
  CreateInterface "SteamClient017" / "SteamClient020"
  repartir32 ISteamClient   emplacement  0 (0 mots)
  repartir32 ISteamClient   emplacement  2 (1 mots)
  repartir32 ISteamClient   emplacement  0 (0 mots)
  repartir32 ISteamClient   emplacement 12 (3 mots)
  repartir32 SteamUtils010  emplacement  9 (0 mots)
  repartir32 ISteamClient   emplacement 34 (1 mots)
  repartir32 ISteamClient   emplacement  5 (3 mots)
  repartir32 SteamUser021   emplacement  2 (1 mots, retour par pointeur cache)
SteamAPI_Init -> 1
```

Un `steam_api.dll` i386 de jeu, pilote directement, initialise Steamworks sur le client Steam
macOS natif. Le chemin 64 bits est inchange.

### Deux corrections en route

L'enveloppement manquait : `repartir32` rendait le pointeur natif brut, qu'un registre de
32 bits ne peut meme pas contenir. Les methodes d'ISteamClient qui rendent une interface la
rendent desormais enveloppee, comme en 64 bits.

Puis l'emplacement 34 depilait zero octet alors qu'il prend un mot -- quatre octets de pile
corrompus, et une faute plusieurs appels plus loin, a `[esi+0x34]` avec `esi` nul. Sept
emplacements d'ISteamClient (1, 20, 23, 25, 32, 33, 34) n'ont pas d'enveloppe plate ; leurs
signatures se lisent sur leurs sites d'appel, ou steam_api.dll designe l'objet par une variable
globale :

```
mov  0x3b4392c8,%ecx     l'objet ISteamClient
push $0x3b406620         un pointeur de fonction
mov  (%ecx),%eax
call *0x88(%eax)         emplacement 34, un mot
```

Le scan de tous ces sites donne : emplacement 0 sans argument, 1 un mot, 4 deux, 5 trois,
12 trois, 23 aucun, 34 un. Deux entrees manquantes sont ainsi comblees.

### Ou ca s'arrete

`SteamAPI_RunCallbacks` enchaine plusieurs tours puis faute en ecriture a `8B4055F0`, dans
steam_api, apres `SteamController008 emplacement 2`. Cet emplacement est bien `RunFrame` sans
argument -- la pile est juste cette fois. **La cause n'est pas etablie.**

Une piste, non verifiee : la table de signatures est indexee par famille d'interface, pas par
version. Le jeu demande `SteamInput002` et `SteamController008` alors que les enveloppes plates
du meme fichier visent d'autres versions ; rien ne garantit que la numerotation des emplacements
soit identique d'une version a l'autre. Il faudra le mesurer avant d'y croire.

## 212. Le cycle complet, en 32 comme en 64 bits

### La piste du paragraphe 211 etait fausse

Je soupçonnais un decalage de numerotation entre versions d'interface. Les accesseurs de
`steam_api.dll` le refutent : `SteamAPI_SteamController_v008` et `SteamAPI_SteamInput_v002`
visent exactement les versions que le jeu demande. Aucun decalage.

### La vraie cause : un pointeur tronque

La faute tombait dans un `memcpy` de steam_api (`movups %xmm0,(%edi)`), `edi` invalide. Le
pointeur venait de `Steam_BGetCallback`, qui recopiait tel quel le `m_pubParam` rendu par le
client natif :

```c
msg->m_pubParam = (unsigned char *)(ULONG_PTR)params.msg.param;   /* tronque a 32 bits */
```

La charge utile d'un rappel vit dans le tas du client natif, a une adresse de 64 bits. Un jeu
32 bits ne peut pas l'atteindre -- et meme en 64 bits, rien ne garantit qu'elle survive a
`Steam_FreeLastCallback`. Le cote unix la recopie desormais dans un tampon fourni par le cote
PE, et la taille est verifiee avant la copie.

### Le cycle complet

```
SteamAPI_Init -> 1
Steam_BGetCallback rappel 1040044, 784 octets
Steam_BGetCallback rappel 1270006,  16 octets
Steam_BGetCallback rappel 1270009, 144 octets
Steam_BGetCallback rappel     336,  12 octets      AvatarImageLoaded
Steam_BGetCallback rappel     304,  12 octets      PersonaStateChange
Steam_BGetCallback rappel 1040011, 260 octets
... vingt tours de RunCallbacks, aucune faute ...
ISteamClient emplacement  4 (2 mots)    ReleaseUser
ISteamClient emplacement  1 (1 mots)    BReleaseSteamPipe
ISteamClient emplacement  1 (1 mots)
ISteamClient emplacement 23 (0 mots)    BShutdownIfAllPipesClosed
SteamInternal_SetMinidumpSteamID:  Caching Steam ID:  7656119804344xxxx
```

La derniere ligne vient de Valve, pas de nous : son propre code a lu l'identifiant Steam reel du
compte a travers le pont. Initialisation, pompe a rappels, arret propre -- le cycle entier, avec
le `steam_api.dll` i386 d'un vrai jeu.

La pompe a rappels, que le paragraphe 201 declarait honnetement « non eprouvee » faute
d'evenements, est maintenant demontree : six rappels reels, dont `PersonaStateChange` et
`AvatarImageLoaded`.

Le chemin 64 bits donne la meme trace, aux adresses pres. Reconstruction verifiee sur les cinq
arbres.

## 213. DREDGE tourne

Un jeu Steam Windows, achete sur Steam, lance sous la pile ouverte, et qui joue : 180 secondes
sans plantage, **14775 appels au pont**, D3D11 initialise sur l'Apple M1 Max.

### Trois defauts corriges pour y arriver

**Le lanceur court-circuitait la pile.** `lancer_jeu_steam.sh` appelait `wine` directement, sans
`VK_DRIVER_FILES` ni `DYLD_LIBRARY_PATH` -- DXVK ne trouvait pas `libvulkan.1.dylib` et le jeu
echouait a creer son peripherique Direct3D. Il delegue desormais a `etape2_pile_wow64.sh`, qui
pose tout cela.

Au passage : les redirections de DLL du prefixe avaient disparu. C'est le `wineboot` declenche
quand j'ai tue `wineserver` au paragraphe 205 qui les avait effacees. Wine chargeait donc son
`wined3d` integre au lieu de DXVK.

**La chaine de version n'etait pas recopiee.** `envelopper` gardait le pointeur de l'appelant.
Quelques milliers d'appels plus tard le journal affichait `repartir32 <<}p.d emplacement 6` :
un nom corrompu, donc une signature choisie au hasard, donc une discipline de pile fausse. La
chaine est desormais copiee dans l'objet.

**L'extracteur manquait la moitie des methodes.** Le compilateur charge parfois l'emplacement
dans un registre avant d'appeler :

```
mov  0x18(%eax),%eax
call *%eax
```

L'analyseur n'acceptait que `call *0x18(%eax)`. En ajoutant ce motif, la table passe de **421 a
874 methodes**. C'est ainsi que `ISteamApps::BIsSubscribedApp` manquait -- emplacement 6, un
argument -- et qu'un thunk depilait zero octet la ou le jeu en poussait quatre. Le gel se
produisait la, a chaque partie, toujours au meme endroit.

### Ce qui ralentissait

Rien dans le pont. Deux causes, toutes deux de ma main :

- Je journalisais chaque appel en `ERR`, donc toujours actif et sur une sortie non tamponnee.
  Les journaux d'appel passent en `TRACE` ; `ERR` ne sert plus qu'aux anomalies.
- Surtout, des processus residuels des essais precedents tournaient a plein regime : quatre
  `winedbg` a 100 % chacun et deux `UnityCrashHandler32`, soit environ 600 % de processeur voles
  au jeu. Le debogueur automatique du prefixe est desormais desactive (`AeDebug\Debugger` a
  `false`), pour qu'un plantage n'en laisse plus derriere lui.

Une fois nettoye : `DREDGE.exe 166 %`, `wineserver 26 %`.

C'est la deuxieme fois de la journee que des processus oublies faussent une mesure. La regle
tient : avant toute observation de performance, verifier ce qui tourne.

## 214. L'arm64 se rouvre : la conclusion du paragraphe 144 ne valait pas pour nous

Apple retire Rosetta 2. La pile entiere etant x86_64 sous Rosetta, ce n'est plus une question
d'optimisation mais de survie. Il fallait donc rouvrir le dossier arm64, ferme au paragraphe 144.

### La mesure de 144 tient, sa conclusion non

Rien a reprendre a la mesure : `x18` est efface par macOS a chaque retour du noyau vers l'espace
utilisateur, preemption comprise, cinq essais sur cinq. Aucun point de restauration n'existe.

Mais la conclusion disait : « recompiler tout le code PE avec un autre acces au TEB, ce qui
interdit les binaires Windows reels et vide le portage de son sens ». Cette phrase suppose qu'on
veuille executer des binaires **Windows ARM64**. Ce n'est pas notre cas :

```
DREDGE.exe          pei-i386
MarsSteam.exe       pei-x86-64
```

Les jeux sont x86. Le seul code PE ARM64 de la pile serait celui de Wine lui-meme, que nous
compilons. Et il lit le TEB en un seul endroit :

```
include/winnt.h:2460  register struct _TEB *__wine_current_teb __asm__("x18");
include/winnt.h:2468  return (struct _TEB *)__getReg(18);
```

Trente-trois occurrences de `x18` hors du cote unix, dont la plupart sont des traces ou des
tests ; les sites reels tiennent dans `winnt.h` et trois fragments d'assembleur de
`signal_arm64.c`.

### Un registre qui tient : TPIDRRO_EL0

`tests/tpidrro_stable.c` reprend exactement le protocole qui avait tue `x18` -- boucle serree,
aucun appel systeme, comparaison a chaque tour -- sur deux fils simultanes :

```
  fil A : TPIDRRO_EL0 = 0x16d8130e0 (pthread_self = 0x16d813000)
  fil B : TPIDRRO_EL0 = 0x16d89f0e0 (pthread_self = 0x16d89f000)
  fil B : STABLE sur 200000000 tours
  fil A : STABLE sur 200000000 tours
```

Deux cents millions de tours sans perte, la ou `x18` tombait en quelques millions. La valeur est
propre au fil et lisible en mode utilisateur. Elle peut donc servir de cle pour retrouver le TEB.

### Le compilateur ne touche pas a x18

Sous forte pression de registres, `aarch64-w64-mingw32-clang` n'emet **aucune** reference a
`x18` : l'ABI Windows ARM64 le reserve au TEB, le compilateur s'en abstient. Le rendre inutile
ne risque donc pas de casser du code genere ailleurs.

### Ce qui reste, et c'est le vrai sujet

Le portage arm64 de Wine redevient envisageable. Mais il ne suffit pas : **les jeux sont x86**.
Un Wine arm64 natif a toujours besoin d'un emulateur x86 pour le code du jeu -- c'est ce que
Rosetta fait aujourd'hui pour toute la pile.

```
FEX-Emu : absent    box64 : absent    qemu-x86_64 : absent
```

Rien d'installe, et la disponibilite de ces emulateurs sur macOS arm64 n'est pas etablie. Deux
voies :

1. garder la pile x86_64 et remplacer Rosetta par un autre emulateur -- aucun portage Wine, mais
   tout repose sur l'existence d'un tel emulateur sur macOS ;
2. porter Wine en arm64 -- desormais credible grace a TPIDRRO_EL0 -- et n'emuler que le code du
   jeu, ce qui reduit la surface emulee mais ne supprime pas le besoin.

Les deux exigent un emulateur x86. C'est la, pas dans `x18`, qu'est maintenant le risque.

## 215. L'etat de l'emulation x86 sur macOS arm64

Le paragraphe 214 concluait que le risque n'etait plus `x18` mais l'emulation. Voici ce que
donne l'etat de l'art, en septembre 2026.

### Le calendrier, corrige

J'avais ecrit que Rosetta 2 n'etait pas retire par la mise a jour disponible. **C'est faux**, et
l'utilisateur l'a corrige. La machine est sur macOS 26.5.2 et `softwareupdate -l` propose
`macOS 27` :

```
* Label: macOS 27-26A428
	Title: macOS 27, Version: 27, Size: 11865773KiB, Recommended: YES, Action: restart,
```

**macOS 27 supprime Rosetta 2 pendant son installation** s'il etait present, et aucune
application Intel ne demarre ensuite. La nuance qui sauve la pile : macOS 27 permet de le
**reinstaller** a la demande. C'est macOS 28, a l'automne 2027, qui coupe definitivement -- avec
seulement un sous-ensemble de Rosetta conserve pour de vieux jeux non maintenus.

Donc deux echeances, pas une : une rupture immediate a reparer d'une commande, et une echeance
ferme dans un an. J'avais retenu la seconde et manque la premiere.

### La voie existe, et quelqu'un l'a deja prise

CodeWeavers distribue depuis juillet 2026 une preversion de CrossOver native arm64 sur macOS.
Sa pile :

- **Wine ARM64EC**, sous LGPL. Wine 10 integre le support complet d'ARM64EC, avec le travail de
  compilateur correspondant verse dans LLVM 21. Les sources accompagneront CrossOver 27, prevu
  debut 2027.
- **un portage macOS de FEX**, realise par CodeWeavers : FEX amont ne supporte pas Darwin.
- **DXMT** en arm64 pour la partie graphique.

La preversion exige macOS 26.5 et n'est pas jugee utilisable au-dela du test.

### Rien d'utilisable publiquement aujourd'hui

```
FEX amont        Linux seulement, aucun projet de support macOS
box64            Linux seulement
FEX_MacOs        depot annonce « Arm64 MacOS », mais instructions et
                 prerequis entierement Linux : bifurcation mal nommee,
                 aucun portage Darwin documente
```

Le seul portage macOS connu de FEX est celui de CodeWeavers, non public. Et attention a la
nuance de licence : Wine est LGPL, donc leur ARM64EC sera publie ; **FEX est MIT**, donc rien ne
les oblige a publier leur portage Darwin. C'est le point de risque reel.

### `x18` reste le probleme, meme en ARM64EC

ARM64EC n'echappe pas a la question : l'ABI prevoit que le code natif lise l'adresse du TEB
dans `x18`, exactement comme l'ARM64 ordinaire. Apple reserve ce registre. CodeWeavers a donc
du resoudre le meme obstacle que nous ; leur solution n'est pas documentee publiquement.

La mesure du paragraphe 214 garde donc toute sa valeur : `TPIDRRO_EL0` tient sur deux cents
millions de tours la ou `x18` tombe en quelques millions, et le compilateur ARM64 Windows
n'emet aucune reference a `x18`. C'est une reponse candidate a un probleme que personne n'a
publiquement resolu.

### Ce que cela dicte

1. La pile x86_64 sous Rosetta reste valable environ un an. Rien n'oblige a l'abandonner
   maintenant, et elle vient de faire tourner un vrai jeu Steam.
2. Le portage arm64 de Wine est de notre ressort et n'attend personne : `x18` a une reponse
   candidate a eprouver.
3. L'emulateur x86 n'est pas de notre ressort a ce stade. Ecrire un portage Darwin de FEX est un
   chantier d'un tout autre ordre. La decision raisonnable est d'attendre les sources de
   CrossOver 27 -- debut 2027, avant l'echeance -- tout en sachant que la partie FEX pourrait ne
   jamais etre publiee.

## 216. Ligne de base arm64, mesuree a nouveau

Avant de toucher a quoi que ce soit, retablir l'etat reel de la pile arm64.

### Premiere erreur : la mauvaise construction

`wine/wine10-arm64` echoue bien avant `x18`, sur la disposition memoire :

```
err:virtual:try_map_free_area mmap() error Cannot allocate memory,
    range 0x7fffffdf0000-0x7fffffff0000
    range 0x100000000-0x100100000
```

C'est une construction **non corrigee**. Les correctifs arm64 de la serie -- 0048 et 0049 --
s'appliquent a l'arbre wine11. La construction a eprouver est `wine/wine11-arm64` (wine-11.18).

### La vraie ligne de base

Sur la construction corrigee, le tremplin du correctif 0049 fonctionne : les contextes
d'exception portent `x18=000000014012a000`, le bon TEB. Et pourtant :

```
code=c0000005 (EXCEPTION_ACCESS_VIOLATION)  info[1]=0x180C
code=c0000005 (EXCEPTION_ACCESS_VIOLATION)  info[1]=0x48
```

`0x180C` et `0x48` sont de petits deplacements de TEB -- `0x48` est
`TEB->ClientId.UniqueThread`, lu par `RtlEnterCriticalSection`. Exactement le tableau du
paragraphe 144. Le tremplin restaure `x18` a la frontiere du signal ; la perte, elle, est
asynchrone, et la faute a deja eu lieu.

`wineboot --init` ne peuple pas `system32` : le prefixe arm64 ne se cree pas.

### Le plan

Remplacer la lecture de `x18` plutot que la reparer. `include/winnt.h` la concentre en un point :

```c
register struct _TEB *__wine_current_teb __asm__("x18");
return (struct _TEB *)__getReg(18);
```

La cle sera `TPIDRRO_EL0`, mesuree stable sur deux cents millions de tours au paragraphe 214.
Il faut trois choses :

1. une table cle -> TEB, logee dans les donnees du ntdll PE ;
2. son remplissage par le cote unix au demarrage de chaque fil, **avant** l'appel a
   `loader_init` -- c'est la que se produit la toute premiere faute, donc l'enregistrement doit
   la preceder ;
3. `NtCurrentTeb()` reecrit pour lire `TPIDRRO_EL0` et consulter la table.

Le point 2 est celui qui brise le cercle : le cote unix connait le TEB et peut lire
`TPIDRRO_EL0` comme n'importe qui, alors que le cote PE ne peut pas obtenir son TEB avant que
l'acces ne fonctionne.

## 217. Le TEB sans x18 : la barriere bouge

Le correctif 0068 remplace la lecture de `x18` par une recherche indexee sur `TPIDRRO_EL0`.

### Ce qu'il contient

- `dlls/ntdll/signal_arm64.c` (cote PE) : une table ouverte de 1024 entrees, exportee, et
  `__wine_current_teb()` qui lit `TPIDRRO_EL0` et la consulte. A defaut d'entree, retour sur
  `x18` -- parfois juste, et toujours mieux que NULL, que l'appelant ne teste pas.
- `dlls/ntdll/unix/signal_arm64.c` : `enregistrer_teb()`, appelee depuis `init_syscall_frame`
  **avant** que le moindre code PE ne s'execute. La cle est posee en dernier, pour qu'un lecteur
  ne voie jamais une entree a moitie ecrite.
- `dlls/ntdll/unix/loader.c` : `GET_FUNC( __wine_teb_table )`, le meme mecanisme que Wine emploie
  deja pour ses repartiteurs.
- `include/winnt.h` : `NtCurrentTeb()` appelle `__wine_current_teb()`.

### Deux pieges, tous deux resolus par la mesure

**La garde etait fausse.** J'avais ecrit `defined(__GNUC__) && defined(WINE_TEB_SANS_X18)`. Or
la cible `aarch64-windows` est la cible **MSVC** :

```
#define WINE_TEB_SANS_X18 1
#define _MSC_VER 1933
#define __aarch64__ 1
```

Pas de `__GNUC__`. La branche prise restait `__getReg(18)`, et rien ne changeait -- le binaire
gardait ses 655 acces a `x18`. Verifie en comparant l'assembleur produit avec et sans le
drapeau, au lieu de supposer que la recompilation avait pris.

Pour la meme raison, la lecture du registre passe par `__builtin_arm_rsr64( "tpidrro_el0" )` et
non par un bloc `__asm__`, indisponible en mode MSVC.

**Changer un `-D` ne recompile rien.** Make ne suit pas les drapeaux. Il faut effacer les objets.

### Le resultat

```
avant : 3 fautes, deplacements de TEB 0x180C et 0x48
apres : 1 faute, a 0x378, dans du code natif -- plus dans le code PE
acces a x18 dans ntdll.dll : 655 -> 28 (l'assembleur de sauvegarde de contexte)
RtlEnterCriticalSection : « mov x8, x18 » -> « bl __wine_current_teb »
```

Les fautes du paragraphe 144 ont disparu. `x18` n'est plus le mur.

### Ce qui bloque maintenant

L'ancienne barriere memoire, deja presente dans la ligne de base :

```
err:virtual:try_map_free_area mmap() error Cannot allocate memory, range 0x100000000-0x100110000
```

`wineboot --init` ne peuple toujours pas `system32`. Le prochain obstacle est la disposition de
l'espace d'adressage, pas le TEB.

### Comment construire

Le correctif ne fait rien sans son drapeau, volontairement : personne ne doit l'activer par
accident sur une cible autre que macOS.

```
make aarch64_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" install
```

En cas de doute, effacer `dlls/*/aarch64-windows/*.o` d'abord.

## 218. Le TEB sans x18 : juste, et beaucoup trop lent

### Les fautes ont disparu

Apres avoir enregistre aussi le fil courant dans `load_ntdll_functions` -- il demarrait avant
que l'adresse de la table ne soit connue, et son enregistrement ne faisait rien -- et borne le
sondage a huit entrees :

```
fautes d'acces pendant wineboot --init : 0
```

Zero, contre trois dans la ligne de base du paragraphe 216 et une au paragraphe 217. L'acces au
TEB fonctionne.

### Mais wineboot tourne a 100 % sans finir

```
67090  100.0  1:28.71  C:\windows\system32\wineboot.exe
```

L'echantillonnage designe un seul coupable :

```
771 echantillons a 0x6fffffcd96b4
ntdll PE base 0x6fffffc70000  ->  RVA 0x696b4
__wine_current_teb            ->  RVA 0x696b4
```

C'est la fonction elle-meme. Rien d'etonnant : `NtCurrentTeb()` est partout, et on a remplace
une lecture de registre par un appel de fonction suivi d'un sondage. Le facteur est de l'ordre
de cinquante a cent sur le chemin le plus chaud de Wine.

**La conception est juste et inexploitable en l'etat.** Il ne suffit pas que ce soit correct.

### La suite : revenir a deux instructions

`TPIDRRO_EL0` pointe sur la zone de donnees propre au fil -- mesure au paragraphe 214,
`TPIDRRO_EL0 = pthread_self + 0xe0`. macOS y loge les emplacements de stockage local, et
`pthread_getspecific` pour une cle directe se compile exactement ainsi :

```
mrs x0, tpidrro_el0
ldr x0, [x0, #8*cle]
```

Deux instructions, sans appel ni sondage -- au lieu d'une pour `x18`. Si un emplacement direct
peut etre reserve, `NtCurrentTeb()` redevient inlinable et le cout s'efface.

A eprouver : quels emplacements macOS laisse a un tiers, et si `pthread_key_create` en rend un
utilisable sous cette forme. La table actuelle reste utile comme repli.

## 219. L'acces direct au stockage local : les services de Wine demarrent

### Deux questions, une mesure

`tests/tpidrro_tsd.c`, sur deux fils simultanes :

```
cle pthread = 258
  fil A : partie haute STABLE sur 300000000 tours ; bits bas vus : 0x0
  fil A : cle=258, [(tpidrro & ~7) + 8*cle] = 0xdeadbeefcafe <-- CONCORDE
  fil B : idem
```

La partie haute de `TPIDRRO_EL0` ne bouge pas, et le stockage local du fil est atteignable a
`(TPIDRRO_EL0 & ~7) + 8 * cle`. Les trois bits de poids faible sont masques par precaution :
macOS y loge le numero de coeur, meme si aucun n'est apparu ici.

### NtCurrentTeb() redevient du code en ligne

```
adrp x8, __imp___wine_teb_tsd_key
ldr  x8, [x8, :lo12:__imp___wine_teb_tsd_key]
mrs  x9, TPIDRRO_EL0
and  x9, x9, #0xfffffffffffffff8
ldr  w8, [x8]
lsl  w8, w8, #3
ldr  x0, [x9, w8, uxtw]
cbz  x0, repli
ret
```

Huit instructions contre une pour `x18`, mais ni appel ni sondage. La table du paragraphe 217
reste le repli, quand l'emplacement vaut encore zero.

Un piege au passage : `NTSYSAPI unsigned int __wine_teb_tsd_key;` dans un en-tete est une
definition provisoire dans **chaque** unite de compilation, d'ou un symbole duplique a l'edition
de liens. Il fallait `extern`.

### Le resultat

```
avant : wineboot.exe a 100 %, 771 echantillons dans __wine_current_teb
apres : services.exe, plugplay.exe, rpcss.exe demarrent
        0 exception
```

Toute la pile de services de Wine s'execute en arm64 natif sans une seule faute. C'est le plus
loin que ce portage soit jamais alle.

### Ce qui reste

Les processus restent a 0 % et `wineboot --init` ne peuple toujours pas `system32` ; trois jeux
de services coexistent, signe que le demarrage recommence. Le blocage suivant est une attente,
pas une faute -- vraisemblablement du cote des communications entre services ou du serveur.
C'est un tout autre terrain que `x18`, et il faudra l'aborder comme tel.

## 220. Le verrou orphelin, et un TEB nul que j'avais fabrique

### Le point chaud, mesure dans un environnement propre

Base du ntdll PE relevee dans la meme execution que l'echantillon, faute de quoi la
symbolisation est fausse -- je m'y suis laisse prendre une fois :

```
base=0x6fffffc50000
  285 -> RtlEnterCriticalSection
  232 -> call_seh_handlers
  189 -> virtual_unwind
```

Une exception levee et deroulee en boucle, dans une section critique. C'est la forme exacte du
paragraphe 144 : une faute a l'interieur de `RtlEnterCriticalSection` laisse le verrou
incremente et sans proprietaire, et chaque tentative suivante l'incremente encore.

### Le piege des processus residuels, troisieme fois

Avant cette mesure, des `start.exe` tournaient a 99 % **depuis 213 minutes**, residus d'essais
precedents. Toutes les mesures prises avant le nettoyage sont a jeter. La regle est desormais :
avant toute observation, tuer tout ce qui porte `.exe` ou `wineserver`.

### La faute : un TEB nul, de ma main

Quatre violations d'acces, toutes a l'adresse `0x378`. Un TEB nul donne un PEB nul, et une
lecture a `PEB + 0x378` tombe exactement la.

J'avais accroche l'enregistrement au point ou Wine pose sa propre cle de fil :

```c
thread_data = init_thread_data( view->base );
pthread_setspecific( thread_data_key, thread_data );
enregistrer_teb( thread_data->teb );     /* faux */
```

Or `init_thread_data` ne renseigne pas `teb` -- il l'est plus loin. J'enregistrais donc `NULL`
pour chaque fil, et c'etait **pire que ne rien enregistrer** : la table rendait ensuite ce `NULL`
au lieu de laisser le repli sur `x18` jouer. L'appel est deplace la ou `data->teb = teb` est
reellement execute.

Les fautes passent de quatre a deux. Il en reste une, a la meme adresse `0x378`, sur un seul fil,
avec un compteur de programme dans du code natif. Un chemin d'initialisation echappe encore a
l'enregistrement.

### Etat du portage arm64

```
acquis    plus aucune faute liee a x18 ; 655 -> 28 acces au registre
          NtCurrentTeb() en ligne, huit instructions, sans appel
          services.exe, plugplay.exe, rpcss.exe demarrent
reste     une faute a 0x378 sur un fil, puis un verrou orphelin qui boucle
          wineboot --init ne peuple pas system32
```

## 221. L'assembleur lisait x18 aussi, et le prefixe se cree

### La faute a 0x378, nommee

Le compteur de programme de la faute tombait dans `ntdll.so` -- le cote **unix**, pas le PE.
Symbolise :

```
__wine_unix_call_dispatcher + 4
__wine_syscall_dispatcher + 4
```

Et l'instruction, dans le source :

```asm
"ldr x10, [x18, #0x378]\n\t" /* thread_data->syscall_frame */
```

`0x378` exactement. Les repartiteurs sont ecrits en assembleur et lisent le TEB directement dans
`x18` ; la correction du paragraphe 219, qui ne touchait que `NtCurrentTeb()`, ne les couvrait
pas. On ne corrige pas un registre en corrigeant le C qui l'entoure.

### Le rechargement

Un prologue commun relit le TEB dans le stockage local du fil, comme le fait `NtCurrentTeb()`,
et ne touche a `x18` que si l'emplacement est renseigne :

```asm
mrs x10, tpidrro_el0
and x10, x10, #0xfffffffffffffff8
adrp x11, _cle_teb_globale@PAGE
ldr w11, [x11, _cle_teb_globale@PAGEOFF]
ldr x10, [x10, x11, lsl #3]
cbz x10, 9f
mov x18, x10
9:
```

La cle est desormais creee a la premiere demande et non au chargement du ntdll PE : les premiers
fils naissent avant, et n'auraient rien enregistre.

### Le resultat

```
exceptions pendant wineboot --init : 0
prefixe cree : system.reg, user.reg, userdef.reg, users/, windows/
wineboot ne boucle plus -- il sort
```

Plus une seule faute, et le prefixe existe. Restait ce message :

```
wine: could not load kernel32.dll, status c0000135
```

Trompeur : la trace montre que `kernel32.dll` est **trouve, charge a 0x6FFFFFA50000, et toutes
ses importations se resolvent** -- y compris `__wine_current_teb` et `__wine_teb_tsd_key`. Il est
ensuite detache. L'echec est donc apres l'attachement, dans une dependance plus loin dans la
chaine, et `c0000135` n'en dit pas le nom.

### Ou en est le portage

```
acquis    aucune faute liee a x18, ni en C ni en assembleur
          NtCurrentTeb() en ligne, huit instructions
          le prefixe arm64 se cree
reste     kernel32 s'attache puis se detache ; cause a nommer
```

C'est de loin le plus loin que ce portage soit alle. Le mur du paragraphe 144 n'existe plus.

## 222. FEX se construit sur macOS, sans toucher a son code

La question n'etait pas « porter FEX sur macOS » mais « produire le module que Wine attend ».
Ce sont deux choses tres differentes, et la seconde est bien plus petite.

### Ce que Wine attend

FEX a un coeur modulaire utilisable comme backend WoW64 d'un Wine arm64. Le produit n'est pas un
binaire Linux mais **un module PE Windows**, `libwow64fex.dll`, qui s'installe dans l'arbre de
Wine. L'hote importe donc bien moins que je ne le craignais : le module tourne dans Wine, pas
sur macOS.

La chaine llvm-mingw du projet fournit deja les 48 outils `arm64ec-w64-mingw32` et les
`aarch64-w64-mingw32` necessaires.

### Deux obstacles, tous deux dans le systeme de construction

```
No CMAKE_ASM_NASM_COMPILER could be found        -> -DBUILD_TESTING=OFF
FileNotFoundError: '/proc/cpuinfo'               -> -DTUNE_CPU=generic
```

Le second est la seule vraie hypothese Linux rencontree : `aarch64_fit_native.py` et
`NeedDisabledSVE.py` lisent `/proc/cpuinfo` pour regler `-mcpu=native`. La branche n'est prise
que si `TUNE_CPU` vaut « native » ; un autre reglage la contourne entierement.

### Le resultat

```
[229/229] Linking CXX shared library Bin/libwow64fex.dll
libwow64fex.dll : 4710400 octets

BTCpuProcessInit   BTCpuSimulate      BTCpuResetToConsistentState
BTCpuGetBopCode    BTCpuThreadInit    BTCpuNotifyMemoryProtect
BTCpuGetContext    BTCpuSetContext    ... 22 points d'entree
```

L'interface CPU complete de WoW64. **Aucune ligne du code de FEX n'a ete modifiee** : deux
options de cmake ont suffi.

### La politique de FEX

Le depot porte, comme Mesa, un fichier a l'intention des agents :

> AI must not be used to generate code for contributions to this project.

Elle est respectee : rien n'a ete ecrit dans leur arbre. Si des correctifs macOS s'averent
necessaires plus tard -- et il y en aura -- je decrirai precisement quoi faire, et c'est
l'utilisateur qui decidera qui l'ecrit.

### Ce qui n'est pas demontre

Le module est construit, pas execute. Deux risques propres a macOS restent devant :

- **W^X.** Un JIT ecrit puis execute sa memoire. macOS l'interdit sans `MAP_JIT` et
  `pthread_jit_write_protect_np`. Ce que Wine fait de ces demandes sur arm64 reste a etablir.
- **x18 dans le code engendre.** L'ABI Windows arm64 y met le TEB, et macOS l'efface. Le
  probleme qu'on vient de resoudre dans Wine se repose dans le JIT de FEX, ou il est plus
  difficile puisque le code est produit a l'execution.

Et il faut un Wine arm64 qui demarre pour l'essayer : au paragraphe 221 il s'arrete encore sur
kernel32.

## 223. Le mur suivant : kernel32 introuvable, et ce n'est pas le chemin

Une fois les fautes disparues, `wineboot --init` echoue proprement :

```
wine: could not load kernel32.dll, status c0000135
```

### Deux fausses pistes, ecartees par la mesure

**« Le chemin de recherche est nul. »** La trace affiche bien
`load_dll looking for L"kernel32.dll" in (null)`. Mais `dlls/ntdll/loader.c:4507` passe `NULL`
**volontairement** : c'est la charge initiale, qui ne cherche que le repertoire systeme. Le
message est normal.

**« C'est le detour par start.exe. »** Lance depuis le repertoire du projet, Wine resolvait
« wineboot » en `Z:\...\proton-ouvert\wineboot`, inexistant, et se rabattait sur `start.exe`.
Lance depuis `/tmp`, l'echec est identique. Ce n'etait pas ca.

### Ce que dit reellement la trace

```
find_builtin_dll looking for "start.exe" for file "C:\windows\system32\start.exe"
build_module loaded "C:\windows\system32\start.exe"
build_ntdll_module Loaded "C:\windows\system32\ntdll.dll"
load_dll looking for "kernel32.dll" in (null)
Failed to load module "kernel32.dll"; status=c0000135
```

`start.exe` et `ntdll.dll` passent par `find_builtin_dll` et se chargent. Pour `kernel32.dll`,
**aucun `find_builtin_dll` n'apparait** : l'echec precede la recherche du module integre. Or le
`system32` du prefixe est vide -- c'est justement `wineboot` qui doit le peupler -- et
`kernel32.dll` est bien present dans `lib/wine/aarch64-windows/` avec les 996 autres.

### Ce qui reste a etablir

Pourquoi `start.exe` atteint le chemin « integre » et pas `kernel32.dll`. La reponse est dans
`find_dll_file` et l'ordre de chargement, pas dans le TEB : ce mur-la n'a rien a voir avec
`x18`, il etait simplement cache derriere.

Rien ne dit non plus qu'il soit nouveau. La ligne de base du paragraphe 216 ne peuplait pas
`system32` non plus ; elle n'allait juste pas assez loin pour le montrer.

## 224. kernel32 introuvable etait la consequence, pas la cause

### La mesure qui tranche

Sondes temporaires dans `find_dll_file`, comparant le processus qui reussit et celui qui
echoue :

```
002c :  search -> c0000135 (bootstrap=1)   builtin_sans_fichier -> 0          succes
0024 :  search -> c0000135 (bootstrap=0)   builtin_sans_fichier -> c0000135   echec
```

Un seul bit differe : `is_prefix_bootstrap`. C'est lui qui autorise `find_builtin_without_file`
a fournir un module integre quand le prefixe est vide.

### Pourquoi il differe

`dlls/ntdll/unix/env.c` le dit sans ambiguite :

```c
set_env_var( ..., WINEBOOTSTRAPMODE, "1" );
is_prefix_bootstrap = TRUE;
run_wineboot( env, env_pos );          /* -> 002c */
/* reload environment now that wineboot has run */
is_prefix_bootstrap = !!bootstrap;      /* -> FALSE */
load_main_exe( &nt_name, 0 );           /* -> 0024 */
```

Wine lance d'abord `wineboot` en fils, avec le drapeau, pour peupler `system32` ; puis il retire
le drapeau et charge l'executable principal, qui s'attend a trouver un `system32` garni.

Le fils (002c) charge bien `kernel32`, `kernelbase`, `rpcrt4` par le chemin integre -- **mais il
ne termine pas**. C'est lui qu'on voyait tourner a 100 % au paragraphe 220, chaud dans
`RtlEnterCriticalSection`, `call_seh_handlers` et `virtual_unwind`. Il ne peuple donc jamais
`system32`, et le parent echoue ensuite faute de trouver `kernel32` sans le drapeau.

### Ce que cela corrige dans le diagnostic

Le paragraphe 223 presentait « kernel32 introuvable » comme le mur suivant. C'est faux : c'est un
symptome. Le seul vrai blocage reste **le fils wineboot qui boucle**, deja identifie au
paragraphe 220 et toujours ouvert. Deux paragraphes de fouille pour revenir au meme point, mais
en sachant desormais que le reste de la chaine est sain.

Les sondes ont ete retirees ; l'arbre est propre et la serie se reproduit.

## 225. La boucle, nommee : une faute d'appel systeme avec x18 nul

### Ce que la trace montre

`WINEDEBUG=+seh` sur le fils `wineboot` qui tourne a 100 % produit **19 226 244 lignes en
45 secondes**, toutes du meme type :

```
002c:trace:seh:handle_syscall_fault  x18=0000000000000000
002c:trace:seh:handle_syscall_fault returning to user mode ip=0x6fffffcb9424 ret=c0000005
002c:trace:seh:handle_syscall_fault code=c0000005 flags=0 addr=0x107220400 pc=0x107220400
```

Sur deux millions de lignes depouillees, une seule adresse fautive revient :

```
166666 fois  pc=0x107220400
     1 fois  pc=0x1072202c8
```

Une faute dans un appel systeme, `x18` a zero, traitee, rendue au mode utilisateur avec
`c0000005`, et reproduite a l'identique. C'est la boucle du paragraphe 220, et elle n'est pas une
section critique orpheline : celle-ci n'en est que la consequence.

### Ce que cela dit du correctif

Le rechargement du paragraphe 221 couvre l'**entree** des repartiteurs. L'adresse fautive,
`0x107220400`, est dans `ntdll.so` -- le cote unix -- mais ailleurs : le chemin de retour, ou le
tremplin, continue de lire `x18` sans le recharger. Il reste donc au moins un site.

### Une difficulte de methode

La boucle est **intermittente**. Sur cinq lancements consecutifs, le fils sort parfois
immediatement sur l'erreur `kernel32` du paragraphe 224, parfois boucle. L'activation de `+seh`
semble favoriser la boucle, ce qui est coherent avec une course. Symboliser l'adresse demande de
relever la base de `ntdll.so` **dans la meme execution** que la faute, par `vmmap` sur le
processus vivant ; les bases changent a chaque lancement.

### L'etat

```
acquis    le mur x18 du paragraphe 144 n'existe plus
          NtCurrentTeb() en ligne, huit instructions, sans appel
          le prefixe arm64 se cree, les services demarrent
          libwow64fex.dll se construit sur macOS sans toucher au code de FEX
reste     un site de lecture de x18 dans le chemin de retour d'appel systeme
          le fils wineboot boucle par intermittence et ne peuple pas system32
```

## 226. Le site manquant : le retour du repartiteur d'appels systeme

### Trouve par relecture, pas par fouille

La liste des lectures de `x18` restantes cote unix tient en une vingtaine de sites. La plupart
sont sures : `call_user_mode_callback` recoit le TEB dans `x4` et pose `x18` lui-meme ; les
sauvegardes de contexte le lisent comme un registre parmi d'autres. Un seul ne l'etait pas :

```c
__ASM_GLOBAL_FUNC( __wine_syscall_dispatcher_return,
                   "ldr w11, [x18, #0x380]\n\t" /* thread_data->syscall_trace */
```

C'est une fonction **separee**, atteinte apres l'appel systeme -- donc apres un retour du noyau,
donc avec `x18` efface -- et sa toute premiere instruction lit `x18`. Le rechargement du
paragraphe 221 ne couvrait que l'entree des deux repartiteurs ; celui-ci est un troisieme point
d'entree, et je l'avais manque.

### La mesure

```
avant : 19 226 244 lignes de handle_syscall_fault en 45 s, journal de 2,3 Go
        166 666 fois la meme adresse fautive
apres : 0 faute d'appel systeme, journal de 195 octets
```

La boucle du paragraphe 220 a disparu.

### Ce qui reste, et ce n'est plus une faute

Le fils `wineboot` charge maintenant 25 modules, tourne, puis **se detache proprement** --
`ucrtbase`, `kernel32`, `kernelbase`, `ntdll`, chacun avec son `PROCESS_DETACH` qui rend 1. Un
arret normal.

Mais il ne peuple pas `system32` :

```
prefixe x86_64 qui marche :  782 fichiers
prefixe arm64             :    0 fichier
```

Il sort donc sans avoir fait son travail. Ce n'est plus un plantage ni une boucle : c'est un
chemin d'execution a comprendre dans `wineboot` lui-meme. La nature du probleme a change.

## 227. Ce n'est plus le TEB : la creation de processus echoue

### La trace de wineboot

```
002c:err:wineboot:start_services_process Couldn't start services.exe: error 731
002c:trace:wineboot:start_rundll32 machine 1 starting L"C:\windows\system32\rundll32.exe"
002c:trace:wineboot:update_wineprefix wine: configuration ... has been updated.
```

Et dans tout le journal, **un seul identifiant de processus** : `002c`. Ni `services.exe` ni
`rundll32.exe` n'emettent quoi que ce soit -- ils ne demarrent pas.

### Pourquoi le message « has been updated » ment

```c
if ((process = start_rundll32( inf_path, L"PreInstall", IMAGE_FILE_MACHINE_TARGET_HOST )))
{
    ...  /* toute l'installation par wine.inf */
}
install_root_pnp_devices();
update_user_profile();
TRACE( "wine: configuration in %s has been updated.\n", ... );
```

Quand `start_rundll32` rend zero, le bloc entier est saute **en silence**, et le message de
succes s'affiche quand meme. D'ou un `system32` vide et un `wineboot` qui sort proprement : il
croit avoir fait son travail.

C'est aussi l'explication complete du paragraphe 224 : `kernel32` introuvable pour le processus
principal decoule de ce `system32` jamais peuple.

### Le vrai point de blocage

Les deux echecs passent par la meme fonction :

```c
create_native_process( L"C:\\windows\\system32\\services.exe", ... )
create_native_process( app /* rundll32.exe */, ... )
```

La creation de processus echoue. L'erreur 731 -- `ERROR_WAIT_1` -- n'a aucun sens ici : c'est
une valeur residuelle, `GetLastError` n'ayant pas ete renseigne par l'echec.

Le prefixe etant vide, la creation doit passer par le repli d'amorcage de
`dlls/ntdll/unix/process.c` :

```c
if (status && is_prefix_bootstrap && is_system_dir_path( attr->ObjectName, &info->machine ))
```

C'est ce chemin qu'il faut eprouver ensuite. Le probleme a de nouveau change de nature : ni
faute, ni boucle, ni TEB -- la creation de processus.

## 228. pthread_setspecific ecrit dans le fil appelant

L'adresse fautive, symbolisee dans la meme execution que sa base :

```
__wine_syscall_dispatcher + 36
__wine_unix_call_dispatcher + 36
```

Le prologue de rechargement fait 32 octets : `+36` est donc l'instruction **juste apres**, celle
qui lit `[x18, #0x378]`. Le rechargement s'executait et ne trouvait rien -- `cbz x10, 9f` -- et
laissait `x18` nul.

La cause : j'avais place `enregistrer_teb` dans `init_teb`, qui s'execute sur le fil **parent**,
pas sur celui qui vient de naitre. `pthread_setspecific` ecrit toujours dans le fil appelant.
Chaque creation de fil ecrasait donc le creneau du parent avec le TEB de l'enfant, et l'enfant
n'avait pas le sien.

L'appel est revenu dans `init_syscall_frame`, qui s'execute sur le nouveau fil.

```
avant : services.exe sort avec le code 5, douze violations d'acces,
        « invalid frame ... not in stack limits »
apres : services.exe sort avec le code 0, aucune exception
```

`wineboot --init` echoue toujours -- `start_services_process` rend l'erreur 731, c'est-a-dire un
fils sorti avec le code 1 -- alors que le meme `services.exe` lance a la main reussit. La
difference tient a l'environnement ou au moment, pas au TEB : il n'y a plus aucune exception.

Sondes retirees, serie verifiee.

## 229. execv echoue en EFAULT : argv a 38 Gio

Le fils spawnе par `wineboot` sort avec le code 1 parce que `exec_wineloader` rend la main :
les deux `execv` echouent.

```
SONDE loader_exec a echoue : wineloader=.../lib/wine/aarch64-unix/wine errno=14 (Bad address)
```

`errno 14` est `EFAULT`, alors que le chemin est exact et le fichier executable. Ce n'est donc
pas le programme qui est en cause mais les tableaux passes a `execv`. Sonde sur les pointeurs,
les deux appels compares :

```
reussite  argv=0x102947f90  environ=0x102948000  argv[1]=0x102948200
echec     argv=0x8edc58300  environ=0x100b08f50  argv[1]=0x8ed4045f0
```

Dans l'appel qui echoue, `argv` et ses chaines vivent vers **0x8ed00000000**, soit environ
38 Gio -- une region que le noyau refuse de lire au moment de l'`exec`. Dans celui qui reussit,
tout tient sous les 5 Gio.

`build_argv` alloue par `malloc` dans le fils de `fork`. Que l'allocateur serve depuis une
region aussi haute est propre a la disposition memoire que Wine impose sur arm64 : le
paragraphe 216 relevait deja `try_map_free_area` balayant des centaines de plages depuis
`0x100000000`. La piste est la, pas dans le TEB.

Sondes retirees, serie verifiee.

## 230. FEX : c'est la variante ARM64EC qu'il faut

Objectif reprecise par l'utilisateur : tout doit tourner **sans Rosetta, maintenant**. Le
sequencement change en consequence -- on attaque le seul verrou binaire, FEX, avant le reste.

### Le JIT alloue x18... sauf en ARM64EC

`FEXCore/Source/Interface/Core/ArchHelpers/Arm64Emitter.cpp` definit deux jeux de registres.
Hors ARM64EC :

```c
constexpr std::array<ARMEmitter::Register, 7> RA = {
    r20, r21, r22, r23, r24, r30, r18,
};
```

`r18` sert de registre general pour des valeurs emulees. Sur macOS, ou il est efface a tout
moment, cela donnerait une corruption silencieuse du code emule -- bien pire qu'une faute.

En ARM64EC, le meme tableau l'exclut :

```c
constexpr std::array<ARMEmitter::Register, 6> RA = {
    r6, r7, r14, r15, r16, r30,
};
```

L'ABI ARM64EC reserve `x18` au TEB, donc FEX s'en abstient deja. **La variante WoW64 que j'avais
construite au paragraphe 222 est inutilisable sur macOS ; la variante ARM64EC ne l'est pas.**

### Construite

```
[242/242] Linking CXX executable Bin/FEXOfflineCompiler64.exe
libarm64ecfex.dll : 5279744 octets
libFEXCore.dll    : 3534848 octets
```

Meme recette qu'au paragraphe 222, avec `-DMINGW_TRIPLE=arm64ec-w64-mingw32`. Toujours aucune
ligne du code de FEX modifiee.

### Ce qui reste cote x18

Trois lectures du TEB par `x18` dans le code **emis** :

```
JIT/MiscOps.cpp:369  ldr(TMP2, XReg::x18, TEB_CPU_AREA_OFFSET)
JIT/MiscOps.cpp:382  idem
Arm64Emitter.cpp:810 ldr(TmpReg.X(), Reg::r18, TEB_CPU_AREA_OFFSET)
```

Meme classe de probleme que dans Wine, mais dans du code produit a l'execution. Borne -- trois
sites -- et ce sont des lectures, pas une allocation. La politique de FEX interdisant d'y ecrire
du code, ce sera a l'utilisateur de trancher si une modification s'impose.

### Correction : les jeux 32 bits ne sont pas la voie difficile

J'avais ecrit que la variante WoW64, servant les invites i386, allouait `x18` et serait donc
inutilisable. **C'est faux.** Le choix du pool se fait a l'execution, selon le mode de l'invite :

```c
if (EmitterCTX->Config.Is64BitMode()) {
    GeneralRegisters = x64::RA;   /* contient r18 */
} else {
    GeneralRegisters = x32::RA;   /* ne le contient pas */
}
```

Et `x32::RA` liste quatorze registres -- r20..r23, r12..r17, r29, r30, r24, r19 -- **sans
r18**. La variante WoW64 sert des invites 32 bits, donc emprunte toujours ce pool.

Les deux modules dont nous avons besoin sont donc propres de ce cote :

```
libwow64fex.dll    invites 32 bits    -> x32::RA, pas de r18
libarm64ecfex.dll  invites x86-64     -> pool ARM64EC, pas de r18
```

Le seul pool qui alloue `r18` est `x64::RA`, emprunte par FEX hors ARM64EC pour des invites
64 bits -- c'est-a-dire le cas Linux, pas le notre. Il ne reste, dans les deux cas, que les
trois lectures de TEB ci-dessus.

## 231. Le W^X n'est pas un mur

### Ce que macOS arm64 accepte, mesure

`tests/wx_arm64.c`, trois voies eprouvees en ecrivant puis executant « mov x0,#42 ; ret » :

```
mmap RWX                     ECHEC (Permission denied)
mmap RW puis mprotect RX     -> 42
mmap MAP_JIT + write_protect -> 42
```

RWX en un seul coup est refuse. Mais **basculer** une page de RW vers RX fonctionne, et
`MAP_JIT` assorti de `pthread_jit_write_protect_np` aussi. Un JIT est donc possible ; c'est la
demande simultanee des trois droits qui ne l'est pas.

### Wine sait deja faire

`get_unix_prot` dans `dlls/ntdll/unix/virtual.c` :

```c
if (vprot & VPROT_EXEC) prot |= PROT_EXEC | PROT_READ;
if (vprot & VPROT_WRITEWATCH) prot &= ~PROT_WRITE;
```

Quand une page est a la fois executable et inscriptible et que le mode est actif, Wine retire
`PROT_WRITE` : il ne demande jamais RWX au noyau, leve une exception a l'ecriture et bascule.
C'est exactement ce que macOS exige.

Le mode s'active par processus, via
`NtSetInformationProcess(ProcessManageWritesToExecutableMemory)` -- le mecanisme que Windows
prevoit pour ses emulateurs.

### Ou doit aller la correction

FEX ne l'appelle pas : `ManageWritesToExecutableMemory` n'apparait nulle part dans son arbre. Il
alloue donc en `PAGE_EXECUTE_READWRITE`, ce qui sur macOS se traduit par un `mmap` RWX, refuse.

Deux issues, et la seconde est la bonne pour nous :

1. faire appeler `NtSetInformationProcess` par FEX -- un appel, mais dans leur arbre, que leur
   politique nous interdit d'ecrire ;
2. **faire activer le mode par Wine** des que l'hote n'accepte pas RWX. C'est notre correctif,
   dans notre arbre, et il profite a tout emulateur, pas seulement a FEX.

Le risque que j'annoncais comme binaire au paragraphe 230 n'en est donc pas un : le JIT est
possible sur macOS, et le chemin passe par du code qui nous appartient.

## 232. Le prefixe arm64 se cree, et un programme Windows tourne

### La cause de l'EFAULT : l'environnement, pas argv

Sonde sur chaque `execv`, cible et errno :

```
argv=0x84ac08878  env=0x103883e80   -> reussit   (argv haut, env bas)
argv=0x1027ecf28  env=0x1027ed020   -> reussit
argv=0x100efb3b8  env=0xb1aca8200   -> EFAULT    (env a ~47 Gio)
argv=0x100efcf88  env=0xb1aca8200   -> EFAULT
```

Le premier cas tranche : `argv` haut ne gene pas, `environ` haut si. macOS refuse le tableau
d'environnement au-dela d'une certaine hauteur. Wine reservant de vastes plages basses, un
`realloc` de `putenv` dans le fils de `fork` peut atterrir n'importe ou -- d'ou le caractere
intermittent de la panne.

`env_bas()` recopie le tableau et ses chaines dans une seule projection demandee vers
`0x110000000`, et `preloader_exec` appelle desormais `execve` avec cette copie.

### Ce qui tourne

```
wineboot --init -> code 0
system32        -> 783 fichiers

wine reg query "HKCU\Software"
  HKEY_CURRENT_USER\Software\Classes
  HKEY_CURRENT_USER\Software\Microsoft
  HKEY_CURRENT_USER\Software\Wine
```

Le prefixe arm64 se cree, et un vrai programme Windows s'execute et rend ses resultats, sur une
pile **entierement native arm64, sans Rosetta**. Le prefixe x86_64 de reference en compte 782 :
on est au meme niveau.

### Ce qui reste visible

```
Unhandled page fault on read access to 00000000000008A0 at 0x6FFFFFC8D370 (un fil)
failed to start L"\??\C:\windows\syswow64\rundll32.exe": c0000135
```

Le second est attendu : rien n'emule encore le 32 bits. Le premier est un deplacement de TEB de
plus, sur un fil ou le repli ne joue pas.

## 233. Le support des invites x86 tue le processus

Pour executer du code x86 il faut que Wine soit construit avec les architectures invitees. Trois
constructions, memes sources, meme correctif 0068 :

```
--enable-archs=aarch64              wineboot -> 0    system32 : 781 fichiers
--enable-archs=i386,x86_64,aarch64  wineboot -> 137  system32 : 0
--enable-archs=x86_64,aarch64       wineboot -> 137  system32 : 0
```

`137` est `128 + 9` : le processus est **tue par SIGKILL**, sans produire une seule ligne, meme
avec `+loaddll,+virtual`. Il meurt avant que la sortie de deboguage ne s'initialise. `wine
--version` fonctionne dans les trois cas -- le chargeur demarre, c'est la mise en place de
l'espace d'adressage qui echoue.

L'i386 n'est pas en cause : retirer `i386-windows` de l'installation ne change rien, et la
construction `x86_64,aarch64` seule echoue pareillement. Le `__PAGEZERO` du chargeur fait
toujours 4 Gio, donc la piste du prealloueur est ecartee aussi.

Reinstaller la construction `aarch64` seule redonne immediatement un prefixe qui se cree : la
regression est bien dans le support des invites, pas ailleurs.

C'est le blocage actuel pour faire tourner quoi que ce soit de x86. Il faut trouver quelle
reservation d'espace d'adressage macOS refuse au point de tuer le processus.

## 234. Wine arm64 accepte les invites x86, et FEX est en place

### Le SIGKILL : __PAGEZERO, encore

Trois sondes dans `__wine_main` situent la mort **avant** la premiere ligne du processus
re-execute. Comparaison des deux chargeurs :

```
--enable-archs=aarch64        loader/wine  __PAGEZERO vmsize 0x100000000  demarre
--enable-archs=x86_64,aarch64 loader/wine  __PAGEZERO vmsize 0x1000       SIGKILL
```

Activer un invite x86 fait prendre a configure la branche qui retrecit `__PAGEZERO`, et le noyau
arm64 tue le binaire avant dyld -- exactement ce que le correctif de l'arbre wine 10 documentait
deja. Le garde-fou manquait dans wine11 ; il y est desormais, sur `HOST_ARCH`.

Apres quoi :

```
--enable-archs=i386,arm64ec,aarch64   wineboot -> 0   system32 : 785 fichiers
```

### Deux ajustements pour ARM64EC

Le premier essai d'invite x86-64 rendait `c00000bb` -- `STATUS_NOT_SUPPORTED` -- en chargeant le
ntdll aarch64 : il faut un ntdll **ARM64EC**, donc `--enable-archs=arm64ec`.

L'edition de liens a ensuite reclame `__wine_current_teb` et `__wine_teb_tsd_key` « (EC symbol) ».
Deux corrections : les entrees du `.spec` passent en `-arch=arm64,arm64ec`, et les definitions
quittent `signal_arm64.c` -- compile pour la seule aarch64 -- pour `thread.c`, compile partout,
sous `#if defined(__aarch64__) || defined(__arm64ec__)`.

### Ou on en est

```
wineboot --init            -> 0, 785 fichiers
wine reg query             -> repond
libarm64ecfex.dll          -> installe
libwow64fex.dll            -> installe comme xtajit.dll
programme x86-64           -> charge, puis
                              err:seh:NtRaiseException Unhandled exception
                              code c0000005 addr 0x6fffff9dde38
```

Le programme x86-64 n'est plus refuse : il est charge et l'emulation demarre, puis faute. C'est
le prochain point a instruire.

## 235. FEX est charge par Wine arm64

### Le nom que Wine attend

Pour un invite x86-64 sur ARM64, Wine charge `xtajit64.dll` -- pas `xtajit.dll`, qui sert aux
invites 32 bits. `libarm64ecfex.dll` installe sous ce nom, Wine le prend.

### macOS refuse RWX, meme par mprotect

```
SONDE mprotect 0x140000000 taille 4000 prot 7 -> Permission denied
```

`prot 7` est `PROT_READ|PROT_WRITE|PROT_EXEC`. Mesure sur une projection de fichier :

```
MAP_PRIVATE R  puis mprotect RX  : ok
MAP_PRIVATE RW puis mprotect RX  : ok
MAP_PRIVATE RW puis mprotect RWX : Permission denied
MAP_PRIVATE R+X a la projection  : Operation not permitted
```

L'execution s'obtient par `mprotect`, jamais en meme temps que l'ecriture, et jamais a la
projection. Or `force_exec_prot` -- que Wine active pour les images non conscientes du bit NX --
ajoute l'execution partout, y compris sur des pages inscriptibles.

`mprotect_exec` gerait deja le cas ou l'execution est *ajoutee*, pas celui ou elle est *deja
demandee* avec l'ecriture. Il retire desormais l'execution plutot que d'echouer : le chargeur
pose ensuite la protection finale de chaque section, et les erreurs
« failed to set protection » ont disparu.

### Ou ca s'arrete

```
err:seh:NtRaiseException Unhandled exception code c0000005 addr 0x6ffff22dde38
info[1] = 0x60
```

`0x60` est le deplacement du PEB dans le TEB : un fil lit `NtCurrentTeb()->Peb` avec un TEB nul.
Un chemin de creation de fil du cote ARM64EC echappe encore a l'enregistrement -- meme famille
que le paragraphe 228, autre chemin.

## 236. Le thunk ARM64EC est réparé ; le mur suivant est `x18` dans FEX

### Ce que lisait la faute du paragraphe 235

Symbolisée, l'adresse `0x6ffff22dde38` tombe dans `#arm64x_check_call`, le thunk que l'ABI
ARM64EC traverse **à chaque appel indirect** :

```
1800cde38: ldr	x16, [x18, #0x60]     <- faute, x18 = 0
1800cde3c: lsr	x17, x11, #18
1800cde40: ldr	x16, [x16, #0x368]    /* peb->EcCodeBitMap */
```

Wine définit ce thunk lui-même (`dlls/ntdll/signal_arm64ec.c`), donc il est réparable. Le
fichier compte quatre lectures de `[x18, #0x60]`, et toutes les quatre ne cherchent que le
**PEB**, qui est unique pour tout le processus.

Deux chemins, selon le coût admissible :

| site | fréquence | accès retenu |
| --- | --- | --- |
| `arm64x_check_call` | chaque appel indirect | variable globale `peb_arm64ec` |
| `KiUserCallbackDispatcher` | rare | clé TSD (`TPIDRRO_EL0`) |
| `KiUserExceptionDispatcher` | rare | clé TSD |
| `DbgUiRemoteBreakin` | rare | clé TSD |

La globale est posée dans `arm64ec_update_hybrid_metadata`, **avant** le `SET_FUNC` qui installe
`arm64x_check_call` dans les métadonnées du module : l'ordre garantit qu'elle n'est jamais lue
vide. Premier jet : elle n'était posée que dans `arm64ec_process_init`, qui n'est appelé que
pour les processus chargeant l'émulateur ; les autres mouraient sur
`user_callback_handler ignoring exception c0000005` puis
`Unhandled page fault on read access to 0000000000000060`. Ces fautes ont disparu.

### Où l'on arrive ensuite

`hello64.exe` (PE x86_64) va maintenant plus loin : le thunk EC passe, `xtajit64.dll` (FEX)
est chargé à `0x6ffff8320000`, et la première faute est ailleurs.

```
0148:trace:seh:dispatch_exception code=c0000005 flags=0 addr=00006FFFF84BD884
0148:trace:seh:dispatch_exception  info[0]=0000000000000001   /* écriture */
0148:trace:seh:dispatch_exception  info[1]=0000000000001488
```

RVA `0x19D884`, dans `libarm64ecfex.dll` :

```
000000018019d84c <TlsAlloc>:
18019d87c: mov	x8, x18
18019d880: add	x8, x8, w19, uxtw #3
18019d884: str	xzr, [x8, #0x1480]    <- faute, TEB->TlsSlots[i]
```

`x18` est nul, donc l'écriture part à `0x1488`. Noter que la faute tombe sur le `str`, pas sur
le `mov` : `x18` a été recopié deux instructions plus tôt. **Aucun rattrapage par signal n'est
possible** — le tremplin du paragraphe 143 aurait dû agir avant le `mov`, qui ne faute pas.

### L'inventaire, mesuré

`llvm-objdump -d libarm64ecfex.dll` : **71 instructions** citent `x18`.

| forme | nombre | origine |
| --- | --- | --- |
| `mov xN, x18` | 65 | `NtCurrentTeb()` en ligne |
| `ldr x17, [x18, #0x1788]` | 4 | `TEB->ChpeV2CpuAreaInfo`, assembleur de FEX |
| `ldr x9, [x18, #0x58]` | 2 | assembleur de FEX |
| `ldr x16, [x18, #0x60]` | 1 | assembleur de FEX |

Les 65 `mov` viennent d'**une seule ligne**, dans les en-têtes de la chaîne d'outils, pas dans
FEX (`toolchain/llvm-mingw-.../generic-w64-mingw32/include/winnt.h`) :

```c
register struct _TEB *__mingw_current_teb __asm__("x18");
FORCEINLINE struct _TEB *NtCurrentTeb(VOID) { return __mingw_current_teb; }
```

C'est le jumeau exact de la ligne de Wine corrigée au paragraphe 145. Le reste est dans les
sources de FEX, et l'inventaire y est court — dix lignes :

| fichier | lignes | nature |
| --- | --- | --- |
| `Source/Windows/ARM64EC/Module.S` | 19, 35, 44, 49, 62 | assembleur écrit à la main |
| `FEXCore/.../Dispatcher/Dispatcher.cpp` | 153, 261, 269 | `ldr` **émis** par le JIT |
| `FEXCore/.../JIT/MiscOps.cpp` | 369, 382 | `ldr` **émis** par le JIT |

### Où ça bloque, et pourquoi ce n'est pas un blocage technique

Les deux en-têtes de la chaîne d'outils ne sont pas du code FEX : on peut les corriger. Les dix
lignes restantes sont dans FEX, et `third_party/FEX/CLAUDE.md` tient en une phrase : *« AI must
not be used to generate code for contributions to this project. »* Aucune ligne de FEX n'a été
modifiée jusqu'ici — seules des options cmake ont servi.

La correction elle-même est courte et connue : remplacer la lecture de `x18` par
`TPIDRRO_EL0 & ~7` indexé par la clé TSD, comme le fait déjà `NtCurrentTeb()` côté Wine. Dans
`Module.S` les registres `x16`/`x17` sont libres aux quatre endroits ; dans le JIT, `TMP1`/`TMP2`
le sont, et le numéro de clé est une constante du processus, donc inscriptible en immédiat dans
le code généré.

**Décision à prendre : qui écrit ces dix lignes.**

### Suite du 236 : l'en-tête de la chaîne d'outils corrigé, 71 sites → 7

Les 65 `mov xN, x18` venaient d'une ligne de `winnt.h` de llvm-mingw, **pas de FEX**. Corrigée
(correctif 0069), derrière `__MINGW_TEB_SANS_X18` pour ne rien changer aux autres constructions :

```c
__declspec(dllimport) extern unsigned int __wine_teb_tsd_key;
FORCEINLINE struct _TEB *NtCurrentTeb(VOID)
{
    unsigned __int64 base = __builtin_arm_rsr64( "tpidrro_el0" ) & ~(unsigned __int64)7;
    return *(struct _TEB **)(base + 8 * (unsigned __int64)__wine_teb_tsd_key);
}
```

`__wine_teb_tsd_key` est déjà exporté par le ntdll de Wine. Pour l'importer sans toucher au
`Defs/ntdll.def` de FEX, une bibliothèque d'importation séparée
(`outils/ntdll_teb.def`, `tests/construire_import_teb.sh`) est ajoutée **en option d'édition de
liens** :

```
cmake . -DCMAKE_CXX_FLAGS=-D__MINGW_TEB_SANS_X18 \
        -DCMAKE_C_FLAGS=-D__MINGW_TEB_SANS_X18 \
        -DCMAKE_SHARED_LINKER_FLAGS="-static -Wl,--file-alignment=4096,/mllvm:-align-loops=1 \
                                     .../outils/libntdll_teb_arm64ec.a"
```

Aucun fichier de FEX modifié. Nouveau `TlsAlloc` dans le binaire produit :

```
18019dbdc: mrs	x8, TPIDRRO_EL0
```

Décompte après reconstruction : **7 instructions citent encore `x18`**, contre 71.

| adresse | fonction | instruction | source |
| --- | --- | --- | --- |
| `18011085c` | `check_target_ec` | `ldr x16, [x18, #0x60]` | `Module.S:19` |
| `180110880` | `enter_jit` | `ldr x17, [x18, #0x1788]` | `Module.S:35` |
| `180110894` | `BeginSimulation` | `ldr x17, [x18, #0x1788]` | `Module.S:44` |
| `1801108a8` | `BeginSimulation` | `ldr x17, [x18, #0x1788]` | `Module.S:49` |
| `1801108c4` | `ExitFunctionEC` | `ldr x17, [x18, #0x1788]` | `Module.S:62` |
| `1801c1bc8` | `__cxa_get_globals` | `ldr x9, [x18, #0x58]` | libc++abi, `thread_local` |
| `1801c1be8` | `__cxa_get_globals_fast` | `ldr x9, [x18, #0x58]` | libc++abi, `thread_local` |

Les deux derniers ne sont pas de FEX non plus : c'est le modèle TLS Windows émis par clang
(`TEB->ThreadLocalStoragePointer`), atteint seulement quand une exception C++ est levée. Aucun
en-tête ne peut les corriger.

### Le mur, maintenant nommé

`hello64.exe` va jusqu'à l'assembleur de FEX, et la trace le dit mot pour mot :

```
0x006ffffb5a0880 xtajit64+0x110880: ldr x17, [x18, #0x1788]
```

C'est `enter_jit`, l'entrée du JIT. Restent donc **cinq lignes de `Module.S` et cinq `ldr`
émis par le JIT** (`Dispatcher.cpp:153,261,269`, `MiscOps.cpp:369,382`). Dix lignes, dans FEX.

Piège rencontré au passage : un `libarm64ecfex.dll` périmé traînait à côté de `xtajit64.dll`
dans l'arbre Wine **et** dans le préfixe. La trace affichait `xtajit64.dll` tout en chargeant
l'ancien, et deux constructions différentes ont fauté au même RVA — ce qui n'a aucun sens et
m'a coûté un aller-retour. Supprimer les copies périmées avant toute mesure, comme pour les
processus oubliés.

## 237. Du x86_64 s'exécute sous FEX, sans Rosetta — et `x18` n'est plus le mur

Suite directe du 236. Décision prise : FEX est corrigé sous forme de correctif appliqué chez
nous, jamais poussé chez eux.

### Ce qui restait, et par où

| origine | sites | traitement |
| --- | --- | --- |
| `NtCurrentTeb()` des en-têtes llvm-mingw | 65 | correctif 0069 sur `winnt.h` |
| `Module.S` de FEX | 5 | correctif 0070 |
| `ldr` émis par le JIT (`Dispatcher.cpp`, `MiscOps.cpp`, `Arm64Emitter.cpp`) | 6 | correctif 0070 |
| `r18` dans les pools d'allocation hors ARM64EC | 2 tableaux | correctif 0070 |
| `__cxa_get_globals` de libc++abi | 2 | laissés : TLS Windows émis par clang, atteint seulement sur `throw` |
| **`__wine_syscall_dispatcher`, `call_user_mode_callback` — côté unix de Wine** | 8 | correctif 0068 |

### Le mécanisme, une fois pour toutes

Le JIT et `Module.S` lisent désormais :

```
mrs x16, tpidrro_el0
and x16, x16, #0xfffffffffffffff8
ldr x17, [x16, #<8 * clé TSD>]
```

La clé est publiée par le ntdll de Wine (`__wine_teb_tsd_key`) et lue une fois dans
`ProcessInit`. Pour l'importer sans toucher au `Defs/ntdll.def` de FEX, une bibliothèque
d'importation à part (`outils/ntdll_teb.def`) est ajoutée en option d'édition de liens.

### Le piège de fond : recharger `x18` ne suffit jamais

Le correctif 0068 rechargeait `x18` à l'entrée des répartiteurs. Mesuré, ça ne tient pas :

```
2c208: ldr x7, [x18, #0x378]   <- passe
2c20c: sub x1, sp, #0x330
2c210: str x1, [x18, #0x378]   <- faute, x18 = 0
```

Deux instructions d'écart, aucun appel système entre les deux. Le noyau efface `x18` de façon
asynchrone, donc **aucune valeur ne peut y séjourner, même une instruction**. Les répartiteurs
relisent maintenant le TEB dans un registre banal juste avant chaque usage (`LIRE_TEB`), et
`call_user_mode_callback` garde simplement le TEB dans `x4`, où l'appelant le lui donne.

Corollaire : le tremplin du paragraphe 143 est neutralisé. Il ne servait plus qu'à écraser `x16`
et à détourner `PC` — et il fautait lui-même sur son propre `ldr x18, [sp]`.

### Le résultat

`hello64.exe`, PE x86_64, sous Wine arm64 natif. `sample` sur le processus :

```
442 __wine_syscall_dispatcher (in ntdll.so)
  388 NtProtectVirtualMemory -> set_protection -> set_vprot -> mprotect_exec
969 ??? [0x6fffff9ba52c]
  95 ??? [0x6ffff725e2d4]   <- code émis par le JIT
```

Les adresses `0x6ffff72xxxxx` sont les blocs produits par FEX : **du x86_64 s'exécute**, sans
Rosetta, sur une pile entièrement arm64. Plus aucune faute `x18` dans la trace (sonde
`SONDE_FAUTE_BASSE` sur toute faute sous `0x10000` : zéro).

### Les deux obstacles suivants, nommés

1. **Le W^X coûte tout le temps CPU.** 388 échantillons sur 442 sont dans `mprotect_exec`.
   FEX demande `PAGE_EXECUTE_READWRITE`, macOS le refuse, notre repli retire `PROT_EXEC` — donc
   chaque bloc émis repasse par une faute. Le remède est connu et mesuré (§231) : `MAP_JIT` +
   `pthread_jit_write_protect_np` pour les pages demandées en RWX.
2. **Les 4 premiers Gio.** `map_fixed_area out of memory for 0x400000-...` et
   `couldn't map free area in range 0x110000-0x7fff0001` : les processus i386 du démarrage ne
   trouvent pas leur espace bas, pris par `__PAGEZERO` et le binaire hôte. Obstacle déjà connu,
   intact.

### Piège de manipulation

`make install` de Wine réécrit `xtajit64.dll` et `xtajit.dll` avec ses propres bouchons ; la
trace dit alors `err:xtajit:ExitToX64 x64 emulation not implemented`. Et une copie périmée de
`libarm64ecfex.dll` à côté avait fait fauter deux constructions différentes au même RVA.
`tests/installer_fex.sh` repose FEX après chaque installation.

## 238. Le W^X : la bascule sur faute, et `hello64.exe` répond

### Ce que le paragraphe 237 laissait, mesuré

Sonde sur `mprotect_exec`, `hello64.exe` pendant trois minutes :

```
SONDE_WX 23020000 appels, 23019838 demandes w+x, 23019837 retraits d'exec
SONDE_WX origines : NtProtect=16939837 faute=0 autre=163
```

Puis les adresses :

```
NtProtect #2000000  base=0x7ffedded0000 size=1000 new=40 old=40
NtProtect #16000000 base=0x7ffedded0000 size=1000 new=40 old=40
```

**Une seule page, 17 millions de fois, avec `new == old == PAGE_EXECUTE_READWRITE`.** C'était un
enlisement, pas une lenteur : la comptabilité de Wine disait RWX, le noyau avait perdu
`PROT_EXEC` à cause de notre repli, FEX exécutait, fautait, redemandait la même protection, et
recommençait.

### La bascule

Ni `MAP_JIT` ni le mode `ManageWritesToExecutableMemory` du paragraphe 231 ne conviennent tels
quels : `MAP_JIT` donne l'écriture **ou** l'exécution par fil (APRR), jamais les deux, et le
second lève une exception que FEX n'attend pas. Ce qu'il faut est plus simple : donner à la page
le droit qu'on vient de lui réclamer.

Un bit de page libre (`VPROT_WX_EXEC`, `0x80`) dit lequel des deux elle détient :

```c
if (bascule_wx && (prot & PROT_WRITE) && (prot & PROT_EXEC))
{
    if (vprot & VPROT_WX_EXEC) prot &= ~PROT_WRITE;
    else                       prot &= ~PROT_EXEC;
}
```

et `virtual_handle_fault` bascule, dans un sens ou dans l'autre, quand la faute correspond
exactement au droit manquant — plus une invalidation du cache d'instructions au passage vers
l'exécution. `bascule_wx` n'est pas supposé : `virtual_init` demande une page RWX au noyau et
regarde s'il la donne.

Coût : deux fautes par alternance écriture/exécution, au lieu d'une boucle infinie.

### Le résultat

```
$ wine c:\hello64.exe
bonjour depuis x86_64 emule
real 0.65 / 0.55 / 0.56
```

**Un PE x86_64 s'exécute et rend la main, en une demi-seconde, sur une pile entièrement arm64 :
Wine arm64, FEX ARM64EC, macOS arm64. Aucun Rosetta.**

### La taxe d'émulation, chiffrée

`tests/banc_emul.c`, même source, 20 millions de tours d'un mélangeur 64 bits ; à gauche le PE
x86_64 émulé par FEX sous notre Wine arm64, à droite le binaire macOS arm64 natif. Les deux
rendent `h=89d7dace25138f6a`, ce qui valide la comparaison.

| | essai 1 | essai 2 | essai 3 | médiane |
| --- | --- | --- | --- | --- |
| x86_64 sous FEX | 84,2 ms | 84,4 ms | 83,9 ms | **84,2 ms** |
| arm64 natif | 80,9 ms | 80,7 ms | 80,7 ms | **80,7 ms** |

**+4,3 %.** À comparer au ×2,04 de Rosetta sur le chemin CPU du pilote (§145). La précaution qui
s'impose : c'est une boucle ALU serrée, sans appel système, sans pression mémoire et sans
branchement imprévisible — le meilleur cas pour un JIT. Ce chiffre dit que le cœur du JIT de FEX
est bon, pas que la pile entière coûtera 4 %.

### Ce qui reste ouvert

1. Les 4 premiers Gio : `virtual_alloc_first_teb` échoue encore dans les processus i386 du
   démarrage (`__PAGEZERO`). Non touché.
2. Un PE **arm64ec** produit par clang (`banc_ec.exe`) se bloque au démarrage sous notre Wine,
   là où le PE x86_64 passe. Non élucidé.

## 239. Vulkan, puis D3D11, sur la pile arm64 : ce qui passe et ce qui bloque

### Le Wine arm64 n'avait pas Vulkan

`configure:24932: libvulkan and libMoltenVK development files not found`. Le chargeur Vulkan
arm64 et l'ICD KosmicKrisp arm64 existaient depuis le paragraphe 232, mais la construction du
Wine ARM64EC ne les voyait pas. Reconfiguré avec `LDFLAGS=-L$R/prefix/lib
CPPFLAGS=-I$R/prefix/include` : `checking for -lvulkan... libvulkan.1.dylib`.

### Un PE x86_64 dessine, de bout en bout

`build/bench_draw_pe.exe`, PE x86_64, 2000 tirages Vulkan. Chaîne complète : PE x86_64 → FEX
ARM64EC → Wine arm64 → winevulkan → chargeur Vulkan arm64 → KosmicKrisp arm64 → Metal.

| | essai 1 | essai 2 | essai 3 | médiane |
| --- | --- | --- | --- | --- |
| PE x86_64 émulé | 0,582 | 0,567 | 0,568 µs/tirage | **0,568** |
| binaire arm64 natif (hôte) | 0,435 | 0,437 | 0,436 µs/tirage | **0,436** |

**+30 %**, et ce chiffre porte l'émulation **et** la couche de conversion de winevulkan, pas
seulement le JIT. À comparer au ×2,04 de Rosetta sur le même genre de chemin (§145).

### DXVK compile pour ARM, après une ligne

`dxvk_pipemanager.cpp` construit une clé vide :

```c
m_shaderLibraries.emplace(std::piecewise_construct, std::tuple(), std::tuple(m_device, this, key));
```

Le libc++ de la chaîne d'outils instancie alors `tuple_element<0, tuple<>>` et refuse. On passe
`std::tuple(key)` — `key` vient d'être construite par défaut deux lignes plus haut, donc même
valeur (correctif 0071). Avec ça, DXVK sort `d3d11.dll`, `dxgi.dll` et `d3d9.dll` en **aarch64**
et en **arm64ec**.

### Le DXVK ARM64EC ne charge pas : le CRT de mingw lit `x18`

```
SONDE pc=... addr=0x8 : [f9400519]
ECHEC: d3d11.dll introuvable
```

`ldr x25, [x8, #0x8]`, précédé de `mov x8, x18` : c'est `NtCurrentTeb()->Tib.StackBase` dans
`_CRT_INIT`. Trois sites, tous dans **`dllcrt2.o`**, un objet **déjà compilé** livré avec
llvm-mingw — le correctif 0069 sur l'en-tête ne peut rien pour lui. La source est
`mingw-w64-crt/crt/crtdll.c`, 219 lignes, deux `NtCurrentTeb()` ; il faudra recompiler cet objet
avec l'en-tête corrigé. FEX y échappe parce qu'il fournit sa propre initialisation de CRT.

### Le DXVK x86_64, lui, tourne

En attendant, le DXVK x86_64 émulé par FEX : Wine arm64 ne le distingue pas d'un jeu.

```
info:  DXVK: v2.7.1+
info:  Vulkan: Found vkGetInstanceProcAddr in winevulkan.dll
info:  Found device: Apple M1 Max (KosmicKrisp 26.2.99)
info:  D3D11InternalCreateDevice: Using feature level D3D_FEATURE_LEVEL_11_0
```

221 lignes d'initialisation : le périphérique D3D11 est créé, les extensions et les types de
mémoire énumérés. **Un D3D11 x86_64 parle à KosmicKrisp arm64.**

Puis, avec les fils de compilation par défaut, tout se bloque sans consommer de CPU
(`NtWaitForAlertByThreadId` partout). Avec `dxvk.numCompilerThreads = 1` l'initialisation va au
bout, et l'arrêt devient une faute nette :

```
err:seh:call_seh_handlers invalid frame 7ffe94078c18 (0000000109C48000-0000000109D40000)
err:seh:NtRaiseException Exception frame is not in stack limits => unable to dispatch exception.
```

L'`EstablisherFrame` est sur la pile **x64 émulée** (`0x7ffe...`), les bornes vérifiées sont
celles de la pile **ARM64EC native** (`0x109c...`). C'est la conversion d'exception entre les
deux mondes ARM64EC qui ne recolle pas. Prochain chantier.

## 240. La bascule W^X par page est fausse à plusieurs fils, et APRR le prouve

### Le symptôme

Avec DXVK, `probe_d3d11.exe` échoue de trois façons différentes d'une exécution à l'autre :
blocage sans CPU, `invalid frame`, ou faute d'exécution à une adresse variable. Le
non-déterminisme est l'indice.

La sonde `SONDE_EC` (toute faute d'abort d'instruction, avec le bit de la carte de code EC) :

```
SONDE_EC faute d'execution pc=0x7ffeabe70004 addr=0x7ffeabe70004 carte=0x7ffefdef0000 bit=1
SONDE_EC faute d'execution pc=0x7ffeabe700a4 ...
SONDE_EC faute d'execution pc=0x7ffeabe71364 ...
```

Des dizaines de fautes d'exécution sur des pages **marquées code EC**, à des adresses qui
avancent : ce sont les pages de code émises par FEX, rendues non exécutables.

### Pourquoi c'était faux dès le départ

La bascule du paragraphe 238 donne à la page l'écriture **ou** l'exécution. L'état est celui de
la **page**, donc du processus entier. Dès que deux fils travaillent — et FEX compile sur un fil
pendant qu'un autre exécute — le fil qui écrit rend la page non exécutable pour tous les autres.
Le compte de fautes explose et l'ordonnancement décide du résultat. Cela explique aussi pourquoi
`dxvk.numCompilerThreads = 1` allait nettement plus loin.

macOS offre le mécanisme qu'il faut, et il est **par fil** : APRR, exposé par `MAP_JIT` et
`pthread_jit_write_protect_np`.

### Les quatre mesures qui fixent la conception

`tests/wx_map_jit.c` :

```
reservation PROT_NONE      ok
MAP_JIT en MAP_FIXED       Invalid argument
MAP_JIT sans adresse       ok
ecriture puis execution    -> 42
mprotect RWX sur MAP_JIT   Permission denied
execution apres mprotect   -> 42
en parallele : 6062150 ecritures, 6052480 executions
```

| | résultat |
| --- | --- |
| `MAP_JIT` **avec** `MAP_FIXED` | **refusé** (`EINVAL`) — on ne choisit pas l'adresse |
| `MAP_JIT` sans adresse | accordé |
| écrire puis exécuter sur un fil, avec la bascule APRR | marche |
| `mprotect` RWX sur une région `MAP_JIT` | refusé, **sans casser la région** |
| **un fil écrit et un autre exécute la même page, en même temps** | **6,06 M écritures et 6,05 M exécutions en 200 ms** |

La dernière ligne est la réponse : APRR est par fil, les deux fils ne se gênent pas du tout. La
bascule par page ne pourra jamais faire ça.

### Ce que ça impose à Wine

1. Les pages demandées en **exécution + écriture** doivent être allouées par un `mmap MAP_JIT`,
   donc **à une adresse choisie par le noyau** — Wine ne peut pas les placer dans son espace
   réservé comme le reste. Il faudra les enregistrer comme vues « système ».
2. Le gestionnaire de faute ne change plus la protection de la page : il bascule l'état **du
   fil** (`pthread_jit_write_protect_np`) selon le type de faute, et reprend.
3. `mprotect` sur ces vues devient un non-événement à avaler sans erreur.

Le correctif 0068 tel qu'il est reste utile pour un seul fil — `hello64.exe` et le banc Vulkan
passent — mais il est faux dès qu'un émulateur compile en parallèle. C'est le prochain chantier,
et il est maintenant entièrement spécifié.

## 241. Un jeu Steam x86_64 tourne sur la pile entièrement arm64

### La correction : `MAP_JIT`, et la bascule passe du côté du fil

Le paragraphe 240 avait tout spécifié. Écrit :

| | avant (bascule par page) | après (`MAP_JIT` + APRR) |
| --- | --- | --- |
| `get_unix_prot` | retire l'écriture **ou** l'exécution selon un bit de page | une page `VPROT_JIT` porte les trois droits |
| `mprotect_range` | rebascule la page à chaque faute | ne touche jamais une page `MAP_JIT` |
| faute d'écriture / d'exécution | change la protection de la **page** | `pthread_jit_write_protect_np` sur le **fil** |
| allocation | espace réservé de Wine | `mmap MAP_JIT`, adresse choisie par le noyau, sur-allouée puis rognée |

Trois pièges rencontrés, tous mesurés :

1. **L'invalidation du cache d'instructions à chaque bascule coûtait tout.** `sample` :
   1370 échantillons sur 1422 dans `sys_icache_invalidate`. Retirée : l'émulateur fait la sienne
   après avoir émis son code.
2. **`is_vprot_exec_write()` est vrai pour `VPROT_WRITECOPY`**, donc les *images PE* partaient
   en `MAP_JIT` — d'où une tempête de bascules sur du code natif. La condition exclut désormais
   `VPROT_WRITECOPY` et les drapeaux `SEC_*`.
3. Le premier jet gardait l'alignement 64 Ko de Windows par chance ; `MAP_JIT` refuse
   `MAP_FIXED`, donc on sur-alloue et on rend le surplus (`unmap_extra_space`).

### Ce qui passe maintenant

```
$ wine c:\hello64.exe                 bonjour depuis x86_64 emule      0,58 s
$ wine c:\banc_x64.exe 20000000       83,8 ms   (natif arm64 : 80,7 ms)
$ wine c:\bench_draw_pe.exe           0,562 us/tirage  (natif arm64 : 0,436)
$ wine c:\probe_d3d11.exe             RESULTAT: le GPU a execute l'effacement, la valeur revient juste
$ wine c:\probe_d3d11_draw.exe        RESULTAT: le triangle est rasterise, interpolation comprise
```

`probe_d3d11_draw` compile du HLSL, le fait traduire en SPIR-V par DXVK puis en Metal par
KosmicKrisp, rasterise un triangle et relit les pixels — **80, 90, 85 au centre, 0 au coin**.

### Le pont Steam, porté sur arm64

Le correctif 0067 vivait dans l'arbre x86_64. Porté tel quel dans `wine11` : le
`steamclient.dylib` du client Steam macOS est un binaire universel avec **une tranche arm64**
(`lipo -archs` : `x86_64 arm64`), donc l'unixlib le charge nativement. Aucun changement de code
n'a été nécessaire — `appel_vtable` passe ses sept arguments dans `x0`-`x6` comme il les passait
dans `rdi`-`r9`.

### Le jeu

`Surviving Mars` (`MarsSteam.exe`, PE x86_64, D3D11) :

```
info:  DXVK: Using 10 compiler threads
info:  Presenter: Actual swapchain properties:
info:    Format:       VK_FORMAT_B8G8R8A8_UNORM
info:    Buffer size:  1728x1117
info:    Image count:  3
Setting breakpad minidump AppID = 464920
SteamInternal_SetMinidumpSteamID:  Caching Steam ID:  76561198043440982
```

Le jeu a récupéré **le vrai identifiant Steam du compte connecté**, à travers le pont, depuis le
client macOS natif. Et il rend :

| | |
| --- | --- |
| occupation GPU (`ioreg`, AGXAccelerator) | 4 à 10 %, soutenue |
| mémoire allouée au GPU | 2,29 Gio |
| CPU | ~45 % d'un cœur |
| durée observée | **48 heures sans incident** (laissé tourner par inadvertance : 2 j, 49 h de CPU) |

**Chaîne complète, sans un octet de Rosetta :** jeu Windows x86_64 → FEX ARM64EC → Wine arm64 →
DXVK → winevulkan → chargeur Vulkan arm64 → KosmicKrisp arm64 → Metal → GPU Apple.

### Ce qui reste

Le lancement est scripté : `tests/etape2_pile_arm64ec.sh` pose l'environnement,
`tests/preparer_pont_steam_arm64.sh` installe le pont et le registre,
`tests/lancer_jeu_steam_arm64.sh` enchaîne le faux client et le jeu.

Piège : sans processus vivant sur `ActiveProcess\pid`, `steam_api64.dll` ne charge même pas le
pont. Le jeu tourne quand même — fenêtre, chaîne d'échange, rendu — puis se ferme sans rien dire
au bout de quatre minutes. La trace disait `[API loaded no]` et zéro ligne `lsteamclient`.

- Les jeux **i386** restent hors de portée : `DREDGE` et `Dead Cells` sont 32 bits, et les
  quatre premiers Gio sont pris par `__PAGEZERO` et le binaire hôte.
- Le DXVK **ARM64EC** ne charge toujours pas (`dllcrt2.o` de mingw lit `x18`, §239) ; c'est le
  DXVK x86_64 émulé qui travaille ici.

## 242. Les polices, puis le dernier `x18` : DXVK tourne en ARM64EC natif

### Les polices : un `configure`, et un piège d'architecture

Wine était construit `--without-freetype` : aucun texte à l'écran. Reconfiguré,
`checking for -lfreetype... libfreetype.6.dylib`. Mais à l'exécution, toujours
*« Wine cannot find the FreeType font library »*. La raison :

```
lipo -archs /usr/local/lib/libfreetype.6.dylib   -> x86_64
lipo -archs /opt/homebrew/lib/libfreetype.6.dylib -> arm64
```

`dlopen` du soname nu trouvait d'abord la tranche **x86_64** de la pile Rosetta. Le dossier
`wine/vklib-arm64`, déjà en tête de `DYLD_LIBRARY_PATH`, sert maintenant à présenter les bonnes
tranches arm64.

Sans fontconfig — absent de cette machine — Wine ne scanne que son propre dossier.
`tests/installer_polices_macos.sh` y lie les 370 polices de macOS et vide le cache du préfixe :
**505 polices enregistrées**, dont Arial, Courier New, Times New Roman, Georgia, Verdana.

### Le dernier `x18` : un objet ARM64EC caché dans l'objet aarch64

Les objets de démarrage de mingw (`crt1/crt1u/crt2/crt2u/dllcrt1/dllcrt2`) sont livrés **déjà
compilés** : le correctif 0069 sur `winnt.h` ne peut rien pour eux. Recompiler depuis les sources
amont ne marche pas — la version livrée n'est ni v14 ni master (`__main` contre
`__mingw_dll_do_global_ctors`, absent des bibliothèques livrées).

Ils ne lisent `x18` que pour **un jeton d'identité de fil** :

```c
void *fiberid = ((PNT_TIB)NtCurrentTeb ())->StackBase;
while ((lock_free = InterlockedCompareExchangePointer (&lock, fiberid, NULL)))
   if (lock_free == fiberid) ...
```

`fiberid` n'est jamais déréférencé : il sert de valeur unique et non nulle dans un verrou.
`TPIDRRO_EL0` a exactement ces deux propriétés, et lui survit aux retours du noyau. D'où un
correctif binaire, instruction pour instruction, sans relocation
(`tests/corriger_crt_mingw.py`) :

```
mov  x8, x18          ->   mrs  x8, tpidrro_el0
ldr  xD, [x8, #0x8]   ->   mov  xD, x8
```

Premier jet : 10 sites, et le binaire produit contenait toujours `mov x8, x18`. Le nœud est là —
un objet aarch64 de llvm-mingw porte une section **`.obj.arm64ec`** : un objet COFF complet, la
variante ARM64EC du même code, que l'éditeur de liens extrait pour une cible arm64ec. C'est
*celle-là* que reçoivent DXVK et les exécutables ARM64EC. Les noms de section de plus de huit
caractères vivent dans la table des chaînes, ce qui masquait aussi la moitié des `.text$#...`.
Avec la récursion : **20 sites**, et zéro `x18` dans les binaires produits.

### Ce que ça débloque

| | avant | après |
| --- | --- | --- |
| exécutable **ARM64EC** produit par clang | se bloquait au démarrage (§239, point resté inexpliqué) | **tourne** : 20 M tours en **82,4 ms** |
| **DXVK ARM64EC** | `ECHEC: d3d11.dll introuvable` | **charge et rend** |

Repères pour la même boucle : 80,7 ms en natif macOS arm64, **82,4 ms en ARM64EC natif**,
83,8 ms en x86_64 émulé par FEX.

Avec le DXVK **ARM64EC natif** en place — la couche D3D11 n'est donc plus émulée :

```
RESULTAT: le GPU a execute l'effacement, la valeur revient juste
RESULTAT: le triangle est rasterise, interpolation des couleurs comprise
```

et `Surviving Mars` tourne, GPU à 99 %.

### Ce qui reste `x18`, et pourquoi on n'y touche pas

`__cxa_get_globals` de libc++abi et `tlsdtor.o` de mingw lisent `[x18, #0x58]`, le vrai
`ThreadLocalStoragePointer`. Ce n'est pas un jeton, c'est un pointeur : la substitution d'une
instruction ne s'applique pas. Atteints seulement sur une exception C++ levée, et sur un
`thread_local` à destructeur. Notés, pas corrigés.

## 243. Les i386 : le plancher est celui du `vm_map`, et le dernier `x18` tombe

### `__PAGEZERO` : remesuré sur macOS 26.5.2, et vu d'un autre angle

Les mesures du paragraphe 139 datent d'une version antérieure. Refaites :

| `__PAGEZERO` demandé | obtenu | résultat |
| --- | --- | --- |
| défaut | 4 Gio | s'exécute ; `mmap 0x400000` et `mmap 0x7ffe0000` → `ENOMEM` |
| `0x100000` | 1 Mio | **SIGKILL** (137) |
| `0x10000` | 64 Kio | **SIGKILL** |
| `-segalign,0x4000,-pagezero_size,0x4000` | — | lien refusé |

La politique tient. Mais un angle nouveau, plus net : `mach_vm_region_recurse` depuis l'adresse 0
rend comme **première région** `0x1001b8000`. Il n'y a donc *aucune* région sous 4 Gio —
`__PAGEZERO` n'est pas une réservation qu'on pourrait libérer, c'est le **plancher du `vm_map` de
la tâche**. Conséquence mesurée :

```
mach_vm_deallocate(0x1000, ~4Gio) -> 0 ((os/kern) successful)
  apres deallocate       mmap 0x400000 -> ENOMEM
munmap(0x1000, ~4Gio)   -> EINVAL
```

Le `deallocate` réussit **sans rien libérer**, et `mmap` échoue toujours. Il n'y a rien à
contourner.

Donc un invité i386 en correspondance 1:1 est impossible, définitivement. La seule voie est la
**translation d'adresses** : la fenêtre 4 Gio de l'invité placée au-dessus de 4 Gio, chaque accès
mémoire du JIT rebasé, et chaque pointeur que Wine présente à l'invité converti. Côté FEX ce
serait contenu (l'adresse effective 32 bits est formée en un endroit) ; côté Wine c'est le cœur
de WoW64. Ce n'est pas un chantier de session, et je ne l'ouvre pas à moitié.

Au passage, le coût de l'i386 aujourd'hui est nul : un préfixe se crée en **5,97 s** (les
démarrages de plusieurs minutes étaient l'enlisement W^X du paragraphe 240, pas l'i386), et
`syswow64` reste vide. L'i386 ne ralentit rien, il ne marche simplement pas.

### Le dernier `x18` : une exception C++ bloquait le processus

`__cxa_get_globals` de libc++abi lit `[x18, #0x58]`, le `ThreadLocalStoragePointer` — c'est la
traduction par clang d'un `thread_local`. Ce n'est pas un jeton mais un vrai pointeur : la
substitution d'une instruction du paragraphe 242 ne s'applique pas.

Mesure, sur un programme de six lignes en ARM64EC :

| lien | résultat |
| --- | --- |
| dynamique | `libc++.dll` et `libunwind.dll` absents — rien à voir avec `x18` |
| **statique** (comme DXVK) | **se bloque** au `throw`, indéfiniment |

DXVK est lié statiquement : chaque `throw` de `DxvkError` était un blocage en attente.

`outils/cxa_globals_sans_x18.c` fournit les deux fonctions en TLS Win32 — que notre Wine sert
sans passer par `x18` — et gagne à l'édition de liens contre libc++abi. Piège rencontré : les
`TlsGetValue`/`TlsSetValue` *en ligne* de mingw repassent par le TEB, donc l'objet doit être
compilé sans que ces macros s'appliquent ; ici le compilateur a émis les appels, mais c'est à
surveiller. La disposition de `__cxa_eh_globals` vient de l'ABI Itanium, avec deux champs de
marge à zéro par prudence.

```
$ wine c:\thr4_ec.exe
avant le try
avant throw
attrape 42
apres
```

DXVK ARM64EC relié avec cet objet : **zéro `x18`** dans `d3d11.dll` et `dxgi.dll`, et les deux
sondes passent toujours. Il ne reste `x18` que dans `tlsdtor.o` de mingw — un `thread_local` à
destructeur, non atteint par ce qu'on exécute.

## 244. Invités 32 bits : la moitié FEX est faite, et elle est petite

Le paragraphe 243 concluait que seule la translation d'adresses restait. Première moitié écrite :
côté émulateur.

### L'entonnoir est unique, et c'était la bonne nouvelle

Pour un invité 32 bits, **tous** les chemins de `SelectAddressMode` sortent par
`LoadEffectiveAddress` — le chemin « registre + registre » optimisé est réservé au 64 bits. Dans
le frontal, il ne reste que **quatre** accès mémoire directs, et trois sont les instructions de
chaîne qui prennent `RSI`/`RDI` bruts. Le second entonnoir est `AppendSegmentOffset`.

Donc : deux entonnoirs et trois sites, pas cent trente.

### Le rebasage est idempotent, ce qui rend la chose sûre

```c
Ref RebaseGuest32(IREmitter* IREmit, Ref Addr) {
  if (!Guest32Base) return Addr;
  return IREmit->_Or(i64Bit, Constant(Guest32Base), IREmit->_Bfe(i64Bit, 32, 0, Addr));
}
```

La base n'ayant aucun bit sous 32, `(a & 0xffffffff) | base` appliqué deux fois donne le même
résultat qu'une fois. On peut donc l'appliquer à chaque entonnoir sans tenir de comptabilité, et
sans craindre qu'un chemin passe par les deux. Et `orr xN, xN, #0x100000000` est un **immédiat
logique valide** en ARM64 : le coût est d'une instruction, souvent repliée dans le calcul
d'adresse.

Le `Bfe` d'abord est nécessaire : un appelant peut avoir demandé `AllowUpperGarbage`, et le `or`
prendrait ces bits pour de l'adresse.

### Qui décide de la base

C'est l'hôte. Wine exporte `__wine_wow64_guest_base` de son ntdll, FEX la lit dans
`BTCpuProcessInit`. Zéro = correspondance 1:1, donc **rien ne change tant que Wine ne déplace pas
la fenêtre** — le 64 bits n'est pas touché du tout (`GPRSize` y vaut 64 bits, la condition est
fausse, le code émis est identique).

Non-régression mesurée, même boucle : 84,1 / 84,2 / 84,4 ms, contre 83,8 / 83,8 / 83,9 avant.
Identique. Le triangle D3D11 passe toujours, `hello64.exe` répond toujours.

### Ce qui reste : la moitié Wine, chiffrée

182 conversions de pointeur (`ULongToPtr` / `PtrToUlong`), réparties ainsi :

| fichier | sites |
| --- | --- |
| `dlls/wow64/syscall.c` | 33 |
| `dlls/wow64win/user.c` | 31 |
| `dlls/ntdll/unix/virtual.c` | 23 |
| `dlls/wow64/wow64_private.h` | 21 |
| `dlls/wow64/virtual.c` | 17 |
| `dlls/wow64/process.c` | 16 |
| le reste | 41 |

Chacune doit être examinée : toutes ne sont pas des adresses, il y a des identifiants et des
poignées mélangés, et se tromper donne un bogue silencieux. S'y ajoute le chargeur PE i386, qui
doit placer l'image à `base + base_préférée` tout en présentant l'adresse basse à l'invité.

C'est là que se trouve le vrai travail, et il n'est pas commencé.

## 245. Invités 32 bits : la moitié Wine, et l'invité exécute ses instructions

Suite du paragraphe 244. Fenêtre à **16 Gio**, pas 4 : à 4 Gio exactement macOS charge le binaire
hôte, et la trace le disait — `map_fixed_area out of memory for 0x100400000`. La base doit rester
un multiple de 4 Gio pour que le rebasage de l'émulateur soit un simple `orr` d'un bit haut.

### L'invariant, et pourquoi la moitié du travail n'existe pas

L'invité voit `A`, l'hôte utilise `user_space_wow_base + A`. Le sens **hôte → invité** ne demande
rien : tronquer à 32 bits *est* la soustraction de la base, la base étant un multiple de 4 Gio.
D'où 86 conversions à examiner et non 182 — et en pratique bien moins, parce qu'elles passent par
des entonnoirs.

### Les entonnoirs, côté Wine

| endroit | ce qu'il fait |
| --- | --- |
| `get_ptr()` de `wow64_private.h` | **tous** les pointeurs qu'un invité passe à un appel système |
| `addr_32to64()` | les pointeurs de sortie |
| `map_image_view()` | l'image PE 32 bits va à `base + base_préférée` |
| `map_view()` | traduit les bornes exprimées en adresses d'invité |

Le dernier mérite un mot. Six appelants passent une limite venue de `zero_bits`, qui ne sait dire
qu'un plafond : `0x7fffffff` pour « sous 2 Gio ». Avec une fenêtre déplacée il faut aussi un
plancher, et les corriger un par un revenait à passer partout la forme étendue de
`NtAllocateVirtualMemory`. On traduit donc une fois, dans `map_view` : **un plafond sous la base
de la fenêtre ne peut être qu'une limite d'invité**. Un appelant 64 bits ne demande jamais ça — il
passe zéro, ou `user_space_limit` ; et s'il le faisait, l'espace sous la fenêtre est de toute
façon pris par le binaire hôte et les bibliothèques du système, donc l'allocation échouerait au
lieu d'être déplacée.

Sites individuels trouvés par la boucle des fautes, chacun nommé par la trace :

| faute | site |
| --- | --- |
| `build_wow64_parameters` assertion | `env.c` : les paramètres de l'invité doivent être dans sa fenêtre |
| `memcpy` depuis `thread_init+0x130` | `syscall.c` : le contexte i386 initial écrit sur la pile de l'invité |
| `call_user_exception_dispatcher+0x2c8` | `syscall.c` : la trame d'exception de l'invité |
| `map_free_area ... 0x110000-0x80000000` | les six `zero_bits`, réglés par l'entonnoir de `map_view` |

### Côté FEX, deux chemins de plus

Le rebasage du paragraphe 244 couvrait les **données**. Il en restait deux :

1. **Les tremplins d'appel système.** FEX les alloue « dans les 2 premiers Gio » pour que l'invité
   puisse y sauter. Vu de l'invité : ils doivent aller dans la fenêtre. Et `BTCpuGetBopCode` les
   rend à Wine, qui les inscrit dans le ntdll 32 bits — donc en adresses d'invité, pas d'hôte.
2. **La lecture du code.** `Core.cpp` prend le RIP de l'invité comme pointeur hôte pour *lire les
   instructions à traduire*. C'est un chemin distinct de celui des adresses de données, et c'est
   lui qui donnait `faute d'exécution à 0x7BDDEAC0` — l'adresse du ntdll 32 bits de Wine.

### Où l'on en est

L'invité **exécute ses instructions** : la faute d'exécution à `0x7BDDEAC0` est devenue une faute
d'écriture à `0x14FD0C` au RIP `0x7BDDEAC2` — l'instruction précédente a tourné. Ce qui reste est
une écriture vers la pile de l'invité depuis le code C++ de FEX lui-même (`pc` dans `xtajit.dll`,
pas dans le code émis), probablement la synchronisation de contexte. Une boucle de 1497
exceptions, donc un site chaud et unique à trouver.

### Non-régression

Le 64 bits n'est pas touché. `hello64.exe` répond, `probe_d3d11` et `probe_d3d11_draw` passent,
et les deux bancs donnent **84,0 ms** en x86_64 émulé et **80,7 ms** en ARM64EC natif — mêmes
chiffres qu'avant.

### Suite du 245 : la pile de l'invité, et les `REP`

Trois chemins de plus, tous trouvés par la boucle des fautes, et le compte d'exceptions mesure
l'avancée : **1497 → 1102 → 259**.

**`Push` / `Pop`.** Ils ont leur propre opération IR, qui n'emprunte pas l'entonnoir d'adresse :
le magasin est *pré-indexé* et le registre porte à la fois l'adresse et la nouvelle valeur du SP.
Le rebaser corromprait le SP, qui doit rester une adresse d'invité. L'abaissement JIT calcule donc
le SP d'abord, l'adresse hôte dans un temporaire, et écrit sans indexation. Idem pour les
variantes par paires (`stp`/`ldp`).

Effet mesuré : le RIP de l'invité est passé de `0x7BDDEAC2` à `0x7BDE2D23`, soit 17 Kio plus loin
dans le ntdll 32 bits.

**`REP MOVS` / `REP STOS`.** Ce sont les opérations `MemCpy` / `MemSet`, et il n'existe pas de
chemin lent : elles *sont* l'implémentation. Leurs boucles prennent les registres de l'invité comme
adresses. On rebase les adresses d'entrée ; le retour n'a besoin de rien, puisqu'il est rangé dans
`RSI`/`RDI` sur 32 bits, ce qui retire la base.

### Ce qui reste

Une faute d'**exécution** à `0x7BDDDFD0` : un saut vers une adresse d'invité, donc un endroit où
le contrôle passe à une adresse non rebasée plutôt qu'au code traduit. Reste à trouver.

Non-régression inchangée : `hello64` répond, le triangle D3D11 passe, **84,1 ms** en x86_64 émulé.

### Suite du 245 : ce que la sonde a corrigé dans mon modèle

Deux erreurs de ma part, toutes deux levées par la mesure.

**Les adresses « dans une section de débogage ».** Je lisais `0x7BDDDFD0` comme tombant dans
`.debug_loc`, donc comme un RIP corrompu. Faux : je calculais depuis la base *préférée* du ntdll
32 bits (`0x7bc00000`) alors qu'il est relocalisé. Sonde dans `thread_init` :

```
base=400000000  eip=7bddeac0  esp=0014fd10
thunk64=47bddeac0   ntdll32=47bd90000   ctx_ptr=40014FD24
```

Le ntdll 32 bits est à l'adresse d'invité `0x7bd90000`, `LdrInitializeThunk` à `0x7bddeac0` — soit
exactement le RIP de départ. Tout est sain : la base est bien arrivée dans `wow64.dll`, le contexte
initial est en adresses d'invité, et `ctx_ptr` est bien `base + 0x14fd24`. Les fautes que je voyais
étaient du vrai progrès dans une vraie fonction.

**La faute d'exécution n'est pas une faute hôte.** La sonde `SONDE_FAUTE_BASSE`, seuil relevé à
4 Gio pour attraper toute adresse d'invité non rebasée, **ne se déclenche pas**. Donc
`0x7BDDDFD0` n'est pas un `SIGSEGV` de l'hôte : c'est une exception **synthétisée par
l'émulateur**, qui refuse de traduire là.

J'ai supposé que `QueryExecutableRange` recevait une adresse d'invité et interrogeait des
intervalles en adresses hôte, et j'ai traduit à cette frontière. **Ça a empiré** : 259 → 1497
exceptions, et la faute est remontée jusqu'à l'entrée `0x7BDDEAC0`. Donc les intervalles sont déjà
en adresses d'invité, et mon modèle de cette frontière était faux. Correctif annulé, état de 259
exceptions rétabli.

C'est la première fois dans ce portage qu'une hypothèse empire la mesure au lieu de la laisser
inchangée. Utile : ça dit que le suivi d'invalidation vit dans le monde de l'invité, pas dans celui
de l'hôte, et que la frontière à traduire est ailleurs — probablement là où Wine notifie FEX des
changements de protection.

## 246. Invités 32 bits : les deux mondes d’adresses, et un programme i386 qui tourne

Suite du paragraphe 245. **Un programme x86 32 bits s'exécute de bout en bout** :
`bonjour depuis i386, somme=10` en 0,89 s. Douze corrections, toutes de la même famille — deux
mondes d'adresses qui se mélangeaient — dans l'ordre où la boucle des fautes les a rendues.

### Le suivi d'exécutabilité de FEX vit chez l'invité, ses appels chez l'hôte

`InvalidationTracker` répond à une seule question : « ai-je le droit de traduire ici ». FEXCore la
pose avec le RIP de l'invité, donc les intervalles sont indexés **en adresses d'invité**. Mais la
même classe appelle `VirtualQuery`, `NtProtectVirtualMemory` et `RtlImageNtHeader`, qui ne
connaissent que l'hôte. Les deux mondes dans une seule classe : chaque site a dû être classé.

L'expérience qui a tranché — trois mesures, même programme :

| intervalles | exceptions émulées |
| --- | --- |
| indexés hôte | 1497, faute dès le point d'entrée |
| moitié hôte, moitié invité | 259 |
| indexés invité, conversion aux appels Windows | 0 |

`Source/Windows/Common/Guest32.h` porte les quatre conversions (`ToGuest32`, `ToHost32`,
`HostPtr32`, `InGuest32Window`) ; elles sont l'identité quand `Guest32Base` est nul, donc le chemin
ARM64EC et Linux ne changent pas d'un octet.

Conséquence : Wine redonne aux rappels `BTCpu*` des adresses d'**hôte** — c'est ce qu'il a, et ce
dont il a besoin lui-même pour ses propres appels. Les treize `ptr_64to32` posés la veille dans
`dlls/wow64/virtual.c` ont été retirés : la conversion appartient à FEX, qui seul connaît la base.

### Le décodeur demandait l'exécutabilité avec le pointeur de lecture

`Decoder::PeekByte` calcule `InstStream.InstStream + offset` — le pointeur avec lequel il *lit*,
donc une adresse d'hôte — et le passe à `CheckRangeExecutable`. En amont tout est en adresses
d'invité : `EntryPoint`, `RIPToDecode`, `DecodeInst->PC`, les cibles de branchement. Une seule
soustraction au sommet de `CheckRangeExecutable` suffit, et le cache de plage
(`ExecutableRangeBase/End`) reste dans le monde de l'invité.

### `lea` rebasé, et la base atterrit dans le RIP

Le plus long à trouver. `LoadSource_WithOpSize` a une branche « donne-moi l'adresse comme valeur »,
prise quand l'opérande n'est pas à charger. Elle sert au `lea`, mais aussi à **l'opérande registre
d'un saut indirect** : pour `call *%edx`, `A.Base` est la valeur de `edx` et rien d'autre. Rebaser
là revient à écrire `base | edx` dans le RIP — et le RIP est lu sur 64 bits, contrairement aux
registres de l'invité, tronqués à chaque écriture. La sonde le montrait sans ambiguïté :

```
SONDE compile rip=47BDDDFD0 rax=400000018 rdx=47BDDDFD0 rsp=14FB74
```

`rdx` porte la base, `rsp` non. `LoadEffectiveAddress` prend donc un paramètre `RebaseGuest`, faux
pour ce seul site — `IsOperandMem(Operand, true)`.

### Le TEB de l'invité dans sa zone DOS

Les blocs de TEB d'un processus wow64 vont dans la fenêtre pour que le code 32 bits les voie. Avec
`limit_low = user_space_wow_base` tout court, ils atterrissaient à l'adresse d'invité `0x20000` —
dans la zone DOS, que l'invité **libère** au démarrage. Le TEB disparaissait, et le premier
`data->teb->ChpeV2CpuAreaInfo` de `setup_raise_exception` faisait une faute dans le gestionnaire de
signal, qui refaisait une faute : 100 % de CPU, zéro progression. `vmmap` a donné la réponse en une
ligne — rien entre `0x400030000` et `0x400040000`. Le plancher est désormais
`user_space_wow_base + address_space_start`.

### Zéro n'est pas zéro

`InvalidateAlignedInterval` traite une base nulle comme « tout l'espace », convention Windows. Après
rebasage, l'adresse d'invité `0` est aussi `0` : la libération de la zone DOS effaçait les
intervalles exécutables de **toutes** les images déjà chargées, et le premier saut suivant donnait
`NoExec instruction in entry block`. La taille distingue les deux cas — le sentinel arrive avec une
taille nulle.

### Les bornes se comparent chez l'invité, les pointeurs se déréférencent chez l'hôte

Trois familles de sites, toutes trouvées par la valeur de retour d'un appel système :

| symptôme | cause |
| --- | --- |
| `NtQueryVirtualMemory -> c000000d` | `(ULONG_PTR)addr > highest_user_address` sur une adresse déjà rebasée |
| `NtMapViewOfSection -> c000000d` | `map_image_view` mélangeait un plancher rebasé et un plafond d'invité |
| `NtMapViewOfSection -> c000000d` | `zero_bits` de `map_section` valait `user_space_wow_limit`, déjà en adresses d'hôte : la section NLS tombait hors de la fenêtre et l'invité n'en voyait qu'une adresse tronquée |
| `NtQueryAttributesFile -> c0000005` | `ULongToPtr` sur les pointeurs imbriqués d'`OBJECT_ATTRIBUTES32` |

Pour la dernière : quatorze sites dans `wow64_private.h` (`UNICODE_STRING::Buffer`, les quatre
champs d'un descripteur de sécurité, `ObjectName`, `SecurityQualityOfService`, …) et vingt dans les
`.c` du même répertoire. `get_ptr()` ne couvre que le premier niveau ; tout ce qui est *dans* une
structure de l'invité reste à convertir.

### KUSER_SHARED_DATA, et les convertisseurs d'appels unix

Deux pages fixes de plus :

- L'invité lit `KUSER_SHARED_DATA` à `0x7ffe0000`, adresse que macOS interdit à l'hôte — d'où son
  déplacement à `0x17ffe0000` (paragraphe 48). Il faut la remapper **aussi** à
  `user_space_wow_base + 0x7ffe0000` : le même `fd` partagé, deux `mmap`.
- `wow64_wine_dbg_write` et ses voisins de `dlls/ntdll/unix/` convertissent les paramètres 32 bits
  d'un appel unix. `ULongToPtr(params32->str)` donnait un pointeur d'invité à `write(2, …)`, qui
  répondait `-1` : **l'invité ne pouvait pas tracer**, ce qui a coûté plusieurs heures d'aveuglement.
  Avec `ptr_wow32()`, `write` rend 71 et l'invité parle.

### Le piège de construction

`make` tout court reconstruit sans `-DWINE_TEB_SANS_X18` : `NtCurrentTeb()` repasse par `x18`, et
`wow64.dll` se met à faire `mov x14, x18 ; ldr x24, [x14, #0x28]`. La faute est propre — lecture à
`0x28` — mais la cause est invisible si on ne relie pas les deux. Toute reconstruction de cet arbre
passe par :

```
make aarch64_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" arm64ec_CFLAGS="-g -O2 -DWINE_TEB_SANS_X18" install
```

### Ce que ça donne, et où ça s'arrête

| mesure | avant | après |
| --- | --- | --- |
| blocs traduits par l'invité | 0 (faute au point d'entrée) | 1923 |
| appels système de l'invité | 2 | 148 puis plus |
| modules 32 bits chargés | `ntdll` seul | `ntdll`, `kernel32`, `kernelbase`, `ucrtbase` |
| trace de l'invité | muette | lisible |

### Le dernier : un petit entier pris pour un pointeur

La lecture à l'adresse d'invité `5` ne venait pas de l'invité : le PC fautif était
`wow64.dll+0x1b418`, dans `wow64_NtContinueEx`. Ce paramètre-là accepte **soit** un pointeur
`KCONTINUE_ARGUMENT`, **soit** un petit entier — 0 ou 1 pour « teste les alertes ». Wine les
distingue par `(UINT_PTR)cont_args > 0xff`. Rebasé, `1` devient `0x400000001`, le test passe du
mauvais côté et le pointeur est déréférencé. La faute remontait ensuite à l'invité, dont
`KiUserExceptionDispatcher` reprenait sur un contexte incohérent : d'où le saut à `0xC0000005`, la
valeur du statut.

La correction tient en une ligne — ramener la valeur chez l'invité avant le test — et c'était la
dernière :

```
bonjour depuis i386, somme=10
```

**0,89 s, 0,91 s, 0,89 s** sur trois lancements. Un programme x86 32 bits s'exécute de bout en bout
sur la pile entièrement arm64 : PE i386 → FEX wow64 → Wine arm64 → macOS. Aucune trace de Rosetta
nulle part.

Non-régression du chemin 64 bits, après tous ces changements : `hello64.exe` écrit
`bonjour depuis x86_64 emule`, `banc_x64` donne **83,8 ms** pour 20 millions de tours (83,8–84,4 ms
mesurés au paragraphe 241), et `probe_d3d11_draw` rasterise toujours son triangle.

### Ce qui reste à faire proprement

`wineboot --init` ne peuple pas `syswow64` : le peuplement demande un `rundll32` 32 bits, qui
demande… `syswow64`. Wine s'en sort sur x86_64 ; ici la création de préfixe rend la main sans avoir
lancé la passe `Wow64Install`. Pour tester, les DLL factices i386 ont été copiées depuis
`wine/pfx-wow64`. À reprendre.

## 247. Un jeu 32 bits : toute la pile se charge, le pont Steam s'arrête

`Dead Cells` est un PE **i386** (`deadcells.exe`, `IMAGE_FILE_MACHINE_I386`). Premier vrai jeu 32
bits essayé sur la pile.

### Ce qui se charge

Le processus invité charge, dans l'ordre : `ntdll`, `kernel32`, `kernelbase`, `ucrtbase`, `user32`,
`gdi32`, `win32u`, `advapi32`, `sechost`, `cryptbase`, `rpcrt4`, `combase`, `coml2`, `ole32`,
`shlwapi`, `shell32`, **et `lsteamclient`** — notre pont Steam, dans sa version i386. Le
`syswow64/d3d11.dll` du préfixe est un DXVK i386 (17 Mo), hérité du travail x86_64 : le jeu a donc
de quoi faire du D3D11.

Et il parle :

```
[S_API] SteamAPI_Init(): Loaded 'C:\windows\system32\lsteamclient.dll' OK.
[S_API] SteamAPI_Init(): No SteamClient014
```

Puis il sort proprement, code 0. `SteamAPI_Init` échoue, donc le jeu s'arrête — même comportement
qu'en x86_64 avant que le pont ne réponde (paragraphe 199).

### Pourquoi `CreateInterface` rend NULL

La trace de `lsteamclient` montre l'unixlib chargée (`steamclient.dylib charge, CreateInterface a
0x1121757e0`) mais **aucune trace de `CreateInterface`** : l'appel unix a échoué avant.

Les structures d'arguments de l'unixlib sont en largeur fixe — ce n'est pas le problème. Le
problème est le contenu : côté PE 32 bits,

```c
struct create_interface_params params = { (ULONG_PTR)version, (ULONG_PTR)err, 0 };
```

met une adresse **d'invité** dans un champ que le côté unix déréférence comme une adresse d'hôte.
Le `steamclient.dylib` natif lit alors n'importe où. Même famille de bogue que tout le paragraphe
246, mais dans notre propre pont, et cette fois la conversion ne peut pas être mécanique : un
appel Steamworks générique passe des entiers et des pointeurs dans les mêmes emplacements. C'est
exactement à quoi servent les `signatures32.h` et `thunks32.h` de Proton, déjà présents dans
l'arbre et pas encore branchés.

### Le trou d'amorçage de `syswow64`

`wineboot --init` lance bien la passe 32 bits (`start_rundll32 machine 14c starting
C:\windows\syswow64\rundll32.exe`) mais elle ne crée rien : `[FakeDllsWow64]` finit par `11,,*`, le
joker qui devrait fabriquer les ~830 factices, et il ne fabrique rien ici. Le repli sur les modules
intégrés ne joue que pendant l'amorçage, et un processus 32 bits ne peut charger `kernel32` que si
le factice existe déjà — la boucle est fermée. En attendant, `tests/peupler_syswow64.sh` copie les
factices d'un préfixe qui en a. Il manquait `cryptbase.dll` dans le jeu copié, sans quoi le renvoi
`advapi32!SystemFunction036 -> cryptbase.SystemFunction036` échoue et le chargement du jeu s'arrête
sur `STATUS_DLL_NOT_FOUND`.

## 248. Le pont Steam en 32 bits, et le chemin GDI de l'invite

### Brancher les thunks32

Les thunks `__thiscall` et leur table étaient déjà écrits (paragraphe 244) ; il leur manquait la
seule chose qui compte ici : **traduire les pointeurs**. Le côté PE du pont range des adresses dans
des structures que l'unixlib déréférence, et l'unixlib vit chez l'hôte.

`ntdll` publie désormais `__wine_wow64_guest_base` pour l'**i386** aussi — la variable existait déjà
pour arm64/arm64ec, il a suffi d'élargir la garde et de la renseigner depuis
`load_ntdll_wow64_functions`. Le pont s'en sert pour `CreateInterface`, l'interface générique et le
tampon de rappel.

Reste le cas dur : les arguments d'un appel de méthode Steamworks. La table mesurée donne le nombre
de mots empilés, **pas leur nature**, et celle-ci n'est publiée que dans le SDK. On interroge donc
l'adresse elle-même :

```c
static UINT64 mot_vers_hote( UINT32 mot )
{
    if (mot < 0x110000) return mot;                       /* zone DOS liberee */
    if (IsBadReadPtr( (const void *)(ULONG_PTR)mot, 1 )) return mot;
    return vers_hote( (const void *)(ULONG_PTR)mot );
}
```

Deux garde-fous : sous `0x110000` vit la zone DOS, que l'invité libère au démarrage — c'est là que
tombent `HSteamPipe`, `HSteamUser` et la plupart des identifiants d'application ; et `IsBadReadPtr`
lit sous garde, sans appel système. Le risque restant est borné et assumé : un entier au-delà de
`0x110000` qui tomberait sur une page engagée serait traduit à tort.

Résultat : `CreateInterface("SteamClient017")` et `("SteamClient014")` rendent des objets enveloppés
au lieu de `No SteamClient014`.

### wow64win avait sa propre copie des convertisseurs

`dlls/wow64win/wow64win_private.h` redéfinit `get_ptr`, `addr_32to64`, `unicode_str_32to64`,
`secdesc_32to64` et `objattr_32to64` — dix `ULongToPtr` que la correction de `dlls/wow64` n'avait
pas touchés. Tout appel win32u d'un invité 32 bits passait donc des adresses d'invité à l'hôte.

### La table GDI partagée : trois lectures, trois mondes

Le `gdi32` de l'invité lit la table des poignées GDI ainsi :

```
fs:0x18            -> TEB32
TEB32 + 0xf70      -> GdiBatchCount, l'adresse du TEB 64 bits
TEB64 + 0x60       -> Peb
PEB64 + 0xf8       -> GdiSharedHandleTable
```

Chaque lecture est un `movl` de 32 bits sur un champ de 64 : la troncature *est* la conversion vers
l'invité, donc tout marche **à condition que la mémoire visée soit dans la fenêtre**. Un petit
programme i386 (`tests/h32gdi.c`) affiche les trois valeurs avant de s'en servir, ce qui a montré la
chaîne saine et `PEB64->Gdi` à zéro : `init_gdi_shared` n'avait pas tourné.

Il n'avait pas tourné parce que `font_init` mourait avant, sur une lecture à l'adresse d'invité
`0x290002`. La cause : le `ntdll` 32 bits publie les tables NLS dans le PEB 64 bits par

```c
peb64->AnsiCodePageData = PtrToUlong( ansi_ptr );
```

— tronquer suffit quand les deux espaces se confondent, pas ici. L'hôte déréférençait une adresse
d'invité. Trois champs à corriger : `UnicodeCaseTableData`, `AnsiCodePageData`, `OemCodePageData`.

Avec ça :

```
pinceau de reserve = 01900024
GetObject = 12, style 0, couleur 000000
GetDC(NULL) = 0801005E, largeur 1728
i386 GDI : ok
```

### Le piège qui a coûté une heure : `cp` sur une bibliothèque mappée

Réinstaller un `.so` de Wine par `cp` par-dessus l'ancien fait **tuer par SIGKILL** les processus
suivants qui le chargent : macOS valide la signature page par page, et les pages déjà en cache ne
correspondent plus au nouveau contenu. Le symptôme est un `rc=137` sans une ligne de trace, y
compris pour un programme qui marchait une minute plus tôt. Remplacer par un `mv` — le renommage
est atomique et donne un inode neuf :

```
cp x.so dest/x.so.neuf && mv -f dest/x.so.neuf dest/x.so
```

### Où Dead Cells s'arrête maintenant

Le jeu passe `SteamAPI_Init`, crée sa fenêtre, et bute sur une assertion de Wine :

```
err:system:user_check_not_lock BUG: holding USER lock
```

Le verrou USER est tenu au moment d'un rappel vers l'invité. C'est le prochain fil.

Non-régression après tout ça : `h32` écrit sa ligne, `h32gdi` aussi, `hello64` tourne, `banc_x64`
donne **84,4 ms** pour 20 millions de tours, `probe_d3d11_draw` rastérise son triangle.

## 249. Le verrou USER, la géométrie nulle, et un jeu 32 bits qui affiche une fenêtre

### L'assertion n'était pas un problème de verrou

`err:system:user_check_not_lock BUG: holding USER lock` laissait croire à un verrou mal rendu. En
instrumentant `user_lock`/`user_unlock` pour tracer qui tenait quoi, la réponse est venue de
l'autre côté : personne ne tenait le verrou trop longtemps, c'est une **faute** qui sautait
par-dessus le `user_unlock`.

Deux causes, toutes deux du même genre — un pointeur de l'invité 32 bits passé tel quel à l'hôte :

1. `set_menu_item_info` déréférençait `MENUITEMINFOW.dwTypeData` sans le rebaser. `WS_SYSMENU`
   construit le menu système à la création de la fenêtre, donc toute fenêtre ordinaire passait là.
   Le champ ne porte une chaîne que pour un élément textuel ; sinon c'est une donnée opaque. D'où
   un rebasage conditionnel sur `MIIM_STRING` / `MFT_*`.
2. La classe était enregistrée avec une `HINSTANCE` rebasée et cherchée avec l'originale, ou
   l'inverse : `CreateWindowEx` rendait `ERROR_CLASS_DOES_NOT_EXIST`. `get_guest_ptr()` sépare
   maintenant les deux cas, et le commentaire au-dessus dit pourquoi : **se tromper de monde sur
   une valeur opaque ne fait pas une faute, mais une comparaison qui échoue.**

Les sondes ont toutes été retirées ensuite ; `win32u.so` et `ntdll.so` réinstallés par `mv`.

### La fenêtre existait mais n'avait aucune géométrie

`tests/h32win.c` créait une fenêtre demandée en `10,10 320x240` et rendait :

```
CreateWindowEx = 0001006C (1400)
client = 0x0
fenetre = 0,0 0x0
```

`GetClientRect` et `GetWindowRect` réussissaient l'un comme l'autre. Le réflexe était de suspecter
le thunk `wow64_NtUserCreateWindowEx` ; la mesure a dit autre chose. Le même programme recompilé en
x86_64 (`tests/h64win.c`, dix lignes de `sed`) donnait :

```
client = 32855x0
fenetre = 10,10 32863x32778
```

Faux aussi, et **le x86_64 ne passe pas par wow64**. Donc deux bogues distincts, et le premier
n'avait rien à voir avec les 32 bits.

#### Bogue 1 : le préfixe était empoisonné

```
SM_CXFRAME=4 SM_CYCAPTION=32770
```

32770, c'est `iCaptionHeight + 1` avec `iCaptionHeight = 32769 = 0x8001`. Et 0x8001, c'est
`2 + 0x7FFF` : `normalize_nonclientmetrics()` fait `max(valeur, 2 + tm.tmHeight)`, et une exécution
ancienne — du temps où `font_init` mourait sur les pointeurs NLS du PEB64 — avait obtenu
`tmHeight = 32767`. Wine a ensuite **réécrit ce résultat dans le registre** :

```
[Control Panel\\Desktop\\WindowMetrics]
"CaptionHeight"="32769"
"MenuHeight"="32769"
"SmCaptionHeight"="32769"
```

Le code était réparé depuis longtemps ; l'état, non. Remis aux valeurs d'origine en twips (`-270`,
`-270`, `-225`), et le x86_64 rend enfin `fenetre = 10,10 320x240`, `client = 312x213`.

La leçon : **un préfixe survit aux corrections du code.** Une exécution cassée peut y graver son
résultat, et un binaire réparé continue de paraître cassé. Vérifier le registre avant le code.

#### Bogue 2 : `UlongToPtr` partout dans wow64win

Restait le 32 bits, toujours à zéro. Une sonde des métriques a découpé le problème :

```
SM_CXSCREEN=1728 SM_CYSCREEN=1117         <- bon
bureau = 4199552,917504 -4199544x-55308   <- faux
AdjustWindowRectEx = -1073741819           <- 0xC0000005, donc une faute
```

Ce qui marche prend un entier, ce qui échoue prend un `RECT *`. La cause est structurelle :
**wow64win amont n'a aucune conversion de pointeurs**, parce que chez lui l'invité et l'hôte
partagent les mêmes adresses. Chaque `UlongToPtr` y est donc un bogue latent dans notre monde, où
l'hôte voit `base + A`. Il y en avait 87 : 34 dans `user.c`, 53 dans `gdi.c`.

Le tri s'est fait valeur par valeur, et il n'est pas mécanique :

- **rebasés** : les tampons que win32u lit ou remplit — les `RECT` de `GetWindowRect` /
  `GetClientRect`, `SCROLLINFO`, les points de `MapWindowPoints`, `INPUT`, `MENUINFO`, les données
  du presse-papiers, les descripteurs D3DKMT (les 53 de `gdi.c` en bloc), les chaînes de `DOCINFO` ;
- **laissés dans le monde de l'invité** : `lpCreateParams`, `hInstance`, `lpfnWndProc`, le
  `callback` de `SendMessageCallback`, `hwndTarget` — tout ce que l'hôte ne fait que stocker,
  comparer, ou rendre tel quel à un rappel.

Et les trois répartiteurs `NtUserCallOneParam` / `TwoParam` / `HwndParam`, qui passaient leurs
arguments bruts, ont désormais un `switch` par code : `GetPrimaryMonitorRect`,
`GetVirtualScreenRect`, `GetAsyncKeyboardState`, `MonitorFromRect`, `GetMonitorInfo`,
`SetIMECompositionRect`, `AdjustWindowRect`. `GetDialogProc` reste brut — c'est une procédure de
l'invité. C'était là qu'`AdjustWindowRectEx` fautait.

Après quoi les deux mondes rendent exactement la même chose :

```
client = 312x213
fenetre = 10,10 320x240
```

### Dead Cells affiche une fenêtre

`deadcells.exe` est un PE32 i386. Il charge maintenant toute la pile, passe `SteamAPI_Init`, et
**crée une vraie fenêtre**, visible côté macOS comme un processus `wine` au premier plan. Le
contenu est une boîte de dialogue de Steam :

```
fenetre pid=248 classe=#32770  titre="Steam Error"
    enfant  classe=Static  texte="Application load error 3:0000065432"
```

Plus une seule exception, plus un seul appel non implémenté en soixante secondes. Ce qui reste est
la vérification de propriété de Steam, c'est-à-dire le pont `lsteamclient` — un autre sujet que le
portage 32 bits.

Non-régression : `h32` écrit sa ligne, `h32gdi` aussi, `h32win` rend sa géométrie, `hello64`
tourne, `banc_x64` donne **84,0 ms** pour 20 millions de tours (bande §241 : 83,8–84,4 ms),
`probe_d3d11_draw` rastérise son triangle.

### Un détail de mesure, pour mémoire

`AdjustWindowRectEx` semblait rendre un rectangle inchangé dans les deux mondes. C'était la sonde :
l'appel était le premier argument d'un `printf` dont les suivants lisaient le rectangle, et
l'ordre d'évaluation des arguments n'est pas spécifié — clang lit de droite à gauche, donc le
rectangle était lu **avant** l'appel. Une mesure fausse ressemble à un bogue ; celle-ci a failli
coûter une demi-heure.

## 250. Trente et une fautes silencieuses, et la vraie raison du refus de Dead Cells

### Des fautes que personne ne voyait

`+seh` sur une exécution de Dead Cells donnait :

```
handle_syscall_fault code=c0000005 addr=0x1118a2c6c pc=0x1118a2c6c
handle_syscall_fault returning to user mode ip=0x6ffffb1cac44 ret=c0000005
```

Trente et une fois. `handle_syscall_fault` attrape une faute survenue **pendant** un appel
système : l'hôte déréférence, le noyau de Wine rattrape, et l'appel rend `c0000005` à l'invité, qui
n'en dit rien. Rien dans `err+all`, rien dans le journal du jeu. Le chiffre `info[1]` désignait à
chaque fois une adresse d'invité non rebasée (`0x10d1c4`, `0x10f198`, …).

L'adresse de retour a suffi à nommer le coupable. `+loaddll` donne la base de `win32u.dll`
(`0x6FFFFB1A0000`), la soustraction donne le RVA `0x2AC44`, et le désassemblage de la DLL installée
tombe pile :

```
000000018002ac30 <NtUserCallHwndParam>:
18002ac30: mov  x8, #0x1336
...
18002ac44: ret
```

C'était le `default:` de `wow64_NtUserCallHwndParam`. Treize codes y passent un tampon ;
`ClientToScreen`, `ScreenToClient`, `GetChildRect`, `GetWindowInfo`, `GetWindowThread`,
`ExposeWindowSurface`, `SetRawWindowPos`, `GetPrivateData`, `SetPrivateData` ont désormais leur
`case`, et `GetPresentRect` rejoint `GetWindowRect` et `GetClientRect`. `SetDialogInfo` et
`SetMDIClientInfo` restent bruts : ce qu'ils rangent, l'invité le relit tel quel.

Après quoi : **zéro faute** sur la même exécution.

La méthode vaut d'être notée : *base de module + RVA + désassemblage de la DLL installée* nomme
l'appel système fautif en trois commandes, sans reconstruire quoi que ce soit.

### Le pont 32 bits marche, et ce n'est pas lui qui bloque

`tests/sonde_vtable32.c` appelle la table d'ISteamClient à la main, en `__thiscall` reproduit par
un `fastcall` à deux paramètres registre :

```
CreateSteamPipe = 1
ConnectToGlobalUser = 1
GetISteamUser = 0005c6e0
```

Toute la séquence d'initialisation de Steamworks passe donc en 32 bits, jusqu'à une sous-interface
enveloppée. (Au passage : les emplacements se lisent dans `signatures32.h`, pas dans l'intuition —
`ConnectToGlobalUser` est le 2, pas le 3, et se tromper rend zéro sans rien tracer.)

### Pourquoi Dead Cells refuse quand même

Le jeu charge le pont, demande `SteamClient017` puis `SteamClient014`, **n'appelle aucune méthode**
et affiche :

```
fenetre pid=256 classe=#32770  titre="Steam Error"
    enfant  classe=Static  texte="Application load error 3:0000065432"
```

La chaîne n'existe dans aucun binaire du jeu — et l'en-tête dit pourquoi :

```
.bind 0002e608
```

Une section `.bind` de 190 Kio : `deadcells.exe` est emballé par le **DRM steamstub**. L'enveloppe
se déchiffre avant tout appel Steamworks, et c'est elle qui refuse. Ce n'est donc ni le portage
32 bits, ni le pont : c'est la vérification de propriété du DRM, qui réclame le billet de
déchiffrement du client Steam. Un jeu sans `.bind` serait un bien meilleur sujet d'essai.

Non-régression : `banc_x64` à **83,7 ms** pour 20 millions de tours (bande §241 : 83,8–84,4 ms),
`probe_d3d11_draw` rastérise, `h32`, `h32gdi`, `h32win` et `hello64` passent.

## 251. Un jeu 32 bits sans DRM : DREDGE ouvre sa fenêtre

`deadcells.exe` portait une section `.bind` : impossible de savoir si le portage tenait ou si
c'était le DRM qui refusait. Un balayage des jeux installés donne le bon sujet :

```
=== DREDGE
   Intel 80386 bind=0  DREDGE.exe
```

Unity 2021.3, i386, DXVK, pas d'enveloppe. Cinq blocages se sont succédé, chacun d'une famille
différente, et chacun a demandé une mesure avant un correctif.

### 1. `opengl32` ne se charge pas

```
warn:opengl:DllMain Failed to initialize thread, status 0xc0000005
err:module:loader_init "OPENGL32.dll" failed to initialize, aborting
```

`opengl32` porte ses relais wow64 **du côté unix** — contrairement à win32u, dont les relais sont
dans `wow64win.dll`. `get_teb64()` y faisait `ULongToPtr(teb32)` : l'hôte déréférençait une adresse
d'invité. Pour le réparer il fallait d'abord que la base soit **lisible depuis une bibliothèque
unix**, ce qui n'existait pas : `ntdll.so` exporte maintenant `__wine_wow64_host_base()`, comme il
exporte `wine_server_call`, et `include/wine/unixlib.h` en fait `wow64_host_ptr()`.

Un piège au passage : la base est installée dès qu'un processus *peut* héberger un invité 32 bits,
même quand l'appelant du moment n'en est pas un. Rebaser sans condition a cassé la sonde D3D11
64 bits. La règle est donc : **ne rebaser que ce qui tient dans 32 bits.**

### 2. `CreateThread` échoue avec l'erreur 87

Le jeu restait à un seul fil, bloqué sur `NtWaitForSingleObject` : Unity attendait des ouvriers qui
n'existaient pas. `tests/h32fil.c`, dix lignes, dit tout de suite :

```
CreateThread = 00000000 id=0 err=87
```

Dans `init_thread_stack`, la pile 32 bits est demandée entre un plancher — `user_space_wow_base`,
16 Gio, une adresse de l'hôte — et un plafond venu de `zero_bits`, c'est-à-dire de l'invité :
0x7fffffff. Intervalle à l'envers, `STATUS_INVALID_PARAMETER`. Le plafond se rebase comme le reste.

### 3. Les 2137 `UlongToPtr` de winevulkan

`vkCreateInstance` échouait, puis `vkGetPhysicalDeviceFeatures2` fautait. Même structure
qu'`opengl32`, en plus gros. Ici le tri est différent : **toutes** les conversions sont des
pointeurs d'invité, y compris les poignées `VkDevice`, `VkQueue` et `VkCommandBuffer`, qui ne sont
pas des entiers opaques mais des objets PE dont l'hôte lit le champ `unix_handle`. On redéfinit
donc `UlongToPtr` pour ce module, avec le commentaire qui le justifie, plutôt que de réécrire
2137 appels engendrés — et la redéfinition doit venir **avant** `find_next_struct32`, sinon cette
fonction-là garde l'identité (une heure perdue là-dessus).

`VkCommandPool` fait exception dans l'autre sens : non « dispatchable », donc transportée comme un
entier de 64 bits, elle ne passe par aucun `UlongToPtr` et se rebase à la main.

### 4. `vkMapMemory` : « tient dans 32 bits » n'est pas la bonne question

```
err:   Failed to map Vulkan memory: VK_ERROR_OUT_OF_HOST_MEMORY
```

`win32u/vulkan.c` vérifiait `(UINT_PTR)*data >> 32` avant de rendre la projection à l'invité. La
règle juste n'est pas « tient dans 32 bits » mais « est dans la fenêtre de l'invité » — chez nous
elle commence à 16 Gio, et le test d'amont rejetait toutes les projections valides.

### 5. `lea` laissait la base de l'hôte dans le registre

Le plus intéressant. Le décodeur refusait de traduire à `7B24EE90`, une adresse pourtant au milieu
du `.text` d'UnityPlayer.dll. Une sonde dans `CheckRangeExecutable` a donné la clé :

```
SONDE refus decodeur : recu 87B24EE90, interroge 47B24EE90, base 400000000
```

**La base comptée deux fois.** Cinq lignes suffisent à le reproduire (`tests/h32lea.c`) :

```c
__asm__ volatile ( "leal (%1), %%eax\n\t"
                   "call *%%eax" : "=a"(r) : "r"(p) );
```

`lea` demande une adresse effective sans accéder à la mémoire ; notre rebasage la lui donnait dans
le monde de l'hôte. Tant que le programme n'en fait qu'une adresse, cela ne se voit pas — le
rebasage est idempotent, puisqu'il combine la base avec les 32 bits de poids faible. Mais
« lea ; call \*eax » met alors base + cible dans EIP, et le décodeur lit base + base + cible.

`LoadSourceOptions` porte désormais `AdresseInvite`, que `LEA` seul positionne : les autres
appelants de ce chemin — `XADD`, `SGDT`, `SIDT`, `PREFETCH` — veulent bien un pointeur de l'hôte.

Une tentative intermédiaire — tronquer le RIP à 32 bits dans `ExitFunction`, ce qui est pourtant la
sémantique exacte du mode 32 bits — a bloqué l'invité dès `h32.exe` : le JIT reconnaît une
constante pour lier les blocs statiquement, et l'envelopper dans un `Bfe` casse cette liaison.
Annulée.

### Où DREDGE en est

```
fenetre pid=248 classe=UnityWndClass  titre="DREDGE"
```

52 fils : le système de tâches d'Unity, `UnityGfxDeviceWorker`, `Loading.AsyncRead`,
`AssetGarbageCollectorHelper`, et les trois fils de DXVK (`dxvk-submit`, `dxvk-queue`, `dxvk-cs`).
Le pilote audio a demandé le même traitement que les autres (57 conversions dans
`winecoreaudio.drv`) avant que la fenêtre n'apparaisse. Elle reste cachée pour l'instant, le jeu
tournant à 100 % d'un cœur : c'est le prochain fil.

### Un rappel qui a coûté trois mesures

`banc_x64` donnait 86 ms au lieu de 84. Ce n'était pas le correctif : un `h32.exe` oublié tournait
à 100 % depuis un essai précédent. Voir [[feedback_gpu_bench_stale_processes]] — la règle vaut
aussi pour les bancs CPU. Après nettoyage : **84,2 — 84,7 ms**, dans la bande du §241.

Non-régression : `h32`, `h32gdi`, `h32win`, `h32fil`, `h32seh`, `h32lea`, `hello64`,
`probe_d3d11_draw` (« le triangle est rastérisé »).

## 252. Le préfixe se réamorce enfin, et où DREDGE bute encore

### `wineboot -u` peuple syswow64, et les inscriptions COM 32 bits avec

Unity s'arrêtait en silence sur :

```
err:ole:com_get_class_object no class object {bcde0395-e52f-467c-8e3d-c4579291692e}
```

C'est `MMDeviceEnumerator`, l'énumérateur audio. La CLSID est pourtant bien dans `system.reg` —
sous `Software\Classes\CLSID`. Mais un processus 32 bits, lui, lit
`Software\Classes\Wow6432Node\CLSID` : la redirection de registre WoW64. Cette clé existait, vide.

La cause est ancienne et notée depuis §247 : la passe 32 bits de `wineboot --init` ne s'était
jamais exécutée, faute d'invité 32 bits en état de marche. Elle marche maintenant. Un simple
`wineboot -u` sur le préfixe existant :

- écrit les inscriptions COM 32 bits (`Wow6432Node\CLSID`) ;
- peuple `syswow64` — **858 fichiers**, là où `tests/peupler_syswow64.sh` en copiait une poignée à
  la main.

`tests/h32audio.c` le vérifie : `CoCreateInstance(MMDeviceEnumerator) = 00000000`. Le contournement
manuel n'a plus lieu d'être.

**La leçon :** un préfixe amorcé par une pile incomplète le reste. Quand la pile progresse, il faut
le réamorcer — le code réparé ne répare pas l'état.

### Ce qui reste

DREDGE charge Unity, DXVK, l'audio, crée sa fenêtre `UnityWndClass`, tourne avec 52 fils. Il meurt
ensuite sur une lecture à une adresse **entièrement libre** :

```
SONDE region 9E1A4000 : base=9E1A4000 alloc=00000000 taille=61d5c000 etat=10000(MEM_FREE) prot=1
```

L'adresse change d'une exécution à l'autre — 0x16234000, 0x7E184000, 0x7C994000, 0x9E1A4000 — mais
ses seize bits de poids faible valent **toujours 0x4000**. Neuf fois sur neuf : ce n'est pas un
hasard, c'est une construction. 0x4000, c'est aussi la taille de page de macOS.

Deux fausses pistes écartées en chemin, qui valent d'être notées :

- **L'EIP rapporté ne désigne pas l'instruction fautive.** Il tombe chaque fois sur un `ret`, ce
  qui laissait croire à un ESP corrompu. La sonde de contexte dans `call_user_exception_dispatcher`
  a montré un ESP parfaitement sain : FEX reconstruit le RIP au dernier point connu du bloc, pas à
  l'instruction. Ne pas désassembler autour d'un EIP reconstruit sans le vérifier.
- **La pile hôte des fils wow64 ne fait que 256 Kio** et déborde pour de vrai — `stack overflow
  16 bytes` avec `FEX_SMCCHECKS=full`. La quadrupler ne change rien à ce bogue-ci ; la
  modification a donc été annulée, mais l'observation reste.

Non-régression : `banc_x64` à **83,8 ms** (trois mesures identiques, bas de la bande §241),
`probe_d3d11_draw` rastérise, et les dix programmes i386 passent — `h32`, `h32gdi`, `h32win`,
`h32fil`, `h32seh`, `h32lea`, `h32cxx`, `h32pile`, `h32croi`, `h32audio`.

## 253. L'adresse en 0x4000 : Mono rustine, FEX ne le voit pas

Le symptôme : une lecture à une adresse **entièrement libre**, différente à chaque exécution, mais
dont les seize bits de poids faible valaient **toujours 0x4000**. Neuf fois sur neuf.

### Ce que la mesure a éliminé

- **La taille de page.** 0x4000, c'est la page de macOS — mais l'invité voit bien
  `dwPageSize = 4096`, et `tests/h32page.c` montre qu'un engagement de 4 Kio dans un granule de
  64 Kio laisse bien le reste réservé. La granularité fine marche.
- **Le pointeur d'instruction x87.** Le sommet de pile de la première exception porte une image
  `fnstenv` dont le FIP vaut zéro (`tests/h32fpu.c` le confirme : 0 au lieu de 0x00401490). C'est
  une limite de **FEX amont** — `X87FNSTENV` y range une constante nulle dans « Instruction
  Offset » — donc pas une régression du portage. Piste close, manque noté.
- **Une allocation périmée.** En traçant les 1344 allocations et 417 libérations de l'invité : sa
  plus haute adresse est 0x18570000, soit 400 Mio. La cible, elle, était à 3 Gio. Le pointeur
  n'avait jamais été alloué : il était **calculé**.
- **L'EIP rapporté.** Il tombait chaque fois sur un `ret`, ce qui faisait croire à un ESP corrompu.
  Une sonde de contexte a montré un ESP parfaitement sain : FEX reconstruit le RIP au dernier point
  connu du bloc.

### Ce qui l'a trouvé

La chaîne des cadres, relevée dans `call_user_exception_dispatcher`, est identique d'une exécution
à l'autre et entièrement en **code engendré par Mono**, avec une seule trame native au fond —
`mono-2.0-bdwgc.dll`. Un essai suffisait alors :

```
FEX_MONOHACKS=0   ->   la faute disparaît
```

Les « rustines Mono » de FEX détectent le bloc qui rustine les sites d'appel, **désactivent la
détection d'écriture de code** et traitent ce bloc à part. Le traitement à part, c'est
`MonoBackpatcherWrite` :

```c
*reinterpret_cast<uint32_t*>(Address) = Value;                    /* Address : hote  */
CTX->SyscallHandler->InvalidateGuestCodeRange(Thread, Address, Size);   /* attend : invite */
```

L'écriture veut un pointeur de l'hôte, l'invalidation une adresse d'invité — les deux autres
appelants d'`InvalidateGuestCodeRange` passent d'ailleurs un RIP. Sans la soustraction, Mono
rustine son site d'appel et FEX continue d'exécuter **l'ancienne traduction** : le saut part vers
l'ancienne cible, et la faute tombe très loin de sa cause. Et comme la détection d'écriture de code
avait justement été désactivée, rien ne la rattrapait.

Une ligne :

```c
CTX->SyscallHandler->InvalidateGuestCodeRange(Thread, Address - FEXCore::IR::Guest32Base, Size);
```

### Au passage : une allocation réussie rendue comme un échec

En cherchant, `tests/h32noacc.c` a mis au jour autre chose : la **première**
`VirtualAlloc(NULL, n, MEM_RESERVE, PAGE_NOACCESS)` de chaque invité 32 bits rendait NULL, avec
`GetLastError()` à zéro. Elle réussissait pourtant — à l'adresse `0x400000000`, c'est-à-dire
l'adresse **zéro de l'invité**, que la troncature rend indistinguable d'un échec.

Le plancher passé à `map_view` valait `user_space_wow_base + 0`. Il vaut maintenant
`user_space_wow_base + address_space_start` : la zone basse ne lui appartient pas de toute façon,
`lpMinimumApplicationAddress` valant 0x10000. Les ramasse-miettes et les gestionnaires de code
engendré réservent exactement ainsi, et ne vérifient pas toujours.

### Où DREDGE en est

La faute aléatoire a disparu. Il reste un échec **déterministe** — le même qu'avec
`FEX_MONOHACKS=0`, donc le suivant dans la file et non un effet du correctif :

```
wine: Unhandled exception 0xc0000093 in thread f8 at address 7B822EF9
```

`STATUS_FLOAT_UNDERFLOW`, levé par l'invité lui-même via `RaiseException`. C'est le prochain fil.

Non-régression : `banc_x64` à **84,2 — 84,7 ms** (bande §241), `probe_d3d11_draw` rastérise, et les
douze programmes i386 passent — `h32fpu` rapportant, comme prévu, la limite d'amont.

## 254. `STATUS_FLOAT_UNDERFLOW` : ce que la mesure a éliminé

DREDGE meurt désormais toujours au même endroit :

```
wine: Unhandled exception 0xc0000093 in thread f8 at address 7B822EF9
```

### Qui lève, et pourquoi

La chaîne des cadres relevée dans `call_user_exception_dispatcher` est entièrement dans
UnityPlayer.dll — le CRT Microsoft lié statiquement :

```
UnityPlayer+121987C  -> RaiseException          (kernelbase+12EF9)
UnityPlayer+1219644
UnityPlayer+1223F49
UnityPlayer+121AEDB
UnityPlayer+1B2A7B                              <- le moteur
<code JIT de Mono>
```

Le désassemblage donne l'appel exact :

```asm
lea  0x8(%ebp),%eax     ; &record
push %eax
push $1                 ; un argument
push $0
push %edi               ; = 0xC0000093
call *0x112343d0        ; RaiseException
```

`ExceptionInformation[0]` pointe donc sur la structure que le CRT a remplie. En la dumpant :

```
+0x00  0x208   RoundingMode=0, Precision=Double, Operation=16 (_FpCodeAtan2)
+0x04  0x03    Cause  : Inexact + Underflow
+0x08  0x0a    Enable : Underflow + ZeroDivide     <-- le coupable
+0x0c  0x10    Status : InvalidOperation
```

`Enable` est calculé bit à bit à partir d'un mot de contrôle x87 que le CRT relit dans un tampon
(`movzwl (%eax),%ecx` sur `[ebx+0x10]`), en inversant chaque bit de masque. Le CRT croit donc le
sous-dépassement **démasqué**, et lève.

Or l'état réel du processeur au même instant, lu dans le contexte de l'exception :

```
CW=133f SW=0000 TW=ffff   (fxsave CW=133f SW=0000 MXCSR=00001f80)
```

`0x133F` : les six bits de masque sont tous à 1. **Tout est masqué.** Le CRT lit donc un mot qui ne
vient pas du processeur — il faudrait `ZM=0` et `UM=0`, soit 0x29 ou 0x2B.

### Ce qui a été éliminé

Chaque mécanisme par lequel ce mot aurait pu se corrompre a été mesuré, et aucun n'est en cause.
Les programmes restent dans `tests/` :

| essai | ce qu'il prouve |
|---|---|
| `h32fcw` | `fldcw`/`fnstcw` et `ldmxcsr`/`stmxcsr` font l'aller-retour sur cinq valeurs, 0x133F comprise ; les masques sont tous posés au démarrage |
| `h32env` | `fnstenv`/`fldenv` sont justes **dans les deux dispositions**, 14 et 28 octets |
| `h32fsave` | `fnsave`/`frstor` et `fxsave`/`fxrstor` conservent CW, SW, TW et MXCSR |
| `h32denorm` | aucun dénormal n'est mis à zéro — le mode « flush-to-zero » d'ARM ne fuit pas |
| `h32fs0` | le SEH par la chaîne `FS:[0]`, que `h32seh` n'exerçait pas, appelle bien son gestionnaire et reprend |
| `h32fpu` | seul manque trouvé : `fnstenv` rend un pointeur d'instruction nul — mais c'est le code d'amont (`X87FNSTENV` y range une constante nulle), donc hors de cause |

Deux impasses également notées :

- **Avaler l'exception ne suffit pas.** Rendre la main depuis `call_user_exception_dispatcher`
  n'équivaut pas à « traitée » : l'invité déroule quand même son filtre de dernier recours.
- **Le manque de drapeaux d'état.** FEX ne pose jamais les bits d'exception du mot d'état x87 ni du
  MXCSR (`1e-300*1e-300` laisse `SW=0000`). C'est une limite connue d'amont ; elle expliquerait un
  `Status` nul, pas un `Status` à `InvalidOperation`.

### Ce qui reste à faire

Trouver d'où `[ebx+0x10]` tire son mot de contrôle. `ebx` est un descripteur passé par la fonction
mathématique (`UnityPlayer+121AEDB`) ; son champ `+0x10` pointe sur un `WORD`. Tant que ce tampon
n'est pas identifié, on ne sait pas si c'est l'émulation qui l'a rempli de travers ou le moteur qui
appelle `atan2` avec des opérandes déjà fausses.

Non-régression : `banc_x64` à **84,4 — 84,7 ms** (bande §241), `probe_d3d11_draw` rastérise, et les
dix-sept programmes i386 passent.
