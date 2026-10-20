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

This first layer does not integrate executable/Services startup or provide an
explicit retry API. Full/light storage contracts remain separate.

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
