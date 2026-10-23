# Retained selection indexes and component accounting

## Authorized continuation and decision

This continues native stack 1238 above tagged-cell head
`0ed42cd2990ebbecb9bb5d9f058b8ee7be9a092b`, within the current 15-PR batch ceiling. The maintainer
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
Selection construction now compacts only this immutable retained index after all roots and
complete graphs have passed validation. Preserve canonical index order, every selected root, source ownership, selected node/
value totals, immutable independent clones, failure reasons and atomicity. Release traversal
scratch before allocating the exact result array; copying requires one additional bounded index
buffer while the former growable array is still live. Allocation exhaustion remains fail-stop.
No new public factory, protocol behavior, file format, compiler/provider pin or CI matrix is added.

Payload pooling is rejected for this increment: the existing 256-byte fixture has no measured
rounding slack and pooling would add retention coupling. Narrowing the small prefix directory is
also deferred: its 36 KiB cost does not justify a new representational boundary here. The chosen
feature addresses measured slack in long-lived maintenance plans rather than claiming a reduction
to the ordinary repository's 62.2 MiB graph floor.

## Feature result and tradeoff

| Entries | Physical cells | Baseline selection bytes | Compact selection bytes | Saving |
| --- | ---: | ---: | ---: | ---: |
| 32 | 74 | 752 | 688 | 64 |
| 512 | 1,030 | 12,384 | 12,384 | 0 |
| 8,192 | 16,386 | 168,032 | 135,264 | 32,768 |

The large panel selection saves 19.5% of its retained overhead. All 33 payload/count cases keep
identical graph, clone, independent payload-calibration and reference-array bytes. Payload order
is reversed within each native run. The one-root plan now retains the calibrated exact machine-word
index allocation plus 96 observed metadata/root bytes; the suite requires at most 128 extra bytes.
An exact requested extent still includes the allocator's ordinary size-class/page rounding.
This does not reduce the repository's ordinary full-graph floor or qualify an RSS ceiling.

The implementation preserves graph traversal, duplicate-root coalescing, full physical address
order, checked inherited policies and source binding. It adds an O(k) copy after the existing
sort of k selected indexes. A lexical scratch scope releases traversal bitmaps and per-root visit
positions first. During final copying, both old and exact index buffers coexist; their lengths
are bounded by the already admitted physical inventory. For a union of many small historical
graphs, the extra final buffer can exceed the just-retired traversal scratch. No universal peak
memory or timing improvement is claimed. Allocator exhaustion keeps the established fail-stop
contract, and no normal failure can expose a partly frozen plan.

## Verification and reproducibility

Baseline component commit: `93ba75cd01e88fa1a536166e014fa1da070d1b11` (production identical to #1237).
Local full receipts remain under ignored `build/`:

- `storage-db11-components-baseline.tsv`, `storage-db11-components-candidate.tsv` and
  `storage-db11-component-comparison.json` retain all scalar observations and unchanged-component checks.
- `storage-db11-components-baseline.log`, `storage-db11-components-candidate.log` and the matching
  semantic-check logs retain the native build/runtime verdicts.
- `storage-db11-selection-compaction.log` and the runner's fresh ARC evidence retain 1,000 complete
  release cycles without reducing the established harness requirement.
- `storage-db11-selected-checks.json`, inventory and pinned formatting logs retain affected-consumer
  results, distinct from full Linux CI or the earlier paired reopen qualification.

`storage_selection_compaction` covers empty and singleton maps, 65/257 disjoint one-leaf historical
roots, reordered/duplicate root lists, identical canonical physical inventory bytes, complete
historical maps after clone close, a narrower clone that cannot reach unselected history, detached
lookup mutation, rejected limits/current-root omissions and a late missing root. Earlier held
plans survive those failures. The 1,000-cycle release path includes empty, singleton and several-root
unions. `storage_retained_components` covers larger full maps, directory thresholds, independently
calibrated heap costs, closed owners and complete independent clones.

The affected existing suites are retention planning, selection lifetime, historical roots, raw and
encoded images, managed compaction/repository/usage, admission graph authority and the original
retained-layout panel. Run them with `make unit SUITE=<name>`; run `make check-inventory` for the
two suite declarations and `make format-check` for pinned formatting. The original retained-layout
panel remains byte-identical to the tagged-cell result. All twelve selected native suites,
`make check-inventory` and `make format-check` passed locally. No new CI job/matrix or ordinary
performance samples are introduced. No full-project Linux, interop, speed or power-loss verdict
is inferred from these scoped local checks.

The documented M1 framing and implemented-scope migration completion remain separate from full
JAM state serialization and client parity. The complete graph remains resident; bounded working-set
ownership and on-disk graph authority need a separately specified design. The next memory decision
should target the measured per-cell ownership floor only if its expected benefit justifies added
sharing/lifetime complexity. Payload pooling and directory narrowing are not assumed future wins.
