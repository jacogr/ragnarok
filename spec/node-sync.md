# Continuous node synchronization and participation readiness

## User scope and order

First implement normal-node peer target discovery and continuous catch-up. Then adapt Tiny
validator authoring to consume the same explicit readiness contract. This is distinct from
node logging: an idle queue, no connected peers, a successful handshake, an empty CE128 reply,
one imported block or a finite download-command completion never establishes synchronization.

Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and JAMNP-S
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, notably `vendor/jam-np/simple.md`
UP0 block announcements, message framing and CE128 block requests. No new wire protocol,
consensus finality rule, fork-choice rule or light-client trust authority may be invented.

## Trust and progress

Peer TLS authentication establishes a source identity, not block validity or finality. UP0
handshakes advertise leaf hash/slot pairs and a peer's claimed finalized hash/slot. All are
untrusted download hints. A full node must connect actual received blocks to its independently
configured genesis/checkpoint and execute ordinary complete-state admission/publication before
calling a target reached. A light node requires its own independent root/header trust and cannot
inherit a full-node readiness result or manufacture complete state from partial proofs.

Readiness is explicit and revocable: unknown/waiting, catching up, caught up, or blocked/conflicting.
It is tied to live authenticated target evidence, the exact canonical hash and slot, retired
in-flight imports, and source freshness. Disconnects, target changes, expiration and conflicting
claims revoke readiness. Same-slot/different-hash branches cannot be resolved using slot order.
Slot differences describe elapsed JAM slots, never a block count or finality distance.

## Implementation sequence and completion evidence

1. Bound and decode UP0 handshake/announcement messages; retain peer identity and live-stream
   provenance; expose copied discovery observations through the existing authenticated catalog.
2. Drive repeated CE128 requests and ordinary current full-state preparation/publication while
   preserving listeners, retries, cancellation and worker ownership. Refresh targets while caught
   up; retain bounded per-turn memory/work and ancestry across arbitrarily many batches.
3. Expose the scalar readiness observation to status/RPC and use it at the actual Tiny authoring
   call. A readiness label alone is insufficient if an authoring path does not enforce it.

Completion checks must exercise a node starting far behind (more than the former 64-child command
cap), target advance during catch-up, empty replies, no peers, stale peers, one-child partial
progress, conflicting hashes, invalid blocks, disconnected target sources, reconnect, bounded
memory and shutdown. Compare canonical hashes and complete state roots, not status strings alone.
Verify slot gaps independently of adopted-block counts. Full and light readiness are tested as
separate trust domains. Network parsers require truncation, noncanonical count, size/count/overflow,
duplicate leaf, malformed header, fragmentation/coalescing and unexpected FIN controls.

The current repository has finite CE128 downloads and a separate bounded Tiny host. Continuous
synchronization remains in progress; existing commands continue to report unknown rather than
imply synchronization while those paths are incomplete.

## Peer-discovery increment

`quic/announcements.nim` bounds UP0 messages, canonical GP compact leaf counts, complete sealed
headers, exact Blake2b header hashes and E4 message framing. Same-slot competing leaves remain
separate claims. `quic/announcement_stream.nim` routes a persistent UP0 stream independently of
CE128; callbacks only copy bounded bytes, while the host decodes/hashes at most one completed
message per peer/poll. Output contains detached encoded bytes rather than canonical ARC aliases,
so native polling can continue during an existing exclusive preparation lease.

The authenticated `CurrentDownloadPeers` catalog opts in through `enableAnnouncements` before
opening endpoints. `announcements(id)` returns an unavailable default until both real TLS
identity validation and a complete live UP0 handshake exist. The view contains only copied
peer claims and a per-stream message sequence. `incarnation(id)` changes on transport/stream
replacement, so repeated identical leaves on a new source cannot reuse old freshness evidence.
TLS/stream failure, reset, EOF, graceful drain and explicit retirement revoke available views.
`publishAnnouncement` queues an exact owned header only on the host after canonical publication;
it captures bytes and scalar claims before future worker/callback turns.

These APIs discover potential targets. They do not assert consensus validity, selected fork,
remote finality, complete synchronization, or participation readiness. Continuous validated
import and readiness remain the next dependent increment.

Verification uses independent literal wire expectations and Python-hashlib header hash values,
every strict message prefix, malformed/noncanonical counts, duplicate/oversized leaves, exact
header tails, all framing fragmentation widths, and real TLS source update/retirement/reconnect,
EOF, malformed-frame and wrong-key controls. Existing finite native current-download and dispatcher
suites remain required consumers; exact private-payload and composite-copy compiler rejections
preserve the API/ownership boundaries. All local results are macOS ARM64 on pinned October 28
Nimony; native Linux CI remains a separate verdict.
