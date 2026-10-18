# Present entropy and trace fetch

Scope: `host_fetch.nim` implements the present-value branches of host identifier 2,
selector 1 (32-byte entropy) and selector 2 (authorizer trace, including an empty trace).
Normative source: Gray Paper 0.8.0 gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General Functions,
Omega_Y and `fnmemgas`; `text/definitions.tex`, `CgasYc`/`CgasYl` entries 1 and 2.

Entropy costs 103; trace costs `80 + ceil(96 * r9 / 1024)`. Charge uses the requested
length before clipping, even for empty copies. Quotient/remainder arithmetic avoids overflow
for every unsigned register value. The maximum trace cost is below 2^63, so exact terminal
deficits fit the existing gas representation. The positive gas-domain gate in
[pvm-host-gas.md](pvm-host-gas.md) remains open.

Source offset and copy length clip to the supplied value. Successful r7 reports the full value
length. Unwritable or nonphysical natural destination ranges panic after charging, preserving
registers and memory. Empty copies accept every pointer. Insufficient gas preserves registers
and memory and returns the exact deficit before attempting a copy. Memory snapshots are immutable;
borrowed trace bytes must remain stable only during the call, and copied bytes outlive the input.

The trusted dispatcher selects the invocation's present value; wrappers reject mismatched r10.
Invalid memory and local copy-budget refusals are typed errors without a HostResponse payload.
Local policy is checked by `writeBytes` before page permissions, and does not claim a protocol exit.
Callers must propagate that refusal or establish sufficient policy in advance. The
[fallible executeWithHost overload](pvm-host-failures.md) now preserves the exact FetchError
through hostFailure; response-only callbacks still cannot carry local refusals.

Completion tests: independent rounding oracle and hard-coded maximal-length price, clipping,
full-length return, exact/insufficient gas, cross-page atomicity, readonly and absent pages,
physical boundaries, empty ranges, source/input ownership, response application, result privacy
and failed extraction, and 1,000 fresh ARC cycles through the native runner.

[Optional context capture](pvm-fetch-context.md) now selects entropy/trace presence and implements
unknown selectors. The pinned notation's Sets section explicitly defines none's cardinality as zero,
resolving the earlier absence gate. A funded absent value returns NONE through an empty interval;
a present empty trace returns zero. Both retain the original selector's requested-length charge.
Other known selectors and complete service invocation assembly remain open. Independent fixtures
establish only the stated subset, not complete fetch or invocation parity.
[Package blob fetch](pvm-fetch-package.md) now supplies configuration, token and item payloads.
Next bounded chunk: encoded refinement context and work-item summaries.
