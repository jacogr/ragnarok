# Strict light journal replay and explicit tail plans

This standalone storage layer verifies a journal selected by the distinct light-journal
manifest. It trusts only the caller's authenticated checkpoint and independently selected
complete chain/root. It changes no protocol encoding, state application, startup path or
full-state interface. The [selection schema](storage-light-journal-selection.md) and
[authenticated frame format](storage-light-deltas.md) define its exact transport.

`LightReplayLimits` separately bounds total journal bytes, frame count and each frame's bytes
and edit count. Checkpoint proof/image/write policies remain unchanged. Before replay, the
checkpoint must match the manifest's chain, root and exact snapshot checksum. The complete
anchor must validate against that exact manifest. Short or malformed anchors never grant
recovery authority.

`replayLightJournal` privately applies complete frames in strict sequence from the checkpoint
baseline. It checks remaining frame capacity and sequence exhaustion before parsing or proof
work. Every frame must match the current exact image checksum, caller identity and next
sequence; checksum, canonical body, proofs and successor checks all pass before the private
candidate advances. No predecessor-image chain is retained. Only a completely consumed journal
publishes a `LightJournalReplay`. A complete corrupt suffix, policy refusal, provider failure
or incomplete suffix exposes no successful prefix through the failed result.

The immutable result retains the last authenticated prepared snapshot, exact last sequence,
complete-frame count and complete byte extent including the anchor. An anchor-only journal is
valid, including a maximum baseline sequence. Any following frame at sequence exhaustion is
refused before an increment can wrap. Retained readers survive later replay and caller buffer
mutation; no mutable transport is retained.

## Explicit incomplete-tail planning

`planLightJournalTail` is a separate opt-in operation. A complete journal returns
`NotIncomplete`. A complete invalid frame, bad anchor, bad checkpoint, exhausted sequence or
exceeded budget returns its typed refusal without a plan. Only a nonempty incomplete next
frame can yield an opaque `LightTailPlan` retaining the fully authenticated prefix.

`IncompleteFrame` from the extent codec alone is insufficient. Available next-frame chain,
root, predecessor and sequence bytes must already match. The partial header's minimum possible
count and length must fit policy; declared complete fields must describe a possible bounded
body. Available edits must have valid tags and reserved fields, bounded node/value lengths,
strict key order and enough declared capacity for every remaining header and payload. A partial
key must admit a strictly larger completion than its predecessor. Extra declared body padding
is invalid. If a complete body has partial footer bytes, those available checksum bytes must
match. These checks reject already provable corruption without inferring missing bytes or
attempting to authenticate an incomplete proof.

The entire incomplete frame is excluded from the retained prefix. The plan grants no authority
to its proof bytes or candidate successor. It records the exact original journal extent, selected
manifest checksum and Blake2b-256 of all inspected journal bytes, including the partial suffix.
It retains no caller buffer. Its public prefix is an authenticated immutable reader and explicit
complete byte extent, not a durable publication receipt.

`validateLightTailPlan` requires the exact current manifest and exact original input extent and
checksum. Any changed, grown or shrunk input refuses; provider failure also refuses. An actual
repair owner must additionally hold the selected directory/journal lease, revalidate current
selection and held file identity, and truncate/synchronize only after these checks. This layer
performs no file I/O and provides no automatic repair, truncation or fallback. Checksums detect
local corruption and do not supply consensus trust or protection against deliberate collisions.

## Failure and ownership boundary

Default replay and plan values report uninitialized. All image, sequence, count, extent, plan
prefix and selection getters require private initialization authority. Only successful tagged
results expose completed data. Frame and selection causes have their own selected-alternative
getters; a failed result never contains a completed prefix or plan. Copying immutable replay or
plan values retains authenticated image ownership, with no mutable backing exports.

## Scoped evidence and remaining work

Checked native tests perform genuine absence-admit/forget/admit transitions at an independently
known empty complete root. They compare the final canonical image and retained source, check
every nonempty proper prefix of the final frame, and prove every short anchor refuses planning.
They exercise stale replay, wrong checkpoints/anchors, complete bad checksums, valid-checksum
bad proofs and wrong successors, malformed partial identities/tags/counts/lengths/node bounds,
reserved fields, body padding, duplicate keys and impossible partial ordering. Exact total,
frame and per-frame caps and maximum sequence baselines have boundary witnesses.

Plans reject exact-byte mutation, growth, shrink and another epoch selection. Every observed
replay and planning provider-call boundary is independently refused, including the complete-input
plan hash and partial-footer check. One thousand scoped complete/partial/refusal/retry cycles
return occupied ARC bytes to baseline. Fifteen runtime guard cases, ten independent positive
controls and ten strict private-field compiler rejections cover the public authority boundary.
Formatting and verification inventory checks pass. Local checked release evidence is macOS
arm64 with the repository-pinned compiler and providers; exact-head Linux CI remains separate.

The next substantial unit is a locked durable light journal owner with strict open and sparse
append. Held-file repair, process-crash qualification, compaction and reclamation remain explicit
follow-up work. Existing M1 framing completion is distinct from complete state serialization.

## Partial-field completion bounds

Partial planning checks whether available local fields can still have a bounded canonical
completion. Available count bytes must fit the frame's minimum edit extent and native proof/key
array capacities. Available little-endian body bytes must admit an integer between the required
fixed metadata and the permitted aggregate node/raw payload. Missing high bytes cannot excuse
a known low-byte residue that is impossible within those bounds. Node payloads contribute
64-byte units; raw-byte allowances determine the gaps between representable payload sizes.

Each available admit header must leave an exactly representable payload for its remaining
edits. Available key bytes must permit a strictly ordered completion with enough distinct
successors for every declared edit. These are local format checks; incomplete proof material
still receives no authenticated successor authority. Arithmetic is bounded before products,
rounding, offsets and conversions, with checked runtime contracts retained.

The `storage_light_partial_frames` native suite independently enumerates small count, node
and raw-byte combinations against partial count/body and admit fields, checks every proper
prefix of structurally possible multi-edit frames including their footer, and rejects exhausted
key space. Four saved native witnesses separately confirm refusal of impossible count capacity,
zero-edit body, partial body residue and raw-length metadata. The existing replay suite retains
its genuine proof transitions, provider failures and one-thousand-cycle ARC evidence.
