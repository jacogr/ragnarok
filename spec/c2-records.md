# Availability specifications and accumulation records

Current target: unreleased Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Appendix C.2
`avspec`, `defxfer` and `operandtuple` equations; `reporting_assurance.tex` availability/valcount;
`accumulation.tex` operand/transfer domains and report-to-operand mapping; and `definitions.tex`
unsigned balance/gas domains and `Cmemosize = 128`. Complete consumed chapter hashes are in
[pins.json](pins.json), now including accumulation. No source/gitlink/toolchain upgrade occurs.

## Wire and fixed records

`AvailabilitySpec` contains package hash32, E4 bundle length, erasure root32, E2 erasure shards,
segment root32 and E2 segment count, exactly **104 bytes**. It reuses existing nominal report field
types. There is no tag, context field or variable count around the standalone tuple. A caller
`AvailabilityConfig` supplies 2..341 cores and a complete-prefix byte budget. Shards must be a
multiple of three from six through three times that ceiling. This matches the existing report
structural domain; equality with the actual assuring validator set and correctness of roots,
bundle length or exported segments remain state/availability checks. Config precedes input;
complete fixed input precedes shard policy and byte budget. No new segment-count/bundle-size
protocol constraint is invented beyond their E2/E4 wire domains.

`DeferredTransfer` includes canonical natural tag **one**, E4 source service, E4 destination
service, the strict one-byte destination-supervisor Boolean, E8 balance, the
**fixed 128-byte memo with no length prefix**, and E8 gas. Total size is
**154 bytes**. Only 0/1 are Boolean encodings; any other octet returns `NonCanonical`. Balance is nominally distinct from gas, memo from arbitrary arrays, and existing
service/gas types are reused. Zero amounts/gas or arbitrary service identities/memos are
structurally representable; account existence, transferable balances, memo interpretation and
execution eligibility are external. Outer tag canonicality/schema precedes fixed input extent,
then whole-prefix budget. Both fixed record decoders copy complete values and retain no input.

`encodeAvailability` / `decodeAvailability` and `encodeTransfer` / `decodeTransfer` return tagged
`RecordResult` values. All decoders consume one prefix; a standalone consumer must separately
require full input consumption when trailing bytes are prohibited. Caller suffixes are not part
of the byte budget. Fixed source records use supported Nim `byref` annotations so encoders can
protect their original field/descriptor storage against the whole written destination.

## Operand and accumulation union

`AccumulationOperand` wire order is canonical natural tag **zero**, package hash32, segment
root32, authorizer hash32, payload hash32, **general natural gas**, the existing C.2 work-result
encoding, then natural authorization-trace byte length and trace bytes. Unlike transfer and
work-digest accumulation gas, operand gas is **not E8**. Hash roles remain nominally distinct.
The existing `WorkKind` domain is reused: success zero plus a variable result blob, or error
one through six with no result length/payload. A final trace is present, possibly empty, for
all work-result alternatives. Empty success with zero gas/trace is 133 bytes; an error equivalent
is 132. Gas 128 occupies two natural octets rather than eight fixed octets.

The synchronous source API contains typed fixed fields, a tagged `OperandOutput` with a mutable
sequence only on success, and a trace sequence. These are borrowed only for the stable encode
call; no detached payload spans enter the public source API. `OperandLimits` explicitly bounds
success-result bytes, trace bytes, their aggregate payload, and whole serialized prefix bytes.
These are caller resource policy, not invented standalone consensus constants. Callers importing
operands from reports must also enforce their enclosing report/state constraints. Work errors
consume no result budget; transfers consume no operand-only blob budget.

`decodeOperand` validates the outer tag, all fixed hashes, natural gas, complete existing work
variant, trace and all limits **before** allocating a snapshot. Child counts stay uint64 until
complete input proves host extent; aggregate subtraction is bounded by prior payload checks.
Canonicality/child payload policy precedes announced payload presence. Fixed/gas/work/trace
complete extents then check the whole-prefix budget in wire order. Every failed late field
discards all earlier hashes, payload coordinates and cursor progress.

Success produces private acyclic ARC `OwnedOperand` storage for the exact validated prefix,
excluding suffixes, and its internal matching layout. Input stays stable during the call and may
then be changed/released. Last-owner destruction releases the bytes; allocation exhaustion retains
Nim's existing fail-stop behavior. `operandInfo` copies fixed metadata and lengths. Its tagged
output metadata has a length only on success. `copyOperandOutput` / `copyOperandTrace` extract
only through the matching owner; work errors return `NoPayload` for output extraction. Mutable
wire storage, pointers and detached coordinates never leave the owner. Extracted bytes are
independent copies. Defaults return `InvalidOwner`, distinct from valid empty payloads.

`encodeOwnedOperand` revalidates against the current caller's limits before capacity/alias checks
and exact re-emission; broader original capture cannot bypass a stricter new policy.
`decodeAccumulationInput` selects an owned operand or copied transfer by the same outer zero/one
already on wire, without adding another union discriminator. Its successful `AccumulationValue`
has only the selected alternative. `encodeAccumulationInput` accepts independently constructed
sources, validates that selected child and protects the entire union descriptor before child
encoding. Unsupported outer tags return `InvalidTag`; overlong tags return `NonCanonical`.

## Atomicity and result discipline

Before writing any byte, source encoding validates all source/cardinality/payload policies,
checked aggregate wire arithmetic and whole output capacity, then aliases. Operand checks cover
its descriptor and every byte of both borrowed sequences against the whole written destination,
including later blobs that an earlier tag/hash would otherwise overwrite. Fixed encoders protect
all borrowed fixed fields; the union additionally protects its tag and active/inactive descriptor
storage. Committing uses already validated stable sources and has no remaining failure path.
Failure leaves the whole destination unchanged; success preserves spare suffix capacity.

Owner copies/re-emission protect the caller handle descriptor (using supported `byref`) and
reject destinations overlapping any byte of private wire, even outside the selected extracted
payload. Empty extraction needs no valid destination element
address and writes nothing. Default/failed `RecordResult` alternatives carry only a reason, never
values, owners or progress. Work errors are valid decoded values, not decoder failures. All
selected output/union/result contracts remain enabled in checked optimized builds. On the Nimony
port, status and variant tags/payloads are private; public properties are read-only and selected
accessors require their matching success/work/union alternative.

## Verification

Historical release corpus counts below describe their original schemas. Current transfer
consumers use 154-byte records with the destination-supervisor flag; see
[the coordinated upgrade](graypaper-unreleased-upgrade.md) for migrated evidence.


Run `make check`. Eight literal known answers
protect independent Python construction/parsing. The historical Nim 2.2.12 ARC/Clang LTO compared
**26,090** deterministic requests: independent named encoder sources, copied fixed/owned fields,
exact bytes/prefixes, union/standalone agreement, every work-result alternative, empty values,
natural gas/count transitions, fixed E8 gas, maximum unsigned fields, every shard count through
1026 plus the E2 maximum under tiny/full ceilings, invalid core configurations, fixed memo bytes,
every small truncation, sampled larger boundaries, exact/short/spare capacities, all explicit
payload/aggregate/wire policies, invalid/overlong tags, hostile uint64 blob claims and mutations.

Exact 104-byte availability prefixes match pinned tiny/full published work-report binaries and
JSON. Operands constructed from named report/digest fields follow the pinned accumulation mapping,
but are explicitly **derived** fixtures; there is no published standalone transfer/operand codec
family at this vector pin. Transfer cases are independently authored against C.2. No roots,
signatures or state transitions are inferred from those structural fixtures.

Native tests cover destructive caller mutation, retained handles, fixed copies, extracted-copy
independence, stricter retained limits, defaults, whole-descriptor/cross-blob/private-wire aliases,
atomicity and work/union/result variant guards. Three nominal and one privacy compiler probe
require intended rejection. White-box alias tests include only this project's own module, using
no private compiler/runtime APIs. Linux CI runs the same checks and retains build commands, logs,
compiler diagnostics and request digest/results under ignored `build/tests/runtime/`. Local
verification is
macOS arm64; Linux x86-64 verification occurs after push. This closes the concrete C.2 framing gaps
in the M1 audit, not state serialization/Merkle layout, PVM execution or accumulation semantics.

## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

Reproduce the checked ARC/Clang LTO coverage with
`make runtime`. All 26,090 independent requests,
eight oracle known answers and both native suites are retained. The cumulative runner adds 56
isolated result/variant/constructor misuse checks and 41 privacy/nominal compilation rejections.

Source work alternatives use `successfulOperandOutput`/`failedOperandOutput`; payload edits require
`editOperandPayload`, while `operandPayloadCopies` returns independent bytes. `operandSource` and
`transferSource` keep source union tags and values together. Source getters copy; decoded operand
getters retain immutable storage and transfer getters copy fixed fields. Encoder internals access
the actual private source fields so descriptor/payload alias checks protect original storage.
Metadata lengths and inactive source/decoded branches have explicit selected-alternative contracts.

Retained source escape/replacement, copied source/payload/metadata independence and warmed ARC
release extend native lifetime checks. After 100 warmups, 1,000 isolated cycles, including all six
work-error alternatives, return live allocator occupancy to baseline. This measures that workload,
not RSS or general leak freedom. Commands, source/request/output hashes, exact release counts and
individual verdicts are retained in `build/tests/runtime/results.json`. See
[the compiler record](../docs/nimony-trial.md) for compiler/environment, cumulative totals and the
next bounded
work. Verification is local macOS ARM64; complete M1, Linux and M2/M3 migration remain unverified.
