# Native storage process-crash qualification

Fresh baseline: merged `7655b78f`, after storage stack #664 and the coordinated PVM/state stacks.
Current Gray Paper is unreleased `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, based on VERSION
0.8.0; the published 0.8.0 vectors remain a separately identified historical corpus. This storage
qualification changes no protocol domains, file formats, state/proof APIs or checkpoint trust.

## Witness and scope

A test-only observer forwards real SDK operations. A child arms observation after setup, writes a
fixed-size receipt only after the selected successful syscall, then stops with SIGSTOP. The parent
checks its exact owned child, exact operation/ordinal and stopped status, sends SIGKILL and requires
its signal reap. Normal exit is a distinct baseline receipt. Missing/unreached hooks, malformed
receipts, unrelated stops, unexpected exits and monotonic deadline expiry cannot pass a crash case.
Child storage owners never execute normal close or ARC retirement after the witnessed boundary.

The supervisor owns one child and pipe, rejects replacement while active, uses nonblocking receipt
reads and bounded monotonic waits, and has explicit failure-path kill/reap. No production hook,
compiler/runtime patch or child process is added to the application. The existing native runner
owns compilation, profiles, logs and suite discovery.

Process death leaves the host kernel and page cache alive. These tests qualify restart after
process interruption; they do not certify filesystem/device durability or hardware power loss.
Strict recovery still needs independently selected exact generation/root authority. Context stays
opaque; an existing migration destination is never overwritten. M1/state-serialization scope stays
unchanged. State #6 owns typed proof readers and selected-root integration; no overlap is planned.

## Initial supervisor verification

`make unit SUITE=storage_crash_supervisor` verifies real one-byte writes, two distinct successful
stop ordinals, explicit three-write normal completion, and refusal without an owned child.
