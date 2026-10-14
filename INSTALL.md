# Installer Cidre

## Pour JOUER -- la voie normale : Verger

Il faut un Mac Apple Silicon sous macOS 26 ou plus recent. Ni Homebrew, ni
Rosetta, ni outils de developpement.

1. **Installer le client Steam** (https://store.steampowered.com/about/), le
   lancer et s'y connecter. Il lance les jeux Steam, et c'est dans son cache que
   Cidre lit le nom des jeux du compte.
2. **Installer [Verger](https://github.com/gtranche/verger/releases/latest)** :
   decompresser `Verger.zip`, puis clic droit > Ouvrir la premiere fois
   (l'application n'est pas notarisee par Apple).
3. **Laisser Verger installer Cidre** : il telecharge `cidre-runtime.tar.xz`
   depuis la derniere release, le decompresse dans
   `~/Library/Application Support/Cidre` et lance `cidre setup`, qui prepare le
   pilote Vulkan, le prefixe Wine, DXVK, FEX, le pont Steam et SteamCMD.
4. **Se connecter a Steam dans Verger** (bouton +, « Connexion a Steam ») : c'est
   la session de SteamCMD, l'outil de Valve qui telecharge les jeux. Elle est
   distincte de celle du client Steam.

**Des jeux deja installes par CrossOver, Whisky ou Heroic ?** Inutile de les
telecharger une seconde fois : Cidre retrouve les jeux Steam Windows de leurs
bouteilles (`cidre bottles`) et les reprend dans son dossier (`cidre import
<appid>`). C'est un clone APFS : immediat, sans place prise tant que les deux
copies sont identiques, et la bouteille n'est pas modifiee -- le jeu y reste
jouable. `cidre import <appid> --move` le deplace au lieu de le cloner (la
bouteille ne l'a plus) ; Cidre le refuse tant que la bouteille est en cours
d'usage (son client Steam ou un jeu ouvert, son wineserver encore la) et dit
quoi fermer. Une bouteille sur un autre disque est copiee, pas clonee : Cidre le
dit, et refuse si la place manque.

Les sauvegardes du jeu suivent : `cidre import` les retrouve dans la bouteille
(`drive_c/users/<nom>/...`, d'apres la fiche du jeu, sinon les dossiers
habituels des moteurs, au nom du jeu) et les copie sur le disque C: de Cidre, la
ou le jeu les cherchera. Une sauvegarde plus recente deja presente cote Cidre
n'est jamais ecrasee ; une plus ancienne est remplacee apres copie dans
l'historique du jeu ; la bouteille n'est que lue.

Avant de lancer un jeu du dossier Cidre qui ecrit ses sauvegardes par l'API de
Steam, Cidre demande au client Steam de synchroniser son nuage -- une seance
Steam au nom du jeu, ouverte puis fermee, l'affaire d'une seconde -- et attend
qu'il ait fini : une sauvegarde faite sur un autre appareil est la des le
premier lancement. A la sortie du jeu, le client envoie la partie ; si le nuage
etait vide, c'est elle qui devient la premiere version en ligne. Jamais de
seance pour un jeu dont Steam synchronise des dossiers (Auto-Cloud) : la synchro
qu'elle declencherait pourrait retirer du nuage des fichiers que ce Mac n'a pas.
Client Steam ferme ou hors ligne : rien n'est attendu, le jeu part avec les
sauvegardes de ce Mac.

La regle, partout : ce que Steam Cloud synchronise a toujours la priorite -- ni
la copie de Cidre, ni iCloud, ni une bouteille ne remplacent un fichier que
Steam detient ; ils ne font que combler un dossier que Steam a vide. A la
reprise d'une bouteille : un jeu qui ecrit par l'API de Steam ne recoit rien (le
client Steam fournit ses sauvegardes) ; un jeu dont Steam synchronise un dossier
macOS ne recoit celles de la bouteille que si ce dossier est vide et que le
client Steam n'en connait aucune dans le nuage -- sinon Cidre ne copie rien, dit
combien la bouteille en garde et ou, et `cidre import <appid> --saves --forcer`
passe outre si tu y tiens (les versions remplacees sont gardees). Quand le
client Steam n'a encore jamais synchronise le jeu sur ce Mac, Cidre ne peut pas
savoir ce que garde le nuage : il comble le dossier et previent que Steam peut
signaler un conflit a la sortie du jeu. Si Cidre ne trouve pas ou
le jeu les range, il le dit : `cidre import <appid> --saves --dossier <dossier
de la bouteille>` le lui montre. `cidre import <appid> --saves` rattrape un jeu
repris par un Cidre plus ancien, ou rejoue depuis dans la bouteille.

Un jeu marche, ou ne marche pas ? Le dire sert a tous les joueurs : Verger a un
bouton « Partager mon resultat » sur la page de chaque jeu. La marche a suivre,
et comment proposer une fiche de jeu : [profils/CONTRIBUER.md](profils/CONTRIBUER.md)
(*[English](profils/CONTRIBUER.md#contributing-to-the-game-profiles)*).

SteamCMD est installe a partir des paquets a jour de Valve
(`tests/installer_steamcmd.sh`), pas de son archive `steamcmd_osx.tar.gz` : elle
date de 2020 et ne contient qu'un binaire Intel, qui ne demarre pas sans Rosetta.

## Sans Verger (install du runtime pre-compile en ligne de commande)

Le runtime deja construit est publie en **release GitHub**. L'utilisateur ne
construit rien : il telecharge UN fichier depuis la page de la derniere release
et le lance.

- Page : https://github.com/gtranche/cidre/releases/latest
- **`installer-cidre.command`** : double-clic dans le Finder. La 1re
  fois, Gatekeeper bloque un script telecharge -> **clic droit > Ouvrir**.
- ou **`installer_cidre.sh`** : `sh ~/Downloads/installer_cidre.sh`
  (echappe a Gatekeeper, pas de clic droit).

L'installeur va chercher le tarball `cidre-runtime.tar.zst` (~550 Mo) de
la release et fait tout le reste. Depuis une copie du depot, c'est le meme
script :

```
sh installer_cidre.sh
```

Il telecharge le tarball de la derniere release, le decompresse (sous
`~/Library/Application Support/cidre` par defaut), **relocalise** l'ICD
Vulkan, regenere un prefixe Wine propre (sans mono/gecko), y depose DXVK + FEX,
et branche Steam. Prerequis utilisateur : macOS Apple Silicon, `zstd`
(`brew install zstd`), Steam installe. Valide : le runtime est relocalisable
(Wine tourne depuis le nouvel emplacement, FEX et KosmicKrisp suivent).

Cote mainteneur, produire le tarball de release :
```
sh tests/empaqueter_runtime.sh        # -> cidre-runtime.tar.zst (~554 Mo)
```
puis l'attacher a une release GitHub (chaque asset <= 2 Gio -- on est loin).
(Dans `installer_cidre.sh`, remplacer `@@OWNER@@/@@REPO@@` par le depot.)

---

## Pour DEVELOPPER / reconstruire depuis les sources

Ce qui suit construit tout depuis zero (utile pour un mainteneur, PAS pour un
joueur). Automatique : `sh tests/de_zero_a_jouable.sh`.

État : **carte d'installation + trous connus**. Ce n'est pas encore un bootstrap
en une commande — les sections marquées **[TROU]** demandent un script ou une
récupération manuelle. L'objectif de ce document est que l'installation soit
*reproductible et comprise*, pas magique.

**Automatique :** `sh tests/de_zero_a_jouable.sh` enchaine tout (prerequis →
toolchain → clone+patches → FEX → pile arm64 → prefixe → Steam). Les 2 Homebrew
et Xcode CLT restent manuels (le script le dit). Le detail des etapes suit, pour
comprendre/reprendre une etape isolee.

Cible : Apple Silicon (testé M1 Max, macOS 26 « Tahoe »). La pile arm64 native
(sans Rosetta) est la voie actuelle ; une ancienne voie x86_64/Rosetta existe
dans `etape2_construire_pile.sh` mais n'est plus la cible.

Ce qu'on obtient : un PE Windows x86-64 → FEX (ARM64EC) → Wine 11 arm64 → DXVK →
winevulkan → chargeur Vulkan → KosmicKrisp (Mesa) → Metal 4. Lancement par le
bouton « Jouer » de Steam (voir plus bas).

---

## 1. Prérequis système

- **Xcode Command Line Tools** (`xcode-select --install`) — clang, Metal, `file`, etc.
- **Deux Homebrew** (la pile mélange des outils Intel et arm64) :
  - Homebrew **Intel** sous `/usr/local` (via Rosetta) : `bison` (≥ 3), `mingw-w64`, `zstd`
  - Homebrew **arm64** sous `/opt/homebrew` : `llvm`, `spirv-tools`, `cmake`, `glslang`, `meson`, `ninja`, `python@3`
- **Steam** pour macOS installé et connecté (le pont lsteamclient parle au vrai
  client Steam natif).

**[TROU]** Ces prérequis sont documentés mais non vérifiés/installés par un
script. À faire : un `etape0` qui teste leur présence et les installe.

## 2. Toolchain (`toolchain/`)

**Scripté** pour le coeur (llvm-mingw) : `sh tests/etape0_toolchain.sh`
(télécharge, vérifie le sha256, extrait, pose le symlink `llvm-mingw` ; idempotent).
Reste manuel : dxc, innoextract, le venv Python. Détail du blob :
- `llvm-mingw-20260908-ucrt-macos-universal.tar.xz` (~124 Mo, sha256 connu, voir NOTES §… « llvm-mingw ») — fournit les triplets `aarch64-w64-mingw32`, `arm64ec-w64-mingw32`, `i386-windows`, `x86_64-pc-windows-msvc`. **Patché** par `etape1` (accès TEB via x18 dans `winnt.h`, voir §3).
- `dxc` (DirectX Shader Compiler), `innoextract` (extraction d'installeurs GOG), `pyenv`, `vkxml`.

À faire : un script qui télécharge llvm-mingw (URL + sha256), dxc, innoextract,
et peuple `toolchain/`. C'est le plus gros angle mort.

## 3. Sources amont (clonées à des révisions fixes)

`tests/etape1_appliquer_correctifs.sh --cloner` clone **cinq** arbres et y
applique la série de patches :

| arbre            | URL                                             | révision      |
| ---------------- | ----------------------------------------------- | ------------- |
| `src/mesa`       | gitlab.freedesktop.org/mesa/mesa                | `5f253b9`     |
| `src/wine`       | gitlab.winehq.org/wine/wine                     | `b073859`     |
| `src/wine11`     | gitlab.winehq.org/wine/wine                     | `7b3fff7`     |
| `src/vkd3d-proton`| github.com/HansKristian-Work/vkd3d-proton      | `5d0db74`     |
| `src/dxvk`       | github.com/doitsujin/dxvk                       | `c3dd74b`     |

**[TROU]** Deux sources ne sont PAS dans la liste de clone d'etape1, à ajouter :
- **FEX** → `third_party/FEX` (etape1 le *patche* mais ne le clone pas ; rev actuelle `72b2ff8`).
- **Vulkan-Loader** → `src/Vulkan-Loader` (github.com/KhronosGroup/Vulkan-Loader, rev `e146980`).

KosmicKrisp est dans `src/mesa/src/kosmickrisp` (présent à la révision mesa
ci-dessus) ; la série de patches `00NN-kosmickrisp-*.patch` le modifie (dont la
fondation GPL parkée, `0077`).

## 4. Appliquer les patches

```
sh tests/etape1_appliquer_correctifs.sh --cloner   # clone + patche (premiere fois)
sh tests/etape1_appliquer_correctifs.sh            # re-patche un arbre deja clone
```
Applique la série par arbre (voir `tests/series.sh`), régénère `configure` (wine),
patche le `winnt.h` de la toolchain et FEX (patch `0070`). Vérifiable :
`sh tests/verifier_reconstruction.sh` (base + série reproduit l'arbre de travail).

## 5. Construire FEX

**Scripté** : `sh tests/construire_fex.sh [--installer]`
(cmake `-DMINGW_TRIPLE=arm64ec…`/`aarch64…`, `-DTUNE_CPU=generic -DBUILD_TESTING=OFF`,
build-ec + build-wow64 ; recette validée contre les CMakeCache existants).

FEX produit `libarm64ecfex.dll` (invités x86-64) et `libwow64fex.dll` (invités
32 bits). Build cmake avec `-DMINGW_TRIPLE=arm64ec-w64-mingw32` (voir NOTES §222,
§237, §242 pour la recette exacte et les deux témoins TEB/x18), dans
`third_party/FEX/build-ec/` et `build-wow64/`. Puis :
```
sh tests/installer_fex.sh     # copie les DLL en xtajit64.dll / xtajit.dll de Wine
```
Conformité : `sh tests/conformite_fex.sh` (après toute reconstruction de FEX).

À faire : extraire les commandes cmake/ninja de build FEX dans un script.

## 6. Construire la pile (Mesa, Wine, DXVK, vkd3d, loader)

`tests/etape2_construire_pile.sh` orchestre les builds. Pour la voie arm64
native, les éléments clés (déjà utilisés par les scripts de lancement) :
- **Mesa/KosmicKrisp arm64** : `ninja -C build/mesa && ninja -C build/mesa install` (→ `prefix/`).
  ⚠️ Toujours avec `-DWINE_TEB_SANS_X18` quand on reconstruit du PE Wine, pas Mesa.
- **Mesa x64** (pour la conformance) : `build/mesa-x64` → `prefix-x64/`.
- **Wine 11 arm64** : `make && make install` sous `wine/wine11-arm64` (drapeaux TEB/x18, voir NOTES).
- **DXVK** arm64ec (`build/dxvk-winarm64ec`) et la variante **async** (`dxvk-gplasync`,
  patch `./dxvk-gplasync-2.7.1-1.patch`, `build/dxvk-async-winarm64ec`).
- **Vulkan-Loader** x64, **vkd3d-proton**.

## 7. Préfixe Wine

`wine/pfx-arm64ec` : `wineboot -u` jusqu'au bout (mono désactivé, voir
`feedback_prefixe_wine_etat_empoisonne`). Déployer DXVK (dxgi/d3d11) dans
`drive_c/windows/system32`, et `installer_fex.sh` y recopie aussi FEX.

## 8. Intégration Steam (bouton « Jouer »)

Steam macOS **ne lit pas** `compatibilitytools.d` (NOTES §186-188, prouvé) — le
seul hook est les options de lancement. Une commande les pose sur tous les jeux
Windows-only (et saute les jeux à version macOS native) :
```
# Fermer Steam d'abord (il réécrit localconfig.vdf en quittant)
sh tests/brancher_jeux_steam.sh            # montre
sh tests/brancher_jeux_steam.sh --ecrire   # pose
sh tests/installer_agent_steam.sh          # agent : re-pose apres chaque reecriture de Steam
```
`tests/lancer_depuis_steam.sh` reçoit `%command%`, monte la pile, et porte les
besoins par jeu (ex. 552500 Vermintide 2 : `PROTON_OUVERT_LUAJIT=1`, async 4
fils, `-eac-untrusted`). Détection macOS native dans `brancher_jeux_steam.sh` :
un jeu avec `.app`/Mach-O est laissé à Steam.

## 9. Limites connues

- **EAC/BattlEye online** : mur structurel (pas de module macOS/Wine-macOS chez
  l'éditeur). Voir `project_cidre_anti_triche`. Modded Realm quand il existe.
- **Jeux LuaJIT non-GC64** : exigent `PROTON_OUVERT_LUAJIT=1` (fenêtre basse 64 bits).
- **Plein écran exclusif** fragile sur Wine-macOS → préférer `borderless_fullscreen=true`.

---

## Résumé des TROUS pour un bootstrap « une commande » (`etape0` à écrire)

1. Prérequis système (2× Homebrew + paquets + Xcode CLT) : vérifier/installer.
2. ~~llvm-mingw~~ **fait** (`etape0_toolchain.sh`). Reste : dxc, innoextract, venv Python.
3. Ajouter **FEX** et **Vulkan-Loader** à la liste de clone d'`etape1`.
4. ~~build FEX~~ **fait** (`construire_fex.sh`).
5. Un orchestrateur `de-zero-a-jouable.sh` : etape0 → etape1 → FEX → etape2 → préfixe → Steam.

Rien de tout ça n'est bloquant techniquement — ce sont des étapes aujourd'hui
manuelles/implicites à rendre explicites et scriptées, puis à **valider sur une
vraie machine neuve** (seule épreuve qui compte).
