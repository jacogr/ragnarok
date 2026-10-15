# Assurances API

[The contract](../spec/assurances.md) follows pinned GP v0.7.1 C.2 `encodeassurances`.
All three production modules are allocation-free; test drivers allocate only trusted utility
storage. Records own anchor, availability bits, validator index and signature bytes directly, so
input mutation or release after decoding cannot change them. No separate snapshot owner or
release handle is needed for these entirely fixed fields.

| Operation/domain | Nim | Odin | Mojo |
| --- | --- | --- | --- |
| Record | `Assurance` | `Assurance` | `Assurance` |
| Profile | `AssuranceConfig` | `Assurance_Config` | `AssuranceConfig` |
| Counts | `CoreCount`, `ValidatorCount` | `Core_Count`, `Validator_Count` | `CoreCount`, `ValidatorCount` |
| Validator index | `ValidatorIndex` | `Validator_Index` | `ValidatorIndex` |
| Encode | `encodeAssurances(values, config, output)` | `encode_assurances(values, config, output)` | `encode_assurances(values, config, output)` |
| Decode | `decodeAssurances(input, config, output)` | `decode_assurances(input, config, output)` | `decode_assurances(input, config, output)` |

Tiny is 2 cores / 6 validators; full is 341 / 1023. Counts are unsigned nominal domains, and
configuration is validated before input access. Bitset native storage is 43 bytes; callers must
zero bytes outside the configured wire width and unused high bits in its final octet.
Validator indices are E2 values, ordered strictly increasingly, each below the configured count.

Callers supply stable borrowed input and disjoint output during each synchronous operation.
Failures preserve the complete destination, including unused records. Decode success exposes
`count` and `consumed`; encode success exposes `written`. Select the successful tagged branch
before accessing these fields. Defaults are failures. Nim retains variant field guards; Odin
retains checked union assertions; Mojo uses the existing checked result wrapper.

A decoder accepts one prefix. Standalone consumers must separately require `consumed == input.len`.
The unused output suffix stays unchanged on success. No codec input controls heap allocation.
The fixed configuration envelope bounds production loops to at most 1023 records.

This module validates structure and canonicality. Block-parent equality, availability assignments,
validator keys and Ed25519 verification require chain context. Structural official fixtures have
different anchors, so adding a common-parent constraint here would reject published codec vectors.
The outstanding shared Ed25519 acceptance-policy question remains unresolved by this increment.

Run `python3 interoperability/test_assurances.py` for the matched official/boundary/fuzz corpus,
`python3 interoperability/test_assurances_types.py` for deliberate compiler rejection probes, and
`python3 interoperability/test_assurances_harness.py` for independent oracle examples.
Nim uses ARC/Clang LTO with bounds, range, field, overflow and assertion checks enabled.
Linux CI runs the same checks; local results are recorded separately from CI verification.
