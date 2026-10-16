# Privileged-service configuration state: chapter 12

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **12**, `text/accounts.tex` privileged-services definition,
`text/overview.tex` unsigned gas domain and C.1 dictionary/natural/fixed-integer encoding.
Exact normative source and fixture hashes are recorded in [pins.json](pins.json). No dependency,
compiler or toolchain revision changes.

## Exact schema

`src/state_privileges.nim` supplies `privilegeStateEntry(source, config)` for C(12) and
`decodePrivilegeState(input, config)` for one complete component prefix:

```text
E4(manager)
|| E4(assigner[0]) || ... || E4(assigner[core_count - 1])
|| E4(delegator) || E4(registrar)
|| E(always_count)
|| (E(service_id) || E(gas_allowance)) pairs in strictly increasing numeric service-ID order
```

There is no tuple count or assigner-sequence count: its length is fixed by the configured core
count. The four-byte override applies only to the manager/assigners/delegator/registrar group.
The current implementation interprets the following dictionary using C.1's ordinary encoding:
one canonical natural count and canonical natural keys and values. The general T fixed-width note
needs reconciliation for these bounded service/gas domains; this is now an explicit
[whole-state parity gate](state-roots.md), not a settled normative width decision. Dictionary service IDs have the uint32 service domain, while
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
storage capacity before pair traversal/allocation. Every natural scalar is charged to the parent
budget; arithmetic is checked before addition. Malformed scalars, overlong representations,
service overflow, duplicate/descending keys and late gas failures publish no values or progress.

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

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_privileges_harness.py
python3 tests/test_state_privileges.py
python3 tools/format.py --check
```

Six literal oracle checks anchor exact fixed/no-count framing, natural key/gas widths, full gas
domain, numeric order, service overflow, byte/item policy, late truncation and huge-count overflow.
**1,354** native requests compare entry keys/bytes, copied roles/assigners/pairs, consumed extents
or failure-only reasons against independent Python byte equations computed before native execution.
The native source adapter uses decimal fields, not production decode output. Decode observations
extract logical values after destroying the input rather than using native round trips as answers.

Cases include every proper truncation of a mixed-width parent; E4 and natural boundaries;
0/1/127/128/129/255/256/1024 dictionary counts; empty dictionaries; shared role IDs; high service IDs;
full uint64 gas; exact/one-below parent and count limits; wrong source shape; unsupported core
profiles; 2/3/127/128/255/256/341 core arrays; malformed/overlong early and late count/key/gas fields;
duplicate/descending keys; out-of-domain natural service IDs; hostile count announcements;
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
objects without checkout/gitlink changes. No upstream scripts run. Nim 2.2.12 ARC/Clang LTO builds
retain assertions/bounds/range/field/overflow checks. Ignored `build/state-privileges/` records
commands, corpus SHA-256, verdicts and diagnostics; Linux CI runs the suite and retains its logs.
Local results are macOS arm64; Linux confirmation requires CI after push. Existing crypto gates
remain unchanged.

The documented M1 C.1/C.2 framing baseline remains covered. State chapters **1–16** now have typed
serializers; chapter 13 retains its [trace parity gate](state-statistics.md). Service entries and
whole-state composition remain open. Next planned bounded increment: **whole-state composition/root evidence
and parity review**. See the [M1 checklist](../docs/m1.md).

The subsequent [pinned width investigation](state-widths.md) supports the next implementation
migration: C12 dictionary IDs/gas to E4/E8 and C13 service keys to E4. Current codecs remain
unchanged in that investigation; C13 gas and request-namespace policy remain unresolved.
