# Report-derived accumulation operands

Target: Gray Paper 0.8.0
[`07f041d`](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/accumulation.tex),
Execution `operandtuple`, `accpar` service enumeration and `accone`'s `i^U` comprehension.
This slice prepares the report-derived part of service inputs. It does not execute accumulation,
select a gas-dependent prefix or publish execution-dependent state.

## Contract

`src/state/accumulation/operands.nim` consumes the immutable priority projection from
[queue planning](accumulation-queue.md) and an explicit nominal `AccumulationReportPrefix`.
The prefix must be within the **accumulatable priority sequence**, not the raw edited queue;
zero is a valid empty projection. The caller's choice does not certify gas affordability or execution.

Each selected report contributes every digest, in report order then digest order. Digests are
filtered by service and grouped under numerically increasing service IDs. Sorting uses an explicit
source ordinal to preserve inner order without assuming sort stability. The service set here is
only the union of selected digest service IDs: transfer-only and always-accumulate-only services
belong to a later complete invocation-context slice.

For each digest the seven fields are copied exactly:

| Operand | Source |
| --- | --- |
| Package identity | Report availability specification's package hash |
| Segment root | Report availability specification's segment root |
| Authorizer | Report authorizer hash |
| Payload hash | Digest payload hash |
| Gas limit | Digest accumulation gas |
| Work result | Digest success bytes or exact work-error discriminator |
| Authorization trace | Report authorization-output bytes |

Code hashes, report authorization gas and refinement load metrics are not operand fields.
All six work errors remain valid values, and every result alternative retains its trace.
Empty successful output is distinct from a work error. No payload padding, synthesized successful
result or fallback representation is introduced. Wire construction uses the established
[C.2 operand codec](c2-records.md), including natural gas rather than the digest's E8 representation.

`OwnedReportInfo.authBytes` adds copied authorization-output length metadata for bounded preflight.
It exposes no source coordinates and changes no report wire format. Preparation copies payloads
only through their exact report owner and digest index, then encodes/captures a complete C.2
`OwnedOperand`. Child operands survive source report, group and prepared-plan scope exit.

`prepareAccumulationOperands` returns a private immutable projection owner retaining the queue,
selected prefix and service groups. Getters expose copied service/count metadata and retained
operand handles, never mutable group arrays. `prepareBlockAccumulationOperands` additionally
requires/retains the genuine block queue from completed report admission. Its wrapper separately
exposes that source and the prepared projection; a pure helper cannot forge the bound handle.
Both paths are read-only and perform no hashing, account lookup or state publication.

## Resource and failure policy

Independent caller ceilings bound selected reports, total digest/operand descriptors, distinct
services, aggregate copied blob bytes and complete retained operand wire. `OperandLimits` also
bounds each result blob, trace, combined blob extent and whole record. A shared report trace is
charged once **per actual operand**, matching the independently retained C.2 records.

All counts and sizes are checked before conversion/addition. Exact wire sizing follows the C.2
framing; aggregate wire fits a native byte extent. Complete prefix metadata and distinct-service
bounds are checked before any payload buffers or operand owners are constructed. A later refusal
returns a reason-only tagged result and releases earlier scratch. Descriptor/byte ceilings which
cannot fit native extents return `InvalidConfig`. Allocation exhaustion retains the existing
fail-stop policy. Materialization uses bounded transient source/encoding buffers as well as retained
wire; aggregate byte limits describe retained records, not an exact peak-process-memory ceiling.

Preparation preserves individual gas values, including the full unsigned domain. Summing gas
with transfers/free allowances and deciding an executable prefix are separate work. This module
must not be used as an execution outcome or complete `Psi_A` invocation context.

## Verification

`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`
provides the affected supported verification groups. Linux CI is separate evidence.

The native suite compares complete operand bytes against an independent mathematical projection
and the existing Python C.2 wire reference. Six unchanged pinned accumulation STF inputs are run
at empty, half and complete priority prefixes (18 projection cases), retaining tiny/full profiles.
Vector revision is `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; existing SHA-256 checks remain mandatory.
These are report-input projections, not complete accumulation STF execution or expected PVM outputs.

Another 128 deterministic authored cases vary services, report/digest ordering, prefix length,
all seven work-result alternatives, authorization traces and natural-gas/blob boundaries.
Literal native and Python witnesses independently anchor the field mapping and filtering order.
Native cases test exact/one-below independent budgets, default owners, invalid prefix/index/native
extents and valid empty preparation. A genuinely signed admission/assurance case reaches the bound
adapter with hashing poisoned, retains its source provenance and leaves the parent root unchanged.
A 1,000-cycle success/late-refusal workload requires identical live ARC occupancy.

Five privacy, three nominal-domain compiler probes and nine strict runtime result-access probes
protect the new boundaries. Prepared child payload extraction remains under the existing C.2
owner contracts.

## Invocation context and next bounded work

[Invocation-input preparation](accumulation-inputs.md) now adds explicit deferred transfers before
report operands, always-accumulate-only services and checked per-service gas sums. That layer retains
this projection and its selected prefix. [Initial round planning](accumulation-round.md) now selects
the gas-bounded prefix and binds parent privileges. Service-account execution-context binding comes
next; PVM execution and posterior state integration remain separate.
