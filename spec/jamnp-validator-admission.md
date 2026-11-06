# Validator reservation and epoch policy

Scope: bounded Nim admission ownership over the authenticated previous/current/next identity
union, builder reservations and other-peer reservations; gated topology replacement from a selected
complete canonical `ChainView`. JAMNP-S remains pinned at
`aa0e2b8498c0b1bc1725af2903704d701c6577ab`, required connectivity and epoch transitions.

Authenticated validator identities use their own budget regardless of ALPN. Builder ALPN requests
a reserved builder slot for a non-validator and grants no protocol privilege. Other identities
cannot consume reserved builder or validator capacity. Reject duplicate/self identities and occupied
or out-of-range native slots without changing counts. Closure releases exactly one retained slot.

New epochs remain held until a block in that epoch is explicitly finalized and at least
max(E div 30, 1) slots have elapsed from its start. Finalized ancestry establishes finality of the
first block in that epoch. A peer's finality hint or advancing the best head is insufficient.
Topology projection errors preserve the accepted policy. Applied transitions reclassify existing
connections; excess peers are marked for retirement and retain native ownership until real closure.

The policy supplies desired UP0 eligibility from accepted grid memberships. Native connection
closure, automatic dialing and dispatch integration remain required subsequent runtime work.

Completion checks: independent reservation/duplicate/count oracles, authenticated TLS integration,
finality versus best-head/elapsed-time cases, unequal rosters and topology failure atomicity.

Local checked ARC/release witnesses include authenticated TLS validator priority over builder ALPN,
duplicate rejection, actual native close/release, finalized reclassification, and ordinary-peer
refusal while a reserved builder slot remains usable. Pure policy checks cover independent copy
ownership, occupied/invalid/self/null identities, reservations, grid selection, explicit old/new
finality, delay for E12/E90, malformed chapter atomicity and retiring-role accounting. Slot-order
reclassification preserves the original builder request when validator membership expires.

`make unit SUITE=jamnp_topology` and `make unit SUITE=jamnp_validator_admission` pass with
checked ARC/release lowering; `make format` passes. Boundary cases also cover future best heads,
finalized descendants and skipped epochs at the maximum uint32 slot. Runtime controllers must
provision the validator budget for their complete required identity union before claiming full
validator connectivity; these explicit resource-policy APIs do not infer that operational choice.
