<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Default block-local admission

Prepared execution now materializes block metadata on resolution. There is no
`pvmLazyAdmission` opt-in and no eager implementation to select. This changes production
source; it does not replace the interpreter with the standalone port. The maintainer accepted the measured workload trade-offs.

## Ownership and resource boundary

The [checked stream owner](../../src/pvm/internal/handler_stream.nim) admits the full validated
instruction count, byte extent and jump table before execution. A compact immutable
opcode rank index preserves source-global ordinals. Each exclusively leased frame/stream
owns its derived catalogue; visiting blocks out of order cannot change native adjacency
proofs. Resolution fills complete containing blocks, including destinations reached by
existing branch prelinks. Interior entry retains full containing-block gas accounting.

Fact limits still apply to the entire source, not only visited blocks. Node and preparation
limits retain their original refusal boundaries. Returning a stream detaches its mutable
catalogue from the old frame. Stream copy/duplication is forbidden in interpreter-only
builds as well as native builds.

This removes whole-program header decoding and suffix-metadata work from construction.
It does **not** remove the full-sized fact-slot and PC-map allocations: those are reserved
on the first valid resolution, with only resolved blocks filled. Separate frames sharing
an admission owner now have separate mutable catalogues. Immutable rank data remain shared.

## Measured implementation before removing the flag

Local macOS 27.0.1 ARM64, pinned Nimony `fd9742bf1939a1b754144506e89a8acb0e7b747a`,
ARC, Clang, release, speed, bounds checks and ThinLTO. Both binaries enabled the same ARM
backend and receipt support; the selected benchmark backend was `interpreted`.
The candidate differed only by the former admission flag. These are local eager/candidate
comparisons, **not** new PolkaVM ratios or Linux CI qualification.

Each of six guest cases ran in 20 fresh processes per role; each DOOM phase ran in 10.
Order alternated within each pair. Every process performed 13 fully checked calls. Cold
is sample 0; reused is the median of samples 3–12, then the median across processes.
Total: 280 processes and 3,640 checked calls. CPU medians below are microseconds;
negative change means faster. Small differences remain sensitive to timing noise.

| Case | Eager cold | Candidate cold | Change | Eager reused | Candidate reused | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sieve-1000 | 1352.50 | 1005.00 | -25.69% | 41.50 | 40.50 | -2.41% |
| sieve-100000 | 6555.50 | 6235.00 | -4.89% | 3225.00 | 3196.50 | -0.88% |
| minimal-1000 | 115.50 | 116.00 | +0.43% | 48.75 | 48.00 | -1.54% |
| memset-1000 | 234.50 | 235.00 | +0.21% | 50.50 | 53.00 | +4.95% |
| minimal-100000 | 4895.00 | 4858.50 | -0.75% | 4786.75 | 4726.25 | -1.26% |
| memset-100000 | 3915.00 | 3929.50 | +0.37% | 3698.50 | 3704.50 | +0.16% |
| doom-init | 233654.50 | 237194.00 | +1.51% | 214414.75 | 215665.75 | +0.58% |
| doom-tick | 28532.00 | 26899.00 | -5.72% | 14546.75 | 14577.00 | +0.21% |

Sieve-1000 constructor CPU fell from 500.5 to 24 microseconds (95.2%). DOOM tick
constructor CPU fell from 2,574 to 219 microseconds. Complete cold calls include
allocation, execution, snapshot capture and other work, so constructor savings do not
translate one-for-one into end-to-end savings. DOOM init and short reused memset retain
the regressions shown above. Earlier visit-order ordinal results are superseded because
they could change native adjacent-block coverage.

## Confirmation with the unconditional default

Rebuilt without `pvmLazyAdmission`, verified the eager binary hashes were unchanged,
and repeated the same 280-process / 3,640-call comparison after all compilation and tests
finished. Every guest state, memory and DOOM event check passed. CPU medians in microseconds:

| Case | Eager cold | Default cold | Change | Eager reused | Default reused | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sieve-1000 | 1345.00 | 911.00 | -32.27% | 40.50 | 39.50 | -2.47% |
| sieve-100000 | 6617.50 | 6377.00 | -3.63% | 3234.75 | 3199.25 | -1.10% |
| minimal-1000 | 112.50 | 117.50 | +4.44% | 49.00 | 48.00 | -2.04% |
| memset-1000 | 235.50 | 230.00 | -2.34% | 49.50 | 48.75 | -1.52% |
| minimal-100000 | 4863.00 | 4755.00 | -2.22% | 4723.00 | 4693.75 | -0.62% |
| memset-100000 | 3908.50 | 3895.50 | -0.33% | 3690.50 | 3660.75 | -0.81% |
| doom-init | 235595.50 | 233033.00 | -1.09% | 213798.25 | 216739.00 | +1.38% |
| doom-tick | 30062.50 | 26860.50 | -10.65% | 14681.50 | 14763.50 | +0.56% |

The cold improvement persists across both runs: Sieve-1000 is 26–32% faster and DOOM
tick 6–11% faster. Small-case and reused differences vary; this does not establish a
uniform speedup. In this confirmation DOOM initialization is 1.1% faster cold and 1.4%
slower reused. The earlier short-memset regression remains recorded rather than being
discarded in favor of this round. Native Linux qualification remains outstanding.

## Optimization-switch audit

The audit covered `defined(...)` and runtime environment switches throughout `src/pvm/`,
plus build requirements and test consumers. No other dormant production optimization
was found behind a required opt-in in this tree:

- `pvmArm64Jit`, `pvmX86Jit` and `polkavmRuntime` select architecture/backend linkage.
- Resident read-cycle registers, budget registers, role registers and credits are already
  enabled by the normal x86 profile. Their named switches select explicit proof profiles;
  the maintained credit witness requires its exact set of flags.
- Memory-cycle seal/native and wide-cycle proof switches expose mechanical proof helpers.
  Ordinary x86 builds already include the corresponding lowering via `pvmX86Jit`.
- Receipt/witness/refusal flags provide observations or inject failures in tests.
  `pvmSharedReadCycleOff` is an explicit feature-off control; the connected read cycle is
  enabled normally on supported native hosts. Allocator/platform definitions retain their
  separate memory and ABI contracts.

Those controls remain; none is required to activate block-local admission. No new
optimization flag or runtime option was introduced.

## Evidence and reproduction

The measurements used base `bd849a2582596608d5138a0c162dd35c4601b954` plus the admission
patch. The PR applies only that admission change on
master `f846bb18`; the standalone comparison commits are not part of its diff. Original measured sources, binary SHA-256 identities and all samples are
retained under ignored `build/lazy-admission/`: `measured-source/`, `identity.json`,
`prototype-measured.patch`, `flagged-controls/` and the observation JSON files.
The `baseline-guest` and `baseline-doom` binaries are frozen eager controls. The old
baseline build script now refuses execution: rebuilding it from the default source
would produce another lazy binary and invalidate the comparison.

`build/lazy-admission/build.py` builds the candidate with no admission definition;
`measure.py` runs unchanged canonical guest/DOOM drivers against those frozen controls.
Its compile and run arguments are recorded in `builds.json`, the archived
`baseline-builds.json` and the runner scripts. Inputs and expected state remain the
existing faithful comparison fixtures. Native Linux ARM64/x86 and the complete
22-workload comparison remain unrun for this change.

## Default-path validation

All 22 selected Hastur native suites passed with no admission define: program decode,
all opcodes, accounting, entry boundaries/reuse, batch/store-loop paths, host resumption,
memory pairing, publication, region/sparse access, resource and transfer limits, pricing
ownership, scalar hosts, prepared reuse, checked-read arbitration, ARM asynchronous
execution, read-cycle receipts and the new lazy-admission witness.

Prepared reuse completed 1,000 cycles with occupied bytes unchanged at 445,760.
The new `pvm_stream_catalogue_copy` compiler guard rejected duplication with the exact
`'=dup' is not available for type <FlatStream>` diagnostic in an interpreter-only build.
Verification inventory passed, as did all 11 native-requirement harness tests. Pinned
formatting and `git diff --check` passed. Recorded commands and results are in
`build/lazy-admission/default-validation.json`; candidate/source identity is in
`default-identity.json`. This is local coverage, not a claim of Linux x86 execution.

## PR integration validation

The admission change applies on master `f846bb18`, which adds ranked mixed-loop arenas.
All 22 selected native suites pass on this integration, including the new paid mixed-loop
witnesses in the ARM asynchronous profile. The newly landed source-discovery and continuation
helpers now read immutable source or the active frame's catalogue instead of assuming the
admission owner eagerly contains every fact. A focused native-entry profile also passes
all 18 fused-entry scenarios with the existing correctness assertions intact.
The exact copy-refusal guard, stable 1,000-cycle ARC check, formatting, inventory and 11
requirement-harness tests pass. Integration evidence is under the PR worktree's ignored
`build/lazy-admission/pr-validation.json`. Performance tables above retain their original
measured source identity; no Linux performance result is inferred from these local tests.
