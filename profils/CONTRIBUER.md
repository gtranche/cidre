# Contribuer à la base de profils

*English version [below](#contributing-to-the-game-profiles).*

Chaque jeu a une fiche, `profils/<appid>.toml` (le schéma est dans le
[README](README.md)) : comment Cidre le lance, et s'il marche. Deux façons d'y
contribuer : dire comment un jeu tourne chez toi, ou proposer une fiche.

## Partager un résultat depuis Verger

Dans [Verger](https://github.com/gtranche/verger), sur la page d'un jeu lancé
par Cidre : **Partager mon résultat…** (Verger le propose aussi de lui-même
après une partie d'au moins dix minutes).

1. Choisir le verdict :

   | Dans Verger | Dans la fiche | Sens |
   |---|---|---|
   | Parfait | `or` | rien à redire |
   | Jouable avec des limites | `argent` | on y joue, avec des défauts ou des réglages baissés |
   | Démarre mais lent ou bogué | `bronze` | se lance, pas vraiment jouable |
   | Ne marche pas | `ko` | ne se lance pas, ou plante |

2. Si tu les as mesurées, les images par seconde au menu et en jeu. En notes :
   ce qui marche, ce qui coince, les options qui ont aidé.
3. **Ouvrir sur GitHub** : la page « nouvel incident » s'ouvre déjà remplie. Tu
   relis, tu publies. Il faut un compte GitHub.

À savoir :

- L'incident est public. Verger a retiré du diagnostic ton nom de session, tes
  identifiants Steam, le nom de ton Mac et les adresses de courriel ; relis
  quand même avant d'envoyer.
- Ne change ni le titre (« Rapport de jeu : *nom* (*appid*) ») ni le bloc
  `[[rapports]]` : c'est ce qui est lu. Tu peux écrire ce que tu veux en dessous.
- Un « ne marche pas » est aussi utile qu'un « parfait ».

Sans Verger : ouvrir un [incident](https://github.com/gtranche/cidre/issues/new)
avec ce titre, et ce bloc dans le texte (l'appid est le nombre dans l'adresse de
la page Steam du jeu ; `cidre status` donne la version) :

````
```toml
[[rapports]]
date = "2026-10-13"
machine = "M1 Max 32 Go"
cidre_version = "1.5.7"
etat = "argent"
fps_menu = 90
fps_jeu = 40
notes = "Ce qui marche, ce qui coince."
```
````

## Proposer une fiche ou une correction (pull request)

Format : une fiche par jeu, dans le sous-ensemble de TOML décrit par le
[README](README.md) (pas de tableau, pas de chaîne sur plusieurs lignes, dates
entre guillemets).

- `[cidre]` ne porte que les options qui diffèrent des réglages par défaut
  (`outil-steam/profils.toml`). Dis dans la pull request la mesure qui justifie
  chacune : machine, version de Cidre, images par seconde avant et après.
- `[[reglages_jeu]]` et `[[machine]]` : mesurer avant d'écrire, et lire les
  mises en garde du README (clés que le jeu recalcule, anciens runtimes).
- Aucun texte recopié de PCGamingWiki, d'AppleGamingWiki ou de ProtonDB.

Qui a le dernier mot (règle d'autorité) :

1. `[compat]` est l'état affiché à tout le monde. Seule une relecture du
   mainteneur le change. Nos propres tests (`source = "cidre-test"`) priment ;
   viennent ensuite les rapports d'utilisateurs qui concordent
   (`source = "utilisateur"`), puis les bases externes.
2. Ton résultat à toi va dans un `[[rapports]]`, à la suite des autres — pas
   dans `[compat]`.
3. Les blocs `[jeu.sources]`, `[compat.protondb]`, `[compat.pcgamingwiki]` et
   `[compat.applegamingwiki]` sont écrits par l'import : ne pas les retoucher,
   ils seraient réécrits.
4. Une valeur de `[jeu]` écrite à la main n'est jamais écrasée par l'import :
   corriger un moteur, une API ou un anti-triche faux est bienvenu, en disant
   d'où vient l'information.

Avant d'envoyer, sur un Mac, depuis la racine du dépôt :

```sh
sh tests/fiche_profil.sh generer-index > profils/index.toml   # fiche créée, ou nom, état, date changés
sh tests/tester_profils.sh                                    # tout doit être vert
python3 -I tests/outils/test_importer_profils.py              # seulement si tests/outils/ est touché
python3 -I tests/outils/test_rapports_vers_fiches.py
```

## Ce que le mainteneur fait d'un rapport

Rien n'est automatique : chaque rapport est relu.

1. `python3 -I tests/outils/rapports_vers_fiches.py` lit les incidents ouverts
   et rend, pour chacun, le bloc `[[rapports]]` prêt à coller, avec ce qui
   mérite un coup d'œil (valeur retouchée, doublon, nom qui ne correspond pas à
   l'appid). Le diagnostic n'est pas recopié. Un rapport illisible reçoit une
   question dans son incident.
2. Relu, le bloc est ajouté à la fiche (`--appliquer --incident N`), avec
   l'adresse de l'incident dans `incident`. Un jeu sans fiche en reçoit une,
   minimale, à l'état `non-teste`. L'incident est fermé.
3. Un rapport seul ne change pas l'état du jeu. Quand deux machines différentes
   donnent le même état et qu'aucun autre état n'en réunit autant,
   `--proposer-compat` suggère le nouveau `[compat]` ; le mainteneur relit et
   tranche. Un `[compat]` issu de nos tests n'est jamais remplacé ainsi : le
   désaccord vaut demande de nouveau test.
4. Les fiches partent sur `main` : `cidre profils maj` les apporte à tout le
   monde, sans attendre une release.

---

# Contributing to the game profiles

Each game has a profile, `profils/<appid>.toml` (schema in the
[README](README.md), in French): how Cidre launches it, and whether it works.
Two ways to help: report how a game runs on your Mac, or propose a profile.
File and key names are French; they are data, please keep them as they are.

## Share a result from Verger

In [Verger](https://github.com/gtranche/verger), on the page of a game launched
through Cidre: **Share My Result…** (Verger also offers it after a session of
ten minutes or more).

1. Pick the verdict:

   | In Verger | In the profile | Meaning |
   |---|---|---|
   | Perfect | `or` | nothing to report |
   | Playable with limits | `argent` | playable, with flaws or lowered settings |
   | Starts but slow or buggy | `bronze` | launches, not really playable |
   | Does not work | `ko` | does not launch, or crashes |

2. Frames per second in the menu and in game, if you measured them. In the
   notes: what works, what does not, which options helped.
3. **Open on GitHub**: the "new issue" page opens already filled in. You review
   it and submit it. A GitHub account is required.

Good to know:

- The issue is public. Verger removed your macOS user name, your Steam
  identifiers, your Mac's name and e-mail addresses from the diagnostic; read
  it anyway before submitting.
- Do not change the title ("Rapport de jeu : *name* (*appid*)", always in
  French) nor the `[[rapports]]` block: that is what gets read. Write anything
  you like below it, in English if you prefer.
- "Does not work" is as useful as "Perfect".

Without Verger: open an [issue](https://github.com/gtranche/cidre/issues/new)
with that title, and this block in the text (the appid is the number in the
game's Steam store URL; `cidre status` prints the version; `etat` is one of
`or`, `argent`, `bronze`, `ko`):

````
```toml
[[rapports]]
date = "2026-10-13"
machine = "M1 Max 32 Go"
cidre_version = "1.5.7"
etat = "argent"
fps_menu = 90
fps_jeu = 40
notes = "What works, what does not."
```
````

## Propose a profile or a fix (pull request)

Format: one profile per game, in the TOML subset described in the
[README](README.md) (no arrays, no multi-line strings, dates as quoted
strings).

- `[cidre]` only holds the options that differ from the defaults
  (`outil-steam/profils.toml`). State in the pull request the measurement that
  justifies each one: machine, Cidre version, frames per second before and
  after.
- `[[reglages_jeu]]` and `[[machine]]`: measure first, and read the README's
  warnings (keys the game recomputes, older runtimes).
- No text copied from PCGamingWiki, AppleGamingWiki or ProtonDB.

Who has the last word (authority rule):

1. `[compat]` is the status everybody sees. Only a maintainer review changes
   it. Our own tests (`source = "cidre-test"`) win; then concurring user
   reports (`source = "utilisateur"`); then external databases.
2. Your own result goes into a `[[rapports]]` block, after the existing ones —
   not into `[compat]`.
3. `[jeu.sources]`, `[compat.protondb]`, `[compat.pcgamingwiki]` and
   `[compat.applegamingwiki]` are written by the importer: do not edit them,
   they would be overwritten.
4. A hand-written `[jeu]` value is never overwritten by the importer: fixing a
   wrong engine, API or anti-cheat is welcome; say where the information comes
   from.

Before submitting, on a Mac, from the repository root:

```sh
sh tests/fiche_profil.sh generer-index > profils/index.toml   # new profile, or name, status, date changed
sh tests/tester_profils.sh                                    # everything must pass
python3 -I tests/outils/test_importer_profils.py              # only if tests/outils/ is touched
python3 -I tests/outils/test_rapports_vers_fiches.py
```

## What the maintainer does with a report

Nothing is automatic: every report is read.

1. `python3 -I tests/outils/rapports_vers_fiches.py` reads the open issues and
   prints, for each, the `[[rapports]]` block ready to paste, with whatever
   deserves a second look (edited value, duplicate, name that does not match
   the appid). The diagnostic is not copied. An unreadable report gets a
   question in its issue.
2. Once reviewed, the block is added to the profile
   (`--appliquer --incident N`), with the issue URL in `incident`. A game
   without a profile gets a minimal one, status `non-teste`. The issue is
   closed.
3. A single report does not change a game's status. When two different
   machines give the same status and no other status gathers as many,
   `--proposer-compat` suggests the new `[compat]`; the maintainer reviews and
   decides. A `[compat]` that comes from our own tests is never replaced this
   way: the disagreement is a request to test again.
4. Profiles land on `main`: `cidre profils maj` brings them to everyone,
   without waiting for a release.
