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

## Set the existing policy ceilings

All fields of `ragnarok-download-policy-v1` remain required. Set these leaves in
your complete policy to cover the supplied files and the selected head:

| Policy leaf | What it bounds |
| --- | --- |
| `input.ancestors` | Number of supplied ancestor files, excluding the selected head. |
| `input.ancestorBytes` | Aggregate encoded bytes of supplied headers. |
| `candidate.reporting.reports.ancestors.headers` | Total headers checked, including the selected head. |
| `candidate.reporting.reports.ancestors.header.maxBytes` | Maximum encoded bytes for each header. |
| `candidate.reporting.reports.ancestors.maxBytes` | Aggregate validation bytes, including the selected head. |

For two supplied files, the count ceilings must permit at least two input headers
and three validation headers. Byte ceilings must cover their actual complete
encodings, including markers/offenders/seals. The fixed 64-path cap never widens
a smaller policy. An omitted list preserves the existing no-ancestor behavior;
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
retained historical state or infer finality. The command still downloads at most
one child from the configured pinned loopback peers.

## Combine with restored state

The same controls work with [trusted checkpoint imports](checkpoint-import.md)
and the [disk backend](disk-storage.md). External imports retain their independent
identity/header trust requirement and create fresh disk paths exclusively. A
normal local disk restart resumes its durable head, retained bounded history and
explicit finality without external import controls. Supply ancestry for the next
download only when its reports need it; local restart itself needs no ancestor
files. Disk adoption reports success only after confirmed durable publication.

See the [feature contract](../spec/application-ancestors.md) for typed component
errors, exact verification evidence and remaining scope. M1 framing is complete;
full state serialization and whole-block JAM/STF parity remain open.
