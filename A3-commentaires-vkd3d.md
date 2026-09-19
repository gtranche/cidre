# vkd3d-proton — commentaires, état après relecture

## Ce qui a été fait

Contrairement à `src/mesa`, cet arbre ne porte aucune politique sur les agents :
j'ai donc pu relire et corriger ces commentaires moi-même.

La relecture s'est faite contre le style réellement pratiqué en amont, mesuré sur
**1 233 lignes de commentaire** des onze mêmes fichiers : largeur médiane 68 colonnes,
32 % des lignes au-delà de 80, blocs d'une seule ligne dans 59 % des cas, ton narratif
et non télégraphique. Mes commentaires s'y conformaient déjà pour l'essentiel, ce qui
a limité les corrections à quatre défauts réels plutôt qu'à une réécriture de façade.

## Les quatre corrections

1. **`include/private/vkd3d_native_sync_handle.h`** — le tiret double ` -- ` n'apparaît
   **jamais** dans les 1 233 lignes amont (qui emploient ` - ` 44 fois). J'en avais mis
   deux dans le même bloc. Reformulé sans, et la mention du mutex ajoutée : l'objet est
   un compteur gardé par un mutex *et* une variable de condition, pas seulement les deux
   derniers.
2. **`libs/vkd3d/device.c`** — le même bloc de trois lignes était recopié **mot pour mot**
   au-dessus des trois `*pipeline_state = NULL;`, dans les variantes graphique, calcul et
   flux. L'explication complète reste au premier site ; les deux autres portent un renvoi
   d'une ligne.
3. **`include/private/vkd3d_threads.h`** — le commentaire expliquant pourquoi macOS est
   exclu se trouvait **à l'intérieur** du `#ifndef __APPLE__`, c'est-à-dire dans la
   branche que macOS ne compile jamais. Il se lisait à l'envers, comme s'il décrivait
   l'appel qu'il justifie d'écarter. Remonté au-dessus de la garde.
4. **`tests/d3d12_sync.c`** — la phrase finale invoquait « the native build » sans que
   rien ne permette de le vérifier, alors que le fichier a son propre idiome de `skip()`
   quelques lignes plus haut. Phrase retirée ; les précédentes justifient déjà le saut.

## Vérifications

- `arch -arm64 ninja` dans `build/vkd3d` : compilation propre, 83 cibles.
- Plus aucune occurrence de ` -- `.
- Correctifs `0004`, `0007` et `0016` régénérés par remplacement de section, pour ne pas
  replier `0014` dans `0004` (les deux touchent `libs/vkd3d-common/platform.c`).
- **Aller-retour vérifié** : les cinq correctifs appliqués sur `git archive HEAD`
  reproduisent l'arbre de travail octet pour octet sur les quatorze fichiers.
- Volume passé de 42 à 38 lignes de commentaire, sur 21 blocs inchangés en nombre.

## Les 21 blocs, état final


---

### `include/private/vkd3d_native_sync_handle.h` — 4 blocs

**[1] ligne 32** — correctif `0004`

```c
/* macOS has no eventfd(). The two shapes this header needs, a counting semaphore
 * (EFD_SEMAPHORE) and an auto-reset event, are both a counter guarded by a mutex
 * and a condition variable, so build that directly instead of emulating a file
 * descriptor. The opaque HANDLE is the object's address. */
```

**[2] ligne 71** — correctif `0004`

```c
        /* A semaphore hands out one count at a time; an auto-reset event is
         * consumed whole. */
```

**[3] ligne 151** — correctif `0004`

```c
            handle.obj->count = 1u;  /* auto-reset event: signalled or not */
```

**[4] ligne 208** — correctif `0004`

```c
        /* pthread_cond_timedwait() is absolute, against CLOCK_REALTIME here. */
```


---

### `include/private/vkd3d_threads.h` — 2 blocs

**[5] ligne 308** — correctif `0004`

```c
    /* macOS names the calling thread only. */
```

**[6] ligne 361** — correctif `0004`

```c
    /* macOS has no pthread_condattr_setclock(); its condition variables always
     * time out against CLOCK_REALTIME, which the wait below matches. */
```


---

### `include/vkd3d_windows.h` — 1 bloc

**[7] ligne 96** — correctif `0004`

```c
/* Darwin off_t is already 64-bit; there are no *64 variants. */
```


---

### `libs/vkd3d-common/file_utils.c` — 1 bloc

**[8] ligne 69** — correctif `0004`

```c
    /* Darwin spells the no-clobber rename renamex_np()/RENAME_EXCL. */
```


---

### `libs/vkd3d-common/platform.c` — 3 blocs

**[9] ligne 42** — correctif `0004`

```c
/* macOS provides dlopen/dlsym/uname just like Linux does. */
```

**[10] ligne 74** — correctif `0004`

```c
    /* No program_invocation_name outside glibc. */
```

**[11] ligne 129** — correctif `0014`

```c
/* Older mingw-w64 headers predate this flag; zero is its documented value. */
```


---

### `libs/vkd3d/device.c` — 3 blocs

**[12] ligne 4028** — correctif `0007`

```c
    /* Direct3D 12 clears the out parameter when creation fails; applications
     * and tests routinely pass an uninitialised pointer and only look at it,
     * not at the HRESULT. Leaving it untouched hands them a stray pointer. */
```

**[13] ligne 4055** — correctif `0007`

```c
    /* Cleared on failure as well, see CreateGraphicsPipelineState(). */
```

**[14] ligne 7455** — correctif `0007`

```c
    /* Cleared on failure as well, see CreateGraphicsPipelineState(). */
```


---

### `libs/vkd3d/swapchain.c` — 1 bloc

**[15] ligne 739** — correctif `0004`

```c
    /* The Darwin sync object has no duplicate operation and handing out the
     * same pointer would let the caller free an object the swapchain still
     * owns. The frame latency waitable is unused headless. */
```


---

### `tests/d3d12_clip_cull_distance.c` — 1 bloc

**[16] ligne 749** — correctif `0008`

```c
    /* Skip just the geometry shader section; the clip distance cases below
     * use pipelines of their own and are still worth running. */
```


---

### `tests/d3d12_crosstest.h` — 2 blocs

**[17] ligne 57** — correctif `0004`

```c
/* macOS has no eventfd(); the harness events use the same counter and
 * condition variable object the driver uses (vkd3d_native_sync_handle.h). */
```

**[18] ligne 215** — correctif `0004`

```c
#endif /* __APPLE__ */
```


---

### `tests/d3d12_geometry_shader.c` — 2 blocs

**[19] ligne 436** — correctif `0008`

```c
    /* Nothing below survives a pipeline that was never created: the draws bind
     * it and the teardown releases it. The failures are already recorded, so
     * stop here rather than take the whole run down. */
```

**[20] ligne 1059** — correctif `0008`

```c
        /* A pipeline that was never created cannot be bound or released;
         * the failure is already recorded. */
```


---

### `tests/d3d12_sync.c` — 1 bloc

**[21] ligne 1269** — correctif `0016`

```c
        /* Wine implements neither CreateSharedHandle nor OpenSharedHandle for
         * fences. Everything below re-opens the fences from those handles, so
         * without them the rest of the test runs on dangling pointers and takes
         * the whole suite down. */
```

