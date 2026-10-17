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

.PHONY: build setup host-tools toolchain clean check test unit modules runtime format format-check summary-runtime summary-modules help

# Build the authenticated proof peer with both maintained features after provisioning dependencies.
build: setup
	$(PYTHON) tools/build.py

# Every native build/test target owns its source and pinned Rust/Cargo preparation.
setup: toolchain
	$(PYTHON) tools/setup_submodules.py
	rustup toolchain install "$(RUSTUP_TOOLCHAIN)" --profile minimal --component rustfmt --no-self-update
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml

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

# Local complete verification combines the same two targets used by independent CI jobs.
check: modules runtime
test: check

# The source-only gate needs only the compiler; runtime checks provision all native dependencies.
modules: toolchain
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_modules.py --compiler "$$NIMONY" 2>&1 | tee build/ci/modules.log
runtime: setup format-check
	. ./build/toolchain/env.sh; $(PYTHON) tools/test_runtime.py --compiler "$$NIMONY" 2>&1 | tee build/ci/runtime.log

# Fixture preparation, exact linking profiles and ARC observations belong to the native runner.
unit: setup
	$(PYTHON) tools/native_tests.py

# Use only the managed formatter; no shell activation or globally installed Nim is required.
format: toolchain
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py
format-check: toolchain
	. ./build/toolchain/env.sh; $(PYTHON) tools/format.py --check

# Summaries can run after a failed job; do not trigger setup or disguise a missing report.
summary-runtime:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind runtime --report build/tests/runtime/results.json --output "$(SUMMARY_OUTPUT)"
summary-modules:
	mkdir -p build/ci
	$(PYTHON) tools/summarize_tests.py --kind modules --report build/tests/modules/results.json --output "$(SUMMARY_OUTPUT)"

# List public commands without provisioning or building anything.
help:
	@printf '%s\n' 'make / make build  Provision dependencies and build build/ragnarok' \
	  'make setup         Provision pinned toolchains, submodules and Cargo dependencies' \
	  'make clean         Remove build/ completely' \
	  'make check / test  Provision dependencies and run complete verification' \
	  'make unit          Run the 59 Hastur application suites (COMPILE_CHECK_JOBS=1..4; default 4)' \
	  'make modules       Check every production module' \
	  'make runtime       Run codec/crypto/networking and independent checks' \
	  'make format        Apply the pinned formatter' \
	  'make format-check  Verify formatting'
