# Heap memory preparation

## Scope and specification

Gray Paper 0.8.0 is pinned at `07f041dabd073f9018b418e9ee72e79dd2185401`.
The `grow_heap` row in `text/pvm_invocations.tex` defines the current heap endpoint
using the count of writable pages in the RW region and sets access permissions
on a half-open page interval. Unspecified memory bytes remain unchanged under the
general-functions preamble.

This increment supplies those memory operations, not a host response:

- `writablePageCount` counts writable pages in a validated half-open interval.
- `withWritablePages` maps that interval writable, preserving every retained byte
  and every page outside it. Newly materialized pages contain zero bytes.
- Endpoints are page ordinals; the exclusive endpoint may equal `2^20`. Default
  owners, reversed ranges and out-of-domain endpoints return typed failure.
- The complete posterior materialized-page count is checked against the memory
  owner's allocation limit before allocating. Permission changes at the limit are
  allowed. Inaccessible retained pages count toward that allocation limit.
- Snapshots remain immutable. The implementation merges the sorted sparse page
  vector in one pass, sharing unchanged page owners rather than repeatedly copying
  the complete vector for every added page.

The caller remains responsible for heap bounds and gas. This environment operation
may map any validated interval, like the existing single-page `withPage` primitive;
it does not expose guest authority to remap arbitrary memory.

## Historical host differences and adoption

The pinned vector release `d3c089c9a1d5352ad353626d7a2db8589f137b2a` explicitly
records two deviations in `vendor/jamtestvectors/CHANGELOG.md`:

1. Gas exhaustion follows GP PR [533](https://github.com/gavofyork/graypaper/pull/533),
   draining the gas counter to zero. The pinned GP's explicit growth branch retains
   the original gas counter on OOG. Its table-wide affordability rule and explicit
   no-growth branch also require reconciliation: the listed cost is
   `275 + (r7 - h) * 121`, while no-growth explicitly charges only 275.
2. The address-space ceiling follows PR [538](https://github.com/gavofyork/graypaper/pull/538),
   rounding the stack reservation to 64 KiB. The pinned GP's expression uses page
   rounding (4 KiB). For a one-byte stack these differ by 15 writable pages.

Both changes merged upstream on 2026-07-22. The initial implementation left them
pending local adoption rather than changing its base pins. On 2026-10-19 the
maintainer explicitly adopted both grow_heap fixes while preserving repository
pins. [Bounded host integration](pvm-accumulation-heap.md) implements gas/result
ordering from #533 and stack reservation from #538; its exact source/merge hashes
are in [the adoption record](pvm-grow-heap-adoption.json). The historical gas and
ceiling pending tests are now active adoption checks. The separate request-domain
pin-upgrade decision is unchanged, and no other #533 behavior is adopted here.

## Completion evidence

Native tests cover empty and full-address-space counts, sparse holes, mixed access,
retained bytes, zero initialization, first/last pages, reversed/oversized ranges,
exact and exceeded allocation limits, repeated mapping, independent snapshots,
a deterministic dense reference and ARC release. Strict runtime and compile-time
probes preserve result and nominal page-count contracts. Local verification results
are reported with the PR; Linux CI remains a separate gate.
