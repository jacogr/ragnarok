# Retained selection indexes and component accounting

## Authorized continuation and decision

This continues native stack 1238 above tagged-cell head
`0ed42cd2990ebbecb9bb5d9f058b8ee7be9a092b`, within the original 30-PR ceiling. The maintainer
requested substantive feature PRs containing their tests and documentation. Component measurements
and selection-index compaction therefore belong to the same feature layer.

Use `make unit SUITE=storage_retained_components`. The public-operation panel varies 32/512/8192
entries and 0/1/15/16/17/31/32/33/255/256/257-byte values, in both payload orders. Every fixture
retires its source graph before measurement. A helper closes admission and retires its empty-view
and result temporaries before observing the sole complete graph owner. Selection and independent
clone deltas are observed separately; complete maps survive owner close and all local owners
return exactly to baseline. Independent ordinary sequence calibration excludes its descriptor
array and measures one payload allocation per leaf. Machine-word arrays calibrate physical
reference slots and the existing 17/257/4097-offset directories without private runtime hooks.

Baseline receipts: `build/storage-db11-components-baseline.tsv` (Apple M1 Max, Darwin 27 ARM64,
ordinary allocator and the unchanged pinned checked native profile). For 8192 entries, the graph
has 16,386 cells. Empty values retain 2,007,472 bytes; 256-byte values retain 4,104,624 bytes.
The difference is exactly 8192 times 256. Values of length 1/15/16 use 16 allocator bytes each;
17/31/32 use 32; 33 uses 48; 255/256 use 256; 257 uses 272. The graph payload slopes match
independent calibration in all cases. There is no measured payload rounding slack at 256 bytes.

Reference arrays cost 592/12,288/135,168 bytes at 74/1,030/16,386 cells. Directories cost
144/2,064/36,864 bytes at 4/8/12 prefix bits. Independent clones cost 944/14,560/172,240 bytes,
exactly reference array plus directory plus 208 bytes of table/revision metadata. The complete
zero-value graph is exactly 112 bytes per cell plus this clone cost in all three cases. This
accounts for the tagged-cell footprint without assigning allocator bytes from RSS observations.
The older small retained-layout panel includes an additional 352-byte empty admission view;
its before/after cell savings and payload slopes remain valid, while this panel retires that
fixed measurement owner before observation. Existing large fresh-reopen receipts are unchanged.

## Selected feature boundary

The baseline root selections retain 752/12,384/168,032 bytes for these same inventories,
independently of payload size. The 8192-entry plan has spare capacity beyond an exact index array.
Compact only this immutable retained index after all roots and complete graphs have passed
validation. Preserve canonical index order, every selected root, source ownership, selected node/
value totals, immutable independent clones, failure reasons and atomicity. Release traversal
scratch before allocating the exact result array; copying requires one additional bounded index
buffer while the former growable array is still live. Allocation exhaustion remains fail-stop.
No new public factory, protocol behavior, file format, compiler/provider pin or CI matrix is added.

Payload pooling is rejected for this increment: the existing 256-byte fixture has no measured
rounding slack and pooling would add retention coupling. Narrowing the small prefix directory is
also deferred: its 36 KiB cost does not justify a new representational boundary here. The chosen
feature addresses measured slack in long-lived maintenance plans rather than claiming a reduction
to the ordinary repository's 62.2 MiB graph floor.
