# Decode-once memory operand facts

## Scope and acceptance

After the rejected [execution-time opcode descriptor](https://github.com/jacogr/ragnarok/blob/ca7a585faca04fb5ee8f7878f3840929f3546039/spec/pvm-memory-descriptors.md),
the maintainer explicitly directed: “Decode once, always use.” This authorizes a
new ownership/representation experiment, not another table variant or a change to
the prior rejection. Baseline is `ca7a585faca04fb5ee8f7878f3840929f3546039`,
whose runtime equals merged `98165f471684c217a6d959c1c021fd34d568ef54`.

The existing owner decoder derives width, load/signed flags, address-base role and
immediate/register store source once after operand validation. The existing
successful `ProgramResult[Instruction]` retains these private scalar facts through
its existing instruction caches. A success-guarded accessor supplies a copied
`MemoryOperands` value with read-only queries. No mutable owner, new cache, new
intermediate instruction stream or assumption is introduced. Raw operand copies
cannot change or rebind these facts. Non-memory/default fact values have width0;
failed/default decoded results never authorize a fact query.

The private memory executor consumes the facts directly, with no opcode set/range
decoding or descriptor lookup. Preserve address arithmetic, signed extension,
register alias ordering, result checks, PC/fault behavior, ARC ownership, compiler
checks and dependency/fixture/driver pins. Gray Paper behavior and approved memory
fault ordering remain in [the machine](pvm-machine.md) and
[memory ordering](pvm-polkavm-memory-order.md) contracts. Call-frame changes remain
separate and pending, as requested.

Retain the earlier gate: at least eight fewer exclusive wrapper instructions per
Pinky memory operation and lower complete execution instructions on Pinky,
fill100000 and indirect100000. Include decoder work and cache-copy costs in the
whole-execution counts; do not move work into an unmeasured preparation phase.
Use local deterministic counts when available, otherwise the existing calibrated
Linux CI attribution path. All timing runs stay on CI.

Only after the counter gate passes, run the complete paired CI timing matrix in
both process orders with identical-image controls. Require a repeatable Pinky gain
above control variation and no reproducible regression above2% on fill, indirect
calls or host/cross-page controls. Stop if qualification fails; preserve the exact
candidate and report its tradeoff without silently combining the pending frame
change to rescue it.

## Verification

A checked native size probe records unchanged `Instruction`/result sizes of56/64
bytes before and after: the five byte-sized facts fit the existing alignment gap
before `skip`. Existing fixed cache entries therefore retain their footprint.
The pinned formatter and checked memory-step suite pass, including independent
width/sign/source/base expectations for all30 memory opcodes, saturated/aliased
registers, all address boundaries, exceptions/retries and1000 ARC cycles.

New privacy guards reject access to the decoded instruction's raw fact field and
the copied fact's raw width field. New runtime refusal witnesses cover default,
invalid-owner and unmarked-PC results, with a valid control retaining facts across
source-owner retirement and mutations to a detached operand copy. All ten selected checked suites pass: program, operand reference, program fuzz,
memory step, execution/cache, access/final-address references, host reentry and
mixed programs. Two privacy guards, three strict runtime refusals and the valid
owner/copy control pass. CI image/full-state controls, instruction counts and paired timings are recorded
below; the local verification does not substitute for those Linux results.

## Instruction gate: passed

[CI40179804111](https://github.com/jacogr/ragnarok/actions/runs/40179804111)
profiles exact code `a09c87a3c8ac7fba6761cad9980d71f599eec32f`. All six raw
profile hashes/parser outputs, generated C and pinned Rust source hashes, strict
image controls and the full54-cell/2808-invocation same-image summary replay
successfully. Reference memory counts remain exactly equal to the retained
baseline on all three guests.

| Guest | Guest memory operations | Wrapper instructions/access, baseline → decoded facts | Saved/access | Total native instructions, baseline → decoded facts |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 8,066,877 | 68.916619 →54.793686 | 14.122932 | 5,048,924,258 →4,938,153,420 (−2.1939%) |
| Fill100000 | 300,101 | 66.000933 →54.333664 | 11.667269 | 194,622,517 →191,136,097 (−1.7914%) |
| Indirect100000 | 1,000,015 | 69.400078 →54.600116 | 14.799962 | 421,594,943 →408,837,326 (−3.0260%) |

Pinky removes113,927,957 wrapper instructions and adds2,250,213 instructions in
`decodeMemoryOperands` plus906,906 in `instruction`, for a net110,770,838
instruction reduction. Every other native function's exclusive count is unchanged,
including the cache-hit/execution function. Thus the footprint-preserving retained
facts add measured decode work without increasing measured cache-hit copy work.
The fill/indirect profiles show the same three-function attribution pattern.

Native Linux assembly reads the five cached facts directly from the genuine
result and contains no memory-opcode decoding/table lookup in the wrapper. Its
existing successful-decode guard, checked memory calls and six-register saved
frame remain. No frame/inlining change is included.

The counter gate passes. Paired timing
[CI40180647462](https://github.com/jacogr/ragnarok/actions/runs/40180647462)
compares this exact runtime with baseline `ca7a585f` in both process orders,
with full-state and same-image controls. Both matrices pass all2808 invocations.


## Timing verdict: retained with measured tradeoffs

The paired runner is AMD EPYC7763; percentages below use warmed CPU medians and
show both process orders. Negative values mean faster. The controls run the same
candidate image on both sides. These are paired measurements, not comparisons
between separate runners.

| Workload/policy | Candidate change | Same-image control change |
| --- | ---: | ---: |
| Pinky planned | −1.102% /−2.246% | +0.398% /+0.462% |
| Pinky memo | −1.838% /−1.391% | +0.005% /−0.008% |
| Long indirect planned | −3.890% /−3.665% | +0.393% /+0.022% |
| Long fill dynamic | −6.374% /−10.210% | +0.107% /−0.027% |
| Long fill planned | +2.084% /+1.516% | −0.039% /−0.197% |
| Arithmetic10000 dynamic | +5.696% /+6.434% | +0.657% /−0.927% |
| Mixed bits dynamic | +6.081% /+6.823% | +0.500% /−0.031% |
| Mixed bits memo | +5.231% /+4.772% | +0.105% /−0.087% |

All54 workload/policy cells remain in the CI artifacts. Planned aligned,
cross-page and sparse memory cases improve in both orders; dynamic crossing
cases have mixed control variation. Host cases change sign between orders and
do not establish a repeatable host win or regression. Pinky dynamic is also not
an independently qualified gain in both orders against its controls.

The counter gate passes and planned/memo Pinky has a modest repeatable timing
win. This is not a universal speedup: the non-memory dynamic/memo regressions
above exceed their controls. The maintainer explicitly requested retaining the
decode-once design even below10%; retain this unit with those tradeoffs exposed,
not as a clean pass of a broad no-regression claim. The separate call-frame
experiment must compare against this exact retained runtime and qualify on its
own. No cause for the timing regressions is established by these measurements.

## Larger-program follow-up

The maintainer supplied two DOOM candidates to complement the short controls.
At `clw8998/jam_doom` revision `89aaf040e997853a9b15b40294d585e62e926464`,
[`doom_1000_steps.pvm`](https://github.com/clw8998/jam_doom/blob/89aaf040e997853a9b15b40294d585e62e926464/src/doom_1000_steps/doom_1000_steps.pvm)
is5457074 bytes; its README documents a1000-frame endpoint, GP0.6.6 format and
640×400×4-byte frames exported in4104-byte segments. Check format/host ABI
compatibility before adding it. A bounded host should hash/validate output
without retaining or displaying roughly1GB of frame data. The README's historical
runtime is not a Ragnarök timing prediction. A smaller deterministic frame prefix
could make a practical CI workload while retaining the complete large program.

[`igankevich/polkadoom` guest source](https://github.com/igankevich/polkadoom/blob/22781e2ba2dc9314b2aebc800369fa4bc5c7b6ca/src/guest.c)
at `22781e2ba2dc9314b2aebc800369fa4bc5c7b6ca` has an unbounded tick loop and
an internal frame counter. Its configure script offers audio selection, no frame
limit; it uses the CoreVM host imports. A bounded adaptation and host ABI work
would be required rather than assuming it is a drop-in fixture. Neither candidate
has been executed or added to the frozen acceptance matrix. Keep short cases to
expose setup/decode costs, and add representative larger programs to measure
cache working sets and amortization over sustained execution separately.


## Review branch provenance

This review unit is based on master `895f300e3efc5ea8fcdb88cccb5267e313818316`;
the diagnostic harness remains independently reviewable in
[PR1585](https://github.com/jacogr/ragnarok/pull/1585). Its runtime files, natural
codec and benchmark guest drivers are byte-identical to the measured candidate
`a09c87a3c8ac7fba6761cad9980d71f599eec32f`. Master and diagnostic baseline
`ca7a585f` have byte-identical PVM runtime, codec and guest drivers; native build,
test and refusal harnesses are also unchanged. Thus the prior selected local
checks and exact experimental Linux measurements cover the same runtime source
and build configuration; they are not described as runs of the review commit.
