# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Opt-in experiment; never part of production builds or the ordinary test registry.

.PHONY: bench loop effects effects-asan sieve sieve-build sieve-measure format format-check

bench:
	python3 run.py

loop:
	python3 run_loop.py

effects:
	python3 run_effects.py

effects-asan:
	python3 check_effects_asan.py

sieve:
	python3 run_sieve.py

sieve-build:
	python3 run_sieve.py --build-only

sieve-measure:
	python3 run_sieve.py --measure-only

format:
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 probe.nim
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 loop_probe.nim

	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 effect_probe.nim
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 shared_api.nim.inc

	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 sieve_probe.nim
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 sieve/binding.nim.inc
	rustup run 1.99.0 rustfmt --edition 2021 sieve/host.rs

format-check:
	mkdir -p ../../build/pvm-ir-experiment
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < probe.nim > ../../build/pvm-ir-experiment/formatted.nim
	cmp probe.nim ../../build/pvm-ir-experiment/formatted.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < loop_probe.nim > ../../build/pvm-ir-experiment/formatted-loop.nim
	cmp loop_probe.nim ../../build/pvm-ir-experiment/formatted-loop.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < effect_probe.nim > ../../build/pvm-ir-experiment/formatted-effects.nim
	cmp effect_probe.nim ../../build/pvm-ir-experiment/formatted-effects.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < shared_api.nim.inc > ../../build/pvm-ir-experiment/formatted-api.nim
	cmp shared_api.nim.inc ../../build/pvm-ir-experiment/formatted-api.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < sieve_probe.nim > ../../build/pvm-ir-experiment/formatted-sieve.nim
	cmp sieve_probe.nim ../../build/pvm-ir-experiment/formatted-sieve.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < sieve/binding.nim.inc > ../../build/pvm-ir-experiment/formatted-binding.nim
	cmp sieve/binding.nim.inc ../../build/pvm-ir-experiment/formatted-binding.nim
	rustup run 1.99.0 rustfmt --edition 2021 --check sieve/host.rs
