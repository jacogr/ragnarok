# Standalone PolkaVM artifacts

Scope: load the pinned PolkaVM `PVM\0` container, blob version3 (JamV1), into the
existing independent program and immutable memory APIs. Source reference:
`polkavm-common/src/program.rs` and `abi.rs` at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. No dependency pin changes.
Other instruction-set versions and CoreVM containers are explicitly unsupported.
This is an application file format, not a change to JAM consensus initialization.

The loader checks declared length, canonical u32 lengths, section order, import
offsets, export instruction boundaries, data sizes, memory-map overlap and finite
resource limits (including at most1024 imports and1024 exports) before publishing an owner. It accepts optional high-bit sections
without interpreting debug metadata. Trailing bytes after EOF are refused.
Memory uses4096-byte pages,65536-byte guard/alignment regions and the pinned
32-bit ABI; initial RA is0xffff0000 and SP is0xfffe0000. Memory snapshots and
symbol observations never expose mutable loader storage.

`ragnarok --pvm-code FILE [--pvm-entry NAME] [--pvm-backend MODE]` executes one
export (default `main`) without starting networking. Gas and attempts are bounded
by `--pvm-gas` and `--pvm-steps` (defaults10000000 each). No guest arguments or
application-specific host bindings are inferred. A host suspension, panic, fault,
budget exhaustion, invalid artifact or unavailable explicit engine fails visibly;
only a guest halt reports success. Artifact options cannot accompany another command
or service controls. The same options/parser and loader are reusable by the DOOM
integration driver, whose explicit ROM/video/audio bindings and warmed snapshot
remain test-owned. PolkaVM compiled is exposed through the existing API/CLI policy
but is not enabled in CI comparisons.

Completion checks: native artifact tests for valid sections/memory/entry/ownership,
truncation/noncanonical/overflow/order/resource failures and unsupported versions;
CLI parser failure atomicity and command isolation; remote native compilation and
both Linux architecture DOOM comparisons consuming the full artifact.
