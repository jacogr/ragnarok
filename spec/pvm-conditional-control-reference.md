# Complete conditional-control cross-check

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` is primary:
its conditional instruction rows and both-successor rule at
[text/pvm.tex lines254–260](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L254-L260).
The independent [generator](../tests/pvm_control_reference.py) constructs original
programs and expected complete register files without importing production code.

All16 conditional opcodes cover values0/1/2/3/UINT64_MAX/INT64_MIN bits. Each has
a valid forward destination plus invalid operand-byte, interior marked-opcode and
past-end destinations. A successful prefix writes r7=7 over99. Distinct successor
blocks write r8=21/42 and halt through r0. Invalid destinations panic before
condition selection, including untaken branches, retaining only the prefix write.

The frozen PVMCTL01 corpus now has1800 rows, including the384 original conditional
cases and1416 [load-and-jump cases](pvm-load-jump-reference.md), each containing a bounded raw program,
expected exit/reference trap PC and all13 initial/expected registers. SHA-256:
`877eef02d3e691abb7357c5167aa6ade65091055470f84261218bfc1cb8fdf6e`.
The [native replay](../tests/unit/codec/test_pvm_conditional_control_reference.nim)
uses the explicit JAM profile, exact four-step path budget, complete register/source
checks and single-step panic PC3. Recursive halt/panic PC0 follows the paper.

The optional [public checker](../tests/reference/polkavm_memory/src/bin/control.rs)
loads the same bytes through pinned PolkaVM0.37.0
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, interpreter/JamV1 and bounded
Sync/Full/L2Hit metering. It checks every exit and register, plus trap PC3.
Metering bounds accidental loops; this corpus compares control/register behavior,
not remaining gas or PolkaVM's API-level final PC normalization.

## Reproduction and evidence

```sh
make unit SUITE=pvm_conditional_control_reference
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin control -- tests/fixtures/pvm-control.bin
PYTHONPATH=tests python3 -m unittest discover -s tests -p test_pvm_control_reference.py
```

All1800 native and public reference rows pass; three independent Python provenance/
signed-boundary tests pass. Corrupting expected r8 fails at row0/register8;
oversized record length refuses before extraction. No source patches, private
features or dependency/pin changes. This extends executed control-flow evidence
without a new discrepancy or a claim of complete conformance. Local checked-release
macOS/ARC/Clang LTO and pinned Rust evidence; Linux CI remains independent.
