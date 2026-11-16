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
  qu'il crée au chargement. Sur la base de D4 : 27 424 pipelines notés, **1 719** liés.

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
