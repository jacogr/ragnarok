# Pinned compiler final-page host-API failure

## Observed failure and current disposition

Compiled comparisons are deferred by the maintainer on 2026-10-21 while the
interpreter baseline remains substantially behind. The current benchmark starts only
Ragnarök and the PolkaVM interpreter. It does not enable kernel facilities or silently
skip compiler fixtures while claiming complete compiled correctness.

Before that decision, hosted run
[39589063101](https://github.com/jacogr/ragnarok/actions/runs/39589063101) at Ragnarök
`3a18314052ba0b4b4a5880257dc812af531aa222` enabled the same sandbox prerequisites as
pinned PolkaVM CI, then ran `RAGNAROK_PVM_REFERENCE_BACKEND=compiler make check-pvm-reference`.
The engine initialized with dynamic paging and the first public memory-boundary probe
panicked before any complete group passed. The benchmark dependency stayed blocked.
This is evidence for that historical head, not a passing result for later revisions.

Environment: GitHub-hosted Ubuntu 24.04, x86-64,
`Linux-6.17.0-1022-azure-x86_64-with-glibc2.39`, Rust 1.99.0,
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` and locked transitive dependencies.
The checked ARC/LTO native/interpreter pairs pass separately; no compiler verdict is
inferred from them.

## Exact trigger and output

The existing `tests/reference/polkavm_memory/src/main.rs` probe constructs a JamV1
module, enables dynamic paging with 4096-byte pages, then uses public host APIs:

```rust
instance
    .zero_memory_with_memory_protection(0xfffff000, 4096, MemoryProtection::ReadWrite)
    .unwrap();
instance.write_memory(0xfffff000, &[7; 4096]).unwrap();
```

The recorded process output is:

```text
Reference backend: compiler; dynamic paging: true

thread 'main' (4479) panicked at /home/runner/work/ragnarok/ragnarok/vendor/polkavm/crates/polkavm/src/sandbox/linux.rs:2389:44:
range end index 4294967296 out of range for slice of length 4294967295
```

Pinned `sandbox/linux.rs` lines 1050 and 1060 create/map a `u32::MAX`-byte host
backing. Line 2389 indexes that slice through `address + data.len()` after checking
writable page membership. The complete final page ends at 2^32, one byte beyond
that slice. This source inspection explains the observed panic; it does not claim
which fix upstream should choose. The interpreter host API supports the existing
fixture's final-byte sentinel. Avoiding only the write is insufficient for identical
coverage: that fixture also reads the final byte through the public host API.

This is a compiler host-API failure, distinct from GP-PVM-002's guest exclusive-end
semantics. It does not authorize a new Gray Paper interpretation, dependency upgrade,
upstream patch or silent fixture exclusion.

## Upstream search and report preparation

Bounded open/closed issue searches for `4294967295`, `last page` and `final byte`,
and PR searches for `last byte` and `memory_mmap` in `paritytech/polkavm` found no
exact discussion on 2026-10-21. Related closed
[PR139](https://github.com/paritytech/polkavm/pull/139) adds instruction test programs;
its body/files do not address this compiler host-memory mapping. These searches are
not an exhaustive absence claim. Current upstream master at inspected commit
`867e65c58e24c76953d385b19b7bf0d91bf77cd4` retains the same allocation size and write
slice; the project pin is unchanged and that newer revision was not executed.

A suitable report title is **Linux compiler dynamic-memory host write panics on a
mapped final page**. The pins, exact environment, public API trigger, verbatim output,
source locations and failing Actions run above form the local report draft. Nothing
has been posted upstream. Reproduce the complete existing probe on supported Linux
with the recorded sandbox prerequisites before claiming a smaller isolated reproducer
was executed. Any future compiled comparison must resolve or explicitly scope this
boundary and run the fixture groups; it must not turn the failed run into a green
compiled result.
