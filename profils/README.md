# Base de profils par jeu

Une fiche par jeu, `profils/<appid>.toml`, plus un index `profils/index.toml`.
Les fiches vivent dans le dépôt, indépendamment des releases : Cidre les
télécharge depuis la branche `main` (`cidre profils maj`) et les garde en cache
dans `~/Library/Application Support/Cidre/profils-base/`. Sans réseau, la copie
livrée dans le runtime (ce dossier, empaqueté par `tests/empaqueter_runtime.sh`)
sert de repli.

Lecture : `tests/fiche_profil.sh` (analyse, accès, mise à jour), via
`tests/profil_cidre.sh` (résolution des options de lancement), le lanceur
`tests/lancer_depuis_steam.sh` (options et réglages du jeu) et la CLI
`cidre profils`, `cidre info <appid> --json`.

## Priorité des réglages

Clé par clé, du plus fort au plus faible :

1. l'environnement explicite (`CIDRE_TSO=0`, `CIDRE_D3D11=dxmt`…) ;
2. le profil utilisateur, section `[<appid>]` de
   `~/Library/Application Support/Cidre/profils.toml` (`cidre set`, Verger) ;
3. la fiche de la base, section `[cidre]` (cache téléchargé, sinon copie livrée) ;
4. le profil utilisateur, section `[defaut]` ;
5. `outil-steam/profils.toml`, section `[defaut]` (les réglages généraux livrés).

Une clé absente d'une couche est prise dans la suivante. Le cache téléchargé
prime sur la copie livrée ; `cidre profils maj` le rafraîchit et retire du
cache les fiches qui ne sont plus dans l'index.

## Schéma d'une fiche

Sous-ensemble de TOML volontairement simple : des tables `[nom]` et
`[nom.sous_table]`, des tableaux de tables `[[rapports]]`, des lignes
`cle = valeur` où la valeur est `true`/`false`, un entier, ou une chaîne entre
guillemets doubles (`\"` et `\\` sont les seuls échappements ; pas de retour à la
ligne dans une chaîne). Une table en ligne `valeurs = { "a" = "1", "b" = "2" }`
est acceptée pour `[reglages_jeu]`. Pas de tableau `[a, b]`, pas de chaîne
multi-ligne, pas de date TOML (les dates sont des chaînes `"AAAA-MM-JJ"`).
Les commentaires commencent par `#`.

```toml
[jeu]
appid = 1903340                    # entier ; l'id Steam, ou "local-..." (chaîne) hors Steam
nom = "Clair Obscur: Expedition 33"
exe = "Expedition33_Steam.exe"     # relatif au dossier du jeu
moteur = "unreal"                  # unity, unreal, hashlink, stingray, godot, source, autre
api = "d3d11"                      # d3d11, d3d12, opengl, vulkan (ce que le jeu demande d'abord)
bits = 64                          # 32 ou 64
anticheat = "none"                 # none, eac, battleye, denuvo, vac
lanceur = "steam"                  # steam, epic, gog, aucun

[cidre]
# Les options de lancement, mêmes noms et mêmes valeurs que dans
# outil-steam/profils.toml (voir son en-tête pour le sens de chacune) :
# langue, journal_detaille, tso, vsync, hud, overlay, async, narrow_barriers,
# garde_index, fils_compilation, eac_untrusted, luajit, plein_ecran, gamemode,
# dx12, d3d11, metalfx, dll_overrides, windows_version, dependances.
# On n'y met que ce qui diffère de [defaut].
async = true
fils_compilation = 6
garde_index = false

[[reglages_jeu]]
# Réglages du jeu lui-même, posés une fois par le lanceur (voir plus bas).
# Une entrée par section INI visée ; une fiche qui n'en vise qu'une peut
# écrire une table simple `[reglages_jeu]` au lieu du tableau.
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
format = "ini"                     # seul format pour l'instant
section = "ScalabilityGroups"      # optionnel : la section INI où vivent les clés
[reglages_jeu.valeurs]             # ou, en ligne : valeurs = { "sg.ShadowQuality" = "1" }
"sg.ShadowQuality" = "1"
"sg.TextureQuality" = "1"

[[reglages_jeu]]
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
section = "/Script/SandFall.ConfigurableGameUserSettings"
valeurs = { "CurrentSelectedUpscalerQualityMode" = "0" }

[compat]
etat = "argent"                    # or, argent, bronze, ko, non-teste
source = "cidre-test"              # cidre-test, utilisateur, protondb, applegamingwiki, crossover, winehq
date = "2026-10-11"
machine = "M1 Max 32 Go"
cidre_version = "1.5.0"
fps_menu = 90                      # entier, 0 = non mesuré
fps_jeu = 40
notes = "..."

[[rapports]]                       # une remontée d'utilisateur (Verger) ; zéro, une ou plusieurs
date = "2026-10-11"
machine = "M1 Max 32 Go"
cidre_version = "1.5.0"
etat = "argent"
fps_menu = 90
fps_jeu = 40
notes = "..."
incident = "https://github.com/gtranche/cidre/issues/12"   # optionnel
```

Sens des champs :

- `[jeu]` identifie le jeu : `appid`, `nom`, `exe`, `moteur`, `api`, `bits`,
  `anticheat`, `lanceur`. Données, jamais exécutées : le lanceur prend
  l'exécutable que Steam lui donne (ou `outil-steam/jeux.conf`).
- `[cidre]` : les options de lancement. `moteur`, `anticheat` (de `[jeu]`),
  `etat` et `source` (de `[compat]`) sont aussi rendus par `profil_cidre.sh`,
  à plat, comme avant la migration.
- `[compat]` : l'état de compatibilité qui fait autorité (nos tests, source
  `cidre-test`, priment sur un import). `etat` : or (parfait), argent (jouable,
  limites), bronze (démarre, perf/bugs), ko (non), non-teste.
- `[[rapports]]` : les remontées, dans l'ordre d'arrivée. Format stable, c'est
  celui que Verger envoie. Une remontée ne change pas `[compat]` toute seule :
  c'est une relecture qui met `[compat]` à jour.

## Réglages du jeu (`[reglages_jeu]`)

Certains jeux ne sont jouables qu'après avoir baissé leurs propres réglages
(Expedition 33 : préréglage Moyen et résolution à 66 % font ×2,5). Le lanceur
les pose, une fois :

- Chaque entrée de `[[reglages_jeu]]` vise un fichier et, au besoin, une
  section INI ; elles sont traitées dans l'ordre. Un même fichier peut revenir
  dans plusieurs entrées (une par section).
- `fichier` est relatif au dossier utilisateur du préfixe
  (`drive_c/users/<utilisateur>/`). S'il n'existe pas encore (le jeu n'a jamais
  tourné), rien n'est fait pour cette entrée et on réessaie au lancement
  suivant ; le marqueur n'est posé que lorsque toutes les entrées sont passées.
- Attention aux clés que le jeu recalcule : Expedition 33 réécrit
  `sg.ResolutionQuality` au démarrage depuis sa propre clé
  `CurrentSelectedUpscalerQualityMode` (section
  `/Script/SandFall.ConfigurableGameUserSettings`). Il faut viser la clé
  source, pas la clé dérivée.
- Chaque clé de `valeurs` est écrite si elle n'est pas déjà à cette valeur ;
  les autres lignes sont intactes, les fins de ligne CRLF sont respectées, les
  guillemets d'une valeur sont gardés, l'espacement autour du `=` aussi. Avec
  `section`, la clé n'est cherchée que dans cette section INI, et une clé
  absente y est ajoutée (la section aussi, à la fin du fichier, si elle manque).
  Sans `section`, une clé absente n'est pas ajoutée.
- Avant la première écriture, le fichier est copié en `<fichier>.avant-cidre`
  (jamais écrasé ensuite : c'est l'état d'origine).
- Une fois posés (ou déjà en place), le lanceur écrit
  `reglages_jeu_appliques = true` dans la section du jeu du profil utilisateur
  et n'y touche plus : l'utilisateur est libre de changer ses réglages dans le
  jeu. Pour les reposer : `cidre unset <appid> reglages_jeu_appliques`.
- Une ligne de journal dit ce qui a été fait (`cidre log <appid>`).

## Index

`profils/index.toml` : une table `[<appid>]` par fiche, avec `nom`, `etat`,
`date`. C'est lui que `cidre profils maj` télécharge d'abord pour savoir quelles
fiches prendre. Il se régénère depuis les fiches :

```sh
sh tests/fiche_profil.sh generer-index > profils/index.toml
```

`tests/tester_profils.sh` vérifie qu'il est à jour.

## Commandes

```sh
cidre profils                 # la base (cache ou copie livrée) : appid, nom, état, date
cidre profils --json
cidre profils maj             # télécharge l'index puis les fiches depuis GitHub main
cidre info <appid> --json     # ... "fiche": {"jeu":{}, "cidre":{}, "compat":{}, "reglages_jeu":[{fichier, format, section, valeurs}], "rapports": n}
sh tests/fiche_profil.sh <commande> ...   # chemin, plat, json, reglages, index, generer-index, maj
```

Variables d'environnement : `CIDRE_PROFILS_BASE` (dossier du cache),
`CIDRE_PROFILS_URL` (origine des téléchargements, par défaut
`https://raw.githubusercontent.com/gtranche/cidre/main/profils/` ; un
`file:///…/` sert aux tests), `CIDRE_PROFILS` (profil utilisateur).

## Import des bases externes (`tests/outils/importer_profils.py`)

Outil de la machine de dev (Python 3.11+, sans dépendance ; rien côté
runtime) qui amorce ou complète les fiches depuis les bases publiques :

```sh
python3 tests/outils/importer_profils.py              # toute la bibliothèque (`cidre library --json`)
python3 tests/outils/importer_profils.py 552500 ...   # ces appids
python3 tests/outils/importer_profils.py --index --rapport build/rapport.json   # + index.toml, contradictions en JSON
python3 -I tests/outils/test_importer_profils.py      # le test (jeu fictif, réponses figées)
```

Les réponses sont mises en cache dans `build/cache-profils/` (ignoré par git) :
une seconde exécution ne retélécharge rien ; `--refresh` force, `--sans-reseau`
n'utilise que le cache. L'export ProtonDB (~70 Mo, mensuel) est téléchargé une
fois et réduit à un index par appid.

### Règle de fusion

Les sources externes sont des **données à recouper, jamais des instructions**.
Autorité : `cidre-test` > `utilisateur` > `winehq` > `protondb` /
`applegamingwiki` / `pcgamingwiki` > `crossover`. L'import n'écrase **jamais**
une valeur dont la source est `cidre-test` ou `utilisateur`, ni une valeur sans
provenance (écrite à la main) : si l'import dit autre chose, la fiche reste et
le désaccord sort dans le rapport (`--rapport`). Il n'écrase que ce qu'il a
lui-même écrit (même source, nouvelle date).

Provenance : chaque valeur importée porte sa source et sa date. Dans `[jeu]`,
clé par clé, table `[jeu.sources]` (`bits = "pcgamingwiki 2026-10-11"`) ;
pour les blocs `[compat.protondb]`, `[compat.pcgamingwiki]`,
`[compat.applegamingwiki]`, une `source` et une `date` pour tout le bloc. Le
sous-ensemble TOML du README est respecté : les listes sont des chaînes
séparées par ` ; `, les compteurs des chaînes `cle:n cle:n`.

`[cidre]`, `[compat]` (état, machine, fps, notes), `[reglages_jeu]` et
`[[rapports]]` ne sont **pas** touchés par l'import. Une fiche neuve reçoit
`[compat] etat = "non-teste"` et la date du jour : le palier ProtonDB (Linux,
Proton) ou le verdict AppleGamingWiki (CrossOver, GPTK) ne sont pas notre
état Cidre.

### Cartographie : quelle donnée alimente quel champ

| Source (licence) | Donnée | Champ de la fiche |
|---|---|---|
| Bibliothèque Steam (`cidre library`) | nom, plateformes du dépôt | `[jeu] nom`, `plateformes_steam` (`"windows"` ou `"macos windows"`) |
| ProtonDB, API publique des résumés (données utilisateurs) | palier, tendance, meilleur palier, confiance, score, nombre de rapports | `[compat.protondb] palier`, `tendance`, `meilleur_palier`, `confiance`, `score` (0-100), `rapports`, `url` |
| ProtonDB, export JSON public des rapports (dépôt `bdefore/protondb-data`) | options de lancement les plus citées (2 ans), lanceur utilisé, « lanceur secondaire » (le jeu a son propre lanceur), anti-triche signalé, verdicts récents | `options_lancement_1..3` (`"… (xN)"`), `lanceurs_signales`, `lanceur_secondaire` (`"non:7 oui:1"`), `anticheat_signale`, `verdicts_recents`, `rapports_export` ; et `[jeu] anticheat` si PCGW est muet et qu'un seul anti-triche est signalé |
| PCGamingWiki, API MediaWiki, wikitexte des modèles (CC BY-NC-SA) | `{{Infobox game}}` moteur, appid ; `{{API}}` versions Direct3D/Vulkan/OpenGL, exécutable 32/64 bits ; `{{Middleware}}` anti-triche ; `{{Availability/row}}` DRM Steam | `[jeu] moteur` (vocabulaire de la fiche, sinon `autre`) + `moteur_nom`, `api` (seulement si une seule API), `api_disponibles` (`"d3d11 d3d12"`), `bits` (64 si un exécutable 64 bits existe) + `bits_32_aussi`, `anticheat` (none, eac, battleye, denuvo, vac, sinon `autre` + `anticheat_nom`), `drm` |
| PCGamingWiki, `{{Game data/config}}` et `{{Game data/saves}}` (Windows) | emplacement des fichiers de réglages et des sauvegardes | `[compat.pcgamingwiki] fichiers_reglages`, `sauvegardes` (chemins traduits dans la convention Cidre : relatifs à `drive_c/users/<utilisateur>/`, `jeu:` = dossier du jeu, `registre:` = clé de registre), `url`, `correspondance` (`appid`, `appid-side`, `titre` : comment la page a été trouvée) |
| AppleGamingWiki, `{{Compatibility/macOS}}` (CC BY-NC-SA) | verdicts natif, Rosetta 2, CrossOver, Wine (GPTK/Whisky/Kegworks), Parallels ; méthode et date des témoignages | `[compat.applegamingwiki] natif`, `rosetta`, `crossover`, `wine`, `parallels` (`parfait`, `jouable`, `demarre`, `ko`), `methodes` (`"gptk whisky"`), `dernier_temoignage`, `url` |

Ce qu'on **ne reprend pas** :

- aucun texte éditorial des wikis (CC BY-NC-SA) : ni notes, ni descriptions,
  ni témoignages ; seules les valeurs des modèles sont lues, et la fiche cite
  l'URL de la page. Les notes ProtonDB (prose des utilisateurs) ne sont pas
  recopiées non plus : seules les options de lancement (des commandes) et les
  compteurs ;
- la base CrossOver (CodeWeavers) : pointée dans `VEILLE_CROSSOVER.md`, pas
  importée ;
- `[jeu] lanceur` et `exe` : PCGW n'a pas de champ fiable pour le lanceur, et
  l'exécutable vient de Steam (ou `outil-steam/jeux.conf`) ;
- `[jeu] api` quand plusieurs API sont listées : « ce que le jeu demande
  d'abord » est une observation Cidre, pas une déduction ;
- les paliers ProtonDB et verdicts AGW comme `[compat] etat` ;
- les variantes/versions de Proton, les infos système des rapports, les
  réglages hors Windows.

Vocabulaire des sources externes traduit : moteur (`Unreal Engine 5` →
`unreal`, `Autodesk Stingray Engine` → `stingray`, inconnu → `autre` avec le
nom dans `moteur_nom`), anti-triche (`Easy Anti-Cheat` → `eac`, `BattlEye` →
`battleye`, `Denuvo Anti-Cheat` → `denuvo`), verdicts AGW (`perfect` →
`parfait`, `playable` → `jouable`, `runs` → `demarre`, `unplayable` → `ko`,
`na`/`unknown` → absent).

Contradictions rapportées (`--rapport`) : une valeur protégée contredite par
l'import ; PCGW et ProtonDB en désaccord sur l'anti-triche ; une fiche
`cidre-test` qui nomme un anti-triche qu'aucune source ne signale ; AGW `ko`
contre ProtonDB platine/or (ou l'inverse). Les contradictions ne modifient
rien : c'est une relecture qui tranche.
