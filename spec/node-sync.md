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

The repository retains its finite CE128 commands and separate bounded Tiny host. The continuous
full-state host described below is a dependent increment; adapting the Tiny authoring call remains
the next layer. Existing finite commands do not acquire synchronization authority from completion.

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

## Continuous full-state host

`quic/current_sync.nim` keeps `Services` and the existing dispatcher at fixed addresses until
explicit joined close. `sync-current` uses the same explicit endpoint/current-download-policy and
full-state startup controls as `download-current`, runs until SIGINT/SIGTERM, and refuses a finite
`--download-blocks` total. No whole-run block count or duration is reserved. `--net-timeout-ms`
continues to bound up-front ancestor acquisition; current policy attempt/stream deadlines remain
independent. On-demand ancestry retains its original child deadline and stops on interruption.
A continuous acquisition round is capped by `--download-discover-ancestors` and the retained input
count/byte ceilings; the lifetime number of imported children is independent of that cap.

`--sync-source-age-ms` (default 30000) bounds the age of an actual UP0 message, and
`--sync-reconnect-ms` (default 5000) delays idle replacement of missing/expired endpoints.
Both accept 1..3600000 milliseconds. Polling an unchanged snapshot never refreshes its age.
Reconnects preserve the exact identity pin and require an actual new handshake. Exhausted finite
retry plans remain unsynchronized and renew only on a later delayed host turn; empty replies and
invalid blocks never create local progress. Caught-up hosts keep polling discovery without issuing
another CE128 request. A later target revokes readiness before a new acquisition turn.

The fixed independently configured complete-state checkpoint is the local UP0 anchor when the
view has no separately selected finalized owner. This is a local trust assumption, not a network
finality proof: imports never advance that anchor or manufacture finalized view entries. Remote
finalized fields remain peer claims and cannot replace the original full-state anchor.

After a consumed installation receipt, the host compares the actual canonical hash, parent and
slot before acknowledging one imported block. It retains a contiguous newest-first ancestry window
under the existing independent header-count and byte limits, evicting only the oldest suffix.
Total imports therefore do not grow retained context. Still-advertised exact target receipts may
survive that header eviction, bounded by each source's leaf cap. Unknown older forks and different
hashes at the same local slot block readiness; the host never rolls back or invents fork choice.
An old peer target is satisfied only by actual observed installation or retained canonical ancestry.

`CurrentSyncProgress` exposes copied `stage`, `localHead`, guarded `target`, `liveSources` and
`adoptedBlocks`; `fullReady` requires fresh explicit target evidence whose hashes have been reached and
no outstanding import. `lightReady` remains false: this host has no independent light authority.
The observation is current as of its host tick, so callers must not reuse an old copied readiness
value to authorize a later action. Status/RPC logging integration can consume these scalar fields
without borrowing canonical maps. A stopped command reports its confirmed imports, never “synced”.

The development current candidate pipeline still bounds supported execution features. Continuous
transport is not a production finality engine, fork reconciliation algorithm or proof of global
network completeness. Missing/pruned ancestry can remain explicitly blocked pending independent
reconciliation; a maximum advertised slot is only a download hint. Tiny participation will also
need a current-clock policy at its actual authoring call, supplied by the next layer.


Local completion witnesses for this increment: `sync_current` constructs 72 genuinely signed and
ordinarily admitted Tiny children at sparse slots through multiple epochs, then synchronizes a
separate complete-state owner over independent TLS UP0/CE128 bytes. It checks partial progress,
a target move during catch-up, repeated empty replies, invalid seals, delayed retry/reconnection,
exact canonical hashes and state roots, a two-header rolling window, source expiry, conflicting
claims, stream loss, fresh reconnect, clock regression and closed-source revocation. Its real
`runCurrentSync` foreground case receives SIGINT only after the peer observes the exact installed
header announcement; joined exit reports two confirmed imports and a journal restart matches the
expected complete state root. The native finite dispatcher/current command and CLI/options suites
remain affected consumer checks. Private progress and composite owner compiler rejections preserve
the readiness and callback-ownership boundaries.

The pinned UP0 handshake permits no unfinalized leaves while still carrying `Final` (JAMNP-S
lines 204–220). In that case the host uses the exact claimed finalized hash/slot as a download
hint. An empty CE128 response still establishes nothing: the independently anchored complete-state
pipeline must actually install that exact hash before readiness. The empty-leaf witness starts two
blocks behind, verifies zero-import non-readiness, imports both blocks, compares the exact state
root, and confirms that the canonical view still has no manufactured finalized entry or light trust.
