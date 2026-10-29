# Nimony October 21–23 nightly upgrade audit

Current qualified candidate: October 23 `4724f66c2e01b17810c844f26575b2317995fda2`.
The verified archive fixes sequence-element copy-hook propagation (#2737), so the ownership hold
is lifted. The three remaining exercised limitations retain their adapters and standalone
[report drafts](nimony-reports-2026-10-23/integer-generic.md). Historical holds and results below
retain their original date/compiler/source scope; the final section records this qualification.

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
`src/state/supplied/logical_inventory.nim`. Replace only that iterator with bounded indexed byte reads into
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
The earlier indexed traversal adaptations in `src/storage/node/repository.nim` remain in place; no additional
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
`src/quic/current/block/download/loop.nim` passed. Diff checks passed.

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
files outside the prior indexed traversal adaptation in `src/storage/node/repository.nim` remain byte-identical
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


## State formatting and CI archive synchronization

Merge master `06cf5b76` normally (merge `bfab6d43`). The state styling PR supplies exactly the
eight import-wrap formatting changes already present here; the merge introduces no native source
or native test changes. All production source, unit/native/support tests, compiler/browser pins
and native build/check/unit helpers are byte-identical to checked head `5c9b8e2b`. Reuse that
head's native, compiler-guard, runtime and executable evidence with this explicit equality scope.

The accompanying CI grouping/archive PR is preserved. All 55 affected CI, binary-package and
Make harness tests passed. `make package-binary` rebuilt the checked ARC/Clang/ThinLTO peer and
created a macOS ARM64 relocatable archive. Its independently unpacked copy passed dependency/
runpath validation and `--version`, `--help`, `--selftest` and `--integration-selftest` without
loader environment overrides. Inventory and diff checks passed. This is local macOS packaging
qualification, not Linux packaging/runtime execution or an uploaded release. No remote CI run
was requested. Raw evidence is under ignored `build/ci/nimony-state-style-*`; the package's own
relocation/smoke log is `build/ci/binary-package.log`. Nightly pin and #2737 hold remain unchanged.


## Logical PVM downloads, invocation caches and decoder fuzzing

Merge master `9eb56ba732605831ff6b87a343d62cc6b61330c9` normally (merge `91d3a131`),
covering eight PVM merges. Preserve explicit logical startup policy/source files, authenticated
session retention and admission before enqueue, plus private invocation cursors and bounded decoded
instruction caches. The new interpreter implementation remains byte-identical to master. Keep
compiler/browser pin `8cb7a690a` and the sequence-element copy-hook hold for #2737 unchanged.

The new startup declaration owner hits the known retained-ref iteration restriction in two loops.
Use indexed traversal for both, preserving order, row values, independent quotas and typed refusals.
This is the only new production compatibility adaptation. It resolves four affected module
failures; all modules and the nine exact compiler rejections were then checked successfully.
Of 72 incoming files, 68 remain byte-identical to master. Differences are this startup adaptation,
the fuzz tool/test below and the earlier native cache-epoch removal merged with the new explicit
fuzzer link flags/compiler environment arguments.

The new fuzz tool imported the retired `native_source_identity` helper. Replace that dependency
with existing project-input discovery and fresh per-file hashes for evidence. Keep these hashes
separate from the stable tool/runtime/flag build profile, relying on the pinned compiler's normal
source invalidation rather than restoring whole-source cache epochs. A focused test verifies that
source mutations update the provenance map. Frozen seed checksums, coverage completion, fatal
assertions, fresh artifacts, independent replay, subprocess retirement and sanitizer limits remain
unchanged. No compiler/runtime patch or relaxed fuzz property is introduced.

All 383 production modules, 103 affected Python tooling/cache/Make/CI tests, nine incoming compiler
rejections and 22 selected native suites passed. The native selection covers all 11 changed suites,
affected step/memory/host/inner/computed/assured/continuation execution, command/loop consumers,
and separate app-options/current-policy controls. It includes actual logical startup across memory,
journal and managed layouts, repeated children, strict restart, identity/permission refusals and
retained-owner checks. All ten changed production modules passed Linux x86-64 semantic checks.
Pinned formatting of 36 incoming Nim inputs, inventory and diff checks passed.

The maintained checked ARC/Clang address/undefined/coverage fuzz target completed 10,000 inputs,
with 246 coverage counters and 461 features. Its assertion control failed as required, created a
fresh exact artifact and passed independent ordinary replay; frozen seeds also replayed correctly.
Use the existing sanitizer scope: default Nimony allocation is preserved, so fine-grained Nim heap
chunk/leak coverage is not claimed. The result receipt is copied under this increment's evidence.
All 24 selected actual current-download executable cases and the complete canonical checked
ARC/Clang/ThinLTO integration/offload build passed.

Runtime results apply to macOS ARM64; Linux checks are semantic only. No new PVM timing comparison,
full E2E, Linux runtime or exhaustive fuzz-coverage claim is made. Raw evidence is under ignored
`build/ci/nimony-pvm-logical-*`; the original campaign and artifact/replay logs remain under
`build/tests/pvm-program-fuzz/`. Next remains a published nightly containing #2737, rechecking
retained workaround probes, and drafting still-needed minimal reports for maintainer submission.


## Storage layout, shared-path writes and final-buffer encoding

Merge master `ca3433f672fff3b6e342279bacfc76c545317cfb` normally (merge `6d12114a`),
covering 14 storage merges. Preserve private tagged leaf/branch alternatives, compact selection
indexes, branch aggregates, sorted bulk trie construction, shared-path batch writes, retained-root
inventory, direct final-buffer collection/snapshot/journal encoding, bitmap union freezing, stale
compaction refusal, exact owning exports and bounded full-address duplicate preflight.
Compiler/browser pin `8cb7a690a` and the #2737 sequence-element copy-hook hold remain unchanged.

Resolve two merge overlaps by retaining master’s exact indexed output writes/counts and tagged
record reconstruction while preserving checked indexed payload reads. Two additional loops in the
new selection encoder hit the known retained-ref iteration restriction; use indexed selection and
payload reads without changing order, quota admission, byte offsets or one-buffer ownership.
All 58 other incoming files remain byte-identical to master. No branch/leaf field, record hash,
complete physical edge, graph authority, format or publication rule is weakened. The original
module/consumer failures named those two encoder loops; affected checks passed after adaptation.

All 383 production modules, 256 affected Python tests and 37 selected native storage suites passed.
The selection covers all 13 changed suites plus 24 admission, codec, ownership, repository,
publication, file/managed/context, replay and repair consumers. The first trie/batch suites were
reused unchanged across the encoder-only adjustment. All 21 strict runtime misuse probes in the
two changed families passed with successful builds and exact assertion diagnostics. The strict
fresh-reopen panel passed all four cases and its report passed independent validation. All 24
selected actual current-download executable cases and the canonical checked ARC/Clang/ThinLTO
integration/offload build passed. All six changed production modules passed Linux x86-64 semantic
checks. Pinned formatting of 23 incoming Nim files, inventory and diff checks passed.

This is local macOS ARM64 compatibility/runtime qualification and Linux semantic checking.
The retained-layout/component/footprint tests preserve their exact map/lifetime/release assertions;
this sync does not establish a new matched baseline/candidate timing, retained-memory or Linux
resident-pressure comparison. Merged performance evidence keeps its original compiler/source/host
scope. Raw evidence is under ignored `build/ci/nimony-storage-layout-*`. The nightly availability
check follows this completed synchronization; pins and hold change only after a candidate is
actually selected and qualified.


## Automatic PR smoke synchronization

Merge master `b589f43d` normally (merge `87e0d4f2`). Preserve automatic lightweight Smoke on
PR open/reopen/synchronize, opt-in heavy checks and the source-only compiler setup. The new
module audit compiles all discovered production modules in one import graph and the real
integration/offload main separately, using fresh private caches for each audit. It exposes an
unoptimized checked smoke profile and retains the checked release/ThinLTO semantic profile.

All 70 affected Make/CI/inventory/profile Python safeguards passed. `make check-smoke` passed
repository-wide pinned formatting (4,229 Nim inputs plus the Rust crate) and all 383 production
modules plus the production main. The refactored `make check-modules` independently passed both
compilations for the same complete inventory under checked-release flags. Native source/tests,
compiler/browser pins and native build/check/unit helpers are byte-identical to checked head
`5a56ae8b`; reuse its runtime evidence rather than claiming fresh native executions. No source
compatibility change was required. Inventory and diff checks passed.

Raw evidence and copied audit receipts are under ignored `build/ci/nimony-smoke-*`. These are
local macOS semantic/tooling results. Publishing this merge automatically requests the new
remote Smoke check; no heavy CI labels are requested. Nightly pin and #2737 hold remain unchanged.


## Authenticated state import/export, code and bounded value reads

Merge master `b723f0c1aeaa3b807f062af69004f1fd76352ea5` normally (merge `b2ba535e`),
covering eight state merges. Preserve complete service-code availability, expected-root snapshot
reconstruction, managed whole-map and paged logical proofs, authenticated historical code,
identity-only startup export, atomic supplied logical qualification and bounded authenticated
value slices. Partial witnesses still confer no complete-map/root authority. Pins, formats,
worker lease boundaries, quotas, typed refusals and explicit adoption policy remain unchanged.

The new `findServiceCode` search hits the pinned compiler's known retained-ref iteration rule.
Read admitted fixed rows by checked index rather than copying an iterator row. This preserves
first-match order and NoService/default behavior without unchecked borrows. No other new
compatibility change was required. The initial smoke/native/privacy failures identified that loop;
all affected checks passed after adaptation. Of 128 incoming files, 124 remain byte-identical to
master. The other three overlaps retain the earlier indexed adaptations in current logical
startup, proof-view and trie-proof code.

Both unoptimized smoke and checked-release audits passed all 392 production modules plus the
real integration/offload main. Full pinned formatting passed, including 89 incoming Nim files.
All 132 state Python checks, 55 incoming privacy/nominal compiler rejections and 32 selected
native suites passed. The selection covers all ten incoming suites, existing service-proof and
proof-view consumers, ordinary/global Services proof consumers and logical startup. It retains
complete maps/roots, code/time selection, paged completeness refusal, mutable-input isolation,
backend failure/retry and source-owned allocation/lifetime checks.

All 100 strict runtime refusal probes across the ten changed families passed with successful
checked ARC/Clang/ThinLTO builds and exact assertion diagnostics, alongside genuine native
positive controls. All 24 selected actual current-download executable cases and the canonical
production build passed. All 14 changed production modules passed Linux x86-64 semantic checks.
Inventory, pinned formatting and diff checks passed. Debug/release receipts and incoming-tree
preservation are retained alongside the per-suite/refusal evidence under ignored
`build/ci/nimony-state-proof-*`.

Runtime qualification is local macOS ARM64; Linux checking is semantic only. No new full E2E,
performance, exhaustive proof correctness or complete JAM/STF claim is made. The October 22
compiler/browser pin and sequence-element copy-hook hold for #2737 remain unchanged. Publishing
this update also requests automatic Smoke; heavy CI remains opt-in. The next compiler increment
still waits for a selected published nightly and rechecks the documented workaround probes.


## October 23 archive: sequence ownership hold resolved

Upgrade the official native compiler and matching browser source from `8cb7a690a` to
`4724f66c2e01b17810c844f26575b2317995fda2` (0.6.3, October 23). Review the exact
[24-commit delta](https://github.com/nim-lang/nimony/compare/8cb7a690ae48363eb3ce65564aafb921ca5d23f3...4724f66c2e01b17810c844f26575b2317995fda2)
and [published archive](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-4724f66c2).
The Linux amd64 archive SHA-256 is `659f4a80f31a8fd88b21c546237f03e09411a33195083b4d668adbdc58a3ca47`;
macOS ARM64 is `0c361caae7351e7dd8a68d435179e8cf37744ad86b8c4df66b41a57eda71774b`.
Both downloaded archives passed checksum and NIGHTLY.txt commit/date/platform verification.
Matching compiler sources are pinned by SHA-256
`d7cd0eca9ea6424d14163e5aefe0db31aeb050ff23b0b815cd2f9a7f524e3408`.
Nimpretty 2.2.12 and nativenif `ec471df7e83d` remain unchanged; the matching pristine-source web
bootstrap passed. The host banner now correctly says `macosx`. No compiler/runtime source is patched.

| Included fix or addition | Observed project outcome |
| --- | --- |
| `d53097d392`, #2737 derived copy hooks | The actual archive rejects both sequence-of-copy-banned-element reproducers with the exact unavailable `=dup` diagnostic for `seq[SequenceOwner]`. Add separate copy-only/copy-plus-dup source-owned lowering guards and a successful explicit-move native control. The former ownership hold is resolved. |
| `52c3fe5007` and related instance rendering | Sixteen nominal guards still rejected the intended calls but no longer matched their old abbreviated text. Require exact rendered domain/schema/element arguments, including `ReportHash[2]` versus `ReportHash[0]`, without weakening exit/call/position checks. All refreshed guards pass. |
| #2743 refined concept resolution | The attempted SomeInteger formatter and separate signed/unsigned variants still fail. Keep concrete integer overloads. |
| #2753 array indexing | A nonzero-based integer-indexed array control passes on both old/new archives. No local before/after improvement or removable workaround is inferred from that control. |
| Native atomic instructions, channels, time-zone/math/NIF updates | Reviewed in the release delta; no further exercised project workaround was identified for removal. Preserve current worker, protocol, dependency and runtime boundaries. |

All 392 production modules and the real integration/offload main pass both debug smoke and
checked-release graph audits. The same whole graph and main pass Linux amd64 semantic checks.
Full compiler rejection verification passes all 2,449 guards, including the new sequence cases
and stronger instance diagnostics. Full Python discovery passes 908 tests with three skips.
All 99 selected native state/storage/PVM/RPC/resource suites pass. All 139 strict runtime
misuse probes in 16 selected families pass with successful checked native builds, exact assertion
diagnostics and positive native controls. All 24 selected actual current-download executable cases
pass. The canonical ARC/Clang/ThinLTO production build and real-browser/production-RPC check pass.

The maintained strict fresh-reopen panel passes all four cases and independent report validation.
The sanitized program fuzzer passes 10,000 inputs (246 coverage counters, 461 features), frozen
seed replay, expected assertion failure, fresh artifact creation and independent artifact replay.
Its documented default-allocator/fine-grained heap coverage limits remain unchanged. The relocated
macOS archive passes dependency/runpath verification and all four unpacked smoke options.
Actual private/shared NativeChecks cache controls both produce `7 -> 12 -> 12` in unchanged cache
directories. Final pinned formatting passes 4,315 Nim inputs plus the Rust crate; inventory and
diff checks pass. The source-epoch workaround stays retired.

Three remaining failures reproduce on the actual archive: generic integer formatting (one line),
nullable refinement across successive var-pointee calls (six lines), and sequence slicing (two
lines). Each reproduces 5/5 times outside the repository in fresh directories; deleting any source
line stops the intended failure. Tested alternatives compile and run. Related open/closed upstream
issues were searched/read; the cases differ from the related triggers found. GitHub master matched
this archive when checked; a separate source build was not performed. Keep the existing integer,
explicit nonnull-binding and slice adapters. Drafts with exact final output and limitations are
under `spec/nimony-reports-2026-10-23/` for maintainer submission; no issue was posted.

This is local macOS ARM64 runtime qualification plus Linux archive/semantic validation. It does
not claim Linux runtime, full E2E, exhaustive fuzz coverage, new performance comparisons or full
JAM/STF parity. Raw scoped evidence is under ignored `build/ci/nimony-2026-10-23-*` and
`build/ci/nimony-2026-10-23-report-evidence/`; maintained fuzz/reopen/package logs retain their
standard build paths. Earlier compiler/source results above remain historical, not attributed
to this archive. Publishing the updated PR automatically requests Smoke; heavy CI remains opt-in.


## Storage light-proof tranche on October 23

Merge master `a60cef83` (15 storage PRs after `b723f0c1`) through merge commit
`5aae0833`, retaining the qualified October 23 compiler `4724f66c2`. This tranche adds
complete-trie proof production, authenticated light caches, canonical snapshots, atomic files,
updates, streaming verification, borrowed publication, bounded proof retrieval/pagination and
selected exports. These remain the incoming standalone storage contracts; this compiler update
does not extend their application/state integration authority.

The new code hits the existing retained-ref iterator restriction. Use checked indexed reads in
four loops: `VerifiedStateLookup.bytes`, `PreparedLightSnapshot.bytes`, cache `forget`, and
`FullStateTrie.prove`'s detached value copy. Retain each immutable owner, output order, bounds
checks and copy semantics. Of the 98 incoming files, 94 remain byte-identical to master; only
these four storage modules differ, including their pre-existing upgrade adaptations.

Scoped local macOS ARM64 qualification passes all 23 selected native suites (15 new storage
suites plus eight complete-trie/StateStore consumers), 21 incoming compiler rejection fixtures
(18 privacy and three ownership/borrow checks), and 69 strict runtime misuse probes across five
families. Each runtime family builds successfully and requires its declared assertion diagnostic;
positive behavior is covered by the native suites. All 65 selected Python inventory/native-harness/
verification-guard tests and inventory preflight pass.

The debug and checked-release graphs cover all 396 production modules plus the real
integration/offload main. Linux amd64 checks cover the complete graph and main semantically;
they are not Linux runtime evidence. The four maintained strict fresh-reopen cases pass with
independent report validation. Pinned formatting covers the updated source tree. Raw evidence
is under ignored `build/ci/nimony-storage-light-*`; the original iterator diagnostic is retained.
The broader October 23 qualification above retains its earlier source scope: this increment
makes no new full-Python/full-guard/full-E2E, fuzz or performance-comparison claim.

PR #971 stays open for the maintainer's upcoming PVM/state merges and subsequent merge decision.
The compiler ownership hold remains resolved; the three documented compiler limitations and
report drafts remain unchanged. Publishing requests automatic Smoke only.


## PVM cursor and page-sharing tranche on October 23

Merge master `1c699722` (11 PVM PRs after `a60cef83`) through merge commit `a5cd6e93`,
keeping the qualified October 23 compiler `4724f66c2`. The incoming tranche adds validated scalar
spans/register writes, immutable shared page chunks, private staged memory writes and host
execution cursors, decoded successor pairs, bounded block-price reuse and owner-bound static
target validation. It also expands the frozen benchmark corpus. Preserve these upstream
contracts and recorded performance evidence without claiming a new timing comparison here.

Two new page-owner copy loops hit the retained-ref iterator diagnostic. Change only their
traversal to checked indexed reads in `machine.nim`: immutable scalar stores and initial scalar
writer activation retain the same shared page references, order, permission checks and snapshot
ownership. Of the 51 incoming files, 50 remain byte-identical to master; the only additional
compatibility edits are these two loops. No compiler/runtime patch or unchecked borrow is used.

Local macOS ARM64 qualification passes all 26 selected native suites, covering every changed
unit plus memory/control/register reference fixtures, host responses/failures/gas, inner invocation
and computed/assured/current-continuation consumers. All 12 incoming compiler privacy guards
and 54 strict runtime misuse probes across ten PVM families pass. Every runtime fixture builds
successfully before its exact assertion checks. Python PVM reference/benchmark/tooling discovery
passes 87 tests with two skips; inventory preflight passes.

Both debug smoke and checked-release semantic audits pass all 396 production modules plus
the real integration/offload main; the complete Linux amd64 graph and main also pass semantic
checks. Pinned formatting passes 4,378 Nim sources plus Rust. The sanitized program fuzz gate
passes 10,000 inputs, including the maintained frozen-seed and assertion/artifact/replay controls.
The default-allocator coverage limitations documented above remain unchanged. All 24 selected actual
current-download executable cases pass, including sequence, preimage, guarantee and rotated
workloads through the rebuilt integration/offload binary.

Scoped evidence is under ignored `build/ci/nimony-pvm-cursor-*`, including the original
iterator rejection. Earlier full compiler/Python/runtime qualification retains its exact earlier
source scope; no new exhaustive fuzz, full-E2E, Linux-runtime or performance claim is made.
The compiler pin and three remaining report drafts are unchanged. PR #971 remains open pending
the state merge and maintainer decision; publishing requests only automatic Smoke.


## State continuation and app timing tranche on October 23

Merge master `f5bdd0fa` (15 state/app PRs plus timing fix #1342 after `1c699722`) through
merge commit `a7403913`, retaining the qualified October 23 compiler `4724f66c2`. The incoming
contracts cover authenticated page import, producer-owned storage/request identities and selected
history, storage/request/service/preimage logical continuation, namespace-changing current
downloads, identity-source refresh and joined-shutdown receipts.

Five new loops in `src/state/accumulation/effects.nim` hit the same retained-ref iteration restriction.
Use checked indexed reads for request-fact lookup/copy, storage-fact lookup/copy and detached raw
key copying. Preserve first-touch identity rules, sticky request provenance, immutable fact sharing,
output order and existing allocation/byte limits. Of the 155 incoming files, 153 remain byte-identical
to master; `src/app/current/logical/startup.nim` retains its two earlier indexed-read adaptations, and only
`src/state/accumulation/effects.nim` needs new compatibility changes. No protocol or ownership contract is
weakened.

The E2E timing fix remains byte-identical to master: the real cancellation workload stops polling
once reset delivery is observed, and the finite Running fixture gas allowance rises from 40 million
to 400 million after the interpreter speedups. Its actual cancellation/reset/resource workload is
qualified separately from the native unit verdicts.


Local macOS ARM64 qualification passes all 37 selected native suites: every changed state unit
and the affected logical-source, durable/mutation, current-download command/loop/session/retention,
option and proof-import consumers. All 39 incoming compiler privacy fixtures and 134 strict runtime
misuse probes across 17 families pass. Each runtime family builds successfully before requiring
its declared assertion diagnostic. All 153 selected Python state/reference/current-download/tooling
checks and inventory preflight pass.

Canonical debug smoke and checked-release semantic audits pass all 402 production modules plus
the real integration/offload main. The complete Linux amd64 graph/main semantic checks pass;
Linux runtime remains untested locally. Pinned formatting passes 4,449 Nim sources plus Rust.
All 24 selected actual current-download executable cases pass with the rebuilt peer. The separate
signed cancellation/reset resource workload passes all 33 joined idle observations: one idle
thread, zero descriptor range and 10,256,384 bytes of retained RSS range, below its 16 MiB growth
budget. This qualifies the actual timing fix without changing its source or weakening its bounds.

Evidence is under ignored `build/ci/nimony-state-continuation-*`, including the original retained-ref
diagnostics and source/profile receipts. Broader prior nightly, fuzz, package and fresh-reopen
results retain their recorded source scope; they were not rerun for unrelated unchanged inputs.
This is selected local runtime coverage plus Linux semantics, not full E2E or Linux runtime.

All three announced storage, PVM and state merge batches are now incorporated. No additional
compiler blocker was found. The sequence-copy hold remains resolved, while the integer-generic,
nullable-var-call and sequence-slice adapters/report drafts remain unchanged. Leave PR #971 open
for the maintainer's merge decision; automatic Smoke is requested on publication, without heavy
CI labels or automatic merging.
