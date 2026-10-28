# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent creation observations cannot reveal payloads from default contexts.
import std/cmdline
import ../../src/state/accumulation_effects as state_accumulation_effects
let owner = default(AccumulationEffectContext)
if paramStr(1) == "count":
  discard owner.effectCreatedAccountFactCount.value # No false initialized empty history.
else:
  discard owner.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(0)).value # No false creation identity.
