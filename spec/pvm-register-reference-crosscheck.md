# Executed register arithmetic cross-check

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary.
The existing [independent arithmetic corpus](pvm-registers.md) is unchanged:38977
records across all85 register-only opcodes. Expected results come from the existing
independent integer reference, including its attributed scalar assembly witnesses.

The optional [public-API checker](../tests/reference/polkavm_memory/src/bin/registers.rs)
executes each original operand byte sequence against pinned PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, interpreter/JamV1, with no gas metering.
Public `ProgramParts::empty` and `ProgramBlob::from_parts` accept the exact code,
mask and jump-table framing. No private testing features, source patches or
instruction re-encoding by the PolkaVM assembler is needed. Every register is set
from the fixture before execution. A trailing real trap must occur at the exact
expected PC; compare all13 posterior registers with independent expectations.

The checker reuses the optional memory-reference crate's pinned dependency lock.
Adding an explicit default binary keeps the earlier memory-regeneration command
working. Ordinary Nim tests and production builds do not invoke Rust or depend on
this optional executable. The original fixture bytes/hash and Nim implementation
remain unchanged; this is cross-check evidence, not a port.

## Completion and reproduction

After the pinned sources/toolchain and exact locked dependencies are provisioned:

```sh
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin registers -- tests/fixtures/pvm-registers.bin
make unit SUITE=pvm_registers
rustup run 1.99.0 cargo fmt --manifest-path tests/reference/polkavm_memory/Cargo.toml -- --check
```

Require all38977 rows and85 opcodes to be observed; malformed/truncated corpus
headers fail before access and checked record extents prevent count overflow.
Validate lock identities against upstream, unchanged fixture SHA-256, exact engine
trap position and all registers. Re-run the default memory generator and compare
its312-byte corpus to preserve the earlier CLI contract. This establishes scalar
value/register parity for this corpus, not gas pricing, arbitrary code or full VM
conformance. Record any differing row in the discrepancy register before changing
expectations or behavior. M1 framing remains complete; full state serialization,
whole-block parity and full chainspec equivalence remain open.

## Observed local evidence

The public interpreter checker and native suite both pass all38977 independent
rows across85 opcodes. The original fixture remains SHA-256
`1abf6f399808dad7ed612200443342717de0e6b75c66eb232ecb4b8c3a2c5d2b`.
A corrupted expected-value control fails at row0, and an inconsistent maximum count
fails the extent check. The default memory generator still reproduces its frozen
312-byte corpus exactly. Upstream-lock identity and pinned Rust formatting pass.
No discrepancy or expectation adjustment was needed. Native evidence is local
checked-release macOS/ARC/Clang LTO; reference execution uses the pinned Rust release
profile. No remote CI or full upstream Rust suite run is claimed.
Logs and intentional tampering controls remain under
`build/pvm-register-reference-*`.
