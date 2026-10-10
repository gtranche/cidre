# CrossOver 26.3 — diff winemac.drv + préloader contre notre Wine 11.18

> Analyse — 2026-10-10. Suite de [VEILLE_CROSSOVER.md](VEILLE_CROSSOVER.md) §1/§2.3.
> **Aucune modification du code de Cidre.** Liste de patches récupérables + applicabilité, à valider avant tout merge.
> Source : `crossover-sources-26.3.0.tar.gz` (media.codeweavers.com, officiel, 149 Mo). Seuls `dlls/winemac.drv/` et `loader/preloader*.c` extraits.

## Méthode (fiabilité du diff)

Les sources CrossOver fusionnent leurs patches dans l'arbre **sans `#ifdef`**, mais les annotent `/* CW Hack NNNNN */`. Pour séparer *leurs apports macOS* de la *dérive de version*, référence vanilla WineHQ récupérée pour **11.0** et **11.18**, diff à trois voies :

| | base | conclusion |
|---|---|---|
| Notre `src/wine11` | **Wine 11.18** + patches Cidre | `mouse.c`, `cocoa_app.m`, `display.c`… identiques au vanilla 11.18 ⇒ on est du 11.18 propre sauf nos patches numérotés |
| CrossOver 26.3 | **Wine 11.0** | `mouse.c` identique à 0 au vanilla 11.0, `CXvs11.0 ≪ CXvs11.18` partout ⇒ base confirmée 11.0 |

**On est en avant de leur base** (11.18 > 11.0). Les apports CrossOver = `diff(vanilla 11.0 → CX)`, soit les lignes `CW Hack`.

## Verdict sur les 3 cibles du brief

| Cible brief | Résultat | Détail |
|---|---|---|
| **Retina / HiDPI** (Ken Thomases) | ❌ **rien à prendre** | Le code Retina de CrossOver (`retina_enabled`/`retina_on`/clé `RetinaMode`/`check_retina_status`/`setRetinaMode:`) est **identique au nôtre** : tout est **upstream dans Wine 11.18**. Aucun patch Retina exclusif CrossOver. |
| **Fix souris Unity** (CrossOver 26.1) | ❌ **absent de winemac.drv** | `mouse.c` CrossOver = **byte-identique** au vanilla 11.0 (0 diff). Zéro occurrence « unity » dans winemac.drv + préloader. Le correctif 26.1, s'il existe, vit **dans un autre DLL** (dinput/rawinput/win32u), **non extrait**. Notre hack `clicabs` VT2 n'a **pas** d'équivalent winemac.drv à recouper ici. |
| **Préloader macOS** | ❌ **rien à prendre** | `loader/preloader_mac.c` CrossOver = **identique au vanilla 11.0 ET 11.18** (0 diff). Aucun patch préloader CrossOver. Notre travail espace d'adressage/W^X (patches 0028/0035/0062/0084) reste Cidre-spécifique, sans contrepartie amont. |
| **Non-régression item A** (plein écran auto, 0081, `CIDRE_FULLSCREEN_SPACE`) | ✅ **sûr** | Aucun patch graphique/fenêtre recommandé au merge ⇒ `cocoa_window.m` n'est pas touché, item A intact. CrossOver n'a **pas** notre fonction `updateFullscreen`/espace plein écran auto ; leurs seuls hacks fenêtre sont app-spécifiques (voir ci-dessous). |

## Inventaire complet des patches downstream CrossOver (winemac.drv)

Tous sous **LGPL 2.1** (en-têtes winemac.drv : « Ken Thomases / Brendan Shanks for CodeWeavers, Inc. »).

| Hack | Fichiers | Ce que ça fait | Intérêt Cidre |
|---|---|---|---|
| **10912** | event.c, keyboard.c, cocoa_app.m | **Menu Édition macOS** : route Cmd+C/X/V/Z/A/Suppr vers un vrai menu Edit Cocoa | 🟡 UX pure. Confort dans les apps (pas les jeux). Récupérable proprement, bas risque. |
| **22310 / 24199 / 23655** | cocoa_app.m | **AppUserModelID + « external quit »** : coordination d'arrêt entre processus (Steam `Valve.Steam.Client`, Epic web helpers, Rockstar Social Club) | 🟡 Touche notre pont Steam. Complexe, liste blanche en dur par launcher. À évaluer seulement si on rencontre le bug « le launcher ne quitte pas ses helpers ». |
| **13440 / 25964** | window.c, cocoa_app.m, cocoa_icon_utils.* | Icône d'app depuis l'URL du bundle + icône masquée (coins arrondis macOS) | 🟡 Cosmétique (icône Dock). Dépend de `cocoa_icon_utils.*` (2 fichiers en plus). |
| **24141** | cocoa_app.m | Supprime l'icône Dock pour « GOG Galaxy Notifications Renderer.exe » | 🔴 App-spécifique, inutile. |
| **16933** | window.c | Pas de décorations Cocoa pour la fenêtre principale de Quicken | 🔴 App-spécifique, inutile. |
| **24152** | cocoa_window.m | `presentsVisibleContent` spécial Epic Games Launcher | 🔴 App-spécifique, inutile. |
| **12205** | cocoa_main.m | Évite un appel `NSVersionOfRunTimeLibrary()` au démarrage (crash possible si un thread Wine décharge une dylib en même temps) | 🟢 **Stabilité macOS**, auto-contenu, bas risque. Seul candidat « sérieux » hors UX. |
| **23422** | opengl.c, + `opengl_bcdec.h` (fichier en plus) | Décode BC7/BPTC **sur CPU** pour le **chemin OpenGL** (Tomb Raider 1-3 Remastered). Crédit « nastys ». | 🟡 Niche : nos jeux passent par **DXVK/vkd3d→KosmicKrisp**, pas le GL Wine. BC7 est déjà géré côté DXVK (cf. patch 0085). Utile seulement pour un jeu en GL natif Wine. |
| **24834** | opengl.c | Env `CX_FWD_COMPAT_GL_CTX=1` force un contexte GL forward-compatible (3.2/3.3/4.0/4.1) | 🟡 Niche GL. Trivial à porter si besoin. |
| **22435** | event.c, d3dmetal_objc.m, macdrv_cocoa.h | Événement **`CLIENT_SURFACE_PRESENTED`** → `macdrv_client_surface_presented()` | 🟠 **Couplé à D3DMetal/DXMT** (émis par `d3dmetal_objc.m`). Orphelin sans eux. Pertinent pour un éventuel chemin DXMT (voir ci-dessous), pas pour notre pile actuelle. |

### Fichiers en plus chez CrossOver (absents de notre arbre)

- `d3dmetal.c`, `d3dmetal_objc.{h,m}` — **glue LGPL côté Wine** vers `D3DMetal.framework` (Apple GPTK). Le framework lui-même **n'est pas** dans le tarball et reste un **mur juridique** (licence Apple non-commerciale, cf. VEILLE §2.1). **Mais** le commentaire `d3dmetal.c:108` dit explicitement que *« D3DMetal ET DXMT appellent `get_win_data` à la création d'une swapchain DXGI »* : `macdrv_set_view_d3dmetal_client_surface()` + `CLIENT_SURFACE_PRESENTED` sont la **couche de hook LGPL que DXMT réutilise** pour présenter directement dans une `NSView`. ⇒ **à récupérer si/quand on prototype DXMT** (cf. session sœur DXMT).
- `cocoa_icon_utils.{h,m}` — utilitaires d'icône (dépendance de 13440/25964).
- `opengl_bcdec.h` — décodeur BC (dépendance de 23422).

## Recommandation

**Rien à merger pour les 3 cibles du brief** : elles sont soit déjà upstream chez nous (Retina), soit absentes de winemac.drv (souris Unity, préloader).

Candidats réels, par ordre d'intérêt — **à valider avant merge** :

1. 🟢 **12205** (anti-crash `NSVersionOfRunTimeLibrary` au démarrage) — seul gain « moteur », auto-contenu. *Proposé en patch Cidre si on veut.*
2. 🟡 **10912** (menu Édition macOS Cmd+C/V) — confort apps, propre, bas risque.
3. 🟠 **Glue D3DMetal/DXMT** (`d3dmetal.c` + 22435 + `macdrv_set_view_d3dmetal_client_surface`) — **à transmettre à la session DXMT**, pas un merge autonome.
4. 🔴 Le reste : app-spécifique (Quicken/Epic/GOG) ou niche GL (23422/24834) — **ignorer** sauf besoin ponctuel sur un jeu précis.

Attribution en cas de reprise : conserver les en-têtes LGPL 2.1 et le crédit CodeWeavers (Ken Thomases / Brendan Shanks), + « nastys » pour 23422.
