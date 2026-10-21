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
- Avec `FEX_SMCCHECKS=full` (controle complet du code auto-modifie), plus aucun debordement de
  pile : la cascade venait sans doute de code dechiffre en place que FEX executait depuis un
  bloc perime. Le chargeur tourne alors 4 min 48 s de CPU a 100 % d'un coeur, puis se fige :
  plusieurs fils sont en `wait_suspend` (suspendus par le chargeur, jamais repris) et le fil
  principal les attend. Piste : la suspension de fils et la lecture de leur contexte sous FEX
  ARM64EC (`NtSuspendThread`/`NtGetContextThread`, BTCpuSuspendLocalThread). Chantier de fond.

### D2R, fils suspendus et SMC (2026-10-19, 13:00-15:25)

Session d2r (worktree `~/Dev/cidre-d2r/depot`, branche `d2r-fils`), runtime clone
`~/Dev/cidre-d2r/wine11-arm64`, FEX pose aussi dans `system32` de `pfx-bnet` (c'est
cette copie que Wine charge).

- Le gel « fils en `wait_suspend` » venait de trois defauts de FEX ARM64EC, tous
  corriges par fex **0194** :
  1. le retour arriere d'une boucle par saut conditionnel ne controlait pas la sonnette
     de suspension : un fil qui boucle ne se suspendait jamais, et le `NtGetContextThread`
     de celui qui le suspendait attendait sans fin (temoin `tests/h64suspend.c`, cas D) ;
  2. la construction de l'IR etait quadratique (`CreateNewCodeBlockAfter`) : sous
     `FEX_SMCCHECKS=full`, un bloc par instruction, d'ou les 5 min a 100 % ;
  3. sous SMC complet, l'invalidation lancee depuis le JIT libere de la memoire sans
     `InSyscallCallback` : ntdll la renvoyait a FEX, qui reprenait `CodeInvalidationMutex`
     deja tenu (pile du fil principal relevee par lldb).
- Trace serveur : le chargeur cree 6 fils suspendus, remappe D2R.exe et lui-meme par des
  sections (vues `SEC_NO_CHANGE`, une RW et une RX de la meme section au debut), liste les
  processus, suspend tous ses fils, lit leurs contextes et les reprend.
- `FEX_SMCCHECKS=full` n'est pas ce qui evitait le debordement de pile : il ralentissait le
  chargeur au point qu'il n'atteignait pas l'endroit fautif. Avec 0194 et sans `full`, le
  chargeur charge winemac.drv et uxtheme en 9 s de CPU, puis meurt de facon non
  deterministe :
  - soit trois fils en « stack overflow » a la meme adresse (thunk d'entree x64 de
    kernelbase), avec StackLimit = DeallocationStack + 0x2000 (valeur ecrite par
    l'invite, a la mode Windows) et RSP = StackLimit + 0x2000. Sous Wine/macOS, les 32
    premiers Kio d'une pile sont sans acces ou garde (pages de 16 Kio) contre 8 Kio sous
    Windows. Correctif prepare, non valide : `~/Dev/cidre-d2r/wine/virtual-pile.c`
    (DeallocationStack annonce decale de 2 pages d'hote moins 2 pages Windows) ;
  - soit un fil sur un pointeur de section critique corrompu
    (`RtlIsCriticalSectionLockedByThread`), apres quoi un autre fil charge shell32/ole32.
- Avec `full` et 0194, le chargeur passe le point de gel mais tourne encore 3 min, surtout
  dans les fautes W^X des invalidations (`VirtualDontNeed` de 4 Mio de pile d'appels a
  chaque invalidation), sans fenetre.
- Essai ecarte : SMC complet seulement dans les vues de section executables
  (`~/Dev/cidre-d2r/fex/hybride-smc-vues-section.diff`) : meme debordement, plus lent.
- Outils : `~/Dev/cidre-d2r/manche_sonde.sh` (D2R 90 s, arret seul), `sonde_pile.c`
  (contexte x64 et pile de chaque fil, depuis un autre processus ; ne marche pas sur un fil
  bloque en mode cooperatif), `lldb_faute.py`, ntdll.so de sonde (ERR + pile invitee au
  debordement).

### D2R, cascade d'exceptions et code perime (2026-10-19, 15:30-16:05)

Session d2r-menu, meme environnement (runtime clone, `pfx-bnet`, FEX 0194).

- `virtual-pile.c` (garde de 32 Kio) est hors sujet. La limite de pile Dealloc+0x2000 vient de
  `RtlCreateUserStack` cote PE : les fils fautifs tournent sur des fibres (`CreateFiberEx`).
  Une sonde de pile au debordement montre la pile de 4 Mio remplie par 632 cycles de 6,6 Kio :
  une cascade d'exceptions imbriquees, pas un probleme de garde.
- La protection pose son crochet dans `ntdll!Wow64PrepareForException` (pointeur lu dans le
  `KiUserExceptionDispatcher` x64, crochet = D2R_loader+0x1b22420). Elle s'en sert pour dechiffrer
  D2R.exe page a page sur faute d'execution, ce qui marche. Les `int3` et `int 2c` (0xc0000420)
  du fil 0138, a chaque manche, sont des sondes anti-debogueur rattrapees.
- wine11 **0195** : `RtlIsEcCode` lisait EcCodeBitMap sans borne. Sur une adresse de retour
  aberrante (0x20074e904cb80), il fautait pendant `virtual_unwind`, et la repartition reprenait
  la meme faute jusqu'au debordement. Temoin `tests/h64isec.c`.
- Temoins sans defaut : fibres + `int3`/`int 2c` (`tests/h64fibres.c`) ; crochet
  `Wow64PrepareForException` + `call` vers une adresse non projetee + `NtContinue`, avec une faute
  imbriquee (`tests/h64prepare.c`).
- Avec 0195, en mtrack, le chargeur meurt encore, de facon non deterministe : saut vers une
  adresse non projetee de la zone 0x6fff... que son crochet ne redirige pas ; pointeur de section
  critique aberrant ; section critique de FEX jamais rendue ; `NtCreateUserProcess` en boucle
  avec une liste d'attributs aberrante, puis sortie code 5. Toujours des valeurs fausses.
- Trois manches de 4 min, avec 0195 :

  | FEX | Issue |
  |---|---|
  | mtrack | mort en 10 s |
  | `FEX_SMCCHECKS=full` | 4 min sans aucune erreur ni assertion, encore dans le chargeur |
  | 0194 + SMC complet sur les vues de section (`hybride-smc-vues-section.diff`) | passe winemac et uxtheme, puis 11 assertions et debordement |

- Diagnostic : en mtrack, FEX execute du code perime. Il ne piege en ecriture que les pages RWX ;
  une vue RX ecrite par une autre vue (section) ou modifiee autrement lui echappe. Le SMC complet
  sur les seules vues de section ne suffit pas : d'autres ecritures echappent encore.
- Suite : en `full`, faire relever par FEX chaque bloc invalide par la verification (adresse,
  type de projection, intervalle RWX ou non) pour savoir quelles ecritures mtrack ne voit pas,
  puis les suivre (FEX). Outils : `~/Dev/cidre-d2r/manche_longue.sh`, sondes `wine/virtual-sonde*.c`
  et `wine/b/dlls/ntdll/signal_arm64ec.c.sonde7`.

### D2R, code auto-modifie sous mtrack : 0196 et 0197 (2026-10-19, 16:05-16:25)

- Le chargeur garde deux alias RW de son code : sa section entiere projetee en RW
  (0x115c60000) avec `.text` reprojete en RX a sa base, et D2R.exe reprojete sur une section
  (vue RW a 0x120050000, image RWX a 0x140000000). D2R.exe est dechiffre page a page : NOACCESS,
  faute d'execution, ecriture par l'alias, puis `NtProtect` en RX, ce qui fait invalider FEX.
  Pas d'ecriture par `NtWriteVirtualMemory`. Ses appels systeme directs passent par les
  enveloppes de Wine qui previennent FEX.
- Temoin `tests/h64smc.c` (code reecrit sans changer de protection). En mtrack, la memoire RWX
  privee etait perimee a 100 %, meme pour une page seule. Deux causes :
  - wine11 **0196** : la branche JIT de `virtual_handle_fault` accordait l'ecriture par APRR
    sans regarder la protection Windows, et le piege de FEX ne faisait jamais faute ;
  - fex **0197** : avec des pages d'hote de 16 Kio, proteger une page de 4 Kio ne piege rien
    tant qu'une voisine reste inscriptible ; piege et invalidation par 16 Kio. 0197 reprend
    aussi le SMC complet dans les vues de section executables non inscriptibles (alias).

  | h64smc (mtrack) | 0194 | + 0196 | + 0196 + 0197 |
  |---|---|---|---|
  | A page RWX seule | perime | OK | OK |
  | B page RWX, voisine RW (meme page d'hote) | perime | perime | perime |
  | C bloc RWX | perime | perime | OK |
  | D, E vue RX/RWX ecrite par une vue RW | perime | perime | OK |

  Non-regression h32smc, h64prepare, h64fibres, h64isec, h32temps et sonde_wx : OK. Manche
  PEAK (deadlock W^X, meme branche) a faire avant toute release.
- D2R avec 0196 + 0197, 3 manches de 4 min en mtrack : aucune fenetre ; meme effondrement en 2
  a 4 min (assertions plus nombreuses, cascades d'exceptions, `RtlVirtualUnwind2` qui lit NULL,
  debordements). Etendre le SMC complet aux vues RWX n'y change rien. Ces defauts ne sont donc
  pas ceux qui bloquent D2R ; seul `FEX_SMCCHECKS=full` reste propre (mais trop lent).
- Suite : en full, faire relever par FEX les blocs dont la verification detecte un changement
  (adresse, type de projection, intervalle) pour trouver les ecritures que mtrack ne voit pas.

### D2R, SMC complet : livelock (0198) et pointeur faux (2026-10-19, 17:00-18:05)

Session d2r-smc, meme environnement. Sonde FEX hors serie (`~/Dev/cidre-d2r/fex/FEX/Source/Windows/Common/SondeSMC.h`,
fil rapporteur natif toutes les 2 s : compilations, blocs perimes trouves par la verification complete,
invalidations et leur cout, fiche de chaque page perimee) ; sonde ntdll SONDE8/9 dans `call_seh_handlers`
(exception d'origine, cadres, registres au saut fautif).

- Le « full propre mais trop lent » etait un livelock. Jusqu'a t=24 s, environ 750 compilations/s et aucun
  bloc perime. A t=24 s, le chargeur rechiffre D2R.exe (5 600 `NtProtect` en NOACCESS) pendant qu'un fil y
  execute encore : FEX compile alors 51 000 blocs/s a la meme adresse (0x14155f8e4), chacun declare perime,
  invalide, recompile, jusqu'a la fin (850 ms d'invalidation par 2 s). Le bloc d'entree sur page non
  executable donne une instruction NOEXEC de taille 0, que le controle complet validait quand meme :
  `ValidateCode` sur 0 octet compare un registre jamais ecrit, donc « code change » a chaque passage, et la
  faute d'execution que le crochet de la protection attend n'est jamais levee. Corrige par fex **0198**.
- Avec 0198, full ne trouve **aucun bloc perime en 170 s**, puis s'effondre comme mtrack. Le code perime n'est
  donc pas ce qui bloque D2R (0196/0197 restent justes pour h64smc).
- Les effondrements viennent d'un pointeur faux d'un octet : un fil saute vers 0x6fffa99c4e60, 0x6fffa95af46c,
  0x6fffa99eaf94 ou 0x6fff979c34bc, c'est-a-dire du code du chargeur (0x6ffff7xxxxxx) dont l'octet des bits
  24-31 vaut 0xa9 (4 fois) ou 0x97 au lieu de 0xf7. Au saut, la pile du fil est presque vide (0x440 octets
  sous son sommet, [rsp]=0) : il s'agit du depart d'un fil ou d'un contexte pose, pas d'un `call`. Le
  deroulement de ce saut lit [Rsp=0] dans `RtlVirtualUnwind2`, d'ou la cascade et le debordement.
- Autre issue, une manche sur deux environ : interblocage sur `ThreadCreationMutex` de FEX
  (xtajit64+0x3b25a8), tenu par le fil 013c ; les fils 0024 et 0128 l'attendent. Essai 0199 (verrou non tenu
  entre les notifications avant et apres de `NtProtect`, `NtAllocate`, `NtFree` et `NtUnmap`) : sans effet,
  non garde (`~/Dev/cidre-d2r/fex/essai-0199-verrou-hors-appel.diff`).
- Ecartes par mesure : crypto (temoins `tests/h64crypto.c` et `tests/h64sha.c` : AES-NI, PCLMULQDQ, CRC32,
  SHA-1/256 justes sous FEX), AVX (`FEX_HOSTFEATURES=enablecrypto,disableavx` : meme interblocage), TSO strict
  (`FEX_VECTORTSOENABLED`, `FEX_MEMCPYSETTSOENABLED`, `FEX_STRICTINPROCESSSPLITLOCKS` : meme pointeur faux).
  `disablecrypto` change le chemin du chargeur (plus de compilation apres 20 s), sans progres.
- Suite : relever les contextes que le chargeur pose sur ses fils (`NtSetContextThread`, `NtContinue`,
  `NtCreateThreadEx` : RIP avant et apres la conversion x64/ARM64EC) pour trouver ou l'octet 3 change ; puis la
  pile de 013c pendant l'interblocage (`sample` du processus Wine : `~/Dev/cidre-d2r/manche_sample.sh`).

### D2R, nanomites, EFLAGS (0199), faute a cheval (0200) et pages de 16 Kio (2026-10-19, 18:05-18:40)

Sondes : ntdll PE SONDE11/12 (contexte de depart des fils, NtContinue/NtSetContextThread, chaque exception
vue par `prepare_exception_arm64ec`), ntdll.so SONDE10 (projections et allocations >= 1 Mio), FEX anneau des
4 096 dernieres entrees de `CompileBlock` vide au saut vers une adresse non projetee, avec les octets du code.

- Le chargeur execute par **nanomites** : plus de 150 000 `int3` en 4 min sur le fil principal, traites par son
  crochet `Wow64PrepareForException`, qui choisit la suite d'apres les EFLAGS du contexte puis `NtContinue`.
- **PF, AF et DF etaient perdus a chaque exception**, a l'aller et au retour (wine11 `unwind.h` et FEX
  `StoreStateToPackedECContext` ne portaient que NZCV+TF ; le crochet ne voyait jamais PF ni AF). Temoin
  `tests/h64eflags.c` : 17 echecs sur 21. **0199** (wine11 + fex) : PF, AF, DF en bits 26, 27, 25 de Cpsr ; DF
  et AF effaces pendant le gestionnaire comme sous Windows x64. Temoin : 0 echec.
- **Faute d'execution d'une instruction a cheval** : FEX signalait Rip, x86 signale le debut de la page suivante ;
  le crochet dechiffrait sans fin la page deja dechiffree (150 000 fautes a 0x14002CFFC). **0200** (fex). Temoin
  `tests/h64faute_page.c` : echoue avant, passe apres.
- Hypothese ecartee (SONDE10) : pas de copie du chargeur projetee ailleurs.
- Avec 0199 + 0200, D2R devient **deterministe** : 3 manches sur 3 meurent a 25 s, `jmp rdx` vers 0x1C55F07BA.
  Le bloc fautif est un `switch` MSVC de D2R.exe (0x140bb86d0, constructeurs statiques) : `rdx = base +
  table[0x140bb9380 + 4*idx]`. 0x855F07BA est une entree **encore chiffree** : la page 0x140bb9000 est
  `PAGE_NOACCESS` (protection Windows relevee au saut), mais ses voisines 0x140bb8000 et 0x140bba000 sont deja
  dechiffrees en `PAGE_EXECUTE_READ`, et les quatre partagent **une page d'hote de 16 Kio**, donc lisible. Sous
  Windows (4 Kio), la lecture ferait faute et le crochet dechiffrerait la table ; ici elle rend l'octet chiffre.
- **Cause racine** : une protection de 4 Kio plus stricte que ses voisines ne peut pas etre appliquee sur une page
  d'hote de 16 Kio (Apple Silicon). Les pointeurs « faux d'un octet » des manches precedentes en relevent sans
  doute aussi. CrossOver passe par Rosetta, dont les processus ont des pages de 4 Kio.
- Suite (chantier) : faire respecter le NOACCESS de 4 Kio dans une page d'hote mixte. Piste : page d'hote
  protegee a l'intersection des droits ; a la faute, si la page de 4 Kio visee est permise, ouvrir la page
  d'hote le temps d'une instruction invitee (FEX sait re-executer une instruction seule, cf. SMC en ligne) et
  la decodeur ; sinon remonter la faute a l'invite. Le crochet dechiffre alors la table comme sous Windows.

### D2R, pages de 4 Kio dans une page d'hote de 16 Kio : 0201 et 0203 (2026-10-19, 18:35-19:26)

- **0201 (wine11, ntdll.so)** : une page d'hote d'une vue de section (ni valloc, ni JIT) dont une page de 4 Kio
  est engagee sans aucun droit pendant qu'une autre est accessible est protegee a `PROT_NONE`. Les acces permis aux
  voisines font faute et `segv_handler` les rejoue (decodeur ARM64 : load/store entier et SIMD, paires, LD1/ST1,
  ordonnes, exclusifs, CAS, LSE, DC ZVA) a travers un alias `mach_vm_remap` de la page, sous `virtual_mutex`. Temoin
  `tests/h64sous_page.c` : A et G echouaient (lecture NOACCESS sans faute, saut dans une table chiffree), A-G passent ;
  2,4 us par acces rejoue. `CIDRE_SOUS_PAGES=0` rend l'ancien comportement, `=2` couvre aussi VirtualAlloc (jamais
  essaye en jeu) ; `CIDRE_DIAG_SOUS_PAGES=1` compte pages fermees et acces rejoues.
- Avec 0201, la mort a 25 s disparait : 4 096 pages d'hote fermees, jusqu'a 8 M d'acces rejoues sans erreur.
- **Gel a 30-60 s** : `ThreadCreationMutex` de FEX garde par le fil 013c du chargeur ; un autre fil l'attend dans le
  chemin de faute de FEX apres une faute d'execution native sur `ntdll!NtQueryPerformanceCounter$hybpatch_thunk`. Le
  chargeur crochete les souches x64 d'appel systeme de ntdll (EXP+#NtClose, EXP+#NtQueryVirtualMemory) en
  `PAGE_EXECUTE_READWRITE` ; macOS refuse W+X et Wine retirait l'execution a toute la page d'hote.
  0201 contient aussi une bascule W^X a la main (`bascule_wx_page`, pages hors MAP_JIT : RX a une faute d'execution
  permise, RW a une ecriture permise). Temoin `tests/a64rwx_voisine.c` (arm64 natif) : echoue avant, A-D apres.
- **0203 (fex)** : `ThreadCreationMutex` n'est plus tenu de la notification « avant » a la notification « apres »
  (Alloc, Free, Protect, Unmap traites au retour). Seul, il deplace le gel ; garde par prudence.
- Non-regression des temoins inchangee (h64smc 4/5, le cas B echouait deja ; h64eflags, h64faute_page, h64suspend,
  h64fibres, h64prepare, h64crypto, h64sha, h64alerte, h32smc). **[A VALIDER avant toute release : `tests/sonde_wx.c`
  et une manche PEAK (W^X), Exp33.]**
- D2R ensuite (134 s, 85 s) : le chargeur pose ses crochets, puis des appels systeme faux (NtCreateUserProcess avec
  des arguments pris dans du code, NtImpersonateAnonymousToken en boucle), puis c0000005 non geree. La numerotation de
  Wine suit celle de Windows sans les trous (egale jusqu'a ~0x5F) ; meme divergence sous Linux, ou D2R tourne. Piste :
  code auto-modifie dans les souches crochetees (meme famille que h64smc B : page RWX a cote d'une page RW).

### D2R, mort déterministe après un nanomite ; 0206 (2026-10-20, nuit)

- **0206 (wine11, signal_arm64.c)** : l'émulateur des pages d'hôte mixtes (0201) rejoue aussi LD1/ST1 à un élément,
  LD1R et CASP. FEX émet ces formes pour movhps, pinsr*, insertps, pextr* en mémoire, movddup, vbroadcast* et
  cmpxchg16b. Avant, l'invité recevait une violation d'accès à tort sur une page de 4 Kio permise. Témoin
  `tests/h64sous_page.c`, cas J : figé à J1 avec 0201, J1-J7 passent avec 0206. En jeu, aucun accès de ce genre n'a
  été vu en 240 s : ce n'est pas la cause de D2R.
- **La mort de D2R est déterministe.** Elle suit toujours le même nanomite du chargeur (int3 à 0x6ffff679f79e, repris
  à 0x6ffff7025285), quel que soit le fil, avec les mêmes registres au bit près ; les morts dans memcpy, RtlRunOnce et
  arm64x_check_call relevées avant sont la même. Écartés :
  - mauvaise compilation par blocs (FEX_MAXINST=1, FEX_MULTIBLOCK=0) ;
  - drapeaux (159 séquences de la trace identiques sous FEX et Rosetta) ;
  - registres à travers les nanomites (h64nanomites) ;
  - SetThreadContext (aucun) ;
  - course simple.
  Une pause de 1,5 s à ce point change l'adresse fausse, et le pas à pas TF l'évite : le pointeur dépend du temps
  (contrôle de durée ou clé). Suite : pas à pas plus long jusqu'à la lecture fautive, sources de temps (RDTSC de FEX,
  KUSER, QueryPerformanceCounter).
- Défaut réel hors D2R : SetThreadContext(CONTEXT_FULL) sur un fil suspendu pendant un appel ARM64EC le fait repartir
  en natif sur l'adresse de retour x64 (témoin h64appel_ec.c, mode 2). Correctif 0207 à faire.

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

## 6. Lancement par `cidre play` (2026-10-21)

Code de la source `battlenet` (point 5 ci-dessus, avance : D2R s'affiche sous Cidre depuis le 21/10).

- **`tests/battlenet.sh`** porte tout ce qui touche au client : `prefixe`, `jeux`, `etat`, `ouvrir`,
  `arreter`, et pour le lanceur `preparer` et `jouer`. Temoin sans jeu : `tests/tester_battlenet.sh`
  (prefixe fabrique ; la partie a faux processus, `CIDRE_ESSAI_PROCESSUS=1`, seulement quand rien ne
  tourne sous Wine).
- **Prefixe** : `CIDRE_BNET_PREFIXE`, sinon `~/Library/Application Support/Cidre/battlenet.prefixe`
  (`cidre battlenet prefixe <chemin>`, pour un prefixe ou le client est deja installe et connecte),
  sinon `wine/pfx-battlenet`.
- **Installation** : `cidre battlenet installer [--json]` telecharge l'installeur officiel
  (downloader.battle.net, HTTPS), le verifie (executable Windows de plus de 1 Mo, nom « Blizzard
  Entertainment » dans sa signature : pas une verification cryptographique, qu'un Mac sans outils ne sait
  pas faire), cree le prefixe s'il manque (`battlenet.sh creer` : Wine neuf, runtime Visual C++ par
  `tests/vcruntime_registre.sh`, partage avec `cidre setup`, DXVK, FEX ; sans le pont Steam), puis lance
  l'installeur (`--lang=` langue du Mac, `--installpath=C:\Program Files (x86)\Battle.net`) et rend la main
  quand le client est installe ; l'utilisateur s'y connecte. Evenements `--json` : etapes telechargement,
  prefixe, installeur, client, puis installe, ou erreur (telechargement, installeur_invalide, prefixe,
  installeur_ferme, trop_long). `cidre setup` remet un prefixe Battle.net existant au runtime (etape 3/6 ; pas
  d'etape de plus : Verger compte les `== k/6 ==`), sauf si le client y tourne. Une mise a jour du runtime
  (archive extraite par-dessus) garde `wine/pfx-battlenet` comme `wine/pfx-arm64ec`.
- **Jeux** : cles Uninstall de l'Agent (`--uid=osi`), traduites par `outil-steam/battlenet.conf` (uid,
  code, executable, nom) en `bnet-osi` (D2R) et `bnet-fen` (D4). `cidre list --json` les rend avec
  `"source":"battlenet"`, `"appid":null`, la taille du dossier, et `"en_ligne":false` quand le dossier
  est un lien vers un disque debranche. Les entrees Steam sont inchangees (temoin).
- **Lancement** : `cidre play bnet-osi` passe par `lancer_depuis_steam.sh` (fiche, dx12, knowndlls,
  version de Windows, journal `build/logs/steam-bnet-osi.log`, sauvegardes), avec le prefixe
  Battle.net, sans client Steam (`CIDRE_SANS_STEAM=1`) ni faux_steam (`CIDRE_SANS_FAUX_STEAM=1`). Au
  lieu de l'executable, `battlenet.sh jouer` ouvre le client (Qt logiciel, `--in-process-gpu`) avec
  `--exec="launch OSI"`, attend le jeu (900 s : connexion eventuelle ; la demande est refaite a 150
  et 400 s), puis sa fin (trois releves vides a 2 s). Le jeu herite de l'environnement du client :
  le client est donc rouvert quand il a ete ouvert pour un autre jeu ou avec d'autres reglages, et
  ferme avant le reglage du prefixe (version de Windows, KnownDLLs : sans wineserver). Il reste
  ouvert apres la partie (`cidre battlenet arreter`). `GameLaunchWindowBehavior` 2 est remis a 0.
- **`cidre stop bnet-osi`** arrete le wineserver du prefixe Battle.net (jeu et client) ; `cidre stop`
  sans id aussi, si un jeu Battle.net est en cours. Pour un jeu Steam, le client Battle.net, son jeu
  et leurs lanceurs ne sont plus touches (avant, l'etape des orphelins tuait tout processus Windows
  du runtime, quel que soit son prefixe).
- **Sauvegardes** : `bnet-osi` -> `Saved Games/Diablo II Resurrected` (personnages hors ligne,
  reglages), copie Cidre dans le prefixe Battle.net. D4 garde ses personnages sur les serveurs.
- **Verger** : rien encore. `Game.Source` prend `battlenet` pour `steam` (`?? .steam`) ; le bouton
  Jouer marcherait (`cidre play <id>`), mais la fiche montrerait des actions Steam.

### Manche D2R par `cidre play bnet-osi` (M1 Max, 2026-10-21, 15:40-16:17)

Runtime installe 1.5.18 (xtajit64 c147ed00, sans 0217), prefixe clone de `pfx-bnet`, arbre fige.

- Le chemin marche : client ouvert par le lanceur, connexion vue par l'utilisateur, D2R lance par le client
  (`--exec="launch OSI"`) avec l'environnement du jeu (DXGI de DXVK, vkd3d-proton par les KnownDLLs), chaine
  1728x1084. Arret par `cidre stop bnet-osi` en 9 s, sauvegardes copiees, aucun processus restant.
- Debit percu (lignes `[CIDRE_WSI]` de la chaine de D2R, fenetres ponderees par leur duree) : premieres images
  454 s apres le depart de D2R ; sur 1 169 s, 2,4 images/s reelles, mediane ponderee 0,2, 87 % du temps sous
  2 images/s, gels jusqu'a 60 s ; ~7 coeurs. « Le jeu tourne, a 2 a l'heure » (utilisateur). Le client presente
  aussi par KosmicKrisp (chaine 1600x1000, ~8 images/s) : a ecarter des releves.
- Trois defauts vus et corriges ensuite :
  - la cle `HKCU\...\Run` « Battle.net » (`--autostarted`) : `wineboot -u` (prefixe_a_jour.sh) ouvrait le client
    hors de l'environnement du jeu et `wineserver -w` l'attendait sans fin. Retiree avant chaque ouverture ;
  - `jeu_vu` : la variable du nom cherche precedait le premier membre du tube et n'atteignait pas awk ; le premier
    processus venu (`start.exe`) passait pour D2R, et la demande de lancement n'etait jamais refaite (refaite ici a
    la main a 15:49:33 : D2R est parti aussitot) ;
  - l'Agent s'ecrit `C:/ProgramData/Battle.net/...` (barres obliques) : il passait pour un jeu.
  Le temoin (`CIDRE_ESSAI_PROCESSUS=1`) couvre les trois ; son faux wineserver, copie de /bin/sleep, doit etre
  re-signe (`codesign -s -`), sinon macOS le tue.
