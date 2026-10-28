# Native owner move retirement

## Scope and contract

This fixes native ownership transfer independently of the October 28 compiler upgrade (#1788).
No protocol interpretation, dependency pin, copy permission or worker relocation precondition changes.
The base is master `41a747900`; the pinned compiler is October 26 Nimony
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`.

A moved-from native owner must report no ownership. Closing, reusing or destroying that source
must not close descriptors, release locks, remove socket paths or retire directory streams that
belong to the destination. Managed fields still delegate to their own move hooks, without
running destructors against transferred storage.

## Evidence and audit

The UDP reproducer supplied by review #1 of #1788 opens two loopback endpoints, moves one,
sends successfully, closes the source, then sends through the destination again. Before this fix
it prints `moved source still open: true`, `before source close: 1`,
`after source close: -1`. Review reproduced this on both October 26 and October 28 compilers.
The October 26 binary was independently rerun for this fix.

Generic move hooks on scalar fields leave the value intact on these pinned compilers. Generated
hooks on connection objects/arrays clear their managed strings but retain scalar ownership flags.
Consequently, field-by-field calls to generic scalar hooks do not establish a native sentinel.

| Owners | Explicit moved-from native sentinel |
| --- | --- |
| UDP endpoint | Closed flag, invalid descriptor, zero port, transferred registration |
| Management/MCP/RPC listeners | Closed listener and every accepted slot; management pathname unbound |
| UI listener | Closed listener, development root, every connection and streaming file |
| Fuzzer socket | Closed/unbound listener, disconnected consumer, no pending request |
| Telemetry client | Disabled retries, closed socket, no in-progress connection |
| Resource sampler | Default opaque `DirStream`, closed scan, unavailable observations |
| Atomic file writer | Inactive lock authority, invalid descriptor, transferred path |
| Managed journal | Inactive lease, invalid descriptor, transferred directory-state reference |

The opaque stream is assigned `default(DirStream)` rather than inspected or modified through
private runtime fields. The pinned public implementations document that default as closed on
Linux and macOS.

Paged/managed directory, paged file, repository, writer, reader and candidate owners store native
ownership behind managed references. Their moved-from safety follows from clearing the owning
reference; resetting the scalar fields inside the shared referent would invalidate the destination.
Existing closed/joined requirements on workers, runtimes and callback-bearing transport owners
remain in force. The new explicit native-handle resets for Bandersnatch and the ARM64 JIT in
#1788 already assign nil directly and do not exhibit scalar-hook delegation.

## Verification

Run the affected native suites with `make unit SUITE=<name>`:

- `quic_io`: IPv4/IPv6 source close, reuse, scope retirement, live send and dispatcher registration.
- `management_resources`: move an incomplete scan, close/reconfigure its source, complete exact accounting.
- `management_http`, `mcp`, `rpc`, `ui`: transfer listener and nested connection descriptors, preserve
  queued managed bytes, then close/reuse/destroy the source. UI also transfers root/streaming files.
- `telemetry`, `fuzz_socket`: source cleanup cannot retire either transferred native descriptor.
- `state_atomic_file_writer`: moved source cannot release the destination lock; destination reads/writes.
- `storage_managed_publication_io`: language move preserves the journal's directory lease and byte count.

Existing scoped ARC evidence and copy/dup rejection fixtures remain applicable. Local validation
uses checked release builds on macOS ARM64; full native Linux verification remains in CI.

The independent fix adds several hooks also introduced by #1788. When reconciling the two PRs,
retain these explicit native sentinels and connection-array resets instead of scalar delegation.

Local result: all ten suites above and all eight affected copy/dup lowering rejection fixtures
passed. The UDP, sampler, lock-writer and journal suites retained their existing unchanged-occupancy
ARC checks. Verification inventory passed without registering another suite.
