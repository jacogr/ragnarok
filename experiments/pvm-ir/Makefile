# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Opt-in experiment; never part of production builds or the ordinary test registry.

.PHONY: bench loop format format-check

bench:
	python3 run.py

loop:
	python3 run_loop.py

format:
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 probe.nim
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 loop_probe.nim

format-check:
	mkdir -p ../../build/pvm-ir-experiment
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < probe.nim > ../../build/pvm-ir-experiment/formatted.nim
	cmp probe.nim ../../build/pvm-ir-experiment/formatted.nim
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < loop_probe.nim > ../../build/pvm-ir-experiment/formatted-loop.nim
	cmp loop_probe.nim ../../build/pvm-ir-experiment/formatted-loop.nim
