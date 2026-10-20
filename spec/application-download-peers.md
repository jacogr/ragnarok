# Authenticated download peer catalog

## Scope and authority

Bind the [joined session](application-download-session.md) to concrete outgoing
Transport owners. Preserve JAMNP-S `439c45aad135dc654b3de6f56d7d694fd02b7aa8`,
its identity/CE 128 rules, and existing GP/vector pins. Use the existing loopback
Transport endpoint API; this adds no address-discovery, wire or consensus rule.

## Contract and completion tests

One non-copyable catalog owns at most sixteen fixed-address outgoing transports.
Configure an explicit positive identity capacity once. Register nonzero local
peer IDs, fixed expected Ed25519 keys, endpoint and TLS/ALPN inputs. Reject ID/key
aliases and quota/endpoint failures before opening native resources. Identity
associations persist across retirement; reconnecting an ID requires the same key.
No peer IDs or certificates supplied by a network response choose a target.

The production verification callback applies the existing JAM identity checks and
exact expected-key pin. Ready requires successful identity verification, native
handshake success and one currently retained connection. Lifetime authentication
counts cannot revive a closed connection. Ready-peer enumeration returns a fresh
bounded copy. Native callback slots remain at stable addresses through teardown.

Request a stream only for the exact admitted session token's authenticated peer.
Retain the session pointer/token before opening, since open callbacks may execute
synchronously. Permit only one outstanding pending/open stream across the catalog.
Check locally opened direction, token, peer and handle before routing. Refused or
unsolicited opens are aborted; selected binding failures remain inspectable after
close. Pending opens retain their mapping until native callback/transport retirement.
A late refused open cannot attach to a replacement attempt. The host keeps borrowed
sessions alive until catalog retirement and aborts stalled pending opens by retiring
the peer; no asynchronous-open timeout is inferred from the bound-stream deadline.

Poll each retained endpoint nonblockingly once per caller tick. Bound-stream expiry
uses the existing controller deadline. Retirement closes the native engine before
clearing callback context and cannot publish or execute a block. Complete Ready
input survives ordinary close; unbound cancelled input still requires the host's
explicit session discard/acknowledgement. Explicit catalog close is mandatory
before destruction and is idempotent. This catalog owns no Services or adoption
outcomes and establishes no finality claim.

Test pinned and wrong-key TLS, two independent peer identities/targets, fresh ready
lists, invalid/duplicate/capacity registration, pre-auth and retired-peer refusal,
selected real CE 128 transfer, invalid binding policy and retry after actual close,
retirement during connection/stream work, genuine deferred preparation/adoption,
zero callback hashing, native-close ownership, ARC and compiler/result guards.

## Verification

Local macOS verification with pinned Nimony/ARC, checked optimized Clang/LTO:

- `make unit SUITE=application_download_peers` passes two real TLS identities,
  observed wrong-key rejection, copied ready lists, actual target selection,
  invalid-policy binding refusal/close/retry, exact bound-stream expiry, sibling
  isolation, native retirement and deferred guest preparation/canonical adoption.
  Native callbacks perform zero observed Blake2b calls. Its 1,000 real endpoint
  open/close cycles retain 8,804,448 occupied bytes before and after.
- Affected `application_download_schedule`, `application_download_session` and
  `application_block_download` suites pass after native restacking onto master.
  Each retains unchanged occupancy across 1,000 cycles. The scheduler/session
  report keys use the new distinct ARC identities while their evidence filenames
  retain the suite names required by the launcher.
- Two privacy probes, the peer-ID/key nominal rejection and actual composite-copy
  lowering rejection pass. Default/missing-result and unclosed-native-owner runtime
  guards pass with exact contract diagnostics, plus real explicit-close success.
- All 102 affected native, verification and inventory harness tests pass. Inventory
  passes with 230 native suites, 161 failure families and 2,027 declared probes.
  Pinned Nim/Rust formatting, local feature links and whitespace checks pass.

Evidence remains under `build/download-peers-*` and
`build/tests/native/selected/`. These are local checks; exact-head Linux/full CI
remains separate evidence and is not requested by opening this PR.

## Remaining work

Command-loop policy/endpoint configuration and execution workers remain open.
The catalog supplies concrete authenticated transport selection to the joined
session; no production synchronization loop, serving policy or fork choice is
claimed. M1 framing remains complete; full state serialization/JAM parity,
persistence and full/light databases remain open.
