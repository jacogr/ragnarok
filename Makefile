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
SUMMARY_OUTPUT ?= build/ci/summary.md

.PHONY: build setup sources host-tools toolchain rust-tools clean check test check-python check-modules check-unit check-failures check-guards check-e2e unit modules runtime format format-check summary-unit summary-failures summary-runtime summary-modules summary-python summary-guards summary-e2e help

# Build the authenticated proof peer with both maintained features after provisioning dependencies.
build: setup
	$(PYTHON) tools/build.py

# Every native build/test target owns its source and pinned Rust/Cargo preparation.
setup: toolchain sources rust-tools
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml

# Formatting needs pinned Rust/rustfmt, but no dependency downloads or native library builds.
rust-tools:
	rustup toolchain install "$(RUSTUP_TOOLCHAIN)" --profile minimal --component rustfmt --no-self-update

# Python provenance/reference tests need pinned sources, but no native toolchain or bridge builds.
sources:
	mkdir -p build/ci
	$(PYTHON) tools/setup_submodules.py 2>&1 | tee build/ci/sources.log

# Ubuntu installs missing native prerequisites here, so CI needs no separate package/bootstrap recipe.
host-tools:
	@if [ "$$(uname -s)" = Linux ] && command -v apt-get >/dev/null; then \
	  packages='build-essential clang lld cmake zlib1g-dev openssl'; missing=0; \
	  for package in $$packages; do \
	    if [ "$$(dpkg-query -W -f='$${Status}' "$$package" 2>/dev/null || true)" != 'install ok installed' ]; then missing=1; fi; \
	  done; \
	  if [ "$$missing" = 1 ]; then \
	    sudo apt-get update; \
	    sudo apt-get install --no-install-recommends -y $$packages; \
	  fi; \
	fi

# Create diagnostics before opening logs, including on the very first invocation after clean.
toolchain: host-tools
	mkdir -p build/ci
	$(PYTHON) tools/setup_nimony.py --ensure 2>&1 | tee build/ci/setup.log

# Remove all generated artifacts, including the local compiler and downloaded archives.
clean:
	rm -rf -- build

# Local complete verification runs the same six independent groups scheduled concurrently by CI.
check: check-python check-modules check-unit check-failures check-guards check-e2e
test: check

# The source-only gate needs only the compiler; runtime checks provision all native dependencies.
modules: check-modules
check-modules: toolchain
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_modules.py --compiler "$$NIMONY" 2>&1 | tee build/ci/modules.log
runtime: check-unit
check-unit: setup format-check
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_runtime.py --compiler "$$NIMONY" 2>&1 | tee build/ci/runtime.log

# Runtime contract/crash probes retain strict diagnostics without delaying ordinary unit/corpus checks.
check-failures: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_runtime.py --compiler "$$NIMONY" --group failures 2>&1 | tee build/ci/failures.log

# Compiler rejection checks retain their own logs/caches and do not execute the unit/corpus workload.
check-guards: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_guards.py --compiler "$$NIMONY" 2>&1 | tee build/ci/guards.log

# Independent Python discovery and long-running networking are selectable without the other workloads.
check-python: sources
	$(PYTHON) tools/test_python.py 2>&1 | tee build/ci/python.log
check-e2e: setup
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_e2e.py --compiler "$$NIMONY" 2>&1 | tee build/ci/e2e.log

# Fixture preparation, exact linking profiles and ARC observations belong to the native runner.
unit: setup
	$(PYTHON) tools/native_tests.py

# Apply both pinned language formatters; check mode must leave source files untouched.
format: toolchain rust-tools
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py
format-check: toolchain rust-tools
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py --check

# Summaries can run after a failed job; do not trigger setup or disguise a missing report.
summary-runtime: summary-unit
summary-unit:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind runtime --report build/tests/runtime/results.json --output "$(SUMMARY_OUTPUT)"
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
	  'make clean         Remove build/ completely' \
	  'make check / test  Provision dependencies and run complete verification' \
	  'make unit          Run Hastur application suites (COMPILE_CHECK_JOBS=1..4; default 4)' \
	  'make check-modules Check every production module' \
	  'make check-python  Run Python reference/tooling/provenance tests' \
	  'make check-unit    Run native suites and independent corpora' \
	  'make check-failures Run runtime contract/crash probes and positive controls' \
	  'make check-guards  Run compiler rejection guards' \
	  'make check-e2e     Run peer/service/resilience/soak/offload scenarios' \
	  'make runtime       Alias for make check-unit' \
	  'make format        Apply pinned Nim and Rust formatters' \
	  'make format-check  Verify Nim and Rust formatting'
