# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A report identity cannot become an offender key despite their identical byte width.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: DisputeHash but wanted: OffenderKey"}

import ../../../src/codec/state_disputes
let hash = default(DisputeHash)
let key: OffenderKey = hash
discard key
