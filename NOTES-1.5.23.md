Runtime Cidre v1.5.23 (pile déjà compilée). Installation et mises à jour : par Verger, ou `sh installer_cidre.sh`.

Cette version apporte la pile de Diablo IV dans le produit. Elle ne change rien de visible pour les autres jeux, sauf
une recompilation des nuanceurs au premier lancement des jeux D3D12 (voir « Points connus »).

## Nouveautés

- **Diablo IV par Battle.net (`cidre play bnet-fen`)** : la pile des parties de développement des 08-11/11 entre
  dans le produit, sans leur instrumentation. Fiche `profils/bnet-fen.toml`.
  - **Îlot TSO** : le jeu tourne dans un vCPU de Hypervisor.framework, en TSO matériel, avec des sous-pages exactes de
    4 Kio. Correctifs Wine 0290-0294, 0301, 0355, 0462 et 0463 ; FEX 0292 et 0360. Seul l'exécutable du jeu y entre ;
    le client Battle.net tourne hors îlot et garde le TSO de FEX.
  - **Compilation des nuanceurs** :
    - Metal compile sur 8 fils ;
    - cache disque des nuanceurs, frontal différé, pipelines paresseux ;
    - file de fond avec liste chaude, base de pipelines, cache de fonctions Metal ;
    - variantes notées ;
    - correctifs KosmicKrisp 0430-0474, réglés par la fiche (`compilation_kk`, `compile_differee = 8`,
      `attente_present = "gpu"`).
  - **FEX : cache disque de blocs de Cidre** (0366-0493, `fex_disque`) et SMC en ligne validé par CRC (0370).
  - Mesuré en développement sur M1 Max : monde 28-42 img/s, 6,9 sauts de plus de 250 ms par 10 min. Le joueur l'a
    jugé « bien jouable ».
  - **Validé par `cidre play bnet-fen` avec le joueur le 18/11** : 26,5 min sans saccade ni gel, environ 30 img/s,
    sortie normale. Le Mac a été redémarré avant la partie, avec Steam fermé (voir « Points connus », mémoire).
  - **Préparation des nuanceurs avant la partie** : mode « tout » (`preparation_shaders = "tout"`) pour toute la base
    0444. Les zones déjà notées sont fluides dès la première visite ; le contenu jamais vu reste compilé en jeu.
  - **KosmicKrisp 0496** : un index par archive Metal ; une recherche de variante consulte une archive au lieu de 35.
    Cache disque Mesa porté à 4 Gio (à 1 Gio, il évinçait des nuanceurs préparés).
  - **KosmicKrisp 0498** : les variantes déjà connues sont reconstruites en priorité haute jusqu'à la fin de la liste,
    et la réserve AIR locale est indexée (9 s d'écritures inutiles évitées par partie).
  - **FEX 0497** : les garde-fous de l'îlot (0288/0289) suivent le TSO effectif, AppConfig compris ; le client
    Battle.net garde son TSO logiciel.
- **FEX 0491** : les champs masqués du cache disque sont relus sans faute. Cela supprime le gel au démarrage de D4
  (auto-blocage sous le verrou d'invalidation, introduit par 0480), sans relocation fautive.
- **FEX 0493** : les copies servies par le cache disque sont réemployées, et le tampon de code n'est vidé qu'une fois.
  En D4 : 33 vidages de 127 Mio par partie (environ 1 s chacun) deviennent 0, et la mémoire résidente baisse de
  110 Mio.
- **KosmicKrisp 0494, « relais économe »** : le relais d'archive MTL4 ne travaille que s'il y a des archives. En D4,
  bind et dessin coûtent 37 % de moins aux variantes, avec un rendu identique.
- **KosmicKrisp 0495** : les deux corrections des tuiles noires de D4 ne valent plus que pour D4 (option de fiche
  `nan_strict = true`, `CIDRE_NAN_STRICT=1`). Il s'agit des comparaisons NaN strictes de l'AIR direct (0440) et du
  select des txf sur poignée nulle (0402). Actives pour tous les jeux, elles coûtaient 4 % à Demonologist (M1 :
  38,6 → 37,0 img/s) ; avec 0495, il revient à parité (38,2 contre 38,2).

## Correctifs

- **Wine 0499, gel de Diablo IV en partie** : le fil principal du jeu mourait sans bruit après 1 à 24 min, et tout le
  jeu restait figé. Un rappel de procédure de fenêtre (souris) arrivé après que le fil avait rendu son vCPU partait
  hors de l'îlot. Le vCPU est désormais recréé pour le rappel. Le correctif apporte aussi deux sondes de diagnostic
  (fils bloqués, fin de fil), muettes sans `CIDRE_ILOT_BLOQUES` / `CIDRE_ILOT_XPROC`.
- **Gel de D4 au démarrage après une mise à jour du runtime** (e924f7c) : les renommages en attente de `wineboot -u`
  défaisaient l'alignement du préfixe sur l'îlot ; ils sont maintenant exécutés avant l'alignement.
- **Cache disque de FEX pour le seul jeu** (AppConfig) : dans l'environnement, il figeait le client Battle.net 32 bits.
- **KosmicKrisp 0492 « froids en fond » coupé par défaut** (`CIDRE_FOND_FROIDS=1` pour l'activer). En partie D4, le
  12/11, il compilait 4 691 pipelines froids en fond pour un seul servi au bind. Les fils de compilation saturaient
  le processeur : 51 sauts par 10 min au lieu de 6,9.

## Non-régression (M1 Max, 13/11, manches entrelacées 1.5.22 / 1.5.23, hors îlot)

| Jeu | Voie | 1.5.22 | 1.5.23 |
|---|---|---|---|
| PEAK | DXMT | 143,1 img/s | 143,4 |
| Dead Cells | DXMT i386 | 119,8 (vsync) | 119,8 |
| Demonologist | D3D12/KosmicKrisp | 38,2 (médiane 32,5) | 38,2 (32,5) avec 0495 |
| ELDEN RING | D3D12/KosmicKrisp, menu | 59,7 (vsync) | 59,7 |

186 manches de mesure et de robustesse, plus 548 manches ciblées sur les incidents. Détail dans le `RAPPORT.md` du
candidat, § 2.

## Points connus

- **Premier lancement des jeux D3D12 plus long** : la clé de code de KosmicKrisp change (`KK_CODEGEN=1-fe23de31`).
  Hors D4, 0495 change aussi les clés de cache. Les nuanceurs de chaque jeu sont donc recompilés une fois, puis le
  cache sert de nouveau.
- **PEAK peut tomber au démarrage, environ 1,5 % des lancements** : faute d'exécution dans le JIT Mono de Unity,
  sortie sur le code 5 ou écran figé sans image. Relancer le jeu suffit ; aucune sauvegarde n'est touchée. Ce défaut
  n'est pas nouveau : la 1.5.22 pure tombe aussi, avec la même signature (1 cas sur 193), et remettre le FEX, le
  ntdll ou le KosmicKrisp de la 1.5.22 dans cette version ne le fait pas disparaître. Le suivi continue hors release.
- **Arrêt forcé (`cidre stop`)** : un jeu tué pendant qu'il encode dans Metal peut laisser un rapport de plantage
  macOS. Exemples : `os_unfair_lock is corrupt`, ou « Command encoder released without endEncoding ». Le jeu était
  arrêté de toute façon, et la 1.5.22 le fait au même taux.
- **Diablo IV demande de la mémoire** : 14-15 Go au menu, 20-23 Go en jeu. Sur un Mac de 32 Go déjà en échange
  disque (applications ouvertes depuis longtemps, Steam), le jeu saccade puis peut se figer. Partir d'un Mac au swap
  vide et fermer Steam et Battle.net pour Mac. Limiter la mémoire graphique annoncée (6 Go) n'a pas aidé.
- **Client Battle.net : un rendu CEF 32 bits plante** (« Unhandled page fault » à 6CA129D8, fenêtre de `winedbg`).
  Sans effet sur le jeu ; 0497 ne le corrige pas, contrairement à ce qu'on pensait. Cause non trouvée.
- **Diablo IV : saccades à la première visite d'une zone jamais notée** (quelques pipelines compilés en jeu, environ
  0,5 s cumulé). Seule une base partagée entre joueurs les supprimerait.
- **Diablo II Resurrected** n'a pas été revalidé sur cette version.
- Validé hors jeu :
  - les séries s'appliquent sans flou sur des arbres neufs aux révisions figées (18/11 : mesa 138, wine11 75,
    FEX 65 dont 0488/0489 dans le sous-module External/rpmalloc) et `verifier_reconstruction.sh` les reproduit à
    l'identique. Le vérificateur n'extrayait pas les sous-modules (échec apparent de 0488/0489) et comptait les
    `.orig` d'un arbre de développement : corrigé. Construits sur ces arbres neufs, la dylib KK, ntdll.so et les deux
    DLL FEX portent exactement les marqueurs des binaires livrés (bb1f01e9, 4f0a4b26, d7fe0872, 40bff86c) ;
  - tests `tester_*` verts ;
  - marqueurs des correctifs vérifiés dans les binaires.

## Check-list de release (à suivre dans l'ordre ; rien n'a été tagué, poussé ni publié)

1. **Accord explicite du joueur** pour publier.
2. **Validation D4 avec le joueur** : `cidre play bnet-fen` depuis le runtime du candidat, sans l'installer. Au journal,
   vérifier :
   - `ilot : Diablo IV.exe dans l'ilot` ;
   - `[CIDRE_ILOT] actif … verrous-0462 seuil-0463` ;
   - la ligne `kk : … COMPILE_DIFFEREE=8 … NAN_STRICT=1 … VARIANTES=notees` ;
   - le cache disque FEX à 256 Mio et le SMC chaud à 64.

   Ensuite : aucune tuile noire à l'écran de sélection du personnage, et des sauts comparables à `partie_combo.sh`.
3. **Archive à refaire avec la version définitive**, depuis le commit de la branche (`6286ee3`). L'archive actuelle
   (`1.5.23-d4rc3`) porte les binaires de cette version. Ses 1 317 scripts et fiches sont ceux de `1621681` : ils ne
   diffèrent que par `profils/index.toml`, dont l'empreinte de bnet-fen est périmée. Ne pas avancer le depot pendant
   une série qui l'utilise.

   ```sh
   cd ~/Dev/cidre-release-d4/depot && git merge --ff-only release-1.5.23
   CIDRE_VERSION=1.5.23 sh tests/empaqueter_runtime.sh ~/Dev/cidre-release-d4/cidre-runtime.tar.zst
   shasum -a 256 ~/Dev/cidre-release-d4/cidre-runtime.tar.zst ~/Dev/cidre-release-d4/cidre-runtime.tar.xz > ~/Dev/cidre-release-d4/SHA256SUMS
   ```

   Les binaires n'ont pas à être reconstruits : aucune source de Wine, FEX ou KosmicKrisp n'a changé. La compression
   est lourde : jamais pendant une manche.
4. **Marqueurs dans l'archive** :
   - `strings` sur le pilote KK : `KK_CODEGEN=1-fe23de315cfc449d` et `CIDRE_NAN_STRICT` ;
   - `xtajit64.dll` : « cache de code vide » et « 0493 » ;
   - `ntdll.so` : « garde controlee », « verrous-0462 » et « seuil-0463 » ;
   - `wine/ilot/ilot.manifeste` présent ;
   - `kk-msl.txt` = `1-fe23de315cfc449d` ;
   - `VERSION` = `1.5.23`.

   Outil : `~/Dev/cidre-release-d4/outil/marqueurs.sh`, qui compte les chaînes de chaque correctif dans le candidat
   et dans la 1.5.22.
5. **Vérifier `SHA256SUMS`** contre les deux archives.
6. **Branche** : avance rapide de `main` sur `release-1.5.23` (la branche contient main), puis tag `v1.5.23`.
7. **Publication** : `tests/publier_release.sh`, avec les deux archives et ces notes. Le push de `main` (chemins
   `profils/**`) relance `.github/workflows/profils.yml`, qui republie `profils-base.tar.gz` avec `nan_strict` pour
   bnet-fen. Sinon : `gh workflow run profils.yml -f publier=true`.
8. **Après publication** :
   - `cidre profils maj` sur une machine ;
   - `sh tests/fiche_profil.sh plat bnet-fen | grep nan_strict` doit donner `nan_strict = true` ;
   - mise à jour par Verger sur le M4.
