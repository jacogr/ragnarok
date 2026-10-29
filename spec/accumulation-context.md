# Initial accumulation contexts

## Authorized bounded scope

Implement the initial `partialstate` and `implications` bindings of GP 0.8.0, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: `accumulation.tex`,
`finalstateaccumulation`, and `pvm_invocations.tex`, `implications`/`accinvocation` initializer `I`.
Source hashes remain recorded in `spec/pins.json`; no authority or vector pins change.

Retain the [invocation bootstrap](accumulation-invocation.md) and its exact service state.
Bind the complete account mapping through its immutable full-state source, plus decoded C(2)
authorization queues, C(7) staging validators and C(12) privilege roles/always-accumulate map.
Require complete chapter extents and coherent chain cardinalities under explicit local ceilings.
Initialize both regular and exceptional contexts to the same immutable `I` value: service ID,
partial state and next free ID, empty transfers and provisions, and absent yield.

The bound adapter must derive state and profile from the original block certificate rather than
accept caller-supplied substitute components. Parent partial state and posterior entropy have
separate provenance. [Incoming credit](accumulation-credit.md) precedes context construction.
No mutable checkpoint, host call, PVM dispatch or publication
is included, and a complete-state source must not be confused with a light-node partial map.

## Completion tests

Native tests will check all initial fields, exact chapter consumption, missing/malformed chapters,
profile mismatch and exact/one-below resource ceilings. Distinct chapter contents and unrelated
service records must survive extraction and source replacement without mutable aliases. A genuinely
signed block will exercise the bound path. Default/result privacy, nominal API positions, strict
runtime extraction and repeated ARC release will be verified through the existing test groups.

## Implementation and ownership

`src/state/accumulation/context.nim` constructs immutable `PreparedAccumulationContexts` from a
successful ready-code bootstrap. `initialContext(Regular|Exceptional)` selects the same retained
initial `I`; the initial-only type cannot express pending transfers, provisions or a present yield.
`contextInfo` reports their zero/absent initial values, service and next free ID. There is no
checkpoint mutation or execution-outcome API in this slice.

`contextAccounts` retains the post-credit complete `StateStoreSnapshot`, including all service
metadata, storage and preimages, rather than copying only the invoking account. It also retains
unrelated chapters: this is an account-backing source, not a filtered mapping or a new partial-state
root. The invoking account was decoded by service preparation and is available through
`contextSelf`; unrelated account payloads remain opaque and are not newly validated here.

`contextQueues`, `contextStaging` and `contextPrivileges` expose existing immutable codec owners.
The adapter requires exact whole-chapter consumption and coherent core cardinalities. The configured
validator population remains the active chain profile; C(7) independently accepts
any valid GP valcount within the core domain and staging resource ceilings. It checks each complete byte extent and their aggregate before copying any
chapter. Hash, validator and allowance traversal/allocation ceilings remain independently enforced
by the component decoders. Oversized input, including suffix bytes, is a resource refusal when it
exceeds policy; otherwise incomplete/invalid encodings and suffixes are malformed-state refusals.
Subtract-before-add charging preserves the aggregate invariant under wrapping Nimony arithmetic.
Existing store policy bounds the retained map; the new aggregate ceiling charges the three decoded
chapter buffers, not another copy of the complete account mapping.

`prepareBlockAccumulationContexts` retains a genuine `BlockAccumulationInvocation`, derives its
chain profile through the certified service/round/queue/admission chain, and rejects substituted
core/population settings. The source map comes exclusively from its bootstrap's service owner.
Partial-state accounts/C(2)/C(7)/C(12) use that parent; bootstrap entropy remains bound to posterior
C(6). No caller buffer can replace a component while preserving the bound certificate.

All owner and tagged-result storage is private and acyclic. Read-only child handles retain their
source after local handles disappear; extracting serialized bytes or fixed records permits caller
edits without changing either initial dimension. Initialization performs no hashing, state writes,
identifier reservation or full/light database selection.

## Verification evidence

`tests/unit/state/test_accumulation_context.nim` compares every queue hash and all staging key,
BLS and metadata bytes against independent scalar patterns across 32 deterministic states. It
checks every role/assigner/allowance, both initial dimensions, self/other accounts and unrelated
preimages. Exact/one-below byte, aggregate, hash, validator and allowance policies are exercised.
Missing chapters, final-byte truncation, trailing bytes, invalid/noncanonical roster counts and a
invalid roster populations all refuse without publishing partial state. Valid staging/active
population differences are accepted under the [shared successor contract](pvm-state-successor.md),
including exact and one-below capture policies for six/nine-validator transitions.

A genuinely signed authored block checks the complete parent root and chapter identity, decoded
staging/queue/privilege views, candidate arguments and retained source certificate. Publishing a
separate replacement map and mutating extracted bytes cannot alter either original context.
A refused-hash provider proves context binding needs no hashing. Default handles return reasons;
five privacy and one nominal compiler probes protect construction/extraction, and twelve strict
runtime probes reject default/refused value access. A 1,000-cycle ARC check covers successful and
late-refused initialization, including release of already-decoded queue/staging owners.

These are authored initial-context witnesses, not published full accumulation STF outcomes. Existing
codec corpora and independent references retain their coverage; this slice adds no Python protocol
implementation, upstream pin change or claim of completed accumulation.

Local affected verification passed:
`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`.
The run compiled 96 source modules, passed 109 native suites and all corpora/runtime/compiler
probes, and passed 404 Python tests with three existing skips. The new ARC loop retained exactly
167,664 occupied bytes before and after 1,000 success/late-refusal cycles. Reports are reproducible
under `build/tests/{modules,runtime,failures,guards}/results.json`; the complete local log is
`build/accumulation-context/verification.log`. These are local results; Linux CI verifies pushed
revisions separately. E2E behavior is unchanged and that group was not rerun locally for this slice.

## Next bounded work

Prepare the standard accumulation machine-entry binding (`Psi_M`, entry point 5) from the retained
code, gas and compact arguments, coordinated with the PVM standard-initialization implementation.
Checkpoint/host effects, termination selection, later rounds and publication need
subsequent bounded work backed by genuine execution outcomes.
