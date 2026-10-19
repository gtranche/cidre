# Battle.net dans Cidre : faisabilite

Etat au 2026-10-18. Objectif : lancer le client Battle.net Windows et ses jeux dans Cidre, en
commencant par Diablo IV (D4) et Diablo II Resurrected (D2R). Diablo III et World of Warcraft ont
une version macOS native : ils sont hors sujet. D3DMetal et GPTK sont exclus.

## En bref

- **Le client tourne.** L'installeur officiel (1.0.66) installe le client 2.53.5 (build 17932,
  CEF 108, **32 bits**) dans un prefixe clone. La page de connexion account.battle.net se charge
  (`UAuth: finished loading. statusCode=200 state=Login`). La connexion elle-meme reste a faire par
  l'utilisateur.
- **Il a fallu le correctif wine11 0182.** Avant lui, aucun programme 32 bits ne pouvait faire de
  reseau sous Cidre. La fenetre 32 bits rebasee (0096) laissait passer cinq adresses ou poignees non
  traduites (detail plus bas). Tous les jeux 32 bits en ligne en profitent, pas seulement
  Battle.net. Le temoin `tests/h32fenetre.c` fait 8 echecs sur v1.5.15 et 0 avec 0182.
- **Les deux jeux visés sont en D3D12.** D4 et D2R passent par vkd3d-proton + KosmicKrisp. DXMT ne
  sert qu'au client, et encore : son CEF peut se passer d'acceleration materielle.
- **L'anti-triche ne semble pas un mur.** Warden de Blizzard n'a jamais banni pour Wine (position
  constante depuis 2012). D4 et D2R sont « Steam Deck Verified », donc tolerent Proton (Linux). Rien
  n'est encore verifie sous macOS : c'est l'objet de la manche de jeu.
- **Restent :** la connexion par l'utilisateur, le telechargement des jeux (D2R environ 30 Go,
  D4 environ 90 Go, sur le SSK), puis une manche par jeu jusqu'au menu.

## 1. Etat de l'art

Recherche web du 2026-10-18. Codeweavers.com refuse la lecture automatique (403) : ce qui vient de
CodeWeavers est donc tire d'extraits et d'articles qui les citent.

### Comment les autres font

| Lanceur | Recette |
|---|---|
| CrossOver | CrossTie « Battle.net Desktop App », bouteille neuve conseillee. D4 : CrossOver 24.0.1 (« tous les backends »), 26.1 + macOS 26.5 (correctif Rosetta), 26.3 (mise a jour du jeu). Sources : codeweavers.com/blog/mjohnson/2024/3/21, codeweavers.com/blog/mjohnson/2026/5/18. |
| Lutris | Script `battlenet-standard` (lutris.net/games/install/37360). Prefixe win64. `Battle.net.config` avec `Client.HardwareAcceleration=false`, `Client.Streaming.StreamingEnabled=false` et `Client.GameLaunchWindowBehavior=2`. Override `locationapi=d`. `Agent.exe` et `Battle.net Helper.exe` exclus de l'attente. D4 : `Battle.net.exe --exec="launch Fen"` (37221) ; D2R : `--exec="launch OSI"` (37245). |
| Heroic | Pas de boutique Battle.net : Battle.net s'y installe comme un programme Wine quelconque. |
| Whisky | Archive depuis le printemps 2025 (fork frankea/Whisky). |
| Proton / Steam Deck | D4 (2344520) et D2R (Infernal Edition, 11/02/2026) sont sur Steam et « Verified ». La version Steam de D4 se passe du client Battle.net, celle de D2R non. |

### Pieges connus

- **CEF :** l'acceleration materielle du navigateur integre casse sous Wine. Contournement documente :
  `Client.HardwareAcceleration=false` (bug Wine 50637). La recherche n'a trouve aucune source pour
  `--in-process-gpu` ou `--disable-gpu-sandbox` cote Battle.net. Pourtant, le client transmet bien
  ses arguments a CEF : mesure ici, `--in-process-gpu` supprime le processus GPU.
- **Fenetre grise :** `WINE_SIMULATE_WRITECOPY=1` (Proton, Wine-staging), depuis le client de
  decembre 2023. C'est exactement le defaut 5 ci-dessous, corrige ici sans simulation.
- **Agent :** « went to sleep » (BLZBNTBNA00000005, 2025) quand un nouvel Agent casse sous Wine. Le
  contournement est de geler l'ancien dossier `Agent.NNNN` (lemmy.cleberg.net/post/37844). Septembre
  2026 : installation figee a 25 % (BLZBNTBTS00000029, discuss.cachyos.org/t/36284).
- **Installeur :** une langue d'installeur differente de la locale de la machine peut bloquer a 45 %.
  On passe donc `--lang=frFR` (langue du Mac).
- **D4, Saison 14 (3.1.0, 30/06/2026) :** le jeu exige l'export `FindNextFileNameW`. Corrige par un
  hotfix Proton du 03/07/2026 (gamingonlinux.com/2026/07). Wine 11.18 l'exporte deja (bouchon dans
  kernelbase/file.c).
- **Rosetta, janvier 2026 :** blocage de D2R et D4 sous CrossOver, corrige par macOS 26.5. Cidre
  passe par FEX : ce defaut ne le concerne pas directement.
- **D2R sans D3DMetal :** rectangles blancs a l'Acte 4 avec la voie vkd3d/MoltenVK
  (codeweavers.com forum diablo-ii-resurrected msg=287278). A surveiller avec KosmicKrisp.
- **Exigences D4 :** Windows 10 1909 ou plus, DirectX 12 obligatoire, 90 Go sur SSD, ray tracing
  optionnel (eu.support.blizzard.com/article/251518).

### Anti-triche et bannissements

Blizzard ne soutient pas Wine mais n'a jamais banni pour lui : Diablo III en 2012
(engadget.com/2012-07-03), Overwatch avec DXVK en 2018, ou les bannissements etaient de probables faux
positifs (phoronix.com/news/Blizzard-Banning-DXVK-Wine). Le statut « Verified » de D4 et D2R implique
que Warden tolere Proton. Contrairement a EAC (memoire anti-triche), Warden est un module en espace
utilisateur, sans pilote, que le jeu telecharge. Rien a porter ni a contourner : il faut seulement
qu'il tourne sous FEX.

## 2. Ce que le prototype a montre

Essais dans `~/Dev/cidre-battlenet/essai/` : prefixe clone `pfx-bnet` et runtime clone, jamais
`pfx-arm64ec` ni le runtime installe. Aucune capture d'ecran : l'etat a ete lu dans les journaux du
client (`AppData/Local/Battle.net/Logs`), le net-log de Chromium et la liste des fenetres Wine
(sonde `EnumWindows`).

| Etape | Symptome | Cause | Correctif (0182) |
|---|---|---|---|
| Installeur | BLZBNTBTS00000028 en 4 ms | `getaddrinfo` 32 bits rend 0xC0000005 : le relais wow64 de ws2_32 (cote unix) lit l'adresse de l'invite sans la rebaser | ULongToPtr rebase dans ws2_32, secur32, crypt32 et dnsapi (comme winevulkan et opengl32) |
| HTTPS 32 bits | WinHTTP 12157 | `sock_ioctl_send` lit le tableau de tampons a l'adresse brute | `u64_to_user_ptr` rebase en wow64 |
| Processus GPU de CEF | 0xC0000005 en boucle, « GPU process isn't usable » | win32u projette les bits d'une DIB (section) sans borne : la vue tombe hors de la fenetre de l'invite | plafond de l'invite par defaut pour une vue non-image demandee pendant un appel wow64 |
| Rendu de CEF | `int3` dans libcef, rendu tue en boucle | `VirtualProtect` rend PAGE_WRITECOPY pour une page de .data deja ecrite, et Chromium exige PAGE_READWRITE | ancienne protection lue par `mincore` (page copiee ou modifiee : PAGE_READWRITE) |
| Rendu de CEF (bis) | politique SystemCallDisable aleatoire | `GetProcessMitigationPolicy` rend TRUE sans remplir le tampon | tampon remis a zero |
| Page de connexion | ERR_FAILED, `os_error 10038` (WSAENOTSOCK) | `IOCTL_AFD_GET_EVENTS` passe une poignee dans `in_buffer`, que le relais rebase comme une adresse | poignee tronquee a 32 bits |

Essais ecartes :

- La simulation PAGE_WRITECOPY a la Proton (pages en lecture seule, conversion a la premiere faute)
  fait un « Bus error » a l'amorcage. Activee plus tard, elle provoque une recursion d'exceptions sous
  FEX.
- `--single-process` evite le plantage du rendu mais fige le client.

Reglages qui restent necessaires au client :

- `Battle.net.config` avec les cles de Lutris. Sans acceleration materielle, CEF passe par SwANGLE,
  qui echoue (`vkCreateWin32SurfaceKHR`), et le processus GPU s'arrete.
- Avec acceleration materielle (ANGLE D3D11 sur DXVK i386), une surface echoue
  (`SwapChain11 ... 0x80004005`), mais le processus GPU survit et la page se charge.

Lequel des deux donne une fenetre propre, il faudra le juger a l'ecran avec l'utilisateur.

## 3. Plan d'integration dans Cidre

**Prefixe dedie** `wine/pfx-battlenet`, et non `pfx-arm64ec`, pour trois raisons :

- L'Agent et le client restent en arriere-plan et tiennent un wineserver. Dans le prefixe Steam, ils
  bloqueraient `fin_de_partie.sh` et rejoindraient chaque jeu Steam.
- `lancer_depuis_steam.sh` demarre `faux_steam.exe`, qui n'a rien a faire ici.
- Les reglages de Battle.net (`Battle.net.config`, langue, mises a jour de l'Agent) ne doivent pas
  toucher les jeux Steam.

Il sera cree par `cidre setup` comme le prefixe Steam, sans le pont Steam : clone APFS d'un modele
neuf, puis DXVK et DXMT en syswow64 et system32.

**Installation** : `cidre battlenet installer`.

- Telecharge l'installeur officiel
  (`downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe`) et verifie
  sa signature Authenticode (DigiCert, « Blizzard Entertainment »).
- Le lance avec `--lang=<langue du Mac> --installpath="C:\Program Files (x86)\Battle.net"`.
- Pose ensuite `Battle.net.config`.
- JSON d'avancement pour Verger : installeur, Agent, client.

**Jeux** : source `battlenet`, identifiants `bnet-<code>` (`bnet-osi` pour D2R, `bnet-fen` pour D4).

- Les identifiants sont deja acceptes par `fiche_profil.sh` (`id_sur`) et `profil_cidre.sh`.
- Detection : cles `Uninstall` du registre du prefixe, ecrites par l'Agent (chemin d'installation,
  nom), ou `ProgramData/Battle.net/Agent/product.db`.
- `cidre list --json` les rend avec `"source":"battlenet"`.
- Le telechargement et les mises a jour restent l'affaire du client : il n'existe pas d'equivalent de
  SteamCMD.

**Lancement** : `cidre play bnet-osi`.

- Par le client : `Battle.net.exe --exec="launch OSI"` (Lutris). Le client doit etre connecte et
  l'Agent en marche, ce qui donne les mises a jour et le jeton de session.
- Le lancement direct (`D2R.exe -launch`) est a essayer en second : il depend de la session ouverte
  par le client.
- Il passe par `lancer_depuis_steam.sh`, a condition d'y ajouter `CIDRE_SANS_FAUX_STEAM=1` (pas de
  client de service) et `WINEPREFIX=wine/pfx-battlenet`. Fiche, voie graphique, HUD, journal,
  `expliquer_sortie.sh` et sauvegardes suivent comme pour un jeu local.
- Fin de partie : le jeu sort, le client reste ouvert. Il faut un `cidre battlenet arreter` explicite,
  et ne pas reutiliser `fin_de_partie.sh` tel quel.

**Fiches** : `profils/bnet-osi.toml` et `profils/bnet-fen.toml`.

- `[cidre] dx12 = true`, pour vkd3d-proton + KosmicKrisp.
- `windows_version = "win10"`.
- Pour D4, `sm66` selon la famille de GPU, comme Demonologist.

**Verger** (`~/Dev/verger`) :

- `Game.Source` doit apprendre `battlenet` : aujourd'hui `Source(rawValue:) ?? .steam` le prendrait
  pour un jeu Steam.
- Une feuille « Battle.net » : installer le client ; ouvrir le client pour se connecter ou telecharger
  un jeu ; liste des jeux installes, bouton Jouer.
- Les jaquettes viennent des fiches (pas d'appid Steam).
- Toujours par le contrat `cidre --json`.

**Livraison de 0182** : prochaine reconstruction de Wine.

- Construire ntdll (deux drapeaux TEB), ws2_32, secur32, crypt32, dnsapi et kernelbase.
- Temoin `h32fenetre` a ajouter a la verification de reconstruction.

## 4. Point d'etat au 2026-10-19 (11:30)

Essais d'affichage avec l'utilisateur devant l'ecran. Aucune capture du bureau : il decrit ce
qu'il voit, et la page est relue par DevTools (`--remote-debugging-port`, DOM et
`Page.captureScreenshot` de la page seule).

| Essai | Ce que l'utilisateur voit | Cause, correctif |
|---|---|---|
| Configuration d'origine (Qt OpenGL/ANGLE, CEF accelere, GPU dans un processus a part) | bandeau Qt, puis une zone noire a la place de la page | winemac refuse la chaine Metal a une fenetre enfant sans donnees propres (« Cross-process child window Metal swapchains are not implemented ») : DXVK rend `VK_ERROR_INCOMPATIBLE_DRIVER`, la vue CEF reste noire |
| `--disable-gpu --disable-gpu-compositing`, puis `--in-process-gpu` | toujours noir | meme cause : la couche Metal de Qt couvre la fenetre enfant GDI de CEF |
| Qt en logiciel (`QT_QUICK_BACKEND=software QT_OPENGL=software`) + `--in-process-gpu` | formulaire, icones et boutons, mais aucun texte | dwrite.so : relais wow64 non rebases, corrige par wine11 **0188** (sur main) ; texte verifie ensuite par DevTools |
| meme chose, apres connexion : panneau principal | barre de navigation absente | essai fait avant 0188 : la navigation est du texte. Avec 0188 (11:53), le panneau s'affiche en entier : Accueil, Jeux, Boutique, favoris, amis, page D2R avec « Installer » |
| « Modifier » l'emplacement d'installation | le client se ferme (code 1, sans trace) | non reproduit hors du client (la boite de dossier 32 bits marche en sonde) ; contournement : le dossier par defaut `C:\Program Files (x86)\Diablo II Resurrected` est un lien vers le SSK |
| Configuration d'origine + `--in-process-gpu` + winemac **0189** (chaine Metal posee sur la vue Cocoa de l'enfant quand son parent est au processus) | « ne s'affichait pas comme il faut » | DXVK cree ses swapchains (plus aucune erreur au journal), mais la composition reste fausse ; a instruire |

Vu au journal et confirme : la connexion fonctionne jusqu'a l'Authenticator, mot de passe accepte
puis « Auth complete ». La session n'a pas ete gardee apres la fermeture du client.

Limite de la verification : DevTools montre ce que CEF dessine, pas la composition de la fenetre
(couches Qt et CEF superposees par winemac). Seul l'utilisateur voit cette derniere.

Connexion faite le 2026-10-19 a 11:53, en Qt logiciel, « Rester connecte(e) » coche : le panneau
principal s'affiche en entier (capture envoyee par l'utilisateur).

Defauts notes pour plus tard, dans la boite de choix de dossier 32 bits (« Changer de repertoire »,
qui s'ouvre desormais sans planter) :

- les boutons OK et Annuler n'ont pas de libelle ;
- la liste des lecteurs, a gauche, est vide.

Le dossier par defaut, lie au SSK, evite d'y passer.

Voie retenue pour avancer :

1. Connexion une seule fois en Qt logiciel (le formulaire s'y affichait ; seul le texte manquait,
   corrige par 0188), avec « Rester connecte(e) » coche, pour garder la session.
2. Session gardee : diagnostic du panneau principal sans l'utilisateur. DOM et rendu de chaque vue
   CEF par DevTools, puis 0189 et la superposition Qt/CEF, en comparant Qt logiciel et Qt OpenGL.
3. Installation de D2R par le bouton du client, sans « Modifier », ou par `--exec`.

### D2R (2026-10-19, 12:20-12:50)

- Telechargement : 31,5 Go par le client, environ 35 Mo/s, sur le SSK, par le dossier par defaut
  `C:\Program Files (x86)\Diablo II Resurrected`, qui est un lien vers le SSK.
- Premier « Jouer » : le client se ferme. `Client.GameLaunchWindowBehavior=2` (repris de Lutris)
  veut dire « quitter au lancement » ; il faut 0 pour garder le client ouvert.
- Ensuite, D2R meurt en 3 s : « D2R_loader.dll failed to initialize », c0000005. Le chargeur protege
  ecrit son code dans une section par une vue RW et l'execute par une vue RX. Wine ne previent FEX
  que pour les images (`notify_map_view_of_section`) : FEX refuse d'executer la vue RX (faute
  d'execution a l'adresse du saut). Corrige par wine11 **0190**, qui annonce a FEX toute vue non-image
  executable comme un `NtProtectVirtualMemory`.
- Avec 0190 : le chargeur s'initialise et le jeu va jusqu'a `uxtheme`. Puis plusieurs de ses fils
  debordent leur pile, dans une passerelle ARM64EC de kernelbase, pendant la mise en place d'une
  exception (cascade d'exceptions : int3 et assertions de la protection, c0000420). Les fils
  restants attendent indefiniment. A instruire : taille des piles des fils crees par le chargeur,
  cout en pile de la remise d'exception ARM64EC sous FEX.
- Warden et le rendu D3D12 ne sont pas encore atteints.

## 5. Suite

1. Connexion par l'utilisateur, avec le client lance dans le prefixe d'essai (JEU DEMANDE a la
   coordination).
2. Telechargement de D2R par le client, sur le SSK (« Jeux Cidre/Battle.net »), en un long creneau.
   D4 ensuite (90 Go).
3. Manche D2R : `--exec="launch OSI"` avec dx12 (vkd3d + KK), jusqu'au menu.
4. Manche D4 : `--exec="launch Fen"`. Il faudra sans doute SM 6.x et des atomiques 64 bits : voir le
   chantier DX12 et la fiche Demonologist. On saura alors si Warden accepte FEX.
5. Seulement ensuite, la source `battlenet` dans `cidre` et Verger.

Outils du prototype, hors depot : `~/Dev/cidre-battlenet/` (`essai/lancer.sh`, sondes `sondes/*.c`,
constructions hors arbre `wine/construire*.sh`).
