# Préparation des shaders avant le lancement

L'équivalent, pour KosmicKrisp, de l'écran « Traitement des shaders Vulkan » de Steam (rejeu Fossilize) :
avant de lancer un jeu D3D12/Vulkan, Cidre recompile **hors du processus du jeu**, en parallèle, les pipelines
que le jeu a **liés** lors des parties précédentes et qui ne sont pas compilés pour le KosmicKrisp, le GPU et le
macOS du moment. Bouton **Passer** : le jeu part tout de suite, le reste se compile en jeu comme aujourd'hui.
Rien (aucun processus, aucun événement) quand tout est chaud.

Fichiers : `tests/preparer_shaders.sh` (logique), `tests/prepa_shaders.c` → `build/prepa-shaders` (outil natif),
`tests/tester_preparation_shaders.sh` (essais sans jeu), branchements dans `cidre` (`play`, `preparation`, `set`)
et `tests/lancer_depuis_steam.sh` (`debut`/`noter`), option dans `outil-steam/profils.toml`, livraison dans
`tests/empaqueter_runtime.sh`. Verger : `verger/0001-preparation-des-shaders.patch` (voir § 7).

## 1. La leçon de 0492

0492 compilait en fond, **pendant la partie**, tout le froid connu : sur Diablo IV, 4 691 nuanceurs compilés
pour 1 servi au bind, des fils de compilation qui saturent le processeur, 51 sauts > 250 ms par 10 min contre 6,9
(coupé par défaut le 12/11). D'où deux règles :

- **avant** la partie, jamais pendant : le jeu n'a aucun fil de préparation à côté de lui ;
- **seulement l'utile** : les pipelines de la base que le jeu a effectivement liés (liste chaude), pas les ~17 600
  qu'il crée au chargement. Sur la base de D4 : 27 424 pipelines notés, **1 719** liés. (Le mode « tout », § 10,
  prépare toute la base, mais toujours avant la partie.)

## 2. Ce qui existait, et ce qui est repris

| Pièce | Rôle | Dans la préparation |
|---|---|---|
| 0444 `CIDRE_BASE_PIPELINES` | base par jeu à la Fossilize : `pipelines.bin` (SPIR-V/NIR et état de chaque pipeline froid, dédoublonné par la clé VS), `nuanceurs.bin`, `fonctions.bin`, `env.txt` (options `CIDRE_*`/`MESA_*` de la partie) | **source** des pipelines à rejouer |
| 0444 `CIDRE_REJEU` | rejeu de KosmicKrisp dans `vkCreateDevice` d'un programme sans Wine (`kk_rejeu.c`, chantier `~/Dev/cidre-d4-fond`) : cache disque (0430), réserve d'AIR (0171), archive Metal | **moteur** de la préparation (`prepa-shaders rejouer`, reprise de `kk_rejeu.c`) |
| 0472 | capture des pipelines de rendu dans l'archive au rejeu (mode cache de fonctions 0451) ; `CIDRE_REJEU_JOURNAL=<nom>` ; lots | journal **par identité**, lots = avancement |
| 0441 liste chaude | `<cache>/liste-chaude-kk.bin` : clé (32 octets) de chaque nuanceur lié | **filtre** : ce que le jeu demande vraiment |
| 0450 `CIDRE_REJEU_QOS_HAUTE` | fils du rejeu en user-interactive | posé : le joueur attend |
| 0237 `CIDRE_COMPILE_DIFFEREE=<n>` | fils de compilation | `n` = cœurs (`CIDRE_PREPARATION_FILS`) |
| 0165 / `cidre precompil` / `tests/precompil_kk.sh` | paquets téléchargés (AIR par famille, archive par architecture et macOS), clé `kk`, famille, réserve d'AIR | clé et famille par `precompil_kk.sh kk|famille`, AIR local et paquet passés au rejeu |
| `tests/rejouer_mtl3.m` | rejeu d'une récolte 0165 par l'ancienne API Metal, pour fabriquer les paquets | non utilisé (outil de fabrication des paquets, côté Cidre) |
| `tests/etat_shaders.sh` | « premier lancement / cache invalide / en cache » d'après les parties notées | adoption à la première rencontre (§ 3.5) |

Rien de KosmicKrisp n'est modifié ni reconstruit : tout passe par des options que kk-0494 a déjà
(`CIDRE_REJEU`, `CIDRE_REJEU_JOURNAL`, `CIDRE_REJEU_LOT`, `CIDRE_REJEU_QOS_HAUTE`).

## 3. Conception

### 3.1 Déroulement de `cidre play <id>`

```
annoncer_shaders            {"evenement":"shaders",...}            (existant)
preparer_shaders            tests/preparer_shaders.sh preparer <id> [--json]
  evaluer                   2 stat si pas de base ; ~0,06 s si chaud (tampon)
  [a_preparer]
    filtrer                 base ∩ liste chaude − journal(identité) − échecs(identité) -> travail.<pid>/pipelines.bin
    rejouer (fond)          build/prepa-shaders rejouer <dylib du jeu>, env de env.txt nettoyé
    sonder toutes les 0,5 s journal (avancement), drapeau passer, parent vivant
  {"evenement":"preparation",...}
partir                      {"evenement":"lancement"} puis le lanceur
...                         lanceur : PREP_DEBUT = taille de la liste chaude ; à la sortie, `noter`
```

Valable pour tous les chemins de `cidre play` qui passent par `partir` : jeu Steam du client (avant
`open steam://run`), jeu du dossier Cidre, jeu hors Steam, **Battle.net `bnet-*`** (avant l'ouverture du client).

### 3.2 Identité

Un pipeline compilé ne vaut que pour : la **clé de code de KosmicKrisp** (`KK_CODEGEN=` lue dans la dylib que
l'ICD de `etape2_pile_arm64ec.sh` charge), la **famille de GPU** (`apple7` = M1, `apple8` = M2 et suivants,
`precompil_kk.sh famille`), le **build de macOS** (`sw_vers -buildVersion` : le compilateur Metal change avec lui,
et les archives d'un autre macOS sont refusées). Identité = `<kk>-<famille>-<build>`, par exemple
`1-fe23de315cfc449d-apple7-25F84`. Mise en cache dans `<cache>/preparation/identite` tant que la dylib (chemin,
taille, date), le modèle de Mac et le build ne changent pas.

La base et la liste chaude, elles, ne dépendent pas de l'identité (clés de cache Vulkan, SPIR-V/NIR) : elles
restent où les met le lanceur, sous `vkd3d-cache/<id>`, une par Mac (la famille est fixe sur une machine ; un
cache recopié d'un autre Mac change d'identité et se prépare).

### 3.3 Fichiers et formats

Sous `<cache>` = `MESA_KK_PIPELINE_CACHE` = `~/Library/Application Support/Cidre/vkd3d-cache/<id>` :

| Fichier | Écrit par | Format |
|---|---|---|
| `base-pipelines/pipelines.bin` | KK (0444) en jeu | `{u32 "KKP1", u32 taille, charge}` ; la charge commence par la clé VS (32) puis la clé FS (32) |
| `base-pipelines/{nuanceurs,fonctions}.bin`, `env.txt` | KK (0444) en jeu | lus par KK au rejeu ; `env.txt` réécrit à chaque partie |
| `liste-chaude-kk.bin` | KK (0441) en jeu | clés de 32 octets bout à bout, ajout seul |
| `rejoues-prep-<identité>.bin` | KK au rejeu (`CIDRE_REJEU_JOURNAL`), lot par lot ; `noter` à la sortie du jeu | clés VS de 32 octets : **faits** pour cette identité |
| `preparation/echecs-<identité>.bin` | `preparer` après un rejeu complet | clés VS que KK n'a pas pu rejouer (échec, ou base d'un autre Mesa : « illisibles ») : pas retentées |
| `preparation/identite` | `preparer` | empreinte (dylib, Mac, build) puis identité, puis `oui/non` (le pilote sait-il rejouer dans un journal nommé) |
| `preparation/chaud` | `evaluer` | tampon : identité et tailles de la liste, de la base, du journal, des échecs au dernier compte nul |
| `preparation/adoption` | `evaluer`, une fois | issue de la première rencontre (§ 3.5) |
| `preparation/journal.txt` | `preparer` | déroulé et sortie du rejeu (stderr de KK) |
| `kk_pipelines.*.mtl4archive.index` | KK (0496) à chaque archive | paires VS/FS de l'archive (§ 12) |
| `preparation/index-<identité>`, `archives-sans-index/`, `rejoues-prep-<identité>.bin.sans-index` | `evaluer` (0496, une fois) | archives sans index mises de côté et journal d'avant ; effacés quand une préparation finit |
| `preparation/verrou/`, `preparation/passer`, `preparation/travail.<pid>/` | `preparer` | transitoires ; `travail` = base filtrée (`pipelines.bin` + liens vers `nuanceurs.bin`/`fonctions.bin`) |

Sélection (`prepa-shaders compter|filtrer`) : un enregistrement de la base est **connu** si sa clé VS **ou** FS
est dans la liste chaude (KK note chaque nuanceur lié, VS et FS ; la clé VS couvre la paire) ; il est **à faire**
s'il est connu et que sa clé VS n'est ni dans le journal ni dans les échecs de l'identité.

### 3.4 Rejeu

- Environnement : celui de la dernière partie (`env.txt`, la clé du cache disque contient les options), moins
  les dossiers et ce qui ne vaut qu'en jeu (`MESA_KK_PIPELINE_CACHE`, `MESA_KK_AIR_LOCAL`, `MESA_KK_PRECOMPIL`,
  `MESA_SHADER_CACHE_DIR`, `CIDRE_BASE_PIPELINES`, `CIDRE_LISTE_CHAUDE`, `CIDRE_COMPILE_FOND`, `CIDRE_FOND_*`,
  `CIDRE_REJEU*`, `CIDRE_BANC_*`, `CIDRE_COMPILE_DIFFEREE`) ; toutes les autres variables `CIDRE_*`/`MESA_*` du
  shell sont retirées. Puis : `CIDRE_REJEU=<travail>`, `CIDRE_REJEU_JOURNAL=rejoues-prep-<identité>.bin`,
  `CIDRE_REJEU_LOT`, `CIDRE_COMPILE_DIFFEREE=<cœurs>`, `CIDRE_REJEU_QOS_HAUTE=1`, `MESA_KK_COMPILE_STATS=1`,
  `MESA_KK_PIPELINE_CACHE=<cache>`, la réserve d'AIR de l'identité (`precompil_kk.sh air_local`) et le paquet
  téléchargé s'il y en a un (`precompil_kk.sh dossier`), `DYLD_FALLBACK_LIBRARY_PATH` du runtime.
- KK écrit au cache disque (0430), à la réserve d'AIR (0171), à l'archive Metal (0472, un fichier par lot) et,
  après l'archive de chaque lot, au journal : une interruption ne marque jamais fait un pipeline absent de l'archive.
- Lots : `ceil(N/10)` bornés à [50, 1 000] (une archive de ~10 000 pipelines est refusée par macOS 27) : une
  dizaine de pas d'avancement et d'archives au plus.
- Fin : `kk: rejeu fini en … : L lances, R reussis, E echecs, …` dans `journal.txt` ; ce qui n'est pas au journal
  va aux échecs.

### 3.5 Tenir le journal à jour sans rien compiler deux fois

- **À la sortie du jeu** (`lancer_depuis_steam.sh`) : `noter <id> <taille de la liste au lancement>` — les
  enregistrements de la base dont le VS ou le FS a été ajouté à la liste pendant la partie ont été compilés par
  le jeu lui-même sous cette identité : leur clé VS va au journal. Vaut aussi pour un jeu lancé depuis le client
  Steam (pas de préparation, mais le journal suit).
- **Première rencontre** d'un jeu (une fois, `preparation/adoption`) : si `etat_shaders.sh` dit `en_cache` (même
  macOS, même Mac, même Cidre qu'à la dernière partie, assez de jeu), la liste actuelle est adoptée (tout noté
  fait) ; sinon tout ce qui a été lié est à préparer.
- **Cache disque vidé** : si `env.txt` dit `CIDRE_CACHE_DISQUE` et que `<cache>/mesa` n'existe plus, le journal
  de l'identité est mis de côté (`.perime`) : tout est à refaire.

### 3.6 Passer, Ctrl-C, annulation

- `cidre preparation <id> passer` (bouton Passer de Verger) pose `preparation/passer` ; la boucle le voit en
  0,5 s, tue le rejeu, écrit `passee` et rend 0 : `cidre play` lance le jeu. Ce qui est au journal reste fait.
- Ctrl-C au terminal : `cidre play` piège INT le temps de la préparation (le rejeu, tâche de fond d'un shell non
  interactif, ignore INT ; c'est le script qui le tue) : même effet que Passer.
- `cidre play` tué (Verger annule le lancement : SIGTERM au seul `sh cidre`) : la préparation voit son parent
  disparu, tue le rejeu et sort ; rien ne survit.
- Un jeu déjà en cours (`en-cours/<id>` vivant) : pas de préparation. Deux préparations du même jeu : verrou.

### 3.7 Coût nul si tout est chaud

Sans base : deux `stat` (8 ms). Avec base, tampon posé : ~0,06 s (base et liste de D4). Sans tampon (la liste a
grandi) : un compte en C (~0,1 s à 0,7 s à froid pour 27 424 enregistrements), puis tampon. Aucun processus de
KosmicKrisp, aucun événement JSON.

## 4. Interfaces

```
cidre preparation <id> [--json]          prepare comme avant un lancement
cidre preparation <id> etat [--json]     {"etat":"inactive"|"chaude"|"a_preparer","raison":…,"a_faire","connus","identite"}
cidre preparation <id> passer            arrete la preparation en cours
```

Raisons d'`inactive` : `sans_base`, `sans_liste`, `option`, `pilote` (dylib introuvable, sans clé, ou sans
`CIDRE_REJEU_JOURNAL`), `en_cours`, `outil`, `illisible`.

Événements de `cidre play --json` (et de `cidre preparation --json`), avant `{"evenement":"lancement"}` :

```
{"evenement":"preparation","etat":"debut","fait":0,"total":1719}
{"evenement":"preparation","etat":"en_cours","fait":172,"total":1719}
…
{"evenement":"preparation","etat":"finie","fait":1719,"total":1719,"echecs":0,"duree":17}
   ou "passee" (fait partiel) ou "echouee" (le jeu compilera lui-même)
```

Options : `preparation_shaders = true|false` (fiche, `profils.toml`, `cidre set <id> preparation_shaders false`) ;
`CIDRE_PREPARATION_SHADERS=0|1` (un lancement) ; `CIDRE_PREPARATION_FILS=<n>`. Essais : `CIDRE_KK_DYLIB`,
`CIDRE_PRECOMPIL_FAMILLE`, `CIDRE_PREPARATION_MACOS`, `CIDRE_PREPARATION_OUTIL`. La préparation suit aussi
`cache_pipelines = false` / `CIDRE_PIPELINE_CACHE=0` (pas de cache : rien à préparer).

## 5. Quels jeux

Aujourd'hui, seuls les jeux dont la fiche note la base **et** la liste chaude : `compilation_kk` avec
`base_pipelines` (0444, qui exige aussi `frontal_differe` et `compile_differee`) et `fond` (0441, qui exige
`pipeline_paresseux`). C'est le cas de **Diablo IV** (`bnet-fen`). Pour les autres jeux KK, la préparation reste
inactive (`sans_base`) sans aucun coût.

Généraliser demande un petit correctif de KosmicKrisp, **décrit ici seulement, ni écrit en .patch ni construit** (aucune
reconstruction de Mesa pendant la partie du joueur) :

- *liste chaude sans fond* : dans `kk_fond_init` (0441), appeler `kk_chaud_charger(device)` avant le
  `return` des cas `n == 0 || !kk_paresseux()` quand `CIDRE_LISTE_CHAUDE` est posée (chemin, ou `1` pour
  `<cache>/liste-chaude-kk.bin`) ; `kk_bind_mesurer` note déjà dès que `kk_chaud_actif`. Coût en jeu : une
  recherche dans un ensemble et, la première fois, un `write` de 32 octets par nuanceur lié ;
- *base sans frontal différé* : `kk_base_noter` (0444) lit l'état gardé par le travail frontal (`lazy_job`) ;
  sans 0431 il faudrait garder une copie de l'état à la création du pipeline. Plus lourd, à mesurer.

Le lanceur poserait alors `CIDRE_LISTE_CHAUDE` et `CIDRE_BASE_PIPELINES` pour tout jeu D3D12/Vulkan.

## 6. Articulation avec `cidre precompil`

- **Premier lancement sur ce Mac** : les paquets téléchargés (`cidre precompil`, fin de `cidre dl`) apportent l'AIR
  de la famille et l'archive de l'architecture et du macOS ; rien à préparer localement (pas encore de base ni de
  liste).
- **Lancements suivants, mise à jour de KosmicKrisp (nouvelle clé), de macOS, cache vidé** : préparation locale,
  à partir de ce que ce joueur a réellement lié. Le rejeu consulte le paquet installé (`MESA_KK_PRECOMPIL`) : une
  bibliothèque dont l'AIR est livré n'est pas recompilée depuis le MSL.
- Plus tard : une liste chaude (et une base) distribuées avec les paquets permettraient de préparer dès le premier
  lancement ce que les autres joueurs ont lié. Non fait.

## 7. Verger

Le dépôt de Verger n'a pas pu recevoir de branche depuis cette session (les commandes git hors du worktree de
Cidre sont refusées) : le travail est dans **`~/Dev/verger-prepa-shaders`** (copie de `~/Dev/verger` à son HEAD,
avec son `.git`, sources modifiées non commitées) et en rustine **`verger/0001-preparation-des-shaders.patch`**
(`git apply` depuis la racine de Verger ; aussi copiée dans `~/Dev/verger-prepa-shaders/`). À faire :
`git -C ~/Dev/verger worktree add ../verger-prepa-shaders-b -b preparation-shaders && git -C ~/Dev/verger-prepa-shaders-b apply <rustine>`, puis commit. Ne pas taguer.

- `CidreBridge/Game.swift` : `ShaderPreparation` (etat, fait, total, echecs, duree ; état inconnu toléré),
  `PlayEvent.preparation`, analyse de `"preparation"`.
- `CidreBridge/CidreCLI.swift` : `skipShaderPreparation(id:)` → `cidre preparation <id> passer`.
- `Library/LibraryModel.swift` : `preparations` par jeu (avant le test d'appid : un jeu Battle.net n'en a pas),
  fermées à `finie|passee|echouee`, au `lancement` et à la fin de la commande ; `skipPreparation`.
- `Library/ShaderPreparationSheet.swift` : feuille « Préparation des shaders », barre `fait sur total`, bouton
  Passer (« Lancement… » une fois demandé), non fermable autrement.
- `Library/LibraryView.swift` : la feuille. `Resources/en.lproj` : 6 textes (`Scripts/chaines.py` : 0 sans
  traduction). `Tests/CidreBridgeTests/ShaderPreparationTests.swift` : 4 tests.
- Construit et testé hors jeu (`swift build`, `swift test` : tout passe, dont les 4 nouveaux).

## 8. Essais faits (hors jeu)

- `tests/tester_preparation_shaders.sh` : 50/50 — états inactifs (sans base, sans liste, option, pilote sans
  journal nommé, jeu en cours), compte (VS ou FS liés), identité, préparation `--json` (ordre, sortie standard
  pure, journal, environnement du rejeu nettoyé, valeur à espace, fils, lots, base filtrée), relance sans
  événement, 5 relances < 3 s, `noter` après une partie, nouvelle clé KK, échec noté et non retenté, nouveau
  build de macOS, cache disque vidé, Passer (code 0, partiel, rejeu tué, nettoyage, reste à faire), parent tué,
  adoption, outil construit à la demande sans en-têtes Vulkan, `cidre preparation etat --json`, `cidre play --json`
  (shaders → preparation → lancement, sortie standard pure, le jeu part, rien au lancement suivant), `cidre help`,
  `cidre set preparation_shaders`.
- Non-régression : `tester_maj_avant_lancement` 202/202, `tester_battlenet` 198/198, `tester_lancement_steam`
  77/77, `tester_etat_shaders_vulkan` 8/8, `tester_profils` 518/518 (après régénération de `profils/index.toml`,
  périmé depuis 0495).
- Avec le vrai KosmicKrisp (kk-0494, `KK_CODEGEN=1-fe23de315cfc449d`), base de D4 lue par liens, tout le reste
  dans un brouillon effacé : 3 pipelines → 3/3 en 5 s (dont ~3,5 s de démarrage : index de 23 917 nuanceurs) ;
  la liste chaude entière de D4 (1 719 pipelines liés) → 1 719/1 719 en **17,8 s** sur le M1 Max, 10 fils,
  0 échec ; relance chaude : 0,06 s.

## 9. Ce qui reste à valider en jeu

1. **Le gain** : D4 avec une nouvelle clé KK (ou cache disque vidé), préparation faite, puis menu et monde :
   `MESA_KK_COMPILE_STATS` (« relus », attentes au bind, « from archives ») et sauts > 250 ms, contre la même
   partie sans préparation (`CIDRE_PREPARATION_SHADERS=0`). Attendu d'après 0444 : attentes au bind 86-175 ms
   contre 9,8 s.
2. **`env.txt` = options du prochain lancement** : la préparation rejoue avec les options de la *dernière* partie ;
   une fiche changée entre-temps peut changer la clé du cache disque et rendre le rejeu inutile une fois.
3. **`noter`** : que tout nuanceur lié en jeu est bien écrit au cache disque sous la clé courante (frontal différé
   0431) et que VS et FS arrivent dans la liste ; sinon `noter` marquerait fait un pipeline froid.
4. **Archives par lot** : une dizaine de fichiers `kk_pipelines.<pid>.<n>.mtl4archive` de plus par préparation :
   effet sur la recherche d'archives au démarrage (0101 : de la plus grosse à la plus petite).
5. **Variantes notées (0471)** : le rejeu les construit-il avec `CIDRE_VARIANTES` repris d'`env.txt` ?
6. **Battle.net** : préparation avant l'ouverture du client ; vérifier que rien dans `battlenet.sh` ne s'en
   ressent (délai de connexion, code 7).
7. **Verger** : la feuille avec un vrai lancement, Passer pendant un lot, annulation du lancement.
8. **M4 / apple8** : une base faite sur le M1 rejouée sur le M4 (0444 : « telle quelle ») sous une identité apple8.
9. **Passer répété** : un pipeline non fait et déjà dans la liste n'est pas re-noté par KK quand le jeu le compile ;
   il est donc re-préparé au lancement suivant (une fois). À surveiller si les joueurs passent souvent.
10. **Base d'un autre Mesa** (signature des structures, 0444) : ses enregistrements sont « illisibles », notés en
    échec ; KK ne les réécrit pas (clé VS déjà connue). Si cela arrive, mettre la base de côté pour qu'elle se
    refasse (à automatiser : base entièrement illisible → renommée).

## 10. Mode « tout » (16/11)

Constat du joueur (D4, 1.5.23 candidate) : fluide là où il est déjà passé, saccades à chaque zone neuve. La
liste chaude ne couvre que ce qui a déjà été lié ; les pipelines d'une zone jamais vue sont dans la base (créés au
chargement) mais froids. Le mode « tout » prépare **toute la base**, toujours **avant** la partie (la règle de 0492
tient : rien pendant la partie).

- Fiche : `preparation_shaders = "tout"` (`true` = liés seulement, défaut ; `false` = rien) ; `cidre set <id>
  preparation_shaders tout` ; un lancement : `CIDRE_PREPARATION_SHADERS=tout` (ou `lies`, `0`, `1` = mode de la fiche).
  **`profils/bnet-fen.toml` passe à `"tout"`.**
- Outil : `prepa-shaders compter|filtrer <base> - …` (liste « - » = toute la base). Pas besoin de liste chaude.
  Même journal par identité (`rejoues-prep-<identité>.bin`) : passer de `lies` à `tout` ne refait pas ce qui est
  fait ; un pipeline créé dans une partie suivante (zone neuve, saison) est préparé au lancement suivant.
- `etat` dit le mode (`mode=`, `"mode"` en JSON) ; le tampon « chaud » le contient.

### Mesures (M1 Max 10 cœurs, macOS 26.5.2 25F84, kk-0494 du candidat `KK_CODEGEN=1-fe23de315cfc449d`)

Copie de la base du joueur (16/11 17:46 : **22 061 pipelines**, 19 074 nuanceurs, 153 Mo) dans un dossier à part,
cache vide (ni Mesa, ni Metal, ni archives, ni AIR), environnement d'`env.txt` du candidat (NAN_STRICT=1, code_kk de
bnet-fen, AIR direct, cache de fonctions, variantes notées : 546).

| | 10 fils (défaut) | 6 fils |
|---|---|---|
| durée totale | **211 s** (rejeu 208,8 s) | 246 s |
| réussis / échecs | 22 061 / 0 | 22 061 / 0 |
| processeur du rejeu | 306 s util. + 50 s sys. | 281 + 42 s |
| charge (loadavg 1 min) | 12 à 19 | 19 à 21 |
| RSS max | 0,70 Go | 0,61 Go |

La compilation Metal se fait surtout dans `MTLCompilerService` (hors du processus) : réduire les fils de KK
allonge la durée sans soulager la machine. QoS user-interactive (le joueur attend devant l'écran).

Produit (Mo) : archives Metal 22 × ~40 = **~920** ; cache disque Mesa (0430) **~910** ; cache de fonctions Metal
(0451) **~800** ; cache de traduction NIR (0386) **~404** ; réserve d'AIR (0171) **~310** ; total **~3,3 Gio**
(+ la base, 153 Mo). Attention : le cache Mesa approche la borne par défaut de `MESA_SHADER_CACHE_MAX_SIZE` (1 Gio).

### Le jeu sert-il ce qui est préparé ?

Vérifié hors jeu par le banc du bind de KK (0464/0473, `CIDRE_BANC_BIND=300 CIDRE_BANC_RELUS=1
CIDRE_BANC_VARIANTES=1`, même dylib, même environnement) : chemin du jeu (nuanceurs relus du cache disque par la
clé Vulkan notée en jeu, bibliothèques paresseuses, variante de rendu au dessin) :

| cache | absents du cache | bind p50 / max | dessin (variante) moy. / max | pipelines Metal |
|---|---|---|---|---|
| préparé (tout) | **0 / 22 061** (44 122 nuanceurs relus) | 0,13 / 0,86 ms | 0,83 / 3,8 ms | **300 / 300 depuis les archives** |
| sans binaires Metal (Mesa + AIR seulement) | 0 | 0,44 / 2,2 ms | **55 / 284 ms** | 0 depuis les archives |
| archives sans cache de fonctions | 0 | 0,41 / 13,9 ms | 0,86 / 7,3 ms | 300 / 300 |

Les clés concordent (disque Mesa : identifiant 0208 calculé avec les options d'`env.txt` ; archive : 300/300
variantes dessinées = clé de préchauffage). Ce sont les binaires Metal (archives) qui suppriment les saccades.

### Réglages proposés

- Écran avant le **premier** lancement d'une identité (nouveau KK, nouveau macOS, cache vidé) : ~3,5 min sur M1 Max,
  à estimer ~6-7 min sur un M1 8 cœurs ; acceptable (Steam fait de même), avec Passer. Ensuite : seulement les
  pipelines nouveaux de la base (quelques secondes), rien si tout est chaud.
- Garder 10 fils (tous les cœurs) : 6 fils = +17 % de durée pour la même charge.
- Disque : ~3,3 Gio par jeu et par identité. À étudier : `CIDRE_AIR_LOCAL=0` pendant la préparation (310 Mo et
  27,7 s d'écriture d'AIR que l'AIR direct ne relit pas, 0385 — à vérifier en jeu), `MESA_SHADER_CACHE_MAX_SIZE=2G`
  pour D4 (sinon évictions), purge des archives d'une identité périmée (la clé KK change à chaque mise à jour du MSL).

## 11. Paquets par famille (0165) pour D4 — plan, rien de publié

Ce que chaque morceau vaut et ce qui en casse la clé :

| morceau | taille (zstd) | clé | sert à |
|---|---|---|---|
| base (`base-pipelines/`) | **~100 Mo** | format 0444 (`kk_base_signature`, NIR sérialisé) ≈ version de Mesa ; prudence : `KK_CODEGEN` | tout recompiler localement (« tout »), quelle que soit la machine |
| cache disque Mesa (0430) | ~806 Mo (déjà compressé) | `KK_CODEGEN` (version + empreinte des sources) **+ famille** (apple7/apple8) + macOS ≥ 27 + options `CIDRE_*` qui changent le code (NAN_STRICT, code_kk, AIR direct...) | supprime le frontal ; **ne supprime pas** la compilation Metal (55 ms/dessin) |
| archives Metal | ~287 Mo | architecture GPU exacte (g13g/g13s/g13c/g13d pour M1, g14x M2...) + **version majeure de macOS** + `KK_CODEGEN` (l'AIR change) | supprime les saccades (binaires) |
| réserve d'AIR (0171) | — | MSL + options | peu utile en AIR direct (0385) |
| cache de fonctions Metal, traduction | — | privés à la machine / au processus | à ne pas publier |

Ce qui casse : toute mise à jour de KosmicKrisp qui change `KK_CODEGEN` (tout), un macOS majeur (archives), une
option de fiche qui entre dans la clé 0208 (cache Mesa), une saison de D4 qui ajoute des pipelines (les nouveaux
restent froids : la préparation locale les rattrape).

Plan proposé :
1. **Publier la base** de D4 (~100 Mo, une par `KK_CODEGEN`, toutes familles) avec le runtime ou par `cidre precompil` :
   le premier lancement prépare « tout » localement (3,5 min M1 Max) sans avoir jamais joué. Le plus rentable :
   indépendant de l'architecture et de macOS.
2. Plus tard, pour les Mac les plus courants : **archives par architecture et macOS majeur** (~290 Mo chacune),
   faites par rejeu sur la machine de cette architecture (ou metal-tt depuis le script d'une archive, 0165) ;
   avec le cache Mesa de la famille (~800 Mo), le premier lancement serait chaud sans préparation. Coût : un paquet
   par (arch, macOS) à refaire à chaque `KK_CODEGEN` : à réserver aux versions stables.
3. Ne pas publier l'AIR, le cache de fonctions ni la traduction.

## 12. Micro-saccades apres la preparation « tout » : decomposition et 0496 (16/11)

Partie du joueur a 18:25 (1.5.23 candidate, preparation « tout » complete, 960 s, journal
`~/Dev/cidre-release-d4/journaux/partie-d4-prepa-tout-1816.log`). Sur le fil du jeu : attentes au bind 2,2 s
(max 258 ms) **et** variantes de rendu au dessin 4,4 s (752, max 53 ms) — les variantes pesaient plus que le bind.

| poste (fil du jeu) | mesure en jeu | cause |
|---|---|---|
| variantes au dessin : recherche dans les archives | 2 326 ms / 683 (3,4 ms) | 35 archives essayees l'une apres l'autre (8 vieilles + 27 lots de preparation), sous le verrou des archives que les fils kkvar tiennent aussi (12,6 s de recherche sur les autres fils) |
| variantes au dessin : relais MSL | ~1 500 ms | sur echec, 2e tour de toutes les archives avec les bibliotheques MSL (`newLibraryWithURL`) : 8 succes sur 577 (14,8 ms par relais rate) |
| binds « relus » (595 / 1 033 ms) | ~1,7 ms | `access()` de deux chemins AIR par bibliotheque pour le relais (« chemins relais » 9 989 ms sur tous les fils, 3,7 ms chacun en jeu), puis la bibliotheque (0,4 ms) |
| binds froids (60 / 1 179 ms, 20 ms chacun) | frontal au bind | (a) **817 pipelines neufs** (zone neuve : aucun de leurs nuanceurs dans la base ni jamais lie), dont 36 nuanceurs lies ; (b) **1 104 pipelines prepares absents du cache Mesa** (5 %, banc sur copie) : cache disque a la borne de 1 Gio (`index` : 1 023,7 Mio), chaque ecriture du rejeu ou du jeu en evince une autre |
| « jamais en file » 177 / 1 298 ms, « sur fond en cours » 258 / 577 ms | — | les memes binds, classes par l'etat du ticket de fond : froids et relus hors liste chaude |

Pointes > 50 ms : les variantes (max 52,8 ms) viennent de la file d'attente du verrou des archives (recherches de
35 archives par kkvar devant) ; les binds >= 100 ms (1) d'un frontal froid.

Correctif :
- **0496** (pont Metal seul, `KK_CODEGEN` inchange `1-fe23de315cfc449d`) : index par archive, une archive par
  recherche ; relais saute quand aucune archive ne peut l'aider ; chemins du relais sondes seulement au relais.
- **Preparation** : une fois par identite, les archives sans index sont mises de cote (`archives-sans-index/`,
  effacees a la fin de la preparation) et la preparation refaite (journal `.sans-index`) : chez le joueur
  ~1,5 min (87 s sur la copie : Mesa, AIR et cache de fonctions deja chauds) ; elle reecrit aussi les nuanceurs
  evinces du cache Mesa (0 absent apres) et prepare les 817 pipelines neufs de la derniere partie.
- **Cache Mesa borne a 4 Gio** (`MESA_SHADER_CACHE_MAX_SIZE=4G` si absent) pour le rejeu et pour le jeu
  (`cidre play`, `partir`). Un jeu lance depuis le client Steam sans `cidre play` garde 1 Gio : a poser dans le
  lanceur (`tests/lancer_depuis_steam.sh`, laisse a l'agent qui y travaille).

Banc du bind (M1 Max, copies APFS du cache du joueur, base de 22 061 pipelines, 300 binds relus + dessin de la
variante de prechauffage, passes entrelacees) :

| | dessins (300) | recherche archives | archives / recherche | binds (300) | chemins relais |
|---|---|---|---|---|---|
| kk-0495, cache du joueur (35 sans index) | 752 / 762 ms (max 11,6) | 677 / 681 ms | 12,2 | 257 / 288 ms | 149 ms |
| 0496, meme cache | 772 / 881 ms | 703 / 812 ms | 12,2 | 197 / 214 ms | 17 ms |
| 0496, cache re-prepare (23 indexees) | **138 / 148 / 277 ms** (max 2,9 / 5,0 / 30) | **129-155 ms** | **1,00** | **89-94 ms** | 4 ms |

Variantes absentes (3 de plus par paire, compilees) : recherche 1,3 s et 770 relais (1,1 s) avec kk-0495 ; 0,22 s
et 0 relais avec 0496 (index coupe : 1,0 s). Les binds plus courts du cache re-prepare viennent aussi d'un cache
plus chaud (la preparation venait de tourner) : gain du seul correctif sur le bind = chemins relais (-25 %).

Reste a valider en jeu : `KK compile: index des archives (0496)` ≈ 1 archive par recherche, relais sautes, « chemins
relais » ~0, variantes au dessin ~0,5-1 ms en moyenne, pointes ; attentes au bind froides restantes = pipelines
vraiment neufs (zone jamais vue : seule une base publiee, § 11, les couvrirait) ; premier lancement apres la mise a
jour : ecran de preparation ~1,5 min (re-preparation avec index).
