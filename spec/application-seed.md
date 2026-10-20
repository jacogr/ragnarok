# Explicitly configured application state seeds

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Supply the canonical application owner
from bounded chainspec text under an explicit complete-state resource policy.
Reuse the existing strict parameter/genesis decoder and structural chain capture.
Protocol equations, PVM selection, CLI and Services startup behavior are unchanged.

## Contract and completion tests

`initApplicationChain(text, StateStoreLimits)` requires a caller-supplied policy.
Validate configured parameters first; retain only their actual failed reason.
Require a complete configured genesis pair, distinguishing unavailable from invalid.
Reject broad trie-policy ceilings before hashing: items <= 16,384, per-value and
total bytes <= 4 MiB, nodes <= 1,048,576. Short policies and primitive refusal keep
configured capture's existing Invalid reason. Policies are never silently clamped.

Commit the decoded complete map once, retain its exact snapshot in the selected
head and fork that version into ApplicationChain without rehashing. Inherit both
trie and independent write-count/write-byte limits unchanged. Defaults for raw
capture and configuredGenesis still use the existing readonly policy, exposed as
genesisStoreLimits; no writable budget is inferred from protocol parameters.
All startup text/header/map storage is detached. Copies remain independent branches.
This trusts supplied full-state completeness and structurally validates only the
existing header/roster/time boundary, with no consensus or persistence claim.

Test JSON emitted through the shared structured writer, exact legacy/direct-capture
parity for every key/value and metadata, one trie commitment plus one header hash,
write-count/byte/trie limits and immutable views. Genuinely re-admit and finalize an
empty signed block against the newly decoded seed, then adopt it through the
application owner; a certificate bound to a separately built equal-root parent must
refuse. Check missing/partial/duplicate/malformed/oversized text and state, all policy
ceilings, early/final hash failure and retry, detached owners and 1,000 init/refusal
ARC cycles. Add selected-accessor, privacy and explicit-policy domain probes. Run
affected application, chain-capture and RPC consumers plus inventory/tooling checks.

## Observed verification

Checked optimized native `application_seed` passes, including genuine re-admission,
PVM finalization and application adoption from the decoded seed. All 1,000 ARC
init/refusal cycles retain 133,648 occupied bytes before and after. Four strict
runtime extraction probes and four compiler privacy/explicit-policy probes pass.
Affected `rpc`, `chain_state_snapshot` and `application_chain` suites pass; the
latter two retain equal before/after ARC occupancy over 1,000 cycles each.
Inventory passes with 202 native suites, 137 failure families and 1,866 data-driven
probes; all 33 verification/failure-harness Python tests pass. Pinned Nim/Rust
formatting and whitespace checks pass. These are local macOS results; Linux and
full verification remain CI responsibilities.

## Remaining work

The executable/service startup path must still select an explicit complete-state
policy, share this exact head with optional RPC and own shutdown/restart. No new
CLI mode, automatic budget, live import scheduler, fork choice, persistent commit
or light-state representation is introduced. PVM owns execution/finalization.
M1 framing is complete; full state serialization and JAM/STF parity remain open.
