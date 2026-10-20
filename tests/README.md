# Tests and independent references

[Project overview](../README.md) · [Testing guide](../docs/testing.md) ·
[Test registration](../docs/testing/adding-tests.md)

This directory holds native implementation checks, independent Python references and process-level
verification. Production protocol code lives in [`src/`](../src/README.md); test orchestration
and evidence collection live in [`tools/`](../tools/README.md).

| Location | Contents |
| --- | --- |
| [`unit/`](unit/) | Native Hastur suites grouped under codec, crypto, QUIC and state |
| [`support/`](support/) | Shared Nim test contexts, independent inputs and ARC evidence helpers |
| [`native/`](native/) | Native drivers, runtime contract probes and compiler rejection fixtures |
| [`browser/`](browser/) | Nimony browser RPC regression fixture |
| [`fixtures/`](fixtures/README.md) | Committed test inputs, expected RPC results and fixture provenance |
| Python files here | Independent encoders/oracles, fixture builders, harness tests and peer scenarios |

Use `make unit SUITE=rpc` to run one native suite, or `make check` for complete verification.
Individual groups include `make check-python`, `make check-unit`, `make check-failures`,
`make check-guards` and `make check-e2e`; the [testing guide](../docs/testing.md) describes
coverage and report locations.

Published and derived vectors are documented in [`vectors/`](../vectors/README.md), while
pinned upstream corpora live in [`vendor/`](../vendor/README.md). Generated fixtures, temporary
keys, logs and reports belong under ignored `build/`.
