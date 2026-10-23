# Bounded authenticated light lookup cache

Scope: standalone in-memory retention of verified serialized-key lookups for the maintainer's
light-storage work. Authority is the existing [proof/trust contract](storage-light-state-proofs.md),
pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` state Merklization M/B/L.
This is a partial lookup cache, not a complete `StateStore`, database schema or consensus head.
It introduces no startup, network, disk, chain-identity or finality integration.

## Trust, absence and immutable ownership

`newLightStateCache(root, limits)` fixes one caller-trusted well-formed complete-state root for
the cache's lifetime. Construction does not authenticate its provenance. A different root needs
a new empty cache; there is no root-switch operation that could carry stale positive/negative
entries across roots. The root accessor returns that exact binding, never a partial-map commitment.

`lookup(key)` returns an immutable `VerifiedStateLookup`, UnknownKey when no retained evidence
exists, or Uninitialized for a default cache. An authenticated Absent lookup consumes an entry
just like Present; present-empty remains distinct. Even an empty-root cache starts with no retained
lookups; explicitly admitting its empty proof records authenticated absence for a queried key.
The cache never promotes missing local data to protocol absence.

`admit(updates)` borrows stable key/proof inputs and returns a new cache only after every proof
verifies against its fixed root. Keys must be unique within a batch, including identical writes.
Entries not updated retain their immutable lookup owners. Count/native extents and individual
proof node/value policy precede sorting; duplicate keys precede final map budgets; all map budgets
precede cryptographic verification. Replacements release their old logical value allowance before
adding new bytes, so order does not affect final quotas. Proof failures retain their typed reason;
backend refusal cannot become UnknownKey or Absent. No partial batch is published.

`forget(keys)` returns a new cache without selected local evidence. Unknown keys are no-ops;
duplicate input keys are rejected. Forgotten keys become UnknownKey rather than authenticated
Absent. Old cache copies and returned lookups remain valid after replacement, forgetting or
retirement of the originating handle. Both operations preserve the exact inherited policy/root.
Empty batches retain the source without hashing or allocation. Inputs, returned byte copies and
other cache revisions cannot mutate private retained entries.

## Resource and lifetime contract

Limits independently bound retained entries, update/forget batch keys, per-proof node/value work
and aggregate retained raw-value bytes. Native descriptor extents are checked before allocation;
counts and byte totals use checked/subtraction-based arithmetic. Sorted fixed key/index scratch
never copies proof payloads. Admission holds bounded validated lookup scratch, then one exact
sorted result array. Values are owned by immutable proof-verification results; sharing cached
entries across revisions does not copy their payloads. Forgetting never hashes.

The aggregate value ceiling counts logical present raw bytes only. Entry limits bound absence
metadata too. These ceilings are not allocator RSS limits or a global history cap: callers control
the lifetime/number of retained caches and lookup handles. Allocation exhaustion remains fail-stop.
The cache uses the project's single-threaded ARC contract and acyclic immutable owners.

## Completion checks

`make unit SUITE=storage_light_cache` distinguishes Unknown/Absent/present-empty against an
independent complete-map root. It checks atomic invalid/incomplete/provider-refused batches,
root-mismatched and stale negative proofs, duplicate/quota precedence before hashes, hard 249-node
bounds under maximum caller policies, exact replacement/absence accounting, forgetting,
caller/output mutation and retained historical cache/lookup lifetimes. A 25-step flat known-key
model independently checks unsorted admission/replacement and forgetting across retained views.
One thousand success/partial-failure/recovery lifetimes return to the exact occupied ARC baseline.

Source-owned compiler privacy guards protect snapshot owners and result status/payload fields.
The runtime failure family covers default and failed lookup/cache result extraction plus default
root/count/value-byte/policy access; successful controls use actual initialized empty-root caches.
Local checked evidence uses pinned Nimony ARC/Clang release with bounds/assertions enabled;
runtime guard builds retain ThinLTO. Full source, guard and lifetime evidence remains under
ignored `build/storage-db26-*`. Heavy exact-head Linux verification remains separate; PR Smoke
runs automatically on publication.

Light database identity/schema, persistent caching, eviction policy, trusted-head selection and
application mode selection remain separately scoped work. M1 framing is complete; complete state
serialization and whole-block JAM parity remain open. No complete light-node claim is made.
