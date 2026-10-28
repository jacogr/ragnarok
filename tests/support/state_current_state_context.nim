# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit policies and actual producer constructors for supplied-current consumers.
import ./state_current_checkpoint_context
import ./state_current_typed_context
import ./state_accumulation_current_chain_context
import ./state_inventory_context
import ../../src/state/current_state as state_current_state
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_profile as state_current_profile
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_composition as codec_state_composition
proc currentQualifiedState*(source: PreparedCurrentChainUpdate): CurrentStateSerialization =
  ## Supply authored declarations and verify every key/value against this original genuine successor.
  let profile = captureCurrentProfile(source, CurrentProfileLimits(validators: ElementLimit(1024),
      bytes: ByteLimit(65536))).value
  let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
      items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
  qualifyCurrentState(globals, currentSuppliedServices(source.currentUpdateState),
      inventoryCaptureLimits).value
