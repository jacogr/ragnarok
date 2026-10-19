# Prepared accumulation fetch adapter

Scope: select one service group from PreparedAccumulationInputs and attach its exact
ordered inputs to an existing FetchContext. Normative source: Gray Paper 0.8.0,
gitlink `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex accone/operandtuple,
pvm_invocations.tex Omega_Y selectors 14–15, serialization.tex Appendix C.2.

withInvocationFetch accepts a nominal InvocationServiceIndex, never a protocol service
ID or raw input array. Existing preparation supplies transfer-before-operand ordering
and report/digest order. The adapter does not sort, filter, credit transfers or reinterpret
work errors. An allowance-only service attaches a present empty list; default plans and
out-of-range ordinals are local typed failures, not absent invocation inputs.

The adapter checks the base context, selection, count, descriptor extent, every fresh
record policy and aggregate count-prefixed byte extent before allocating source storage
or copying blobs. The C.2 ownedOperandSize shares the owned encoder's policy revalidation.
All additions and narrowing are bounded first. Immutable plan owners remain stable across
the preflight and conversion passes. Temporary payload copies are bounded by the aggregate
wire budget, with separately count-bounded source descriptors. The existing host capture
encodes the final private list buffer; temporary conversion storage is released on return.
No borrowed span escapes, and unrelated fetch attachments survive replacement.

Completion tests cover exact prepared transfer/operand encodings, service isolation, ordering,
allowance-only empty lists, invalid/default/full-width selections, fresh limits, retained
contexts after source destruction, and repeated ARC release. Existing host tests cover gas,
memory atomicity and real dispatch; the adapter reuses that implementation unchanged.

This is a pure projection adapter, not evidence of block admission, account eligibility,
transfer credit, PVM invocation or posterior-state publication. All fetch selectors exist;
full invocation assembly and remaining host functions are still open. The
[machine adapter](pvm-accumulation-machine.md) now initializes a PVM machine from the
existing bootstrap arguments and service code gate. Complete accumulation
host-context assembly remains open.
