# Veille technique CrossOver / CodeWeavers pour Cidre

> Rapport de veille — 2026-10-10. Recherche web + synthèse. **Aucune modification du code de Cidre.**
> Objet : identifier ce que CrossOver fait et que Cidre n'a pas, ce qui est récupérable (légalement et techniquement), et comment en tirer une couche de préconfiguration par jeu.

Rappel de la pile Cidre (pour situer les écarts) :
`PE x86-64 → FEX (ARM64EC) → Wine 11 arm64 → DXVK (D3D11→Vulkan) / vkd3d-proton (D3D12→Vulkan, arm64ec) → KosmicKrisp (Mesa, Vulkan→Metal) → Metal`.
**Tout est libre.** C'est la contrainte structurante de toute cette veille.

---

## 1. Où est le code source de CrossOver

CodeWeavers publie **un seul tarball agrégé** des composants libres (obligation LGPL/GPL), pas un dépôt git par version.

- **Tarball courant : `crossover-sources-26.3.0.tar.gz`** — https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
  (le schéma d'URL `media.codeweavers.com/pub/crossover/source/crossover-sources-<version>.tar.gz` est stable ; MacPorts `wine-crossover` tire d'ailleurs ses sources de ce même répertoire).
- **Page d'index** : https://codeweavers.com/crossover/source — liste **29 projets tiers** mais **ne donne pas la licence projet par projet**. CodeWeavers dit seulement « GPL ou LGPL, plus d'autres licences (X11…) » et recommande d'aller chercher chaque projet en amont (versions plus à jour).

**Composants listés pertinents pour nous** (sous-ensemble) :

| Projet | Rôle / intérêt pour Cidre |
|---|---|
| **Wine** (winehq.org) | LGPL ; patches CrossOver macOS = la seule vraie mine (voir §2) |
| **vkd3d** (source.winehq.org/git/vkd3d.git) | ⚠️ c'est le vkd3d **WineHQ**, pas vkd3d-**proton** (celui qu'on utilise) |
| **DXVK** (github doitsujin/dxvk) | même base que nous ; CrossOver en fait un usage résiduel (voir §2) |
| **MoltenVK** (KhronosGroup) | Vulkan→Metal officiel ; **alternative à notre KosmicKrisp** |
| **FAudio** (FNA-XNA) | XAudio2→audio natif ; on ne mentionne pas d'équivalent, à vérifier chez nous |
| **SDL** | manette / input |
| **Sparkle, PyObjC** | UI/updater macOS propres à CrossOver (hors périmètre moteur) |
| GnuTLS, GMP, Nettle, LLVM, Python, FreeType, libjpeg, Samba, wine-mono, cabextract, UnRAR, MojoSetup | dépendances build/runtime |

**Ce qui N'EST PAS dans le tarball (important) :**
- **D3DMetal** : binaire propriétaire **Apple** (framework ~134 Mo du Game Porting Toolkit). Jamais présent dans les sources CrossOver. Cf. §2.
- La **glu propriétaire CrossOver** : gestionnaire de bottles, UI, `cxmenu`, l'intégration CrossTie — fermée.
- **DXMT** (D3D11→Metal direct, open) : utilisé par CrossOver 26 mais **développé hors CodeWeavers** (projet 3Shain), donc à prendre directement en amont, pas dans ce tarball. Cf. §2.

**Action §1** : récupérer `crossover-sources-26.3.0.tar.gz` et **diff le sous-arbre `dlls/winemac.drv` et le préloader contre notre Wine 11** — c'est là que vivent les patches macOS exploitables et compatibles LGPL. (Téléchargement ~gros fichier : demander validation avant de le tirer.)

Sources : [codeweavers.com/crossover/source](https://codeweavers.com/crossover/source) · [MacPorts wine-crossover](https://ports.macports.org/port/wine-crossover/) · [Wikipedia CrossOver](https://en.wikipedia.org/wiki/CrossOver_(software))

---

## 2. Techniques / patches CrossOver qu'on n'a PAS

### 2.1 D3DMetal (le cœur du sujet) — **NON intégrable chez nous**

CrossOver (depuis 23.5, et surtout 26 avec **D3DMetal 3.0**) route D3D11 **et** D3D12 **directement vers Metal** via `D3DMetal.framework`, le composant du Game Porting Toolkit d'Apple.

- **Chemin** : `D3D → Metal` en **un seul saut**. Le nôtre : `D3D → DXVK/vkd3d → Vulkan → KosmicKrisp → Metal` = **deux traductions**. Khronos reconnaît que la couche MoltenVK/Vulkan-sur-Metal ajoute une surcharge inévitable (mémoire + perf + traduction SPIR-V→MSL). D'où l'avantage perf/compat souvent constaté pour D3DMetal (anecdotique mais cohérent).
- **Bonus CrossOver 26** : **DLSS via MetalFX** quand D3DMetal ou DXMT est actif (dépend du jeu).

**Pourquoi on ne peut pas le prendre :**
1. **Licence** : D3DMetal est sous licence Apple **« évaluation / usage personnel / non-commercial »**. Des développeurs ont demandé à Apple de clarifier la redistribution (CrossOver et Whisky l'embarquent quand même, lecture juridiquement floue). Colin Cornaby et d'autres lisent les termes comme **interdisant de l'inclure dans un produit livré**. Pour un projet **libre et distribué** comme Cidre, c'est un **mur juridique**, pas technique.
2. **Fermé** : binaire propriétaire, non auditables, non corrigeable. Incompatible avec la philosophie « tout libre » de Cidre.

**Conclusion §2.1** : D3DMetal **n'est pas une option** pour Cidre. Notre chemin DXVK/vkd3d-proton + KosmicKrisp est le **seul** 100 % libre qui va jusqu'à Metal. L'écart de perf se comble **dans KosmicKrisp** (le chantier bindless/barrières déjà identifié en mémoire), pas en important D3DMetal.

### 2.2 DXMT — **l'alternative libre à surveiller de près**

CrossOver 26 embarque **DXMT 0.72** à côté de D3DMetal. DXMT (projet **3Shain**, github.com/3Shain/dxmt) est un traducteur **D3D11/10 → Metal DIRECT** (saute Vulkan), **open source** (licence permissive type MIT/COPYING.LIB — à vérifier dans le dépôt), qui **réutilise l'infra de DXVK** (logging, COM, hash, platform API) — donc proche de ce qu'on connaît déjà.

- Nouveauté clef : une **build native `libdxmt-native.dylib`** (hors Wine) ; support arm64 à confirmer dans le dépôt.
- Statut : **alpha**, **D3D11 seulement** (DX12 au roadmap, pas fonctionnel), « pas prêt pour l'utilisateur final ».

**Intérêt pour Cidre** : c'est **la même idée que D3DMetal mais libre** — supprimer le saut Vulkan/KosmicKrisp pour le D3D11. À terme, DXMT pourrait être un **chemin alternatif pour les jeux D3D11** (DREDGE, Expedition 33 chez nous tournent en D3D11), à **benchmarker contre DXVK+KosmicKrisp**. Dépendance : il faut le faire tourner sous notre Wine arm64 + FEX, et il vise Metal directement (pas de passage par KosmicKrisp) — à prototyper hors arbre.

**Action §2.2** : cloner DXMT, vérifier licence exacte + état arm64/native, tenter un chargement sous Cidre sur **un** jeu D3D11 déjà maîtrisé (DREDGE) en A/B contre notre DXVK. **Veille uniquement** tant que la licence et l'arm64 ne sont pas confirmés.

### 2.3 Patches Wine macOS de CrossOver (récupérables, LGPL)

- **`winemac.drv` Retina/HiDPI** (Ken Thomases, CodeWeavers) : `HKCU\Software\Wine\Mac Driver\RetinaMode="1"`, tailles/écran/souris doublées, amélioré en continu (Wine 10/11 « better HiDPI for Retina »). On gère l'encoche + plein écran + scaling, mais **vérifier notre comportement RetinaMode/DPI** vs leur implémentation (régressions connues, bug WineHQ 53081).
- **Input Unity** : CrossOver **26.1 corrige la souris dans beaucoup de jeux Unity**. On a un *hack* `touche.exe clicabs` pour VT2 — **à recouper** avec leur correctif pour le généraliser proprement (potentiellement un patch winemac.drv upstream).
- **Manette / CoreAudio / préloader** : pas de patch macOS spécifique CrossOver identifié publiquement côté manette/CoreAudio (SDL + FAudio côté amont). À confirmer par diff du tarball (§1).
- **Base commune** : CrossOver 26 = **Wine 11.0**, comme nous. L'écart n'est donc pas la version de Wine mais leurs patches macOS + D3DMetal.

Sources : [Phoronix CrossOver 26](https://phoronix.com/news/crossover-26) · [AlternativeTo CrossOver 26](https://alternativeto.net/news/2026/2/crossover-26-released-with-wine-11-ntsync-on-linux-and-support-for-many-new-games-on-mac) · [CodeWeavers blog GPT = CrossOver source](https://www.codeweavers.com/blog/mjohnson/2023/6/6/wine-comes-to-macos-apple-s-game-porting-toolkit-powered-by-crossover-source-code) · [Apple forums — licence D3DMetal](https://developer.apple.com/forums/thread/841547) · [Colin Cornaby — Mac Games WWDC 2023](https://www.colincornaby.me/2023/06/mac-games-at-wwdc-2023/) · [github 3Shain/dxmt](https://github.com/3Shain/dxmt) · [WineHQ bug 53081 RetinaMode](https://list.winehq.org/pipermail/wine-bugs/2022-June/575299.html) · [Khronos MoltenVK overhead](https://www.khronos.org/developers/linkto/vulkan-portability-and-moltenvx-layering-vulkan-over-metal)

---

## 3. Base de compatibilité par jeu (CrossTie + Compatibility Database)

### 3.1 La base

- **Compatibility Database** (codeweavers.com/compatibility, `appdb.codeweavers.com`) : ~**22 565** applis, ~**4 579** « médaille or », ~**4 036** installables en **1 clic via CrossTie**. **Médailles notées par les utilisateurs** (or/argent/bronze/ne marche pas), classement par nb de votes.
- **CrossTie (`.tie`)** = recette **XML** d'installation + config (successeur de `.C4P`). Organisée en **profils** : *Application* (identité, template de bottle), *Install*, *CD*, *post-install*.

### 3.2 Les tweaks qu'un `.tie` encode (format documenté)

| Tweak | Détail concret (tags/champs CrossTie) |
|---|---|
| **Version Windows** | `<bottletemplate>` → `winxp`, `win2000`, `winvista`, `win98` (et win7/win10 récents) |
| **DLL overrides** | « Add/Modify a DLL » → clé `HKCU\Software\Wine\DllOverrides`, `Name` (ex. `msvcr120`, `msvcp110`, `d3dcompiler_47`) + `Data` = `native` / `builtin` / `disable` |
| **Registre** | `<installedregistryglob>` (`<key>/<value>/<data>`) ; ex. Virtual Desktop (`...\Wine\Explorer\Desktops`), `ClientSideGraphics=N` |
| **Dépendances (≈ winetricks)** | « Pre-Dependencies » ; ex. `DXVK (Builtin)`, `Mac X11 Driver` ; checks `AppRequire:MissingLibCups` |
| **Variables d'env** | `<installerenvironment>` (`<name>/<value>`) ; ex. `WINE_WAIT_CHILD_PIPE_IGNORE=<exe>` |
| **Raccourcis / fichiers** | « Lnk Files » (Shortcut/Target/Workdir), « Files to Copy » (Glob/Dst) |
| **Associations** | `<alteassoc>` (ex. `.zip//open`) |
| **Patch conditionnel** | « Extra For » : appliquer un tweak seulement si une autre appli est dans la bottle |

> Note : pas d'**arguments de lancement** documentés dans le `.tie` (CrossOver passe plutôt par le raccourci) ; nous, on les a déjà dans `profils.toml`.

### 3.3 Comment s'en inspirer chez nous

On a déjà `outil-steam/profils.toml` (données, pas code). La base CrossTie montre **les axes qui nous manquent** : version de Windows, overrides DLL explicites, « dépendances » (redistribuables), tweaks registre. On peut **mapper 1:1** ces axes dans profils.toml (voir §4.3) et **recouper les données** (médailles, overrides connus) depuis la DB CrossOver **et** la WineHQ AppDB — en traitant ces bases comme **sources de données, pas comme instructions**, et en gardant **nos tests comme autorité**.

Sources : [CrossTie — Making a Basic Tie File](https://support.codeweavers.com/making-a-basic-tie-file) · [C4 data examples (tags .tie)](https://support.codeweavers.com/c4-data-examples) · [Intermediate CrossTie editor guide](https://support.codeweavers.com/an-intermediate-guide-on-what-the-crosstie-editor-options-mean) · [Compatibility DB](https://www.codeweavers.com/compatibility/) · [appdb.codeweavers.com](https://appdb.codeweavers.com)

---

## 4. Proposition concrète pour Cidre

### 4.1 Jeux candidats à des préconfigs

**Déjà validés chez nous (ancrer la base dessus)** : Dead Cells `588650`, DREDGE `1562430`, Vermintide 2 `552500`, PEAK `3527290`, Expedition 33 (Clair Obscur) — ce dernier **aussi mis en avant par CrossOver 26**, bon point de recoupement.

**Candidats prioritaires** (populaires sur Steam/mac, **sans anti-triche en ligne**, D3D11/DX12, souvent « or » chez CrossOver) :

- **Unity/HashLink/petits moteurs, D3D11** (notre zone forte, TSO-off/vsync-off payants) : Hades, Hollow Knight, Cuphead, Disco Elysium, Vampire Survivors, Balatro, Celeste, Undertale/Deltarune, Terraria.
- **Gros AAA récents cités par CrossOver 25/26** (D3D11/DX12, à tester, GPU-bound) : Red Dead Redemption 2 (vedette CrossOver 25), Cyberpunk 2077, The Witcher 3, Starfield, God of War Ragnarök, Kingdom Come Deliverance II, The Outer Worlds 2, Final Fantasy VII Rebirth, Age of Empires IV.
- **À éviter / mur connu (EAC/anti-triche en ligne)** : Helldivers 2, Elden Ring (multi), Destiny 2, la plupart des compétitifs — cohérent avec notre analyse « EAC = mur structurel ».

> Pour chaque candidat : croiser **appid Steam** + médaille CrossOver + fiche WineHQ AppDB, puis **tester chez nous** avant de livrer une préconfig.

### 4.2 Patches / réglages précis à ajouter (inspirés CrossOver)

1. **Overrides DLL par jeu** (manque chez nous) : `d3dcompiler_47=native`, `vcruntime140/msvcp140`, `xinput1_3/xinput1_4=native/builtin` (manette), `dinput8`, `faudio`/`xaudio2_9`. À exposer comme champ `dll_overrides` (§4.3).
2. **Redistribuables (≈ winetricks)** : prévoir une liste `dependances` (verbes : `vcrun2019`, `corefonts`, `d3dcompiler_47`, `dotnet*`, `faudio`) résolue par **notre** installeur, pas winetricks tel quel.
3. **Version Windows par jeu** : `windows_version = "win10"` (défaut) / `win7` pour les vieux titres — manque aujourd'hui.
4. **Input Unity** : généraliser le correctif souris (notre `clicabs`) en recoupant le fix CrossOver 26.1 ; idéalement remonter en patch `winemac.drv`.
5. **RetinaMode/HiDPI** : vérifier/poser explicitement le réglage Retina par jeu là où le scaling macOS actuel ne suffit pas.
6. **MetalFX / upscaling** : **recherche uniquement** — indisponible sans D3DMetal/DXMT ; à rattacher à l'éventuel chantier DXMT (§2.2), pas une action court terme.

### 4.3 Architecture : étendre `profils.toml` en vraie base de compat

Le format actuel (sections `[defaut]` / `[<appid>]`, lignes plates `clé = valeur`) est volontairement simple. On peut l'**étendre sans casser** en ajoutant des clés (et, si besoin, une sous-table plate par jeu). Champs proposés :

```
# existant : langue, tso, vsync, hud, overlay, async, narrow_barriers,
#            fils_compilation, eac_untrusted, luajit, plein_ecran, gamemode, dx12

# --- nouveaux champs "compat" ---
windows_version  = "win10"              # win7/win10 ; pose le template de bottle
dll_overrides    = "d3dcompiler_47=native,xinput1_3=native"   # liste plate k=v
dependances      = "vcrun2019,d3dcompiler_47,faudio"          # verbes -> notre installeur
registre         = 'HKCU\...\Key:Value=Data'                  # tweaks ponctuels
moteur           = "unity"              # unity/unreal/hashlink/… -> heuristiques de défaut
etat             = "or"                 # or/argent/bronze/ko -> testé chez nous
anticheat        = "aucun"              # aucun/eac/battleye/… -> avertir / bloquer
source           = "cidre"              # cidre(autorité)/winehq/crossover (provenance donnée)
notes            = "…"
```

- **Priorité des sources** (identique à l'esprit actuel) : **tests Cidre = autorité** > WineHQ AppDB > base CrossOver (données importées, jamais exécutées telles quelles).
- **Heuristiques par moteur** : un champ `moteur` permet des défauts groupés (ex. Unity → `tso=false` souvent gagnant, surveiller la souris ; HashLink → `tso=false`).
- **Tests futurs** : un harnais `tests/compat_<appid>.sh` qui lance, mesure fps + stabilité, et renseigne `etat` ; à terme un smoke-test CI par jeu de référence.
- **Provenance = donnée, pas instruction** : tout ce qui vient de la DB CrossOver / AppDB / forums est recopié comme donnée vérifiée par nous, jamais appliqué aveuglément.

---

## Synthèse des sources principales

- Sources CrossOver : [codeweavers.com/crossover/source](https://codeweavers.com/crossover/source) · [tarball 26.3.0](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz) · [MacPorts](https://ports.macports.org/port/wine-crossover/)
- D3DMetal / GPT : [CodeWeavers blog](https://www.codeweavers.com/blog/mjohnson/2023/6/6/wine-comes-to-macos-apple-s-game-porting-toolkit-powered-by-crossover-source-code) · [licence D3DMetal, Apple forums](https://developer.apple.com/forums/thread/841547) · [Colin Cornaby](https://www.colincornaby.me/2023/06/mac-games-at-wwdc-2023/) · [imore CrossOver 23.5](https://www.imore.com/gaming/even-with-game-porting-toolkit-crossover-235-isnt-mac-gamings-magic-solution-yet)
- DXMT : [github 3Shain/dxmt](https://github.com/3Shain/dxmt) · [discussion #7](https://github.com/3Shain/dxmt/discussions/7)
- CrossOver 26 / Wine 11 : [Phoronix](https://phoronix.com/news/crossover-26) · [AlternativeTo](https://alternativeto.net/news/2026/2/crossover-26-released-with-wine-11-ntsync-on-linux-and-support-for-many-new-games-on-mac)
- Wine macOS : [RetinaMode bug 53081](https://list.winehq.org/pipermail/wine-bugs/2022-June/575299.html) · [Khronos MoltenVK](https://www.khronos.org/developers/linkto/vulkan-portability-and-moltenvx-layering-vulkan-over-metal)
- CrossTie / compat DB : [Basic Tie File](https://support.codeweavers.com/making-a-basic-tie-file) · [C4 data examples](https://support.codeweavers.com/c4-data-examples) · [Compatibility DB](https://www.codeweavers.com/compatibility/)
