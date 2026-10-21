# Supply lookup ancestry when downloading a child

The bounded `download` command can receive explicit sealed ancestor headers for
report lookup-anchor validation. Supply raw binary header files, newest first:
the first file is the immediate parent of the currently selected head, followed
by its parent, without gaps. Exclude the selected head itself; startup already
owns it. Preserve every seal byte.

For example, with your existing certificate/key, peer pin, configured ALPN and
complete versioned download policy:

```sh
./build/ragnarok download 4000 node.cert.pem node.key.pem peer-public.bin \
  "$configured_alpn" 30000 download-policy.conf \
  --with-state --chain chain.json \
  --download-ancestor parent-of-head.bin \
  --download-ancestor grandparent-of-head.bin
```

Use at most 64 distinct paths. The control is valid only for state-enabled
`download`; duplicate paths and incomplete controls refuse atomically. Each file
must be regular and contain exactly one complete sealed header under the policy's
header profile. Capture preserves the supplied order and requires bounded EOF.
File replacement after capture cannot change the retained input.

## Reuse retained local parents

Add `--download-local-ancestors` to capture all parents in the restored rolling
history, newest first, excluding the selected head. It is a unique, valueless,
download-only switch; the default remains explicit files only. For a normal disk
restart, keep the same chain/database controls and add the switch:

```sh
./build/ragnarok download 4000 node.cert.pem node.key.pem peer-public.bin \
  "$configured_alpn" 30000 download-policy.conf \
  --with-state --chain chain.json --state-storage disk --state-db local.db \
  --download-local-ancestors --download-blocks 2
```

The rolling view retains at most eight blocks, so initial local capture has at
most seven parents. A separately retained finalized block never fills an evicted
gap. With this switch, explicit `--download-ancestor` files follow the **oldest
captured local parent**, without overlap or gaps. Do not repeat local headers in
files. A one-head genesis or imported checkpoint has no local parents; reports
requiring older anchors still need explicit files or remote acquisition. Capture does not create missing
historical state or grant external checkpoint authority.

All retained parents must fit the supplied count and byte ceilings; capture never
silently drops older headers to satisfy a smaller policy. Disk restoration and
Services startup occur before local capture. Local capture/quota refusal occurs
before outgoing peer connections or child adoption; an existing journal stays
unchanged. Starting against a fresh disk path may already have initialized its
seed before local admission refuses. External files are still captured before
Services startup.

## Fetch older context from pinned peers

Add `--download-remote-ancestors COUNT` to fetch up to 1..64 older parent headers
from the configured pinned loopback peers before requesting a child. The default
is disabled. COUNT is a unique positive decimal control; zero, leading zeros,
duplicates and use outside state-enabled `download` refuse atomically.

```sh
./build/ragnarok download 4000 node.cert.pem node.key.pem peer-public.bin \
  "$configured_alpn" 30000 download-policy.conf \
  --with-state --chain chain.json --state-storage disk --state-db local.db \
  --download-local-ancestors --download-remote-ancestors 4 --download-blocks 2
```

Order is selected head, captured local parents when enabled, explicit files in
caller order, then fetched older parents. The descending-inclusive CE 128 request
starts at the parent of the oldest supplied header, or at the selected head's
parent when no context was supplied. Preserve continuous linkage between those
sources; do not repeat the head or overlap local, file and remote parents.

The peer returns complete GP blocks; acquisition keeps their sealed headers after
scanning complete extrinsics to find boundaries. Every fetched header must hash
to the requested parent and have a strictly older slot. An authenticated peer
cannot substitute a different lineage. These checks provide report context;
historical execution, finality and new canonical state are not inferred.

A peer may return fewer headers than COUNT. A valid nonempty shorter reply is
accepted, and ordinary report admission still requires every lookup proof needed
by the downloaded child. Empty, malformed, oversized and wrong-lineage replies
consume one finite attempt without exposing a prefix. Configured pins, retry
count, per-peer cooldown, stream/attempt ceilings and the total command deadline
still apply. No child request follows exhausted or failed acquisition. The total
deadline includes both context acquisition and later successive children.

A fresh child connection starts only after the ancestor stream and its graceful
connection close retire. RPC/UI can progress during acquisition; guest execution
starts later under the existing preparation lease. Fetched headers remain context
only: disk restart retains actual canonical snapshots/history and explicit
finality, without inserting remote headers as historical state snapshots.

## Discover context after receiving each child

Use `--download-discover-ancestors COUNT` when you want to fetch older headers only
if a received child's reports need them. It is an alternative to
`--download-remote-ancestors`; supplying both controls refuses. The default is off.
COUNT is one positive allowance of 1..64 fetched headers for the **whole command**,
including successive children, rather than a fresh allowance per child or retry.

```sh
./build/ragnarok download 4000 node.cert.pem node.key.pem peer-public.bin \
  "$configured_alpn" 30000 download-policy.conf \
  --with-state --chain chain.json --state-storage disk --state-db local.db \
  --download-local-ancestors --download-discover-ancestors 4 --download-blocks 2
```

The command receives a child and checks its supported block/report stages before
requesting missing context. Existing local/file context is checked first. Invalid
signatures and known package/core-capacity failures do not authorize an ancestor
fetch. A missing older lookup can suspend the prepared child while its native
worker and child connections retire. The command then fetches a bounded suffix
from the pinned peers and resumes that same prepared child. It does not download,
decode or authenticate that child again, and guests execute only after report
lookup completion.

Short valid replies consume their actual header count. If the proof still needs
older context, another round uses the remaining whole-run allowance. Each round
must make nonempty header progress. A wrong slot, wrong known root or missing
newer proof child cannot be repaired by an older suffix and refuses instead.
The original child-attempt deadline includes acquisition and never resets; the
command's overall deadline also remains shared. Exhausting the allowance or
refusing remote context cannot adopt that child. Earlier confirmed children
remain adopted and are reflected in reported progress.

Reserve the maximum allowance in both count policies even when no fetch is
ultimately needed. Keep every existing response/header byte limit, and size all
stage policies for evolved parent state when requesting several children.
Fetched headers remain temporary lookup context: disk restart retains adopted
canonical children, not fetched historical headers or fabricated historical maps.

## Set the existing policy ceilings

All fields of `ragnarok-download-policy-v1` remain required. Set these leaves in
your complete policy to cover the supplied files and the selected head:

| Policy leaf | What it bounds |
| --- | --- |
| `input.blockBytes` | Complete remote response payload bytes, excluding its E4 prefix; existing child-input bytes retain their own use of this ceiling. |
| `input.ancestors` | Combined local, explicit and remote older header count, excluding the selected head. |
| `input.ancestorBytes` | Aggregate encoded bytes of combined local, explicit and remote older headers. |
| `candidate.reporting.reports.ancestors.headers` | Total headers checked, including the selected head. |
| `candidate.reporting.reports.ancestors.header.maxBytes` | Maximum encoded bytes for each header. |
| `candidate.reporting.reports.ancestors.maxBytes` | Aggregate validation bytes, including the selected head. |

For two supplied files, the count ceilings must permit at least two input headers
and three validation headers. Byte ceilings must cover their actual complete
encodings, including markers/offenders/seals. The fixed 64-path cap never widens
a smaller policy. Reserve the requested remote maximum or whole-run discovery allowance even if a peer returns fewer
headers or existing context makes acquisition unnecessary.
For N children, also reserve N−1 additional carried parents in the input count and N
parent-inclusive validation headers, then check actual growing bytes between children.
Without local capture or remote acquisition, an omitted list preserves the existing no-ancestor behavior;
reports requiring unavailable lookup anchors still refuse.

## Observe capture and admission separately

Malformed, truncated, suffixed, missing, nonregular or oversized files return
`InvalidAncestors` before Services starts, listeners open, a disk database is
created/opened, or outgoing transport begins. An insufficient count policy
returns `InvalidPolicy` at that same startup boundary.

A structurally valid header still has to pass the existing report validator. It
hashes exact sealed bytes, checks newest-first parent links and strictly advancing
slots, and requires each lookup's matching header/slot plus a retained newer
child binding its posterior state root. Broken ancestry is a failed download
attempt and may end in `Exhausted`; it cannot publish a child.

Ancestor files supply lookup context for the selected canonical head. They neither
select a different head nor grant checkpoint-import authority. They do not create
retained historical state or infer finality. The command defaults to one
child; [bounded successive downloads](download-progress.md) can request up to 64
additional children on the configured pinned loopback peers. Budget both initial
files, captured local parents, the remote maximum and the carried newer headers for the complete run.

## Combine with restored state

The same controls work with [trusted checkpoint imports](checkpoint-import.md)
and the [disk backend](disk-storage.md). External imports retain their independent
identity/header trust requirement and create fresh disk paths exclusively. A
normal local disk restart resumes its durable head, retained bounded history and
explicit finality without external import controls. Select local capture, explicit ancestry or bounded remote acquisition for the next
download when its reports need it; local restart itself needs no ancestor
files. Disk adoption reports success only after confirmed durable publication.

See the [on-demand context contract](../spec/state-ancestor-context.md),
[remote acquisition contract](../spec/application-remote-ancestors.md),
[local capture contract](../spec/application-local-ancestors.md) and the [feature contract](../spec/application-ancestors.md) for typed component
errors, exact verification evidence and remaining scope. M1 framing is complete;
full state serialization and whole-block JAM/STF parity remain open.
