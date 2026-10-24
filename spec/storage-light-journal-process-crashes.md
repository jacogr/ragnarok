# Light journal bootstrap and append process-crash qualification

This grouped verification unit exercises the real
[durable light journal owner](storage-light-journal-cache.md) and
[explicit held-inode repair](storage-light-journal-repair.md). It changes no production code,
format, startup selection, state application, compiler or native provider. The independent
complete-root fixture retains only partial light evidence and authenticated forward/reverse
proof-cache transitions.

## Exact child ownership and completed operations

The maintained process controller forks one test-owned child and arms observation only at the
chosen boundary. A successful observed SDK operation produces a fixed matching stop receipt.
The parent verifies the exact stopped child still owns the exclusive directory lease, then
requires that child's matching SIGKILL and reap receipt under a monotonic deadline. Completed
controls send a separate successful completion receipt. Arbitrary exits, setup failures, timeout,
unmatched counts or missing stops do not count as crash passes. Failure cleanup aborts only the
still-owned child; the native observer/controller remains unchanged.

The append workload opens and strictly verifies the existing selected journal before arming.
The bootstrap workload arms before namespace creation, including LOCK, directory and parent
barriers. The child exits without ARC retirement after a completed control, preserving the
same operating-system process-exit lease boundary as the killed cases. These are process-death
witnesses on the local filesystem, not power-loss, device-cache or filesystem crash guarantees.

## Append and retained-prefix cases

Both first-frame and following-frame workloads cover the one ordinary write and one append
sync boundary. Genuine 64-byte writes then cover every actual short chunk, including the final
complete chunk. The following workload first confirms a real frame, so a later partial append
must retain an authenticated nonempty journal prefix and the correct global sequence.

After each receipt, the journal must equal the exact old bytes plus the independently predicted
completed frame prefix. `CURRENT` and checkpoint bytes remain identical, no `CURRENT.next` is
created, and an unknown forensic sentinel remains unchanged. Strict reopening performs no
writes, renames or cleanup. A complete frame is reauthenticated and confirmed even if the child
died before returning its append receipt or publishing its in-process successor. A partial frame
refuses strict open and preserves every byte. Only a fresh explicit inspection/repair may discard
that incomplete frame; its plan must retain the exact old prefix/image/sequence before retrying
the authenticated append. Retained old readers remain immutable after recovery and close.

## Bootstrap cases and forensic preservation

Completed controls discover every actual write, sync, rename and close boundary. Each successful
boundary is then killed independently. Another short-write control determines every 64-byte
chunk across checkpoint, anchor and staged manifest files; every chunk has an independent kill
case with exact per-file extent prediction.

Every existing checkpoint, anchor or `CURRENT.next` file must contain only its exact authored
prefix. Future files cannot appear before their first observed write. `LOCK` remains the original
empty regular file. A selected `CURRENT` must be the complete exact manifest, with complete exact
checkpoint and anchor, and staging must have been consumed by rename. No alternate epoch or
staged file supplies selection authority.

Strict reopening preserves every captured known filename's presence and bytes. A selected complete
bootstrap reopens and appends successfully. Without `CURRENT`, strict opening refuses, releases
its lease and leaves forensic children unchanged. Failed initialization is never automatically
adopted or overwritten; a separate explicit fresh namespace can retry bootstrap. Test cleanup
removes only exact owned fixture children after every owner and child process has retired.

## Local evidence

The checked native suite passes 60 supervised cases: 11 completed controls and 49 exact witnessed
kill boundaries. First and following append controls produce 7 and 8 short chunks. Bootstrap
controls observe 3 writes, 11 syncs, 1 rename and 4 closes, plus 11 short chunks. The source-owned
JSON evidence records these actual counts beside the native verdict; counts are derived from
controls rather than assumed by the kill scheduler.

Semantic, formatting and verification inventory checks accompany the maintained native suite.
The shared negative process-supervision controls were already verified with the identical pinned
compiler and unchanged controller/provider sources earlier in this stack; this unit reuses that
evidence. Local results are macOS arm64 checked release with the repository-pinned tools and
providers. Exact-head Linux CI remains separate.

Remaining substantial work is atomic checkpoint compaction, explicit guarded epoch reclamation,
their grouped process-crash qualification and matched churn/reopen measurements. No automatic
repair, namespace adoption, pruning or application integration is added. Historical M1 framing
completion remains distinct from complete state serialization.
