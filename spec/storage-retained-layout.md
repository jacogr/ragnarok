# Retained immutable repository layout

## Authorized scope and acceptance

The next storage increment measures immutable cell, reference-array and prefix-index ownership
before choosing a representation. Its baseline is merged master
`90dc41d568ec4bb775eb9917a2239953c7eccbe1`. The maintainer authorized at most 30 substantive
stacked PRs; that is a ceiling, not a target. This work does not change protocol encodings, disk
formats, compiler/provider pins, allocator, checked ARC/Clang configuration or routine CI workloads.

Run `make unit SUITE=storage_retained_layout`. The deterministic public-operation panel varies
32/512 entries and 0/32/257-byte values, repeats sizes in reverse order, and requires identical
retained live Nim bytes in both orders. Source maps, trie owners and detached records retire
before admission. The stable encoded source remains outside both allocator observations.
The observation follows encoded publication and explicit repository close; the held immutable
view is the graph owner. Every complete key/value map is independently checked after close,
and every observation must return exactly to its allocator baseline after releasing the view.
The supported runner writes `storage-retained-layout.tsv` in its `RAGNAROK_TEST_EVIDENCE`
folder; copy the baseline before a candidate run.

This panel distinguishes payload-dependent growth from a graph's non-payload footprint, but
does not assign all bytes to individual allocations. Live Nim allocator bytes exclude native
provider allocations, stack, OS page cache and allocator-reserved pages. Compiler-emitted C
layouts describe object size/alignment, not allocator block rounding or resident pages.

Use the existing optional `make bench-storage-fresh-reopen` and paired-reopen targets for
whole-child RSS, exact roots/maps, selected file bytes and release on larger disk fixtures.
Capture a clean baseline binary/report before the representation change, freeze them under
ignored `build/`, and keep identical providers and checked build flags. Comparison must allow
only reviewed source differences; imported report command vectors must never be executed.
No wall-clock speed claim follows from retained-byte or RSS measurements.

## Representation decision gate

Inspect the actual pinned compiler's C cell/reference/index layout and record the retained panel
before changing production code. A candidate must reduce measured retained heap on the same
inputs, preserve complete mapping/root/record identity and independent view lifetime, and pass
affected raw/encoded admission, image, selection and disk consumers. Unused raw transport fields
remain canonical zero/empty. Full physical child edges remain significant even where JAM masks
an edge bit during hashing. Complete-root inventory, checked arithmetic, failure precedence and
atomic installation remain unchanged. No trusted public constructor or validation bypass is added.

The retained graph remains proportional to the complete admitted physical inventory. Smaller
cells do not provide bounded working-set or out-of-core authority. Allocation exhaustion,
power-loss scope, external checkpoint trust and full/light integration retain their separate gates.
The documented M1 framing and implemented-scope migration completion do not establish complete
JAM state serialization or whole-client parity.

## Baseline diagnosis

The checked native panel on Apple M1 Max/macOS ARM64 records:

| Entries | Bytes/value | Physical nodes | Retained live Nim bytes |
| --- | --- | --- | --- |
| 32 | 0 | 74 | 13,136 |
| 32 | 32 | 74 | 14,160 |
| 32 | 257 | 74 | 21,840 |
| 512 | 0 | 1,030 | 179,712 |
| 512 | 32 | 1,030 | 196,096 |
| 512 | 257 | 1,030 | 318,976 |

The 32-byte payload slope is exactly entry count times 32. The 257-byte case also reflects
allocator rounding; do not treat that slope as exact raw payload capacity. Counts include
canonical unary routing branches, so physical inventory need not equal twice the leaf count.
Clang's layout dump of the pinned compiler-generated baseline C reports a 144-byte cell body,
alignment 8, and a 152-byte ARC owner including its reference counter. A sorted table additionally
owns one pointer per physical cell and an independently allocated 4/8/12-bit prefix directory.
These sizes do not include allocator rounding. Source and generated layout support testing a
private tagged leaf/branch cell before considering a different reference/index architecture.

Baseline checks: `make unit SUITE=storage_retained_layout` and `make check-inventory` pass.
Native measurement assertions use the repository's checked pinned Nimony profile. The outer
report-release observation warms the stdlib's persistent process-environment cache first;
that cache is not repository-owned storage. Each graph observation separately checks exact release.
