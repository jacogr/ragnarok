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

## Tagged-cell candidate

The candidate keeps the common physical digest and a private immutable discriminator, storing
leaf key/payload and branch child hashes in alternatives. Constructors run only after existing
raw or encoded validation. Raw mutable values still deep-copy; freshly decoder-owned leaf values
still transfer once. Export reconstructs a complete canonical `TrieRecord` with unused fields
zero/empty. Duplicate/conflict comparison checks every active field, including complete physical
branch edges. Mixed inventories explicitly count zero payload bytes for branches.

The pinned generated C body is 104 bytes, alignment 8; its ARC owner is 112 bytes. The body
reduction is 40 bytes. Actual live allocator savings are 48 bytes per physical cell in all six
panel cases, which includes allocator rounding rather than attributing 48 bytes to C fields.
Reference arrays, index directory widths and sharing across revisions are unchanged.

| Entries | Bytes/value | Baseline retained | Candidate retained | Saved bytes |
| --- | --- | --- | --- | --- |
| 32 | 0 | 13,136 | 9,584 | 3,552 |
| 32 | 32 | 14,160 | 10,608 | 3,552 |
| 32 | 257 | 21,840 | 18,288 | 3,552 |
| 512 | 0 | 179,712 | 130,272 | 49,440 |
| 512 | 32 | 196,096 | 146,656 | 49,440 |
| 512 | 257 | 318,976 | 269,536 | 49,440 |

These are retained live Nim bytes for the same complete graph; the percentage improvement
varies with value size. Both orders preserve exact complete maps after owner close and return
to the same allocator baseline. The test's fixed ceilings and deterministic fixtures remain
unchanged between binaries. This does not establish an RSS or timing improvement by itself.

## Functional verification

The unchanged checked native suites pass: `storage_repository`, `storage_encoded_publication`,
`storage_image`, `storage_image_decode`, `storage_admission_precedence`,
`storage_admission_backend_failures`, `storage_admission_ownership`,
`storage_admission_graph_authority`, `storage_image_staging_failures`,
`storage_image_admission_limits`, `storage_retention_plan`, `storage_historical_roots`,
`storage_managed_repository`, `storage_context_repository`, `storage_managed_compaction`,
`storage_admission_file_corruption` and `storage_record_owners`. Existing ARC suites retain
1,000 cycles and exact release. The retained-layout panel also passes with the candidate.

Eight selected compiler controls reject the private decoded-record factory, image/publication
stages, codec scan, repository head, result payload/reason and view data with their expected
module/field privacy diagnostics. This is scoped local evidence, not a full Linux unit/Python/
interop or resident-pressure CI verdict. Original compiler and provider inputs remain pinned.

## Paired strict-reopen qualification

Clean baseline measurement head: `0860f1b107073f6d37d0182d3fc4f0ac1bd2dccf`.
Clean candidate measurement head: `52e65c457f7f5ba8f311e4ba8f88826a61f16e5a`.
The subsequent qualification commit changes this feature record only. The 455 captured measurement
inputs remain identical to the candidate; only `src/storage/node/repository.nim` differs between
baseline and candidate. Compiler, checked ARC/Clang LTO flags, providers, interpreter, native
workload, observer, same-host identity and selected namespace bytes match.

The maintained paired driver completes eight producer invocations and sixteen fresh consumers:
two reversed case/binary orders, both producer directions, journal/managed backends and
32,768/131,072-entry fixtures. Every consumer checks its independently supplied exact root,
complete map before and after close, unchanged selected file bytes and complete allocator release.
Read-only validation reparses all receipts without executing imported command vectors.

Host: Apple M1 Max, Darwin 27.0.0, ARM64, 16,384-byte pages. Both observations per table cell round
to the same displayed tenth of a MiB:

| Backend | Entries | Baseline RSS MiB | Candidate RSS MiB | Baseline live Nim MiB | Candidate live Nim MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Journal | 32,768 | 43.3 | 40.1 | 18.7 | 15.6 |
| Journal | 131,072 | 165.9 | 153.5 | 74.2 | 62.2 |
| Managed | 32,768 | 43.3 | 40.1 | 18.7 | 15.6 |
| Managed | 131,072 | 172.6 | 153.4 | 74.2 | 62.2 |

At 131,072 entries the inventory contains 262,750 physical cells; the retained allocator saving
is exactly 12,612,000 bytes (48 per cell). Whole-child RSS includes temporary admission/IO work,
allocator reservation and native providers, so its larger managed reduction is not assigned to
specific allocations. This is no speed, cold-cache, paging or deployment-ceiling qualification.
Prior Linux pressure results describe their recorded earlier binary; this candidate has no new
Linux resident-pressure verdict, and large no-swap cases remain unqualified.

Local reproducibility/evidence:

- `build/storage-db10-layout-baseline.tsv` and `build/storage-db10-layout-candidate.tsv`.
- `build/storage-db10-cell-layouts.json`: exact generated-C hashes and Clang record layouts.
- `build/storage-db10-baseline/` and `build/storage-db10-candidate/`: frozen local native binaries,
  clean source/build identities and complete individual reports.
- `build/storage-db10-pair-config.json`: explicit local report/binary selection and one approved
  production source difference.
- `build/storage-db10-paired/results.json` and `summary.md`: complete paired receipts.
- `build/storage-db10-selected-checks.json` and `build/storage-db10-private-guards.json`.

Use `make inspect-storage-reopen-pair REOPEN_PAIR_CONFIG=build/storage-db10-pair-config.json`
for read-only admission, `make bench-storage-reopen-pair` with the same config and
`REOPEN_PAIR_OUTPUT` for explicitly authorized local execution, and
`make summary-storage-reopen-pair REOPEN_PAIR_REPORT=build/storage-db10-paired/results.json`
for read-only receipt validation. Rebuild fresh clean reports when captured inputs change;
never edit historical source identities to relabel a dirty or different binary as comparable.

## Completion and next bounded decision

The retained-layout measurement and private tagged-cell increment are complete within their
local qualified scope. Stop here rather than expanding routine performance/CI workloads.
The remaining large-fixture live graph is about 62.2 MiB. Further representation work should
first measure payload allocation slack and reference/index contribution on the same complete-map,
root and lifetime workload before increasing sharing/reclamation complexity. No further packing
benefit is assumed. A separately specified bounded working set and on-disk graph authority is
still required for a database larger than RAM. Existing M1 framing/implemented-scope migration
completion remains distinct from full JAM state serialization and client parity.
