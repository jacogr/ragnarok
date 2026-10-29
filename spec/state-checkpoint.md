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

`src/lib/atomic/file.nim` owns the common synchronous file-sync/rename/directory-sync
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

## Shared bounded byte reads

`readBoundedFile(path, ByteLimit)` shares the same fixed-chunk ceiling-plus-one
reader without interpreting a checkpoint or generation record. Private
`BoundedFileResult` alternatives expose bytes only after true EOF and descriptor
retirement. Raw empty files are successful; higher-level formats keep their own
nonempty/header/consumption rules. State loading maps raw lifecycle failures
exactly, then invokes the unchanged strict full-map decoder. No mutable file
storage or descriptor escapes; successful outputs survive later replacement.
The reader opens with nonblocking/close-on-exec flags, checks the opened inode
is a regular file, and refuses FIFOs/devices/directories before reading. File
size metadata never controls allocation. Regular-file storage latency remains
synchronous; this does not claim a wall-clock I/O deadline.

Raw-file tests cross chunk boundaries, check binary/empty/exact/short/max limits,
invalid/missing/directory paths, output mutation/retention and 1,000 read/refusal
ARC cycles. The complete-state file suite remains the affected integration control.

## Schema-independent file ownership

`AtomicFileWriter` now owns the common copied path, stable lock inode and explicit
retirement contract. Its bounded raw read/replace methods support generation and
light-state control records without a complete-map API. Closed reads expose no
bytes, closed writes return `Uninitialized`, and the existing nonblocking contention,
0600 SDK creation, close-on-exec lock and no-lock-inode-deletion rules remain.
`CheckpointWriter` is an independently noncopyable composite facade: its private
native child cannot bypass full-state encoding or independently trusted-root reads.
No canonical graph is retained by either owner between calls.

Raw ownership tests cover binary/empty control records, path mutation, contention,
reopen, short-budget rollback and 1,000 ownership cycles. The state-facing owner
suite retains real permissions, forked contention and its own 1,000 ARC cycles;
privacy, lifecycle and actual lowering checks cover both resource types.

## Local generation/head records

`src/state/checkpoint/head.nim` defines exact `RAGNAROK-HEAD-V1\n`, uint64 little-endian
generation, one-byte slot (0/1), complete root (32 bytes), then Blake2b-256 of all
preceding bytes. The fixed extent is 89 bytes. This is local control metadata, not
JAM state or a protocol timeslot. Unknown versions, other slots, prefixes, trailers
and checksum failures expose no initialized metadata. The checksum detects accidental
corruption; it does not authenticate chain authority or defend against replacement
by another valid record. State restoration still requires an independently trusted root.

Default heads remain uninitialized. Explicit constructors preserve nominal generation
and root domains; successor construction changes slots and checks uint64 exhaustion
before incrementing. Encoding checks the fixed byte ceiling before allocating. Native
checks include a Python hashlib known-answer checksum, every prefix and every octet
corrupted, zero/max generations, retained output and 1,000 ARC cycles.

## Locked exact-slot recovery

`CheckpointBank` owns `prefix.head.lock` through a private raw file writer and an
independent copied slot prefix. Explicit close and an independently checked
noncopyable composite contract apply. Every cooperating bank holds this one lock
across selector and slot reads; one host thread serializes methods and preserves
the directory namespace. A head selects exactly `prefix.0` or `prefix.1`.

`selectedHead` inspects at most 89 bytes and grants no chain authority. `restore`
first checks that selected metadata agrees with an independently trusted caller
root, then strictly decodes only the selected complete-map file against that root
and caller resource ceilings. Missing/corrupt head, missing/wrong selected slot,
other intact slots and temporary siblings never trigger an implicit fallback.
Default/closed owners expose no candidate; all format reasons remain guarded.
Successful restored maps survive later disk changes and are not retained by the bank.
This read-only increment does not initialize or advance a bank; durable two-file
publication and explicit recovery decisions follow. Native tests cover each refusal,
contention/reopen, copied paths and 1,000 lock/read/restore ARC cycles.

## Recovery synchronization before reuse

`syncAtomicFile` synchronizes an already visible regular file, retires its descriptor,
then synchronizes and retires its actual parent directory descriptor. The owned raw
writer exposes this only while its cooperative namespace lock is active. No bytes or
paths are replaced. Every native/kind/retirement failure refuses success; a directory,
FIFO or device cannot become a successful persistence file. File size is irrelevant.

This supplies a recovery barrier before reusing an older transaction slot after
startup or uncertain selector publication. A visible selector must be made durable
before overwriting data that an older durable selector could still reference.
It does not authenticate content or itself decide whether a head should be adopted.
Native checks cover binary/empty files, missing/invalid/directory/FIFO paths, default
and closed ownership, preserved exact bytes and 1,000 repeated sync/refusal ARC cycles.
Real local fsync success is not a simulated power-loss or failed-directory-sync witness.

## Explicit absent-head bootstrap

`initialize` accepts an initialized complete snapshot and an explicit slot byte ceiling.
It preflights both encodings, accepts only actual selector absence under the bank lock,
durably publishes slot zero and only then publishes generation-zero metadata. A selector
of any existing kind (including malformed files, directories and dangling symlinks)
returns `AlreadyInitialized`; no automatic reset or repair is attempted. Explicit
bootstrap may replace unselected orphan slot data, never an existing selector.

A staged file whose directory sync is uncertain returns `StagedUnsynced` without
writing a selector. A selector rename with uncertain directory sync instead returns
`PublishedUnsynced`; neither grants a head payload or permission to adopt state.
Pre-selector failures leave no selected generation. Successful initialization
exposes the exact committed head; subsequent restoration still requires independent
root authority. No canonical snapshot is retained. Production preserves the selector
and lock namespaces; test-only teardown is not an automatic recovery policy.

Native tests include default/closed/invalid inputs, actual slot rename failure,
unchanged existing head/data on reinitialization, malformed/directory heads and
1,000 synced bootstrap/refusal/restoration ARC cycles. Power-loss and uncertain
sync behavior need separate evidence.

## Expected-head two-slot advancement

`advance(expectedHead, completeSnapshot, slotByteLimit)` compares all current
selector fields (generation, slot and complete root) with the explicit caller token.
A mismatch is `StaleHead`; an absent selector never bootstraps implicitly. This is
a local compare-and-publish token, not proof of a valid chain transition. The caller
retains responsibility for candidate authority and canonical adoption.

After candidate/header preflight and checked generation advancement, the writer
synchronizes the currently visible selector and parent before overwriting the
inactive slot. This barrier also covers startup and a prior visible-but-unsynced
head. It then durably publishes the inactive complete checkpoint and only then
atomically publishes the new selector. Slot uncertainty returns `StagedUnsynced`
without changing the selector; head uncertainty returns `PublishedUnsynced` with
no successful successor payload. Every later advance rechecks and resynchronizes
the actual visible selection. The owner caches neither a head nor a canonical map.

Tests verify both slot alternations, exact prior-file preservation, every stale
field, default/closed/invalid/ceiling/exhaustion refusals before writes, real
inactive-slot rename rollback and 1,000 advance/stale-refusal/restore ARC cycles.
Selector short-write rollback and uncertainty require separate native witnesses.

## Real two-stage write rollback

A forked test writer uses child-only `RLIMIT_FSIZE` and a nonallocating SIGXFSZ
handler. Three ceilings force zero/partial inactive writes; three ceilings allow
the entire empty candidate checkpoint to become durable but force partial selector
writes. Exact and ample selector ceilings publish normally. Setup/signal/process
failures have separate verdicts and cannot substitute for expected typed I/O refusal.

Child and joined-parent observations verify the correct selected map; the parent
also checks exact old selector/data bytes, presence of fully staged orphan data
only when the stage succeeded, and no partial canonical inactive file otherwise.
Removing known files then successfully removing the dedicated directory proves
operation temporaries were removed on the functioning test filesystem. No live
lock owner crosses fork, every child closes its own owner, and forked ARC memory
is not reported as parent allocator-release evidence. This covers pre-rename
write failure, not power loss or a post-rename directory-sync failure.

## Exclusive detached checkpoint transfers

`prepareFullCheckpoint` encodes one complete snapshot into a private noncopyable
`PreparedCheckpoint` whose success alternative owns independent bytes and a scalar
complete root. Default/refused alternatives carry only the original codec reason.
No source snapshot alias survives preparation, and no mutable buffer accessor exists.
Successful root/size access is guarded. Explicit move transfers the sole prepared
owner and resets its source; actual ARC lowering rejects implicit copies.

Prepared publication writes exact bytes through the existing bounded atomic file
primitive and never touches the retired source graph. It preserves native publication
uncertainty; failed/default prepared owners authorize no I/O. Preparation is synchronous
computation work, suitable for startup or an already permitted computation worker.
The detached owner can later move to a bounded I/O worker without freezing all aliases
of the live canonical complete map under plain ARC. No background worker is added here.
Native witnesses cover source retirement, exact/short publication, moved/default/refused
owners, unchanged published bytes and 1,000 prepare/move/release ARC cycles.

## Prepared bank publication

Bank initialization/advancement overloads borrow an exclusive `PreparedCheckpoint`
through the synchronous call. Codec status and any narrower publication ceiling
are checked before writes; the prepared scalar complete root supplies new head
metadata. No original map is read, re-encoded or retained. The buffer stays usable
for explicit synchronous retry, while moved-from/default/refused owners cannot write.

Snapshot overloads now prepare bytes and delegate to this same transaction, preserving
their original head/source error ordering, counters, locking, old-head resynchronization
and stage/selector uncertainty distinctions. Worker offload can transfer the sole
prepared owner; it need not borrow the canonical state graph. Native tests cover
retired sources, exact/short ceilings, default/moved/closed owners, unchanged prior
files and 1,000 prepared advance/restore ARC cycles. Existing snapshot bootstrap,
advance and real kernel write rollback suites remain affected integration controls.

## Regular lock-inode admission

Raw and composite checkpoint owners open lock paths with `O_NONBLOCK` and SDK
`O_NOFOLLOW`, then require the opened inode to be regular before attempting advisory
locking. FIFO/device/directory/symlink lock paths refuse without adopting ownership,
following a link or changing an existing inode. Nonblocking FIFO open plus kind
validation cannot wait for another FIFO peer. Ordinary regular lock-file contention,
0600 creation and stable inode preservation remain unchanged.

Tests use real FIFO/directory/regular-target and dangling symlink paths, ensure the
refused inode/target is preserved, reacquire normal ownership after cleanup, and
repeat 1,000 special-file refusal/release ARC cycles. Storage latency for real regular
files is still synchronous; these flags do not promise a wall-clock I/O deadline.

## Scalar verification of a selected checkpoint

`CheckpointBank.verify(expectedRoot, limits, byteLimit)` reads one bounded selector
and exactly its selected complete map. It applies the same independent-root,
canonical decoding and store-policy checks as restoration, but returns only the
captured head after all temporary bytes and complete-map owners retire locally.
The caller supplies trust; local metadata is never its own authentication source.
Both restore and verify share selected-map validation without rereading the head
or scanning orphan slots. Failure preserves typed head/codec reasons and exposes
no usable scalar receipt. Native witnesses cover exact selection, wrong trust,
byte/map ceilings, malformed or missing selected data and repeated temporary map
release, preserving exact on-disk bytes on read-only success/refusal.

## Published complete-map checkpoint replay

The checkpoint replay suite uses the existing independently hash-checked fourteen
published complete mappings from seven pre/post pairs. A shared native fixture
reader serves both storage replay and checkpoint replay without changing fixture
preparation or pins. Every original key/value, root and node count is checked after
checkpoint restoration. Exact re-encoding, independently supplied roots, exact and
one-below byte/item ceilings and detached preparation are checked for each mapping.
This is complete-map persistence evidence; it does not execute those blocks or
establish whole-block JAM parity.

## Published bank generation replay

Seven original pre/post map pairs now cross real bootstrap, close/reopen,
expected-head advancement and recovery against independently published roots.
Every original key/value, root and node count is checked. Exact old/new slot bytes,
stale-selector refusal and selected-file corruption are checked without allowing
an intact orphan/older slot to substitute for selected state. Repair is explicit
in the test; production recovery never scans or rewrites data implicitly. These
local process-restart witnesses do not simulate power loss or whole-block execution.
