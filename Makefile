# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Provides the developer and CI command entry points. Exposes setup, build, formatting,
# inventory and independent verification targets with their dependency sequencing.

# Make owns setup dependencies and command sequencing; helpers retain validation and native logic.
.DEFAULT_GOAL := build
# Put flags in SHELL for both macOS Make 3.81 and newer Linux Make.
SHELL := /bin/bash -eu -o pipefail
# Native preparations and tests share build directories; serialize top-level targets.
.NOTPARALLEL:
PYTHON ?= python3
export PYTHONDONTWRITEBYTECODE := 1
export PYTHONUNBUFFERED := 1
# Read the shared pin lazily; clean/help need no compiler or dependency setup.
export RUSTUP_TOOLCHAIN = $(shell $(PYTHON) -c 'import json; print(json.load(open("spec/bandersnatch-pins.json"))["rust"])')
# Bound compatible codec runs and independent compiler checks to the Linux runner's four CPUs.
export COMPILE_CHECK_JOBS ?= 4
# Local builds retain readable assets; CI uses the native JS/CSS minifier. Override with 0 or 1.
export UI_MINIFY ?= $(if $(filter 1 true,$(CI)),1,0)
# Optional one-suite selection is passed through the environment, never interpolated as shell code.
export REOPEN_PAIR_REPORT ?=
export REOPEN_PAIR_OUTPUT ?=
export REOPEN_PAIR_CONFIG ?=
# Focused fuzzing is opt-in; all controls are passed as environment values, never shell source.
export FUZZ_RUNS ?= 100000
export FUZZ_CLANG ?= clang
export FUZZ_LIBFUZZER ?=
export FUZZ_REPLAY ?=
export SUITE ?=
# Select one independent E2E family; an empty value retains complete local verification.
export E2E_GROUP ?=
SUMMARY_OUTPUT ?= build/ci/summary.md
# The pinned compiler supports Linux x86-64; Docker can emulate it on an ARM development host.
DOCKER ?= docker
DOCKER_IMAGE ?= ragnarok:local
DOCKER_PLATFORM ?= linux/amd64

.PHONY: summary-storage-reopen-pair bench-storage-reopen-pair inspect-storage-reopen-pair bench-storage-growth summary-storage-growth probe-storage-resident-pressure bench-storage-resident-pressure diagnose-storage-aborts summary-storage-memory-ceilings bench-storage-memory-ceilings summary-storage-resources bench-storage-fresh-reopen bench-storage-file-cache bench-storage-deployment bench-storage-lifetimes bench-storage-allocations bench-storage-resources bench-storage summary-storage-benchmark bench-pvm fuzz-pvm-program summary-pvm-benchmark summary-pvm-reference check-pvm-reference ui-minifier build-info browser-tools check-ui web-toolchain ui-assets check-telemetry-interop-ci telemetry-interop-collector check-telemetry-interop telemetry-interop-python build setup sources host-tools toolchain rust-tools clean check test check-inventory check-python check-modules check-unit check-failures check-guards check-e2e unit modules runtime format format-check summary-unit summary-failures summary-runtime summary-modules summary-python summary-guards summary-e2e help

# Build the authenticated proof peer with both maintained features after provisioning dependencies.
build: setup
	$(PYTHON) tools/build.py

# Package only after Make has provisioned and compiled the production peer on this pinned host.
.PHONY: package-binary
package-binary: export BINARY_PACKAGE = 1
package-binary: build
	$(PYTHON) tools/package_binary.py

# Docker owns an isolated setup/build; do not provision host compilers or reuse host artifacts.
.PHONY: docker-build check-docker
docker-build:
	mkdir -p build/ci
	$(DOCKER) build --platform "$(DOCKER_PLATFORM)" --tag "$(DOCKER_IMAGE)" . 2>&1 | tee build/ci/docker-build.log

# Exercise the packaged ABI closure and checked peer selftests as its non-root runtime user.
check-docker: docker-build
	@for option in --version --help --selftest --integration-selftest; do \
	  $(DOCKER) run --rm --network none "$(DOCKER_IMAGE)" "$$option"; \
	done 2>&1 | tee build/ci/docker-smoke.log

# Every native build/test target owns its source and pinned Rust/Cargo preparation.
setup: check-inventory toolchain model-tools sources rust-tools ui-assets build-info
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml

# Refresh source/release metadata even when all native dependencies are already provisioned.
build-info: compiler-tools
	$(PYTHON) tools/build_info.py

# Build the missing JS tool at the exact backend revision recorded by the compiler.
web-toolchain: compiler-tools
	@if ! command -v cc >/dev/null 2>&1; then $(MAKE) host-tools; fi
	$(PYTHON) tools/setup_web.py

# Browser automation is test-only; reuse installed Chrome or provision pinned Chromium.
browser-tools: web-toolchain $(if $(filter 1,$(UI_MINIFY)),ui-minifier)
	$(PYTHON) tools/setup_browser.py
	$(PYTHON) tools/build_ui.py --rpc-test

# Focused real-browser verification reuses the owning RPC E2E workload and peer build.
check-ui: build browser-tools
	$(PYTHON) tools/test_ui_browser.py

# Provision one checksum-pinned native executable only when minification is requested.
ui-minifier:
	$(PYTHON) tools/setup_minifier.py

# Stage static build output and embed every asset into a generated compile-time manifest.
ui-assets: web-toolchain $(if $(filter 1,$(UI_MINIFY)),ui-minifier)
	$(PYTHON) tools/build_ui.py

# Formatting needs pinned Rust/rustfmt, but no dependency downloads or native library builds.
rust-tools:
	rustup toolchain install "$(RUSTUP_TOOLCHAIN)" --profile minimal --component rustfmt --no-self-update

# Check out clean static source submodules at recorded pins, including after parent updates; never overwrite edits.
# Python provenance/reference tests need these sources, but no native toolchain or bridge builds.
sources:
	mkdir -p build/ci
	$(PYTHON) tools/setup_submodules.py 2>&1 | tee build/ci/sources.log

# Ubuntu installs missing prerequisites with bounded network waits and retained pre-toolchain logs.
host-tools:
	@if [ "$$(uname -s)" = Linux ] && command -v apt-get >/dev/null; then \
	  packages='build-essential clang lld cmake zlib1g-dev openssl'; missing=0; \
	  if [ "$(BINARY_PACKAGE)" = 1 ]; then packages="$$packages patchelf"; fi; \
	  if [ "$(STORAGE_ABORT_DIAGNOSTICS)" = 1 ]; then packages="$$packages lldb"; fi; \
	  for package in $$packages; do \
	    if [ "$$(dpkg-query -W -f='$${Status}' "$$package" 2>/dev/null || true)" != 'install ok installed' ]; then missing=1; fi; \
	  done; \
	  if [ "$$missing" = 1 ]; then \
	    mkdir -p build/ci; \
	    apt_options='-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o DPkg::Lock::Timeout=60'; \
	    apt_source_args=(); \
	    if [ "$(STORAGE_PRESSURE_HTTPS)" = 1 ]; then \
	      $(PYTHON) tools/storage_pressure_apt.py; \
	      if [ -f build/ci/storage-pressure-https.list ]; then \
	        apt_source_args=(-o "Dir::Etc::sourcelist=$(CURDIR)/build/ci/storage-pressure-https.list" -o Dir::Etc::sourceparts=-); \
	      fi; \
	    fi; \
	    sudo timeout --kill-after=10s 300s apt-get $$apt_options $${apt_source_args[@]+"$${apt_source_args[@]}"} -o APT::Update::Error-Mode=any update 2>&1 | tee build/ci/host-tools-update.log; \
	    sudo apt-get $$apt_options $${apt_source_args[@]+"$${apt_source_args[@]}"} install --no-install-recommends -y $$packages 2>&1 | tee build/ci/host-tools-install.log; \
	  fi; \
	fi

# Create diagnostics before opening logs, including on the very first invocation after clean.
toolchain: host-tools compiler-tools

# Semantic checks and formatting need the pinned tools, not C/link/runtime dependency installation.
.PHONY: compiler-tools
compiler-tools:
	mkdir -p build/ci
	$(PYTHON) tools/setup_nimony.py --ensure 2>&1 | tee build/ci/setup.log

# Verification-only tools use separate pins and never replace the application compiler.
.PHONY: model-tools check-models summary-models
model-tools: toolchain
	$(PYTHON) tools/setup_tlanif.py 2>&1 | tee build/ci/model-tools.log

# Lifecycle model verification owns an independent local/CI gate.
check-models: check-inventory model-tools
	$(PYTHON) tools/test_models.py 2>&1 | tee build/ci/models.log

# Remove all generated artifacts, including the local compiler and downloaded archives.
clean:
	rm -rf -- build

# Local complete verification runs the same independent groups scheduled concurrently by CI.
check: check-models check-python check-modules check-unit check-failures check-guards check-e2e
test: check

# The source-only gate needs only the compiler; runtime checks provision all native dependencies.
modules: check-modules
check-modules: check-inventory compiler-tools ui-assets build-info
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_modules.py --compiler "$$NIMONY" 2>&1 | tee build/ci/modules.log
runtime: check-unit
check-unit: setup format-check
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_runtime.py --compiler "$$NIMONY" 2>&1 | tee build/ci/runtime.log

# Fast PR gate checks all formatting and every production source with an unoptimized semantic profile.
.PHONY: check-smoke
check-smoke: check-inventory format-check ui-assets build-info
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_modules.py --compiler "$$NIMONY" --smoke --output build/tests/smoke 2>&1 | tee build/ci/smoke.log

# Optional differential verification owns Rust setup; ordinary native tests retain frozen inputs.
check-pvm-reference: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/reference/polkavm_memory/Cargo.toml
	$(PYTHON) tools/pvm_reference.py

# Speed baselines are opt-in, validated before timing and separate from correctness verification.
bench-pvm: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fmt --manifest-path tests/performance/polkavm/Cargo.toml -- --check
	$(PYTHON) tools/pvm_benchmark.py

# Frozen real guest; normal setup installs no historical guest compiler or experimental backend.
.PHONY: bench-pvm-sieve
bench-pvm-sieve: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fmt --manifest-path tests/performance/polkavm/Cargo.toml -- --check
	$(PYTHON) tools/pvm_sieve_benchmark.py

# Broader frozen real guests share strict full-state interpreted controls; historical guest compilers stay unused.
.PHONY: bench-pvm-guests
bench-pvm-guests: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fmt --manifest-path tests/performance/polkavm/Cargo.toml -- --check
	$(PYTHON) tools/pvm_guest_benchmark.py

# Paired local revisions share one current driver and frozen full-state interpreted inputs.
.PHONY: compare-pvm-guests
compare-pvm-guests: export RAGNAROK_PVM_COMPARE_BASE = $(PVM_COMPARE_BASE)
compare-pvm-guests: export RAGNAROK_PVM_COMPARE_SCOPE = $(PVM_COMPARE_SCOPE)
compare-pvm-guests: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml
	$(PYTHON) tools/pvm_guest_compare.py

# Native host byte-range API throughput is separate from interpreter backend comparisons.
.PHONY: bench-pvm-memory
bench-pvm-memory: setup
	$(PYTHON) tools/pvm_memory_benchmark.py

# Exact-start public pricing cost includes invalid-start controls and cold/warm samples.
.PHONY: bench-pvm-pricing
bench-pvm-pricing: setup
	$(PYTHON) tools/pvm_pricing_benchmark.py

# Calibrated optional AddressSanitizer qualification reuses frozen native corpus contracts.
.PHONY: check-pvm-asan
check-pvm-asan: setup
	$(PYTHON) tools/pvm_sanitizers.py

# Diagnostic opcode/pair counts use ignored snapshots and discard all instrumented timings.
.PHONY: census-pvm
census-pvm: setup
	$(PYTHON) tools/pvm_opcode_census.py

# Maintained real guests share calibrated counters and full-state interpreted inputs; timings are discarded.
.PHONY: census-pvm-guests
census-pvm-guests: setup
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml
	$(PYTHON) tools/pvm_guest_census.py

# Coverage-guided byte fuzzing owns its native adapter, finite controls and retained corpus; it never runs from ordinary unit or E2E checks.
fuzz-pvm-program: toolchain check-inventory
	$(PYTHON) tools/fuzz_pvm_program.py

# Upstream owns its separate pinned fuzz nightly; ordinary runtime builds never depend on it.
.PHONY: fuzz-pvm-upstream upstream-fuzz-tools
upstream-fuzz-tools: sources
	rustup toolchain install nightly-2025-03-29 --profile minimal

fuzz-pvm-upstream: toolchain rust-tools upstream-fuzz-tools check-inventory
	rustup run "$(RUSTUP_TOOLCHAIN)" rustfmt --edition 2021 --check tests/fuzz/pvm_upstream_bridge.rs.inc
	$(PYTHON) tools/fuzz_pvm_upstream.py

# Runtime contract/crash probes retain strict diagnostics without delaying ordinary unit/corpus checks.
check-failures: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_runtime.py --compiler "$$NIMONY" --group failures 2>&1 | tee build/ci/failures.log

# Compiler rejection checks retain their own logs/caches and do not execute the unit/corpus workload.
check-guards: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_guards.py --compiler "$$NIMONY" 2>&1 | tee build/ci/guards.log

# Inventory validation runs before provisioning and is independently usable on a fresh checkout.
check-inventory:
	$(PYTHON) tools/check_inventory.py

# Independent Python discovery and long-running networking are selectable without the other workloads.
check-python: check-inventory sources
	$(PYTHON) tools/setup_submodules.py --prefetch-blobs vendor/jamtestvectors 2>&1 | tee build/ci/python-sources.log
	$(PYTHON) tools/test_python.py 2>&1 | tee build/ci/python.log
check-e2e: setup browser-tools
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_e2e.py --compiler "$$NIMONY" 2>&1 | tee build/ci/e2e.log

# CI builds the pristine gitlink with the shared Rust pin and keeps Cargo output under build/.
telemetry-interop-collector: host-tools rust-tools
	mkdir -p build/ci
	$(PYTHON) tools/setup_submodules.py vendor/jamtart 2>&1 | tee build/ci/telemetry-interop-sources.log
	cargo build --locked --no-default-features --bin tart-backend --manifest-path vendor/jamtart/Cargo.toml --target-dir build/jamtart-reference-target 2>&1 | tee build/ci/telemetry-interop-collector.log

# The same reproducible collector gate is available locally and on every PR/master CI run.
check-telemetry-interop-ci: check-inventory telemetry-interop-collector
	$(MAKE) check-telemetry-interop JAMTART="$(CURDIR)/build/jamtart-reference-target/debug/tart-backend" 2>&1 | tee build/ci/telemetry-interop.log

# An explicit external collector is an optional interoperability gate, outside the self-contained CI groups.
telemetry-interop-python:
	@test -n "$(JAMTART)" || { echo 'Set JAMTART to an explicitly built tart-backend binary'; exit 1; }
	$(PYTHON) -m venv build/telemetry-interop-python
	build/telemetry-interop-python/bin/python -m pip install --disable-pip-version-check --only-binary=:all: --require-hashes -r tools/telemetry-interop-requirements.txt
check-telemetry-interop: check-inventory telemetry-interop-python build
	build/telemetry-interop-python/bin/python tools/test_telemetry_interop.py --collector "$(JAMTART)"

# Fixture preparation, exact linking profiles and ARC observations belong to the native runner.
unit: setup
	@if [ -n "$$SUITE" ]; then \
	  $(PYTHON) tools/native_tests.py --suite "$$SUITE"; \
	else \
	  $(PYTHON) tools/native_tests.py; \
	fi

# Apply both pinned language formatters; check mode must leave source files untouched.
format: compiler-tools rust-tools
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py
# Storage measures matching public operations; Make provisions the checked native crypto toolchain first.
# Separate whole-process resource observations never contribute speed samples to Perf Storage.
probe-storage-resident-pressure:
	$(PYTHON) tools/storage_resident_pressure.py --probe

bench-storage-resident-pressure: STORAGE_PRESSURE_HTTPS = 1
bench-storage-resident-pressure: setup
	$(PYTHON) tools/storage_resident_pressure.py

diagnose-storage-aborts: STORAGE_ABORT_DIAGNOSTICS = 1
diagnose-storage-aborts: setup
	$(PYTHON) tools/storage_abort_diagnostics.py

bench-storage-memory-ceilings: setup
	$(PYTHON) tools/storage_memory_ceilings.py

# Reparse an existing pair without opening imported binaries or executing command vectors.
summary-storage-reopen-pair:
	$(PYTHON) tools/paired_storage_reopens.py --validate "$${REOPEN_PAIR_REPORT:?Set REOPEN_PAIR_REPORT}"

# This optional pair uses already-built frozen binaries; rebuilding providers would invalidate them.
bench-storage-reopen-pair:
	$(PYTHON) tools/paired_storage_reopens.py --config "$${REOPEN_PAIR_CONFIG:?Set REOPEN_PAIR_CONFIG}" --output "$${REOPEN_PAIR_OUTPUT:?Set REOPEN_PAIR_OUTPUT}" --execute-local-builds

# Inspect caller-selected frozen local artifacts without rebuilding or executing them.
inspect-storage-reopen-pair:
	$(PYTHON) tools/paired_storage_reopens.py --config "$${REOPEN_PAIR_CONFIG:?Set REOPEN_PAIR_CONFIG}"

bench-storage-fresh-reopen: setup
	$(PYTHON) tools/storage_fresh_reopen.py

bench-storage-file-cache:
	$(PYTHON) tools/storage_file_cache.py

bench-storage-deployment: setup
	$(PYTHON) tools/storage_deployment_benchmark.py

bench-storage-lifetimes: setup
	$(PYTHON) tools/storage_lifetime_benchmark.py

bench-storage-allocations: setup
	$(PYTHON) tools/storage_allocation_benchmark.py

bench-storage-resources: setup
	$(PYTHON) tools/storage_resources.py

# Separate CI owners retain identical matrices while avoiding a serial speed/growth critical path.
bench-storage-growth: setup
	$(PYTHON) tools/storage_benchmark.py --panel growth

bench-storage: setup
	$(PYTHON) tools/storage_benchmark.py --panel comparison

format-check: compiler-tools rust-tools
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py --check

# Summaries can run after a failed job; do not trigger setup or disguise a missing report.
summary-storage-memory-ceilings:
	$(PYTHON) tools/summarize_storage_limits.py --output "$(SUMMARY_OUTPUT)"

summary-storage-resources:
	$(PYTHON) tools/summarize_storage_resources.py --output "$(SUMMARY_OUTPUT)"

# Both scope reports use the same strict setup-free renderer and separate CI artifact owners.
summary-storage-growth:
	mkdir -p build/ci build/tests/storage-growth-benchmark
	$(PYTHON) tools/summarize_tests.py --kind storage-benchmark --report build/tests/storage-growth-benchmark/results.json --output "$(SUMMARY_OUTPUT)" --artifact build/tests/storage-growth-benchmark/summary.md

summary-storage-benchmark:
	mkdir -p build/ci build/tests/storage-benchmark
	$(PYTHON) tools/summarize_tests.py --kind storage-benchmark --report build/tests/storage-benchmark/results.json --output "$(SUMMARY_OUTPUT)" --artifact build/tests/storage-benchmark/summary.md

summary-pvm-benchmark:
	mkdir -p build/ci build/tests/pvm-benchmark
	$(PYTHON) tools/summarize_tests.py --kind pvm-benchmark --report build/tests/pvm-benchmark/results.json --output "$(SUMMARY_OUTPUT)" --artifact build/tests/pvm-benchmark/summary.md

summary-pvm-reference:
	mkdir -p build/ci build/tests/pvm-reference
	$(PYTHON) tools/summarize_tests.py --kind pvm-reference --report build/tests/pvm-reference/results.json --output "$(SUMMARY_OUTPUT)" --artifact build/tests/pvm-reference/summary.md

summary-runtime: summary-unit
summary-unit:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind runtime --report build/tests/runtime/results.json --output "$(SUMMARY_OUTPUT)"
summary-models:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind models --report build/tests/models/results.json --output "$(SUMMARY_OUTPUT)"

summary-modules:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind modules --report build/tests/modules/results.json --output "$(SUMMARY_OUTPUT)"

summary-failures:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind failures --report build/tests/failures/results.json --output "$(SUMMARY_OUTPUT)"

summary-guards:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind guards --report build/tests/guards/results.json --output "$(SUMMARY_OUTPUT)"

summary-python:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind python --report build/tests/python/results.json --output "$(SUMMARY_OUTPUT)"
summary-e2e:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind e2e --report build/tests/e2e/results.json --output "$(SUMMARY_OUTPUT)"

# List public commands without provisioning or building anything.
help:
	@printf '%s\n' 'make / make build  Provision dependencies and build build/ragnarok' \
	  'make setup         Provision pinned toolchains, submodules and Cargo dependencies' \
	  'make check-smoke   Check all formatting and semantically compile every production module' \
	  'make package-binary  Build and smoke-test a relocatable native archive in build/dist/' \
	  'make docker-build  Build the Linux amd64 runtime image (DOCKER_IMAGE=ragnarok:local)' \
	  'make check-docker  Build and smoke-test the image locally; never publish it' \
	  'make ui-assets     Stage/embed UI assets (UI_MINIFY=1 minifies JS/CSS; default in CI)' \
	  'make check-ui      Run the compiled UI against production WebSocket RPC in a browser' \
	  'make clean         Remove build/ completely' \
	  'make check / test  Provision dependencies and run complete verification' \
	  'make unit          Run Hastur application suites (COMPILE_CHECK_JOBS=1..4; default 4)' \
	  'make unit SUITE=natural  Run one native suite; full output stays under build/tests/native/selected/' \
	  'make check-modules Check every production module' \
	  'make check-inventory  Validate local registries without native setup' \
	  'make fuzz-pvm-program  Run bounded sanitized program fuzzing (FUZZ_RUNS=16..1000000)' \
	  'make fuzz-pvm-upstream  Run pinned upstream campaigns and JAM interpreter comparisons' \
	  'make bench-storage  Compare validated memory, journal and managed storage' \
	  'make bench-storage-growth  Measure sustained storage growth and SDK IO' \
	  'make bench-pvm      Measure validated PVM workloads against PolkaVM backends' \
	  'make bench-pvm-guests  Compare frozen checked indirect-call and memory-fill guests' \
	  'make check-pvm-reference  Run pinned PolkaVM probes and matching native suites' \
	  'make model-tools   Build the pinned verification-only tlanif' \
	  'make check-models  Check bounded models, mutants and reachability' \
	  'make check-python  Run Python reference/tooling/provenance tests' \
	  'make check-unit    Run native suites and independent corpora' \
	  'make check-failures Run runtime contract/crash probes and positive controls' \
	  'make check-guards  Run compiler rejection guards' \
	  'make check-e2e     Run peer/service/resilience/soak/offload scenarios' \
	  'make check-telemetry-interop-ci  Build the pinned collector and check interoperability' \
	  'make check-telemetry-interop JAMTART=/path/to/tart-backend  Check an actual collector' \
	  'make runtime       Alias for make check-unit' \
	  'make format        Apply pinned Nim and Rust formatters' \
	  'make format-check  Verify Nim and Rust formatting'

# Repeat fixed crypto-work/live-memory observations; an optional baseline is supplied via the environment.
.PHONY: measure-state-store
measure-state-store: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/measure_state_store.py --compiler "$$NIMONY"

# Repeat real-file state workloads; compare only an explicitly supplied compatible prior report.
.PHONY: measure-disk-store
measure-disk-store: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/measure_disk_store.py --compiler "$$NIMONY" $(if $(DISK_STORE_BASELINE),--baseline "$(DISK_STORE_BASELINE)",)
