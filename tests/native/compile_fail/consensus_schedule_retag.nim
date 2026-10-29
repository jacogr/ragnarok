# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate chapter results or expose/retag private parent/schedule
## storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "mode"}

import ../../../src/codec/state/[consensus as state_consensus, safrole as state_safrole,
    trie as state_trie]
var value = default(SealerSchedule)
value.mode = SealerKind.Keys
