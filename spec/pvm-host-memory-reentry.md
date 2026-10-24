# Host memory replacement, permission repair and reentry

## Scope and independent expectations

Reuse the independently derived frozen mixed-loop corpus and its recorded specification and
PolkaVM pins. Test hosts replace complete memory owners, change unrelated sentinel bytes and
make a lower page read-only while withdrawing the higher page before each guest store. Repair
missing higher pages before the lower read-only page, reenter the same paid block and finish the
loop through the second host. No production semantics, fixtures, pins or fuzzing policy change.

Compare dynamic pricing, immutable plans and cold/warmed memos through both callback APIs.
Check every CPU field, complete bytes/permissions, each fault/host order and exact gas, including
initial/final block underfunding. Retain predecessor snapshots through later host replacements
and repairs, and verify ARC retirement. Cross-check the same state sequence with the pinned
public PolkaVM Interpreter and reject corrupted copied inputs in both consumers. Native retained
inaccessible-image bytes are an additional snapshot contract, not readable reference VM memory.

## Completed comparison

The unchanged frozen input SHA-256 is
`13a5be9ff1c65e08869dbe31c0ab5b49fa8593a7adfbdc4b32b4e0bbd521cf09`.
Both interpreters check 32 original loop programs at surplus, exact, final-block-short and
first-block-short gas. Each host/fault observation checks every register, exact gas and PC;
every accessible page is compared completely, including two unrelated host marker bytes.
Cross-page stores must fault on the missing higher page before the lower read-only page,
write no prefix and resume without a second block debit after each repair. The second host
restores both writable images; later iterations must observe those replacement owners.

The native matrix passes 1,024 cold/warm policy and callback cases, 15,744 host callbacks and
11,808 repaired faults. All retained original, callback, fault and repaired snapshots are checked
again after terminal execution. One thousand complete crossing-repair owner lifetimes retain
unchanged ARC occupied memory. The public pinned interpreted reference independently passes
128 base cases, 1,968 callbacks and 1,476 faults using public protection/free/map APIs. An absent
reference page exposes no bytes; its restored image is checked after repair, while native retained
inaccessible images additionally preserve their original copied bytes.

Both actual executables accept the original input and reject copied corruptions of expected
registers, memory, prices, record counts and truncation. Source-owned discovery pairs the new
reference with its native suite. Independent fixture reproduction and runner controls pass, along
with inventory, pinned formatting and whitespace checks. All evidence is local checked macOS
ARM64 / ARC / Clang ThinLTO and pinned Rust, saved under `build/pvm11/reentry/`.

Reproduce native verification with `make unit SUITE=pvm_host_memory_reentry_reference`;
`make check-pvm-reference` discovers and runs this public/native pair with the other comparisons.
The original [mixed-loop oracle](pvm-mixed-program-reference.md) and approved
[memory ordering](pvm-polkavm-memory-order.md) own the underlying expectations. This comparison
adds no new interpretation and does not establish arbitrary program, full state serialization
or whole-JAM equivalence. M1 framing remains complete only in its documented scope; fuzzing
remains paused pending the maintainer's Daybreak access.
