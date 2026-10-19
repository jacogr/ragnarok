# Raw work-package fetch selectors

Scope: fetch selectors 8 (authorizer configuration), 9 (authorization token), and 13 (indexed
work-item payload), selected from a validated OwnedWorkPackage. Sources are Gray Paper 0.8.0
at gitlink `07f041dabd073f9018b418e9ee72e79dd2185401`: `text/pvm_invocations.tex`, General
Functions, Omega_Y; `text/definitions.tex`, CgasYc/CgasYl entries 8, 9 and 13; Appendix C.2
package ownership and field encodings. The Sets notation defines none's cardinality as zero.

Configuration costs 84 and token costs 88, independent of requested length. Payload costs
95 + ceil(96*r9/1024), including missing package, invalid index and empty copies. All returns
use raw field bytes, without C.2 length prefixes. r11 indexes items for selector 13 only and is
compared at full uint64 width before conversion. Absent package and out-of-range item return
NONE after charging; a present empty blob returns zero. Other register, clipping, natural
memory interval, gas-deficit and local refusal rules reuse the existing fetch implementation.

withFetchPackage creates a new context retaining the existing immutable entropy/trace snapshot.
It preflights configuration, token and all payload lengths against one FetchPackageLimit before
allocating any blob. Item metadata is fixed at sixteen entries, matching the validated codec
bound. Selected bytes are copied once into private immutable storage; guest calls never decode
or materialize a whole package or payload. The original codec owner need not remain alive.
The additional canonical encoding now has its own explicit FetchEncodingLimit; see
[encoded package capture](pvm-fetch-encoded.md).
The cap covers aggregate variable blob bytes; fixed metadata and retained entropy/trace have
separate existing bounds. An absent attachment ignores its owner and clears only package data.
A present default owner or invalid base context is InvalidContext; a short cap is LimitExceeded.
No partial context escapes. Package validation is structural/resource validation by the codec;
service authorization, current-item identity and invocation eligibility remain caller duties.

Tests use original multi-item codec fixtures to distinguish every blob, empty and absent values,
full-width item indices, requested-length prices, clipping, atomic cross-page failures, aggregate
exact/short capture caps, retained snapshots, caller mutation, replacement/clearing and fallible
host-loop dispatch. Runtime/compile guards enforce private capture results and the nominal cap.
Fresh 1,000-cycle ARC evidence exercises both captures and execution. Existing fetch and codec
suites remain regression controls. No copied upstream source or vector is introduced.

Selectors 10–12 now use [encoded metadata capture](pvm-fetch-summaries.md), with fixed
storage bounds independent of the raw-blob cap.

Remaining: extrinsics/imports, accumulation selectors and complete
service invocation assembly. Positive gas-domain limitations remain documented in
pvm-host-gas.md. Next bounded chunk: external-input capture and fetch.
