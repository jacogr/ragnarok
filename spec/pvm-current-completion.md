# Complete current PVM state builder

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive;
this orchestration changes no protocol semantics or dependency pins.

`prepareCurrentAccumulationComposition` consumes a genuine terminal current sequence and runs
statistics, account timestamps, C15/C16 finalization, ready/recent history, validator observations,
C13 activity, preimages, authorizer pools and consensus composition in order. Each phase keeps its
existing independent resource ceiling. Only complete success exposes the full consensus owner.
Each failure retains its actual guarded child, with no earlier usable prefix.

`runCurrentAccumulationCompletion` drives one original block round with its frozen parameters and
then calls the same state-only builder. Composition alone never runs guests or publishes canonical
state. Current and legacy completion types remain nominally separate. Preparation/publication and
worker integration are independent consumer boundaries; this is not a complete JAM parity claim.

Completion checks compare the complete root against independently assembled existing current phase
witnesses, exercise every state-phase failure and defaults, drive the genuine round convenience
entry, retain original snapshots, and release 1,000 ARC cycles. Source-owned runtime guards verify
success and all failed-child accessors; privacy/nominal compilation, module/inventory/format checks
retain exact diagnostics. Local macOS evidence and exact-head Linux CI remain separate.

Local macOS validation passed: 305 source modules; current completion and consensus native suites;
complete root equality for state-only and execution convenience entry points; all ten actual phase
refusals; 12 exact runtime access guards; two compiler rejections; 1,000 ARC cycles; inventory and
formatting. Linked native/runtime checks ran serially. Exact-head Linux CI is separate.
