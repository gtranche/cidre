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

[reglages_jeu]
# Réglages du jeu lui-même, posés une fois par le lanceur (voir plus bas).
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
format = "ini"                     # seul format pour l'instant
section = "ScalabilityGroups"      # optionnel : la section INI où vivent les clés
[reglages_jeu.valeurs]             # ou, en ligne : valeurs = { "sg.ResolutionQuality" = "66" }
"sg.ResolutionQuality" = "66"
"sg.ShadowQuality" = "1"

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

- `fichier` est relatif au dossier utilisateur du préfixe
  (`drive_c/users/<utilisateur>/`). S'il n'existe pas encore (le jeu n'a jamais
  tourné), rien n'est fait et on réessaie au lancement suivant.
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
cidre info <appid> --json     # ... "fiche": {"jeu":{}, "cidre":{}, "compat":{}, "reglages_jeu":{}|null, "rapports": n}
sh tests/fiche_profil.sh <commande> ...   # chemin, plat, json, reglages, index, generer-index, maj
```

Variables d'environnement : `CIDRE_PROFILS_BASE` (dossier du cache),
`CIDRE_PROFILS_URL` (origine des téléchargements, par défaut
`https://raw.githubusercontent.com/gtranche/cidre/main/profils/` ; un
`file:///…/` sert aux tests), `CIDRE_PROFILS` (profil utilisateur).
