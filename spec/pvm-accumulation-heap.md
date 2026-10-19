# Bounded accumulation heap host integration

## Scope and authority

Base pins remain GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` and
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. On 2026-10-19 the
maintainer explicitly adopted the two merged grow_heap fixes already followed by
that vector release, while directing that repository pins remain unchanged:

- [GP #533](https://github.com/gavofyork/graypaper/pull/533), merged 2026-07-22,
  commit `0c0664eb52ba92afd8d21cef96c0e1da506eddfe`: gas is clamped to zero
  on OOG, without a negative deficit; registers, memory and context are unchanged.
  Grow_heap cost uses the selected returned endpoint, so no-growth costs 275.
- [GP #538](https://github.com/gavofyork/graypaper/pull/538), merged 2026-07-22,
  commit `b76e637c0901f1beb6fc7a63f4e64f8707b94baf`: reserve stack address
  space in 64 KiB zones, preserving the required guard region.

[The adoption record](pvm-grow-heap-adoption.json) retains exact source identities
and SHA-256 values. This supersedes the historical local host gate recorded in
[pvm-heap-memory](pvm-heap-memory.md) and [integration](pvm-accumulation-integration.md).
These were resolved upstream, pending local adoption, rather than unanswered
upstream questions. Adoption is limited to grow_heap; other #533 changes are not
silently applied to existing host functions or terminal normalization.

## Behavior and ownership

The adopted `pvm_invocations.tex` Omega_Gemini row uses a first page derived from
zone-rounded RO length and a past page derived from zone-rounded stack length.
Retain copied nominal bounds beside the exact initialized machine, after the
standard initializer has validated the bootstrap's own complete envelope. Count
current writable pages in that interval and set h=first+count. A request <=h or
above the ceiling returns h at base cost 275. Otherwise return the requested page
and charge 275+121*(requested-h). Full-width requests are compared before narrowing
or multiplication; fixed page-domain bounds prove all gas arithmetic fits uint64.

Affordability precedes register/memory changes. OOG drains credit to zero with no
gas deficit, preserves r7 and memory, and retains the causing ecalli PC. A funded
call maps [first, returned endpoint) writable, preserving bytes and outside pages;
new pages are zero-filled. The existing immutable memory owner's complete
materialized-page limit is the independent local allocation policy. Exhaustion
returns LimitExceeded, never guest OOG. Host-call, step and gas-analysis budgets
remain independent. No caller-supplied replacement geometry or effects certificate.

Heap is CPU memory: panic/checkpoint account selection does not rewind the
completed machine's heap. Account effects and publication contracts are unchanged.
M1 framing is complete; full serialization remains open.

## Completion tests

Execute real queries, one/two-page growth, repeat growth, exact/spare/zero/short
gas, exact/exhausted page policies, full-width requests and stack-rounding limits.
Compare literal gas/returned ordinals, zero-filled new memory, preserved RW/RO/
stack/input bytes and immutable original CPUs. Check copied/default geometry,
detached owners, panic/checkpoint selection, batch publication and fresh
1,000-cycle ARC cleanup. Retain strict default/failed extraction and privacy
guards, affected consumers and independent pinned-source/arithmetic checks.

## Other upstream dispositions

The same review confirms #533 fixes C's hash-return provision projection to X,
commit/source as above. That separate AmbiguousProvisions adoption remains next
bounded work; this layer does not change its runtime gate. [GP #539](https://github.com/gavofyork/graypaper/pull/539),
merged 2026-08-10 at `f01d06d5ca6aa10a4a123e185f57f18df908eb12`, changes the
account-integration rule and introduces junior services. The pinned vector
changelog deliberately keeps the old recreation rule, so this is not compatible
evidence for changing the preceding prior-ID layer. No blanket tip adoption.


## Local verification (2026-10-19)

Nine native suites passed: pvm_accumulation_heap, pvm_accumulation_machine,
pvm_accumulation_dispatch, pvm_heap_memory, pvm_initialization,
pvm_accumulation_integration, accumulation_batch, accumulation_complete_batch
and pvm_accumulation_outcome. Every suite retained fresh stable 1,000-cycle ARC
evidence; the new heap workload used 53,088 occupied bytes before and after.
Ten strict machine/dispatch extraction guards (including default heap-bound
extraction), four privacy rejections, four downstream semantic checks and the
new getter's attached-doc check passed. Six independent heap/source/adoption
Python checks and two outcome source checks passed; the separate provision
projection adoption test remains intentionally pending. Inventory, affected pinned
formatting and whitespace checks passed. These are local macOS checks; exact-head
CI is separate. Vendor gitlinks, source pins, native bridges and toolchains are
unchanged.

Evidence lives under `build/pvm-grow-heap/` (reviewed upstream sources, exact
hashes, guard results, docs and semantic logs), with
`build/pvm-grow-heap-native.log`, `build/pvm-grow-heap-regressions.log`,
`build/pvm-grow-heap-final.log` and matching Python/inventory/format logs.
Existing prepared native libraries and runner paths were reused. Initial fixture
compilation needed explicit fetch/operand-limit imports. The first outcome rerun
exposed its historical unsupported-heap assumption; that case now uses a genuine
allocation refusal and separately verifies normalizable zero-deficit heap OOG.
Seven unchanged passing consumer suites were retained when only the final heap
and outcome tests changed. No full corpus, dependency setup or pin upgrade ran.

Next bounded work: scoped adoption of #533's regular hash-return X provision
projection, with divergent checkpoint/regular provisions and complete publication
witnesses. M1 framing remains complete; full serialization and complete accpar/
whole-block publication remain open.
