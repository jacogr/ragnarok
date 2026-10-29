# Public compiled policy interface

Refs #1733. This prerequisite adds the independent `compiled` identity and precise unavailable
public API/CLI behavior. The Gray Paper and existing program, execution and host contracts
remain authoritative. Public working compilation is a separate implementation increment.

## Stable public surface

`PvmBackend.Compiled` has ordinal4 and canonical spelling `compiled`. Existing ordinals0–3,
zero-initialized `jit` and `DefaultPvmBackend=Jit` remain unchanged. Strict ordinary/dedicated
CLI parsing and help include the new name. Other spellings and duplicate options still fail.
The startup summary identifies the requested eager policy and required source admission without
claiming availability, actual execution or the optional foreign revision for this independent policy.

The shared prerequisite supplies `prepareFlatStream(plan): FlatResult[FlatStream]`, copied
`FlatSealedInfo`, its zero/unsealed getter and three appended availability errors. Its honest
stub returns `NativeNotBuilt` for an admitted source-only plan. The public constructor admits
immutable source facts under the caller's existing limits and calls that hook. The
[separate owner implementation](pvm-eager-compilation.md) adopts only a successful, complete sealed
stream; the landed shared stub still returns a guarded refusal with no owner or receipt. The enum enters this
independent path explicitly, before the foreign constructor's JAM-profile, library or compiler
selection. That safety guard is inseparable from exposing the enum to callers.

## Error and ownership contract

| Shared boundary outcome | Public preparation result |
| --- | --- |
| `NativeNotBuilt` | `BackendNotBuilt` |
| `NativePlatformUnsupported`, `NativeStorageUnavailable` | `BackendUnavailable` |
| Code/fact/jump/page/stream/preparation quota refusal | `LimitExceeded` |
| Malformed/uninitialized source program | `InvalidProgram` |
| Invalid caller policy | `LimitExceeded` |
| Invalid admitted plan, default/unexpected error, unsealed/inconsistent successful hook | `BackendFailure` |

Failed/default results retain only their typed reason. Direct execution, response-only host and
fallible-host convenience calls preserve that reason without callbacks or input mutation.
`backendAvailability(Compiled)` performs the same typed preparation check before application
resources open. Optional PolkaVM build flags and conflicting upstream selection variables cannot
turn this request into a foreign engine, JIT or interpreted success.

The owner implementation checks a successful hook's sealed source-entry partition before adopting
its stream under the existing exclusive lease. A private temporary retires on every refusal.
No dummy stream, callback, guest run or automatic policy fallback can manufacture success.
An actual `compiled` receipt requires native work from a successfully adopted compiled owner;
checked-only execution remains `interpreted`.

Existing JIT/interpreted preparation error mapping, hot dispatch and frame/stream/native-owner
layouts stay unchanged. The public layer copies existing shared diagnostics and owns no generator
or sealing storage implementation. It depends on the small shared contract, independently of
generator performance experiments.

## Focused checks

- `app_pvm_backend`: preserved defaults/ordinals, canonical names, malformed/duplicate refusal,
  help, independent unavailable summary and startup availability.
- `pvm_runtime_backends`: typed constructor/direct/response/fallible-host refusals, no callbacks,
  unchanged input/gas, repeated refusals, malformed-source and caller-quota classification, paper
  source independent from foreign JAM-profile policy and enabled-bridge selection isolation.
- Pinned formatting and source-only Nimony checks locally; linked unit/application checks run in
  CI against the exact shared contract and public policy heads. No local native execution or
  performance result is part of this interface prerequisite.
