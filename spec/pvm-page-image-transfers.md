# Bounded page capture and image materialization

`captureMemory`, `withPage` and `pageImage` keep their existing copied-value contracts. Capturing
an admitted page copies each 512-byte span into a fresh private chunk. Materialization copies each
of eight immutable chunks into its corresponding span of a fresh 4096-byte `PageImage`. A checked
helper contract proves the complete capture source span before copying; fixed chunk and page
sizes prove the destination extents. Every copy stays within a single allocation and has disjoint
source/destination storage. No pointer escapes and raw bytes need no endian conversion.

All page-shape, ordering, ordinal and allocation-policy validation still precedes capture. Page
indices, permissions, hidden inaccessible bytes, sparse absence and replacement behavior are
unchanged. Returned images expose copied bytes, never private chunk storage. Caller mutation,
returned-image mutation, parent retirement and later permission/scalar/host updates cannot change
an earlier snapshot. This changes implementation cost without changing the Gray Paper memory
model, approved exception ordering, guest gas, public signatures or dependency pins.

The persistent-page native suite now checks every byte across all chunks and all three access
states, including protected and final physical pages. It mutates complete caller inputs and
returned observations, verifies predecessor-preserving replacement, and uses observations after
temporary parents retire. These checks accompany the existing scalar/chunk/page-boundary and
host-write generations in 1,000 ARC release cycles, with actual AddressSanitizer linkage and execution.
Affected machine, scalar writer, initialization, host-memory, inner-page and boundary/step consumers
and the maintained full-state sieve comparison cover integration.

`make bench-pvm-memory` now additionally measures 4096/65536-byte capture and 4096-byte image
materialization. Each of 128 calls per sample retains its independent result until untimed full-byte
validation and retirement. Capture additionally proves its neighboring source page was not retained.
The original six read/write cases remain, with strict framing and complete reversed case order.
All clocks, samples, warmups, source/binary identities, assertion controls and noise flags remain
available. This supporting benchmark measures native memory APIs, not guest interpreter throughput.

Initial paired checked ARC/Clang ThinLTO measurements on the recorded M1 Max reduced 4096-byte
materialization from 0.1605 to 0.0210 ms per 128-call batch (about 87% lower process CPU).
Capture measured 0.024→0.021 ms at 4096 bytes and 0.398→0.3715 ms at 65536 bytes (about 13% and 7% less).
No sustained read/write improvement is claimed; the shortest calls are sensitive to clock granularity. Short capture
calls are sensitive to clock granularity and host load; canonical confirmation and complete raw
samples qualify these observations. A second paired run confirmed 0.161→0.021 ms for images
and 0.402→0.370 ms for 64 KiB capture (about 87% and 8% less CPU). Small 4 KiB capture varied
from about 4–13% lower across runs; no precise stable gain is claimed there. Canonical API/sieve
comparisons, all 403 production modules and 930 Python checks (three skips) pass. No checking flags,
ownership rules or source fixtures change.

M1 framing retains its documented completion scope. Full state serialization and whole-JAM/STF
parity remain open. Fuzzing remains deferred pending maintainer Daybreak access.
