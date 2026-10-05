# Note de synthèse — PEAK, deadlock W^X et modèle mémoire FEX/Wine (2026-10-05)

## 0. Résultat principal
Le blocage de PEAK n'est **pas** un crash de compilation de shaders. C'est un **deadlock W^X dans la couche d'émulation CPU (FEX/Wine arm64ec)**, atteint bien avant tout travail GPU. (Les « morts silencieuses sans .ips » précédentes = deux sessions Claude qui se tuaient PEAK sur le prefix partagé ; aucun crash applicatif.)

## 1. Le deadlock (prouvé par lldb + vmmap)
- Faute : `EXC_BAD_ACCESS code=2` (écriture), instruction `stlrb w6,[x21]` exécutée depuis le **cache JIT de FEX** (région `VM_ALLOCATE rwx 16 Mo`), x21 = page JIT **de l'invité** (Mono d'Unity, `VM_ALLOCATE rwx 64 Ko`).
- Les deux régions sont **MAP_JIT** : droits RWX dans la table, mais APRR n'accorde qu'UN mode (W **ou** X) **par fil**. Un seul fil ne peut pas *fetcher* le `stlrb` (page de code FEX → mode X) **et** exécuter son store (page invité → mode W) au même instant.
- La branche `VPROT_JIT` de `virtual_handle_fault` bascule l'APRR et renvoie SUCCESS sans vérifier : à la reprise, re-fetch → faute X → bascule → faute W → **boucle infinie**. N'arrive que quand l'invité écrit dans sa **propre** mémoire exécutable (JIT Mono).

## 2. Pourquoi le discriminant « bitmap EC » (is_emulated_code) est une IMPASSE
Vérifié dans le code (le pair a fourni les pistes, j'ai confirmé) :
- Polarité (`virtual.c:3075`) : bit=1 → code natif EC, bit=0 → émulé ; `is_emulated_code` renvoie TRUE quand bit=0.
- Les bits ne sont posés **que** pour des plages de code d'**IMAGE** arm64ec : `set_arm64ec_range` (`virtual.c:1429`), appelé au chargement de module (`virtual.c:3072`) et par `NtAllocateVirtualMemory` **avec** `MEM_EXTENDED_PARAMETER_EC_CODE` (`virtual.c:5692`). Les allocations RWX ordinaires du runtime ne posent **pas** ce flag.
- FEX alloue **tout** son code natif au runtime via `FEXCore::Allocator::VirtualAlloc(size, executable=true)` **sans** EC_CODE : `FEX/.../Dispatcher/Dispatcher.cpp:40` (vérifié), `SharedCodeBufferManager.cpp`, `CodeCache.cpp`. FEX ne fait que **lire** le bitmap (`Dispatcher.cpp:159`, `BranchOps.cpp` / `RtlIsEcCode`) pour valider les cibles de branchement invité — il ne marque jamais son propre cache.
- **Donc** : code natif FEX = bit 0, JIT x86 de Mono = bit 0. `is_emulated_code == TRUE` pour **les deux**. Aucun état de *page* ne les distingue.

Preuve empirique : en forçant « process AMD64 → pages JIT en RW » (sans MAP_JIT), la tempête W^X disparaît (0 vs 2521 échantillons) **mais** FEX ne peut plus exécuter son propre code natif → `EXC_BAD_ACCESS code=2` (défaut d'**exécution**) à `0x7ffedded0100`, page `rw-` contenant du code ARM64 natif. Confirme que FEX et Mono partagent le même type d'allocation RWX.

## 3. AUCUN signal côté Wine ne discrimine (résolu statiquement — sonde inutile)
Il faudrait distinguer « alloc de code invité (Mono) » de « alloc de code natif FEX ». Or :
- `ChpeV2CpuAreaInfo->InSimulation` reste **à 1** pendant l'exécution invité ET le syscall natif (posé =1 à `signal_arm64ec.c:1326` avant de rendre la main au thunk ; aucun =0 hors tests). Inutilisable.
- Wrapper arm64ec de `NtAllocateVirtualMemory` (`dlls/ntdll/signal_arm64ec.c:648`) : `enter_syscall_callback`/`InSyscallCallback` n'est qu'un **garde de ré-entrance** ; `pNotifyMemoryAlloc` est déclenché pour **tout** appel top-level — invité ET FEX (les deux allouent top-level). Côté FEX, `NotifyMemoryAlloc` (`FEX/.../ARM64EC/Module.cpp:810`) ne fait que du suivi SMC (`HandleMemoryProtectionNotification`), il ne décide pas du mapping.
- FEX alloue son propre code via `::VirtualAlloc(PAGE_EXECUTE_READWRITE)` (`Module.cpp:653`, `Dispatcher.cpp:40`) → passe par `map_view` **comme** l'invité (confirmé empiriquement : mon changement Wine a bien affecté le code FEX).
- `is_emulated_code(frame->pc)` : même impasse que §2 (FEX natif = bit 0).

**Conclusion : seul FEX connaît l'origine de chaque alloc** (ses propres `::VirtualAlloc` vs le forward d'un syscall invité). Tout discriminant fiable doit donc venir **de FEX**, pas de Wine seul. La sonde ne ferait que confirmer ce résultat déjà établi.

## 4. Trois approches (toutes demandent soit une modif FEX, soit un risque de lenteur)
- **A — RW pour les pages JIT invité (pas de MAP_JIT)**, avec **marquage côté FEX**. Chirurgical et correct (restaure aussi le SMC), MAIS exige que FEX marque les allocs de code invité qu'il forwarde (ex. `MEM_EXTENDED_PARAMETER` dédié, ou drapeau per-fil posé par le handler de syscall de FEX autour du forward), que Wine lit pour mapper RW ; ses propres `::VirtualAlloc` restent non marqués → MAP_JIT. Modif FEX **et** Wine.
- **B — émuler le store fautif dans `virtual_handle_fault`**. Wine-seul, garde MAP_JIT partout (code FEX intact) ; le handler (natif) complète le store puis avance le PC. Aucun discriminant requis, MAIS ~1 faute par écriture de code de Mono → **à mesurer** (peut être praticable si Mono écrit par gros blocs/memcpy, ou rédhibitoire sinon).
- **C — double-mapping**. Page JIT invité mappée 2× : vue MAP_JIT (exécution) + alias RW (écritures FEX). Pas de discriminant, pas de faute/store, MAIS demande que **FEX écrive via l'alias** → modif FEX/pont.

## 5. Recommandation
Le discriminant ne pouvant venir que de FEX (§3), le choix réel est :
- **A** si on accepte une petite modif FEX (la plus propre, corrige aussi le SMC) — le pair peut aider à câbler le marquage côté FEX + le hook `NtAllocateVirtualMemory`.
- **B** si on veut un essai **Wine-seul rapide** : implémenter l'émulation du store dans le handler et **mesurer** la vitesse sur PEAK (le livelock se reproduit en <1 min, donc verdict rapide). Repli vers A/C si trop lent.
La sonde du §3 n'est plus nécessaire (résolu statiquement).

## État de la pile
Restaurée à l'origine (ntdll rebâti, toutes mes modifs de `virtual.c` annulées à la main ; les ~520 lignes non commitées du dépôt préservées). Rien n'est cassé pour les autres jeux ni pour la session « cache KosmicKrisp » (dylib figé, prêt à agir dès que PEAK franchira le deadlock).
