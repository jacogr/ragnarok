# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-3 results, owners or peak
## alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "isPresent"}

import ../../../src/codec/state/[history as state_history, trie as state_trie]
discard HistoryPeak(isPresent: true)
