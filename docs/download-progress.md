# Download a bounded sequence of children

`download` can adopt 1–64 successive children from the selected application head.
It defaults to one. Each child uses the existing CE128 maximum-one request,
supported admission/execution stages and exact-parent publication. Authenticated
connections to the configured pinned loopback peers remain open across children.

For three additional children, using your existing certificate/key, peer pin,
configured ALPN and complete versioned policy:

```sh
./build/ragnarok download 4000 node.cert.pem node.key.pem peer-public.bin \
  "$configured_alpn" 30000 download-policy.conf \
  --with-state --chain chain.json --download-blocks 3 \
  --state-storage disk --state-db local-state.db
```

`--download-blocks` accepts one canonical positive decimal count, 1–64. Duplicate,
zero, malformed and unrelated-command use refuses atomically. All fields of
`ragnarok-download-policy-v1` remain required; the new control changes local
orchestration, not that policy schema or wire request encoding.

## Budget the complete run

Starting with `A` explicit [ancestor files](download-ancestors.md) and requesting
`N` children requires these count ceilings before any file or Services startup:

| Policy leaf | Minimum capacity |
| --- | --- |
| `input.ancestors` | `A + N - 1` older headers. |
| `candidate.reporting.reports.ancestors.headers` | `A + N` headers, including the selected parent. |

With no supplied files and three children, allow at least two older input headers
and three validation headers. The command prepends each adopted child's previous
selected header newest-first. It keeps the complete supplied/carried lineage;
resource refusal never silently removes an older header.

`input.ancestorBytes`, the validation aggregate bytes and per-header maximum must
also fit the actual evolved headers. These byte ceilings are checked before the
next stream starts. Execution/composition limits apply to each actual new parent;
service/statistics counts and other state extents can grow after the first child.
The command never widens a stage or inherited mutation policy automatically.

One monotonic timeout starts after Services startup and covers the entire run,
including preparation and durable publication. It is checked between bounded
dispatcher turns. Each child gets the policy's explicit fresh attempt/retry budget;
success does not reset the overall timeout. Worker jobs and native streams retire
before rearming, and final shutdown joins outstanding execution/IO before owners
or callback inputs are released.

## Read the result as confirmed progress

A multi-child invocation prints:

```text
DOWNLOAD_PROGRESS adopted=3 requested=3
DOWNLOAD_ADOPTED
```

Exit 0 means the requested children completed successfully. Later failure exits 2
with the existing `DOWNLOAD_FAILED REASON` diagnostic and an exact progress line,
for example `adopted=1 requested=3`. Downloaded or prepared bytes alone do not
increase the count. A timeout keeps its failure reason even if joined shutdown
confirms the one outstanding durable child; inspect both the reason and count.
The default single-child invocation preserves its existing output tokens.

Use the disk backend for progress that survives command/process exit. Earlier
confirmed disk publications remain when a later child is empty, invalid, stale,
over budget or times out. Normal restart resumes the actual durable head; a new
run counts additional children from that head. Select the remaining count
explicitly. Memory-mode counts describe confirmed adoption during that command;
its private Services state retires when the command returns.

Library callers can use `runDownloads` for immutable requested/adopted scalar
diagnostics plus the terminal reason. `runDownload` remains the status-only API.
These diagnostics grant no execution or publication authority.

## Preserve the selected trust and history

[External checkpoint imports](checkpoint-import.md) still require independent
identity/header inputs and start with one unfinalized head. Disk imports create
fresh paths exclusively. [Normal disk restart](disk-storage.md) preserves its
bounded history and explicit finalized anchor without rereading external trust
files. Successful child counts never infer finality.

RPC readers observe the canonical retained history and exact roots/headers as
adoption proceeds; native execution/publication keeps its existing exclusion
lease. The command closes its listeners on completion. Supply any older lookup
context needed at startup through the explicit ancestor controls; local restart
does not automatically acquire missing external headers.

See the [feature contract](../spec/application-download-progress.md) for the
verified signed-chain, real TLS/RPC, durable restart and executable scenarios.
M1 framing is complete; full state serialization and whole-block JAM/STF parity
remain open.
