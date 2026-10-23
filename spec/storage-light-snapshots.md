# Light proof-cache snapshots

Scope: a standalone local light-cache persistence format, distinct from every full-state storage
schema. It carries proof evidence rather than trusting stored lookup results. The caller supplies
both independently expected chain identity and trusted complete-state root on decode; neither is
learned from the snapshot. Authority for proof meaning remains pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` state Merklization M/B/L and the
[proof contract](storage-light-state-proofs.md). This format is not a JAMNP-S wire protocol.

## Exact local format and trust

V1 is ASCII `RAGNAROK-LIGHT-CACHE-V1\n`, 32 chain bytes, 32 root bytes, E8 proof count, followed
by strictly ascending unique 31-byte query keys. Each query stores E2 path-node count, E8 raw-value
length, that many canonical 64-byte root-to-terminal nodes and then the raw value. A final 32-byte
Blake2b-256 checksum commits every preceding byte. Counts/lengths are fixed little endian. There
is no alternate schema, padding, ignored suffix or fallback. Empty proof sets still bind chain/root.

`prepareLightSnapshot` accepts unsorted unique key/proof inputs, bounds all extents, verifies every
proof at the supplied trusted root, and returns an opaque immutable prepared snapshot with canonical
bytes and an admitted cache. Byte extraction copies; cache extraction retains immutable state.
`decodeLightSnapshot` checks exact mode/version, independently expected chain/root, bounded complete
shape and canonical query ordering before hashing or allocating proof buffers. It checks the outer
checksum, reconstructs bounded proof inputs and independently verifies every proof before returning
a cache. An attacker who recomputes the file checksum cannot authorize a different value or root.

Complete-snapshot entry/value ceilings apply independently of future cache mutation-batch ceilings.
Construction may restore more entries than an ordinary batch allows, including a read-only cache
with zero write allowance; the returned cache retains the caller's original exact policy. Node
counts remain at most 249 per proof. All host descriptor extents, aggregate raw bytes and complete
encoded bytes are checked before allocation/narrowing/addition. Decode performs a complete bounded
shape pass before checksum/proof work, so a truncated tail exposes no decoded prefix or partial cache.

The outer checksum detects corruption, not finality, root provenance or chain authority. Identity
mismatch is explicit and never triggers conversion or opening a full-state store. Proof failures
retain their cache-level reason; primitive refusal is BackendFailure. Defaults and failures expose
no snapshot/cache. Allocation exhaustion remains fail-stop. Encoded bytes, decoded transport and
verified cached bytes can coexist during bounded preparation/restoration; logical byte ceilings
are not an RSS cap. No application/startup/consensus integration is added.

## Completion checks

`make unit SUITE=storage_light_snapshot` covers canonical unsorted-input round trips; authenticated presence/absence and unknown
keys; empty-root/empty-cache images; read-only restored mutation policy; strict truncation/trailing,
count/node/value/host-limit handling; identity mismatch before hashes; checksum corruption; rechecksummed
false proofs; full/light format refusal; provider-prefix refusal; immutable input/output ownership
and 1,000 exact ARC success/failure/recovery lifetimes. Runtime/compiler guards protect prepared
owners, selected failure reasons and successful extraction. Existing cache/proof suites supply
consumer regression evidence.

File publication, directory leases and explicit durability are the next storage layer. Trusted-head
selection, persistent schema migration and startup/consensus integration remain separate contracts.
M1 framing is complete; complete state serialization and whole-block JAM parity remain open.


Local checked macOS ARM64 evidence uses pinned Nimony ARC/Clang release with bounds/assertions
preserved. Four selected snapshot/cache/proof/producer suites pass, including 1,000 snapshot
success/refusal/recovery lifetimes returning to 848/848 occupied ARC bytes. Runtime guards use
ThinLTO and exercise actual dynamic fields rather than compile-time array lengths. Heavy Linux
verification remains separate; PR Smoke runs automatically. Source/build/diagnostic evidence is
retained under ignored `build/storage-db27-*`.

The independent golden case uses zero chain/root and two empty proofs for keys beginning 0 and
128, with their remaining 30 bytes zero. Its canonical image is 210 bytes: a 96-byte header,
two 41-byte query entries and checksum `f3326bbb483e608646ae4a0b35ea20d4f3c2259d7fd76875aff585379f4a7394`.
That checksum was independently computed with Python hashlib Blake2b-256; the native suite checks
every body/checksum byte. An empty proof-set image is 128 bytes, including its checksum.
