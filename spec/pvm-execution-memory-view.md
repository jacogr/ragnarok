# Execution-owned memory view experiment

## Scope and acceptance

The maintainer authorized one experiment after the
[CI attribution](pvm-interpreter-diagnosis.md#deeper-memory-and-execution-attribution).
The frozen comparison baseline is `c6410bbe009515b947b83838c3f06c471260af7b`,
with runtime equal to merged `98165f471684c217a6d959c1c021fd34d568ef54`.
PR1585 supplies the strict image controls and attribution tools; it is unchanged
by the experiment. No compiler, dependency, fixture, driver or gas-policy changes
are included. Gray Paper and approved memory fault ordering remain those of
[the machine contract](pvm-machine.md) and [memory ordering](pvm-polkavm-memory-order.md).

Keep the previous gates: at least10% lower long memory-fill CPU time in both
process orders, a repeatable Pinky gain above identical-image control variation,
and no reproducible regression above2% on indirect calls or the existing
host/cross-page controls. Require checked full-state parity, source/image controls,
meaningful ownership/boundary witnesses and generated-code confirmation before
claiming a result. Timings come from opt-in CI, never this loaded local machine.
Stop if the experiment fails; no sequence of follow-up variants is part of this
bounded experiment.

## Working representation

The existing public scalar writer remains the execution-local mutable identity.
Its private sparse slot vector lazily owns contiguous4096-byte page views, each
with copied bytes and a dirty chunk mask. Cache metadata keeps each physical
tag and immutable epoch permission beside its retaining page owner. The first
successful access materializes a page; private bytes never alias published chunks. Two cached page owners allow complete same-page accesses
to reach their bytes after width, cyclic-address, protected-prefix, exclusive-end,
page-boundary and write-permission checks. Misses and crossings use the existing
complete scalar preflight and its fault precedence. Every load/store still returns
its existing guarded result type. Hot lookup returns a copied slot; page access
borrows the cache owner only through the callback-free operation. Checked ThinLTO
assembly confirms that this path performs no page retain/release or allocator TLS
lookup; cold materialization and publication retain ordinary ARC ownership.

Sealing copies only dirty512-byte spans into fresh immutable chunks, shares clean
snapshot chunks and retires all private page/cache owners before the next epoch.
Read-only materialization does not dirty or replace a snapshot; unchanged
publication can retain those views because its immutable base and permissions
remain identical. Writer aliases share progress; published snapshots retain independent bytes. The executor's existing
fourth-store activation and observation boundaries remain unchanged. Host/mapping
changes operate on immutable published successors, and a resumed execution creates
its own writer. No writable page view or borrowed payload pointer escapes.

The resource tradeoff is explicit: a touched page reads/copies4096 bytes once per
writer epoch even for a narrow read, and retains a private full-page buffer until
a dirty epoch is sealed or the writer retires. This is bounded by the captured page count but can use more
memory and first-touch work than chunk staging. Conversion and publication costs
must remain inside the maintained execution measurement, not be moved into an
unmeasured preparer. Sparse and snapshot-heavy controls remain acceptance gates.

## Verification and evidence

Existing scalar-writer tests cover every width across chunk/page boundaries,
read-only/missing/final pages, cyclic addresses, failure atomicity, aliases,
multiple epochs and1000 ARC retirement cycles. A mixed epoch witness additionally
compares360 sparse/read-only/boundary operations with the independent immutable
scalar implementation, sealing every11 operations and checking all page bytes,
permissions and unchanged source storage.

Local qualification passes all eleven affected native suites: scalar writer,
immutable machine/chunks, memory-access and final-address references, memory steps,
execution/cache, host memory/reentry and mixed-program reference. The final scalar
writer retains unchanged occupied memory over1000 ARC cycles. Five focused private
member guards reject access to the view resolver, page vector, scalar spans/slots
and immutable memory backing. Pinned formatting, inventory and semantic checks pass.

The checked normal-driver Clang ThinLTO disassembly on macOS ARM64 confirms that
complete cached hits reach contiguous private bytes without sparse lookup, span
construction, page retain/release, allocator TLS or first-write chunk cloning.
Cold materialization and immutable publication remain in the same executor scope.
This is code-generation evidence, not a local timing claim. Raw builds/assembly
and test logs remain under `build/pvm16-view/`.

## CI outcome: rejected

[CI40174266361](https://github.com/jacogr/ragnarok/actions/runs/40174266361)
passes at prototype `f0884e120eabb6ab4321cf37545a842b0ef32118` on an
AMD EPYC7763. The prototype is preserved on
`codex/pvm-execution-memory-view`; the active runtime returns to the unchanged
diagnostic baseline. Only `src/pvm/machine.nim` differs between the captured
runtime endpoints. All54 paired cells and2808 full-state invocations pass,
followed by all54 same-image control cells and another2808 invocations. The
control's guest, legacy-synthetic and memo-synthetic binaries are each whole-file
byte-identical. All assertion controls pass in both matrices. The pinned interpreted-reference
pack also completes. Offline summarization independently revalidates both full
matrices and calculates each reversed order from its ten measured samples.

Negative percentages mean lower candidate time. Real-guest rows use process CPU;
synthetic rows use the maintained workload execution clock. These clocks are not
combined. Materialization, dirty publication and private writer retirement stay
inside the executor; every sample starts with the same immutable source.

| Real guest | Pricing | Change, order0 | Order1 | Same-image control, order0 /1 |
| --- | --- | ---: | ---: | ---: |
| Fill100000 | Dynamic | -11.15% | -11.30% | +0.23% / +1.36% |
| Fill100000 | Planned | -5.04% | -5.65% | -0.07% / -0.27% |
| Fill100000 | Memo | -5.33% | -5.44% | +0.25% / +0.08% |
| Pinky | Planned | -2.37% | -0.35% | -4.90% / +1.72% |
| Indirect100000 | Planned | -2.81% | -4.73% | -0.05% / +0.13% |

The primary planned fill result misses the10% gate in both orders. Pinky's
observed change is smaller than the same-image variation, so it does not establish
a repeatable gain. Dynamic fill improves, but that cannot qualify other policies
or override the planned primary and crossing-control gates.

| Synthetic control | Pricing | Change, order0 | Order1 | Same-image control, order0 /1 |
| --- | --- | ---: | ---: | ---: |
| Memory aligned1000 | Planned | -16.28% | -16.27% | +0.42% / +0.33% |
| Memory crossing1000 | Dynamic | +31.02% | +30.05% | -0.48% / -2.16% |
| Memory crossing1000 | Planned | +24.46% | +26.19% | -0.19% / +15.56% |
| Memory crossing1000 | Memo | +23.82% | +24.55% | -1.32% / +0.28% |
| Sparse aligned1000 | Planned | -13.81% | -13.35% | -0.67% / -0.23% |
| Sparse crossing1000 | Planned | +26.17% | +25.20% | -1.11% / +0.11% |
| Hosts aligned1000 | Planned | +3.10% | +6.29% | -0.19% / +1.05% |
| Hosts crossing1000 | Planned | -1.21% | -0.15% | -1.38% / +0.06% |

Crossing memory regresses in all three policies and both orders, with clear
separation from controls in dynamic/memo and sparse planned cases. Other adverse
cells remain visible too: arithmetic10000 dynamic changes+2.75/+3.52%, mixed
bits memo+4.44/+4.47%, and alternating blocks dynamic+5.73/+5.60%.
The complete54-cell summaries, raw samples and source/image hashes remain in
that run's `pvm-revisions-1` artifact and locally under
`build/pvm16-view/ci-pair/`; no unfavorable cell is excluded from qualification.

Code inspection explains the coverage limit, without assigning measured CPU
fractions: complete single-page hits bypass the generic machinery, while crossing
accesses still use full span preflight and resolve/promote both private page owners.
The view therefore adds ownership/metadata work on that path. The aligned results
show that its successful hit path can be cheaper; they do not demonstrate a broadly
faster memory representation or explain all remaining Pinky work. No timing qualification rerun, follow-up variant or runtime PR is pursued after
these decisive failures. The subsequently requested retrospective instruction
attribution is recorded below; it leaves the prototype and rejection unchanged.

**Rejected; experiment stopped.** This implementation is not a supported successor
to the sparse writer. It does not qualify as a way to close the reference gap.
The independent binary-identity fix and attribution tools in PR1585 remain valid;
they are unaffected by this runtime experiment.


## Retrospective instructions per memory operation

[CI40175798852](https://github.com/jacogr/ragnarok/actions/runs/40175798852)
passes at tooling head `e14296d5762ba4f5799b202dcd4dc1649bd32119`.
Captured runtime/driver endpoint manifests are **exactly equal** to the original
`f0884e12` experiment; only historical stress-source provisioning changed. The
initial attempt40175260025 stopped before profiling because its deleted stress
branch no longer supplied commit11f79d97. Make now fetches that immutable object
by its full SHA when absent. No runtime variant or timing qualification rerun was
introduced to collect these counters.

The repaired job passes all three canonical stress image pairs, the full54-cell/
2808-invocation same-image matrix and all six native/reference execution profiles.
Offline review independently verifies every raw profile hash and parser replay,
all captured C/Rust hashes and the strict comparison summary. The new reference
memory-path instruction totals exactly match the prior reference totals for all
three guests. Native/reference memory-operation counts also exactly match each
other and the original profile:8,066,877 Pinky,300,101 fill,1,000,015 indirect.

Use the same inclusive boundaries as the original1.89b versus0.27b comparison:
native `memoryMutation` and descendants, versus the reference's executed raw
scalar memory handlers and descendants. Call-edge costs are counted once; they
are not added to exclusive totals. The source profiles use the same checked
ARC/Clang ThinLTO diagnostic configuration with native `-g` as the original
attribution. These are machine instruction counts per guest memory operation,
not per byte or CPU cycles. Instrumented clocks are discarded.

| Guest | Baseline instructions/access | Prototype instructions/access | Reference instructions/access | Prototype/reference |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 234.39 | 187.76 | 33.14 | 5.67x |
| Fill100000 | 205.76 | 133.55 | 33.08 | 4.04x |
| Indirect100000 | 233.10 | 204.92 | 33.81 | 6.06x |

Pinky's memory path changes from **1,890,787,923 to1,514,617,787 instructions**,
against the reference's **267,346,564**. That removes376,170,136 instructions,
19.89% of native memory-path work, and closes23.17% of the original excess over
the reference. The remaining excess is1,247,271,223 instructions. The view is
closer in instruction work but remains far from the reference.

The unchanged memory wrapper accounts for555,941,887 instructions, **68.92 per
operation**, versus555,941,885 before. Its own work alone remains more than twice
the reference's entire33.14-instruction handler average. Inclusive staged loads
fall from162.69 to124.52 instructions each, and staged stores from169.85 to109.89.
Both are additional to wrapper work; public immutable startup operations remain
inside the complete memory boundary.

Pinky total interpreter instructions fall from5,048,924,258 to4,672,971,129,
**7.45%**, including materialization, publication and retirement. Snapshot
publication increases from148 to217,157 inclusive instructions; that is too small
to explain the memory saving as work moved outside the memory boundary. Executor
self work remains exactly2,847,194,333 instructions in both images. The whole
prototype still executes4.74x the reference's986,604,703 instructions.

Fill and indirect total instructions fall11.07% and6.69%, respectively. These
counter reductions establish less executed work in the measured cases; they do
not establish equivalent CPU-time gains. The paired CPU observations and severe
crossing regressions above still fail the acceptance gates. The prototype stays
rejected, and the active runtime stays at the diagnosed baseline.
