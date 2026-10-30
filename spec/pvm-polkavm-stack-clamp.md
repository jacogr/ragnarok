# PolkaVM declared-stack clamp qualification

## Scope and authority

The pinned Gray Paper remains primary. PolkaVM is an explicit optional runtime and
public-API implementation cross-check; no independent interpreter, JAM initializer,
gas, host, retry or approved compatibility-exception semantics change here.

The authorized source pin advances from
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` to
`acff91f0df4494b576471feb0c031066ab7406df` in pristine `vendor/polkavm`.
The official [three-commit comparison](https://github.com/paritytech/polkavm/compare/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa...acff91f0df4494b576471feb0c031066ab7406df)
contains exactly:

- [#427](https://github.com/paritytech/polkavm/pull/427), `a802f44537484f16c676e6acd5b97d40c9f4905e`:
  the allocator fuzzer frees removed nonzero allocations instead of only dropping its bookkeeping.
- [#428](https://github.com/paritytech/polkavm/pull/428), `867e65c58e24c76953d385b19b7bf0d91bf77cd4`:
  upstream CI also runs the correctness fuzzer, and the VM fuzzer reuses engines by backend.
- Merged [#436](https://github.com/paritytech/polkavm/pull/436), `acff91f0df4494b576471feb0c031066ab7406df`:
  standard-memory stack growth clamps resident length to the declared stack size.

No unmerged lazy-compilation branch or #445 changes are included. Upstream manifests,
root/fuzz lockfiles, Rust toolchains and our reduced Cargo dependency identities are unchanged.
[PolkaVM pins](polkavm-pins.json) refresh the four changed inspected source hashes and
record the upstream CI workflow hash. Both Rust ABI and Nim loader revision constants
advance together, preserving rejection of a mismatched loaded library.

## Regression boundary

`StandardMemory::stack_resize` reserves a power-of-two capacity. Previously it also
exposed that capacity as resident stack length, so a non-power-of-two declared stack
could admit reads and writes below its lower bound after growth. The upstream change
clamps exposed length while preserving its allocation and memory-budget policy.
The maintained optional runtime bridge explicitly selects dynamic paging; it does not
use this standard-memory allocation path, and its profile and qualification stay unchanged.

The existing public-API `validation` reference executable now creates a JamV1 module
with 4096-byte pages and a declared three-page standard stack. Successive host writes
grow residency through the rounding boundary and verify retained marker bytes.
Host reads/writes below the declared low address must fail. Real guest load/store
instructions must succeed at the low address, interior page and final fitting eight
bytes, then trap for accesses crossing or starting below the declared lower bound.
The original module-validation matrix still runs in the same executable and remains
paired with the independent `pvm_initialization` suite. This is an upstream adapter
qualification, not a change to the independent initializer or a new GP exception.

An immutable old-pin CI control runs the same regression before the source upgrade;
the old source compiles and then fails the retained marker control after three-page
growth (`[0]` observed instead of `[17]`). The same witness also requires below-stack
host refusal and guest traps once the upgraded path passes marker preservation.
The final source must pass `make check-pvm-reference`, the linked optional-runtime
suites and all final-head `ci:full` jobs before independent review.

## Fixtures and historical provenance

Frozen fixture bytes and original generation metadata remain unchanged. The explicit
`guest_artifact_commit` in `polkavm-pins.json` binds all four checked guest artifacts to
their original `69e5b87c` generation source, separately from the current host runtime.
Every guest-consumed source hash is unchanged at the new target. Validation checks the
current and original source tables independently; neither can override the other.
Missing, unknown or current-runtime-only generation identities are refused. Current
reference regeneration still compares against the original frozen commitments. DOOM ELF/WAD/golden
asset hashes are identical at both revisions; only their current source-commit binding
in `pvm-doom-assets.json` advances. Source/configuration and emitted file hashes in new
CI evidence identify the upgraded inputs explicitly.

Existing interpreter/JIT/native compiler experiments, timing receipts and discrepancy
citations retain the old pin and their original scope. They are not upgraded performance
results. No old receipt is rewritten and no performance improvement is claimed here.

## Old-pin control evidence

CI [41019555657](https://github.com/jacogr/ragnarok/actions/runs/41019555657), exact
source `3703ccf101784d80688441880e8b821c9a9ec2b8`, retains PolkaVM `69e5b87c`.
The reference executable built successfully and reached `declared_stack_bounds`;
`validation-reference.log` records an assertion failure at the marker preservation
check: `left: [0]`, `right: [17]`. This is a runtime qualification failure, not a
compiler/setup refusal. The immutable old-pin control is distinct from final-head
upgrade verification and is not a passing reference result.
