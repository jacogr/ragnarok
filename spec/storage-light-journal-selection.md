# Light journal selection and anchor schema

This standalone local format explicitly separates append-only light proof-cache persistence
from the existing whole-image light-file cache and both full-state schemas. Caller-supplied
chain identity, complete trusted root and admission limits remain external. No protocol pin,
JAM root, startup wiring or application interface changes here.

`prepareLightJournalManifest` constructs checked scalar metadata only from an authenticated
prepared light snapshot and a positive physical epoch. Its local baseline sequence may be zero
for a new journal or the last completed sequence at compaction. Epoch and sequence are separate
unsigned 64-bit domains. Both may reach their maximum; callers must check before advancing.
The manifest retains no image buffers or predecessor chain. Its private fields have guarded
read-only getters and `.bytes` returns detached mutable transport.

## Exact local layouts

Integers use fixed-width little endian. The 27-byte magic
`RAGNAROK-LIGHT-MANIFEST-V1\n` starts the 171-byte `CURRENT` manifest. Offsets are:

| Offset | Bytes | Field |
| --- | --- | --- |
| 0 | 27 | Magic including final newline |
| 27 | 32 | Independently selected chain identity |
| 59 | 32 | Independently selected complete state root |
| 91 | 8 | Positive physical file epoch |
| 99 | 8 | Checkpoint baseline sequence |
| 107 | 32 | Exact canonical light snapshot checksum |
| 139 | 32 | Blake2b-256 of the preceding 139 bytes |

The selected checkpoint uses the existing canonical light snapshot format. Its checksum must
later be checked against this manifest during replay; parsing the selection alone does not
verify any checkpoint or proof.

The 98-byte journal anchor starts with the 26-byte magic
`RAGNAROK-LIGHT-JOURNAL-V1\n`, then the selected manifest checksum (32 bytes), its baseline
sequence (8 bytes), and Blake2b-256 of those preceding 66 bytes (32 bytes). The anchor exceeds
the managed journal primitive's minimum truncation extent. Validation accepts exactly one
complete anchor; the replay caller must pass its header slice separately from following frames.
The anchor's checksum detects corruption and its selection checksum prevents substituting
another epoch's journal. Neither checksum supplies consensus or root trust.

Manifest decoding requires exact width, exact magic, externally expected chain/root, nonzero
epoch and checksum. Anchor validation requires initialized selection metadata, exact width,
exact magic, exact selection checksum/baseline and its own checksum. No trailing-byte, old-image,
full-state or alternate-schema fallback exists. Structural, identity and capacity refusals
precede hashing or input-derived allocation. Incomplete selections and anchors are format
errors and grant no partial-tail repair authority.

Only successful tagged results expose completed data. Default metadata reports uninitialized;
all other getters require its private initialization authority. Default/failed result payloads
remain inaccessible. Encoding detached transport grants no unchecked metadata adoption path.

## Evidence and next work

The checked native suite matches independent Python `struct`/`hashlib` golden manifest and
anchor bytes. It covers every proper prefix, trailing data, short byte caps, zero and maximum
epoch/sequence, wrong caller identities, corrupt checksums, wrong anchors and baseline bytes,
full-state and old light-image schema confusion, and all four provider-refusal entry points.
Detached output and retained scalar copies remain isolated. One thousand scoped retirement
cycles return occupied ARC bytes to the same 2,176-byte baseline.

Nine runtime guard cases, eight independent positive controls and nine strict private-field
compiler rejections exercise the result and metadata boundary. Format and verification inventory
checks pass. Evidence is local macOS arm64 checked release using the repository-pinned compiler
and providers; exact-head Linux CI remains separate.

This layer does no disk I/O. Strict bounded replay, explicit partial-tail recovery authority,
append ownership and durability, compaction and reclamation follow as substantive storage
units. No successful prefix, selected current image or repair operation is implied by these
codecs. Existing M1 framing completion remains distinct from complete state serialization.
