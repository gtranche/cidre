# Intégration de la pile Diablo IV dans Cidre

Branche `d4-integration`, partie de main `3dd43cf` (11/11/2026). Rien n'a été poussé ni fusionné.
Aucun jeu, ni Battle.net, n'a été lancé pour ce travail. Les dossiers du joueur (`partie_combo.sh`, `rt-0463`,
les DLL et dylibs `cidre-d4-*`, les caches, les préfixes) ont seulement été lus.

## 1. Ce qui fait tourner D4 aujourd'hui

`~/Dev/cidre-d4-combo/scripts/partie_combo.sh` :

1. Il pose ses variables (`D4J_ENV`), puis il lance `~/Dev/cidre-ralent/scripts/partie_d4_ralent.sh`.
2. `partie_d4_ralent.sh` fait les vérifications de départ :
   - il refuse si un jeu ou un wineserver tourne, si `m1.verrou` est posé, ou s'il reste moins de 5 Go libres ;
   - il copie la DLL FEX dans `system32` du préfixe `~/Dev/cidre-d4-jumelles/pfx-d4-jumelles`.
3. Il lance ensuite `Battle.net.exe --in-process-gpu --lang=frFR "--exec=launch Fen"` avec le runtime `rt-0463`.
4. Il redemande `--exec=launch Fen` à 150 s puis à 300 s si le jeu n'est pas apparu.
5. Il échantillonne les fils et attend que le client et le jeu sortent.
6. À la fin, `partie_combo.sh` produit ses tableaux de mesure (`fenetres.py`, `mesure.py`).

### Pièces réellement utilisées

| Pièce | Fichier du joueur | sha1 |
|---|---|---|
| Runtime Wine | `~/Dev/cidre-d4-suspfex/rt-0463/wine11-arm64` | ntdll.so `3bea746d`, win32u.so `30d2d824`, ntdll.dll `3e1578d8` |
| FEX (xtajit64) | `~/Dev/cidre-d4-fexdisque/obj/xtajit64-fexdisque-0493.dll` | `e4e55ddd` |
| KosmicKrisp | `~/Dev/cidre-d4-kkcompil/kk/kk-0494.dylib` (ICD `kk-0494_icd.json`) | `d5a4d337`, `KK_CODEGEN=1-fe23de315cfc449d` |
| vkd3d-proton | `system32` du préfixe : d3d12.dll / d3d12core.dll | `892cee29` / `b4780078` = `build/vkd3d-winarm64ec` du dépôt principal |
| dxgi | `system32` du préfixe | `d990ad3b` = DXVK async (`build/dxvk-async-winarm64ec`) |
| Chargeur Vulkan | `DYLD_LIBRARY_PATH=~/Dev/proton-ouvert/wine/vklib-arm64:~/Dev/proton-ouvert/prefix/lib` | celui du dépôt principal |

## 2. Inventaire et classement

Il y a trois catégories :
- **main** : déjà dans main ;
- **porté** : absent de main, ajouté à la série par cette branche ;
- **non repris** : instrumentation.

### 2.1 Runtime Wine `rt-0463`

`rt-0463` est un clone de `~/Dev/cidre-fex-banc/d4-rt`, avec un seul fichier remplacé : `ntdll.so`. `d4-rt` est lui-même un clone de `ilotr-rt` (le runtime de l'îlot jouable de D2R) auquel s'ajoutent les 5 DLL PE « 0309 ». Les 85 fichiers qui diffèrent du runtime du dépôt principal se répartissent en trois groupes :
- copies de garde `.avant-*` ;
- versions de série antérieures ;
- modules propres à l'îlot.

| Élément | Source chez le joueur | Catégorie | Dans la branche |
|---|---|---|---|
| Base Wine 11 (série jusqu'à 0396) | build 1.5.19 + modules posés (0381…) | main | série wine11 de main |
| Îlot TSO : `unix/ilot.c`, garde des régions, `virtual.c` jumelles v2, `signal_arm64.c`, `sync.c`, `server.c`, `env.c` | `cidre-fex-banc/ilot-port/unix` (dossier « îlot par défaut », 0290) | porté | **0290** (inchangé, s'applique sans flou) |
| Appels servis dans la boucle de l'îlot | idem (0291) | porté | **0291** |
| ntdll.so relié à Hypervisor.framework, `unix/ilot.c` compilé avec ntdll | relié à la main (`construire.sh`, objets 1.5.19) | porté | **0293** (nouveau : Makefile.in + `#pragma makedep unix`) |
| Mémoire Vulkan de l'hôte en mémoire Windows (win32u) | `cidre-fex-tso/vk13/win32u/vulkan.c` | porté | **0294** |
| ntdll PE de l'îlot (horloge, liste inter-processus, string.c, exception.c) | `cidre-fex-tso/d2r/pe19` | porté | dans **0290** |
| Cession sans sortie 3 fois sur 4 (ntdll PE) | `wine-restes/ilot/avant308_signal_arm64ec.c` | porté | **0301** |
| Suspension pendant une sortie vers l'hôte | `cidre-d2r-gel/correctifs/0355` | porté | **0355** |
| Verrou de l'îlot, signaux bloqués | `cidre-d4-verrous` (0462) | porté | **0462** |
| Suspension au seuil d'un appel hôte | `cidre-d4-suspfex` (0463) | porté | **0463** |
| Journal de mort des fils `[CIDRE_MORT]` (`CIDRE_MORT_FILS`, actif par défaut chez le joueur) | `cidre-d4-jumelles/ntdll-mort` | non repris | absent (0462 et 0463 s'appliquent sans lui) |
| Page nulle sans mutex (0312), heure sans sortie (0311) | dossier « îlot par défaut » | non utilisés par D4 | absents (`rt-0463` ne les a pas) |
| 5 DLL PE sans `ldp q` (ntdll, kernelbase, kernel32, ucrtbase, msvcrt), thunks d'entrée recousus, assemblés en cible MSVC (0309) | `cidre-fex-banc/wine-restes/pe/*-thk-309.dll`, outil `construire_pe_sans_ldp.py` | porté (outil) | `outils/construire_pe_sans_ldp.py`, `outils/thunks_sans_ldpq.py`, `construire_pile_d4.sh pe` |
| Chargeurs `bin/wine` et `lib/wine/aarch64-unix/wine` signés `com.apple.security.hypervisor` | signés à la main | porté | `tests/ilot.sh preparer` (branche `ilot-option`, reprise) |
| winemac 0241 (démarrage Cocoa) | posé | main | série |

### 2.2 FEX `xtajit64-fexdisque-0493` (e4e55ddd)

La lignée a été vérifiée arbre par arbre. Chaque étape est reproduite exactement par son correctif, à l'exception des deux écarts expliqués plus bas.

| Étape | Arbre | Catégorie | Dans la branche |
|---|---|---|---|
| Série FEX de main (0070-0313) | — | main | série, avec **0310** en plus (voir les écarts) |
| Partie FEX de l'îlot : lectures groupées, barrières, jumelles v2, tampon 128 Mio, compteurs | `cidre-fex-banc/fex-ilotr` (0292b) | porté | **0292** |
| Pages validées réarmées | `cidre-d2r-gel/fex` (0360) | porté | **0360** |
| Diagnostic « validation par page » (`CIDRE_DIAG_VALIDATION`) | idem (0361) | non repris | absent |
| Jumelles v3e : horloge CNTVCT, verrou groupé, diag des invalidations | `cidre-d4-jumelles/fex` | porté | **0365** |
| Cache disque de blocs v9 (`CIDRE_FEX_DISQUE`) | `cidre-d4-fexcache/fex` | porté | **0366** |
| SMC en ligne sur page chaude (`CIDRE_SMC_EN_LIGNE_CHAUD`) | `cidre-ralent/fex` (0370) | porté | **0370** |
| Décalage TSD du TEB recalé au service | `cidre-d4-cache-tsd` | porté | **0452** |
| Journal des exceptions coupé | `cidre-d4-combo` | porté | **0460** |
| Cache disque 0475-0491, 0493 (dont rpmalloc 0488/0489 dans `External/rpmalloc`) | `cidre-d4-fexdisque` | porté | **0475 à 0491, 0493** |

Le code de mesure intégré aux correctifs (compteurs « cidre compil/disque », `CidreDiagInval.h`) est gardé tel quel. Il est inactif par défaut et entremêlé au code fonctionnel.

### 2.3 KosmicKrisp `kk-0494` (d5a4d337)

Lignée : `cidre-d4-compil` → `-zone` → `-fond` → `cidre-pipeline-froid` (= kk-I4f) → `cidre-acoups` → `cidre-bind-prise` → `cidre-vblank` → `cidre-d4-variantes` → `cidre-d4-kkcompil/mesa` → `mesa-0494`.

Tous les arbres partent de la série de main (0410 et 0412 compris).

| Correctif | Rôle | Catégorie |
|---|---|---|
| 0402 | txf sur poignée nulle garde la sélection | porté |
| 0430-0434 | cache disque des nuanceurs, frontal différé, dessins sautés, pipelines paresseux v2, barrière de repli `u_thread` | porté |
| 0440 | AIR direct : contournement 17 (NaN) | porté |
| 0441, 0443, 0444 | file de fond et liste chaude, rafales, base de pipelines et rejeu | porté |
| 0450-0451 | profil du pipeline froid et cache de fonctions Metal (un seul fichier, comme dans le chantier) | porté |
| 0461 | `CIDRE_WSI_CADENCE` | porté **sans** l'histogramme `[CIDRE_FEN]` |
| `CIDRE_FENETRE` (kk_queue.c, wsi) | lignes `[CIDRE_FEN]` par seconde | non repris |
| 0464 | le bind prend le travail en file ; `KK_CODEGEN_FIGE` | porté |
| 0470 | `CIDRE_WSI_ATTENTE_PRESENT=gpu` | porté |
| 0471-0474 | variantes notées, archive au rejeu, banc, réserve à priorités | porté |
| 0492, 0494 | froids en fond (**coupé par défaut** depuis le 12/11 : `CIDRE_FOND_FROIDS=1` pour l'activer), relais économe | porté |

Le 0434 a été renommé `0434-kosmickrisp-util-…` : la série Mesa ne prend que les fichiers `kosmickrisp-*`.

### 2.4 Variables d'environnement de `partie_combo.sh` et `partie_d4_ralent.sh`

| Variable (valeur du joueur) | Catégorie | Dans le produit (branche) |
|---|---|---|
| `CIDRE_ILOT=1`, `CIDRE_ILOT_EXE="Diablo IV.exe"`, `CIDRE_ILOT_UNIQUE=1`, `CIDRE_ILOT_VUES_PARTAGEES=copie`, `CIDRE_SMC_ARME=1`, `CIDRE_SOUS_PAGES_EN_LIGNE=0`, `CIDRE_DIAG_SOUS_PAGES=0` | main (lanceur `ilot-option`) | `tests/ilot.sh env` (fiche `ilot = true`) |
| `CIDRE_ILOT_XPROC=1`, `CIDRE_SMC_REARMER=1` | porté | ajoutés à `ilot.sh env` (une valeur posée garde la main) |
| `FEX_HOSTFEATURES=enablecrypto` | porté | `ilot.sh env` (`CIDRE_ILOT_FEX_HOSTFEATURES` pour en changer ; hors îlot, `extensions_fex.sh` donne aussi flagm/flagm2) |
| `FEX_TSOENABLED=0` (tous les processus) | adapté | AppConfig `TSOEnabled 0` pour **l'exe du jeu seul** (`lancer_depuis_steam.sh`, ilot-option) ; le client garde le TSO |
| AppConfig `MaxInst 500` (préfixe du joueur) | main | fiche `fex_maxinst = 500` |
| `CIDRE_COMPILE_HORS_VERROU=1`, `MESA_KK_EXPERIMENTAL=image_view_min_lod,fl12`, `CIDRE_MINMAX_ZERO_ENTIER=1`, `CIDRE_TEXTURES_NULLES_SANS_BRANCHE=1`, `CIDRE_VKD3D_DENORMAUX_LIBRES=1`, `CIDRE_DERIVEES_CALCUL=1`, `CIDRE_ATOMIQUES_64=1`, `CIDRE_DEMI_PRECISION=1`, `CIDRE_VISIB=2`, `CIDRE_RESOLVE_GROUPE=4`, `CIDRE_FILES=4`, `CIDRE_AIR_DIRECT=1` | main | défauts du lanceur pour `dx12` et `sm66` (fiche) |
| `CIDRE_HORODATAGES_CPU=1`, `CIDRE_SANS_ATTACHEMENT_BORNE=1`, `CIDRE_CBV_SANS_BORNES=1`, `CIDRE_FUSION_SOUMISSION=1` | main (options) | fiche `code_kk` |
| `CIDRE_COMPILE_DIFFEREE=8` | porté | fiche `compile_differee = 8` (nombre de fils accepté par le lanceur) |
| `CIDRE_CACHE_DISQUE=1`, `CIDRE_FRONTAL_DIFFERE=1`, `CIDRE_PIPELINE_PARESSEUX=1`, `CIDRE_CACHE_FONCTIONS=1`, `CIDRE_COMPILE_FOND=4`, `CIDRE_BASE_PIPELINES=<dossier>`, `CIDRE_LISTE_CHAUDE=<fichier>` | porté | fiche `compilation_kk` (liste chaude et base sous le cache de pipelines du jeu) |
| (variantes notées, actives par défaut dans le pilote) | porté | `compilation_kk … variantes` ; le lanceur pose `CIDRE_VARIANTES=0` aux autres jeux |
| `CIDRE_WSI_ATTENTE_PRESENT=gpu` | porté | fiche `attente_present = "gpu"` |
| `CIDRE_WSI_CADENCE` (seulement avec un argument) | porté | fiche `cadence` (non posée pour D4) |
| `CIDRE_FEX_DISQUE=1`, `_MO=256`, `_VALIDES=1`, `_CLE_BRUTE=0`, `_MAX_MO=0`, `CIDRE_ARME_RAPIDE=0` | porté | fiche `fex_disque = true` |
| `CIDRE_SMC_EN_LIGNE_CHAUD=64` | porté | fiche `fex_smc_chaud = 64` |
| `VK_DRIVER_FILES=<ICD kk-0494>`, `DYLD_LIBRARY_PATH=…` | main | KosmicKrisp et chargeur du runtime |
| `MESA_KK_PIPELINE_CACHE=…/cache-kk-d4-13-PFR`, `MESA_KK_AIR_LOCAL=…/air-local-d4-13-PFR` | main | caches par jeu du lanceur (`vkd3d-cache/bnet-fen`, `precompil_kk.sh air_local`) |
| `WINEDLLOVERRIDES=mscoree,mshtml=;dxgi,d3d11=n;d3d12,d3d12core=n;winedbg.exe=d` | main, sauf `winedbg.exe=d` | `etape2_pile_arm64ec.sh` ; winedbg n'est pas coupé (écart mineur) |
| `QT_QUICK_BACKEND=software`, `QT_OPENGL=software`, `--in-process-gpu`, `--exec=launch Fen`, relances à 150 s et 400 s, `--lang` | main | `tests/battlenet.sh` (langue du Mac) |
| `CIDRE_MAJ_AVANT_LANCEMENT=0`, `MTL_HUD_ENABLED=0` | main | défauts |
| `CIDRE_FENETRE=1`, `CIDRE_GPU_STATS=1`, `CIDRE_GPU_STATS_WINDOW=1/120`, `CIDRE_WSI_TRACE=1`, `CIDRE_WSI_STATS=1`, `MESA_KK_COMPILE_STATS=1`, `CIDRE_ILOT_CHRONO=1`, `CIDRE_ILOT_BLOQUES=5`, `FEX_SILENTLOG=0`, `WINEDEBUG=-all,+loaddll,err+all` | non repris | journal détaillé seulement (`CIDRE_ILOT_JOURNAL=1` remet CHRONO et BLOQUES) |
| Guetteur `guette_gel.py`, échantillonneur `ps -M` (`D4J_CPU`), `fenetres.py`, `mesure.py`, copie de `FenrisDebug.txt`, verrou `m1.verrou`, `D4J_DUREE` | non repris | — |

### 2.5 Îlot, Battle.net, caches

- **Îlot.** La branche `ilot-option` a été reprise : `73e2347` + `fa4ae49`, jamais fusionnés ; `73e2347` avait été annulé sur main par `4e44498`. Elle apporte l'option de fiche `ilot`, `tests/ilot.sh`, l'alignement du préfixe et l'AppConfig TSO. Avec la série D4, le runtime de Cidre porte lui-même l'îlot, inactif sans `CIDRE_ILOT=1`. Le runtime de l'îlot en est un clone APFS auquel s'ajoutent :
  - les 5 DLL PE sans `ldp q` ;
  - les chargeurs re-signés.

  `xtajit.dll`, le FEX 32 bits du client Battle.net, n'est plus jamais aligné.
- **Battle.net.** C'est le chemin de `cidre play bnet-fen` (main + `ilot-option`). Le préfixe est `pfx-battlenet`, et non le clone `pfx-d4-jumelles` du joueur.
- **Caches du joueur** : à migrer à part, voir le § 6.
  - `cache-kk-d4-13-PFR` (1,7 Go) : pipelines, traduction et archives Metal ; il contient aussi `variantes-kk.bin` et `liste-chaude-kk.bin` ;
  - `air-local-d4-13-PFR` (355 Mo) ;
  - `cidre-d4-fond/base-d4` (187 Mo) ;
  - `cidre-d4-fond/liste/liste-chaude-d4.bin` ;
  - le cache disque FEX, dans le préfixe.

  Ils restent valables avec le pilote de la branche, parce que la clé `KK_CODEGEN` est la même (§ 4).

## 3. Portage : ce qui a changé dans le dépôt

- **53 correctifs** à la racine, régénérés contre la série de main. Chacun s'applique sans flou dans l'ordre de `tests/series.sh`, avec un en-tête au format de la série :
  - wine11 : 0290, 0291, 0293, 0294, 0301, 0355, 0462, 0463 ;
  - FEX : 0292, 0360, 0365, 0366, 0370, 0452, 0460, 0475 à 0491, 0493 ;
  - KosmicKrisp : 0402, 0430-0434, 0440, 0441, 0443, 0444, 0450, 0461, 0464, 0470-0474, 0492, 0494.
- `tests/series.sh` et les témoins FEX d'`etape1_appliquer_correctifs.sh` (25 nouveaux).
- `tests/construire_pile_d4.sh` :
  - `kk`, `fex`, `wine` ;
  - `pe` (DLL sans `ldp q`) ;
  - `ilot` (artefacts `wine/ilot`) ;
  - `marqueurs`.
- `outils/construire_pe_sans_ldp.py` et `outils/thunks_sans_ldpq.py` : outils 0309, sans chemins en dur, sources pe19 désormais dans la série.
- `tests/cle_kk_figee.sh` fige la clé de code de KK, puis vérifie après la construction que les sources hachées sont bien celles de kk-0494. `construire_pile_arm64.sh` s'en sert aussi.
- `tests/lancer_depuis_steam.sh` : options `compilation_kk`, `attente_present`, `cadence`, `compile_differee` (nombre de fils), `fex_disque` et `fex_smc_chaud`.
- `tests/ilot.sh` :
  - les artefacts sont les 5 DLL PE ;
  - `env` reprend XPROC, REARMER et les extensions FEX des parties.
- Fiche `profils/bnet-fen.toml` : réglages de `partie_combo.sh`, sans l'instrumentation. Index régénéré.
- Tous les réglages expérimentaux restent coupables par variable :
  - par l'option de fiche ;
  - par `CIDRE_<option>=0` ;
  - par leurs propres interrupteurs (`CIDRE_RELAIS_ECONOME=0`, `CIDRE_FEX_REEMPLOI=0`, `CIDRE_BIND_PRISE=0`, `CIDRE_JOURNAL_EXCEPTIONS=1`, `CIDRE_ILOT_VULKAN_HOTE=0`, `CIDRE_JOUER_ILOT=0`…).

## 4. Reconstruction depuis la branche, et preuve

Tout a été construit dans le worktree : `build/`, `wine/` et `third_party/FEX/build-ec`. Les sources amont sont des clones APFS des dépôts du checkout principal, remis aux révisions d'`etape1` puis patchés par `series.sh`.

### Sources

Les arbres patchés ont été comparés aux arbres du joueur. Ils sont identiques, à ces écarts près :

| Arbre | Écarts |
|---|---|
| KK | `CIDRE_FENETRE` seulement (kk_queue.c, wsi_common_metal.c) |
| FEX | 0310 en plus, 0361 en moins |
| ntdll unix | journal de mort des fils, plus les 5 lignes `#pragma makedep unix` ajoutées en tête d'`ilot.c` par 0293 |
| ntdll PE | pe19 + 0301 = `avant308_signal_arm64ec.c`, la source exacte du ntdll.dll du joueur |
| win32u | vk13 à l'identique |

### Binaires

| Pièce | Joueur | Branche | Constat |
|---|---|---|---|
| KosmicKrisp | `d5a4d337` | `54300f2d` | `KK_CODEGEN=1-fe23de315cfc449d` dans les deux ; empreinte **calculée** des sources hachées identique (`1fbdc554…`) ; chaînes : seuls diffèrent les chemins de build et les deux chaînes `[CIDRE_FEN]` + `CIDRE_FENETRE` (non reprises) |
| xtajit64 (FEX) | `e4e55ddd` | `dfc575e9` | même taille à l'octet (5 722 112) ; chaînes Cidre : 561 communes ; joueur seul : 3 chaînes du diag 0361 ; branche seule : 3 chaînes de 0310 (`CIDRE_KUSER_FEX`) |
| ntdll.so | `3bea746d` | `2952679f` | chaînes identiques (dont la version « ilot19 verrous-0462 seuil-0463 … ») sauf les 11 du journal `[CIDRE_MORT]` et la date de build |
| ntdll.dll de l'îlot | `3e1578d8` | `5878908c` | 132 `ldp q` dans les deux (méthode reproduite) ; chaînes : seuls les chemins des `assert` (`__FILE__`) diffèrent |
| kernelbase / kernel32 de l'îlot | `19884285` / `d0c0b959` | `3896e576` / `9023de48` | 4 `ldp q` dans les deux kernelbase ; seuls les chemins diffèrent, plus le nom interne `kernel32-thk-309.dll` |
| msvcrt / ucrtbase de l'îlot | `d8ccfb08` / `d9218f93` | `49dd3337` / `a20a0399` | 48 `ldp q` dans les deux msvcrt ; **memmove : 782 instructions chez le joueur, 273 dans la branche** (0297, NEON, dans main depuis 4cc64cc, absent des DLL 1.5.19 du joueur) |
| win32u.so | `30d2d824` | `5d1db18d` | chaînes identiques (0294) |
| winemac.so | `b8b57e29` | `993b1309` | la branche a 0391 (`CIDRE_SYNC_POINTEUR`, main), absent du runtime du joueur |
| lsteamclient, user32, mfreadwrite, wow64win, ffmpeg (colorcnv, msvproc…) | — | — | versions de main postérieures à 1.5.19 (0221 boîte OK, 0257/0323, 0390, 0332, 0396) : la branche les a, `rt-0463` non |
| Autres modules | — | — | les sha1 diffèrent même là où aucune source n'a changé (crypt32.so : 0 chaîne propre de part et d'autre) : chemins absolus et dates du build dans les objets ; le `ntdll.so` du joueur a même `BINDIR` pointant vers `~/Dev/proton-ouvert/wine/wine11-arm64` (relié à la main) |

Runtime de l'îlot fait depuis la branche :
- `ilot.sh preparer` puis `disponible` donnent « oui » ;
- le chargeur porte `com.apple.security.hypervisor` ;
- le runtime a été préparé dans un dossier temporaire, et non dans le Cidre installé.

### Écarts restants, et pourquoi

1. **0310** (FEX, KUSER redirigé) : il est dans main mais pas dans le FEX du joueur. Il est inerte quand `CIDRE_ILOT` est posé, ce qui est le cas de tous les processus du préfixe sous l'option `ilot`.
2. **0297** (memmove/memset NEON de msvcrt/ucrtbase) : il est dans main, mais absent des DLL du joueur, qui sont construites sur les sources 1.5.19. Il a été écrit pour l'îlot (vld1q/vst1q, sans `ldp q`), mais n'y a jamais tourné avec D4. **À valider en jeu.**
3. **Modules Wine postérieurs à 1.5.19** (0221, 0257, 0314, 0323, 0332, 0390, 0391, 0396) : `rt-0463` est une base 1.5.19. La branche suit main.
4. **Instrumentation retirée** :
   - `[CIDRE_MORT]` : chez le joueur, il écrit une ligne à chaque fin de fil ;
   - `[CIDRE_FEN]` ;
   - diag 0361.
5. **Réglages adaptés** :
   - le client Battle.net garde le TSO logiciel (chez le joueur : `FEX_TSOENABLED=0` pour tous) ;
   - winedbg n'est pas coupé ;
   - liste chaude et base de pipelines sous le cache du jeu, et non dans `cidre-d4-fond`.
6. **Défauts actifs pour tous les jeux**, à vérifier hors îlot :
   - 0440 : NaN en AIR direct, code AIR changé pour tout jeu dx12 ;
   - 0434 : barrière `u_thread` ;
   - 0460 : journal des exceptions FEX coupé ;
   - 0489 : retenue rpmalloc ;
   - 0490/0491 : lectures sans faute ;
   - 0493 : vidage unique ;
   - 0292 : tampon et jumelles de l'îlot, lus hors îlot ;
   - 0365 : verrou groupé ;
   - 0494 : relais économe.

   Les variantes notées 0471 sont coupées par le lanceur hors fiche.
7. **Clé KK figée** pour tous les jeux (`fe23de31…`). C'est juste tant que `cle_kk_figee.sh verifier` passe. La construction s'arrête si les sources hachées changent.

## 5. Tests sans jeu

Lancés sur la branche (11/11), sans Wine ni jeu, tous verts :

| Test | Résultat |
|---|---|
| tester_battlenet | 196 vérifications, 0 échec |
| tester_profils | 513 / 0 |
| tester_pile_kk | 16 / 0 |
| tester_fex | tout bon |
| tester_installer_fex | 29 / 0 |
| tester_sortie | 61 / 0 |
| tester_diag | 32 / 0 |
| tester_lancement_steam | 77 / 0 |
| tester_client_steam | 113 / 0 |
| tester_langue | 62 / 0 |
| tester_version_windows | 112 / 0 |
| tester_deck | tout bon |
| tester_clavier | tout bon |
| tester_rosetta | 121 / 0 |
| tester_emplacements | 140 / 0 |
| tester_maj_avant_lancement | 202 / 0 |
| tester_saves | 168 / 0 |
| tester_bouteilles | 276 / 0 |

`tester_emplacements` a eu 4 échecs une fois, pendant les constructions (« disque débranché pendant la copie » : la copie finissait avant le débranchement simulé). Relancé seul, il passe à 140 / 0. Ce test dépend du temps et n'a pas de lien avec la branche.

Ajouts dans `tester_battlenet.sh` :
- îlot : artefacts PE, `xtajit.dll` jamais aligné, environnement des parties D4 ;
- lanceur : `compilation_kk`, variantes coupées par défaut, `fex_disque`, `fex_smc_chaud`, valeur de l'environnement prioritaire ;
- fiche `bnet-fen`.

## 6. Ce qui reste à faire en jeu (M1, joueur présent)

1. **Construire la release depuis la branche.** Commandes :
   - `etape1` ;
   - `construire_pile_arm64.sh`, qui fige la clé KK ;
   - `construire_fex.sh --installer` ;
   - `construire_pile_d4.sh pe` puis `ilot` ;
   - `empaqueter_runtime.sh`.

   Vérifier ensuite les marqueurs (`construire_pile_d4.sh marqueurs`, `strings`).
2. **Migrer les caches du joueur** vers le Cidre de la branche, par copie APFS et jamais par déplacement :
   - `cache-kk-d4-13-PFR` vers `vkd3d-cache/bnet-fen` ;
   - `air-local-d4-13-PFR` vers l'AIR local de `precompil_kk.sh` ;
   - `base-d4` vers `vkd3d-cache/bnet-fen/base-pipelines` ;
   - `liste-chaude-d4.bin` vers `vkd3d-cache/bnet-fen/liste-chaude-kk.bin` ;
   - le cache disque FEX, s'il y a lieu, dans le préfixe Battle.net.
3. **Première partie par `cidre play bnet-fen`.** Vérifier au journal :
   - `ilot : Diablo IV.exe dans l'ilot` ;
   - `[CIDRE_ILOT] actif … verrous-0462 seuil-0463` ;
   - `kk : … COMPILE_DIFFEREE=8 … VARIANTES=notees` ;
   - `cache disque cidre 256 Mio, smc chaud 64` ;
   - `relais 0` dans « KK compile detail » (avec `MESA_KK_COMPILE_STATS=1`).
4. **À comparer à `partie_combo.sh`** (mêmes zones) :
   - img/s (monde 28-42) ;
   - sauts de plus de 250 ms (6,9 par 10 min avec 0491) ;
   - gels au démarrage (0480/0491) ;
   - entrée en monde (variantes).

   Mesurer avec `CIDRE_WSI_STATS` / le journal détaillé, puis le retirer.
5. **Points propres à la branche** :
   - memmove 0297 dans l'îlot ;
   - client Battle.net avec TSO ;
   - flagm/flagm2 hors îlot pour le client ;
   - winemac 0391 ;
   - user32 0221.
6. **Non-régression hors îlot** (défauts actifs, § 4, écart 6) : PEAK, Dead Cells (i386), Demonologist, ELDEN RING, D2R, en séries entrelacées, comme pour la 1.5.19.
