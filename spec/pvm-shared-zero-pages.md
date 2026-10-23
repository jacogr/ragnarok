# Operation-local immutable zero pages

Trusted mapping/clearing operations now lazily allocate one 512-byte known-zero chunk and share
it across all newly materialized zero pages in that operation. Page headers, indices, permissions,
sorted sparse vectors and page-budget accounting remain independent. The seed is local to
`withWritablePages` or `withPageRange`; children retain it after that call returns. There is no
global pool, mutable singleton or owner cycle. Empty/no-op/permission-only paths do not allocate
a zero payload. Dropping zero/inaccessible pages retains the existing sparse omission behavior.

Only absent or explicitly cleared pages use this path. Preserved inaccessible/read-only bytes
continue to share their original immutable payload, and arbitrary `PageImage` inputs still copy
all bytes privately. No zero classification is inferred from untrusted caller storage. Complete
owner, interval, native-extent and page-limit preflight remains before allocations. No failed
operation publishes a prefix. The limit counts logical retained pages exactly as before, including
inaccessible retained data; physical payload sharing does not relax it.

All writes preserve copy-on-write isolation. `writablePageClone` copies every touched chunk before
scalar or host mutation. `prepareWriterSpan` copies each touched chunk on its first write within
a private writer epoch; sealing transfers that epoch and later writes clone again. These rules
apply even when multiple slots in one page, or several different pages, reference the same zero
child. Permission-only headers remain immutable aliases. No public API exposes chunk addresses.
Guest addresses, bytes, permissions, fault precedence, gas and pinned dependencies are unchanged.

The persistent-memory suite now writes across zero-sharing chunk boundaries and different pages,
retains consecutive writer snapshots through an alias, and compares every byte against independent
expectations. It checks scalar and bulk host copies, nonzero-page clearing, read-only refusals,
partial permission grants, missing-page refusal, exact/short page budgets and drop/remap behavior.
All earlier dirty/zero/read-only/empty predecessors survive. These operations join 1,000 ARC release
cycles and actual AddressSanitizer execution. Heap, inner-page/dispatch, scalar writer, machine,
host-memory and metered cross-page retry consumers protect the environment integration.

`make bench-pvm-memory` additionally measures reservation and clearing of 32 pages (128 KiB) per
call. Each sample retains 128 independent immutable results until full-byte/access validation and
untimed retirement, with three warmups and ten measurements in each of two reversed-order passes.
The original read/write/capture/image cases remain. Strict framing, assertion controls, both clocks,
source/binary identities and all outliers remain in the reports. These are native memory API costs,
not complete guest interpreter or JAM throughput.

Initial matched checked ARC/Clang ThinLTO observations on the recorded M1 Max measured reservation
at 0.859→0.032 ms per 128 calls and clearing at 0.870→0.035 ms (about 96% less process CPU for both).
The other cases do not establish a sustained gain and are not claimed as improvements. Final
confirmation measured 0.8565→0.032 ms for reservation and 0.8615→0.036 ms for clearing
(about 96% less CPU). Some unchanged short API rows vary across paired runs, including a roughly 11%
slower 4 KiB write row in confirmation; no broad gain or stable regression is established for those
rows. All observations remain visible. All 930 Python checks (three skips), canonical API/sieve
comparisons and 403 production modules pass; exact-head Linux CI is separate.

M1 framing retains its documented completion scope. Full state serialization and whole-JAM/STF
parity remain open. Fuzzing remains deferred pending maintainer Daybreak access.
