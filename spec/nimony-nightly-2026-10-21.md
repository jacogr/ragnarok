# Nimony October 21/22 nightly upgrade audit

Current candidate: October 22 `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`. **Held** pending a
published nightly containing the sequence-element copy-hook propagation fix `d53097d392`
([#2737](https://github.com/nim-lang/nimony/issues/2737)). The chronological qualification below
preserves the evidence and scope of the original candidate and master synchronizations.

## Initial October 21 scope and pins

Upgrade the official compiler from `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`
(October 15) to `29b96c31be1647665e5c57f2788e1c8cfeeddc9c` (October 21), both 0.6.3.
This was the newest published nightly found during the initial audit; it was not upstream master.
Review the [44 included commits](https://github.com/nim-lang/nimony/compare/5b51edfedb4d0dbd9028d9e57ac61d69dffe9410...29b96c31be1647665e5c57f2788e1c8cfeeddc9c)
and the [official release](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-29b96c31b).

Both supported compiler assets retain explicit SHA-256 pins and NIGHTLY.txt identity checks.
The Linux archive was downloaded and verified; macOS ARM64 runs the installed compiler.
The formatter stays at Nim 2.2.12. No production dependency, protocol byte or compiler source is patched.
The matching browser source dependency changes to `ec471df7e83d6938bd482b4f4dd5c8d2ef210c1f`,
read from the new compiler's `src/nativenif.commit`; both source archives are checksum pinned.
Neither supported nightly contains `bin/jorogumo`, so its existing pristine-source bootstrap remains.

## Included fixes and project decisions

| Upstream change | Project adjustment or checked boundary |
| --- | --- |
| [#2708](https://github.com/nim-lang/nimony/pull/2708), interface checksums include generic bodies and private declarations | Remove whole-tree source epochs from NativeChecks and Hastur. The original private-helper arity reproducer succeeds in one unchanged cache (`7`, `12`, `12`); the old compiler still fails its second build. Preserve flags, ABI/header hashing, compiler isolation, worker locks and source provenance. |
| [#2715](https://github.com/nim-lang/nimony/pull/2715), strict stateless UTF-8 validation | Replace the duplicated RPC scalar decoder with `std/unicode.validateUtf8` (now in shared `src/lib/utf8.nim`). Independent literal tests retain ASCII/NUL, scalar limits, overlong, surrogate, out-of-range, malformed-continuation and truncated-input coverage, including errors between valid runs. |
| [#2719](https://github.com/nim-lang/nimony/pull/2719), reject ref-reached iteration | Traverse immutable owner fields by index, copying fixed values or retaining immutable owners where needed. Also avoid a sequence iterator across mutation of its draft's work counter. No `uncheckedBorrow`, disabled checks or dependency patches. |
| [#2688](https://github.com/nim-lang/nimony/pull/2688), [#2697](https://github.com/nim-lang/nimony/pull/2697), [#2711](https://github.com/nim-lang/nimony/pull/2711), forwarded borrows, results and conditional reassignment | The actual block-download callback probe still reports `cannot prove expression is not nil` without explicit non-null receiver/session bindings. Keep those bindings and short borrow lifetimes. |
| [#2673](https://github.com/nim-lang/nimony/pull/2673), integer formatting and allocation-free NumBuffer/addInt | Existing `$` calls inherit the new implementation. The actual `SomeInteger` JSON-style generic body still fails overload checking on the new pin, so concrete integer overloads remain. |
| [#2707](https://github.com/nim-lang/nimony/pull/2707), contract body field names; [#2652](https://github.com/nim-lang/nimony/pull/2652), static parameters | Keep public result guards and checked bounds. Existing static schema parameters remain valid; no protocol schema or proof is weakened. |
| [#2709](https://github.com/nim-lang/nimony/pull/2709), OS additions and directory/error fixes | The Darwin creation-call `open` binding still has a fixed third mode argument, so the maintained variadic-header binding remains. The newly merged management sampler uses public `DirStream` open/read/close operations instead of the removed libc directory exports; storage semantics remain unchanged. |
| [#2682](https://github.com/nim-lang/nimony/pull/2682), [#2685](https://github.com/nim-lang/nimony/pull/2685), inlining/name fixes; [#2694](https://github.com/nim-lang/nimony/pull/2694), alias copy propagation; cursor-field construction | Inherited compiler fixes; retain ownership/runtime and lowering regression checks. Custom moved-from discriminators remain explicit resource invariants, not removed on the assumption of a related fix. |
| CTFE enum/set/range constants, generic varargs contracts and assembler field access | Inherited fixes. Nonzero enum-index defaults and generic variant constructors are separate recorded limitations; do not remove their alternatives based only on these commit titles. |
| Streams, buffered parsing/deadlines, HTTP headers, terminal/colors, string layout and native math | Newly available APIs reviewed; no matching production workaround requires replacing maintained QUIC, JSON-number policy or bounded network scheduling. |

The scalar-only copy-hook fix `1112e45997` ([#2729](https://github.com/nim-lang/nimony/issues/2729))
was after the initial October 21 release. The October 22 qualification below verifies its direct-copy
behavior; explicit ownership contracts and destructors enforcing real resource invariants remain.

## Verification

Local verification passed all 313 production module checks, all 1,976 compiler guards, 721 Python
tests (three skipped), and the real-browser UI check. Eighteen affected native suites passed, including RPC, block codecs, PVM memory/inner-machine
lifecycle, trie/proof transport, accumulation, storage retention and checkpoint transfer. The old/new same-cache control and both actual
NativeChecks profile controls establish the bounded cache fix. Raw local compiler-range, archive and compatibility-probe evidence
is under ignored `build/ci/` and `build/nimony-upgrade-probes/`. Local results apply to macOS ARM64;
checksum verification of the Linux asset is not a Linux runtime pass. Historical M1 migration evidence
remains historical evidence, not a new claim of complete JAM client parity.

## Qualification after merged storage resource work

Merge master `e0c3a430` into this upgrade without rewriting the published compiler commit.
All 81 master-changed files outside the original upgrade scope remain byte-identical to master;
the shared infrastructure guide retains both the cache-policy update and the merged package-setup
bounds. CI wiring, storage resource/report contracts, workload axes and provenance checks are preserved.
No additional storage compatibility edits were needed.

On the merged tree, all 112 storage Python safeguards and 86 Make/CI/cache integration safeguards
passed. All 11 new or affected native suites passed: allocator observations, deployment domain and
fixtures, seven lifetime controls, and sustained growth fixtures. The five ordinary-growth,
allocator-instrumented, deployment, lifetime and fresh-reopen benchmark profiles built with the
new compiler. Sixteen bounded native invocations passed their maintained independent parsers:
seven lifetime scenarios, three deployment backends, one allocator trajectory, one ordinary growth
trajectory, and separate producer/strict-consumer pairs for journal and managed reopen. Reopen
controls also preserved every stored byte. These are compatibility controls, not a rerun of complete
resource panels or new speed/resource measurements. Earlier production-module/guard verification
covers unchanged runtime sources and compiler pins; the new storage inputs have this additional
qualification. Local raw evidence is under `build/ci/nimony-storage-*`.

The subsequent memory-ceiling tranche was reconciled through master `ebd27f7b` with the same
held compiler pin. All 46 newly changed master files are byte-identical to master; no runtime,
build-profile or compiler-pin adjustment was needed. All 148 storage Python safeguards and
46 Make/CI safeguards passed. `make bench-storage-memory-ceilings` and its setup-free summary
passed: eight unrestricted native consumers validated complete maps and retained selected bytes;
three Darwin probes and all twelve capped attempts remained explicitly unavailable. This supplies
no Linux limit-enforcement evidence. The candidate remains held pending the next published nightly.


## Qualification after merged RPC and state review work

Reconcile master `42112504` while retaining the held compiler pin. Keep master's shared JSON
reader and UTF-8 module extraction, with the fixed stdlib validator in the shared UTF-8 module
so both public RPC and local management HTTP use it. All 368 newly changed upstream files outside
the upgrade's intended scope remain byte-identical to master.

The new management resource sampler used removed `DIR`/`opendir`/`readdir`/`closedir` exports.
Use the public `DirStream` API and an explicit private active flag. Preserve sixteen entries per
turn, the 4,096-entry admission limit, separate EOF/error outcomes, flat-layout accounting and
idempotent close/abandoned-scan cleanup. The immutable owner destructor closes a local copy of the
public stream value; only the retiring owner exercises that cleanup authority. Keep the
sampler's copy/dup rejections and the enclosing server's ownership contract.

On this merged tree, all 341 production modules, 2,113 compiler guards and 52 focused independent
state-oracle/Make/CI Python tests passed. All 35 selected native suites passed, covering the new
state review/checkpoint/deposit/footprint/supervision work, management HTTP/resources/services,
application options, RPC state proofs and public RPC UTF-8/JSON regressions. The resource suite
also passed after adding a forced mid-scan read-error witness, retaining its 1,000 abandoned-scan
ARC baseline check. The complete checked ARC/Clang/LTO native peer build passed. Inventory,
pinned formatting of changed Nim files and `git diff --check` passed. Evidence is under ignored
`build/ci/nimony-rpc-sync-*`. These are macOS ARM64 results; Linux runtime qualification remains
for CI. No storage semantics or compiler pins changed, and the candidate remains held.


## Qualification after storage preflight, pressure and growth-CI work

Merge master `56e8686f` normally, retaining both held compiler pins and the earlier directory
stream adaptation. Preserve the merged Linux RSS explicit-result fix and proof-protocol token
correction. Resolve only the compatibility-guide overlap: retain the verified cache-fix guidance
and the new Linux RSS lowering record. No additional compiler compatibility fix was necessary.
All 42 newly changed upstream files outside four reviewed upgrade overlaps remain byte-identical
to master. The two benchmark manifest overlaps retain removal of the retired source-epoch helper;
all comparison/growth source inputs exist. Preserve the separate Perf Storage Growth job and the
new pressure/abort evidence collectors without changing their workloads or success criteria.

All 341 production modules and 242 focused storage/native-profile/Make/CI/cache Python tests
passed. Four Linux x86-64 target semantic checks passed: management resources, both storage file
readers and the RPC proof-protocol suite. These are semantic checks, not Linux linking/runtime
results. All 14 selected native suites passed on macOS ARM64: managed/journal tiny-heap preflight,
post-stat growth, read bounds, short/interrupted reads, file admission, journal/managed owners,
managed publication IO, disk recovery, repair interruptions, management resources and RPC proof
protocol. The maintained memory-ceiling panel and its setup-free summary passed, including eight
unrestricted native controls and byte preservation; three probes and twelve capped attempts
remain unavailable on Darwin. Linux resident-pressure and debugger call-site measurements were
not rerun on this host. Inventory, pinned formatting of all nine new/changed Nim inputs and diff
checks passed. Raw local evidence is under `build/ci/nimony-storage-next-*`. The candidate remains
held pending the next published nightly.


## Qualification after merged current-download PVM work

Merge master `edc4f528` normally (qualification merge `dd5efba6`), preserving all 131 changed
upstream files byte-for-byte and both held compiler pins. The tranche adds signed current input,
worker preparation, retained publication handoffs, Services memory/disk adoption, authenticated
native downloads, explicit complete policies and the current command, with ancestry, durable
partial-progress and RPC/lease witnesses. No additional compiler compatibility edits were needed.

All 350 production modules, 2,139 compiler guards and 89 focused executable/Make/CI/native-profile/
verification-harness Python tests passed. All 16 new native PVM suites passed, plus six affected
options, startup, handoff and legacy ancestor/download command suites (22 native suites total).
All 31 declared runtime-refusal probes in the eight new families passed their independent exact
assertion diagnostics. The full checked ARC/Clang/LTO integration/offload peer build passed, as
did Linux x86-64 semantic checking of that production entry point with both defines enabled.

The existing registered `application_current_download` E2E workload also passed all six actual
executable cases, using its freshly compiled shipped profile and independent native TLS/map
witness: journal/managed adoption, replay/empty refusal after one adoption, timeout after one
adoption and legacy-policy rejection. Existing fixture hashes, request authority, strict durable
reopen, output/exit checks and joined responder cleanup remained required. These selected cases
are not a full E2E-plan run or Linux native linking/runtime qualification.

Inventory, pinned formatting of all 69 new/changed Nim inputs and diff checks passed. Local
results apply to macOS ARM64; raw evidence and preserved input identities are under ignored
`build/ci/nimony-pvm-sync-*`. The candidate remains held pending the next published nightly.


## Qualification after the final state tranche

Merge master `e7df0c60` normally (merge `f1ed6651`) and retain both held compiler pins. The
tranche adds complete-state qualification corpora, frozen account review preparation, current-bound
profiles/globals/checkpoints/reviews, retained supplied logical keys and bounded detached service
reconstruction. Preserve the recorded consumer/producer handoff gates; this sync adds no producer
delta API, adoption policy or full current-pin STF/parity claim.

The held compiler rejected the raw-key copy's iterator through `data.rows[row].keys[item]` in
`supplied_logical_inventory.nim`. Replace only that iterator with bounded indexed byte reads into
the same newly allocated detached output. Keep all existing source/index/byte-limit validation,
empty-key behavior, retained-owner lifetimes and bounds checks; use no unchecked borrow or new
allocation. All other 220 upstream-changed files remain byte-identical to master.

After the fix, all 360 production modules, 2,219 compiler guards and 214 focused state-oracle/
Make/CI/native-profile/verification-harness Python tests passed. All 19 merged state native suites
passed, including raw-key/output isolation, complete supplied reconstruction, independent complete
serialization/audit/review corpora, current provenance and checkpoints, substitutions and refusal
boundaries. All 63 declared runtime-refusal probes across ten new families passed their exact
assertion diagnostics. The full checked ARC/Clang/LTO integration/offload peer build passed.

Linux x86-64 semantic checks passed for current logical qualification and supplied-service
reconstruction. These are not Linux linking/runtime results. Inventory, pinned formatting of all
132 new/changed Nim inputs and diff checks passed. Local native evidence applies to macOS ARM64;
raw logs and preservation identities are under ignored `build/ci/nimony-state-sync-*`. The candidate
remains held pending the next published nightly.


## October 22 candidate and remaining hold

Advance the native and matching browser compiler pins to the official `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`
release, keeping the formatter at Nim 2.2.12 and the existing nativenif source pin unchanged.
Download and SHA-256-check both supported archives, verify their exact commit/date/platform
metadata, and verify the matching browser source archive. Neither release archive contains
jorogumo; the existing pristine-source bootstrap succeeds and remains necessary. No compiler,
stdlib, native dependency or protocol source is patched.

The [eight commits since the held candidate](https://github.com/nim-lang/nimony/compare/29b96c31be1647665e5c57f2788e1c8cfeeddc9c...8cb7a690ae48363eb3ce65564aafb921ca5d23f3)
include generic base-argument checking, direct copy-hook enforcement without a destructor, sink-array
element typing, checked array-to-sequence moves, nonzero-domain global initialization checks,
ref/ptr type-attached routine lookup and Android directory binding/documentation updates.
No matching production workaround for the inheritance, initialization or lookup changes needs
removal. Keep indexed ref-reached traversal, moved-from resource disarming and real destructors.

Two new source-owned compiler guards freeze the ownership improvements. A scalar-only owner with
error copy/dup hooks compiles on the old pin and is rejected by the new binary at the exact unavailable
dup hook. Array conversion of the actual BlockDownloadStream owner also compiles on the old pin
with the complete native header/library profile, but is rejected at the intended hook by the new
pin. A preliminary old comparison lacking transport headers was only a build-setup failure and is
not ownership evidence. The controller destructor enforces actual callback retirement and is kept.

The actual SomeInteger-to-dollar generic and inferred nullable callback bindings still fail their
previous probes, so concrete integer overloads and explicit non-null bindings remain. Related
upstream work exists ([refined concept overloads #2743](https://github.com/nim-lang/nimony/pull/2743),
[nil-path/mutation analysis #2110](https://github.com/nim-lang/nimony/pull/2110)); neither establishes
that these exact cases are tracked or fixed on master. No duplicate upstream report was filed.

**The candidate remains held.** The new release still accepts sequence copies whose element
forbids copying, even with both copy and dup hooks declared as errors. Both independent local
variants compile and print `70` (original value 7, copied value 0). Minimal copy/dup variant:

```nim
import std/syncio
type Foo = object
  value: int
proc `=copy`(target: var Foo, source: Foo) {.error.}
proc `=dup`(source: Foo): Foo {.error.}
var original: seq[Foo] = @[]
original.add Foo(value: 7)
var duplicate = original
echo original[0].value, duplicate[0].value
```

Upstream already fixed this after the release in
[`d53097d392`](https://github.com/nim-lang/nimony/commit/d53097d39240a33c8c63db6423b62a1c27b8adc8)
for [#2737](https://github.com/nim-lang/nimony/issues/2737), propagating unavailable hooks through
generic instances and derived hooks. Wait for a published archive containing that fix, then turn
this reproducer into a required rejection guard and validate the actual binary. Do not infer full
container ownership safety from the two direct/array rejection checks.

This candidate passed all 360 production module checks, all 2,221 compiler guards and the full
Python suite (856 tests, three skipped). The complete checked ARC/Clang/LTO integration/offload
peer build and real-browser UI/production RPC check passed, using the rebuilt matching browser
compiler. Both actual NativeChecks private/shared cache controls produced `7 -> 12 -> 12` in an
unchanged directory after the helper-arity edit. Inventory, pinned formatting of the new guards and
diff checks passed. Additional broad native-suite qualification was deferred after the confirmed
ownership blocker; earlier selected-suite passes belong to the prior compiler and are not claimed
for this candidate. Local runtime results apply to macOS ARM64; Linux archive verification does
not establish Linux runtime behavior. Raw evidence is under ignored `build/ci/nimony-2026-10-22-*`.


## Storage read/transfer synchronization on the October 22 pin

Merge master `d5064139` normally (merge `928105e0`), retaining the October 22 compiler/browser
pins and the sequence-element copy-hook hold. This tranche transfers admitted read/record/frame/
snapshot payloads instead of copying them, fills bounded read buffers directly, handles actual
post-stat shrinkage and retires detached snapshot input before journal replay. Preserve all
consuming-result invalidation, causal guards, strict selected-byte admission and immutable owners.
The earlier indexed traversal adaptations in `node_repository.nim` remain in place; no additional
production compatibility changes were necessary.

Native codec qualification exposed a separate stdlib sequence-slice failure on this pin:

```nim
import std/assertions
let bytes = @[1'u8, 2, 3]
let prefix = bytes[0..<2]
assert prefix == @[1'u8, 2]
```

`nimony check --mm:arc --cc:clang -d:release --boundchecks:on` rejects the stdlib slice body at
`system.nim(640, 12)` with `cannot mutate rawData(result)[i] through a ref/ptr in a
.noSideEffect context` (with backticks around `.noSideEffect` in the raw diagnostic). Keep the
minimal source/output under `build/ci/nimony-storage-transfer-slice.*` for the requested next-nightly
recheck and possible report draft. In three codec tests, use bounded borrowed prefix views in
place of allocating slices. Every truncation index, including the empty prefix, retains the
original decode/refusal assertions. The context-codec assertion names the result explicitly to
keep formatter line wrapping unambiguous. These adaptations change no decoder or storage policy.

All 25 upstream-changed files outside the reviewed node traversal and two changed codec tests
remain byte-identical to master. The third adapted codec test predates this incoming tranche.
All 360 production modules and 246 focused storage/comparison/native-profile/Make/CI Python tests
passed. All 24 selected storage native suites passed: the documented 19 transfer/read consumers
plus interrupted reads, file read bounds, journal owner, disk recovery and repair interruptions.
This includes the four consumed-result misuse children and successful process control. Seven
Linux x86-64 semantic checks passed for the changed storage modules. The maintained strict
fresh-reopen panel passed all four cases, including complete maps/roots, retained lifetimes and
unchanged selected files; its report was independently revalidated. The complete checked
ARC/Clang/LTO integration/offload peer build passed. Inventory, pinned formatting of all 15
merged/adapted Nim inputs and diff checks passed.

This is compiler compatibility and strict-reopen qualification, not a new baseline/candidate
performance comparison or Linux pressure rerun. The published storage measurements retain their
original compiler/host/workload scopes. Earlier broad compiler guards remain separately labelled
above; this increment ran the affected native result guards. Local runtime evidence applies to
macOS ARM64; Linux semantic checks do not establish Linux linking/runtime success. Raw local
evidence is under ignored `build/ci/nimony-storage-transfer-*`. The PR remains held for the
published sequence-copy fix, with remaining workaround probes to recheck after the next nightly.


## Additional PVM synchronization on the October 22 pin

Merge master `e76fc43483bdbc6d83d79dc0bb2ab2510613aa30` normally (merge `3856a8b9`),
covering 30 additional PVM merges. All 100 incoming files remain byte-identical to master.
This includes the production current-download loop's managed-maintenance wait and the new
consecutive-adoption, preimage-delivery, ancestry and validator-rotation qualification. No new
compiler compatibility edits were necessary. Keep compiler/browser pin `8cb7a690a`, all earlier
workaround adaptations and the sequence-element copy-hook hold for #2737 unchanged.

All 360 production modules, 12 affected Python executable-harness tests and all 19 incoming
native PVM suites passed. The shipped integration/offload binary built with checked
ARC/Clang/LTO. The four source-owned executable workloads passed all 24 cases: 11 consecutive
current-download cases, four nonempty-preimage cases, four original-ancestry acquisition cases
and five validator-rotation cases. Their existing independent TLS/map witnesses, fixture hashes,
request counts, durable-history checks, restart and refusal verdicts were retained. Inventory,
pinned formatting of all 31 incoming Nim files and the Linux x86-64 semantic check of
`current_block_download_loop.nim` passed. Diff checks passed.

These are selected compatibility/runtime results on macOS ARM64. No full E2E plan, new storage
performance measurement or Linux runtime run is claimed. Earlier broad Python/compiler-guard
results retain their explicitly recorded source scope. Raw evidence is under ignored
`build/ci/nimony-pvm-sequence-*`, including exact incoming-tree preservation and per-workload
JSON reports. The next bounded compiler task remains qualification of a published nightly
containing #2737, followed by rechecking the remaining workaround probes and drafting any
still-needed minimal reports for maintainer submission.


## Current logical state synchronization on the October 22 pin

Merge master `3aa4c368cdc8cf85d93ac7194fac9a1456cecbca` normally (merge `52af3a3e`),
covering 30 additional state merges. Preserve bounded configured selected-parent admission,
completed-origin identities, immutable request-key companions, frozen service/full logical
refresh and source-bound review/proof composition. All 12 incoming production modules remain
byte-identical to master; no production compatibility change was needed. Compiler/browser pin
`8cb7a690a` and the #2737 sequence-element copy-hook hold remain unchanged.

The current logical-proof suite instantiates the same confirmed stdlib sequence-slice failure
recorded above, through `wire[0..3]`. After the original minimum-length assertion, compare each
of the four RPV1 magic bytes by checked index. Keep every expected byte, proof/root assertion,
projection, missing-witness refusal and 1,000-cycle allocation check. This is the only incoming
file adapted: the other 241 of 242 files remain byte-identical to master. The first seven native
suites passed before this test-only correction and were not repeated; all remaining suites were
then qualified, including the corrected proof suite. Retain the existing standalone slice
reproducer for next-nightly rechecking; no compiler/stdlib patch or weaker validation is used.

All 368 production modules, 132 focused state Python tests, all 29 incoming native suites and
all 71 incoming source-owned privacy/nominal compiler rejection fixtures passed. The 59 strict
runtime refusal probes across 11 families passed with successful builds and exact assertion
diagnostics; the native suites retain their genuine successful accessor controls. The complete
checked ARC/Clang/LTO integration/offload peer build passed. All 12 changed production modules
passed Linux x86-64 semantic checks. Inventory, pinned formatting of 142 incoming Nim files
(including the final adapted proof test) and diff checks passed.

Results apply to local macOS ARM64 execution and the stated Linux semantic checks. This sync
makes no new full E2E, Linux runtime, performance, complete current-schema/STF or JAM parity
claim. The previous 24-case PVM executable results retain their earlier source scope. Raw
evidence, exact incoming-tree preservation, per-suite logs and strict refusal reports are under
ignored `build/ci/nimony-state-current-*`. Next remains a published nightly containing #2737,
then rechecking the remaining workaround probes and drafting still-needed minimal reports for
maintainer submission.


## Bounded storage admission synchronization on the October 22 pin

Merge master `90dc41d5` normally (merge `c56899fa`), covering 30 storage merges. Preserve
structural record preflight, provisional per-record delivery, private staged image/publication
owners, complete graph authority, atomic refusal and independent retained views. All 47 incoming
files outside the prior indexed traversal adaptation in `node_repository.nim` remain byte-identical
to master. The new record-codec implementation is unchanged. Compiler/browser pin `8cb7a690a`
and the sequence-element copy-hook hold for #2737 remain unchanged.

The broader image-repository consumer test, which predates this incoming tranche, hits the same
confirmed stdlib sequence-slice failure through its deliberately incomplete record prefix. Copy
that prefix by checked index into an independently owned sequence before the original refusal
assertion. This preserves the same omitted record and all graph/ownership assertions without a
compiler/stdlib patch. It is the sole new compatibility adaptation in this synchronization.
The first 15 selected native suites passed before that correction and were reused unchanged;
the remaining nine, including the corrected image suite, then passed.

All 368 production modules and 24 selected native storage suites passed: the ten incoming
admission/delivery/failure/ownership suites plus 14 affected record, repository, image, publication,
file/managed/context, replay and repair consumers. All five incoming compiler privacy fixtures
passed their exact module-member rejection predicates. The 250 affected Python tests passed,
including paired-reopen artifact/evidence validation, privacy predicates, storage references,
native profiles and Make/CI safeguards. The first Python launcher named two nonexistent modules;
its 203 actual tests passed, and the corrected Make/CI selection passed all 47 tests. Preserve
both logs and the aggregate receipt instead of presenting the initial launcher as successful.

The strict fresh-reopen panel passed all four cases; independent read-only report validation
passed. The complete checked ARC/Clang/LTO integration/offload peer build passed. Both changed
production modules passed Linux x86-64 semantic checks. Inventory, pinned formatting of the 18
incoming Nim files and the final adapted image test, and diff checks passed.

Results apply to local macOS ARM64 runtime and the stated Linux semantic checks. No new matched
baseline/candidate memory measurement, Linux resident-pressure run or full E2E result is claimed.
The merged storage measurements retain their original compiler, source and host scopes; optional
paired collection was not rerun against unlike compiler captures. Raw evidence is under ignored
`build/ci/nimony-storage-admission-*`. The next compiler task remains a published nightly with
#2737 followed by the retained workaround probes and any still-needed minimal report drafts.


## Host logical state and ThinLTO synchronization on the October 22 pin

Merge master `f431127730f702f455fc535474bb5d94e78f30d2` normally (merge `79b16cba`),
covering 20 state, CI and workflow merges. Preserve collected logical qualification, configured
seeds, managed retained proofs/checkpoints/review, frozen supplied/review inputs, retry plans,
complete service-proof namespaces, bounded declaration exports and authenticated detached
checkpoint imports. All 17 incoming production modules remain byte-identical to master.
Compiler/browser pin `8cb7a690a` and the #2737 sequence-element copy-hook hold remain unchanged.

Keep master’s twelve unit shards, family-partitioned E2E plan, shared current-sequence responder
and ThinLTO flags. The earlier cache-epoch removal remains in force in the merged native helpers,
harness controls and infrastructure documentation; no source epoch is reintroduced. The only
new source edits are pinned-format import wrapping in eight incoming supplied-mutation tests.
Whitespace-token comparison against master confirms no semantic change, and all eight formatted
files passed focused semantic checks before their native runs. Of 302 incoming files, 290 remain
byte-identical to master; the other four differences are the pre-existing upgrade adaptations in
`docs/testing/infrastructure.md`, `tests/test_native_units_harness.py`, `tools/native_checks.py`
and `tools/native_tests.py`.

All 380 production modules, 162 affected Python harness tests, all 37 incoming native suites and
all 86 incoming compiler rejection fixtures passed. All 101 strict runtime refusal probes across
ten new families passed with actual successful ThinLTO builds and their exact assertion
predicates; the native suites retain successful contract controls. The four source-owned executable
current workloads passed all 24 cases through the newly shared responder setup. Both the actual
integration/offload executable and the canonical Make production build passed checked
ARC/Clang/ThinLTO. All 17 changed production modules passed Linux x86-64 semantic checks with
ThinLTO flags. Inventory, pinned formatting of all 157 incoming Nim inputs and diff checks passed.

This is compatibility and selected runtime qualification on macOS ARM64, plus Linux semantic
checking. It makes no full E2E, Linux runtime, CI execution-time, performance or complete JAM/STF
claim. Earlier measurements and broad checks retain their recorded source/compiler scopes.
Raw evidence is under ignored `build/ci/nimony-state-host-*`, with preservation, whitespace-only
formatting, per-suite, exact-refusal and executable reports. The next compiler task remains a
published nightly containing #2737, followed by the retained workaround probes and any still-needed
minimal report drafts for maintainer submission.
