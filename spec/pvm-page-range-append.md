# Immutable page-range append

This implementation preserves the existing sparse-memory contract in
[pvm-machine.md](pvm-machine.md), including the scoped scalar-access interpretation
in [pvm-polkavm-memory-order.md](pvm-polkavm-memory-order.md). No specification,
vector, compiler or dependency pins change.

## Construction and admission

`withPageRange` retains its existing owner/range checks, exact-owner empty return,
and complete materialized-page/native-int limit checks before construction. Only
non-dropping ranges with insertion slot equal to the old page count use the private
append constructor. Ordered endpoints then prove the stop slot is also the old
count: every new ordinal follows every old page. Physical contiguity is unnecessary;
sparse holes before the appended range stay absent.

For n old pages, share n div 64 complete immutable blocks. Copy only n mod 64 old
references into a private tail, then append new zero-page headers into private
blocks of at most 64 initialized entries. New root/tail sequences never alias mutable
source containers; old page/chunk/block owners remain immutable and acyclic. A final
exact fill publishes no empty block. All assertions and checked-build bounds remain.

Inaccessible+Preserved materializes zero pages and counts them against the original
limit. Inaccessible+Zeroed remains the existing dropped-range path. Interior inserts,
overlaps, remaps and drops retain the generic fallback. InvalidOwner precedes
InvalidRange, valid empty intervals return before allocation policy checks, and
LimitExceeded is decided before any constructor allocation or narrowing.

## Work and consumers

Construction copies at most 63 old PageData references, replacing per-page prefix
retains with one retained PageBlock per complete 64-page group. The transient flat
page-reference vector and rebuilding of complete prefix blocks disappear. The root
still costs O(blocks), and new headers cost O(new pages). With 64 fixed this remains
linear in old page count; no new asymptotic class or measured latency win is claimed.

A subsequent same-shaped retained-memory comparison can skip shared complete blocks
in both passes of `changedMemoryPageSlots`. Changed counts/permissions still refuse
that comparison and preserve the existing complete-frame fallback. Common machine
and retained-frame code applies to ARM64, x86 and interpreter consumers; no backend
eligibility, assembler or initialization-template behavior changes.

## Witnesses and current verification status

`pvm_page_range_append` compares complete independent PageImage oracles for empty,
63/64/65/127/128-page bases, exact fills, crossing appends and sparse physical gaps.
It covers all access/content pairs, materialized inaccessible versus dropped pages,
limits/refusal precedence, the final valid page, tail overlap and independent sibling
history through writes, chunk crossings and remaps. Public page identity checks
prove page preservation; they do not prove internal block sharing.

`pvm_memory_reuse` adds a true retained-frame consumer with 64- and 65-page bases and
fresh equal-sized argument successors, built directly through public memory APIs.
Literal complete CPU/images assert argument reads, dirty base restoration, padding,
old source/result history and unchanged-count reuse. An expanded map explicitly
requires refusal/fallback. This witness has no dependency on the initializer template
and does not claim native guest-fragment publication or internal block identity.

Local Darwin arm64 validation used the pinned Nimony compiler with ARC, Clang,
release optimization, ThinLTO, assertions and bounds checks retained. Pinned formatting
and focused semantic checks passed; registry inventory and 31 targeted Python checks
also passed. Two fresh native builds and two runs passed the
complete source-owned goldens: one line for `pvm_page_range_append`, three for
`pvm_memory_reuse`. The consumer enabled `pvmArm64Jit`; its assertions prove the common
retained-frame behavior, without claiming native guest-fragment publication.

The existing isolated 1,000-cycle ARC workload produced fresh numeric evidence with
occupied bytes equal before/after (432720). This is the original release workload,
not 1,000 iterations of the new consumer case. Generated C and both linked ARM64
callers confirm one retain per shared complete block, page retains only for the old
partial tail, moved private tail storage and no hidden full page-vector copy on the
append path. The generic fallback keeps its existing allocation behavior.

Source, commands, logs, full stdout/stderr, binaries and generated C are bound in the
local `build/directory-append/` qualification packet. Runtime/test files are unchanged
since that qualification; this results documentation is the only subsequent source
change. No Linux CI result or measured instruction/cache/latency improvement is claimed.
