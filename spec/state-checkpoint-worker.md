# Bounded checkpoint I/O worker

## Scope and ownership

One explicitly started native thread owns one stable bank and one outstanding
exclusive prepared-byte buffer. Worker addresses remain fixed until joined close. A public move hook rejects active relocation; only default/closed owners may move.
One host thread serializes control calls. Preparation is synchronous computation
work performed at startup or in an already permitted computation worker; no live
canonical map or external ARC alias is borrowed by the I/O thread.

`stage` validates capacity, codec success, expected-head readiness, byte ceiling
and nonwrapping request generation before moving the sole buffer. Refusal leaves
the source untouched; successful admission resets it. Staged requests perform no
I/O until explicit `begin`. Only scalar phases are polled; Done holds capacity
until matching collection. Host-only retained identity and local generation reject
foreign/stale tickets, including across restart.

The thread performs the bank's existing ordered bootstrap/advance operations.
Completed means the operation returned its typed bank result, not that publication
succeeded. Only a successful inner bank result grants a committed head. No chain
adoption, protocol execution or network callbacks run on this thread. Parent
synchronization and publication uncertainty remain the bank's contracts.

`close` joins before dropping a private buffer or closing the bank. A completed
operation's actual receipt survives shutdown separately from native retirement
errors. Unstarted staged/running requests can be cancelled by joined shutdown;
already completed publication is never labelled cancelled. A joined worker that entered native execution without publishing a receipt reports Interrupted, requiring visible-head reconciliation. Storage calls can wait
on the filesystem; shutdown joins rather than pretending a running write rolled
back. Explicit close and independently checked composite noncopyability apply.

Executable/Services startup and policy integration remain separate. Full/light
storage contracts remain separate.

## Explicit staged cancellation

`cancel(ticket)` accepts only the matching Staged slot, before dispatch can enter
native I/O. It releases the sole prepared buffer and publishes a Cancelled Done
receipt, retaining acknowledgement backpressure until matching collection or joined
close. Foreign/stale/default/repeated cancellation has no effect. Running, executing
and already completed publication all refuse cancellation; an actual disk result
cannot be hidden or described as rolled back.

Tests deterministically cancel staged requests, prove exact selector/data preservation
and no inactive canonical file, reject foreign/stale tickets, retain Done capacity,
then perform real publication after dispatch and require its actual completed receipt.
One thousand cancellation cycles measure host buffer/ticket release. Joined close
preserves a cancelled acknowledgement independently of native retirement errors.

## Inspecting and retrying a stale selector

`peek(ticket)` returns only a matching Done receipt, preserving both the sole buffer
and acknowledgement capacity. `retry(ticket, newExpectedHead)` accepts only a
completed advancement refused specifically as StaleHead. That refusal performed
no publication. The same private bytes and original byte ceiling remain; a fresh
nonwrapping request ticket replaces old authority and explicit begin is required.

A default/foreign/stale/cancelled/active ticket, missing expectation, successful
write or any I/O/publication uncertainty cannot authorize this shortcut. Actual
success is never duplicated; uncertainty requires explicit collection and recovery.
No local selector comparison establishes chain-transition authority. Tests retain
exact refusals across failed retry admission, invalidate all old tickets, cancel
restaged work, preserve real success receipts and run 1,000 stale/read/retry/publish
cycles with host-only ARC release evidence.

## Asynchronous selector observation

`stageHead()` admits a metadata-only request into the same single slot. Explicit
begin, staged cancellation, ticket namespaces, Done backpressure and joined close
apply unchanged. The native worker calls the bounded checksummed head reader;
no filesystem call occurs in staging or scalar phase polling. Missing, malformed
and oversized heads preserve typed failures. Observation cannot use stale-write
retry, since it owns no prepared publication buffer.

A successful observation establishes only local format/checksum validity. Its root
is untrusted metadata and cannot supply independent chain or checkpoint authority.
No complete map crosses the worker boundary. Native checks include real reads,
exact scalar receipts, corrupt/oversized metadata, cancellation and repeated host
receipt release.
