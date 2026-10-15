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
3. **Ouvrir sur GitHub** : le formulaire « Rapport de jeu » du dépôt s'ouvre,
   son titre et son champ « Rapport » déjà remplis. Tu relis, tu publies. Il
   faut un compte GitHub, et aucun droit sur le dépôt : le formulaire range
   lui-même l'incident sous le label `rapport-jeu`.

À savoir :

- L'incident est public. Verger a retiré du diagnostic ton nom de session, tes
  identifiants Steam, le nom de ton Mac et les adresses de courriel ; relis
  quand même avant d'envoyer.
- Ne change ni le titre (« Rapport de jeu : *nom* (*appid*) ») ni le bloc
  `[[rapports]]` : c'est ce qui est lu. Tu peux écrire ce que tu veux en dessous.
- Un « ne marche pas » est aussi utile qu'un « parfait ».
- Si GitHub te demande d'abord de te connecter, le formulaire revient rempli
  après la connexion. S'il arrive quand même vide : dans Verger, **Copier le
  rapport**, puis colle-le dans le champ « Rapport », à la place du modèle.
- Une adresse web ne porte que quelques kilo-octets. Verger coupe donc la fin du
  diagnostic et te montre le fichier complet, à glisser dans le champ si tu veux
  le joindre. Si le rapport lui-même est trop long (de très longues notes),
  Verger le copie et ouvre le formulaire avec le titre seul : colle-le de même.
- Il faut Verger 0.3.14 ou plus récent. Les versions d'avant ouvrent un incident
  hors formulaire, avec le label dans l'adresse : d'après la documentation de
  GitHub, la page ne s'ouvre alors (erreur 404) que pour qui a le droit de poser
  un label sur le dépôt.

Sans Verger : ouvrir le formulaire
[Rapport de jeu](https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml),
remplacer `NOM DU JEU` et `APPID` dans le titre (l'appid est le nombre dans
l'adresse de la page Steam du jeu) et remplir le bloc du champ « Rapport »
(`cidre status` donne la version ; les images par seconde non mesurées restent
à 0) :

````
```toml
[[rapports]]
date = "2026-10-13"
machine = "M1 Max 32 Go"
cidre_version = "1.5.10"
etat = "argent"
fps_menu = 90
fps_jeu = 40
notes = "Ce qui marche, ce qui coince."
```
````

Le formulaire envoyé tel quel (`etat = ""`) n'est pas un rapport : il est refusé
à la relecture.

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
   (ceux du label `rapport-jeu`, et par filet ceux dont le titre commence par
   « Rapport de jeu » ou dont le texte porte la balise de Verger) et rend, pour
   chacun, le bloc `[[rapports]]` prêt à coller, avec ce qui mérite un coup
   d'œil (valeur retouchée, doublon, nom qui ne correspond pas à l'appid,
   incident arrivé sans le label). Le diagnostic n'est pas recopié. Un rapport
   illisible reçoit une question dans son incident.
2. Relu, le bloc est ajouté à la fiche (`--appliquer --incident N`), avec
   l'adresse de l'incident dans `incident`. Un jeu sans fiche en reçoit une,
   minimale, à l'état `non-teste`. L'incident est fermé.
3. Un rapport seul ne change pas l'état du jeu. Quand deux machines différentes
   donnent le même état et qu'aucun autre état n'en réunit autant,
   `--proposer-compat` suggère le nouveau `[compat]` ; le mainteneur relit et
   tranche. Un `[compat]` issu de nos tests n'est jamais remplacé ainsi : le
   désaccord vaut demande de nouveau test. La même règle, famille de Mac par
   famille (M1, M2, M3 et M4…), suggère une entrée `[[compat.machines]]`
   quand un jeu se comporte autrement sur une famille (voir le README,
   « Compatibilité par famille de Mac »).
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
3. **Open on GitHub**: the repository's "Rapport de jeu / Game report" issue
   form opens, its title and its "Rapport" field already filled in. You review
   it and submit it. A GitHub account is required, and no permission on the
   repository: the form itself files the issue under the `rapport-jeu` label.

Good to know:

- The issue is public. Verger removed your macOS user name, your Steam
  identifiers, your Mac's name and e-mail addresses from the diagnostic; read
  it anyway before submitting.
- Do not change the title ("Rapport de jeu : *name* (*appid*)", always in
  French) nor the `[[rapports]]` block: that is what gets read. Write anything
  you like below it, in English if you prefer.
- "Does not work" is as useful as "Perfect".
- If GitHub asks you to sign in first, the form comes back filled in after you
  sign in. If it still comes up empty: in Verger, **Copy the Report**, then
  paste it into the "Rapport" field, replacing the template.
- A web address only carries a few kilobytes. Verger therefore cuts the end of
  the diagnostic and shows you the complete file, to drag into the field if you
  want to attach it. If the report itself is too long (very long notes), Verger
  copies it and opens the form with the title only: paste it the same way.
- Verger 0.3.14 or later is required. Earlier versions open an issue outside
  the form, with the label in the address: according to GitHub's
  documentation, that page only opens (404 error otherwise) for people allowed
  to set labels on the repository.

Without Verger: open the
[Rapport de jeu / Game report](https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml)
form, replace `NOM DU JEU` (the game's name) and `APPID` in the title (the
appid is the number in the game's Steam store URL) and fill in the block of the
"Rapport" field (`cidre status` prints the version; `etat` is one of `or`,
`argent`, `bronze`, `ko`; leave unmeasured frame rates at 0):

````
```toml
[[rapports]]
date = "2026-10-13"
machine = "M1 Max 32 Go"
cidre_version = "1.5.10"
etat = "argent"
fps_menu = 90
fps_jeu = 40
notes = "What works, what does not."
```
````

The form submitted as is (`etat = ""`) is not a report: it is rejected at
review.

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

1. `python3 -I tests/outils/rapports_vers_fiches.py` reads the open issues
   (those labelled `rapport-jeu` and, as a safety net, those whose title starts
   with "Rapport de jeu" or whose text carries Verger's tag) and prints, for
   each, the `[[rapports]]` block ready to paste, with whatever deserves a
   second look (edited value, duplicate, name that does not match the appid,
   issue that arrived without the label). The diagnostic is not copied. An
   unreadable report gets a question in its issue.
2. Once reviewed, the block is added to the profile
   (`--appliquer --incident N`), with the issue URL in `incident`. A game
   without a profile gets a minimal one, status `non-teste`. The issue is
   closed.
3. A single report does not change a game's status. When two different
   machines give the same status and no other status gathers as many,
   `--proposer-compat` suggests the new `[compat]`; the maintainer reviews and
   decides. A `[compat]` that comes from our own tests is never replaced this
   way: the disagreement is a request to test again. The same rule, one Mac
   family at a time (M1, M2, M3 and M4…), suggests a `[[compat.machines]]`
   entry when a game behaves differently on one family (see the README,
   "Compatibilité par famille de Mac").
4. Profiles land on `main`: `cidre profils maj` brings them to everyone,
   without waiting for a release.
