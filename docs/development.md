# Development and verification

Use Nim 2.2.12 with ARC, Clang and bundled nimpretty. Report and assurance adapters enable checked LTO,
assertions, bounds, ranges, field and overflow guards. Core regression suites also exercise debug
and release profiles. Install Rust 1.99.0 for the pinned historical
Bandersnatch crate; keep its Cargo.lock and offline build policy. Python 3.12+ is tooling only.

On macOS install the selected Nim, LLVM/Clang, CMake, zlib and OpenSSL with the normal local package
manager and select an Xcode command-line SDK. Linux CI installs the checksum-pinned Nim archive
through `tools/setup_ci_linux.py`; C/C++/CMake/zlib and lld come from Ubuntu packages.
Initialize sources with `python3 tools/setup_submodules.py` before native builds.

## Fast codec and boundary checks

```sh
python3 tools/format.py --check
python3 tests/test_codec.py
python3 tests/test_bits.py
python3 tests/test_collections.py
python3 tests/test_c2.py
python3 tests/test_bits_harness.py
python3 tests/test_collections_harness.py
python3 tests/test_c2_harness.py
python3 tests/test_tickets.py
python3 tests/test_tickets_harness.py
python3 tests/test_guarantees.py
python3 tests/test_guarantees_harness.py
python3 tests/test_disputes.py
python3 tests/test_disputes_harness.py
python3 tests/test_work_package.py
python3 tests/test_package_harness.py
python3 tests/test_header.py
python3 tests/test_block.py
python3 tests/test_header_harness.py
python3 tests/test_block_harness.py
python3 tests/test_assurances.py
python3 tests/test_assurances_types.py
python3 tests/test_assurances_harness.py
```

The codec runner includes native selftests, deterministic malformed input, official vectors,
failure atomicity, immutable ownership and intentional nominal-domain compilation failures.

## Crypto and report checks

```sh
python3 tests/test_crypto.py --fetch
python3 tests/test_state_layout.py
python3 tests/test_state_layout_harness.py
python3 tests/test_state_trie.py
python3 tests/test_state_trie_harness.py
python3 tests/test_state_safrole.py
python3 tests/test_state_safrole_harness.py
python3 tests/test_state_consensus.py
python3 tests/test_state_consensus_harness.py
python3 tests/test_state_disputes.py
python3 tests/test_state_disputes_harness.py
python3 tests/test_state_history.py
python3 tests/test_state_history_harness.py
python3 tests/test_state_requests.py
python3 tests/test_state_requests_harness.py
python3 tests/test_state_service_values.py
python3 tests/test_state_service_values_harness.py
python3 tests/test_state_accounts.py
python3 tests/test_state_accounts_harness.py
python3 tests/test_state_outputs.py
python3 tests/test_state_outputs_harness.py
python3 tests/test_state_workqueues.py
python3 tests/test_state_workqueues_harness.py
python3 tests/test_state_statistics.py
python3 tests/test_state_statistics_harness.py
python3 tests/test_state_privileges.py
python3 tests/test_state_privileges_harness.py
python3 tests/test_state_availability.py
python3 tests/test_state_availability_harness.py
python3 tests/test_state_authorization.py
python3 tests/test_state_authorization_harness.py
python3 tests/test_bandersnatch.py --fetch
python3 tests/test_work_report.py
python3 tests/test_report_types.py
python3 tests/test_report_harness.py
python3 tests/test_assurance_crypto.py
python3 tests/test_assurance_crypto_types.py
python3 tests/test_assurance_crypto_harness.py
```

The native primitive build precedes report/context runners. Independently installed OpenSSL signs
public fixture transcripts and first reproduces a pinned RFC8032 known answer. Tests do not use
production secrets. `--skip-build` reuses a deliberately built adapter where supported.

## Networking and integration

```sh
python3 tests/test_quic_harness.py
python3 tests/test_quic.py --fetch
python3 tests/test_quic_soak_harness.py
python3 tests/test_quic_soak.py --skip-build
python3 tests/test_quic_service.py --skip-build
python3 tests/test_quic_mesh.py --skip-build
python3 tests/test_quic_resilience.py --skip-build
python3 tests/test_integration.py --reuse-native
python3 tests/test_quic_offload.py --reuse-native
```

Integration/offload build distinct Nim binaries against already-built native libraries. Lifecycle
runners retain their timeout, memory, descriptor and one-dispatcher-thread gates. Offload additionally
observes two fixed worker threads. These finite tests are not production-capacity or leak-freedom claims.
All build products and diagnostics go under `build/`; native production sources stay under `src/`.
