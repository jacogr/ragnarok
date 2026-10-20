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
Crash-safe file publication, startup recovery,
canonical head binding and separate light-state persistence follow in later layers.
M1 framing is complete; full state serialization and JAM parity remain open.

## Strict restoration

`decodeFullCheckpoint(input, StateStoreLimits, ByteLimit)` first checks the exact
version, fixed overhead, full-width counts/lengths, strictly increasing keys,
complete consumption and entry/per-value/aggregate byte ceilings. No record is
allocated until the entire borrowed input passes structural/policy checks. Input
must remain stable for this synchronous call. It then owns raw entries, constructs
the complete store under the supplied trie/node ceilings and compares every byte
of its recomputed root with the envelope root. Only complete success returns a
store; no partial map or root is published. Restored stores inherit the caller's
explicit subsequent mutation budgets. This verifies internal integrity, not an
externally trusted chain head or adversarial file authenticity.

Native checks cover exact round trips, every truncated prefix and short input
ceiling, all single-byte tampering, duplicate/reversed keys, trailers, uint64
length attacks, all store ceilings, source mutation, independent branches,
empty maps and 1,000 successful/refused restoration ARC cycles.

## Bounded file loading

`loadFullCheckpoint(path, limits, byteLimit)` is synchronous startup work. It
rejects empty/NUL-containing paths, opens one descriptor and closes it on every
return. Fixed 4 KiB reads request at most remaining capacity plus one detection
byte; no file-size metadata is trusted. Native read errors differ from EOF, and
bytes beyond the explicit/host ceiling are never retained. Only EOF permits the
strict decoder to run. File failures have no state payload; decoder failures
retain only their typed inner reason. Successful stores survive later file
replacement/deletion independently. Concurrent in-place file mutation has no
consistency guarantee; root verification remains mandatory. Atomic writer
publication follows next. These APIs are not called from networking callbacks.

Real-file native tests cross a read chunk, enforce exact/short/zero budgets,
reject missing/directory/invalid paths and malformed files, preserve inner policy
errors and retained owners, and repeat successful/refused loads for ARC cleanup.

## Synchronized atomic publication

`saveFullCheckpoint(path, snapshot, byteLimit)` encodes before opening filesystem
resources, creates a unique 0600 sibling with standard POSIX `mkstemp`, handles
short writes, syncs and closes the file, atomically renames it over the destination,
and syncs the parent directory. Success retains the exact source snapshot. Every
pre-rename failure closes and attempts to remove its own temporary, preserving
the previous destination. A cleanup I/O failure or process crash can leave an
orphan sibling; readers never select temporary filenames. A failed parent sync after rename returns `PublishedUnsynced`: new
complete bytes are visible, while durable publication has not been established.
Callers serialize writers and keep directory names/current working directory stable
during the synchronous operation. This is one file's publication, not a multi-file
transaction or an externally authenticated chain-head recovery protocol. Storage
hardware/filesystem synchronization guarantees still govern power-loss behavior.

Real native tests verify initial publication/replacement, exact load round trips,
preflight rollback, missing parents, a real post-write rename refusal, retained
owners and 1,000 file-plus-directory-sync publication ARC cycles. The small libc
bindings compile against standard headers; compiler/runtime/dependency pins stay
unchanged. System-call failure injection and recovery policy follow in later layers.

## Independently trusted restoration roots

The decode and file-load overloads accepting `StateRoot` require the recomputed
complete root to match an independently trusted caller commitment. A different
map with a perfectly valid internal envelope/root still returns `RootMismatch`
without exposing its store. Ordinary structural/resource/I/O refusals keep their
original reason. Existing overloads remain useful for internal integrity tooling;
they do not authenticate a state source. The trusted root must not be derived
from the same untrusted checkpoint. No assumption is made that a block header's
parent-state-root is its own post-state root. Chain-head trust and canonical
recovery require their own application binding.

Native tests restore matching and empty roots, reject intact alternate maps,
preserve failed-file/format/limit reasons, retain earlier restored owners across
file replacement, and release 1,000 accepted/unauthorized map pairs under ARC.

## Real kernel write-refusal controls

A dedicated native suite forks seven isolated child writers and changes only each
child's POSIX `RLIMIT_FSIZE`. Real zero/partial/final-byte write refusals must return
`IoFailure`, remove their own temporary on the functioning test filesystem and
preserve exact prior bytes/root. Exact and one-byte-ample ceilings must publish the
new complete checkpoint normally. Child and joined-parent observations separately
verify the authorized result. Setup, signal-policy and process failures are distinct
failures, not accepted substitutes. No production sleeps, failure hooks or compiler
changes are used. This witnesses ordinary write rollback, not power-loss recovery
or simulated file/directory-sync failure. Forked-process cleanup is not presented
as a cross-process ARC occupancy measurement.

## Explicit cooperative writer ownership

`CheckpointWriter` owns an independent copied destination and one stable sibling
`.lock` descriptor. Opening is nonblocking; actual lock contention returns `Busy`
and other native failures return `IoFailure`. Live owners cannot change paths.
Save/load delegation requires an active owner, and every owner-bound load requires
an independently trusted complete root. No canonical state alias is retained
between calls. One host thread serializes methods on each owner.

Call `close` explicitly before destruction. Copy/duplication is forbidden. Close
unlocks and closes once, disarming even on a reported retirement error; callers
must handle such OS errors conservatively. Lock files remain in place across
closes: deleting/replacing an in-use lock inode would bypass cooperative exclusion.
Advisory locking requires all writers to respect this namespace; it does not
protect against arbitrary filesystem mutation or grant canonical chain authority.
Native path lengths are checked before suffix arithmetic, and NUL paths refuse.

Tests exercise exact 0600 lock permissions under a controlled/restored process
umask, independent owners, nonblocking forked-process contention,
reacquisition, source-path mutation, anchored delegation, closed/default access,
and 1,000 joined-host ownership ARC cycles. Publication uncertainty still reaches
the caller through `PublishedUnsynced`; recovery policy follows separately.

## Shared atomic byte publication

`src/lib/atomic_file.nim` owns the common synchronous file-sync/rename/directory-sync
sequence with an explicit byte ceiling and exhaustively typed outcomes. It writes
exact raw bytes, including an empty file, without interpreting state, roots or
control metadata. Borrowed input remains stable for the call. The checkpoint
adapter still encodes complete state first and exposes its exact snapshot only
after raw publication succeeds; every error maps without losing durability status.
This permits generation/control metadata to share the same publication discipline
without being embedded in a fabricated JAM state mapping.

Native checks cover binary/empty exact writes, preflight and real rename rollback,
all path/ceiling boundaries and 1,000 synchronized ARC cycles. Existing full-state
publication and real kernel short-write controls remain required affected consumers.
