# Encoded refinement context and work-item summary fetch

Scope: fetch selectors 10, 11 and 12, using the immutable package captured by
withFetchPackage. Normative source: Gray Paper 0.8.0, gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General
Functions, Omega_Y and S(w); `text/definitions.tex`, CgasYc/CgasYl entries 10–12;
Appendix C.1/C.2 for scalar, sequence and refinement-context encodings.

Selector 10 returns the canonical encoded refinement context and costs 111.
Selector 11 returns a compact item-count prefix followed by the ordered summaries
and costs 317. Selector 12 returns the summary indexed by r11 without a prefix and
costs 250. All three have zero per-byte rate, including maximal requested lengths.
Selectors 10/11 ignore r11; all three ignore r12. Missing packages and invalid
selector-12 indices return NONE after charging. The full uint64 index is compared
before narrowing. Existing fetch clipping, atomic copy, gas-deficit and local error
contracts apply unchanged; r7 returns the full selected encoding length.

S(w) is exactly 62 bytes: E4 service index, 32-byte code hash, E8 refinement gas,
E8 accumulation gas, E2 export count, E2 import count, E2 extrinsic count and E4
payload length. These are fixed-width little-endian scalars, not compact integers.
The list prefix counts items, not bytes, with no per-summary length prefixes.
The existing refinement-context codec supplies selector 10's encoding; it is not
reimplemented by the host layer.

Capture encodes metadata once before allocating raw blobs. The private owner adds
425 context bytes (169 + 8*32) and 993 summary-list bytes (1 + 16*62), plus a context
length. Validated codec bounds prove these fixed capacities. FetchPackageLimit
continues to cap only aggregate variable configuration/token/payload bytes; fixed
metadata has an unconditional constant bound. Checked scalar encoding refuses any
unrepresentable metadata as InvalidContext. No new public types or result variants
are introduced. Captures are immutable, acyclic and independent of source lifetimes;
guest calls borrow fixed-buffer slices and do not re-encode or allocate whole values.

Completion evidence: independent literal byte layouts cover every field, multi-byte
counts/lengths, gas above 32 bits, minimum/maximum item and prerequisite counts,
list framing/order, full-width invalid indices, clipping across summary boundaries,
exact/short funding, absent packages, empty copies at invalid pointers, atomic page
faults and local copy caps. Source mutation/destruction and 1,000 capture/fetch/release
cycles exercise ownership. Existing package, fetch, context, host-failure and codec
suites remain regression controls, including tagged-result and nominal/privacy guards.
No upstream source or vectors are copied.

Selector 7 is now covered by [encoded package capture](pvm-fetch-encoded.md), which adds
an explicit FetchEncodingLimit argument alongside the unchanged raw-blob cap.
Remaining: external-input and accumulation fetch selectors, and complete service
invocation assembly. Next bounded increment: external-input capture and fetch.
