# Privileged-service configuration state: chapter 12

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **12**, `text/accounts.tex` privileged-services definition,
`text/overview.tex` unsigned gas domain and C.1 dictionary/natural/fixed-integer encoding.
Exact normative source and fixture hashes are recorded in [pins.json](pins.json). No dependency,
compiler or toolchain revision changes.

## Exact schema

`src/codec/state_privileges.nim` supplies `privilegeStateEntry(source, config)` for C(12) and
`decodePrivilegeState(input, config)` for one complete component prefix:

```text
E4(manager)
|| E4(assigner[0]) || ... || E4(assigner[core_count - 1])
|| E4(delegator) || E4(registrar)
|| E(always_count)
|| (E4(service_id) || E8(gas_allowance)) pairs in strictly increasing numeric service-ID order
```

There is no tuple count or assigner-sequence count: its length is fixed by the configured core
count. The general fixed-width note after T also governs the dictionary: one canonical natural
count precedes fixed E4 service keys and E8 gas allowances. Every pair occupies exactly twelve
bytes, including zero padding. This follows the bounded service/gas domains and the
[pinned nonempty binary evidence](state-widths.md). Dictionary IDs have the uint32 domain, while
gas accepts the entire uint64 domain, including zero and its maximum. Keys sort numerically,
not by encoded bytes, gas value or little-endian role octets. Duplicate/descending keys reject;
encoder sources are never silently sorted or deduplicated. Distinct core roles may share a
service, and role IDs need not occur in the always-accumulate dictionary.

Existing `ServiceIndex` and `CoreCount` types are reused. `PrivilegeGas`, `PrivilegeCoreIndex`
and `PrivilegeEntryIndex` keep gas, core positions and dictionary ordinals nominally separate.
`PrivilegeState` is a stable synchronous source with role fields, assigners and fixed
`AlwaysAccumulate` pairs; its mutable arrays never become retained owner storage.

## Bounds, failures and lifetime

`PrivilegeConfig` supplies the existing supported 2..341 core domain, an independent dictionary
item ceiling and a complete encoded-byte ceiling. Invalid core profiles reject before input
access. The fixed E4 group must fit the byte policy before scanning; the dictionary count still
consumes additional budget even when empty. Encoder sources must contain exactly one assigner
per configured core. Announced dictionary count is checked against caller policy and native typed
storage capacity before pair traversal/allocation. The natural count and every fixed key/gas byte are charged to the parent budget; arithmetic is
checked before addition. Malformed/overlong counts, incomplete fixed fields, duplicate/descending
keys and late gas failures publish no values or progress. All E4/E8 bit patterns are valid numeric
values; former compact-pair framing is not an alternate format.

The decoder preflights every field without allocation, then copies the fixed roles, assigners
and complete pairs into private acyclic ARC storage. Count policy bounds work; actual input
presence and byte policy bound parsing. Capturing repeats only proved scalar reads. The source
encoder checks complete shape, count, key order and extent before allocating one independent
output. Source/input stability is required only during the synchronous call. Allocation exhaustion
retains the project's existing Nim fail-stop policy.

`PrivilegeResult` defaults/failures contain only a reason. Complete decode success binds the
snapshot to the exact consumed extent, leaving unrelated suffix bytes with the caller.
`PrivilegeSnapshot` copies retain private immutable storage. `privilegeInfo` returns copied
roles/cardinalities; `privilegeAssignerAt` and `alwaysAccumulateAt` check nominal indices before
narrowing and return independent fixed values. Default owners and invalid indices are typed
failures. Source mutation, caller-input destruction, extracted-pair edits and replacing one owner
handle cannot alter retained data. No mutable retained sequences or standalone spans are public.
Encoded entry bytes belong to the caller and remain stable during a later [trie call](state-trie.md).

This codec does not execute bless/assign/designate/register host calls, check service-account
existence/eligibility, validate a gas budget against block accumulation gas, enforce privilege
transitions or execute accumulation. Those require contextual state rules beyond T serialization.
Passing a component codec does not establish a valid chain state.

## Evidence and reproduction

Run the complete checks; Make prepares native dependencies:

```sh
make check
```

Seven literal oracle checks anchor exact fixed/no-count framing, E4/E8 padding, full gas
domain, numeric order, byte/item policy, late truncation and huge-count overflow.
**1,390** native requests compare entry keys/bytes, copied roles/assigners/pairs, consumed extents
or failure-only reasons against independent Python byte equations computed before native execution.
The native source adapter uses decimal fields, not production decode output. Decode observations
extract logical values after destroying the input rather than using native round trips as answers.

Cases include every proper truncation of a fixed-pair parent; E4/E8 value and natural-count boundaries;
0/1/127/128/129/255/256/1024 dictionary counts; empty dictionaries; shared role IDs; high service IDs;
full uint64 gas; exact/one-below parent and count limits; wrong source shape; unsupported core
profiles; 2/3/127/128/255/256/341 core arrays; malformed/overlong counts and incomplete key/gas fields;
duplicate/descending keys; legacy compact-pair byte probes; hostile count announcements;
250 deterministic valid sources with single-byte and arbitrary raw mutations; suffixes; and
24 partial C(12)-only trie roots. Supplementary native tests cover retained scope, independent
source/input/pair copies, default owners, nominal indices and runtime result guards. Two negative
compiler probes reject gas-as-service and dictionary-index-as-core; one rejects private storage
access. All other codecs retain their existing implementations.

Sixteen published pre/post/profile observations derive component bytes from eight exact JSON blobs
at vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`:
`stf/accumulate/{tiny,full}/{always_accumulate-1,always_accumulate-2,bless_from_non_manager-2,assign_from_non_assigner-2}.json`.
The fixture adapter maps `bless` to manager, `assign` to core assigners, `designate` to delegator,
`register` to registrar, and `always_acc` to service/gas pairs. Values are unchanged; JSON dictionary
pairs are explicitly sorted numerically, as required by C.1. Unique IDs, exact supported schema and
tiny/full core counts are asserted. All sixteen derived components pass. These are not standalone
published T(state) binaries, executed STFs, valid-transition certifications or whole-state roots.

Every consumed Git blob is SHA-256 checked before parsing; partial clones may fetch exact promised
objects without checkout/gitlink changes. No upstream scripts run. The historical Nim 2.2.12
ARC/Clang LTO builds
retain assertions/bounds/range/field/overflow checks. Ignored `build/tests/runtime/` records
commands, corpus SHA-256, verdicts and diagnostics; Linux CI runs the suite and retained its logs.
Local results are macOS arm64; Linux confirmation requires CI after push. Existing crypto gates
remain unchanged.

The four original nonempty STF Privileges spans described in [state-widths.md](state-widths.md)
now decode completely under exact/one-below byte limits. Their field offsets, original hashes,
fixed numeric values and candidate comparison remain reproducible without running upstream scripts.
These are STF fields, not independently published nonempty T12 trie entries.

The C12 width migration is complete. Empty dictionary bytes are unchanged; nonempty entries use
E4/E8 pairs exclusively. [Typed composition](state-composition.md) preserves the same bounds and
ownership contracts. Compact C13 gas is accepted by maintainer policy; M1 state parity remains
incomplete pending request namespace policy. The request-namespace question is [parked for Gray Paper 0.8.1/0.8.2 review](state-clarifications.md).

## Experimental Nimony branch

The [Nimony trial](../docs/nimony-trial.md) verifies the unchanged 1,390 independent requests and
seven literal reference checks. `PrivilegeResult[T]` uses private status/payload, read-only reasons
and checked success-only accessors, including internal natural and layout proofs. Nullable owner
storage is checked through stable retained locals. Fixed E4 roles/services, E8 gas and strictly
increasing numeric dictionary order retain their existing representation and error precedence.

Two native suites cover escaped/replaced/retained parents, copied metadata/assigners/pairs, empty
dictionaries, late failures and arithmetic/storage boundaries. Fifty isolated runtime cases require
the exact success contract; twelve privacy/read-only and two nominal probes reject compilation.
The warmed 1,000-cycle ownership workload returns live occupancy 192 → 192 bytes locally on
macOS ARM64, checked ARC/Clang LTO. This does not establish general leak freedom or Linux parity.

Use `make runtime`.
The numerical observations above describe the original compiler-port increment. Actual Linux results
and
full M1/M2/M3 migration remain separate gates. The compact C13 gas policy and parked request
namespace question are unchanged by this compiler port.
