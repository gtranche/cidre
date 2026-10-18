# Base de profils par jeu

Une fiche par jeu, `profils/<appid>.toml`, plus un index `profils/index.toml`.
Les fiches écrites ou vérifiées à la main vivent dans le dépôt ; le catalogue
entier (une fiche par jeu noté sur ProtonDB sans version macOS native, voir
« Catalogue ») est généré chaque mois et publié en une archive. Cidre prend
l'archive (`cidre profils maj`), sinon les fiches du dépôt une à une, et les
garde en cache dans `~/Library/Application Support/Cidre/profils-base/`. Sans
réseau, la copie livrée dans le runtime (ce dossier, empaqueté par
`tests/empaqueter_runtime.sh`) sert de repli. Le cache prime sur la copie
livrée, sauf quand celle-ci est plus récente que lui (voir « Catalogue »,
`index-depot.toml`). Un jeu qu'on installe sans
fiche en reçoit une provisoire (voir « Fiche provisoire »).

Lecture : `tests/fiche_profil.sh` (analyse, accès, mise à jour), via
`tests/profil_cidre.sh` (résolution des options de lancement), le lanceur
`tests/lancer_depuis_steam.sh` (options et réglages du jeu) et la CLI
`cidre profils`, `cidre info <appid> --json`.

Pour partager un résultat, proposer une fiche ou une correction :
[CONTRIBUER.md](CONTRIBUER.md) (*[English](CONTRIBUER.md#contributing-to-the-game-profiles)*).

## Priorité des réglages

Clé par clé, du plus fort au plus faible :

1. l'environnement explicite (`CIDRE_TSO=0`, `CIDRE_D3D11=dxmt`…) ;
2. le profil utilisateur, section `[<appid>]` de
   `~/Library/Application Support/Cidre/profils.toml` (`cidre set`, Verger) ;
3. la fiche de la base, section `[cidre]` (cache téléchargé, sinon copie livrée) ;
4. le profil utilisateur, section `[defaut]` ;
5. `outil-steam/profils.toml`, section `[defaut]` (les réglages généraux livrés).

Une clé absente d'une couche est prise dans la suivante. Le cache téléchargé
prime sur la copie livrée, qui prime sur une fiche provisoire ; `cidre profils
maj` le rafraîchit et retire du cache les fiches qui ne sont plus dans l'index.

### Présentation hors de l'écran et garde GPU (DXMT, environnement seul)

Le DXMT de Cidre (patch 0154) cesse de présenter quand la fenêtre du jeu n'est
plus visible, ou quand le jeu est dans un espace plein écran et perd la main sur
un Mac à un seul écran (cmd-tab, changement d'espace) : il vide ses commandes
sans demander de drawable. `CIDRE_PRESENTATION_CACHEE=1` rend l'ancien
comportement (toujours présenter). Le même patch arme une garde : si un tampon
de commandes attendu ne se termine pas en `CIDRE_GARDE_GPU` secondes (20 par
défaut, `0` = jamais), le jeu est terminé (code 0xC1D3, message
`cidre-garde-gpu` dans le journal) plutôt que de laisser WindowServer bloqué
jusqu'à la panique du watchdog (gel du 2026-10-16). Ni l'un ni l'autre n'est
une clé de profil.

### Mise à jour avant le lancement (`maj_avant_lancement`)

`true` par défaut : `cidre play <id>` (et « Jouer » dans Verger) met d'abord à
jour un jeu du dossier Cidre dont Steam publie un build plus récent, puis le
lance. L'option suit la priorité ci-dessus : `cidre set defaut
maj_avant_lancement false` la coupe pour tous les jeux, `cidre set <appid>
maj_avant_lancement false` pour un seul (c'est la façon d'épingler un jeu sur
son build), et une fiche peut la couper dans `[cidre]` pour un jeu qu'une mise
à jour casse. `CIDRE_MAJ_AVANT_LANCEMENT=0` (ou `1`) passe devant le profil,
`cidre play <id> --sans-maj` vaut pour un seul lancement.

Ce que fait le lancement, cas par cas :

| Cas | Ce qui se passe |
|---|---|
| Jeu du client Steam (natif macOS, ou Windows par le wrapper) | rien : Steam le met à jour lui-même avant de le lancer |
| Jeu hors Steam (`cidre add`) | rien : pas de build à comparer |
| Jeu du dossier Cidre, à jour | lancement, sans attendre : le build publié est lu dans le cache du client Steam, sinon dans celui de `cidre updates` (30 minutes) ; SteamCMD n'est interrogé, 8 s au plus, que si aucun des deux n'est frais |
| Build plus récent publié | téléchargement de ce qui a changé (SteamCMD, session mémorisée), puis lancement |
| Jeu repris d'une bouteille (`cidre import`) | comme un jeu téléchargé : mis à jour sur place ; la bouteille garde sa version (clone APFS : seuls les fichiers changés prennent de la place) |
| Option à `false`, ou `--sans-maj` | lancement de la version installée ; la mise à jour connue est annoncée en une ligne |
| Jeu sur une branche bêta de Steam (`BetaKey` dans son manifeste) | jamais mis à jour au lancement : il est épinglé |
| Hors ligne, Steam trop lent (plus de 8 s), SteamCMD absent | une ligne le dit, lancement de la version installée |
| Session Steam absente, place insuffisante, échec en route | une ligne dit pourquoi et quoi faire, lancement de la version installée ; la tentative est reprise au lancement suivant |
| Mise à jour du même jeu déjà en cours ailleurs | refus (code 4) : le jeu serait lancé à moitié remplacé |

Le build publié vient de deux sources, et la plus grande l'emporte : le cache
du client Steam (`appcache/appinfo.vdf`, lu par `cidre-outil builds`, sans
réseau), tenu pour frais s'il a été écrit depuis moins de 30 minutes, ou si le
client tourne et a relu les fiches de son compte depuis moins de 30 minutes
(il le fait toutes les quinze minutes environ et ne réécrit son cache que si
l'une a changé) ; et `cache/appinfo.txt`, que remplit SteamCMD sans compte.
`cidre updates --fond` rafraîchit ce dernier en arrière-plan (Verger le fait à
son ouverture) ; une seule demande à SteamCMD tourne à la fois.

Un build installé plus récent que le build « publié » est tenu pour à jour :
les builds de Steam ne font que croître, c'est la fiche lue qui est en retard.
L'état de la dernière mise à jour de chaque jeu est gardé dans
`~/Library/Application Support/Cidre/maj/<appid>` ; `cidre updates --json` et
`cidre info <id> --json` (`"maj"`) le rendent : `a_jour`, `disponible`,
`en_cours` (avec `avancement`, `octets`, `total`), `echouee` (`raison`,
`message`), `ignoree` (`raison` : `option`, `branche`, `sans_effet`),
`inconnu`. Réglages d'essai : `CIDRE_MAJ_TTL` (minutes de validité du cache),
`CIDRE_MAJ_BUDGET` (secondes laissées à la vérification), `CIDRE_MAJ_LIBRE_MIN`
(Mo libres exigés), `CIDRE_MAJ_VALIDER=1` (revérifier tous les fichiers).
Essais : `sh tests/tester_maj_avant_lancement.sh`.

### Arguments du jeu (`arguments`)

`arguments = "-force-gfx-direct"` dans `[cidre]` ajoute ces options à la ligne de
commande du jeu, à chaque lancement (`cidre play`, Verger, bouton « Jouer » de
Steam). Arguments séparés par des espaces, sans guillemets ni échappement : un
argument qui contiendrait un espace n'est pas pris en charge. Une option déjà
passée au jeu, par exemple dans les options de lancement de Steam, n'est pas
doublée, ni les valeurs qui la suivent. `cidre set <id> arguments "-a -b"` la
pose pour un jeu, `CIDRE_ARGUMENTS` le temps d'un essai, et
`cidre play <id> -- <arguments>` pour un seul lancement.

Exemple mesuré (2026-10-14, PEAK en vrai D3D12, même vue) : Unity rend par
défaut en ~120 listes de commandes par image, que KosmicKrisp ne peut pas
fusionner ; avec `-force-gfx-direct`, 2 listes par image, et 32 → 45 images/s.

### Clavier AZERTY : les touches à leur place (`clavier`)

Un jeu qui lit les codes virtuels de Windows (`VK_W`, `WM_KEYDOWN` : Unreal,
Unity, la plupart des jeux Win32) attend ses touches aux positions d'un
clavier QWERTY. Wine, comme Windows, donne à chaque touche le code virtuel de
son caractère : en AZERTY, la touche Z envoie `VK_Z`, et le joueur
réassignait ZQSD dans chaque jeu. Un jeu qui lit les codes de balayage
(DirectInput, Raw Input) n'est pas concerné : ce sont déjà des positions.

- `clavier = "positions"` : chaque touche de caractères du bloc principal
  prend le code virtuel de sa position QWERTY. En AZERTY : A et Q, Z et W
  échangées ; la touche M est le `;` du jeu et la touche virgule son `M` ; la
  rangée du haut donne `1`…`0` sans Maj (Unreal appelait la touche 1 « & »).
  Les touches par défaut du jeu tombent là où il les attend. Sans effet sur
  une disposition QWERTY US.
- `clavier = "systeme"` (défaut) : le comportement de Wine.

Le texte tapé (discussion, nom du personnage) reste celui de la disposition
macOS, et le nom d'une touche (`GetKeyNameText`) aussi. Le jeu voit une
disposition US (`00000409`) dans la langue du système, cohérente avec ses
codes virtuels : un jeu qui adapte ses touches à une disposition AZERTY ne
les déplace pas une seconde fois. Un jeu déjà réassigné à la main en ZQSD est
à remettre à ses touches par défaut. Pour tous les jeux : `cidre set defaut
clavier positions` ; pour un essai, `CIDRE_CLAVIER=positions`. La mécanique
est dans winemac (wine11 0151) ; `tests/sonde_clavier.c` montre ce que voit
un jeu, touche par touche.

### Version de Windows (`windows_version`)

Sans l'option, un jeu voit Windows 10. Une fiche (ou `cidre set <id>
windows_version win7`) la change pour ce jeu-là : `win11`, `win10`, `win81`,
`win8`, `win7`, `vista`, `winxp64`, `winxp`, `win2k`. Tous les jeux partagent
un préfixe : le lanceur règle donc la version **à chaque lancement**, pour le
jeu qu'il lance, et un jeu qui ne la demande pas tourne en win10 quel que soit
le jeu lancé avant lui.

- La mécanique : la valeur `HKCU\Software\Wine\Version`, que Wine lit au
  démarrage de chaque processus, avant la version du préfixe. Tous les
  processus du jeu la voient, quel que soit leur nom (son lanceur,
  l'exécutable final, ce qu'il démarre, en 64 comme en 32 bits) : c'est la
  portée d'une bouteille CrossOver, d'où viennent la plupart de ces valeurs.
  La clé par application de Wine (`AppDefaults\<exe>\Version`) ne suit que le
  nom d'un exécutable : il faudrait énumérer ceux du jeu, et deux jeux qui ont
  un `Launcher.exe` se la disputeraient. Un réglage par application posé à la
  main (winecfg, onglet Applications) garde la priorité ; Cidre n'y touche pas.
- L'écriture : une ligne de `user.reg`, posée sans démarrer Wine par
  l'écriture de registre de `[reglages_jeu]` (voir plus bas), avant le premier
  processus Wine du lancement ; sans l'option, la ligne est retirée. Si un
  wineserver tient le préfixe (un autre jeu tourne), rien n'est écrit et le
  journal le dit.
- La version du préfixe (`HKLM`, celle de `winecfg -v`) reste Windows 10. Si
  elle a été changée pour tous les jeux (`winecfg -v`, à la main ou par
  winetricks ; le lanceur d'avant devait l'appeler, mais sa commande ne
  partait pas), elle est remise au lancement suivant et le journal le dit.
  Elle est reconnue à la signature de winecfg : `ProductName` « Microsoft
  Windows … » (wine.inf écrit « Windows 10 Pro ») avec un autre numéro de
  build que 19045, ou plus aucune valeur NT et un `VersionNumber` de
  Windows 9x. Les ruches d'avant la première écriture sont gardées
  (`user.reg.avant-cidre`, `system.reg.avant-cidre`).
- Une valeur inconnue (`windows 7`, `win95`…) est dite au journal et à la
  sortie du lancement, et le jeu part en win10 ; `cidre set` la refuse.
- Limite, celle de la clé par application de Wine : un programme qui lit la
  version dans `HKLM` au lieu de la demander à Windows y trouve Windows 10.

`CIDRE_WINDOWS_VERSION=win7` passe devant le profil, pour un essai. Le code
est dans `tests/version_windows.sh` ; essais : `sh
tests/tester_version_windows.sh`.

## Schéma d'une fiche

Sous-ensemble de TOML volontairement simple : des tables `[nom]` et
`[nom.sous_table]`, des tableaux de tables `[[rapports]]` et
`[[compat.machines]]` (et, sous un `[[machine]]`, `[machine.cidre]` et
`[[machine.reglages_jeu]]`), des lignes
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
mac_32bits = true                  # optionnel : la version macOS n'existe qu'en 32 bits
anticheat = "none"                 # none, eac, battleye, denuvo, vac
lanceur = "steam"                  # steam, epic, gog, aucun

[cidre]
# Les options de lancement, mêmes noms et mêmes valeurs que dans
# outil-steam/profils.toml (voir son en-tête pour le sens de chacune) :
# langue, journal_detaille, maj_avant_lancement, tso, tso_sans, tso_msvc, sync_local, vsync, hud, overlay, async, narrow_barriers,
# garde_index, fils_compilation, eac_untrusted, luajit, plein_ecran, mode_emule, gamemode,
# dx12, d3d11, d3d9, metalfx, clavier, deck, fex_cache_disque, fex_x87_reduit, fex_maxinst,
# arguments, dll_overrides, windows_version, dependances.
# On n'y met que ce qui diffère de [defaut].
async = true
fils_compilation = 6
garde_index = false

[[reglages_jeu]]
# Réglages du jeu lui-même, posés une fois par le lanceur (voir plus bas).
# Une entrée par section INI visée ; une fiche qui n'en vise qu'une peut
# écrire une table simple `[reglages_jeu]` au lieu du tableau.
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
format = "ini"                     # ini (défaut), gvas (sauvegarde Unreal), playerprefs (Unity) ou registre, voir plus bas
section = "ScalabilityGroups"      # optionnel : la section INI où vivent les clés
                                   # (exemple de forme : ce jeu-ci relit sa qualité ailleurs, voir plus bas)
[reglages_jeu.valeurs]             # ou, en ligne : valeurs = { "sg.ShadowQuality" = "1" }
"sg.ShadowQuality" = "1"
"sg.TextureQuality" = "1"

[[reglages_jeu]]
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
section = "/Script/SandFall.ConfigurableGameUserSettings"
valeurs = { "CurrentSelectedUpscalerQualityMode" = "0" }

[[machine]]
# Variante par machine (voir plus bas) : ce bloc ne vaut que si `si` est vraie.
si = "coeurs_gpu <= 10 et ecran_largeur >= 1920"
[machine.cidre]                    # options de lancement en plus de [cidre], ou à sa place clé par clé
metalfx = true
[[machine.reglages_jeu]]           # réglages du jeu en plus de [[reglages_jeu]], ou à leur place clé par clé
fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
section = "ScalabilityGroups"
valeurs = { "sg.ShadowQuality" = "0" }

[compat]
etat = "argent"                    # or, argent, bronze, ko, non-teste
source = "cidre-test"              # cidre-test, utilisateur, protondb, applegamingwiki, crossover, winehq
date = "2026-10-11"
machine = "M1 Max 32 Go"
cidre_version = "1.5.0"
fps_menu = 90                      # entier, 0 = non mesuré
fps_jeu = 40
notes = "..."
voie = "dxmt"                      # la voie de rendu mesurée : dxmt, dxvk, d3d12, wined3d, natif

[[compat.machines]]                # l'état sur une famille de Mac, pour une voie (voir plus bas)
nom = "M2 et suivants"             # ce que Verger affiche
si = "famille_gpu >= 8"            # même langage que [[machine]]
voie = "d3d12"
etat = "bronze"
source = "cidre-test"
date = "2026-10-15"
machine = "iMac M4 24 Go"
cidre_version = "1.5.11"
fps_jeu = 19
options = "dx12=true sm66=true"    # ce qu'il faut régler pour cette voie (`cidre set`), pour l'affichage
notes = "..."

[compat.steam_cloud]               # comment Steam Cloud range les sauvegardes du jeu (import, source steam)
methode = "auto"                   # aucune, api (ISteamRemoteStorage), auto (Auto-Cloud : dossiers déclarés)
synchro = "steam-lien"             # qui synchronise sous Cidre : steam-api, steam-lien, copie, aucune
racine_windows = "WinAppDataLocalLow/LandCrab/PEAK"    # racine Steam/chemin, tels que déclarés
motifs = "*.peak"
dossier_windows = "AppData/LocalLow/LandCrab/PEAK"     # le même, convention Cidre (sert à la copie)
racine_macos = "MacAppSupport/unity.LandCrab.PEAK"     # absent : le jeu ne déclare rien pour macOS
partage = "par-plateforme"         # multiplateforme (mêmes fichiers sur tous les systèmes) ou par-plateforme
liens = "AppData/LocalLow/LandCrab/PEAK => Library/Application Support/unity.LandCrab.PEAK"
source = "steam"
date = "2026-10-13"

[[rapports]]                       # une remontée d'utilisateur (Verger) ; zéro, une ou plusieurs
date = "2026-10-11"
machine = "M1 Max 32 Go"
modele = "MacBookPro18,2"           # hw.model, ou le nom en clair
macos_version = "26.5.2"
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
- `[jeu] mac_32bits = true` : Steam distribue une version macOS, mais en 32
  bits seulement (i386, PowerPC). macOS ne la lance plus depuis Catalina et
  Rosetta 2 ne traduit pas le 32 bits : Cidre traite le jeu en Windows
  seulement (`cidre dl` et `cidre install auto` prennent la version Windows,
  `cidre play` refuse la version macOS installée par Steam, code 9 ; Verger
  n'offre pas « Version macOS (par Steam) »). Importé de Steam (source
  `steam`) : `common/osextended` sans `macos64` ni `macosapplesilicon` (la case
  « 64 Bit Binaries Included » que le client exige), et aucune entrée de
  lancement ni aucun dépôt macOS en `osarch` 64. `false`, posé à la main,
  corrige un éditeur qui n'a pas coché la case. Un jeu installé se juge
  d'abord sur ses binaires (`file`), puis sur la fiche, puis sur le cache du
  client Steam (`cidre-outil plateformes`).
- `[cidre]` : les options de lancement. `moteur`, `anticheat` (de `[jeu]`),
  `etat` et `source` (de `[compat]`) sont aussi rendus par `profil_cidre.sh`,
  à plat, comme avant la migration.
- `[[machine]]` : une variante de la fiche pour certaines machines ; voir
  « Variantes par machine ».
- `[compat]` : l'état de compatibilité qui fait autorité (nos tests, source
  `cidre-test`, priment sur un import). `etat` : or (parfait), argent (jouable,
  limites), bronze (démarre, perf/bugs), ko (non), non-teste. C'est l'état sur
  la machine de référence (`machine`), avec la voie de rendu `voie`.
- `[[compat.machines]]` : l'état sur d'autres familles de Mac, voie par voie ;
  voir « Compatibilité par famille de Mac ».
- `[compat.steam_cloud]` : la configuration Steam Cloud du jeu, relevée par
  l'import ; le lanceur s'en sert pour laisser Steam synchroniser les
  sauvegardes lui-même quand il le peut (voir « Sauvegardes »).
- `[[rapports]]` : les remontées, dans l'ordre d'arrivée. Format stable, c'est
  celui que Verger envoie. Une remontée ne change pas `[compat]` toute seule :
  c'est une relecture qui met `[compat]` à jour (voir « Rapports
  d'utilisateurs »).

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
  `/Script/SandFall.ConfigurableGameUserSettings`), et **tous** ses
  `sg.*Quality` depuis une sauvegarde Unreal,
  `Saved/SaveGames/<compte>/SharedGameUserSettings.sav` (mesuré le 2026-10-12 :
  des `sg.*` posés à 0 dans l'INI reviennent à 1 au lancement, le jeu tourne
  en Moyen). Il faut viser la source, pas la clé dérivée — d'où le format
  `gvas`.
- `fichier` peut contenir un `*` à la place d'un dossier dont on ne connaît pas
  le nom d'avance (`AppData/Local/Sandfall/Saved/SaveGames/*/SharedGameUserSettings.sav`,
  un dossier par compte Steam) : chaque fichier qui correspond est traité.
- `format = "gvas"` : le fichier est une sauvegarde Unreal (`SaveGame`, en-tête
  `GVAS`). Chaque clé de `valeurs` est le nom d'une propriété **entière**
  (`IntProperty`), sa valeur un entier positif ; elle est remplacée sur place
  (4 octets, la taille et le reste du fichier ne bougent pas). Une propriété
  n'est touchée que si son en-tête est exactement celui attendu et qu'elle
  n'apparaît qu'une fois dans le fichier ; sinon elle est laissée, le journal
  le dit, et les autres sont posées. Pas d'autre type (les flottants et les
  chaînes changent de forme d'une version d'Unreal à l'autre). Même copie
  `.avant-cidre` avant la première écriture.
  Unreal n'écrit pas une propriété qui vaut sa valeur par défaut : Expedition 33
  réglé en Bas (0) n'a plus aucune `*Quality` dans sa sauvegarde. Avec
  `section = "<nom de la structure>"` (`EngineSettingsData` pour ce jeu), une
  propriété absente est ajoutée à la fin de cette structure (`StructProperty`),
  dont la taille est corrigée ; en-têtes au format d'Unreal 5.4 et suivants
  seulement. Sans `section`, une propriété absente est laissée et le journal
  le dit (« trouvée 0 fois ») ; jusqu'à Cidre 1.5.11 c'était le cas, et la
  qualité de la fiche n'était plus posée après une partie en Bas.
  Une clé `"Parent.Champ"` vise le champ entier qui suit immédiatement la
  chaîne `Parent` écrite en clair dans la sauvegarde : Sherlock Holmes Chapter
  One range chaque réglage sous une entrée `Graphics_X` dont le champ s'appelle
  toujours `Value` (`"Graphics_VerticalSync.Value" = "0"`). Les en-têtes
  d'Unreal 5.4 et ceux d'Unreal 4 (taille sur 8 octets) sont reconnus ; une
  telle clé n'est jamais ajoutée si elle manque.
- `format = "playerprefs"` : le jeu est en Unity et garde ses options dans les
  PlayerPrefs, que Unity range sous Windows dans le registre
  (`HKEY_CURRENT_USER\Software\<éditeur>\<jeu>`). `fichier` vaut alors
  `"user.reg"` (la ruche de l'utilisateur, à la racine du préfixe ; la seule
  acceptée) et `section` est la clé, relative à `HKEY_CURRENT_USER`. Chaque clé
  de `valeurs` est le nom du PlayerPrefs tel que le jeu le nomme
  (`"ShadowDistanceSettings"`) : le lanceur lui ajoute le suffixe `_h<hachage>`
  qu'Unity lui donne. Une valeur faite de chiffres est un entier (`SetInt`,
  `REG_DWORD`), toute autre une chaîne (`SetString`, rangée en binaire avec son
  zéro final, comme Unity l'écrit). Pas de nombre décimal (`SetFloat`), pas de
  caractère hors ASCII : la valeur est laissée, le journal le dit.

  ```toml
  [[reglages_jeu]]
  fichier = "user.reg"
  format = "playerprefs"
  section = "Software\\LandCrab\\PEAK"
  valeurs = { "ShadowDistanceSettings" = "Low" }
  ```

  Où trouver les noms : le journal du jeu (`Player.log`, sous
  `AppData/LocalLow/<éditeur>/<jeu>/`) quand il les cite (PEAK : « Failed to
  load setting of type ShadowDistanceSettings from PlayerPrefs » tant qu'une
  option est à sa valeur par défaut), la ruche après avoir changé l'option dans
  le jeu (`grep -A40 'LandCrab' user.reg`), sinon les classes du jeu
  (`PEAK_Data/Managed/Assembly-CSharp.dll`).
- `format = "registre"` : même chose pour un jeu qui écrit le registre
  lui-même, sans les conventions d'Unity : le nom de la valeur est pris tel
  quel, un entier est un `REG_DWORD`, une chaîne un `REG_SZ`.
- Pour ces deux formats : la clé est créée si elle manque (les réglages valent
  dès le premier lancement, le jeu n'a pas besoin d'avoir tourné) ; les autres
  valeurs de la clé et les autres clés ne bougent pas ; la ruche est copiée en
  `user.reg.avant-cidre` avant la première écriture. Le registre n'est écrit
  que si aucun `wineserver` ne tient le préfixe (il garde le registre en
  mémoire et réécrirait le fichier à sa sortie) : sinon rien n'est fait et on
  réessaie au lancement suivant. Un runtime d'avant ces formats (Cidre ≤ 1.5.9)
  répond « format inconnu » et réessaie à chaque lancement sans rien écrire.
- Un runtime d'avant ces deux ajouts (Cidre ≤ 1.5.4) répond « format inconnu »
  ou « fichier absent » et réessaie à chaque lancement, sans jamais poser le
  marqueur : une entrée `gvas` ou à `*` ne se met donc **que dans un bloc
  `[[machine]]`**, que ces runtimes ignorent, tant qu'ils circulent. Pour une
  entrée qui vaut sur toute machine, la condition toujours vraie est
  `si = "coeurs_gpu >= 1"` (fiche d'Expedition 33).
- Format `ini` : chaque clé de `valeurs` est écrite si elle n'est pas déjà à
  cette valeur ;
  les autres lignes sont intactes, les fins de ligne CRLF sont respectées, les
  guillemets d'une valeur sont gardés, l'espacement autour du `=` aussi. Avec
  `section`, la clé n'est cherchée que dans cette section INI, et une clé
  absente y est ajoutée (la section aussi, à la fin du fichier, si elle manque).
  Sans `section`, une clé absente n'est pas ajoutée.
  Avec `creer = true` (et une `section`), un fichier absent dont le dossier
  existe est créé vide puis rempli : l'`Engine.ini` d'Unreal
  (`Saved/Config/Windows/`), où vivent les `[SystemSettings]`, que le jeu
  n'écrit pas lui-même (Demonologist). Sa sauvegarde `.avant-cidre` est alors
  vide. Sans le dossier (le jeu n'a jamais tourné), on réessaie au lancement
  suivant.
- Avant la première écriture, le fichier est copié en `<fichier>.avant-cidre`
  (jamais écrasé ensuite : c'est l'état d'origine).
- Une fois posés (ou déjà en place), le lanceur écrit
  `reglages_jeu_appliques = true` dans la section du jeu du profil utilisateur
  et n'y touche plus : l'utilisateur est libre de changer ses réglages dans le
  jeu. Pour les reposer : `cidre unset <appid> reglages_jeu_appliques`.
- Une entrée ajoutée à une fiche déjà posée chez des utilisateurs porte un
  `id` (`id = "resolution-edid"`) : le lanceur garde les `id` posés dans
  `reglages_jeu_ids` et pose une fois, même sur un jeu déjà marqué, les seules
  entrées dont l'`id` est nouveau, sans reposer les autres.
- Une ligne de journal dit ce qui a été fait (`cidre log <appid>`).
- Le témoin (`[reglages_jeu_temoin]`, optionnel : `fichier` INI et `cle`).
  Certains jeux refont leur détection du matériel quand la carte graphique
  qu'ils voient change — passage de DXVK à DXMT, autre machine — et remettent
  alors leurs réglages à leurs propres valeurs, après que le lanceur a posé
  ceux de la fiche et noté le marqueur. Expedition 33 le fait quand
  `UserConfigHardwareProfile` change : il réécrit sa sauvegarde de réglages et
  son INI une minute après le lancement. Le lanceur relève la valeur du témoin
  avant le jeu et la compare à la sortie : si elle a changé, il retire le
  marqueur et le dit au journal ; les réglages de la fiche sont reposés au
  lancement suivant, et tiennent (le témoin ne bouge plus). La valeur relevée
  à la sortie est gardée par voie graphique dans le profil utilisateur
  (`reglages_jeu_temoin_dxmt`, `_dxvk`, `_d3d12`) et remise avant une partie
  dans cette voie : passer de DXMT à D3D12 puis revenir ne fait plus repartir
  le jeu sur ses propres réglages. Seule la toute première partie dans une
  voie, avant qu'une valeur soit connue, se joue avec les réglages du jeu.

  ```toml
  [reglages_jeu_temoin]
  fichier = "AppData/Local/Sandfall/Saved/Config/Windows/GameUserSettings.ini"
  cle = "UserConfigHardwareProfile"
  ```

## Variantes par machine (`[[machine]]`)

Un jeu limité par la carte graphique ne se règle pas pareil partout :
Expedition 33 tient 50 images/s sur un M1 Max avec le préréglage Moyen à 50 %
de résolution, et ~35 sur un iMac M4 (10 cœurs GPU, écran 4,5K) avec les mêmes
réglages. Une fiche peut donc porter, après sa partie commune, des blocs qui ne
valent que sur certaines machines. (Pour ce jeu-là la mesure du 2026-10-12 a
rendu le même réglage sur les deux : sa fiche n'a pas de bloc propre au M4.
Mesurer avant d'écrire une variante.)

```toml
[cidre]                            # commun à toutes les machines
d3d11 = "dxmt"

[[reglages_jeu]]                   # commun : le réglage de référence
fichier = "…/GameUserSettings.ini"
section = "ScalabilityGroups"
valeurs = { "sg.ShadowQuality" = "1", "sg.FoliageQuality" = "1" }

[[machine]]
si = "coeurs_gpu <= 10 et ecran_largeur >= 1920"
[machine.cidre]
metalfx = true
[[machine.reglages_jeu]]
fichier = "…/GameUserSettings.ini"
section = "ScalabilityGroups"
valeurs = { "sg.ShadowQuality" = "0" }
```

- `si` est une condition sur des faits de la machine : `fait op nombre`, `op`
  parmi `<=`, `>=`, `<`, `>`, `==`, `!=` (ou `gamme == max`, `gamme != base`),
  plusieurs termes reliés par ` et ` (tous vrais). Pas de `ou` : deux blocs
  font l'affaire.
- Les faits (`sh tests/machine.sh`) :

  | fait | sens | M1 Max (MacBook Pro 16") | M4 (iMac 24") |
  |---|---|---|---|
  | `famille_gpu` | la famille Metal de la carte (`MTLGPUFamilyApple<N>`, la plus haute que Metal reconnaît) : 7 = M1, 8 = M2, 9 = M3 et M4. C'est elle qui dit ce que la carte sait faire | 7 | 9 |
  | `generation` | le numéro de la puce (M1 → 1) | 1 | 4 |
  | `gamme` | `base`, `pro`, `max` ou `ultra` ; un mot, qui ne se compare que par `==` et `!=` | max | base |
  | `macos` | la version majeure de macOS | 26 | 27 |
  | `coeurs_gpu` | cœurs de la carte graphique | 24 | 10 |
  | `memoire_go` | mémoire vive, en Go | 32 | 24 |
  | `ecran_largeur`, `ecran_hauteur` | l'écran principal en **points**, c'est-à-dire la résolution que le jeu voit en plein écran | 1728 × 1117 | 2240 × 1260 |
  | `puce` | le nom de la puce, pour l'affichage (ne se compare pas) | Apple M1 Max | Apple M4 |
  | `macos_version` | la version complète, pour l'affichage (ne se compare pas) | 26.5.2 | 27.0.1 |

  `famille_gpu` est lue par un appel à Metal (`osascript`, ~0,1 s), sinon
  déduite de la génération de l'accélérateur graphique (`ioreg`,
  `AGXAcceleratorG13X` = M1). Les faits que nomment les conditions d'une fiche
  sont lus une fois par lecture de la fiche.

  Le nombre de cœurs GPU ne compare pas deux générations (un cœur de M4 vaut
  plus qu'un cœur de M1), mais il sépare les puces de base (8 à 10 cœurs) des
  Pro (14 à 20) et des Max (24 à 40) ; croisé avec la taille de l'écran, il dit
  si la carte est petite pour ce qu'elle doit remplir.
- Tous les blocs dont la condition est vraie s'appliquent, dans l'ordre de la
  fiche, après la partie commune. Une condition qu'on ne sait pas évaluer (fait
  inconnu, valeur illisible, faute de frappe) est fausse : la partie commune
  sert seule.
- `[machine.cidre]` : chaque clé remplace celle de `[cidre]` ou s'y ajoute. La
  priorité des couches ne change pas (l'utilisateur garde la main).
- `[[machine.reglages_jeu]]` : même forme que `[[reglages_jeu]]`. Une entrée qui
  vise le même `fichier` et la même `section` qu'une entrée déjà vue s'y fond
  (chaque clé de `valeurs` remplace la précédente ou s'ajoute) ; sinon c'est une
  entrée de plus. On n'écrit donc dans la variante que ce qui diffère.
- Les réglages du jeu ne sont posés qu'une fois (marqueur
  `reglages_jeu_appliques`) : une fiche qui gagne une variante n'atteint une
  machine déjà marquée qu'après `cidre unset <appid> reglages_jeu_appliques`.
  Un fait qui change ensuite (un autre écran branché) ne les repose pas non
  plus.
- Le journal du lancement dit quelle variante a joué
  (`fiche : variante pour cette machine (si …)`), `cidre info <appid> --json`
  aussi (`"fiche": {… "variantes": ["…"]}`), et `cidre doctor` affiche les
  faits. `CIDRE_MACHINE="coeurs_gpu=10 ecran_largeur=2240"` remplace les faits
  nommés, pour voir ce qu'une fiche donne ailleurs :

  ```sh
  CIDRE_MACHINE="coeurs_gpu=10 ecran_largeur=2240" sh tests/fiche_profil.sh reglages 1903340
  ```
- Compatibilité : un runtime d'avant ce mécanisme (Cidre ≤ 1.5.4) ignore les
  blocs `[[machine]]` et applique la partie commune. C'est pour cela que la
  variante est un bloc à part et non une condition posée sur une entrée de
  `[[reglages_jeu]]` : la partie commune doit rester le bon réglage pour qui
  ne sait pas lire le reste. Les mesures d'une autre machine vont dans un
  `[[rapports]]`, `[compat]` reste celui de la machine de référence.
- Un runtime qui lit les blocs `[[machine]]` mais pas les faits `famille_gpu`,
  `generation`, `gamme` et `macos` (Cidre 1.5.5 à 1.5.11) tient ces faits pour
  inconnus : la condition est fausse, le bloc ne s'applique pas. Une fiche peut
  donc s'en servir sans risque pour ces versions.

### Options par famille de Mac

Une option qui n'a de sens que sur certaines cartes se pose dans un bloc
`[[machine]]` conditionné par `famille_gpu`, et nulle part ailleurs : la partie
commune reste le bon réglage pour toutes les autres familles et pour les
runtimes qui ignorent le bloc. Le D3D12 d'Unreal 5 (Nanite) demande le Shader
Model 6.6, donc les atomiques 64 bits min/max que Metal n'offre qu'à partir de
la famille Apple8 (M2) :

```toml
[cidre]                            # toutes les machines : D3D11 par DXMT
d3d11 = "dxmt"

[[machine]]
si = "famille_gpu >= 8"            # M2 et suivants : le vrai D3D12, Shader Model 6.6
[machine.cidre]
dx12 = true
sm66 = true
```

Sur M1, sans le bloc, le jeu garde DXMT ; `sm66` y serait sans effet (le
pilote ne trouve pas les atomiques et ne les annonce pas) mais `dx12` y ferait
refuser le D3D12 par le jeu. Mesurer avant d'activer : Expedition 33 démarre
en D3D12 sur M4 mais y fait 19 fps contre 35 en DXMT, sa fiche reste donc en
DXMT partout et dit l'état du D3D12 dans `[[compat.machines]]`.

## Compatibilité par famille de Mac (`[[compat.machines]]`)

`[compat]` dit l'état d'un jeu sur la machine de référence. Quand il change
d'une famille de Mac à l'autre — un jeu qui ne passe en D3D12 qu'à partir du
M2, un autre limité par la carte d'un M1 de base —, chaque cas est une entrée
`[[compat.machines]]`, placée après `[compat]` :

```toml
[compat]                           # la machine de référence : un M1 Max, en DXMT
etat = "argent"
machine = "M1 Max 32 Go"
voie = "dxmt"
...

[[compat.machines]]
nom = "M1"
si = "famille_gpu <= 7"
voie = "d3d12"
etat = "ko"
options = "dx12=true sm66=true"
notes = "Unreal refuse le D3D12 : pas d'atomiques 64 bits."

[[compat.machines]]
nom = "M2 et suivants"
si = "famille_gpu >= 8"
voie = "dxmt"
etat = "argent"
machine = "iMac M4 24 Go"
fps_jeu = 35

[[compat.machines]]
nom = "M2 et suivants"
si = "famille_gpu >= 8"
voie = "d3d12"
etat = "bronze"
fps_jeu = 19
options = "dx12=true sm66=true"
```

- Une entrée a les champs de `[compat]` (`etat`, `source`, `date`, `machine`,
  `cidre_version`, `fps_menu`, `fps_jeu`, `notes`), plus `nom` (le libellé
  affiché : « M1 », « M2 et suivants »), `si` (même langage que les blocs
  `[[machine]]`, d'ordinaire sur `famille_gpu`), `voie` (la voie de rendu dont
  elle parle : `dxmt`, `dxvk`, `d3d12`, `wined3d`, `natif`) et `options` (ce
  qu'il faut régler pour cette voie, en `option=valeur` séparés par des
  espaces ; affiché, jamais appliqué).
- La voie de la fiche sur une machine : `d3d12` si `[cidre]` (variantes
  fondues) dit `dx12 = true`, sinon son `d3d11`, sinon le `voie` de
  `[compat]`. Les options que l'utilisateur règle lui-même n'y entrent pas : la
  compatibilité est celle de la fiche.
- Sur une machine, les entrées dont `si` est vraie et dont la `voie` est celle
  de la fiche (ou qui n'ont pas de `voie` : toutes les voies) **remplacent
  `[compat]` tout entier**, la dernière de la fiche gagnant. Les autres entrées
  qui s'appliquent décrivent une autre voie possible sur ce Mac (le D3D12 en
  bronze sur un M4 dont la fiche est en DXMT).
- `cidre info <appid> --json` rend, dans `"fiche"` : `"compat"`, l'état sur CE
  Mac (avec `"pour"`, le `nom` de l'entrée retenue, quand ce n'est pas
  `[compat]`) ; `"compat_reference"`, le `[compat]` écrit ; `"compat_machines"`,
  toutes les entrées, chacune avec `"applique"` (vrai sur ce Mac). `cidre info
  <appid>` l'écrit en clair (`compat`, puis une ligne `par famille` par entrée,
  « (ce Mac) » sur celles qui s'appliquent), et `sh tests/fiche_profil.sh
  compat <appid>` en lignes `cle TAB valeur`. L'état rendu à plat
  (`profil_cidre.sh`) est celui de ce Mac ; l'index garde celui de `[compat]`.
- Compatibilité : un runtime d'avant (Cidre ≤ 1.5.11) ne lit que `[compat]` ;
  un Verger d'avant n'affiche rien de plus. La fiche doit donc garder dans
  `[compat]` l'état de la machine de référence, pas un état moyen.
- `CIDRE_MACHINE="famille_gpu=9"` montre ce que voit un M4 :
  `CIDRE_MACHINE="famille_gpu=9" sh tests/fiche_profil.sh compat 1903340`.

## Index

`profils/index.toml` : une table `[<appid>]` par fiche, avec `nom`, `etat`,
`date`, `empreinte`. Sans archive, c'est lui que `cidre profils maj` télécharge
d'abord pour savoir quelles fiches prendre. Il se régénère depuis les fiches :

```sh
sh tests/fiche_profil.sh generer-index > profils/index.toml
sh tests/fiche_profil.sh generer-index build/catalogue > build/catalogue/index.toml   # un autre dossier
```

`tests/tester_profils.sh` vérifie qu'il est à jour. Un index ne part jamais
sans les fiches qu'il nomme : ni dans un commit, ni dans l'archive (`maj` la
refuse si une fiche manque).

## Sauvegardes : Steam Cloud d'abord (`[compat.steam_cloud]`)

Le client Steam de macOS synchronise lui-même, à la sortie d'un jeu lancé par
Cidre, tout ce qu'il sait trouver (son `logs/cloud_log.txt` : « Starting sync
(up,AC Exit,) »). Ce qu'il sait trouver dépend de la façon dont le jeu a
déclaré ses sauvegardes à Steam (section `ufs` de ses métadonnées), que
l'import relève dans la fiche :

| `methode` | `synchro` | Ce qui se passe sous Cidre |
|---|---|---|
| `api` : le jeu écrit par l'API Remote Storage, aucun dossier déclaré | `steam-api` | Les appels passent par le pont ; les fichiers arrivent dans `userdata/<compte>/<appid>/remote` du client macOS, qui les envoie. Cidre ne copie rien, sauf un dossier de sauvegardes locales désigné par `saves.conf` (`api` dit que le jeu *peut* écrire par l'API, pas que tout y passe : Vermintide 2 garde tout en local en Modded Realm). |
| `auto` : Auto-Cloud, et le jeu déclare un dossier **pour macOS** | `steam-lien` | Avant le lancement, le dossier de sauvegarde du préfixe Wine devient un lien symbolique vers le dossier macOS déclaré (`liens`) : le client macOS y trouve les fichiers et les envoie. Cidre ne copie rien. |
| `auto`, dossiers déclarés pour Windows seulement (ou non liables : `sans_lien`) | `copie` | Steam ne peut pas : le client macOS ne sait pas résoudre une racine Windows (« Unable to resolve path with root WinAppDataLocal »), et Steam pour macOS n'a pas d'outil de compatibilité à qui déléguer. Cidre copie le dossier lui-même. |
| `aucune` : pas de Steam Cloud | `aucune` | Cidre copie, s'il sait où sont les sauvegardes. |

**Le lien** (`tests/lier_saves_steam.sh`) n'est proposé que si la même règle
vaut sur les deux systèmes (`partage = "multiplateforme"` : le jeu déclare un
`rootoverrides` pour macOS, ce sont les mêmes fichiers dans le nuage, partagés
avec un PC), ou si une règle Windows et une règle macOS de **même motif** se
répondent (`par-plateforme` : Steam garde alors des fichiers distincts par
système — la synchro se fait entre Mac, et avec la version macOS du jeu, pas
avec un PC). Des motifs différents sont des formats différents : pas de lien
(`sans_lien = "motifs differents"`). Pas de lien non plus vers le dossier du
jeu (côté macOS, le client le cherche dans sa propre bibliothèque, où le jeu
Windows n'est pas ; côté Windows, on ne déplace jamais un dossier du jeu), ni
d'une racine entière (`Documents`), ni partiel (une règle Windows que
rien ne reprend sur macOS : tout le jeu reste en copie).

Poser le lien ne détruit rien : le dossier d'origine du préfixe est déplacé,
entier, dans `<Cidre>/saves/<appid>/.history/avant-lien-<date>/` ; ses fichiers
sont copiés dans le dossier macOS sans rien y écraser (un fichier déjà présent
côté macOS reste : c'est celui que Steam synchronise) ; le dossier macOS, s'il
n'était pas vide, est lui aussi copié là avant le premier lien. Les variables
`{64BitSteamID}` et `{Steam3AccountID}` sont résolues avec le compte connecté
au client ; sans compte, pas de lien (la copie Cidre sert).

Limites, à connaître :

- le client macOS **envoie à la sortie** du jeu, mais ne **télécharge au
  lancement** que les jeux qu'il lance lui-même (« AC Launch, down ») : pour un
  jeu lancé par Cidre, ce qui a été joué sur une autre machine arrive à la
  synchro suivante du client, pas avant la partie ;
- `par-plateforme` avec un motif passe-partout (`*`) : rien ne prouve que les
  deux versions écrivent le même format ; la copie datée d'avant le lien permet
  de revenir en arrière ;
- `CIDRE_SAVES_STEAM=0` rend tout à la copie Cidre.

**La copie Cidre** (`tests/sync_saves_steam.sh`, pour le reste) va dans un
dossier de ce Mac, `~/Library/Application Support/Cidre/saves/<appid>/`. iCloud
n'est plus le défaut ; qui le veut le choisit :

```sh
cidre saves                      # par jeu : Steam Cloud (API ou dossier lié), ou copie Cidre et son état
cidre saves <appid> --json       # {"etat":"steam","steam":"api"|"lien","lie":…} ou l'état de la copie
cidre saves dossier              # le dossier des copies
cidre saves dossier icloud       # iCloud Drive/CidreSaves (ou un chemin absolu ; `defaut` pour revenir)
```

`cidre saves <appid> --json` dit qui synchronise, pour une interface (Verger),
par deux champs ajoutés aux champs existants (inchangés) :

| `synchro` | Sens | Champs utiles |
|---|---|---|
| `steam_api` | le jeu écrit par l'API Remote Storage, par le pont : Steam s'en charge | `dossier` (le `remote` du client) ; si `copie` n'est pas vide, Cidre copie **en plus** le dossier local `dossier` désigné par `saves.conf`, et `etat` est celui de cette copie |
| `steam_macos` | dossier du préfixe lié à celui que le jeu déclare pour macOS : le client Steam s'en charge | `dossier` (le dossier macOS), `lie` (`true` ; `false` tant que le jeu n'a pas été lancé) |
| `copie` | Cidre copie lui-même | `copie` (le dossier de la copie), `icloud`, `etat` (`a_jour`, `a_sauvegarder`, `a_restaurer`, `divergent`, `jamais_sauvegarde`, `vide`) |
| `aucune` | dossier de sauvegarde inconnu : rien n'est synchronisé | `configure` est `false` |

`synchro_detail` le dit en une phrase, en français. `etat` vaut `steam` quand
Steam seul synchronise ; `steam` (`api`, `lien` ou vide) et `lie` restent, mais
c'est `synchro` qui fait contrat.

Les copies faites dans iCloud Drive par les versions précédentes sont reprises
une fois dans le nouveau dossier (celles d'iCloud restent en place). Le dossier
à copier vient de `outil-steam/saves.conf`, de `cidre saves set`, sinon de la
fiche : `[compat.steam_cloud] dossier_windows` (ce que le jeu déclare lui-même
à Steam) puis `[compat.pcgamingwiki] sauvegardes`, sinon de ce que le jeu vient
d'écrire (`tests/deviner_saves.sh`).

## Commandes

```sh
cidre profils                 # la base (cache ou copie livrée) : appid, nom, état, date
cidre profils --json
cidre profils maj             # l'archive de la base (une requête), sinon l'index puis les fiches depuis GitHub main
cidre info <appid> --json     # ... "fiche": {"jeu":{}, "cidre":{}, "compat":{}, "protondb":{}|null, "reglages_jeu":[{fichier, format, section, valeurs}], "variantes":["si …"],
                              #               "compat_reference":{}, "compat_machines":[{nom, si, voie, etat, …, applique}], "origine": "cache|livree|provisoire", "rapports": n}
sh tests/fiche_profil.sh <commande> ...   # chemin, plat, json, reglages, compat, variantes, index, generer-index, maj, provisoire
sh tests/machine.sh [json [fait…] | si "<condition>"]   # les faits de la machine, une condition
```

`cidre info`, `plat`, `json`, `reglages` et `compat` rendent la fiche telle
qu'elle vaut sur cette machine (variantes fondues, compatibilité de ce Mac) ; `fiche_profil.sh toml <fichier>` rend
le fichier tel quel.

Variables d'environnement : `CIDRE_PROFILS_BASE` (dossier du cache),
`CIDRE_PROFILS_ARCHIVE` (l'archive de la base, par défaut
`https://github.com/gtranche/cidre/releases/download/profils-base/profils-base.tar.gz` ;
vide = jamais d'archive), `CIDRE_PROFILS_URL` (origine des fiches une à une,
par défaut `https://raw.githubusercontent.com/gtranche/cidre/main/profils/` ; un
`file:///…/` sert aux tests), `CIDRE_PROFILS_PROVISOIRES` (dossier des fiches
provisoires), `CIDRE_PROTONDB_URL` et `CIDRE_STEAM_MAGASIN_URL` (ce que
`provisoire` interroge ; `file://` pour les tests), `CIDRE_PROFILS` (profil
utilisateur), `CIDRE_MACHINE` (faits de la machine imposés, pour les tests et
les essais).

## Catalogue : tous les jeux notés sur ProtonDB

`importer_profils.py --catalogue-protondb` prend pour liste de jeux l'export
mensuel de ProtonDB (34 293 appids au 2026-10-01), demande au magasin Steam
(sans compte, `IStoreBrowseService/GetItems`, par lots de 100) le nom et les
plateformes de chacun, et garde ceux qui n'ont pas de version macOS native
(25 306 ; une version macOS 32 bits seulement n'en est pas une : ces jeux
restent, lus par SteamCMD, `mac_32bits` au bilan), ceux que le magasin ne montre plus (1 022) et les fiches déjà
écrites : 26 818 fiches. Rien n'y est demandé jeu par jeu aux wikis : la page
d'un jeu se trouve par les liens que son infobox pose vers Steam
(`list=exturlusage`, 500 par requête : le magasin sur PCGamingWiki, 52 112
appids ; SteamDB et le magasin sur AppleGamingWiki, 642), le wikitexte se
charge par lots de 50 pages, et l'appid est vérifié dans l'infobox comme pour
une fiche seule. Les résumés ProtonDB se prennent un par un, deux par seconde
au plus, les jeux les plus rapportés d'abord : ProtonDB coupe tout accès à qui
va plus vite (constaté le 2026-10-15 : plus aucune connexion après ~12 500
résumés à ~12 par seconde), et le chargement s'arrête de lui-même après cinq
échecs de suite. `--resumes-max N` borne un passage, comme `--steam-cloud-max N`
la configuration Steam Cloud par SteamCMD (~0,5 s par jeu) ; le reste vient aux
passages suivants, et une fiche sans résumé garde ce que dit l'export
(`rapports_export`, `verdicts_recents`, lanceurs, anti-triche signalé). Les recettes
CrossOver ne sont jamais demandées pour le catalogue (une part non
substantielle de leur base seulement, voir plus bas) : celles des fiches du
dépôt restent telles quelles.

```sh
cp -R profils build/catalogue
python3 -I tests/outils/importer_profils.py --catalogue-protondb --profils build/catalogue \
        --rapport build/rapport-catalogue.json            # --limite N pour un essai
sh tests/fiche_profil.sh generer-index build/catalogue > build/catalogue/index.toml
python3 -I tests/outils/verifier_catalogue.py profils build/catalogue   # rien d'écrit à la main n'a bougé
```

Le catalogue n'est pas commité (des dizaines de milliers de fichiers que chaque
export ProtonDB change presque tous) : `.github/workflows/profils.yml` le
régénère le 3 de chaque mois à partir des fiches du dépôt, vérifie que les
valeurs sans provenance, `cidre-test`, `utilisateur` ou `crossover` n'ont pas
bougé (`verifier_catalogue.py`), et publie `profils-base.tar.gz` (un tar.gz à
plat : `index.toml` et les fiches) sur la release `profils-base`, une
pré-release que `/releases/latest` ne voit pas. `cidre profils maj` la
télécharge, refuse une archive qui contiendrait autre chose que des fiches à
plat ou dont l'index nommerait une fiche absente, la déballe à côté du cache
et l'échange avec lui d'un coup. Sans archive publiée, ou refusée, `maj` revient
aux fiches du dépôt une à une.

L'archive porte aussi `index-depot.toml` (`tests/outils/index_depot.py`) : pour
chaque fiche du dépôt, le md5 de la version dont le catalogue est parti
(`empreinte`) et ceux de ses versions précédentes dans l'historique git
(`anciennes`). La fiche du cache est celle du dépôt enrichie par l'import ; elle
ne doit pas masquer une correction faite depuis (constaté le 2026-10-16 :
Sherlock Holmes Chapter One parti en D3D12 sur une copie du cache du 14/10
sans `[cidre]`, quand la fiche livrée disait `dx12 = false`). `fiche_profil.sh
chemin` prend donc la copie livrée quand son md5 n'est ni l'empreinte ni l'une
des anciennes (fiche corrigée depuis l'archive, modifiée localement, ou écrite
depuis), le cache sinon. Un cache sans `index-depot.toml` (archive d'avant,
fiches une à une) : la copie livrée sert si son fichier est plus récent que
l'horodatage de la dernière mise à jour.

Mesures du 2026-10-15 (export du 2026-10-01) : 26 818 fiches, 35,5 Mo de texte
(109 Mo sur le disque, ~16 Mo d'objets git par instantané, presque tous
renouvelés chaque mois) ; l'archive fait 4,9 Mo. `maj` par l'archive : 6 s
avec un cache vide, 10 s sinon, plus le téléchargement ; une à une, il
faudrait ~0,3 s par fiche de réseau (plus de deux heures) et l'index relu
pour chacune.

## Fiche provisoire

Quand `cidre dl` (jeu Windows) ou `cidre install` installe un jeu que la base ne
connaît pas, `fiche_profil.sh provisoire <appid>` lui écrit en fond une fiche
locale, `~/Library/Application Support/Cidre/profils-provisoires/<appid>.toml` :
le résumé public de ProtonDB (`[compat.protondb]`, mêmes clés que l'importeur),
le nom et les plateformes du magasin Steam, `[compat] etat = "non-teste"` et
`[jeu] provisoire = true`. Deux requêtes courtes, curl, awk et sed seulement
(pas de python3, qui échoue sur un Mac dont la licence Xcode n'est pas
acceptée). Rien si le jeu a déjà une fiche ; rien non plus si ProtonDB ne le
connaît pas (code 3). La vraie fiche passe devant dès qu'elle existe (cache ou
copie livrée), et `maj` retire les provisoires que la base couvre désormais.
`cidre info <appid> --json` la rend avec `"origine":"provisoire"` ;
`"protondb"` y porte le palier.

## Rapports d'utilisateurs (`tests/outils/rapports_vers_fiches.py`)

Verger (« Partager mon résultat ») ouvre le formulaire d'incident « Rapport de
jeu » du dépôt (`.github/ISSUE_TEMPLATE/rapport-jeu.yml`), titré « Rapport de
jeu : *nom* (*appid*) », dont le champ « Rapport » porte une balise
`<!-- cidre-rapport v1 appid=… -->`, le bloc `[[rapports]]`, le profil effectif
et le diagnostic ; le formulaire pose le label `rapport-jeu`. L'outil (machine de dev,
Python 3.11+, sans dépendance, `gh` en lecture seule) en fait des blocs prêts à
coller ; c'est un outil de relecture, il ne décide rien :

```sh
python3 -I tests/outils/rapports_vers_fiches.py                    # les incidents ouverts : blocs, mises en garde, illisibles
python3 -I tests/outils/rapports_vers_fiches.py --appliquer --incident 12   # ajoute ce bloc à sa fiche
python3 -I tests/outils/rapports_vers_fiches.py --proposer-compat  # suggère [compat], n'écrit rien
python3 -I tests/outils/rapports_vers_fiches.py incidents.json     # depuis un fichier (forme de `gh issue list --json`)
python3 -I tests/outils/test_rapports_vers_fiches.py               # le test (incidents fabriqués)
```

- Le label vient du formulaire, pas de l'adresse : un `labels=` dans une adresse
  « nouvel incident » exige le droit de poser un label sur le dépôt (la
  documentation de GitHub annonce une page 404 sinon), alors que les labels d'un
  formulaire sont posés « automatiquement », quel que soit l'auteur — à
  condition que le label existe sur le dépôt. Verger remplit le champ du
  formulaire par son identifiant
  (`issues/new?template=rapport-jeu.yml&title=…&rapport=…`) : ne renommer ni le
  fichier ni l'`id` du champ sans changer Verger.
- Les incidents sont cherchés par le label, **et** par le titre, **et** par la
  balise du corps : un rapport ouvert hors du formulaire (Verger 0.3.13 ou plus
  ancien, incident libre) arrive sans label. L'outil le lit quand même et le
  signale. Deux formes de corps sont lues : « ### Rapport » suivi du champ (le
  formulaire) et le rapport seul (avant le formulaire).
- Le modèle du formulaire est vide (`etat = ""`) : envoyé tel quel, il est
  refusé. Si un rapport est collé sous le modèle laissé en place, c'est le bloc
  qui donne un état qui est lu.
- Le bloc rendu : `date`, `machine`, `modele`, `macos_version`, `famille_gpu`, `voie`, `cidre_version`,
  `etat`, `fps_menu`, `fps_jeu`, `notes` (celles du joueur, sur une ligne,
  suivies des options avec lesquelles il a lancé quand elles diffèrent de la
  fiche) et `incident` (l'adresse de l'incident). Le diagnostic n'est ni lu ni
  recopié. `modele` (l'identifiant `hw.model`, « Mac15,9 », ou le nom en clair
  d'un rapport écrit à la main) et `macos_version` (« 26.5.2 », le fait de même
  nom) situent la machine au-delà de la puce : écran et cœurs GPU, version de
  Metal ; une `macos_version` qui n'en a pas la forme est omise et signalée.
  Verger les écrit depuis la version qui affiche la compatibilité par Mac sur
  son site. `famille_gpu` et `voie` sont écrits par Verger depuis sa version
  qui affiche la compatibilité par famille ; pour un rapport plus ancien, la
  famille est déduite du nom de la puce dans `machine` (M1 → 7, M2 → 8, M3 et
  M4 → 9) et la voie des options du profil effectif (`dx12`, `d3d11`).
- Le contenu d'un incident est une donnée écrite par un inconnu : l'appid ne
  sert de nom de fichier que s'il en a la forme, les caractères de contrôle
  sont retirés, un `incident` écrit dans le corps est ignoré. Ce que l'outil a
  dû interpréter (état en anglais, fps en fourchette, date absente, lien dans
  les notes, nom qui ne correspond pas à la fiche, même auteur deux fois) est
  dit au mainteneur.
- `--appliquer` ajoute le bloc après le dernier `[[rapports]]` (sinon après
  `[compat]`) sans toucher au reste, relit la fiche avant de l'écrire, crée une
  fiche minimale (`[jeu]` appid et nom, `[compat] etat = "non-teste"`) si le
  jeu n'en a pas, et régénère l'index. Un jeu hors Steam (`local-…`) ne reçoit
  pas de fiche d'office. Un incident déjà intégré (son adresse figure dans un
  `incident` de la base) n'est pas rajouté.
- `--proposer-compat` : `etat = E`, `source = "utilisateur"`, quand au moins
  deux rapports donnent E sur au moins deux machines différentes (le rapport
  le plus récent de chaque machine compte seul) et qu'aucun autre état ne
  réunit autant de machines ; date, machine et fps sont ceux du rapport le plus
  récent. Un `[compat]` de source `cidre-test`, ou écrit à la main sans source,
  n'est jamais proposé au remplacement : le désaccord est signalé, à retester.
  Deux joueurs sur le même modèle de Mac comptent pour une machine.
- `--proposer-compat` regarde aussi chaque famille de Mac : les rapports sont
  rangés par famille (`famille_gpu`) et par voie, et la même règle (deux
  machines d'accord, aucun autre état à égalité) propose une entrée
  `[[compat.machines]]` (`si = "famille_gpu == N"`, à élargir à la main si
  d'autres familles suivent) quand l'état de cette famille diffère de ce que la
  fiche en dit déjà. Une entrée de source `cidre-test` n'est pas proposée au
  remplacement : le désaccord est signalé. Un tableau par jeu résume ce que les
  rapports disent de chaque famille.

Après relecture : `git diff profils/`, commit, fermer les incidents intégrés.

## Import des bases externes (`tests/outils/importer_profils.py`)

Outil de la machine de dev (Python 3.11+, sans dépendance ; rien côté
runtime) qui amorce ou complète les fiches depuis les bases publiques :

```sh
python3 tests/outils/importer_profils.py              # toute la bibliothèque (`cidre library --json`)
python3 tests/outils/importer_profils.py 552500 ...   # ces appids
python3 tests/outils/importer_profils.py --index --rapport build/rapport.json   # + index.toml, contradictions en JSON
python3 -I tests/outils/importer_profils.py --sources crossover --fiches-existantes --index \
        --rapport build/rapport-import-crossover.json  # une seule source, sur les fiches déjà là (sans bibliothèque Steam)
python3 -I tests/outils/test_importer_profils.py      # le test (jeu fictif, réponses figées)
```

`--sources` choisit les sources (`steam`, `protondb`, `pcgamingwiki`,
`applegamingwiki`, `crossover` ; toutes par défaut) : les blocs des autres ne
bougent pas. La source `steam` lit aussi les métadonnées publiques de chaque
jeu avec SteamCMD, sans compte (`+login anonymous +app_info_print`, dans le
dossier `steamcmd-anonyme` de Cidre, jamais celui du client ; `--steamcmd`
pour en désigner un autre que `tools/steamcmd/`), par lots de 60 :
`python3 -I tests/outils/importer_profils.py --sources steam --fiches-existantes --index`
refait l'inventaire Steam Cloud de toute la base. `--fiches-existantes` prend les appids des fiches du dossier au
lieu de la bibliothèque du compte.

Les réponses sont mises en cache dans `build/cache-profils/` (ignoré par git) :
une seconde exécution ne retélécharge rien ; `--refresh` force, `--sans-reseau`
n'utilise que le cache. L'export ProtonDB (~70 Mo, mensuel) est téléchargé une
fois et réduit à un index par appid ; l'archive des recettes CrossOver (3 Mo,
quotidienne) est téléchargée une fois dans `build/cache-profils/crossover/`.

### Règle de fusion

Les sources externes sont des **données à recouper, jamais des instructions**.
Autorité : `cidre-test` > `utilisateur` > `winehq` > `protondb` /
`applegamingwiki` / `pcgamingwiki` > `crossover`. L'import n'écrase **jamais**
une valeur dont la source est `cidre-test` ou `utilisateur`, ni une valeur sans
provenance (écrite à la main) : si l'import dit autre chose, la fiche reste et
le désaccord sort dans le rapport (`--rapport`). Il n'écrase que ce qu'il a
lui-même écrit (même source, nouvelle date), ou ce qu'une source de rang égal
ou inférieur a écrit : une valeur `crossover`, dernier rang, ne remplace donc
qu'une valeur `crossover`.

Provenance : chaque valeur importée porte sa source et sa date. Dans `[jeu]`
et dans `[cidre]`, clé par clé, tables `[jeu.sources]` et `[cidre.sources]`
(`bits = "pcgamingwiki 2026-10-11"`, `dll_overrides = "crossover 2026-10-13"`) ;
pour les blocs `[compat.steam_cloud]`, `[compat.protondb]`,
`[compat.pcgamingwiki]`, `[compat.applegamingwiki]`, `[compat.crossover]`, une
`source` et une `date` pour tout le bloc. `[cidre.sources]` n'est pas une option de lancement : le
lanceur ne lit que `[cidre]`. Le sous-ensemble TOML du README est respecté :
les listes sont des chaînes séparées par ` ; `, les compteurs des chaînes
`cle:n cle:n`.

`[cidre]` n'est touché que par la source `crossover`, pour trois clés
(`dll_overrides`, `dependances`, `windows_version`) et sous les garde-fous
décrits plus bas ; une clé qui s'y trouve déjà, écrite à la main, reste.
`[compat]` (état, machine, fps, notes), `[reglages_jeu]` et
`[[rapports]]` ne sont **pas** touchés par l'import. Une fiche neuve reçoit
`[compat] etat = "non-teste"` et la date du jour : le palier ProtonDB (Linux,
Proton) ou le verdict AppleGamingWiki (CrossOver, GPTK) ne sont pas notre
état Cidre.

### Cartographie : quelle donnée alimente quel champ

| Source (licence) | Donnée | Champ de la fiche |
|---|---|---|
| Bibliothèque Steam (`cidre library`) | nom, plateformes du dépôt | `[jeu] nom`, `plateformes_steam` (`"windows"` ou `"macos windows"`) |
| Steam, métadonnées publiques du jeu (`app_info_print`, `common/osextended`, `osarch` des entrées de lancement et dépôts macOS) | version macOS 64 bits déclarée ou non | `[jeu] mac_32bits = true` quand la version macOS n'est qu'en 32 bits (retiré si Steam en déclare une 64 bits) |
| Steam, métadonnées publiques du jeu (`app_info_print`, section `ufs` : la configuration Steam Cloud) | méthode (API Remote Storage ou Auto-Cloud), règles `savefiles` (racine, chemin, motif, plateformes) et `rootoverrides` par système | `[compat.steam_cloud] methode` (`aucune`, `api`, `auto`), `racine_windows` et `racine_macos` (`Racine/chemin`, après `rootoverrides`), `motifs` (+ `motifs_macos` s'ils diffèrent), `dossier_windows` (convention Cidre), `partage`, `liens` (`dossier du préfixe => dossier sous le dossier personnel`) ou `sans_lien` (pourquoi pas), `synchro` (`steam-api`, `steam-lien`, `copie`, `aucune`) ; voir « Sauvegardes » |
| ProtonDB, API publique des résumés (données utilisateurs) | palier, tendance, meilleur palier, confiance, score, nombre de rapports | `[compat.protondb] palier`, `tendance`, `meilleur_palier`, `confiance`, `score` (0-100), `rapports`, `url` |
| ProtonDB, export JSON public des rapports (dépôt `bdefore/protondb-data`) | options de lancement les plus citées (2 ans), lanceur utilisé, « lanceur secondaire » (le jeu a son propre lanceur), anti-triche signalé, verdicts récents | `options_lancement_1..3` (`"… (xN)"`), `lanceurs_signales`, `lanceur_secondaire` (`"non:7 oui:1"`), `anticheat_signale`, `verdicts_recents`, `rapports_export` ; et `[jeu] anticheat` si PCGW est muet et qu'un seul anti-triche est signalé |
| PCGamingWiki, API MediaWiki, wikitexte des modèles (CC BY-NC-SA) | `{{Infobox game}}` moteur, appid ; `{{API}}` versions Direct3D/Vulkan/OpenGL, exécutable 32/64 bits ; `{{Middleware}}` anti-triche ; `{{Availability/row}}` DRM Steam | `[jeu] moteur` (vocabulaire de la fiche, sinon `autre`) + `moteur_nom`, `api` (seulement si une seule API), `api_disponibles` (`"d3d11 d3d12"`), `bits` (64 si un exécutable 64 bits existe) + `bits_32_aussi`, `anticheat` (none, eac, battleye, denuvo, vac, sinon `autre` + `anticheat_nom`), `drm` |
| PCGamingWiki, `{{Game data/config}}` et `{{Game data/saves}}` (Windows) | emplacement des fichiers de réglages et des sauvegardes | `[compat.pcgamingwiki] fichiers_reglages`, `sauvegardes` (chemins traduits dans la convention Cidre : relatifs à `drive_c/users/<utilisateur>/`, `jeu:` = dossier du jeu, `registre:` = clé de registre), `url`, `correspondance` (`appid`, `appid-side`, `titre` : comment la page a été trouvée) |
| AppleGamingWiki, `{{Compatibility/macOS}}` (CC BY-NC-SA) | verdicts natif, Rosetta 2, CrossOver, Wine (GPTK/Whisky/Kegworks), Parallels ; méthode et date des témoignages | `[compat.applegamingwiki] natif`, `rosetta`, `crossover`, `wine`, `parallels` (`parfait`, `jouable`, `demarre`, `ko`), `methodes` (`"gptk whisky"`), `dernier_temoignage`, `url` |
| CrossOver, archive publique des recettes CrossTie `crossover.tie.gz` (aucune licence publiée : valeurs techniques seulement, voir plus bas) | recette en vigueur du jeu : gabarit de bouteille, DLL forcées (`HKCU\Software\Wine\DllOverrides`), dépendances, variables d'environnement de la bouteille, autres clés sous `Software\Wine` | `[compat.crossover] recette` (`com.codeweavers.c4.N`), `correspondance` (`steamid`, `steamid+titre`, `titre`), `confiance` (`haute`, `moyenne`), `recette_date`, `crossover_version`, `bouteille` (`win10_64`…), `dll_overrides` (telles que la recette les donne : `"xaudio2_7=n ; mfplay="`), `dll_overrides_par_exe`, `dependances` (nos verbes), `dependances_non_traduites` (identifiants), `graphismes` (`d3dmetal`, `dxvk`), `environnement`, `registre`, `url` ; et, fondus dans `[cidre]` : `dll_overrides`, `dependances`, `windows_version` |

Ce qu'on **ne reprend pas** :

- aucun texte éditorial des wikis (CC BY-NC-SA) : ni notes, ni descriptions,
  ni témoignages ; seules les valeurs des modèles sont lues, et la fiche cite
  l'URL de la page. Les notes ProtonDB (prose des utilisateurs) ne sont pas
  recopiées non plus : seules les options de lancement (des commandes) et les
  compteurs ;
- de la base CrossOver (CodeWeavers) : tout ce qui est texte ou avis —
  descriptions, notes d'installation, commentaires, médailles et classements,
  contributeurs — et la Compatibility Database du site (derrière un contrôle
  anti-robot, `robots.txt` y demande 100 s entre deux requêtes) ; voir
  « Recettes CrossOver » ;
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
contre ProtonDB platine/or (ou l'inverse) ; une clé de `[cidre]` déjà posée
(à la main ou par une source de rang plus haut) que la recette CrossOver
contredit ; une bouteille CrossOver 32 bits pour un jeu que la fiche dit
64 bits. Les contradictions ne modifient rien : c'est une relecture qui
tranche.

### Recettes CrossOver (source `crossover`)

**D'où.** CodeWeavers publie ses recettes CrossTie en une archive, sans compte
ni clé, que CrossOver télécharge lui-même :
`https://media.codeweavers.com/pub/crossover/tie/crossover.tie.gz` (miroir
`ftp.codeweavers.com`, même chemin ; 3 Mo, remise à jour chaque jour). C'est du
XML : racine `<c4p>`, puis `<applications>` et une entrée
`<app appid="com.codeweavers.c4.N">` par version minimale de CrossOver
(`<cxversion>`) — la plus haute est la recette en vigueur, les autres sont
celles des anciens CrossOver. Au 2026-10-13 : 4 489 recettes, 1 574 Steam ID
distincts (`<appprofile><steamid>`). Les `.tie` unitaires se prennent sur le
site, page par page, derrière un contrôle anti-robot : on ne les prend pas. La
page d'une recette, citée dans la fiche (`url`) et jamais téléchargée :
`https://www.codeweavers.com/compatibility/browse/name/?app_id=N`.

**Licence.** Aucune n'accompagne l'archive ; le site porte « Copyright ©
1999-2026 All Rights Reserved » sans conditions d'utilisation publiées, et la
licence de CrossOver (`codeweavers.com/crossover/eula`) ne vise que le logiciel
(« the software accompanying this License »), pas les recettes ni la base. Il
n'y a donc pas d'autorisation de reprise : l'archive n'est ni redistribuée ni
versée au dépôt (cache local), aucun texte n'en sort, et on n'en tire que des
valeurs techniques — des faits de configuration de Wine — pour les seuls jeux
qui ont une fiche (163 recettes sur 4 489). Constat, pas avis juridique : pour
revenir en arrière, `--sources` sans `crossover` et retirer les blocs
`[compat.crossover]` et les clés de `[cidre]` que `[cidre.sources]` lui
attribue.

**Rapprochement.** Par Steam ID quand la recette en porte un (`steamid`, ou
`steamid+titre` si le titre concorde aussi ; confiance `haute`). Sinon par
titre exact d'une recette de jeu sans Steam ID (`titre`, confiance `moyenne` ;
« exact » : à la casse, aux ®™©, aux apostrophes et tirets typographiques et
aux espaces près) — une recette qui porte un *autre* Steam ID est un autre jeu
(remaster, autre édition). Deux recettes pour un même Steam ID sans titre pour
les départager : rien n'est écrit, le cas sort dans le rapport (`ambigus`).

**Ce qui est lu d'une recette.** Les profils d'installation sans condition, ou
dont la condition `<useif>` vaut pour nous (`platform` = Mac, `sourcetype` =
steam, le gabarit de la recette) ; une condition qu'on ne sait pas évaluer (langue de
la bouteille, fichier d'installation) écarte le profil. Pas ce qui ne vaut que
pour l'installeur (`installerdlloverrides`, `installerenvironment`), ni les
profils posés pour une autre application de la bouteille. Les recettes n'ont
pas d'options de lancement.

**Ce qui entre dans `[cidre]`**, et seulement depuis une recette de confiance
`haute` (un titre ne dit pas que c'est la même distribution du jeu) :

- `dll_overrides`, au format du lanceur (`"a,b=n,b;c="`). `native` seul devient
  `n,b` : la recette installe la DLL native par une dépendance, pas nous (pas
  encore) — `n` seul empêcherait le jeu de démarrer, `n,b` retombe sur la DLL
  de Wine. Les DLL du chemin graphique (`dxgi`, `d3d9` à `d3d12`, `winemetal`,
  `nvapi`) restent celles de Cidre. La valeur d'origine est gardée dans
  `[compat.crossover] dll_overrides`.
- `dependances` : les composants CrossOver traduits en verbes façon winetricks
  par notre table (`vcrun2005`…`vcrun2022`, `dotnet40`, `dotnet35sp1`,
  `msxml3/4/6`, `corefonts`, `physx`, `xna40`, `d3dcompiler_47`, `wmp9`… ;
  `directx_jun2010` et `directx_feb2010` pour les redistribuables DirectX de
  juin et février 2010). Ce qu'elle ne sait pas nommer reste cité par son
  identifiant dans `dependances_non_traduites` ; « DXVK (Builtin) » et les
  variables `WINED3DMETAL`/`D3DMetal` deviennent `graphismes` (le chemin que
  CrossOver prend sur Mac : une donnée, Cidre a le sien).
- `windows_version` : **posé** (`--sans-crossover-windows-version` pour le
  retenir : les fiches concernées sortent alors dans le rapport,
  `windows_version_retenues`). Le lanceur le règle à chaque lancement, pour le
  jeu qu'il lance, et le retire pour un jeu qui ne le demande pas (voir
  « Version de Windows ») : le préfixe partagé n'en garde rien. Un gabarit
  n'est repris que s'il est un choix : recette pour CrossOver 23 ou plus
  (avant, `win7_64` ou `winxp` sont le défaut de l'époque, pas une exigence du
  jeu), plus ancien que win10 (win11 est aussi courant que win10 dans les
  recettes pour CrossOver 26 : un défaut, là encore), connu du lanceur (pas de
  Windows 9x), et pas un gabarit 32 bits pour un jeu 64 bits.

Une clé de `[cidre]` que la recette ne donne plus est retirée au passage
suivant, si elle venait de `crossover`.

Import du 2026-10-13 sur les 698 fiches : 163 reçoivent `[compat.crossover]`
(145 par Steam ID, 18 par titre) ; dans `[cidre]`, `dependances` sur 32 fiches
et `dll_overrides` sur 2 (33 fiches en tout) ; `windows_version` retenu sur 1
(Ancestors: The Humankind Odyssey, `win7`) ; 1 cas ambigu (Civilization III:
Complete, deux recettes) ; 2 contradictions (Secret World Legends et Rain
World : bouteille 32 bits, jeu 64 bits).
