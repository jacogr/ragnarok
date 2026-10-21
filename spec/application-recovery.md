# Trusted checkpoint startup recovery

## Authority and scope

The maintainer authorizes explicit operator-supplied trusted application checkpoint
identity and sealed header as a startup anchor, with exactly one retained head and
finality unset. Use the existing complete-map StateStore and application checkpoint
APIs. No trie/storage interfaces, disk-backed StateStore, durable-head transaction,
fork choice or finality verification is introduced. GP 0.8.0 equations and pins
remain unchanged; structural capture does not authenticate consensus validity.

## Complete-map/head binding

`recoverApplicationChain` requires initialized independent trust before map access.
It checks the complete posterior root, structurally captures the exact sealed header
under the trusted full parameter tuple, and compares its sealed hash and slot.
Header prior-state roots never substitute for posterior roots. Default maps,
malformed headers and mismatches expose typed reasons alone. Success retains the
exact immutable complete snapshot, preserving all inherited limits and independent
fork ownership. It creates one selected head, no ancestors and no finality.

Tests cover defaults, every header truncation, root/hash/time mismatches, exact
snapshot identity, complete profile retention, detached input ownership, inherited
write limits and repeated graph release. Startup envelope/file loading and CLI
integration follow as dependent layers. M1 framing is complete; full T(state) and
whole-block JAM parity remain open. Local evidence is separate from Linux CI.

## Binding verification

Local checked optimized Nimony/ARC native binding passes, including 1,000
recovery/release cycles with 47,248 occupied bytes before and after. Three strict
runtime extraction refusals and genuine success/nested-reason controls pass; all
three private-result compiler probes reject the intended field. Source-owned
inventory, pinned formatting and whitespace checks pass. Evidence is under
`build/recovery-binding.log` and `build/recovery-guards/`; no CI is requested.
