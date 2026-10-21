# Executed block-gas cross-check

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary.
The [independent gas corpus](pvm-gas.md) retains all1776 original blocks and their expected prices/cycle ceilings, then
adds eight [raw gas-boundary cases](pvm-gas-block-boundaries.md) inspired by Grey's
transpiler-masking report. Production pricing remains unchanged.

The optional [public-API checker](../tests/reference/polkavm_memory/src/bin/gas.rs)
uses pristine pinned PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`.
Public ProgramParts parses each original framed program; the bounded JamV1
instruction iterator starts at the recorded block offset. The full pipeline
simulator uses `CacheModel::L2Hit`, matching the paper's fixed25-cycle memory
latency. Compare the first completed block price with the independent expectation.
Do not substitute PolkaVM's generic engine-default gas mode or other cache models.

The public API exposes a final block price; this checker does not claim to compare
raw simulation-cycle counts. The native suite still verifies exact/one-less local
cycle ceilings and maximum limits for every row. GP-PVM-003's48 wrapped negative-
target cases are included through the existing approved pricing interpretation.
No private fields/features, source patches, dependency upgrades or Rust production
integration. The checker shares the optional reference crate's existing lockfile.

## Reproduction and completion

From the provisioned repository, prepare the native gas corpus and run the optional
checker against the path selected by its source-owned provider. One explicit
independent regeneration path is:

```sh
python3 -c 'import sys; from pathlib import Path; sys.path.insert(0,"tests"); from pvm_gas_reference import prepare; prepare(Path("build/pvm-gas-crosscheck"))'
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin gas -- build/pvm-gas-crosscheck/pvm-gas.bin
make unit SUITE=pvm_gas
rustup run 1.99.0 cargo fmt --manifest-path tests/reference/polkavm_memory/Cargo.toml -- --check
```

The current1784-row corpus SHA-256 is
`9c048aa7dbe706ce8072047473203a45e6db16900a4330dc0c4127ecf1ec1797`.
The original1776 records remain byte-identical after the count header.
Require all1784 prices, exact consumption without trailing bytes, default memory
CLI compatibility and unchanged upstream-lock identities. Corrupted price and
record-length controls must reject; never change an expectation to obtain parity.
This result is bounded price evidence, not full execution or gas-model equivalence.
M1 framing remains complete; full state serialization, whole-block parity and
full chainspec equivalence remain open.

## Observed local evidence

All1784 public simulator prices and native gas rows pass. Native replay retains
its exact/one-less/maximum cycle-limit assertions. A corrupted price fails at row0,
and an oversized record length fails before program extraction. The eight added rows preserve the original1776 expectations; upstream-lock checks and pinned Rust formatting pass. No new gas
discrepancy or expectation adjustment was needed. Local checked-release
macOS/ARC/Clang LTO and pinned Rust release evidence; no remote CI or full upstream
Rust test-suite run is claimed. Logs and tampering controls remain under
`build/pvm-gas-reference-*`.
