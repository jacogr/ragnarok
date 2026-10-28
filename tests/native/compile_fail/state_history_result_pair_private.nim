# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-3 results, owners or peak
## alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_history as codec_state_history
import ../../../src/codec/state_trie as codec_state_trie
let value = default(HistoryResult[ReportedPackage])
discard value.completed
