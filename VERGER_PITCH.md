# Verger — pitch

> **À déplacer dans son propre dépôt** (`gtranche/verger`). Ce fichier vit temporairement dans le dépôt Cidre, le temps de démarrer. Verger et Cidre restent deux projets séparés (voir « Pourquoi un dépôt séparé »).

## En une phrase

**Verger** est l'interface graphique macOS qui pilote **Cidre** : ta bibliothèque de jeux, où tu installes, règles et lances tes jeux Windows (via Cidre) comme tes jeux natifs — sans jamais toucher à la console Steam ni à une ligne de commande.

Cidre = le moteur (FEX + Wine + DXVK + KosmicKrisp). Verger = le verger où poussent les jeux : la vitrine, le catalogue, les réglages, le bouton « Jouer ».

## Pourquoi un dépôt séparé (le point qui commande tout)

Le runtime Cidre pèse des **gigas** (Wine arm64, Mesa/KosmicKrisp, DXVK, FEX…). L'UI, elle, change **souvent** et pèse **quelques Mo**. Les mélanger obligerait à re-pousser / re-télécharger tout le runtime à chaque correction d'un bouton.

→ **Verger est un dépôt et un binaire indépendants.** Il ne contient aucun binaire de runtime. Il **détecte / installe / met à jour Cidre séparément**. On peut patcher l'UI 10 fois par jour sans que personne ne retélécharge un seul octet de Wine.

Conséquence d'archi : la frontière Verger ↔ Cidre est un **contrat stable** (la CLI `cidre`), pas un couplage de code.

## Le contrat Verger ↔ Cidre (la CLI)

Verger ne réimplémente rien : il appelle la CLI `cidre` et lit/écrit des fichiers de config que `cidre` consomme.

| Besoin UI | Commande Cidre |
|---|---|
| Lister les jeux (plateforme, mode, installé ?) | `cidre list` (prévoir une sortie `--json`) |
| Télécharger un jeu Windows hors client | `cidre dl <appid> [windows\|macos]` |
| Lancer un jeu | `cidre play <appid>` |
| Sauvegardes (iCloud) | `cidre sync <appid\|all> [backup\|restore]` |
| (futur) Désinstaller | `cidre rm <appid>` |

**Action pour Cidre :** ajouter `cidre list --json` et un `cidre info <appid> --json` (plateforme, taille, chemin, options actives) pour que Verger parse proprement au lieu de scraper du texte.

## Fonctionnalités

### 1. Bibliothèque (le verger)
Grille des jeux possédés / installés, avec pour chacun : jaquette, plateforme (**natif** vs **Cidre/Windows**), état (installé / à télécharger / MAJ dispo), taille, dernier lancement. Bouton **Installer** (`cidre dl`) et **Jouer** (`cidre play`).

### 2. Options de lancement par jeu  ← demande explicite
Un panneau de réglages **par jeu**, avec des interrupteurs pour **activer/désactiver des fonctionnalités**. Chaque interrupteur mappe une variable que `cidre play` lit déjà :

| Réglage UI | Variable / arg Cidre | Effet |
|---|---|---|
| Perf CPU (ordre mémoire relâché) | `CIDRE_TSO=0` (`FEX_TSOENABLED`) | gros gain CPU, risque de course — **off par défaut** |
| Vsync | `CIDRE_VSYNC=0` (`dxgi.syncInterval=0`) | enlève le plafond vblank (40→84 fps mesuré DREDGE) |
| HUD fps/GPU | `CIDRE_HUD=1` (`DXVK_HUD`, `MTL_HUD`) | overlay de perf pour régler |
| Compilation shaders async | `DXVK_ASYNC=1` + `numCompilerThreads` | tue le stutter (ex. VT2) |
| Anti-triche permissif | `-eac-untrusted` | realm Modded (EAC = mur en ligne) |
| Correctif LuaJIT | `PROTON_OUVERT_LUAJIT=1` | requis VT2 |
| Plein écran / encoche | (à venir côté Cidre) | couvrir l'encoche comme le natif |

**Modèle :** un profil **par défaut** + des **surcharges par appid**. Aujourd'hui ces réglages sont codés en dur dans `lancer_depuis_steam.sh` (`case $SteamAppId`). 

**Action pour Cidre :** externaliser ces réglages dans un fichier de données (ex. `~/Library/Application Support/Cidre/profils.toml`, une section par appid) que `cidre play` lit et que **Verger écrit**. C'est ce qui rend le panneau d'options possible sans toucher au code à chaque jeu.

### 3. Login simple  ← demande explicite
**Connexion par QR / appli Steam mobile**, pas de mot de passe tapé dans Verger, pas de terminal :
1. Verger affiche un **QR code**.
2. L'utilisateur le scanne avec l'appli Steam mobile et **approuve**.
3. Verger récupère un **jeton de session** (mémorisé), zéro mot de passe stocké.

Moteur : **SteamKit2 / DepotDownloader** (supporte le login QR et le téléchargement de dépôt par OS). Pour la V1 on peut encapsuler SteamCMD (session mémorisée), mais la cible UX est le QR.

> Pourquoi pas steamctl : `python-steam` renvoie « Invalid Password » sur l'ancien flux de login (déprécié par Steam). Abandonné.

### 4. Sauvegardes
État de synchro par jeu + bouton backup/restore (`cidre sync`), au-dessus de notre sync iCloud (Steam Cloud ne résout pas les roots Windows sur mac).

## Stack technique recommandée

**SwiftUI (app macOS native, arm64).** Cohérent avec l'ADN du projet (natif, sans Rosetta, sans bloat) : ce serait absurde de livrer une UI Electron de 200 Mo pour un projet qui refuse la traduction. SwiftUI donne aussi la meilleure intégration plein écran / encoche / notifications, et un binaire léger qui se patche vite.

- UI : SwiftUI
- Logique : appels à la CLI `cidre` (Process), parsing JSON
- Login : binaire DepotDownloader embarqué (self-contained .NET) ou bridge SteamKit
- Stockage réglages : `profils.toml` partagé avec Cidre

Alternative si on veut du cross-platform plus tard : Tauri (Rust + web, léger). Mais pour une cible mac-only, SwiftUI gagne.

## MVP par phases

- **Phase 0 — plomberie** : `cidre list --json`, `cidre info --json`, `profils.toml`. (côté Cidre)
- **Phase 1 — Verger lecture seule** : bibliothèque + bouton Jouer (`cidre play`) sur les jeux déjà installés. Prouve l'intégration UI↔CLI.
- **Phase 2 — options par jeu** : panneau de réglages qui écrit `profils.toml`.
- **Phase 3 — install + login QR** : bouton Installer (`cidre dl`) derrière le login QR.
- **Phase 4 — polish** : saves, MAJ, jaquettes, détection auto de Cidre + auto-update de Verger (séparé du runtime).

## Structure de dépôt (proposée)

```
verger/
  Verger/              # app SwiftUI
    Library/           # vue bibliothèque
    GameSettings/      # panneau options par jeu
    Login/             # QR / session
    CidreBridge/       # appels CLI cidre + parsing JSON
  Tools/               # DepotDownloader embarqué (login QR)
  README.md            # ce pitch, nettoyé
```

## Prochaines étapes

1. Créer le dépôt `gtranche/verger`, y déplacer ce pitch (→ README).
2. Côté **Cidre** : livrer la Phase 0 (sorties `--json` + `profils.toml`).
3. Côté **Verger** : squelette SwiftUI + `CidreBridge` → Phase 1.

---
*Cidre est le moteur, Verger est la vitrine. Deux dépôts, un contrat (la CLI). On patche l'un sans retélécharger l'autre.*
