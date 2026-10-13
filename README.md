# Cidre

*English version [below](#cidre-in-english).*

Cidre fait tourner les jeux Windows de Steam sur un Mac Apple Silicon, en arm64
natif, sans Rosetta. C'est un assemblage de logiciels libres — FEX, Wine, DXVK,
DXMT, vkd3d-proton et le pilote Vulkan KosmicKrisp de Mesa — et des correctifs
qu'il a fallu leur apporter pour macOS.

Cidre est jeune : tous les jeux ne tournent pas, et la compatibilité se vérifie
jeu par jeu. Les jeux en ligne protégés par Easy Anti-Cheat ne marchent pas.

## Installer

La voie normale est [Verger](https://github.com/gtranche/verger), l'application
qui installe Cidre, le tient à jour et lance les jeux. Il faut un Mac Apple
Silicon sous macOS 26 ou plus récent et un compte Steam ; ni Homebrew ni
Terminal.

1. Installer le [client Steam](https://store.steampowered.com/about/) et s'y
   connecter.
2. Télécharger [Verger](https://github.com/gtranche/verger/releases/latest),
   puis clic droit → Ouvrir la première fois (l'application n'est pas notarisée
   par Apple).
3. Laisser Verger installer Cidre.

Le détail, l'installation en ligne de commande et la construction depuis les
sources : [INSTALL.md](INSTALL.md).

## Contribuer

- **Dire comment un jeu tourne chez toi.** Dans Verger, sur la page d'un jeu :
  « Partager mon résultat ». Verger prépare un rapport, tu le relis et tu le
  publies toi-même sur GitHub. Sans Verger : le formulaire
  [Rapport de jeu](https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml).
- **Proposer ou corriger la fiche d'un jeu.** Chaque jeu a une fiche,
  `profils/<appid>.toml` : ses options de lancement, et s'il marche.

La marche à suivre, et ce que devient un rapport :
[profils/CONTRIBUER.md](profils/CONTRIBUER.md). Le format des fiches :
[profils/README.md](profils/README.md).

## Dans ce dépôt

- `NNNN-*.patch` : les correctifs appliqués aux sources amont, numérotés.
- `profils/` : la base de fiches par jeu.
- `cidre` : la commande, et `tests/` : le lanceur, les scripts d'installation
  et les suites de tests.
- `outil-steam/` : l'outil de compatibilité pour Steam et les réglages livrés
  par défaut.

---

# Cidre in English

Cidre runs Windows games from Steam on Apple Silicon Macs, as native arm64,
without Rosetta. It is an assembly of free software — FEX, Wine, DXVK, DXMT,
vkd3d-proton and Mesa's KosmicKrisp Vulkan driver — plus the patches they
needed on macOS.

Cidre is young: not every game runs, and compatibility is checked game by game.
Online games protected by Easy Anti-Cheat do not work.

## Install

The normal way is [Verger](https://github.com/gtranche/verger), the app that
installs Cidre, keeps it up to date and launches the games. You need an Apple
Silicon Mac running macOS 26 or later and a Steam account; no Homebrew, no
Terminal.

1. Install the [Steam client](https://store.steampowered.com/about/) and sign
   in.
2. Download [Verger](https://github.com/gtranche/verger/releases/latest), then
   right-click → Open the first time (the app is not notarized by Apple).
3. Let Verger install Cidre.

Details, command-line installation and building from source:
[INSTALL.md](INSTALL.md) (in French).

## Contribute

- **Report how a game runs on your Mac.** In Verger, on a game's page: "Share
  My Result". Verger prepares a report; you review it and publish it yourself
  on GitHub. Without Verger: the
  [Rapport de jeu / Game report](https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml)
  form.
- **Propose or fix a game's profile.** Each game has a profile,
  `profils/<appid>.toml`: its launch options, and whether it works.

How to do it, and what happens to a report:
[profils/CONTRIBUER.md](profils/CONTRIBUER.md#contributing-to-the-game-profiles).
The profile format: [profils/README.md](profils/README.md) (in French).

## In this repository

- `NNNN-*.patch`: the numbered patches applied to the upstream sources.
- `profils/`: the per-game profiles.
- `cidre`: the command, and `tests/`: the launcher, the installation scripts
  and the test suites.
- `outil-steam/`: the Steam compatibility tool and the default settings.
