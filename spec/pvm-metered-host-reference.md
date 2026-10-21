# Metered host suspension and resumption cross-check

Primary Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`:
[ecalli](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L300-L314),
whole-block charging and host-transition composition. The host test policy replies
Continue, writes only r8 and charges no external host fee; this isolates PVM
suspension/resumption from JAM-specific host-function prices.

Nine original programs vary the first ecalli's immediate width/sign bits. A prefix
loads r7=7, the first host writes r8=41, a guest move copies it to r9, the second
host writes r8=42, another move copies it to r10, then r0 halts. Both hosts belong
to the same gas block. Independent GP pipeline pricing is103 gas/106 cycles.
Native exact106/one-less105 cycle checks and public PolkaVM module pricing agree.
Starting with110 gas leaves seven at each host and final halt; a second block
charge would prevent continuation.

Native replay checks every final/source register, callback order and causing PCs,
prepaid flags, full sign-extended GP identifiers and exact six-step/two-callback
budgets. Five steps refuse after both replies; callback budgets1/0 refuse before
the next callback while preserving completed context effects and original CPU
aliases. There are nine successful programs and27 explicit local-budget refusals.

The public pinned PolkaVM checker uses Interpreter/JamV1 with Sync/Full/L2Hit
metering. It observes both host exits, uses public register replies and resumes
with the instance's next PC, then checks final halt, seven gas and all13 registers.
No source patches, private features or dependency changes.

## Reference API representation

GP immediate decoding sign-extends at most32 bits into a64-bit register pattern.
PolkaVM's `Ecalli(u32)` exposes the corresponding32-bit pattern. For example,
one byte0x80 is GP0xffffffffffffff80 and public0xffffff80; four bytes ending0x80
are GP0xffffffff80000000 and public0x80000000. These are explicitly documented
representations of the same decoded signed immediate. Native checks preserve the
GP value and reference checks preserve the public value. Positive JAM host IDs
are unchanged. This adapter mapping is distinct from a specification discrepancy;
it does not replace GP raw identifiers with zero-extended values.

## Reproduction and evidence

```sh
make unit SUITE=pvm_metered_host_reference
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin hosts
```

All nine native and public-reference programs pass, including native budget controls.
Evidence is local checked-release macOS/ARC/Clang LTO and pinned Rust. Full upstream
Rust/fuzz-suite execution and Linux CI are separate.
