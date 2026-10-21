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

## Captured independent operator inputs

`captureCheckpointTrust` accepts separately operator-selected canonical identity
bytes and an exact hash-matching sealed header. A subtraction-checked aggregate
byte limit and existing 256 KiB header ceiling bound work before header copying.
Successful immutable input owners copy sealed bytes privately and expose fixed
identity only. Decode/file recovery consumes that same captured pair, with defaults
reaching MissingTrust before map or path access. No checksum grants authority: the
operator must select independent trusted inputs rather than extract metadata from
the untrusted checkpoint. No signature, ancestry or finality proof is inferred.

Local trust native verification passes, with 299,808 occupied bytes before/after
1,000 captured-input/complete-recovery cycles. Nine combined runtime refusals,
genuine success/error controls, eleven private-owner/result compiler checks and
inventory pass. Evidence uses `build/recovery-trust*`; CI is not requested.

## Separate bounded operator files

`loadCheckpointTrust` reads at most 238 identity bytes, checks exact canonical
identity before opening the header path, then bounds that regular-file read by
both the remaining aggregate ceiling and existing header ceiling. Shared private
header capture avoids rehashing identity. All descriptors retire before returning
the immutable owner; later checkpoint work never rereads either trust path.
FileFailure retains the native reason. Explicit operator selection supplies trust;
no checkpoint self-authentication, implicit repair or alternate-file scan occurs.

Local trust-file suite and affected memory-capture consumer pass. The 1,000-cycle
file/recovery witness retains 21,184 occupied bytes before/after; captured input
replacement and identity-before-header error ordering pass. Ten combined runtime
refusals, genuine controls, twelve compiler privacy checks and inventory pass.
Evidence uses `build/recovery-trust-files*`; CI remains separate.

## Explicit recovered Services startup

`Services.startRecovered` accepts only a successful opaque recovery result and
validated state-enabled options. It compares the full independently configured
chain parameter tuple before any listener opens, then installs the exact recovered
application pair. Default/refused recovery cannot fall back to configured genesis;
repeated start preserves live state. The component API preserves the restored
map's explicit policy, as the existing explicit-limits startup overload does; CLI
recovery must decode using its parsed policy. Close/restart keeps existing joins
and acknowledgement behavior. No ancestral link to configured genesis is inferred:
the operator-selected trusted anchor is the authority for this one-head restart.

Local checked Services recovery suite passes with 29,744 occupied bytes before/
after 1,000 aggregate lifetimes. Existing application Services startup/adoption
and checkpoint-capture suites also pass, preserving their own ARC evidence.
Focused module/test semantic checks, inventory and complete pinned formatting
pass. Logs use `build/recovery-services*`; exact-head Linux CI is separate.

## Real RPC selected-view verification

A real ephemeral loopback WebSocket checks a recovered anchor whose sealed hash
differs from configured genesis. Best block, posterior root, exact sealed bytes
and best subscription match the recovered owner. Parent lookup, finalized block
and finalized subscription remain unavailable; client info reports null finality.
No request replaces or mutates the map. Shared bounded socket controls preserve
the existing Services adoption suite's transport and listener-retirement witnesses.

Local real recovered-head RPC suite passes, and the original Services startup/
adoption suite passes with the shared socket controls, including 1,000 ownership
cycles at 141,936 occupied bytes before/after. Focused semantic checking and
source-owned inventory pass. Logs use `build/recovery-rpc*`; CI is unrequested.

## Atomic external recovery controls

The parser accepts `--state-checkpoint FILE --state-trust FILE --state-header FILE
--state-checkpoint-bytes N` only together and with existing explicit `--with-state`,
`--chain` and both mutation budgets. All partial subsets, duplicates, missing values,
disabled use and malformed/overflowing ceilings refuse atomically. Byte policy
retains uint64 including explicit zero; no listener is implied. Private guarded
getters expose only complete active requests. Service initialization requires a verified recovered owner for import intent,
preventing silent genesis fallback. Backend `--state-storage`/`--state-db`
names are reserved for db #1 and acquire no placeholder behavior here.

Local recovery and legacy option suites pass; the affected Services suite proves
parsed recovery intent cannot fall back to genesis and retains unchanged occupied
bytes through 1,000 close/restart cycles. Eight strict default/inactive getter
refusals, genuine positive controls, five private-option compiler rejections,
semantic checking and inventory pass. The pinned runtime checks conjunctions as
separate parsed/active assertions; exact diagnostics are recorded per origin.
Evidence uses `build/recovery-options*`; CI is unrequested.

## Configured checkpoint startup

Both public `Services.start` overloads dispatch complete parsed import requests
through bounded independent trust-file capture and selected checkpoint recovery
before service initialization. The normal overload supplies its exact parsed
mutation policy; the existing explicit-limits overload preserves its caller policy.
Any trust, byte/map, context/header or profile failure refuses without listeners,
file repair or genesis fallback. Active services reject repeated startup before
trust I/O. Trust input ceilings use the fixed identity and existing structural
header extent; checkpoint bytes use the separately required operator ceiling.
The production entry's help documents all four controls. This imports into the
existing complete in-memory store; db #1's local durable-head restart is separate.

Local configured-startup suite passes with 27,936 occupied bytes before/after
1,000 complete import/service lifetimes. The legacy service checkpoint-capture
consumer passes. The real production entry builds and its help exposes all four
controls; semantic checking, source-owned inventory and complete pinned formatting
pass. Evidence uses `build/recovery-startup*`; no remote CI is requested.

## Production executable import witnesses

The registered application_checkpoint_import E2E workload reuses pinned complete
checkpoint/identity/chainspec fixtures, then independently hashes a changed sealed
header and its exact local metadata. A real retained executable peer exposes that
imported hash, slot, posterior root and sealed bytes through an independent Python
WebSocket client; finality and parent remain unavailable. Both executable peer
shapes reject zero/short budgets and missing/malformed selected trust/header/map
files before readiness, preserving every input byte. Every child is bounded and
reaped. This covers process/startup integration, not consensus validity of the
operator-selected anchor or filesystem power-loss behavior.

The selected production executable workload passes real RPC and all sixteen
server/mesh startup refusals, with exact input preservation and reaped children.
Both E2E plan/completeness harness tests and inventory pass. Evidence is under
`build/recovery-executable*`; this is focused local process evidence, not a full
E2E or exact-head Linux CI verdict.

## Genuine resumed successor authority

A signed two-guest block is independently prepared and adopted through direct
execution and a fresh checkpoint-restored Services owner. Exact child identity,
complete posterior root/count and every key/value agree. A pre-recovery finalized
certificate is rejected as StaleState despite root equality; successful private
preparation publishes only on the later service tick. The retained imported parent
stays immutable, ordinary history grows to two heads, finality remains unset and
replay refuses without changing canonical state. Shared fixture startup retires
all temporary restored aliases before subsequent lease tests. No PVM or state
transition implementation changes are required.

Local signed-successor suite, focused semantic checking and inventory pass.
Evidence uses `build/recovery-successor*`; no full JAM/STF or Linux CI claim is made.
