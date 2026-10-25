# Bounded pinned DOOM attribution

## Scope and correctness

Use the existing PolkaVM pin `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, its
`test-data/doom_64.elf.zst`, shareware WAD and upstream golden images. Asset
identities are in [pvm-doom-assets.json](pvm-doom-assets.json); all Cargo packages
retain existing upstream lock identities. Public linking targets JamV1 with an
explicit 16 KiB minimum stack. The original 8 KiB declaration traps under 4 KiB pages;
16 KiB restores the stack extent implicitly mapped by the upstream example's
16 KiB pages. No guest rebuild, vendor/pin upgrade or runtime optimization is included.

Both runners receive identical complete code/jump-table framing, thirteen
registers, gas, 4,285 mapped 4 KiB pages and permissions. They compare normal exit,
final gas/registers, every mapped memory byte and ordered video/audio/console
payloads. Native source memory must also remain unchanged. Six strict refusals
prove active assertions and rejection of altered expected state/output, followed
by restored positive controls. Every timing invocation repeats complete validation.

Initialization (`ext_initialize`) and a single gameplay `ext_tick` have separate
inputs. Shared reference preparation runs 1,320 bounded untimed ticks before the
measured gameplay call, matching upstream's zero-indexed frame 1,320 combat golden.
Frame 120 is still the title screen. Initialization emits a frame and transitions
can emit many frames per tick; measured tick and emitted-frame counts stay distinct.
Warmup output is read/validated and discarded instead of accumulated.

Raw gameplay video SHA256 is
`58dee7573bf534ade151ded609039f5b14c5f712cae567c814701a9a5b539168`.
The pinned golden matches after upstream's BGR/opaque-alpha normalization, with
normalized SHA256 `44f42f5bed248db9caadf2caf329a2857e1c54a084b69d6b44fba83df4e5422b`.
Native/reference raw bytes match before normalization, including alpha. The
initializer's raw video SHA256 is
`aac090dc14536eea1237ddcbba6b037872a49f1420f277abe0a2c153965b4d50`.

## Measurement boundary

Native uses retained decode-once runtime from PR #1607, checked release ARC/Clang
ThinLTO with debug information and an immutable `GasPlan`. Reference is forced to
PolkaVM Interpreter, JamV1, Sync/Full/L2Hit, canonical Rust release/LTO. The rejected
frame annotation is excluded. Both selected outer guest-call boundaries include
in-memory host callbacks (ROM writes and one owned copy of each output payload).
Program/memory/price preparation, snapshot restoration, file I/O, serialization,
hashing and final validation remain outside collection and clocks.

Calibrated Callgrind profiles collect one complete call per phase/engine; every
selected scope has exactly one incoming call. The source-mapped profiles retain
raw files, fixed simulated cache configuration and branch counters. Instrumented
clocks are discarded. Timings use 13 fresh-state calls per process: three warmups
and ten measured calls. Both native/reference process orders run on the same CI
runner. Counter profiles describe one invocation; warmed timing medians are a
separate measurement and are not inferred from instruction counts.

Commands: `make check-pvm-doom` performs untimed local parity/refusal checks;
`make profile-pvm-doom` is the opt-in `profile-doom` CI entry. Linux developers can
collect counters without timings using
`python3 tools/pvm_doom_attribution.py --counts-only --warmup 1320`.
`PVM_DOOM_WARMUP` selects a bounded preparation prefix up to 1,320 ticks.

## Qualified CI results

[CI 40187719956](https://github.com/jacogr/ragnarok/actions/runs/40187719956)
measures exact head `1271eb08771ba32aeee9e8af5c2f6d394cc47ff3` on
Intel Xeon 6973P-C. All 104 timing calls validate complete state and output.
Warmed process CPU medians are shown for both process orders:

| Guest call | Native CPU ms, order 0 / order 1 | Reference CPU ms, order 0 / order 1 | Native/reference CPU time |
| --- | ---: | ---: | ---: |
| Initialization | 1141.535 / 1133.000 | 504.937 / 504.716 | 2.261× / 2.245× |
| Gameplay tick | 81.244 / 81.649 | 20.764 / 20.777 | 3.913× / 3.930× |

The ten warmed gameplay samples span 81.04–81.99 ms native and 20.73–21.73 ms
reference across both orders. Initializer spans are 1125.48–1152.07 ms native and
504.51–505.89 ms reference. Wall medians closely track CPU medians. These results
cover this checked headless workload and boundary, not general real-time playback
or setup-inclusive application throughput.

| Guest call | Native total instructions | Reference total instructions | Ratio | Identical guest memory operations |
| --- | ---: | ---: | ---: | ---: |
| Initialization | 26,741,550,265 | 6,364,944,906 | 4.201× | 8,145,614 |
| Gameplay tick | 1,951,800,802 | 367,064,441 | 5.317× | 2,652,585 |

The CPU ratios are smaller than the instruction ratios. These software counters
do not establish hardware IPC or turn instruction shares into time shares.

## Memory and execution attribution

Memory totals below are incoming scalar-memory handler/wrapper inclusive costs.
They exclude in-memory host bulk I/O. The native wrapper's exclusive cost is
reported separately; do not add inclusive and exclusive totals together.

| Guest call | Native memory instructions | Reference memory instructions | Native / reference per guest access | Native wrapper self/access |
| --- | ---: | ---: | ---: | ---: |
| Initialization | 2,976,982,046 | 266,481,730 | 365.47 / 32.71 | 53.84 |
| Gameplay tick | 763,910,421 | 86,931,231 | 287.99 / 32.77 | 53.73 |

The scalar-memory path consumes 39.14% of native gameplay instructions. Its
remaining cost is much larger than the logical wrapper alone. The source-mapped
`lowerBound` page-search body accounts for 189,472,721 instructions, 9.71% of the
whole native gameplay call. This is mapped search-body work; unresolved line-zero
instructions are not guessed or assigned to it. The writer currently remembers
two page slots and searches the sorted sparse page vector on a miss.

There is also substantial work outside those memory callees: the native outer
execution function alone has 1,137,399,881 exclusive instructions, 58.27% of the
call. Its inlined arithmetic, control, cache/admission and host-loop code do not
isolate dispatch alone. Memory work and outer execution work both need attention;
removing one wrapper cannot explain or close the complete gap.

## One proposed next experiment

Expand the existing owner-bound recent-page cache from two slots to four. The
hypothesis is that interleaved gameplay page streams evict useful entries and
cause avoidable binary searches. This hypothesis is not yet a measured hit-rate
claim. Preserve immutable base ownership, exact bounded slot/index validation,
per-access permissions, cross-page/fault ordering and COW behavior. Do not cache
permissions, add a new instruction representation or combine other changes.

First require at least eight fewer total native instructions per identical
gameplay memory access, a clear reduction in mapped search work, unchanged
state/output and no initializer instruction regression. Only after that counter
gate, compare baseline/candidate native DOOM timings on one CI runner in both
orders and run the maintained full paired matrix with identical-source controls.
Require repeatable gameplay improvement beyond control variation and no
reproducible regression above 2% on fill, indirect, host/cross-page or memo controls.
Stop and record rejection if it fails. No cache variant is implemented by this PR.

## Verification and provenance

Local untimed admission covers 0, 120 and 1,320 warmup ticks, complete parity,
goldens and all six refusal controls. After moving serialization outside both
boundaries, final runners also pass the saved gameplay snapshot. The 67 focused
parser/profile/workflow tests, pinned formatting and verification inventory pass.
CI replays all four raw profiles, source manifests (24 generated C files and 77
Rust files), ten correctness/scope controls and all timing logs/medians. Archive
hashes, profile totals and complete process records independently verify.

The first run 40186627565 collected the same four instruction profiles but failed
before timings because source archival omitted its required repository argument.
The repair moves validated archival before collection; the real local 24-file
archive passes. Both engine binaries remain byte-identical between runs, and all
four instruction totals repeat exactly. Only the successful rerun supplies the
qualified source archives and CPU ratios above. Subsequent evidence-only edits
change no measured runtime, driver, build, guest or tool source.
