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

## Complete envelope recovery

`decodeRecoveryCheckpoint` restores the existing canonical application envelope
against independent expected context and explicit map/byte ceilings, then binds
its complete map to the supplied sealed header. Default trust refuses first.
Selected context/identity/checkpoint failures remain available only through the
guarded EnvelopeFailure alternative. No decoded state escapes a subsequent header
refusal, and success owns both map and header independently of input buffers.
Native checks cover every envelope cut, independent context variants, narrow byte/
map policies, header mismatch, every original key/value and repeated release.

Local envelope and affected binding suites pass under checked ARC. Envelope
release retains 20,704 bytes before/after 1,000 cycles; binding retains 47,728.
Four runtime refusal cases, genuine success/error controls, four private-result
compiler probes and source-owned inventory pass. Logs use `build/recovery-envelope*`.

## Bounded selected-file recovery

`loadRecoveryCheckpoint` refuses absent independent trust before opening a path,
then uses the existing bounded regular-file/true-EOF/checked-close application
envelope loader and exact head binder. FileFailure retains precise native, byte,
context and checkpoint reasons. Recovery is synchronous startup work, reads only
the selected file, and never repairs corruption, scans alternatives or widens
limits. No file or canonical graph is changed on refusal.

Local selected-file native verification passes with 28,560 occupied bytes before/
after 1,000 full recovery cycles. Five runtime refusal cases, genuine success/
error controls, all five private-result compiler probes and inventory pass.
Evidence is under `build/recovery-file*`; CI remains unrequested.
