# Commentaires à réécrire dans l'arbre Mesa

La politique d'IA de Mesa (`src/mesa/CLAUDE.md`) interdit les commentaires de code
écrits par un agent. Les blocs ci-dessous ont été ajoutés au fil des correctifs et
doivent être **réécrits de la main de l'auteur** avant toute publication, ou
supprimés.

**122 blocs, 20 fichiers.** Les numéros de ligne sont ceux de
l'arbre de travail actuel.

Les correctifs les plus récents (0056 à 0059) ont été écrits **sans commentaire**,
conformément à la politique ; ce qu'il faudrait y inscrire est consigné en fin des
sections 159, 161, 163 et 165 de NOTES.md.


## src/kosmickrisp/vulkan/kk_shader.c — 29 blocs

### ligne 425

```c
      *out = MTL_BLEND_FACTOR_ONE_MINUS_SRC_COLOR; return true;
```

### ligne 428

```c
      *out = MTL_BLEND_FACTOR_ONE_MINUS_DST_COLOR; return true;
```

### ligne 431

```c
      *out = MTL_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA; return true;
```

### ligne 434

```c
      *out = MTL_BLEND_FACTOR_ONE_MINUS_DST_ALPHA; return true;
```

### ligne 436

```c
      *out = MTL_BLEND_FACTOR_SRC_ALPHA_SATURATED; return true;
```

### ligne 449

```c
      *out = MTL_BLEND_OPERATION_REVERSE_SUBTRACT; return true;
```

### ligne 510-511

```c
   *blend = out;
   *write_mask = BITFIELD_MASK(4);
```

### ligne 860-866

```c
   /* VK_EXT_transform_feedback. Metal has no transform feedback, but a Metal
    * vertex function may write to device buffers, so capture straight from
    * the vertex stage: keep_outputs leaves rasterization untouched and the
    * same draw both draws and captures. The address system values this leaves
    * behind are lowered against the root table in
    * kk_nir_lower_descriptors.c.
    */
```

### ligne 871

```c
      /* Fold constant IO offsets so the XFB info can be attached. */
```

### ligne 1067-1068

```c
      /* Capture strides survive kk_lower_nir(), which already turned the XFB
       * outputs into global stores. */
```

### ligne 1155-1161

```c
/* Metal's indirect compute dispatch counts threadgroups, so an indirect draw
 * has to round the grid up and ends up running invocations past the real
 * vertex or primitive count. poly's programs do not bound-check, so wrap the
 * body in a test here. The limit sits in the parameter buffer the program
 * already reads and is filled in for direct draws too, so the guard costs one
 * scalar load whichever kind of draw follows.
 */
```

### ligne 1231-1233

```c
/* Last leg shared by every program we hand to Metal: finish lowering, optimise
 * and translate to MSL, keeping the entrypoint name alive past the NIR.
 */
```

### ligne 1247-1248

```c
   /* Steal so it outlives the NIR. Must happen after nir_to_msl(), which is
    * where the entrypoint gets renamed. */
```

### ligne 1299-1302

```c
   /* A shader poly turns into compute has to keep its clip and cull distances
    * as ordinary outputs: the MSL lowering writes them into the rasterizer's
    * output struct, which a kernel has not got. poly's rasterization program
    * gets the pass instead, once it exists. */
```

### ligne 1335-1337

```c
      /* Metal has no geometry stage. poly_nir_lower_gs() rewrites the shader
       * into programs dispatched as compute before the draw, plus a plain
       * vertex shader that rasterizes whatever they produced. */
```

### ligne 1352-1353

```c
      /* The main program runs as compute, like the vertex shader does on the
       * tessellation path. */
```

### ligne 1377-1378

```c
         /* The counting program is a clone of the geometry shader and still
          * claims to be one; like the main program it runs as compute. */
```

### ligne 1384-1385

```c
         /* These come straight out of poly and have seen none of the
          * preprocessing the application's shaders went through. */
```

### ligne 1390-1394

```c
         /* Only this one feeds the rasterizer, so only this one gets the
          * lowering every hardware vertex shader goes through -- point size,
          * position, depth clamp -- and the clip and cull distances. What it
          * rasterizes is the geometry shader's output primitive, not the
          * topology the application drew with. */
```

### ligne 1399-1401

```c
            /* That lowering reaches for root-table system values (the clip Z
             * coefficient, for one). poly's programs carry no descriptors, so
             * no set layout is needed to resolve them. */
```

### ligne 1812-1814

```c
      /* A geometry shader brings more than one program along. Carry them and
       * their layout over too, since the pipeline is built from the vertex
       * shader. */
```

### ligne 1839

```c
      /* What reaches the rasterizer is what the geometry shader emits. */
```

### ligne 1899

```c
   /* Layered rendering in Metal requires setting primitive topology class */
```

### ligne 1903-1906

```c
   /* If color attachments are reordered there might be unused / invalid gaps
    * in the array so need to check them all, not just first
    * color_attachment_count entries.
    */
```

### ligne 1966

```c
            *stored = *key;
```

### ligne 1993-1995

```c
      /* Geometry shaders take their own route. The vertex shader and every
       * program poly produced run as compute before the draw, and what
       * actually feeds the rasterizer is poly's own vertex program. */
```

### ligne 2006-2009

```c
      /* A geometry shader fed by tessellation would have to read the
       * tessellation evaluation shader's output rather than the vertex
       * shader's, and the two emulations would have to be chained. Not wired
       * up: refuse rather than rasterize the wrong buffer. */
```

### ligne 2030

```c
      /* Counting and pre-GS only exist when the shader needs them. */
```

### ligne 2226-2227

```c
   /* Determine if the pipeline contains tessellation or geometry stages; both
    * push earlier stages into compute. */
```


## src/kosmickrisp/vulkan/kk_cmd_draw.c — 23 blocs

### ligne 679

```c
   /* Clean up previous encoder */
```

### ligne 1293-1296

```c
/* Parameters the geometry shader emulation programs read, plus the index
 * buffer the rasterization draw will consume. poly decides the shape of that
 * draw; we only have to lay out what it asked for.
 */
```

### ligne 1338-1340

```c
      /* The topology is a compile-time constant, so it is the same whatever
       * the draw. poly hands it to us byte-sized, but Metal only indexes with
       * 16 or 32 bit values, so widen it on the way out. */
```

### ligne 1355-1357

```c
   /* An indirect draw only knows its counts on the GPU: poly's setup kernel
    * fills the rest of this in, including the index buffer of a dynamically
    * indexed shape, which it takes from the device heap. */
```

### ligne 1392

```c
      /* The geometry shader writes this one itself. */
```

### ligne 1893

```c
   /* So does geometry: the emulation programs read their parameters from it. */
```

### ligne 2199-2205

```c
/*
 * Metal has no geometry stage, so poly rewrote the shader into compute
 * programs (see kk_compile_shader()). Run them here, in front of the draw:
 * the vertex shader feeds the geometry shader, and what the geometry shader
 * produced is then rasterized by poly's own vertex program, which is already
 * bound as this pipeline's render shader.
 */
```

### ligne 2220-2221

```c
      /* Only the GPU knows the counts, so poly's setup kernel fills in the
       * parameter buffers and the dispatch grids from the indirect command. */
```

### ligne 2262-2263

```c
   /* The vertex shader, as compute, writing its outputs where the geometry
    * shader will read them. */
```

### ligne 2288

```c
   /* The geometry shader proper, one invocation per input primitive. */
```

### ligne 2293-2297

```c
   /* Whatever shape poly chose for the rasterization draw. For a direct draw
    * the third component of the grid is the base instance, not a depth: the
    * rasterization shader decodes the primitive from a zero-based instance
    * index, so it must stay 0. An indirect one reads the command poly wrote,
    * whose layout already matches Metal's. */
```

### ligne 2310

```c
         /* poly allocated that index buffer out of the device heap. */
```

### ligne 2488-2506

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

### ligne 2522

```c
   /* An indirect draw's vertex count is only known on the GPU. */
```

### ligne 2526-2528

```c
   /* For an indexed draw the vertex ID is the index value, not the position
    * in the draw, so it cannot address the capture buffer.
    */
```

### ligne 2532-2534

```c
   /* A multi-draw would need each draw to start where the previous one
    * stopped, which is one base address per draw.
    */
```

### ligne 2561

```c
/* Vertex count of a direct draw, indexed or not. */
```

### ligne 2591

```c
   /* Only shaders that capture read any of this. */
```

### ligne 2610

```c
      /* The stream still produces primitives, they are just not captured. */
```

### ligne 2648

```c
   /* Vertices that still fit in every buffer this shader captures into. */
```

### ligne 2652

```c
      /* info.vs.xfb_stride is in words, like nir_shader_info. */
```

### ligne 2682-2683

```c
      /* The shader drops whatever runs past the end of a buffer, so only the
       * primitives whose vertices all fit count as written. */
```

### ligne 2807

```c
   /* Must run before the root table is uploaded. */
```


## src/kosmickrisp/vulkan/kk_cmd_buffer.h — 12 blocs

### ligne 59-64

```c
         /* VK_EXT_transform_feedback. nir_lower_xfb_to_stores() captures at
          *   xfb_address[buf] + (instance_id * xfb_num_vertices + raw_vertex_id)
          *                      * stride + offset
          * xfb_address already includes everything earlier draws in this
          * capture wrote, so each draw appends rather than overwrites.
          */
```

### ligne 67-68

```c
         /* Bytes still writable in each buffer. Zero while capture is
          * inactive, which is how the shader's captures get switched off. */
```

### ligne 109-110

```c
   /* Non-zero when the last vertex of a primitive is the provoking one.
    * poly's geometry lowering reads it to order the indices it emits. */
```

### ligne 123

```c
   /* Address of geometry param buffer if a geometry shader is used, else 0 */
```

### ligne 205

```c
   /* VK_EXT_transform_feedback capture state */
```

### ligne 207

```c
      /* Buffers bound by vkCmdBindTransformFeedbackBuffersEXT. */
```

### ligne 213-217

```c
      /* Bytes already captured into each buffer since the current
       * vkCmdBeginTransformFeedbackEXT, tracked on the CPU: with the
       * vertex-indexed capture scheme the write offsets of a draw are known
       * before it runs.
       */
```

### ligne 220-222

```c
      /* Counter buffers handed to vkCmdEndTransformFeedbackEXT, so the byte
       * counts can be written back when capture stops.
       */
```

### ligne 232-234

```c
      /* Active VK_QUERY_TYPE_TRANSFORM_FEEDBACK_STREAM_EXT query. Addresses
       * rather than the pool, to keep the query pool out of this header.
       */
```

### ligne 245-247

```c
   /* Geometry shader emulation: what the rasterization draw should use once
    * the emulation programs have run. Filled while uploading the geometry
    * parameters, consumed by kk_launch_gs(). */
```

### ligne 331-335

```c
      /* Metal command buffers already closed for this recording, in the order
       * they must execute. A recording that would overrun a single command
       * buffer's encoder budget is spread over several; see
       * KK_MAX_ENCODERS_PER_COMMAND_BUFFER. Empty in the common case.
       */
```

### ligne 337

```c
      /* Encoders opened on cmd_buf since it was begun. */
```


## src/kosmickrisp/vulkan/kk_shader.h — 9 blocs

### ligne 56-59

```c
/* Metal has no geometry stage, so poly_nir_lower_gs() splits a geometry shader
 * into several programs run as compute before the draw. Only the main one maps
 * onto a Vulkan stage; the others live in kk_shader::gs_msl_data.
 */
```

### ligne 61-62

```c
   /* Counts the primitives each input primitive emits. Only built when the
    * shader needs counting -- transform feedback or pipeline statistics. */
```

### ligne 64

```c
   /* Prefix sums those counts and fills in the indirect draw. */
```

### ligne 66

```c
   /* Plain vertex shader that rasterizes what the geometry shader produced. */
```

### ligne 79-80

```c
   /* Geometry shader emulation. Kept outside the union because the vertex
    * shader carries the whole pipeline and needs it at draw time. */
```

### ligne 119-122

```c
         /* VK_EXT_transform_feedback: byte stride of each capture buffer, 0
          * when unused. Lets the draw path work out how far a draw advances
          * each buffer without re-inspecting the shader.
          */
```

### ligne 167-169

```c
         /* Geometry shader emulation, dispatched between the vertex shader
          * and the draw. count and pre_gs are only built when the shader
          * needs counting; see enum kk_gs_program. */
```

### ligne 199

```c
   /* The programs poly_nir_lower_gs() produces alongside the main one. */
```

### ligne 246-247

```c
/* VK_EXT_transform_feedback: capture vertex outputs into the bound buffers,
 * bounds checked, from the same draw that rasterizes them. */
```


## src/kosmickrisp/vulkan/kk_cmd_buffer.c — 7 blocs

### ligne 180-181

```c
   /* Recording is over and whatever used these has been submitted, so the
    * split-off command buffers can go back to the pool. */
```

### ligne 283-294

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

### ligne 307-308

```c
   /* Without a spare, keep filling the current one: overshooting the budget
    * may still work, whereas dropping commands certainly would not. */
```

### ligne 315-318

```c
   /* The budget is per command buffer, not per allocator -- measured: one
    * allocator happily backs 131072 encoders spread over eight command
    * buffers, while 38000 in a single one is refused -- so the recording
    * keeps the allocator it started with. */
```

### ligne 472-474

```c
      /* Counted but not split on: a compute encoder can be opened from inside
       * cs_end() to flush post-render writes, where splitting would cut the
       * recording in an awkward place. */
```

### ligne 1242

```c
   *cursor = align(*cursor, align_b);
```

### ligne 1245

```c
   *cursor += len;
```


## src/kosmickrisp/vulkan/kk_physical_device.c — 7 blocs

### ligne 377

```c
      /* VK_EXT_descriptor_buffer */
```

### ligne 484

```c
      /* VK_EXT_dynamic_rendering_unused_attachments */
```

### ligne 487

```c
      /* VK_EXT_transform_feedback */
```

### ligne 512

```c
      /* VK_EXT_device_generated_commands */
```

### ligne 794-797

```c
      /* Metal wants 16 bytes whatever the format, but a view whose offset is
       * only texel aligned is emulated: the texture starts at the boundary
       * below and the shader shifts the coordinate. See
       * struct kk_texel_buffer_descriptor. */
```

### ligne 873

```c
      /* VK_EXT_device_generated_commands */
```

### ligne 944

```c
      /* VK_EXT_descriptor_buffer */
```


## src/kosmickrisp/vulkan/kk_nir_lower_descriptors.c — 6 blocs

### ligne 41

```c
      *ctx->fields_read |= 1u << f;
```

### ligne 437-440

```c
   /* A texel buffer view may start mid-way through the 16 byte granule Metal
    * insists on, so shift the coordinate past the texels the view skipped.
    * See struct kk_texel_buffer_descriptor.
    */
```

### ligne 590-593

```c
   /* VK_EXT_transform_feedback. nir_lower_xfb_to_stores() leaves these for
    * the driver; we feed them from the root table, which the draw path fills
    * in before every capturing draw.
    */
```

### ligne 633-635

```c
   /* Metal's [[vertex_id]] counts from the draw's first vertex, so undo that
    * to get the zero-based index the capture offsets are computed from.
    */
```

### ligne 803

```c
   /* Same shift for the sampled side. */
```

### ligne 1228

```c
      *fields_read = read_mask;
```


## src/kosmickrisp/vulkan/kk_nir_lower_xfb.c — 6 blocs

### ligne 1-4

```c
/*
 * Copyright 2026 The Mesa contributors
 * SPDX-License-Identifier: MIT
 */
```

### ligne 11-30

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

### ligne 39

```c
   /* Transform feedback info is in words, Metal addresses are in bytes. */
```

### ligne 62

```c
   /* Discard anything that would land outside the bound range. */
```

### ligne 78

```c
   /* Capture programs consume the zero-based hardware vertex ID. */
```

### ligne 106

```c
   /* Keep the store_output: this draw still rasterizes. */
```


## src/kosmickrisp/vulkan/kk_buffer_view.c — 4 blocs

### ligne 69-71

```c
   /* kk_get_va_format() returns NULL for anything missing from the texel
    * buffer table, so this cannot assume the format is usable. Fail the call
    * instead of dereferencing NULL. */
```

### ligne 112-116

```c
   /* Metal only takes a 16 byte aligned offset for a texture buffer, whatever
    * the format, but Vulkan lets the view start at any texel. Start the
    * texture at the boundary below and remember how many texels that added in
    * front; kk_nir_lower_descriptors.c adds them back to every coordinate.
    */
```

### ligne 123-127

```c
   /* The offset is a multiple of the texel size (that is what
    * *TexelBufferOffsetSingleTexelAlignment promises the application), and so
    * is the 16 byte boundary for any format we expose, so the bias lands on a
    * whole number of texels.
    */
```

### ligne 134-136

```c
   /* Past this Metal aborts the process from its own validation rather than
    * returning nil, so refuse the view here. Note the prefix added above
    * counts towards the limit. */
```


## src/kosmickrisp/vulkan/kk_private.h — 4 blocs

### ligne 28-33

```c
/* A Metal command buffer -- really the allocator backing it -- only holds so
 * many encoders before the commit is rejected. Measured on an M1 Max with a
 * fresh allocator: 36000 encoders commit, 38000 do not. Allocators are
 * recycled here without ever being reset, so their remaining room is unknown;
 * split well clear of the measured ceiling.
 */
```

### ligne 35

```c
/* Workgroup poly's geometry shader programs are compiled and dispatched with. */
```

### ligne 38

```c
/* Metal caps a texture array at this many layers. */
```

### ligne 40

```c
/* Metal caps a texture buffer at this many texels. */
```


## src/kosmickrisp/vulkan/kk_query_pool.c — 4 blocs

### ligne 42

```c
      /* primitivesWritten and primitivesGenerated. */
```

### ligne 208-209

```c
      /* kk_query_report_addr() scales the remapped index by one report, so
       * space the identity mapping out by the reports each query owns. */
```

### ligne 398

```c
   *index_out = query % KK_TS_COUNTER_HEAP_ENTRIES;
```

### ligne 489-497

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


## src/kosmickrisp/libkk/kk_xfb.cl — 2 blocs

### ligne 1-4

```c
/*
 * Copyright 2026 The Mesa contributors
 * SPDX-License-Identifier: MIT
 */
```

### ligne 13

```c
   *dst = *counter + added;
```


## src/kosmickrisp/vulkan/kk_queue.c — 2 blocs

### ligne 101-103

```c
   /* A long recording is split across several Metal command buffers (see
    * kk_cmd_buffer_split_if_full()); commit them in recording order, the
    * still-open one last. Metal runs them in that order on the queue. */
```

### ligne 125-127

```c
         /* Without the array the pieces can still go one after another; the
          * queue keeps them in order. Only the last one carries the feedback
          * handler, which is the one the caller waits on. */
```


## src/kosmickrisp/libkk/kk_geometry.cl — 1 blocs

### ligne 51-56

```c
/* Geometry shader emulation, indirect draw. Only the GPU knows the vertex and
 * instance counts, so poly fills in the parameter buffers here, and we turn
 * the thread counts it computed into the threadgroup counts Metal's indirect
 * dispatch expects. Invocations past the real count are dropped by the guard
 * kk_shader.c puts at the top of each emulated program.
 */
```


## src/kosmickrisp/vulkan/kk_buffer_view.h — 1 blocs

### ligne 27-30

```c
   /* Texels between the start of the Metal texture and this view's first
    * element. Non-zero when the requested offset was not 16 byte aligned.
    * See struct kk_texel_buffer_descriptor.
    */
```


## src/kosmickrisp/vulkan/kk_descriptor_set_layout.c — 1 blocs

### ligne 49-50

```c
      /* Carries the texel bias on top of the resource id. */
      *stride = *alignment = sizeof(struct kk_texel_buffer_descriptor);
```


## src/kosmickrisp/vulkan/kk_descriptor_types.h — 1 blocs

### ligne 48-58

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


## src/kosmickrisp/vulkan/kk_image.c — 1 blocs

### ligne 624-626

```c
   /* Metal validates arrayLength itself and aborts the process rather than
    * returning nil, so catch an over-long array here. The limit reported in
    * maxImageArrayLayers is the same one Metal enforces. */
```


## src/kosmickrisp/vulkan/kk_query_pool.h — 1 blocs

### ligne 16-19

```c
   /* Metal 4 counter heaps backing VK_QUERY_TYPE_TIMESTAMP pools. Timestamps
    * are sampled into them and later resolved into `bo` (see kk_query_pool.c).
    * A single heap holds at most KK_TS_COUNTER_HEAP_ENTRIES entries, so a pool
    * larger than that is spread over several. NULL for non-timestamp pools. */
```


## src/kosmickrisp/vulkan/kk_sampler.c — 1 blocs

### ligne 214

```c
      /* We also need to record the border. */
```

