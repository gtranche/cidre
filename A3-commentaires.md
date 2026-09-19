# A3 — commentaires à réécrire dans l'arbre Mesa

## Ce que c'est

Inventaire des commentaires que j'ai écrits et qui se trouvent **actuellement** dans
`src/mesa`. Construit depuis l'arbre de travail comparé à `HEAD`, pas depuis les fichiers
de correctif : les numéros de ligne sont donc exacts et utilisables tels quels, et les
blocs que des correctifs ultérieurs ont modifiés ou supprimés n'y figurent pas.

La politique Mesa (`src/mesa/CLAUDE.md`) interdit qu'un agent génère des commentaires ;
le texte de remplacement doit être le vôtre. **Je n'ai donc rien réécrit ni supprimé.**

`src/vkd3d-proton` ne porte aucune politique équivalente : ses commentaires sont hors A3.

## Comment lire

- **convention** — en-tête de licence, `#endif /* GARDE */`, étiquette `/* VK_… */`
  identique aux trente déjà présentes dans le même fichier, annotation `/* output */`
  utilisée en amont dans `poly` et `asahi`. Ce ne sont pas des phrases ; rien à y
  réécrire à mon sens, mais c'est votre appel.
- **à réécrire** — tout le reste.
- **⚑** — le bloc porte un chiffre mesuré pendant le projet. En reformulant, gardez la
  mesure : elle ne se retrouve nulle part ailleurs dans le code.

## Volume

**108 blocs** sur **21 fichiers** : 11 en convention,
**97 à réécrire**, dont 3 portant une mesure.

Une fois l'arbre corrigé, régénérez les correctifs concernés : les blocs listés ici
retombent dans 0003, 0005, 0006, 0009 et 0010 pour l'essentiel.


---

## `src/kosmickrisp/libkk/kk_geometry.cl` — 3 blocs

### [1] ligne 46 — *a reecrire*

```c
/* Geometry shader emulation, indirect draw. Only the GPU knows the vertex and
 * instance counts, so poly fills in the parameter buffers here, and we turn
 * the thread counts it computed into the threadgroup counts Metal's indirect
 * dispatch expects. Invocations past the real count are dropped by the guard
 * kk_shader.c puts at the top of each emulated program.
 */
```

### [2] ligne 54 — *a reecrire*

```c
                        global struct poly_vertex_params *vp /* output */,
                        global struct poly_geometry_params *p /* output */,
```

### [3] ligne 57 — *convention*

```c
                        global uint32_t *grids /* output: VS then GS */,
```


---

## `src/kosmickrisp/libkk/kk_xfb.cl` — 1 blocs

### [4] ligne 1 — *convention*

```c
/*
 * Copyright 2026 The Mesa contributors
 * SPDX-License-Identifier: MIT
 */
```


---

## `src/kosmickrisp/vulkan/kk_buffer_view.c` — 4 blocs

### [5] ligne 69 — *a reecrire*

```c
   /* kk_get_va_format() returns NULL for anything missing from the texel
    * buffer table, so this cannot assume the format is usable. Fail the call
    * instead of dereferencing NULL. */
```

### [6] ligne 112 — *a reecrire*

```c
   /* Metal only takes a 16 byte aligned offset for a texture buffer, whatever
    * the format, but Vulkan lets the view start at any texel. Start the
    * texture at the boundary below and remember how many texels that added in
    * front; kk_nir_lower_descriptors.c adds them back to every coordinate.
    */
```

### [7] ligne 123 — *a reecrire*

```c
   /* The offset is a multiple of the texel size (that is what
    * *TexelBufferOffsetSingleTexelAlignment promises the application), and so
    * is the 16 byte boundary for any format we expose, so the bias lands on a
    * whole number of texels.
    */
```

### [8] ligne 135 — *a reecrire*

```c
   /* Past this Metal aborts the process from its own validation rather than
    * returning nil, so refuse the view here. Note the prefix added above
    * counts towards the limit. */
```


---

## `src/kosmickrisp/vulkan/kk_buffer_view.h` — 1 blocs

### [9] ligne 27 — *a reecrire*

```c
   /* Texels between the start of the Metal texture and this view's first
    * element. Non-zero when the requested offset was not 16 byte aligned.
    * See struct kk_texel_buffer_descriptor.
    */
```


---

## `src/kosmickrisp/vulkan/kk_cmd_buffer.c` — 5 blocs

### [10] ligne 170 — *a reecrire*

```c
   /* Recording is over and whatever used these has been submitted, so the
    * split-off command buffers can go back to the pool. */
```

### [11] ligne 273 — *a reecrire*

```c
/*
 * A Metal command buffer holds a bounded number of encoders; past it the
 * commit is rejected outright and the Vulkan device is lost. A single Vulkan
 * command buffer can easily ask for more -- vkd3d-proton turns one D3D12
 * command list into one of ours, and 65536 resolves is a real workload -- so
 * close the current Metal command buffer and open another whenever the budget
 * runs out. They are committed together, in order, so nothing else changes.
 *
 * Only called with no encoder open, which is the only point where the split
 * is free: Metal command buffers on one queue run in submission order, so
 * work either side of the seam stays correctly ordered.
 */
```

### [12] ligne 297 — *a reecrire*

```c
   /* Without a spare, keep filling the current one: overshooting the budget
    * may still work, whereas dropping commands certainly would not. */
```

### [13] ligne 305 — *a reecrire* ⚑

```c
   /* The budget is per command buffer, not per allocator -- measured: one
    * allocator happily backs 131072 encoders spread over eight command
    * buffers, while 38000 in a single one is refused -- so the recording
    * keeps the allocator it started with. */
```

### [14] ligne 385 — *a reecrire*

```c
      /* Counted but not split on: a compute encoder can be opened from inside
       * cs_end() to flush post-render writes, where splitting would cut the
       * recording in an awkward place. */
```


---

## `src/kosmickrisp/vulkan/kk_cmd_buffer.h` — 13 blocs

### [15] ligne 24 — *convention*

```c
#include "compiler/shader_info.h"  /* MAX_XFB_BUFFERS */
```

### [16] ligne 51 — *a reecrire*

```c
         /* VK_EXT_transform_feedback. nir_lower_xfb_to_stores() captures at
          *   xfb_address[buf] + (instance_id * xfb_num_vertices + raw_vertex_id)
          *                      * stride + offset
          * xfb_address already includes everything earlier draws in this
          * capture wrote, so each draw appends rather than overwrites.
          */
```

### [17] ligne 59 — *a reecrire*

```c
         /* Bytes still writable in each buffer. Zero while capture is
          * inactive, which is how the shader's captures get switched off. */
```

### [18] ligne 98 — *a reecrire*

```c
   /* Non-zero when the last vertex of a primitive is the provoking one.
    * poly's geometry lowering reads it to order the indices it emits. */
```

### [19] ligne 112 — *a reecrire*

```c
   /* Address of geometry param buffer if a geometry shader is used, else 0 */
```

### [20] ligne 194 — *a reecrire*

```c
   /* VK_EXT_transform_feedback capture state */
```

### [21] ligne 196 — *a reecrire*

```c
      /* Buffers bound by vkCmdBindTransformFeedbackBuffersEXT. */
```

### [22] ligne 202 — *a reecrire*

```c
      /* Bytes already captured into each buffer since the current
       * vkCmdBeginTransformFeedbackEXT, tracked on the CPU: with the
       * vertex-indexed capture scheme the write offsets of a draw are known
       * before it runs.
       */
```

### [23] ligne 209 — *a reecrire*

```c
      /* Counter buffers handed to vkCmdEndTransformFeedbackEXT, so the byte
       * counts can be written back when capture stops.
       */
```

### [24] ligne 220 — *a reecrire*

```c
      /* Active VK_QUERY_TYPE_TRANSFORM_FEEDBACK_STREAM_EXT query. Addresses
       * rather than the pool, to keep the query pool out of this header.
       */
```

### [25] ligne 233 — *a reecrire*

```c
   /* Geometry shader emulation: what the rasterization draw should use once
    * the emulation programs have run. Filled while uploading the geometry
    * parameters, consumed by kk_launch_gs(). */
```

### [26] ligne 314 — *a reecrire*

```c
      /* Metal command buffers already closed for this recording, in the order
       * they must execute. A recording that would overrun a single command
       * buffer's encoder budget is spread over several; see
       * KK_MAX_ENCODERS_PER_COMMAND_BUFFER. Empty in the common case.
       */
```

### [27] ligne 320 — *a reecrire*

```c
      /* Encoders opened on cmd_buf since it was begun. */
```


---

## `src/kosmickrisp/vulkan/kk_cmd_draw.c` — 22 blocs

### [28] ligne 1247 — *a reecrire*

```c
/* Parameters the geometry shader emulation programs read, plus the index
 * buffer the rasterization draw will consume. poly decides the shape of that
 * draw; we only have to lay out what it asked for.
 */
```

### [29] ligne 1292 — *a reecrire*

```c
      /* The topology is a compile-time constant, so it is the same whatever
       * the draw. poly hands it to us byte-sized, but Metal only indexes with
       * 16 or 32 bit values, so widen it on the way out. */
```

### [30] ligne 1309 — *a reecrire*

```c
   /* An indirect draw only knows its counts on the GPU: poly's setup kernel
    * fills the rest of this in, including the index buffer of a dynamically
    * indexed shape, which it takes from the device heap. */
```

### [31] ligne 1346 — *a reecrire*

```c
      /* The geometry shader writes this one itself. */
```

### [32] ligne 1834 — *a reecrire*

```c
   /* So does geometry: the emulation programs read their parameters from it. */
```

### [33] ligne 2140 — *a reecrire*

```c
/*
 * Metal has no geometry stage, so poly rewrote the shader into compute
 * programs (see kk_compile_shader()). Run them here, in front of the draw:
 * the vertex shader feeds the geometry shader, and what the geometry shader
 * produced is then rasterized by poly's own vertex program, which is already
 * bound as this pipeline's render shader.
 */
```

### [34] ligne 2161 — *a reecrire*

```c
      /* Only the GPU knows the counts, so poly's setup kernel fills in the
       * parameter buffers and the dispatch grids from the indirect command. */
```

### [35] ligne 2203 — *a reecrire*

```c
   /* The vertex shader, as compute, writing its outputs where the geometry
    * shader will read them. */
```

### [36] ligne 2229 — *a reecrire*

```c
   /* The geometry shader proper, one invocation per input primitive. */
```

### [37] ligne 2234 — *a reecrire*

```c
   /* Whatever shape poly chose for the rasterization draw. For a direct draw
    * the third component of the grid is the base instance, not a depth: the
    * rasterization shader decodes the primitive from a zero-based instance
    * index, so it must stay 0. An indirect one reads the command poly wrote,
    * whose layout already matches Metal's. */
```

### [38] ligne 2251 — *a reecrire*

```c
         /* poly allocated that index buffer out of the device heap. */
```

### [39] ligne 2400 — *a reecrire*

```c
/*
 * VK_EXT_transform_feedback.
 *
 * Capture happens inside the drawing vertex function (see
 * kk_nir_lower_xfb.c), which indexes each buffer by
 *
 *    (instance_id * num_vertices + raw_vertex_id) * stride + offset
 *
 * Those write offsets only depend on the draw's own parameters, so a direct
 * draw's capture extent is known here, before it runs: the CPU can hand the
 * shader an already-advanced base address and the room left in each buffer,
 * and no GPU-side counter is needed.
 *
 * That reasoning does not hold once the vertex index stops being the
 * sequential position within the draw, so indexed, indirect and multi-draws
 * do not capture; kk_xfb_draw_captures() spells out why. Rather than write
 * wrong data, they are given a remaining capacity of zero, which the shader's
 * bounds check turns into no writes at all.
 */
```

### [40] ligne 2431 — *a reecrire*

```c
   /* An indirect draw's vertex count is only known on the GPU. */
```

### [41] ligne 2435 — *a reecrire*

```c
   /* For an indexed draw the vertex ID is the index value, not the position
    * in the draw, so it cannot address the capture buffer.
    */
```

### [42] ligne 2441 — *a reecrire*

```c
   /* A multi-draw would need each draw to start where the previous one
    * stopped, which is one base address per draw.
    */
```

### [43] ligne 2470 — *a reecrire*

```c
/* Vertex count of a direct draw, indexed or not. */
```

### [44] ligne 2498 — *a reecrire*

```c
   /* Only shaders that capture read any of this. */
```

### [45] ligne 2517 — *a reecrire*

```c
      /* The stream still produces primitives, they are just not captured. */
```

### [46] ligne 2526 — *a reecrire*

```c
   /* Vertices that still fit in every buffer this shader captures into. */
```

### [47] ligne 2530 — *a reecrire*

```c
      /* info.vs.xfb_stride is in words, like nir_shader_info. */
```

### [48] ligne 2560 — *a reecrire*

```c
      /* The shader drops whatever runs past the end of a buffer, so only the
       * primitives whose vertices all fit count as written. */
```

### [49] ligne 2685 — *a reecrire*

```c
   /* Must run before the root table is uploaded. */
```


---

## `src/kosmickrisp/vulkan/kk_descriptor_set_layout.c` — 1 blocs

### [50] ligne 47 — *a reecrire*

```c
      /* Carries the texel bias on top of the resource id. */
```


---

## `src/kosmickrisp/vulkan/kk_descriptor_types.h` — 1 blocs

### [51] ligne 48 — *a reecrire* ⚑

```c
/* Metal wants a texture buffer to start on a 16 byte boundary whatever the
 * format (measured: minimumTextureBufferAlignmentForPixelFormat: returns 16
 * for every format), while Vulkan lets a VkBufferView start at any texel once
 * uniform/storageTexelBufferOffsetSingleTexelAlignment is advertised. The view
 * is therefore created at the 16 byte boundary below the requested offset and
 * carries the number of texels that were skipped; the shader adds it back to
 * every coordinate.
 *
 * image_gpu_resource_id must stay first: the texture and image paths both read
 * a resource id at offset 0 without caring which descriptor they got.
 */
```


---

## `src/kosmickrisp/vulkan/kk_image.c` — 1 blocs

### [52] ligne 616 — *a reecrire*

```c
   /* Metal validates arrayLength itself and aborts the process rather than
    * returning nil, so catch an over-long array here. The limit reported in
    * maxImageArrayLayers is the same one Metal enforces. */
```


---

## `src/kosmickrisp/vulkan/kk_indirect_commands.c` — 1 blocs

### [53] ligne 1 — *convention*

```c
/*
 * Copyright 2026 Guillaume Tranchepain
 * SPDX-License-Identifier: MIT
 */
```


---

## `src/kosmickrisp/vulkan/kk_indirect_commands.h` — 2 blocs

### [54] ligne 1 — *convention*

```c
/*
 * Copyright 2026 Guillaume Tranchepain
 * SPDX-License-Identifier: MIT
 */
```

### [55] ligne 66 — *convention*

```c
#endif /* KK_INDIRECT_COMMANDS_H */
```


---

## `src/kosmickrisp/vulkan/kk_nir_lower_descriptors.c` — 4 blocs

### [56] ligne 392 — *a reecrire*

```c
   /* A texel buffer view may start mid-way through the 16 byte granule Metal
    * insists on, so shift the coordinate past the texels the view skipped.
    * See struct kk_texel_buffer_descriptor.
    */
```

### [57] ligne 443 — *a reecrire*

```c
   /* VK_EXT_transform_feedback. nir_lower_xfb_to_stores() leaves these for
    * the driver; we feed them from the root table, which the draw path fills
    * in before every capturing draw.
    */
```

### [58] ligne 486 — *a reecrire*

```c
   /* Metal's [[vertex_id]] counts from the draw's first vertex, so undo that
    * to get the zero-based index the capture offsets are computed from.
    */
```

### [59] ligne 653 — *a reecrire*

```c
   /* Same shift for the sampled side. */
```


---

## `src/kosmickrisp/vulkan/kk_nir_lower_xfb.c` — 6 blocs

### [60] ligne 1 — *convention*

```c
/*
 * Copyright 2026 The Mesa contributors
 * SPDX-License-Identifier: MIT
 */
```

### [61] ligne 11 — *a reecrire*

```c
/*
 * Software transform feedback for Metal.
 *
 * Metal has no transform feedback, but a Metal vertex function may write to
 * device buffers, so the capture rides along with the draw that produces the
 * vertices: store_output intrinsics carrying io_xfb info (attached by
 * nir_io_add_intrinsic_xfb_info) gain a matching store_global at
 *
 *    xfb_address(buffer) + (instance_id * num_vertices + raw_vertex_id)
 *                          * stride + offset
 *
 * which is nir_lower_xfb_to_stores()'s scheme. We do not use that pass because
 * every capture here has to be bounds checked: Vulkan discards writes past the
 * end of a bound buffer, and the driver reports a remaining capacity of zero
 * while capture is inactive, which is what stops a pipeline with transform
 * feedback varyings from writing outside
 * vkCmdBeginTransformFeedbackEXT/vkCmdEndTransformFeedbackEXT.
 *
 * The outputs themselves are left alone: the same draw rasterizes as usual.
 */
```

### [62] ligne 39 — *a reecrire*

```c
   /* Transform feedback info is in words, Metal addresses are in bytes. */
```

### [63] ligne 62 — *a reecrire*

```c
   /* Discard anything that would land outside the bound range. */
```

### [64] ligne 78 — *a reecrire*

```c
   /* Capture programs consume the zero-based hardware vertex ID. */
```

### [65] ligne 106 — *a reecrire*

```c
   /* Keep the store_output: this draw still rasterizes. */
```


---

## `src/kosmickrisp/vulkan/kk_physical_device.c` — 4 blocs

### [66] ligne 475 — *convention*

```c
      /* VK_EXT_dynamic_rendering_unused_attachments */
```

### [67] ligne 503 — *convention*

```c
      /* VK_EXT_device_generated_commands */
```

### [68] ligne 785 — *a reecrire*

```c
      /* Metal wants 16 bytes whatever the format, but a view whose offset is
       * only texel aligned is emulated: the texture starts at the boundary
       * below and the shader shifts the coordinate. See
       * struct kk_texel_buffer_descriptor. */
```

### [69] ligne 864 — *convention*

```c
      /* VK_EXT_device_generated_commands */
```


---

## `src/kosmickrisp/vulkan/kk_private.h` — 4 blocs

### [70] ligne 26 — *a reecrire* ⚑

```c
/* A Metal command buffer -- really the allocator backing it -- only holds so
 * many encoders before the commit is rejected. Measured on an M1 Max with a
 * fresh allocator: 36000 encoders commit, 38000 do not. Allocators are
 * recycled here without ever being reset, so their remaining room is unknown;
 * split well clear of the measured ceiling.
 */
```

### [71] ligne 33 — *a reecrire*

```c
/* Workgroup poly's geometry shader programs are compiled and dispatched with. */
```

### [72] ligne 36 — *a reecrire*

```c
/* Metal caps a texture array at this many layers. */
```

### [73] ligne 38 — *a reecrire*

```c
/* Metal caps a texture buffer at this many texels. */
```


---

## `src/kosmickrisp/vulkan/kk_query_pool.c` — 3 blocs

### [74] ligne 42 — *a reecrire*

```c
      /* primitivesWritten and primitivesGenerated. */
```

### [75] ligne 208 — *a reecrire*

```c
      /* kk_query_report_addr() scales the remapped index by one report, so
       * space the identity mapping out by the reports each query owns. */
```

### [76] ligne 470 — *a reecrire*

```c
/*
 * VK_EXT_transform_feedback queries.
 *
 * The counts come from the CPU: capture offsets are worked out at record time
 * (see kk_flush_xfb_state()), so how many primitives a draw emits and how many
 * of them fit is known before it runs. The results are still handed over on
 * the GPU timeline, so they land after the draws they describe rather than at
 * record time.
 */
```


---

## `src/kosmickrisp/vulkan/kk_query_pool.h` — 1 blocs

### [77] ligne 16 — *a reecrire*

```c
   /* Metal 4 counter heaps backing VK_QUERY_TYPE_TIMESTAMP pools. Timestamps
    * are sampled into them and later resolved into `bo` (see kk_query_pool.c).
    * A single heap holds at most KK_TS_COUNTER_HEAP_ENTRIES entries, so a pool
    * larger than that is spread over several. NULL for non-timestamp pools. */
```


---

## `src/kosmickrisp/vulkan/kk_queue.c` — 2 blocs

### [78] ligne 101 — *a reecrire*

```c
   /* A long recording is split across several Metal command buffers (see
    * kk_cmd_buffer_split_if_full()); commit them in recording order, the
    * still-open one last. Metal runs them in that order on the queue. */
```

### [79] ligne 125 — *a reecrire*

```c
         /* Without the array the pieces can still go one after another; the
          * queue keeps them in order. Only the last one carries the feedback
          * handler, which is the one the caller waits on. */
```


---

## `src/kosmickrisp/vulkan/kk_shader.c` — 19 blocs

### [80] ligne 859 — *a reecrire*

```c
   /* VK_EXT_transform_feedback. Metal has no transform feedback, but a Metal
    * vertex function may write to device buffers, so capture straight from
    * the vertex stage: keep_outputs leaves rasterization untouched and the
    * same draw both draws and captures. The address system values this leaves
    * behind are lowered against the root table in
    * kk_nir_lower_descriptors.c.
    */
```

### [81] ligne 870 — *a reecrire*

```c
      /* Fold constant IO offsets so the XFB info can be attached. */
```

### [82] ligne 1065 — *a reecrire*

```c
      /* Capture strides survive kk_lower_nir(), which already turned the XFB
       * outputs into global stores. */
```

### [83] ligne 1153 — *a reecrire*

```c
/* Metal's indirect compute dispatch counts threadgroups, so an indirect draw
 * has to round the grid up and ends up running invocations past the real
 * vertex or primitive count. poly's programs do not bound-check, so wrap the
 * body in a test here. The limit sits in the parameter buffer the program
 * already reads and is filled in for direct draws too, so the guard costs one
 * scalar load whichever kind of draw follows.
 */
```

### [84] ligne 1229 — *a reecrire*

```c
/* Last leg shared by every program we hand to Metal: finish lowering, optimise
 * and translate to MSL, keeping the entrypoint name alive past the NIR.
 */
```

### [85] ligne 1245 — *a reecrire*

```c
   /* Steal so it outlives the NIR. Must happen after nir_to_msl(), which is
    * where the entrypoint gets renamed. */
```

### [86] ligne 1279 — *a reecrire*

```c
   /* A shader poly turns into compute has to keep its clip and cull distances
    * as ordinary outputs: the MSL lowering writes them into the rasterizer's
    * output struct, which a kernel has not got. poly's rasterization program
    * gets the pass instead, once it exists. */
```

### [87] ligne 1315 — *a reecrire*

```c
      /* Metal has no geometry stage. poly_nir_lower_gs() rewrites the shader
       * into programs dispatched as compute before the draw, plus a plain
       * vertex shader that rasterizes whatever they produced. */
```

### [88] ligne 1332 — *a reecrire*

```c
      /* The main program runs as compute, like the vertex shader does on the
       * tessellation path. */
```

### [89] ligne 1357 — *a reecrire*

```c
         /* The counting program is a clone of the geometry shader and still
          * claims to be one; like the main program it runs as compute. */
```

### [90] ligne 1364 — *a reecrire*

```c
         /* These come straight out of poly and have seen none of the
          * preprocessing the application's shaders went through. */
```

### [91] ligne 1370 — *a reecrire*

```c
         /* Only this one feeds the rasterizer, so only this one gets the
          * lowering every hardware vertex shader goes through -- point size,
          * position, depth clamp -- and the clip and cull distances. What it
          * rasterizes is the geometry shader's output primitive, not the
          * topology the application drew with. */
```

### [92] ligne 1379 — *a reecrire*

```c
            /* That lowering reaches for root-table system values (the clip Z
             * coefficient, for one). poly's programs carry no descriptors, so
             * no set layout is needed to resolve them. */
```

### [93] ligne 1784 — *a reecrire*

```c
      /* A geometry shader brings more than one program along. Carry them and
       * their layout over too, since the pipeline is built from the vertex
       * shader. */
```

### [94] ligne 1811 — *a reecrire*

```c
      /* What reaches the rasterizer is what the geometry shader emits. */
```

### [95] ligne 1965 — *a reecrire*

```c
      /* Geometry shaders take their own route. The vertex shader and every
       * program poly produced run as compute before the draw, and what
       * actually feeds the rasterizer is poly's own vertex program. */
```

### [96] ligne 1978 — *a reecrire*

```c
      /* A geometry shader fed by tessellation would have to read the
       * tessellation evaluation shader's output rather than the vertex
       * shader's, and the two emulations would have to be chained. Not wired
       * up: refuse rather than rasterize the wrong buffer. */
```

### [97] ligne 2002 — *a reecrire*

```c
      /* Counting and pre-GS only exist when the shader needs them. */
```

### [98] ligne 2198 — *a reecrire*

```c
   /* Determine if the pipeline contains tessellation or geometry stages; both
    * push earlier stages into compute. */
```


---

## `src/kosmickrisp/vulkan/kk_shader.h` — 10 blocs

### [99] ligne 14 — *convention*

```c
#include "compiler/shader_info.h"  /* MAX_XFB_BUFFERS */
```

### [100] ligne 56 — *a reecrire*

```c
/* Metal has no geometry stage, so poly_nir_lower_gs() splits a geometry shader
 * into several programs run as compute before the draw. Only the main one maps
 * onto a Vulkan stage; the others live in kk_shader::gs_msl_data.
 */
```

### [101] ligne 61 — *a reecrire*

```c
   /* Counts the primitives each input primitive emits. Only built when the
    * shader needs counting -- transform feedback or pipeline statistics. */
```

### [102] ligne 64 — *a reecrire*

```c
   /* Prefix sums those counts and fills in the indirect draw. */
```

### [103] ligne 66 — *a reecrire*

```c
   /* Plain vertex shader that rasterizes what the geometry shader produced. */
```

### [104] ligne 78 — *a reecrire*

```c
   /* Geometry shader emulation. Kept outside the union because the vertex
    * shader carries the whole pipeline and needs it at draw time. */
```

### [105] ligne 118 — *a reecrire*

```c
         /* VK_EXT_transform_feedback: byte stride of each capture buffer, 0
          * when unused. Lets the draw path work out how far a draw advances
          * each buffer without re-inspecting the shader.
          */
```

### [106] ligne 166 — *a reecrire*

```c
         /* Geometry shader emulation, dispatched between the vertex shader
          * and the draw. count and pre_gs are only built when the shader
          * needs counting; see enum kk_gs_program. */
```

### [107] ligne 198 — *a reecrire*

```c
   /* The programs poly_nir_lower_gs() produces alongside the main one. */
```

### [108] ligne 241 — *a reecrire*

```c
/* VK_EXT_transform_feedback: capture vertex outputs into the bound buffers,
 * bounds checked, from the same draw that rasterizes them. */
```

