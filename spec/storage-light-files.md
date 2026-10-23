# Durable light proof-cache files

This standalone storage layer persists the canonical image in
[light snapshots](storage-light-snapshots.md). It does not choose consensus roots,
change application startup, or expose a complete-state interface from partial evidence.
The caller supplies a separate directory and an independently trusted chain/root.

`LightFileCache` owns one directory-relative `LOCK` lease and requires explicit close.
Its private stable owner cannot be copied or duplicated; moved-from owners are closed.
Immutable cache handles obtained before close or later publication remain valid.
No IO runs asynchronously and no callbacks share the retirement authority.

The namespace contains the persistent regular `LOCK`, selected `CURRENT` light image,
and exclusive staging name `CURRENT.next`. Initialization creates a missing private
namespace. Opening requires the original lock and fully validates the bounded image
against caller expectations, including every lookup proof. It never scans alternative
files, selects a root from disk, creates a missing lock or accepts full-state bytes.

Initialization and publication accept only opaque prepared images with exactly the
owner's chain, root and policy. They stage all bytes, synchronize the file, atomically
replace `CURRENT`, and synchronize the held directory before returning
`FileAndDirectorySynced`. Opening verifies existing bytes but makes no new file-data
synchronization receipt. Cache state changes only after successful publication.
A root change requires another explicitly selected owner/namespace.

IO failure or publication uncertainty poisons an acquired owner: fresh reads and writes
return `RecoveryRequired` until explicit close and validated reopen. Previously retained
immutable handles remain usable. An existing staging file returns `AlreadyExists`
without replacing `CURRENT`. Explicit pending cleanup rereads and verifies `CURRENT`
and checks that its decoded knowledge matches the owner's selected checksum before
removing only a regular staging file. Symlinks and directories are refused. Cleanup
failure also requires reopen; no automatic forensic deletion occurs.

Expected errors use `FileError`: identity mismatches become `WrongIdentity`, size/native
extent limits become `LimitExceeded`, hash provider refusal becomes `BackendFailure`,
and malformed/checksum/proof failures become `InvalidFrame`. A prepared policy mismatch
is `InvalidBatch`; default preparation is `Uninitialized`. Failed/default result payloads
remain private and guarded. Failed initialization/open releases its lease and leaves
any on-disk forensic bytes untouched. Close retires descriptors even after poison.

Completion checks cover real create/reopen/replacement, busy leases, retained readers,
wrong identities and policies, malformed and full-state image refusal, size limits,
staging collisions/symlinks, rename failure and recovery, moved-owner retirement,
1,000 reopen/close lifetimes, and actual compiler lowering/runtime/privacy guards.
The existing test-only syscall observer exercises actual write, file-sync, rename and
directory-sync refusal, including the post-rename `PublishedUnsynced` boundary. No
power-loss experiment is claimed by these local checks.

Local completion evidence uses the pinned checked ARC/Clang native runner. The
light-file suite passes with 1,000 reopen/close cycles and occupied ARC bytes
3,728 before/after. Four consumed permanent IO refusals cover write, file sync,
rename and directory sync, including old/new restart selection. Three runtime
guards, two positive controls, three privacy rejections and an actual lowering
rejection for resource-owner duplication pass. Formatting and inventory pass.
These local results do not claim exact-head Linux CI or complete client integration.

Incremental `admit` and `forget` are specified in
[light evidence updates](storage-light-updates.md). Opening retains the bounded canonical
image as well as its immutable cache, allowing later edits without caller retransmission
of retained proofs. Successful file operations, including empty or unknown-only edits,
still run publication barriers before returning a fresh synchronization receipt.
