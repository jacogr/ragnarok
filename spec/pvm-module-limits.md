# JAM module bounds with paper-aligned raw decoding

Primary Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` and pinned
PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` differ on code-byte
and declared jump-count bounds. [GP-PVM-007](graypaper-discrepancies.md) records
this alongside open upstream PR559. The PolkaVM ABI source digest is added to
`polkavm-pins.json`; revisions, dependencies and compiler pins remain unchanged.

Under the maintainer's compatibility policy, the explicit `decodeJamProgram`
profile rejects instruction code above33554432 bytes and declarations above
16777216 entries. Count validation precedes width-zero semantic normalization;
a huge declared table cannot become admissible merely because its runtime table
would be empty. Caller byte/count policies remain independent local ceilings and
can refuse first with `LimitExceeded`. The raw `decodeProgram` entry point keeps
the pinned paper's structural behavior, including larger complete blobs when local
policy permits.

The native suite checks four tiny width-zero count declarations: limit-1, limit,
limit+1 and UINT64_MAX. Raw lookup retains the declared zero-valued last entry;
JAM admits only the first two with an empty semantic table. Actual initialization
maps semantic refusal to `InvalidProgram`; real inner-machine creation maps it to
HUH without adding a slot. Prior empty maps remain unchanged, and tighter caller
limits produce local refusals.

Three full present all-trap code programs use33554431/33554432/33554433 bytes and
canonical opcode masks. Raw decoding accepts all three; JAM and the public pinned
PolkaVM parser admit only the first two. Both accepted reference blobs validate all
instructions. Code and mask together exceed the instruction-byte cap at the exact
accepted boundary, proving that the cap is not a complete-blob byte policy.

## Reproduction and evidence

```sh
make unit SUITE=pvm_module_limits
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin limits
```

All seven native/public cases pass. Raw program regression and the512-case raw/JAM
jump-table suite pass. Local checked-release macOS/ARC/Clang LTO and pinned Rust
evidence; no remote Linux CI or full upstream Rust/fuzz-suite claim. M1 framing
remains complete; full serialization, whole-block parity and full chainspec
equivalence remain separate gates.
