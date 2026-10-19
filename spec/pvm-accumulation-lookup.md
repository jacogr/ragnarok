# Accumulation preimage lookup host

## Scope and authority

Implement lookup (3), Omega_L, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`.
`text/definitions.tex` fixes cost `600 + ceil(248*r11/1024)`; the
General Functions preamble charges before all table mutations. `text/notation.tex`
defines NONE's cardinality as zero, so absence has an empty writable interval.

Read a raw 32-byte hash at r8, choose self for r7=UINT64_MAX or the invoking
service ID, otherwise an exact uint32 account, and use its canonical preimage
namespace. Missing accounts and missing hashes return NONE. Present empty bytes
return zero. Clip r10 against the full value length and r11 against the remaining
suffix, atomically write to r9, and return the full value length. Unreadable hashes
or unwritable effective output panic after charging. An empty interval accepts
any destination pointer. Never truncate high target/address/offset bits.

Hash input is fixed at 32 bytes; copyLimit independently bounds the variable value
slice and guest write. Bounded owner-bound store slicing avoids materializing an
entire retained value for short or zero-copy queries. Malformed account metadata,
backend refusal and local policy exhaustion expose no partial execution. Lookup
changes only guest memory/r7; implication contexts and serialized state stay immutable.

Completion witnesses cover gas rounding and full-width requests, self/other/missing
accounts, missing versus empty values, clipping, zero copies, overlapping/cross-page
buffers, all permission failures and atomicity, malformed backing/backend refusal,
unchanged effects/state, independent owners and 1,000 release cycles. Store-slice
unit/negative checks cover default owners, invalid/full-width ranges and exact budgets.
Other account calls and persistent publication remain separate increments.


## Ownership, absence and errors

The dispatcher reads its current immutable account backing from the original
prepared implication context, never a caller-supplied replacement map. It validates
an existing account's complete canonical metadata before deriving the one existing
preimage namespace key. Orphan keyed blobs cannot create accounts. Lookup returns
serialized dictionary contents; it does not rehash retrieved payloads or fulfill
requests/provisions. The synthetic test maps witness those exact dictionary rules,
without claiming reachable whole-chain state.

The 32-byte hash read is fixed and separately bounded, so a zero variable-copy
ceiling can still query a length or distinguish absent/present-empty values.
Funded NONE has f=l=0 by the pinned notation's cardinality rule. Present-empty
instead returns length zero. For present values the offset is clipped before
subtraction, copySlice validates the exact interval, and writeBytes preflights all
guest pages before publishing memory. Hash/output overlap is safe because the hash
is already copied. Failed writes preserve the entire original memory and r7.
Implications and complete-map roots stay unchanged across every outcome.

Backend namespace failure maps to local `BackendFailure`; malformed metadata or
invalid owners map to `InvalidContext`; local copy exhaustion maps to
`LimitExceeded`. These return no partial machine/effects. Guest panic and exact
host gas deficits remain completed executions. The unchanged broader signed-gas
and nonempty-provision/hash-return gates remain separate.

## Remaining boundary

Read (4), write (5), info (6), grow_heap and the remaining accumulation host calls
are subsequent work, as is persistent publication. Lookup requires the current
complete-map contract; it does not add light-node partial-state support or claim
complete Psi_A/block execution.


## Local verification (2026-10-19)

The selected native lookup, state_store, accumulation dispatch, outcome and provide
suites passed through `tools/native_tests.py --suite`. Lookup's 1,000-cycle ARC
witness held occupied memory at 1,040,960 bytes before/after. Store slicing exhausts
small ranges, exact/short ceilings, full-width invalid inputs, default owners,
independent copied bytes and retained views across later map updates.

The shared store enum/API addition justified a complete source semantic audit:
all 110 modules passed with the pinned compiler. Eleven focused runtime probes
(including both new failed-slice byte-result paths) and six privacy probes passed
through the existing harnesses. Forty selected Python inventory/failure/guard/native
runner checks passed. Inventory, pinned Nim/Rust formatting and `git diff --check`
passed. No executable source changed after these results.

Logs and targeted guard evidence remain under `build/pvm-lookup/`: `lookup.log`,
`store.log`, three consumer logs, `modules.log`, `guards.log`,
`targeted-results.json`, selected Python logs and `format-check.log`. This is local
macOS verification; complete six-group verification and Linux CI are not claimed.
