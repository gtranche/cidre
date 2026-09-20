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
