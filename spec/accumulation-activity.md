# Accumulation-bound combined activity

## Scope and authority

Bind [core/service activity](core-service-activity.md) to the exact
[validator activity candidate](accumulation-validators.md), then replace C(13) on a private complete
map. Authority remains GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, statistics.tex
SHA-256 `a8bee7c99853ed116fb7ed5e45e9977c7c323ad386e5a7e6c8cefba509f2d2a9`, plus the pinned
[preimage admission](preimage-transition.md) and [C(13) encoding](state-statistics.md) contracts.
No pins, arithmetic formulas, wire widths, signature validation or PVM behavior change.

## Contract

Only PreparedAccumulationValidators constructs PreparedAccumulationActivity. Retain that source
and derive its exact timestamp/statistics/finalization/report-admission graph. Incoming reports
come from its verified guarantee owner; newly-available reports come from its authenticated
availability plan; raw assurances and preimages come from that same bound block. Accumulation S
comes from the retained timestamp statistics, never detached caller rows. Core count and validator
populations come from that same chain/profile and validator projection. Callers supply only
resource ceilings, without alternative maps, rosters, projections or chain domains.

Admit the exact submitted preimages against the original admitted parent complete map using the
existing ordered/unique/outstanding-request checks. Retain this admission certificate for later
integration. Only its per-service provisions contribute statistics; invalid, unsolicited or malformed
requests cannot become a combined activity candidate. This admission hashes preimages and their
request keys, but does not provide values or alter histories. Rechecking post-accumulation requests
and integrating those values remains the next phase.

Bound component copies and report/assurance/S/provision descriptor populations independently.
Run the existing pure core/service projection with source-derived domains, combine its fresh core/
service tuples with the source's projected current/previous validator tuples, and use the pinned
codec for exact C(13) encoding. Decode that validated entry to retain one immutable complete
ActivitySnapshot. A private fork of the exact timestamp map inherits store ceilings and applies one
C(13) Put atomically. Never write nested preimages, alter request histories, replay accumulation,
reverify signatures, copy stale core/service rows or mutate an earlier map.

The opaque acyclic owner retains exact source, admitted preimages, copied core/service work info,
canonical entry/snapshot and complete successor. Getters retain immutable owners or copy fixed
observations/entry bytes. Defaults and refusals carry reasons alone; preimage/projection/codec/store
causes have separately guarded alternatives. Resource, admission, overflow or backend failure
cannot expose a partial entry or usable successor. This is a private complete-map bookkeeping
candidate, not canonical whole-block publication or light-state proof support.

## Completion tests

Require genuine signed empty, incoming, newly-available, preimage-only and combined histories.
Admit actual outstanding empty/nonempty preimages from the original parent. Check literal C(13)
bytes for all four components, numeric service union, fresh per-block rows and preserved epoch
rotation; compare a separately reconstructed full-map root with only C(13) replaced. Preserve all
earlier C(3)/C(14)/C(15)/C(16), account timestamps, requests and opaque entries. Unsatisfied/late
unsolicited, disordered preimages, short independent policies, projection overflow, codec ceilings
and immediate/delayed backend failure must refuse atomically and allow retry. Check copied entry/
info, immutable snapshot/source lifetimes, strict runtime/private/nominal extraction and 1,000 ARC
cycles. Run selected native suite, affected signed-fixture consumers, Python/inventory and pinned
formatting. Reuse unchanged pure algorithms, codecs and preimage admission evidence.

## Remaining work

Post-accumulation preimage integration, remaining transfer/account/privilege coordination and
whole-block publication remain open. M1 framing is complete; full state serialization and
accumulation/block parity remain open.

## Local verification

`make unit SUITE=accumulation_activity` passes genuine signed empty, incoming-only, available-only,
preimage-only, combined and epoch-boundary histories. Real initial PVM guests also contribute
actual 22/22 gas-only S rows. Independent literal E4/natural framing matches every byte of all four
C(13) components. A separate full-map reconstruction using the same prior keys and only the literal
C(13) replacement reproduces the candidate root. Stale parent service/core statistics are reset;
all prior C(3), C(14), C(15), C(16), account timestamps, requests and opaque entries survive.

Three genuine outstanding preimages, including an empty blob, contribute service-specific 1/1 and
2/3 count/byte pairs. The retained admission prior is the identical original-parent snapshot;
requests remain outstanding because this phase does not integrate values. First/late unsolicited
and disordered blobs refuse with selected admission causes. Twelve independent short component,
report/assurance/S/preimage/provision/digest/service/codec policies refuse at their intended boundary;
exact and full-width ceilings retry successfully. Certified reports with maximal refinement gas
refuse the overflowing combined service sum with the existing typed projection error.

Immediate admission-hash refusal and delayed trie failures after the independently measured
admission-hash prefix preserve source roots/bytes and expose no successor. Retry succeeds.
Canonical entries and copied info remain independent after extraction; source/snapshot owners
survive source scope. Across 1,000 scoped success, early-admission refusal and delayed-store refusal
cycles, occupied allocation remains 1,751,968 bytes before and after.

All twelve runtime extraction guards and five compiler privacy/source-substitution rejections pass
through existing source-discovered runners. The affected report-admission and validator suites
pass, including their 1,000-cycle allocations at 294,032 and 946,832 bytes unchanged. Shared fixtures
only add optional per-core refinement loads before genuine signing, with existing defaults retained.
Python discovery passes 451 tests with seven skips; inventory discovers 116 failure families,
1,707 probes and 181 native suites. Pinned formatting/checking passes for 1,585 Nim files and the
Rust crate; diff checks pass. Existing projection algorithms, codecs, preimage admission, stores,
cryptographic primitives and PVM code are unchanged, so their prior algorithm evidence is reused.
Logs remain under ignored `build/accumulation-activity/` and native selected/evidence directories.
These are local macOS results, separate from exact-head Linux CI. M1 framing is complete; full
state serialization and accumulation/block parity remain open.
