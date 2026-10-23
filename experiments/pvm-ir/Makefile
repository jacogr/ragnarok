# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Opt-in experiment; never part of production builds or the ordinary test registry.

.PHONY: bench format format-check

bench:
	python3 run.py

format:
	"$(NIMPRETTY)" --indent:2 --maxLineLen:100 probe.nim

format-check:
	mkdir -p ../../build/pvm-ir-experiment
	"$(NIMPRETTY)" --stdin --indent:2 --maxLineLen:100 < probe.nim > ../../build/pvm-ir-experiment/formatted.nim
	cmp probe.nim ../../build/pvm-ir-experiment/formatted.nim
