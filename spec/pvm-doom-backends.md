# Continuing DOOM through shared prepared backends

## Scope and pins

This check exercises the merged public adapter through the real application option parser,
`--pvm-backend polkavm-interpreted` and `--pvm-backend jit`. It uses the pristine pinned
PolkaVM commit in `polkavm-pins.json`, the DOOM ELF/WAD identities in `pvm-doom-assets.json`
and the unchanged pinned Nimony/Rust toolchains. The standalone Rust interpreter prepares
an identical complete input and an independent first-call oracle; both compared processes
execute through Ragnarök's `PreparedProgram`/`executeWithHost` API.

The initial snapshot is the maintained frame-1320 gameplay fixture, checked against upstream's
TGA golden. Each process restores it once, then executes two successive ticks. The second call
uses memory from the first result and resets only the exported-call CPU/gas ABI. It never reloads
the fixture between calls. The frozen guest has only five ROM/output imports; clock, RNG and
demo/key state are deterministic guest state, and both runs receive the exact same WAD bytes.

Every emitted video frame has an ordered frame/call index, fixed 640×400 dimensions and SHA256
of opaque RGBA, normalized from the guest's BGRX ABI using the established upstream-golden rule.
Raw ordered audio/video/stdout events are compared separately, retaining all original bytes.
Every call also compares complete CPU/gas and mapped page bytes/permissions, plus the ordered ROM/
output host-argument trace. The first call additionally checks the full independent upstream
state/events and frame golden. Native assertions remain active in checked release/ARC/ThinLTO.

## Refusals and availability

Changed bytes from an actually produced framebuffer are rehashed and must fail at the first
changed frame. Omitting/reordering actual frame receipts must also fail. The same comparator
checks complete state and ordered hosts, so a matching final image cannot hide earlier divergence.
Native assertion and wrong-backend process controls must fail with their intended diagnostics.
A separately built unlinked image must return `BackendNotBuilt` for the explicit foreign request;
missing support is never a skipped/pass comparison. Compiled PolkaVM is not invoked.

ARM64 requires actual JIT receipts and positive native operations; x86-64 honestly reports the
requested JIT policy's interpreted fallback and zero native activity. Neither architecture may
substitute another engine for an explicit PolkaVM interpreted request.

## CI and evidence

`make check-pvm-doom-backends` is correctness-only, CI-only execution. It belongs to
`Interop / PVM Backends` on native Linux ARM64 and Linux x86-64, included in master,
`ci:interop`/`ci:full` and explicit Interop/full dispatches. A focused `pvm-backends` dispatch
avoids unrelated families. It does not add a product DOOM command or another performance row.

The manual one-call sizing pilot is reported as `pilot-passed`, never as qualification of the
continuing two-call sequence. Final/default CI uses two calls; the traced foreign adapter is
piloted on remote runners before accepting that bound. No heavy local execution is authorized
while the optimization agent measures locally. Wall-clock process duration sizes CI only and
supports no engine throughput claim.

`build/tests/pvm-doom-backends/results.json` and `summary.md` retain exact source/compiler/
input/image identities, architecture, requested/actual backends, every frame hash and the first
mismatch. Raw memory/video files stay transient on the runner and are excluded from artifacts.
Completion requires both native architecture jobs, every comparison and all refusal controls.
