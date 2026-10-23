# Private contiguous scalar writes

Scalar stores now copy an admitted contiguous chunk span from an initialized stack word into
private byte storage. Both immutable `store(Memory,...)` and staged `store(ScalarMemoryWriter,...)`
use the same bounded helper. One-byte writes remain direct. Chunk-crossing and big-endian hosts
retain the byte-wise little-endian equation; a page crossing copies its suffix only when the
prefix is shorter than the scalar, so no shift reaches64.

Complete original scalar preflight still precedes every mutation: width, wrapped-address rules,
protected prefix, page presence and permission precedence do not change. Immutable stores clone
the touched page/chunks first. Writers prepare both touched spans first and clone each chunk
once per epoch. Only those private chunks may reach the helper. The disjoint stack source and
one-chunk destination are range checked for the full1..8-byte extent before `copyMem`; no mutable
pointer escapes. Failed writes expose no partial prefix; aliases and published snapshots remain
immutable. No pin, gas, memory ordering or ARC policy changes.

The writer suite now independently checks every byte and permission of both pages after overlapping
writes through immutable stores and aliased writer epochs. Widths1/2/4/8 cover aligned, unaligned,
chunk and page edges, including partial words. It retains both earlier snapshots, checks original
source aliases and a temporary source's lifetime. The actual suite also passes AddressSanitizer
with the instrumented runtime verified in its dynamic linkage, plus1,000 ARC release cycles.
Memory/access/boundary/step, mixed execution, host and metered retry suites protect consumers.

Two reversed-order paired local observations show aligned scalar elapsed time about7–10% lower,
and sparse aligned time about7–9% lower. Crossing workloads changed only about2%, an unproven
small difference. Real-sieve process CPU changed by about1.5–1.7%, also below a reliable broad
claim. The maintained eleven-guest and real-sieve comparisons pass full outcomes. These local
M1 Max observations do not establish exact-head Linux CI or whole-client throughput improvements.

The prior complete Python result (922 tests, three skips) is reused because no Python source,
fixture contract or dependency changed. Production Smoke remains checked. M1 framing remains
complete within its contract; full state serialization and whole-block/JAM parity remain open.
Fuzzing remains deferred pending maintainer Daybreak access.
