# Current Gray Paper qualification

Target source: `fad0ded4a433052397bf7234352a57fe491883f7`, compared with
`3861aed15d7d016a3a416e14e61fc67dddf6daec`. The upgrade covers authorizer code limits,
package gas inclusivity, report refine-load bounds, refinement failure precedence,
bless duplicate keys, parent-free assurance wire records, and compact validator statistics.
The final qualification layer adopts the source pin and public preset tuple and qualifies the
combined execution, bless, assurance and statistics behavior. Earlier layer receipts retain
their original bounded scope; the completed combined qualification is recorded below.

The vector dataset remains `d7b73e396d2f872fcfca37cbbb7d7869675d34d6` on `gp-next`.
Its old assurance/statistics bytes are historical evidence and do not independently qualify the
new encoding. No dataset switch or alternate decoding is authorized. The existing compact-gas
interpretation and fixed E4 service keys remain in force.

## Execution bounds

`text/definitions.tex`, `text/work_packages_and_reports.tex` and
`text/reporting_assurance.tex` distinguish input data (13,791,360 bytes) from the encoded
bundle (13,904,950 bytes). Fetch keeps the input limit. Package gas sums accept equality.
Reports independently bound refinement gas, imports, exports, extrinsics, input footprint,
bundle bytes and authorization gas, and require exported segment-count equality.
Every aggregate checks remaining capacity before arithmetic. Invocation errors retain their
kind before successful output oversize/export checks. Authorizer code permits196,608 bytes.

Completion checks include exact/one-over package gas and report load boundaries, full-width
counter overflows, per-report reset, authenticated authored reports, real refinement invocations
with overlapping failure conditions, exact/one-over authorization code, and unchanged fetch input
limit. The combined qualification below covers the remaining upgrade layers.

Signed combined-activity fixtures use the actual Tiny per-report refinement ceiling of1B gas,
then verify the two-report2B service total. The old UINT64_MAX signed-report overflow scenario
is incompatible with admission bounds. Independent pure core/service projection witnesses retain
full-width arithmetic overflow coverage; no admitted certificate bypasses the new report policy.

## Execution-layer evidence

Checked native suites pass for package boundaries, signed report policy, actual refinement report
results, authorization invocation, authorized/owned-input refinement, both startup-policy paths,
computed admission, assured queues, auditable bundles, fuzzer profile selection and accumulation
statistics. The latter retains independent literal wire expectations and fresh1,000-cycle ARC
release evidence. The independent mathematical package corpus agrees byte-for-byte on8,127
context/import/commitment/item/package requests, including exact gas equality and one over.
All 486 production modules and the peer entry point pass checked-release semantic compilation;
final fuzzer/CLI changes receive focused semantic and native checks. Package reference tests and
trace-conformance tooling tests pass; formatting, inventory and whitespace checks pass.

Evidence is local macOS checked/optimized execution under the recorded pinned toolchain,
retained in `build/gp-execution-*` and `build/tests/gp-package-corpus/result.json`. It establishes
this layer's behavior, while source-pin adoption, bless and new wire/state encodings remain
subsequent qualification layers. Whole-client and exact-head Linux CI claims remain separate.

The bundled `config/tiny-devnet-policy.conf` is migrated with the v2 schema and explicitly
sets Tiny refinement gas to1,000,000,000. The current-policy native suite loads that actual
shipped file through the same file decoder used before devnet listener startup, in addition
to exercising generated policies. Its fixture provider passes the source path directly and
records a transport digest; it does not substitute a copied policy or infer its correctness.

## Bless duplicate keys

Target `text/pvm_invocations.tex` compares the cardinality of distinct service IDs with the
original raw pair count. Both identical and conflicting repeated IDs return HUH. Memory
preflight still precedes authority/duplicate checks, and those checks precede WHO for invalid
proposed roles. Gas uses the complete raw count. State effects reject duplicate keys without
publishing a successor; guest dispatch translates that refusal to HUH. Completion witnesses
cover both duplicate forms, duplicates combined with invalid roles, exact raw-count charging,
unchanged C12/retained owners, memory precedence, unique numeric sorting and ARC release.

The bless native suite passes actual duplicate/refusal/preexisting-success and raw-gas cases
with fresh1,000-cycle ARC evidence. Independent target report inputs match availability
segment count to digest exports before signing. Complete native comparison passes36 signed
transitions across6 allowance chains and210 across21 rotation/privilege chains. Seven
independent Python invariants pass. The historical report factories retain their original
inputs in the historical archive. Current factories select the target count equality before
signing; final qualification includes every maintained report family and the new wire/state formats.

## Parent-free assurance qualification

Target `fad0ded4a433052397bf7234352a57fe491883f7`, Appendix C.2 and
`text/reporting_assurance.tex`, removes the serialized parent from each assurance.
Records contain fixed profile bits, E2 validator index and a64-byte signature; Tiny/Full
strides are67/109. Signature verification still hashes the actual externally supplied parent.
There is one current encoding; original pinned vectors remain immutable historical evidence.
Qualification derives current structural records explicitly from their named historical fields,
without claiming the old binary representation is current. Completion requires exact new wire
bytes, every truncation, canonical padding/index ordering, atomic/alias behavior, signatures
against the actual and a different parent, and real block/admission/availability consumers.

The assurance layer passes33,393 independent codec/inspection requests,2,087 ordinary
OpenSSL signing-context requests and17,065 whole extrinsic/block requests, comparing every
result byte. Native codec, context, original signing credentials, availability, block, commitment,
computed-assurance and report-admission suites pass, including fresh1,000-cycle ARC receipts.
All 486 production modules and the peer entry point compile with checked release flags.
Sixteen independent Python contract checks pass. Original assurance fixtures are retained under
`tests/fixtures/historical/parent-free-assurances/`; their target counterparts omit the parent.
The remaining whole-state historical golden families are qualified with the statistics/source-pin
layer, because the new C13 representation changes their state roots again. This layer alone
does not claim that final full-state replay qualification or whole-upgrade completion.

## Validator statistics and final qualification

Target C13 encodes each of six validator counters as a canonical natural. Counters retain the
complete uint64 domain, checked before accumulation; fixed E4 service keys and C12 E8 gas remain
unchanged. Decoder preflight scans every scalar before allocating an owner. Completion witnesses
cover natural-width transitions and maximum counters, exact increments and overflow refusals,
preimage payload bytes, reporter Ed25519 identity, rotation order, full-map replay and pin integrity.
Historical E4-counter state is explicitly converted in test-only qualification, with original
bytes preserved; production accepts only the target format.


## Completed combined qualification

All 185 maintained native corpora pass: 100 complete current-state replay families, 78 Fuzz/JAM
cases and seven statistics, composition, width, trie, raw-root and trace corpora. This includes
2,455 independent statistics requests, 14,260 composition requests, all 224 qualified chapter
captures and 14 derived whole-state mappings. Original published bytes and roots remain
historical receipts; explicit test-only conversion derives current C13 records before native
execution. Production decoders have one current representation.

The final report-factory audit also bounds high-core extrinsic counts to 128 and binds each
availability segment count to the digest export total before signing. Full-profile ancestry,
its missing-anchor control, guest execution, population changes and real offline commands pass.
After that fuzzer-only correction, all 78 Fuzz/JAM cases were rerun. The 107 unchanged non-fuzzer
results were retained only after a recorded file-hash audit established identical production,
native, Nim, specification and non-fuzzer reference/fixture inputs. The audit records both source
identities and every changed fuzzer-owned path.

Thirty-six focused native consumer suites pass, including two unchanged pure codec/projection
receipts. All 152 existing statistics/activity failure contracts pass; their exact failure reasons
and success-only payload guards remain enforced. All 486 production modules and the peer entry
point pass checked-release semantic compilation. Complete Python discovery ran 1,668 tests with
one skip; its 15 stale-format failures were cleared by 79 affected checks. Twenty additional
composition/root/width checks and all 39 Python fuzzer tests pass. Formatting, inventory and
whitespace checks complete the local qualification; these receipts do not claim a fresh complete
Linux native run.

All 100 current-state and 36 fuzzer golden families were independently regenerated, with ten
additional serialization/trace fixtures and metadata-only primitive witness qualification. The 153
original files are preserved byte-for-byte through git mv, including the original Genesis binary.
The vector dataset pin and its last-compatible source qualification remain unchanged. Crypto
implementations, proof payloads, primitive dependencies and compiler/toolchain pins are unchanged;
only their Gray Paper source-identification metadata follows the adopted source. The consumed
Bandersnatch chapter is byte-identical across this source upgrade.

The remaining source clarifications require no alternate implementation: work-report prerequisites
are sorted unique hashes in the report codec; validator preimage bytes count payload lengths;
reporter membership compares posterior active Ed25519 keys and credits each validator once.
The removal of the blanket dictionary-key sentence does not change the explicit C12 E4/E8 or C13
E4 service-key contracts. The accepted compact core/service statistics gas policy remains in force.
