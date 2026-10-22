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

## Supervisor negative controls

`storage_crash_controls` repeats normal-but-unarmed completion, unmarked SIGSTOP, raw early exit,
a20ms monotonic timeout and explicit cancellation. Invalid operation/ordinal/deadline and nested
fork/start requests cannot replace an owned child. Every completed case refuses a second finish;
normal completion has count0 and cannot be confused with a successful crash witness.

## Complete legacy append before return

`storage_legacy_append_crash` counts the actual append write in a normally completing control,
then stops and kills the writer after the real complete write but before its caller receives
success. The parent checks the exact independently encoded frame, strict generation2 reopen,
complete authored leaves and its original retained generation1 view. No failed child receipt is
counted as a confirmed publication; the surviving parent must independently reopen visible bytes.

## Managed publication append crashes

`storage_managed_append_crash` independently counts 1 successful observed boundaries and kills after each.
After a successful journal append but before its caller receives success, strict restart selects
the complete successor. Exact encoded bytes, authored leaves and the retained old reader are checked;
managed snapshot/epoch selection remains unchanged and no implicit fallback layout is introduced.

## Legacy torn append process death

`storage_legacy_partial_crash` kills after actual eight-byte writes at the beginning, middle, penultimate
and final frame extent. Exact visible prefix bytes are independently checked. Incomplete tails
fail strict startup; wrong generation/root repair tokens preserve every byte and expose no owner.
The exact independent prefix token permits truncation and a complete resumed successor. A final
complete frame refuses the old repair token and cannot be rolled back. Held readers remain valid.

## Managed torn append process death

`storage_managed_partial_crash` kills after actual eight-byte writes at the beginning, middle, penultimate
and final frame extent. Exact visible prefix bytes are independently checked. Incomplete tails
fail strict startup; wrong generation/root repair tokens preserve every byte and expose no owner.
The exact independent prefix token permits truncation and a complete resumed successor. A final
complete frame refuses the old repair token and cannot be rolled back. Held readers remain valid.

## Legacy publication barrier crashes

`storage_legacy_barrier_crash` independently counts 3 successful observed boundaries and kills after each.
Pre-append barriers retain the exact prior frame; the final completed sync leaves the exact complete
successor visible. Strict restart admits only the independently checked generation/root and complete
authored leaves, while retained parent readers remain unchanged.

## Managed publication barrier crashes

`storage_managed_barrier_crash` independently counts 3 successful observed boundaries and kills after each.
Pre-append barriers retain the exact prior frame; the final completed sync leaves the exact complete
successor visible. Strict restart admits only the independently checked generation/root and complete
authored leaves, while retained parent readers remain unchanged.
