# Encoded work-package fetch

Scope: fetch selector 7 returns the complete canonical work-package encoding from
an explicitly captured package. Normative source: Gray Paper 0.8.0, gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General
Functions, Omega_Y selector 7; `text/definitions.tex`, CgasYc/CgasYl entry 7;
Appendix C.1/C.2 for canonical work-package encoding.

The price is 85 + ceil(96*r9/1024), based on requested rather than copied length.
Both item registers are ignored. Funded absence returns NONE without touching
memory; a present package returns its full encoded length even for a clipped or
empty copy. Existing fetch atomic memory, natural interval, gas-deficit and local
copy-policy rules apply. Maximal uint64 requests use the existing overflow-safe
price calculation and cost 1729382256910270549.

withFetchPackage now requires an additional nominal FetchEncodingLimit argument.
FetchPackageLimit still covers only aggregate raw configuration, authorization and
payload bytes. FetchEncodingLimit independently caps the additional full encoding,
including all framing and manifests. Both budgets are checked before any variable
capture allocation. Thus total variable storage is bounded by the sum of the two
budgets, with the existing constant metadata bound; implementation never needs to
add the budgets in machine arithmetic. Absent attachment ignores both budgets and
the supplied package and clears all package state. Invalid base/owner errors and
tagged-result extraction contracts are unchanged.

The codec's consumed prefix length determines the allocation. The existing
encodeOwnedWorkPackage operation copies the validated immutable encoding, excluding
unrelated trailing input. No independent host-layer serializer or normalization is
introduced. All package selectors use the same capture, so there is no partially
available package whose selector 7 incorrectly reports absence. Guest calls borrow
the stored encoding and allocate only their existing memory-copy response. The
codec owner and caller buffers need not survive capture. Snapshots remain acyclic
and immutable; replacing or clearing one handle does not alter retained handles.

Completion tests use an independent 653-byte C.2 layout with two work items,
multi-byte blob lengths, distinct hashes, gas above 32 bits, an import and an
extrinsic commitment. The encoder is checked against those literal bytes before
capture; fetch and real host-loop output are checked against the same independent
witness. Tests cover ignored index registers, exact/short and maximal capture caps,
trailing decoder input, source mutation/destruction, clipped copies at framing
boundaries, maximal requests/offsets, exact/short funding, absence, zero copies at
invalid pointers, atomic cross-page panic, local copy refusal and 1,000 ARC cycles.
The existing failure family also rejects payload extraction after encoding-cap
refusal, and a compiler guard enforces the nominal encoding limit. Existing fetch,
summary, raw-package, host-failure and codec suites remain regression controls.

Implemented package fetch scope is now selectors 7–13. Remaining fetch families:
constants (0) and accumulation inputs (14–15). External inputs (3–6) are now covered
by [external-input capture](pvm-fetch-inputs.md).
Complete invocation assembly and the documented positive gas-domain gate remain
open. Next bounded increment: protocol-parameter fetch selector 0.
