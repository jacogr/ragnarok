# Keep Make a command front end; Python owns pinned setup, compilation and verification.
.DEFAULT_GOAL := build
# Native preparations and tests share build directories; do not run top-level targets concurrently.
.NOTPARALLEL:
PYTHON ?= python3
export PYTHONDONTWRITEBYTECODE := 1
# Select the same Rust version as the primitive bridge rather than a user's global default.
export RUSTUP_TOOLCHAIN := $(shell $(PYTHON) -c 'import json; print(json.load(open("spec/bandersnatch-pins.json"))["rust"])')

.PHONY: build setup toolchain check test unit modules runtime format format-check help

# Build the current authenticated proof peer with integration and bounded offload enabled.
build: toolchain
	$(PYTHON) tools/build.py

# Provision pinned project tools/sources and locked registry dependencies; host packages are prerequisites.
setup: toolchain
	$(PYTHON) tools/setup_submodules.py
	rustup toolchain install "$(RUSTUP_TOOLCHAIN)" --profile minimal --component rustfmt --no-self-update
	rustup run "$(RUSTUP_TOOLCHAIN)" cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml

# Verify existing binaries/pins and install only if absent, changed or damaged.
toolchain:
	$(PYTHON) tools/setup_nimony.py --ensure

# Both names run exactly the canonical complete verification, including strict negative/process checks.
check: toolchain
	$(PYTHON) tools/test.py
# Requesting both names in one invocation still executes the full check only once.
test: check

# These bounded selections use the same command plan as complete local verification and CI.
unit: toolchain
	$(PYTHON) tools/test.py --suite unit
modules: toolchain
	$(PYTHON) tools/test.py --suite modules
runtime: toolchain
	$(PYTHON) tools/test.py --suite runtime

# Source only the managed environment so a global Nim/formatter cannot change the selected version.
format: toolchain
	. ./build/toolchain/env.sh && $(PYTHON) tools/format.py
format-check: toolchain
	. ./build/toolchain/env.sh && $(PYTHON) tools/format.py --check

# Show the public entry points without provisioning or building anything.
help:
	@printf '%s\n' 'make / make build  Build build/ragnarok (current proof peer)' \
	  'make setup         Provision pinned toolchains, submodules and Cargo dependencies' \
	  'make check / test  Run complete verification' \
	  'make unit          Run the 59 Hastur application suites' \
	  'make modules       Check every production module' \
	  'make runtime       Run codec/crypto/networking and independent checks' \
	  'make format        Apply the pinned formatter' \
	  'make format-check  Verify formatting'
