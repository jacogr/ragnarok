# Accumulation-input fetch

Scope: fetch selectors 14 (all accumulation inputs) and 15 (input indexed by r11).
Normative source: Gray Paper 0.8.0, gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General
Functions, Omega_Y and accumulation invocation's input sequence;
`text/definitions.tex`, CgasYc/CgasYl entries 14–15; `text/serialization.tex`,
Appendix C.2 transfer and operand encodings and C.1 compact sequence counts.

Selector 14 returns a compact input count followed by ordered tagged C.2 records.
Selector 15 returns exactly one tagged record, without the list count or a new wrapper.
Transfers have tag 1, E4 service IDs, E8 amount, fixed 128-byte memo and E8 gas.
Operands have tag 0, four hashes, compact gas, encoded work result and a variable
trace. Error results have their tag alone; successful results retain blob framing.
The host reuses the existing codec rather than implementing a second serializer.

withFetchAccumulation accepts explicit presence, ordered AccumulationSource values
and FetchAccumulationLimits. The item cap bounds traversal and descriptors; the
aggregate byte cap includes the compact list prefix; OperandLimits apply per record.
The codec's new accumulationInputSize is the encoder's shared allocation-free preflight.
Capture checks every record and aggregate size before allocating. Subtract-after-compare
accounting and a host-int ceiling prevent overflow. Every record occupies at least 132
bytes, also bounding descriptor allocation arithmetic. A second pass encodes one private
list buffer and records per-item spans, without duplicating individual records.

Caller source storage must remain stable until return and may then be changed or
destroyed. Immutable captures are acyclic and preserve parameter, package, trace and
external-input snapshots across replacement/clearing. Absent capture ignores sources
and limits. Present empty input encodes as one zero byte for selector 14; selector 15
then returns NONE for every index. Missing context returns InvalidContext; local
capture limits return LimitExceeded with no partial snapshot. Invocation assembly is
responsible for selecting the correct service's inputs and transfer/operand ordering;
capture does not reorder or authenticate them.

Selector 14 costs 287 + ceil(400*r9/1024); selector 15 costs 355 + ceil(344*r9/1024).
Both charge requested length even for absent or clipped values. Maximal uint64 requests
cost 7205759403792793887 and 6196953087261802851 respectively, below 2^63. The shared
split multiplication remains overflow-safe at the expanded maximum rate of 400.
Selector 14 ignores r11/r12; selector 15 checks full-width r11 before narrowing and
ignores r12. Existing gas-deficit, full-length return, clipping, natural empty-copy,
atomic memory panic and typed local-copy refusal contracts apply unchanged.

Tests contain independent literal transfer/success/error operand encodings, mixed-list
ordering, 127/128/129 count framing, empty versus absent values, full-width indices,
maximal price witnesses, exact/short funding, clipping across record boundaries,
atomic copy failures, local descriptor/byte/record caps, replacement and attachment
preservation, real host dispatch and fresh 1,000-cycle ARC evidence. Existing C.2
codec tests retain alias, result and source-validation regression coverage. Runtime
capture-refusal probes and a compiler privacy guard protect the new owner.
No upstream code or vectors are copied.

All sixteen fetch selectors now have implementations, with explicit invocation data
and configured parameters where required. This is fetch coverage, not full PVM host
or service invocation parity. Complete invocation assembly, remaining host functions
and the documented positive gas-domain gate remain open. The [prepared-input adapter](pvm-fetch-invocation.md) now binds a selected service group
to fetch; complete service invocation assembly remains open.
