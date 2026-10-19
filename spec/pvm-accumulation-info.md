# Accumulation account info host

## Scope and authority

Implement info (6), Omega_I, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex,
definitions.tex and accounts.tex threshold equations. Charge 703 before lookup or
memory effects. Select the current complete-map account by exact uint32 r7 or
UINT64_MAX for self; absent targets return NONE with an empty output interval.

Encode 96 bytes: raw code hash, E8 balance/minimum balance/minimum accumulation
gas/minimum transfer gas/storage octets, E4 items, E8 gratis, then E4 creation
slot/last accumulation slot/parent. Clip r9/r10 to this record and atomically write
to r8, returning 96. Empty intervals accept every pointer. Copy policy bounds only
the selected output; the fixed account and record extents remain independently
bounded. No extra state metadata version byte belongs in the host record.

Completion witnesses cover all exact fields/widths, self/other/absent/full-width
targets, current state after writes, offsets and lengths, zero/short copies,
cross-page atomicity, exact gas ordering, malformed/overflowing metadata,
deposit/gratis cancellation and fixed result contracts, immutable owners and ARC
release. Minimum balance outside its declared E8 domain is local MalformedState;
never truncate or saturate it. Grow_heap and remaining accumulation calls and
persistent publication remain later bounded increments.

## Arithmetic and ownership

Minimum balance uses the same exact three deposit terms as write funding. Start
with UINT64_MAX+gratis in two limbs, consume each complete 128-bit product and
base deposit, then derive max(0, UINT64_MAX-remainder). An exhausted budget means
the mathematical minimum is outside E8 and refuses as MalformedState. This also
accepts cancellation where intermediate deposits exceed uint64 but the resulting
minimum fits. No overflow, truncation or saturation changes the result.

The public effectAccountInfo query retains this exact immutable context's current
complete map and returns its fixed record by value. It validates the full 89-byte
canonical metadata before encoding. UnknownService, invalid/default contexts,
invalid parameters and malformed dependent fields remain guarded local results.
The guest adapter maps only actual absence to NONE; memory failures panic after
charging and preserve every prior guest byte/r7. Fixed metadata/record work is
bounded independently of the variable copy ceiling. Info changes no account,
provision, yield, checkpoint or initial provenance and performs no backend hashing.

## Local verification (2026-10-19)

Info, write, effects, dispatch and outcome native suites passed with fresh
1,000-cycle ARC evidence and unchanged occupied memory. The info suite freezes an
independent whole-record byte witness, exercises field-boundary and full-width
slices, self/other/missing accounts, zero-copy queries, cross-page atomic failures,
all affordability edges, malformed versions/extents, backend independence,
minimum-balance/gratis cancellation, overflow refusal and info after an actual
storage write. Public query default/parameter/absence errors are checked directly.

Twenty-two runtime extraction probes, nine privacy rejections and 42 selected
Python discovery/failure/native-harness checks passed. Inventory, pinned Nim/Rust
formatting and whitespace checks passed. Evidence remains in `build/pvm-info/`,
including native.log, guards.log, targeted-results.json, selected Python logs and
format-check.log. These are focused local macOS results; full verification and
exact-head Linux evidence remain CI work. Consumers reused one prepared library
set while retaining independent execution/output/ARC verdicts.
