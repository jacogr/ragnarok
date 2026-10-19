# Optional entropy and trace fetch context

Scope: immutable context selection for fetch selectors 1 (entropy) and 2 (authorizer trace),
including absent values, plus the unknown-selector branch for r10 >= 16. Selectors 8, 9 and 13 are now supplied by [package blob capture](pvm-fetch-package.md).
Other known selectors remain explicit UnsupportedSelector errors, not fabricated absent values. This module
handles host identifier 2 only; selecting a host identifier remains the dispatcher's job.

Normative source: Gray Paper 0.8.0 gitlink `07f041dabd073f9018b418e9ee72e79dd2185401`:
- `text/notation.tex`, Sets: none's cardinality is explicitly defined as zero.
- `text/pvm_invocations.tex`, General Functions, Omega_Y: clipping, permission and NONE rules;
  host return-value definitions set NONE to 2^64 - 1.
- `text/definitions.tex`, CgasYc/CgasYl: selector 1 costs 103; selector 2 costs
  80 + ceil(96*z/1024); unknown selectors cost 80 with zero per-byte rate.

This resolves the earlier absence gate using the pinned source, without changing dependencies or
assuming semantics from another implementation. For absent v, f and l are zero. The empty natural
interval is writable for every pointer, so funded absence returns NONE and unchanged memory.
A present empty trace instead returns zero. Gas still depends on selector and requested z, even
when no bytes are copied. Underfunding precedes all table mutations and retains the exact deficit.
An invalid local memory owner remains an API error, even on an empty or underfunded operation.

captureFetchContext copies selected entropy and trace into a private immutable acyclic ARC owner.
FetchPresence distinguishes absent from present empty. Absent payload arguments are ignored and
not copied. FetchTraceLimit caps variable trace bytes before allocation; the fixed-size entropy
field does not consume that local cap. Oversized present traces fail without a partial owner.
Default handles are invalid; explicitly captured all-absent contexts are valid. Shared handles do
not expose any mutable storage, and caller input mutation cannot affect later responses.

fetchContextResponse reads selector r10 from the guest and reuses the existing fetch charging and
copying path. Context and memory failures, unimplemented selectors and copy-budget refusals remain
FetchError values; the fallible host loop propagates them without inventing guest exits. The
response-only present-value functions remain supported. Context selection does not establish that
supplied values belong to a valid JAM service invocation; callers still validate and choose inputs.

Completion evidence: independent absence gas witnesses, exact/short gas, maximal requested length,
empty versus absent trace, pointer/offset extremes, every known unsupported selector, unknown
selector boundaries, context/input/response ownership, real fallible host-loop integration, default
and refused result guards, privacy/nominal compilation checks and 1,000 fresh native ARC cycles.
The present fetch and host-failure suites retain clipping, memory and dispatch regression coverage.
No upstream code or fixture is copied. These witnesses establish this subset only.

Remaining: encoded/summary and external-input selector families, service invocation context
assembly and complete invocation/gas accounting. The positive gas-domain gate in pvm-host-gas.md is unchanged. Next bounded chunk:
encoded refinement context and work-item summaries.
