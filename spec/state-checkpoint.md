# Local full-state checkpoints

## Scope and authority

Preserve GP0.8.0 state keys, complete-map Merklization and pinned vectors. This
versioned local storage envelope is not a JAM wire format or full T(state)
serialization. Only an initialized complete `StateStoreSnapshot` can be encoded;
partial light-state storage needs a separate contract and database.

## Version one

Bytes are ASCII `RAGNAROK-FULL-V1` plus LF, then an eight-byte little-endian
entry count, the existing 32-byte complete state root, and sorted records. Each
record contains its 31-byte serialized key, an eight-byte little-endian value
length, and exactly that many raw value bytes. Present-empty values remain
records. Keys follow the store's strict lexicographic order. No native integer
width, padding, compression, alternate encoding or protocol fallback is used.

`encodeFullCheckpoint(snapshot, ByteLimit)` preflights total fixed overhead and
value bytes by checked subtraction before allocating the output. Both configured
and host sequence bounds apply. Default snapshots refuse; failures expose only
reasons. Successful output owns independent mutable bytes, while historical
snapshot inputs retain their exact immutable version. Encoding performs no
hashing, publication or disk I/O. Callers must respect any active worker lease.

## Completion checks and next layers

The native suite verifies exact empty/nonempty layout, fixed-width count/lengths,
sorted keys, copied root, every short output ceiling, exact/max ceilings,
independent output mutation, historical snapshots and 1,000 ARC release cycles.
Strict decoding/root verification, crash-safe file publication, startup recovery,
canonical head binding and separate light-state persistence follow in later layers.
M1 framing is complete; full state serialization and JAM parity remain open.
